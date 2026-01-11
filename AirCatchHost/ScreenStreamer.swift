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
import AppKit
import IOSurface

/// Captures the screen using ScreenCaptureKit and compresses frames to HEVC.
final class ScreenStreamer: NSObject {
    
    // MARK: - Configuration
    
    private var currentPreset: QualityPreset
    private var clientWidth: Int?
    private var clientHeight: Int?
    private var targetDisplayID: CGDirectDisplayID?

    private(set) var captureWidth: Int = 0
    private(set) var captureHeight: Int = 0
    
    // MARK: - Capture Components
    
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private var videoQueue: DispatchQueue?
    private var encodeQueue: DispatchQueue?
    
    // MARK: - Compression
    
    private var compressionSession: VTCompressionSession?
    private var frameCallback: ((Data) -> Void)?
    private var cachedVPS: Data?  // HEVC only
    private var cachedSPS: Data?
    private var cachedPPS: Data?
    
    // MARK: - State
    
    private var isRunning = false
    
    init(preset: QualityPreset = .balanced,
         maxClientWidth: Int? = nil,
         maxClientHeight: Int? = nil,
         targetDisplayID: CGDirectDisplayID? = nil,
         onFrame: @escaping (Data) -> Void) {
        self.currentPreset = preset
        self.clientWidth = maxClientWidth
        self.clientHeight = maxClientHeight
        self.targetDisplayID = targetDisplayID
        self.frameCallback = onFrame
        super.init()
    }

    
    // MARK: - Public API
    
    func start() async throws {
        guard !isRunning else { return }
        
        // 1. Get available content
        let availableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        
        // Get the target display
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
        
        // Calculate output resolution based on client's iPad screen
        // Goal: Match iPad's aspect ratio for pixel-perfect display
        let (width, height) = calculateOptimalOutputResolution(
            sourceWidth: display.width,
            sourceHeight: display.height,
            clientWidth: clientWidth,
            clientHeight: clientHeight
        )
        
        // Create content filter (capture entire display)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        captureWidth = width
        captureHeight = height
        
        // 3. Create stream configuration
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(currentPreset.frameRate))
        config.queueDepth = 5 // Allow buffer for compression pipeline
        
        // Use compatible pixel format - BGRA works with both H.264 and HEVC
        // VideoToolbox will handle color space conversion internally
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true


        
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
        
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        isRunning = false
        NSLog("[ScreenStreamer] Stopped")
    }


    
    // MARK: - VideoToolbox Compression
    
    private func setupCompressionSession(width: Int, height: Int) throws {
        var session: VTCompressionSession?
        
        // Choose codec based on quality preset
        let codecType = currentPreset.useHEVC ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        
        // Force hardware encoding for best quality and performance
        let encoderSpec: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ]
        
        // Specify source pixel format attributes to match ScreenCaptureKit output
        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] // Enable IOSurface backing
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: codecType,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: sourcePixelBufferAttributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            throw StreamerError.compressionSessionCreationFailed(status)
        }
        
        // Real-time encoding with minimal latency
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        
        // Ultra-low latency: process frames immediately
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 1 as CFNumber)
        
        if currentPreset.useHEVC {
            // ----------------------------------------------------------------------
            // HEVC Main 4:2:2 10-bit - High Chroma Quality
            // Re-enabled as per user request to use 4:4:2 (4:2:2) with lower bitrate
            // ----------------------------------------------------------------------
            
            let status422 = VTSessionSetProperty(session, 
                                                 key: kVTCompressionPropertyKey_ProfileLevel, 
                                                 value: kVTProfileLevel_HEVC_Main42210_AutoLevel)
            
            if status422 == noErr {
                NSLog("[ScreenStreamer] 🚀 SUCCESS: Encoder configured for HEVC Main 4:2:2 10-bit")
            } else {
                // Fallback to Main 10-bit if 4:2:2 fails
                NSLog("[ScreenStreamer] ⚠️ 4:2:2 10-bit unavailable (Error: \(status422)). Falling back to Main 10-bit.")
                VTSessionSetProperty(session, 
                                     key: kVTCompressionPropertyKey_ProfileLevel, 
                                     value: kVTProfileLevel_HEVC_Main10_AutoLevel)
            }
            
        } else {
            // H.264 High Profile with CABAC for better compression
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
            VTSessionSetProperty(session, key: kVTCompressionPropertyKey_H264EntropyMode, value: kVTH264EntropyMode_CABAC)
        }
        
        // Keyframe interval: 1 second for faster stream recovery after packet loss
        let keyframeInterval = currentPreset.frameRate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyframeInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
        
        // Frame rate configuration
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: currentPreset.frameRate as CFNumber)
        
        // DYNAMIC BITRATE: Respect the selected high-bandwidth QualityPreset
        // Performance (25Mbps) | Balanced (45Mbps) | Quality (80Mbps)
        let targetBitrate = currentPreset.bitrate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: targetBitrate as CFNumber)
        
        // Adaptive Bitrate Cap: 2.5x target (UNLEASHED)
        // High burst allowance eliminates scrolling stutter by allowing VBR spikes
        let bytesPerSecondCap = Int(Double(targetBitrate) / 8.0 * 2.5)
        let dataRateLimits = [bytesPerSecondCap as CFNumber, 1 as CFNumber] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits)
        
        // === COLOR SPACE: P3-D65 for Mac/iPad display matching ===
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_P3_D65)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        
        // Preserve any HDR metadata if present
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PreserveDynamicHDRMetadata, value: kCFBooleanTrue)
        
        // Quality setting: 0.75 (Balanced)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 0.75 as CFNumber)
        
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        if prepareStatus != noErr {
            NSLog("[ScreenStreamer] ⚠️ Warning: PrepareToEncodeFrames returned status \(prepareStatus)")
        }
        
        NSLog("[ScreenStreamer] ✅ HEVC 4:2:2 10-bit compression session created: \(targetBitrate / 1_000_000)Mbps @ \(currentPreset.frameRate)fps - P3-D65 color space")
        self.compressionSession = session
    }


    /// Calculate optimal output resolution - Strictly matches Client Resolution
    /// As requested: "Stream only at iPad's native resolution"
    /// ScreenCaptureKit will handle aspect ratio by letterboxing/pillarboxing the content within this frame.
    private func calculateOptimalOutputResolution(
        sourceWidth: Int,
        sourceHeight: Int,
        clientWidth: Int?,
        clientHeight: Int?
    ) -> (Int, Int) {
        // If no client dimensions provided, use source
        guard let clientWidth = clientWidth, let clientHeight = clientHeight,
              clientWidth > 0, clientHeight > 0 else {
            NSLog("[ScreenStreamer] No client dimensions, using source: \(sourceWidth)x\(sourceHeight)")
            return (sourceWidth, sourceHeight)
        }
        
        // Strictly use Client's Native Resolution
        // Ensure even dimensions for video encoding
        let targetWidth = max(2, clientWidth & ~1)
        let targetHeight = max(2, clientHeight & ~1)
        
        let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
        
        NSLog("[ScreenStreamer] Resolution: source=\(sourceWidth)x\(sourceHeight), client=\(clientWidth)x\(clientHeight), output=\(targetWidth)x\(targetHeight), sourceAspect=\(String(format: "%.3f", sourceAspect))")
        
        return (targetWidth, targetHeight)
    }




    
    /// Dynamically updates the bitrate during an active session.
    func setBitrate(_ bps: Int) {
        guard let session = compressionSession else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps as CFNumber)
        
        // Also update data rate limits to match the new target (2.5x cap)
        let bytesPerSecondCap = Int(Double(bps) / 8.0 * 2.5)
        let dataRateLimits = [bytesPerSecondCap as CFNumber, 1 as CFNumber] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits)
        
        NSLog("[ScreenStreamer] Bitrate updated to \(bps / 1_000_000) Mbps")
    }

    /// Dynamically updates the frame rate property of the encoder.
    /// Note: This doesn't change the screen capture rate (controlled by SCStreamConfiguration),
    /// but helps the encoder allocate bits more effectively.
    func setFrameRate(_ fps: Int) {
        guard let session = compressionSession else { return }
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        // Also update keyframe interval to match 1 second
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber)
        NSLog("[ScreenStreamer] Encoder FPS updated to \(fps)")
    }
    
    private var compressCount = 0
    private var skippedFrames = 0
    
    private func compressFrame(_ sampleBuffer: CMSampleBuffer) {
        compressCount += 1
        
        guard let session = compressionSession else {
            #if DEBUG
            if compressCount <= 3 {
                NSLog("[ScreenStreamer] compressFrame: No compressionSession!")
            }
            #endif
            return
        }
        
        // ScreenCaptureKit provides sample buffers with CVPixelBuffers
        // Some callbacks may not have imageBuffer - just skip them silently
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            skippedFrames += 1
            #if DEBUG
            // Only log first few skipped frames - this is normal for some ScreenCaptureKit callbacks
            if skippedFrames <= 2 {
                let dataReady = CMSampleBufferDataIsReady(sampleBuffer)
                let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
                NSLog("[ScreenStreamer] Skipped frame %d (no imageBuffer, dataReady=%d, samples=%d)", 
                      skippedFrames, dataReady ? 1 : 0, numSamples)
            }
            #endif
            return
        }
        
        #if DEBUG
        // Log pixel buffer details for first successful frame only
        if compressCount - skippedFrames == 1 {
            let pbWidth = CVPixelBufferGetWidth(imageBuffer)
            let pbHeight = CVPixelBufferGetHeight(imageBuffer)
            NSLog("[ScreenStreamer] First imageBuffer: %dx%d", pbWidth, pbHeight)
        }
        #endif
        
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
            guard let strongSelf = self else { return }
            if status != noErr {
                #if DEBUG
                NSLog("[ScreenStreamer] Encode callback error: \(status)")
                #endif
                // Error recovery: invalidate session on persistent errors
                // The next frame will trigger session recreation
                if status == kVTInvalidSessionErr || status == kVTVideoEncoderMalfunctionErr {
                    Task { @MainActor in
                        strongSelf.handleCompressionError()
                    }
                }
                return
            }
            guard let sampleBuffer = sampleBuffer else {
                #if DEBUG
                NSLog("[ScreenStreamer] Encode callback: nil sampleBuffer")
                #endif
                return
            }
            strongSelf.handleCompressedFrame(sampleBuffer)
        }
        
        if status != noErr {
            #if DEBUG
            NSLog("[ScreenStreamer] Compression failed: \(status)")
            #endif
        }
    }
    
    /// Handle compression errors by resetting the session
    @MainActor
    private func handleCompressionError() {
        guard let session = compressionSession else { return }
        VTCompressionSessionInvalidate(session)
        compressionSession = nil
        cachedSPS = nil
        cachedPPS = nil
        cachedVPS = nil
        // Session will be recreated on next start
        #if DEBUG
        NSLog("[ScreenStreamer] Compression session reset due to error")
        #endif
    }
    
    private var handleCount = 0
    
    private func handleCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
        handleCount += 1
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            #if DEBUG
            if handleCount <= 3 {
                NSLog("[ScreenStreamer] handleCompressedFrame: No dataBuffer")
            }
            #endif
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
        
        #if DEBUG
        if Int.random(in: 0...60) == 0 {
            NSLog("[ScreenStreamer] Compressed frame: \(frameData.count) bytes")
        }
        #endif
        
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

    /// Caches SPS/PPS (H.264) or VPS/SPS/PPS (HEVC) from the format description.
    private func cacheParameterSetsIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        
        let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        if codecType == kCMVideoCodecType_HEVC {
            // HEVC: Extract VPS, SPS, PPS (3 parameter sets)
            guard cachedVPS == nil || cachedSPS == nil || cachedPPS == nil else { return }
            
            var vpsPointer: UnsafePointer<UInt8>?
            var vpsSize: Int = 0
            var spsPointer: UnsafePointer<UInt8>?
            var spsSize: Int = 0
            var ppsPointer: UnsafePointer<UInt8>?
            var ppsSize: Int = 0
            
            // VPS (index 0)
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: &vpsPointer,
                parameterSetSizeOut: &vpsSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            
            // SPS (index 1)
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 1,
                parameterSetPointerOut: &spsPointer,
                parameterSetSizeOut: &spsSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            
            // PPS (index 2)
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 2,
                parameterSetPointerOut: &ppsPointer,
                parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            
            if let vpsPointer, vpsSize > 0 {
                cachedVPS = Data(bytes: vpsPointer, count: vpsSize)
            }
            if let spsPointer, spsSize > 0 {
                cachedSPS = Data(bytes: spsPointer, count: spsSize)
            }
            if let ppsPointer, ppsSize > 0 {
                cachedPPS = Data(bytes: ppsPointer, count: ppsSize)
            }
            
            if cachedVPS != nil && cachedSPS != nil && cachedPPS != nil {
                NSLog("[ScreenStreamer] HEVC parameter sets cached (VPS: \(cachedVPS?.count ?? 0)B, SPS: \(cachedSPS?.count ?? 0)B, PPS: \(cachedPPS?.count ?? 0)B)")
            }
        } else {
            // H.264: Extract SPS, PPS (2 parameter sets)
            guard cachedSPS == nil || cachedPPS == nil else { return }
            
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
            
            if cachedSPS != nil && cachedPPS != nil {
                NSLog("[ScreenStreamer] H.264 parameter sets cached (SPS: \(cachedSPS?.count ?? 0)B, PPS: \(cachedPPS?.count ?? 0)B)")
            }
        }
    }

    /// Converts the compressed block buffer into an Annex B elementary stream, optionally
    /// prefixing with parameter sets for keyframes (SPS/PPS for H.264, VPS/SPS/PPS for HEVC).
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

        if includeParameterSets {
            if let vps = cachedVPS {
                // HEVC: Include VPS, SPS, PPS
                guard let sps = cachedSPS, let pps = cachedPPS else { return nil }
                stream.append(contentsOf: startCode)
                stream.append(vps)
                stream.append(contentsOf: startCode)
                stream.append(sps)
                stream.append(contentsOf: startCode)
                stream.append(pps)
            } else if let sps = cachedSPS, let pps = cachedPPS {
                // H.264: Include SPS, PPS
                stream.append(contentsOf: startCode)
                stream.append(sps)
                stream.append(contentsOf: startCode)
                stream.append(pps)
            }
        }

        var offset = 0
        while offset + 4 <= length {
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
        guard type == .screen else { return }
        #if DEBUG
        // Only log occasionally to reduce noise - streaming is working
        if frameCount == 1 || frameCount % 300 == 0 {
            NSLog("[ScreenStreamer] Frame %d captured", frameCount)
        }
        #endif
        handler(sampleBuffer)
    }
}



// MARK: - Errors

enum StreamerError: Error {
    case noDisplayFound
    case compressionSessionCreationFailed(OSStatus)
}
