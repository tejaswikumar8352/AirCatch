//
//  WebRTCHostSession.swift
//  AirCatchHost
//
//  WebRTC sender for relay mode (video only). Uses relay for signaling.
//

import Foundation
import WebRTC
import CoreMedia

final class WebRTCHostSession: NSObject {
    private let queue = DispatchQueue(label: "com.aircatch.webrtc.host")
    private let factory: RTCPeerConnectionFactory
    private let videoSource: RTCVideoSource
    private let videoTrack: RTCVideoTrack
    private let capturer: ExternalVideoCapturer
    private let iceServers: [RTCIceServer]
    private var peerConnection: RTCPeerConnection?
    private var videoSender: RTCRtpSender?
    private var targetMaxBitrateBps: Int = AirCatchConfig.webrtcMaxBitrate
    private var targetMinBitrateBps: Int = AirCatchConfig.webrtcMinBitrate
    private var targetMaxFramerate: Int = AirCatchConfig.webrtcMaxFrameRate
    private var targetScaleDown: Double = 1.0
    private var degradationPreference: RTCDegradationPreference = .maintainResolution

    var onSignal: ((WebRTCSignalMessage) -> Void)?
    var onConnectionStateChange: ((RTCPeerConnectionState) -> Void)?
    var onDataReceived: ((Data) -> Void)?
    
    private var dataChannel: RTCDataChannel?

    var isDataChannelOpen: Bool {
        return dataChannel?.readyState == .open
    }

    func sendData(_ data: Data) {
        guard let dataChannel = dataChannel, dataChannel.readyState == .open else { return }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        dataChannel.sendData(buffer)
    }

    init(iceServerURLs: [String]) {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        if let h264 = RTCDefaultVideoEncoderFactory.supportedCodecs()
            .first(where: { $0.name == kRTCVideoCodecH264Name }) {
            encoderFactory.preferredCodec = h264
        }
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        self.videoSource = factory.videoSource()
        self.videoTrack = factory.videoTrack(with: videoSource, trackId: "aircatch_video")
        self.capturer = ExternalVideoCapturer()
        self.iceServers = iceServerURLs.map { RTCIceServer(urlStrings: [$0]) }
        super.init()
        RTCInitializeSSL()
        capturer.delegate = videoSource
        peerConnection = makePeerConnection()
    }

    func start() {
        queue.async { [weak self] in
            self?.startInternal()
        }
    }

    func close() {
        queue.async { [weak self] in
            self?.peerConnection?.close()
            self?.peerConnection = nil
        }
    }

    func handleRemoteSignal(_ message: WebRTCSignalMessage) {
        queue.async { [weak self] in
            self?.handleRemoteSignalInternal(message)
        }
    }

    func sendFrame(pixelBuffer: CVPixelBuffer, time: CMTime) {
        queue.async { [weak self] in
            guard let self, self.peerConnection != nil else { return }
            let timestampNs = Self.timestampNs(from: time)
            self.capturer.capture(pixelBuffer: pixelBuffer, timeStampNs: timestampNs)
        }
    }

    func updateVideoFormat(width: Int, height: Int, fps: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            let cappedFps = max(1, min(fps, AirCatchConfig.webrtcMaxFrameRate))
            self.videoSource.adaptOutputFormat(
                toWidth: Int32(max(2, width)),
                height: Int32(max(2, height)),
                fps: Int32(cappedFps)
            )
            self.targetMaxFramerate = cappedFps
            self.applySenderParameters()
        }
    }

    func setEncodingConstraints(maxBitrateBps: Int, minBitrateBps: Int, maxFramerate: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            self.targetMaxBitrateBps = max(100_000, maxBitrateBps)
            self.targetMinBitrateBps = max(100_000, minBitrateBps)
            self.targetMaxFramerate = max(1, maxFramerate)
            self.applySenderParameters()
        }
    }

    // MARK: - Private

    private func startInternal() {
        guard let peerConnection = ensurePeerConnection() else { return }

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self, let sdp, error == nil else { return }
            peerConnection.setLocalDescription(sdp) { [weak self] error in
                guard let self, error == nil else { return }
                let message = WebRTCSignalMessage(type: .offer, sdp: sdp.sdp)
                self.onSignal?(message)
            }
        }
    }

    private func handleRemoteSignalInternal(_ message: WebRTCSignalMessage) {
        guard let peerConnection = ensurePeerConnection() else { return }
        switch message.type {
        case .answer:
            guard let sdp = message.sdp else { return }
            let description = RTCSessionDescription(type: .answer, sdp: sdp)
            peerConnection.setRemoteDescription(description, completionHandler: { _ in })
        case .candidate:
            guard let candidate = message.candidate else { return }
            let sdpMid = message.sdpMid
            let sdpMLineIndex = message.sdpMLineIndex ?? 0
            let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
            peerConnection.add(iceCandidate, completionHandler: { _ in })
        case .offer:
            // Host is the offerer in this flow; ignore unexpected offers.
            break
        }
    }

    private func ensurePeerConnection() -> RTCPeerConnection? {
        if peerConnection == nil {
            peerConnection = makePeerConnection()
        }
        return peerConnection
    }

    private func makePeerConnection() -> RTCPeerConnection? {
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            return nil
        }
        if let sender = connection.add(videoTrack, streamIds: ["aircatch_stream"]) {
            videoSender = sender
            applySenderParameters()
        }
        
        // Create Data Channel for control events (Client -> Host)
        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        dcConfig.channelId = 0
        if let dc = connection.dataChannel(forLabel: "aircatch-control", configuration: dcConfig) {
            self.dataChannel = dc
            dc.delegate = self
        }
        
        return connection
    }

    private func applySenderParameters() {
        guard let sender = videoSender else { return }
        let parameters = sender.parameters
        let encoding: RTCRtpEncodingParameters
        if let first = parameters.encodings.first {
            encoding = first
        } else {
            encoding = RTCRtpEncodingParameters()
        }

        encoding.maxBitrateBps = NSNumber(value: targetMaxBitrateBps)
        encoding.minBitrateBps = NSNumber(value: targetMinBitrateBps)
        encoding.maxFramerate = NSNumber(value: targetMaxFramerate)
        encoding.scaleResolutionDownBy = NSNumber(value: targetScaleDown)
        encoding.networkPriority = .high
        encoding.bitratePriority = 1.0

        parameters.encodings = [encoding]
        parameters.degradationPreference = NSNumber(value: degradationPreference.rawValue)
        sender.parameters = parameters
    }

    private static func timestampNs(from time: CMTime) -> Int64 {
        let timescale = time.timescale
        guard timescale != 0 else {
            return Int64(Date().timeIntervalSince1970 * 1_000_000_000.0)
        }
        let seconds = Double(time.value) / Double(timescale)
        return Int64(seconds * 1_000_000_000.0)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCHostSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let message = WebRTCSignalMessage(
            type: .candidate,
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        onSignal?(message)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onConnectionStateChange?(newState)
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCHostSession: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        AirCatchLog.info("WebRTC Data Channel state: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        onDataReceived?(buffer.data)
    }
}

// MARK: - External Video Capturer

final class ExternalVideoCapturer: RTCVideoCapturer {
    func capture(pixelBuffer: CVPixelBuffer, timeStampNs: Int64) {
        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timeStampNs)
        delegate?.capturer(self, didCapture: frame)
    }
}
