//
//  ScreenStreamer.swift
//  AirCatchHost
//
//  High-performance screen capture using ScreenCaptureKit with H.264 compression.
//

import Foundation
import ScreenCaptureKit
import VideoToolbox
import CoreMedia
import CoreAudio
import AppKit

/// Captures the screen using ScreenCaptureKit and compresses frames to H.264.
final class ScreenStreamer: NSObject {
    
    // MARK: - Configuration
    
    private var currentPreset: QualityPreset
    private var maxClientWidth: Int?
    private var maxClientHeight: Int?
    private var targetDisplayID: CGDirectDisplayID?

    private(set) var captureWidth: Int = 0
    private(set) var captureHeight: Int = 0
    
    // MARK: - Capture Components
    
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var audioOutput: AudioStreamOutput?
    private var videoQueue: DispatchQueue?
    private var encodeQueue: DispatchQueue?
    
    // MARK: - Compression
    
    private var compressionSession: VTCompressionSession?
    private var frameCallback: ((Data) -> Void)?
    private var audioCallback: ((Data) -> Void)?
    private var cachedSPS: Data?
    private var cachedPPS: Data?
    
    // MARK: - State
    
    private var isRunning = false
    
    init(preset: QualityPreset = .balanced,
         maxClientWidth: Int? = nil,
         maxClientHeight: Int? = nil,
         targetDisplayID: CGDirectDisplayID? = nil,
         onFrame: @escaping (Data) -> Void,
         onAudio: ((Data) -> Void)? = nil) {
        self.currentPreset = preset
        self.maxClientWidth = maxClientWidth
        self.maxClientHeight = maxClientHeight
        self.targetDisplayID = targetDisplayID
        self.frameCallback = onFrame
        self.audioCallback = onAudio
        super.init()
    }
    
    // MARK: - Public API
    
    func start() async throws {
        guard !isRunning else { return }
        
        // 1. Get available content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        
        // 2. Select the requested display (or default)
        let display: SCDisplay?
        if let targetDisplayID {
            display = availableContent.displays.first(where: { $0.displayID == targetDisplayID })
                ?? availableContent.displays.first
        } else {
            display = availableContent.displays.first
        }

        guard let display else {
            throw StreamerError.noDisplayFound
        }
        
        // Use native resolution, optionally clamped to client max size
        let sourceWidth = display.width
        let sourceHeight = display.height
        let (width, height) = scaledDimensionsToFit(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            maxWidth: maxClientWidth,
            maxHeight: maxClientHeight
        )

        captureWidth = width
        captureHeight = height
        
        // 3. Create stream configuration
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(currentPreset.frameRate))
        config.queueDepth = 5 // Allow buffer for compression pipeline
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        if audioCallback != nil {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }
        
        // 4. Create content filter (capture entire display)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        // 5. Setup compression session
        try setupCompressionSession(width: width, height: height)
        
        // 6. Create and start the stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        let queue = DispatchQueue(label: "com.aircatch.videocapture", qos: .userInteractive)
        self.videoQueue = queue  // Keep reference to prevent deallocation
        
        streamOutput = StreamOutput { [weak self] sampleBuffer in
            // Call compressFrame directly - queue is already background
            self?.compressFrame(sampleBuffer)
        }

        try stream.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: queue)

        if audioCallback != nil {
            let audioQueue = DispatchQueue(label: "com.aircatch.audiocapture", qos: .userInteractive)
            audioOutput = AudioStreamOutput { [weak self] sampleBuffer in
                self?.handleAudioSample(sampleBuffer)
            }
            try stream.addStreamOutput(audioOutput!, type: .audio, sampleHandlerQueue: audioQueue)
        }
        
        try await stream.startCapture()
        
        self.stream = stream
        isRunning = true
        
        NSLog("[ScreenStreamer] Started capturing at \(currentPreset.frameRate)fps (\(width)x\(height)) - Preset: \(currentPreset.displayName)")
    }
    
    func stop() {
        guard isRunning else { return }
        
        Task {
            try? await stream?.stopCapture()
        }
        
        stream = nil
        streamOutput = nil
        audioOutput = nil
        
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        isRunning = false
        NSLog("[ScreenStreamer] Stopped")
    }

    // MARK: - Audio

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let audioCallback else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return
        }

        let asbd = asbdPtr.pointee
        let isFloat32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let channels = Int(asbd.mChannelsPerFrame)
        guard isFloat32, channels > 0 else { return }

        var audioBufferList = AudioBufferList(
            mNumberBuffers: 0,
            mBuffers: AudioBuffer(mNumberChannels: 0, mDataByteSize: 0, mData: nil)
        )
        var blockBuffer: CMBlockBuffer?
        var sizeNeeded: Int = 0

        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        // AudioBufferList can be interleaved (1 buffer) or planar (N buffers).
        if audioBufferList.mNumberBuffers == 1 {
            let buffer = audioBufferList.mBuffers
            guard let mData = buffer.mData, buffer.mDataByteSize > 0 else { return }
            audioCallback(Data(bytes: mData, count: Int(buffer.mDataByteSize)))
            return
        }

        let abl = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        guard abl.count == channels else { return }

        // Interleave float32 planar buffers into a single interleaved payload.
        var out = Data(count: frameCount * channels * MemoryLayout<Float>.size)
        out.withUnsafeMutableBytes { outBytes in
            guard let outBase = outBytes.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            for c in 0..<channels {
                let inBuf = abl[c]
                guard let inData = inBuf.mData else { return }
                let inBase = inData.assumingMemoryBound(to: Float.self)
                for f in 0..<frameCount {
                    outBase[(f * channels) + c] = inBase[f]
                }
            }
        }

        audioCallback(out)
    }
    
    // MARK: - VideoToolbox Compression
    
    private func setupCompressionSession(width: Int, height: Int) throws {
        var session: VTCompressionSession?
        
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            throw StreamerError.compressionSessionCreationFailed(status)
        }
        
        // Configure for low latency streaming
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel) // High Profile for better quality
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        // Use ~1s keyframe interval for better compression efficiency vs forcing frequent IDRs.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: currentPreset.frameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: currentPreset.frameRate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: currentPreset.bitrate as CFNumber)

        // Cap instantaneous rate spikes to reduce Wi‑Fi burst loss/jitter.
        let bytesPerSecondCap = Int(Double(currentPreset.bitrate) / 8.0 * 1.10)
        let dataRateLimits = [bytesPerSecondCap as CFNumber, 1 as CFNumber] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        self.compressionSession = session
    }

    private func scaledDimensionsToFit(
        sourceWidth: Int,
        sourceHeight: Int,
        maxWidth: Int?,
        maxHeight: Int?
    ) -> (Int, Int) {
        guard let maxWidth, let maxHeight, maxWidth > 0, maxHeight > 0 else {
            return (sourceWidth, sourceHeight)
        }

        let scaleW = Double(maxWidth) / Double(sourceWidth)
        let scaleH = Double(maxHeight) / Double(sourceHeight)
        let scale = min(1.0, min(scaleW, scaleH))

        if scale >= 1.0 {
            return (sourceWidth, sourceHeight)
        }

        var w = Int((Double(sourceWidth) * scale).rounded(.down))
        var h = Int((Double(sourceHeight) * scale).rounded(.down))

        // H.264 generally expects even dimensions.
        w = max(2, w & ~1)
        h = max(2, h & ~1)

        return (w, h)
    }
    
    /// Dynamically updates the bitrate during an active session.
    func setBitrate(_ bps: Int) {
        guard let session = compressionSession else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps as CFNumber)
        NSLog("[ScreenStreamer] Bitrate updated to \(bps / 1_000_000) Mbps")
    }
    
    private var compressCount = 0
    
    private func compressFrame(_ sampleBuffer: CMSampleBuffer) {
        compressCount += 1
        if compressCount <= 3 || compressCount % 60 == 0 {
            NSLog("[ScreenStreamer] compressFrame called: \(compressCount)")
        }
        
        guard let session = compressionSession else {
            NSLog("[ScreenStreamer] compressFrame: No compressionSession!")
            return
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            NSLog("[ScreenStreamer] compressFrame: No imageBuffer (sampleBuffer valid: \(CMSampleBufferIsValid(sampleBuffer)))")
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        var flags = VTEncodeInfoFlags()
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: nil,
            infoFlagsOut: &flags
        ) { [weak self] status, _, sampleBuffer in
            if status != noErr {
                NSLog("[ScreenStreamer] Encode callback error: \(status)")
                return
            }
            guard let sampleBuffer = sampleBuffer else {
                NSLog("[ScreenStreamer] Encode callback: nil sampleBuffer")
                return
            }
            self?.handleCompressedFrame(sampleBuffer)
        }
        
        if status != noErr {
            NSLog("[ScreenStreamer] Compression failed: \(status)")
        }
    }
    
    private var handleCount = 0
    
    private func handleCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
        handleCount += 1
        if handleCount <= 3 || handleCount % 60 == 0 {
            NSLog("[ScreenStreamer] handleCompressedFrame called: \(handleCount)")
        }
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            NSLog("[ScreenStreamer] handleCompressedFrame: No dataBuffer")
            return
        }

        // Extract SPS/PPS when present so the client can build a valid decoder
        cacheParameterSetsIfNeeded(from: sampleBuffer)

        // Determine if this frame is a keyframe
        let isKeyframe = isKeyframeSample(sampleBuffer)

        // Convert AVCC (length-prefixed) to Annex B (start-code prefixed)
        guard let elementaryStream = makeAnnexBStream(from: dataBuffer, includeParameterSets: isKeyframe) else {
            return
        }

        // Create frame data with timestamp header (first 8 bytes) followed by Annex B stream
        var frameData = Data()
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var timestampValue = timestamp.value
        frameData.append(Data(bytes: &timestampValue, count: 8))
        frameData.append(elementaryStream)
        
        if Int.random(in: 0...60) == 0 {
            NSLog("[ScreenStreamer] Compressed frame: \(frameData.count) bytes")
        }
        
        frameCallback?(frameData)
    }

    /// Returns true when the sample buffer represents a keyframe (sync frame).
    private func isKeyframeSample(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
              CFArrayGetCount(attachments) > 0,
              let rawAttachment = CFArrayGetValueAtIndex(attachments, 0) else {
            return false
        }
        let attachment = unsafeBitCast(rawAttachment, to: CFDictionary.self) as NSDictionary
        let notSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        return !notSync
    }

    /// Caches SPS/PPS from the format description if not already captured.
    private func cacheParameterSetsIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard cachedSPS == nil || cachedPPS == nil,
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        var spsPointer: UnsafePointer<UInt8>?
        var spsSize: Int = 0
        var ppsPointer: UnsafePointer<UInt8>?
        var ppsSize: Int = 0

        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPointer,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )

        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPointer,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )

        if let spsPointer, spsSize > 0 {
            cachedSPS = Data(bytes: spsPointer, count: spsSize)
        }
        if let ppsPointer, ppsSize > 0 {
            cachedPPS = Data(bytes: ppsPointer, count: ppsSize)
        }
    }

    /// Converts the compressed block buffer into an Annex B elementary stream, optionally
    /// prefixing with SPS/PPS for keyframes.
    private func makeAnnexBStream(from dataBuffer: CMBlockBuffer, includeParameterSets: Bool) -> Data? {
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let pointer = dataPointer else { return nil }

        let startCode: [UInt8] = [0, 0, 0, 1]
        var stream = Data()

        if includeParameterSets, let sps = cachedSPS, let pps = cachedPPS {
            stream.append(contentsOf: startCode)
            stream.append(sps)
            stream.append(contentsOf: startCode)
            stream.append(pps)
        }

        var offset = 0
        while offset + 4 <= length {
            // Read the NAL length (big endian)
            // Read the NAL length (big endian) safely to avoid alignment crashes
            var lengthVal: UInt32 = 0
            withUnsafeMutableBytes(of: &lengthVal) { buffer in
                buffer.copyBytes(from: UnsafeRawBufferPointer(start: UnsafeRawPointer(pointer).advanced(by: offset), count: 4))
            }
            let nalLength = UInt32(bigEndian: lengthVal)
            offset += 4
            guard nalLength > 0, offset + Int(nalLength) <= length else { break }

            stream.append(contentsOf: startCode)
            stream.append(Data(bytes: pointer.advanced(by: offset), count: Int(nalLength)))

            offset += Int(nalLength)
        }

        return stream
    }
}

// MARK: - SCStreamDelegate

extension ScreenStreamer: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[ScreenStreamer] Stream stopped with error: \(error)")
        isRunning = false
    }
}

// MARK: - Stream Output Handler

private final class StreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void
    private var frameCount = 0
    
    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        frameCount += 1
        if frameCount <= 3 || frameCount % 60 == 0 {
            NSLog("[ScreenStreamer] StreamOutput called: frame \(frameCount), type: \(type)")
        }
        guard type == .screen else { return }
        if frameCount % 60 == 0 {
            NSLog("[ScreenStreamer] Processing frame \(frameCount)")
        }
        handler(sampleBuffer)
    }
}

private final class AudioStreamOutput: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}

// MARK: - Errors

enum StreamerError: Error {
    case noDisplayFound
    case compressionSessionCreationFailed(OSStatus)
}
