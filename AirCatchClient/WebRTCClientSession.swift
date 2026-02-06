//
//  WebRTCClientSession.swift
//  AirCatchClient
//
//  WebRTC receiver for relay mode (video only). Uses relay for signaling.
//

import Foundation
import WebRTC

final class WebRTCClientSession: NSObject {
    private let queue = DispatchQueue(label: "com.aircatch.webrtc.client")
    private let factory: RTCPeerConnectionFactory
    private let iceServers: [RTCIceServer]
    private var peerConnection: RTCPeerConnection?

    var onSignal: ((WebRTCSignalMessage) -> Void)?
    var onRemoteVideoTrack: ((RTCVideoTrack) -> Void)?
    var onConnectionStateChange: ((RTCPeerConnectionState) -> Void)?
    var onDataReceived: ((Data) -> Void)?

    private var dataChannel: RTCDataChannel?

    var isDataChannelOpen: Bool {
        return dataChannel?.readyState == .open
    }

    init(iceServerURLs: [String]) {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        self.factory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
        self.iceServers = iceServerURLs.map { RTCIceServer(urlStrings: [$0]) }
        super.init()
        RTCInitializeSSL()
        peerConnection = makePeerConnection()
    }

    func sendData(_ data: Data) {
        guard let dataChannel = dataChannel, dataChannel.readyState == .open else { return }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        dataChannel.sendData(buffer)
    }

    func close() {
        queue.async { [weak self] in
            self?.dataChannel?.close()
            self?.dataChannel = nil
            self?.peerConnection?.close()
            self?.peerConnection = nil
        }
    }

    func handleRemoteSignal(_ message: WebRTCSignalMessage) {
        queue.async { [weak self] in
            self?.handleRemoteSignalInternal(message)
        }
    }

    // MARK: - Private

    private func handleRemoteSignalInternal(_ message: WebRTCSignalMessage) {
        guard let peerConnection = ensurePeerConnection() else { return }
        switch message.type {
        case .offer:
            guard let sdp = message.sdp else { return }
            let description = RTCSessionDescription(type: .offer, sdp: sdp)
            peerConnection.setRemoteDescription(description) { [weak self] error in
                guard let self, error == nil else { return }
                let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                peerConnection.answer(for: constraints) { [weak self] answer, error in
                    guard let self, let answer, error == nil else { return }
                    peerConnection.setLocalDescription(answer) { [weak self] error in
                        guard let self, error == nil else { return }
                        let response = WebRTCSignalMessage(type: .answer, sdp: answer.sdp)
                        self.onSignal?(response)
                    }
                }
            }
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
        return factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClientSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.videoTracks.first {
            onRemoteVideoTrack?(track)
        }
    }

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

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        AirCatchLog.info("WebRTC Data Channel opened: \(dataChannel.label)")
        self.dataChannel = dataChannel
        dataChannel.delegate = self
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onConnectionStateChange?(newState)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection,
                        didAdd rtpReceiver: RTCRtpReceiver,
                        streams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            onRemoteVideoTrack?(track)
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCClientSession: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        AirCatchLog.info("WebRTC Data Channel state: \(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        onDataReceived?(buffer.data)
    }
}
