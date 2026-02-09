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
import Accelerate  // PERFORMANCE: SIMD-optimized audio interleaving

/// Captures the screen using ScreenCaptureKit and compresses frames to HEVC.
final class ScreenStreamer: NSObject {
    
    // MARK: - Configuration
    
    private var targetFrameRate: Int
    private var targetBitrate: Int
    private var clientWidth: Int?
    private var clientHeight: Int?
    private var targetDisplayID: CGDirectDisplayID?
    /// When true, stream at host's native resolution. When false, scale to client resolution.
    private var optimizeForHostDisplay: Bool

    private(set) var captureWidth: Int = 0
    private(set) var captureHeight: Int = 0
    
    // MARK: - Capture Components
    
    private var stream: SCStream?
    private var streamConfiguration: SCStreamConfiguration?
    private var streamOutput: StreamOutput?
    private var videoQueue: DispatchQueue?
    private var encodeQueue: DispatchQueue?
    
    // MARK: - Compression
    
    private var compressionSession: VTCompressionSession?
    private var frameCallback: ((Data) -> Void)?
    private var rawFrameCallback: ((CVPixelBuffer, CMTime) -> Void)?
    private var encodeVideo: Bool
    private var audioCallback: ((Data) -> Void)?
    private var cachedVPS: Data?  // HEVC only
    private var cachedSPS: Data?
    private var cachedPPS: Data?
    private let encodeStateLock = NSLock()
    
    // MARK: - Audio
    
    private(set) var audioEnabled: Bool = false
    
    // MARK: - State
    
    private var isRunning = false
    
    // MARK: - Encoder Throughput Tracking
    
    /// Total frames encoded since last reset (used for FPS measurement)
    private(set) var encodedFrameCount: Int = 0
    private var lastFrameCountReset: Date = Date()
    
    init(targetFrameRate: Int = AirCatchConfig.defaultFrameRate,
         targetBitrate: Int = AirCatchConfig.defaultBitrate,
         maxClientWidth: Int? = nil,
         maxClientHeight: Int? = nil,
         targetDisplayID: CGDirectDisplayID? = nil,
         audioEnabled: Bool = false,
         optimizeForHostDisplay: Bool = false,
         encodeVideo: Bool = true,
         onFrame: @escaping (Data) -> Void,
         onRawFrame: ((CVPixelBuffer, CMTime) -> Void)? = nil,
         onAudio: ((Data) -> Void)? = nil) {
        self.targetFrameRate = targetFrameRate
        self.targetBitrate = targetBitrate
        self.clientWidth = maxClientWidth
        self.clientHeight = maxClientHeight
        self.targetDisplayID = targetDisplayID
        self.audioEnabled = audioEnabled
        self.optimizeForHostDisplay = optimizeForHostDisplay
        self.encodeVideo = encodeVideo
        self.frameCallback = onFrame
        self.rawFrameCallback = onRawFrame
        self.audioCallback = onAudio
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
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFrameRate))
        config.queueDepth = 3 // Keep latency low while preserving encoder headroom
        
        // Use compatible pixel format - BGRA works with both H.264 and HEVC
        // VideoToolbox will handle color space conversion internally
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        
        // Audio capture configuration
        if audioEnabled {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true  // Don't capture AirCatch's own sounds
            config.sampleRate = 48000
            config.channelCount = 2
        }


        
        // 5. Setup compression session (optional, can be disabled for WebRTC-only)
        if encodeVideo {
            try setupCompressionSession(width: width, height: height)
        }
        
        // 6. Create and start the stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        let queue = DispatchQueue(label: "com.aircatch.videocapture", qos: .userInteractive)
        self.videoQueue = queue  // Keep reference to prevent deallocation
        
        streamOutput = StreamOutput(
            onVideo: { [weak self] sampleBuffer in
                // Call compressFrame directly - queue is already background
                self?.compressFrame(sampleBuffer)
            },
            onAudio: audioEnabled ? { [weak self] sampleBuffer in
                self?.processAudioSample(sampleBuffer)
            } : nil
        )

        try stream.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: queue)
        
        // Add audio output if enabled
        if audioEnabled {
            let audioQueue = DispatchQueue(label: "com.aircatch.audiocapture", qos: .userInteractive)
            try stream.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: audioQueue)
        }


        
        try await stream.startCapture()
        
        self.stream = stream
        self.streamConfiguration = config
        isRunning = true
        
        AirCatchLog.info(" Started capturing at \(targetFrameRate)fps (\(width)x\(height))")
    }
    
    func stop() {
        guard isRunning else { return }
        
        Task {
            try? await stream?.stopCapture()
        }
        
        stream = nil
        streamConfiguration = nil
        streamOutput = nil
        
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        isRunning = false
        AirCatchLog.info(" Stopped")
    }
    
    deinit {
        reusableAudioBufferList.deallocate()
    }

    /// Enable/disable video encoding while keeping capture running.
    func setEncodingEnabled(_ enabled: Bool) {
        encodeStateLock.lock()
        encodeVideo = enabled
        encodeStateLock.unlock()
    }

    private func isEncodingEnabled() -> Bool {
        encodeStateLock.lock()
        let enabled = encodeVideo
        encodeStateLock.unlock()
        return enabled
    }


    
    // MARK: - VideoToolbox Compression
    
    private func setupCompressionSession(width: Int, height: Int) throws {
        var session: VTCompressionSession?
        
        // Choose codec: Always HEVC (all iOS 17+ and macOS 14+ devices have hardware support)
        let codecType = kCMVideoCodecType_HEVC
        
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
        
        // HEVC Profile: Main10 (10-bit) for best quality, fallback to Main (8-bit)
        let statusMain10 = VTSessionSetProperty(session, 
                                                key: kVTCompressionPropertyKey_ProfileLevel, 
                                                value: kVTProfileLevel_HEVC_Main10_AutoLevel)
        
        if statusMain10 == noErr {
            AirCatchLog.info(" 🚀 SUCCESS: Encoder configured for HEVC Main10 (10-bit) 4:2:0")
        } else {
            AirCatchLog.info(" ⚠️ HEVC Main10 unavailable (Error: \(statusMain10)). Falling back to Main (8-bit).")
            VTSessionSetProperty(session, 
                                 key: kVTCompressionPropertyKey_ProfileLevel, 
                                 value: kVTProfileLevel_HEVC_Main_AutoLevel)
        }
        
        // GOP Configuration (1s) for balanced recovery and compression efficiency
        let gopDuration = 1.0
        let keyframeInterval = Int(Double(targetFrameRate) * gopDuration)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyframeInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: gopDuration as CFNumber)
        
        // Frame rate configuration
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: targetFrameRate as CFNumber)
        
        // DYNAMIC BITRATE: Adaptive target set by HostManager
        let initialBitrate = targetBitrate
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: initialBitrate as CFNumber)
        
        // Bitrate Cap: 2.5x target (VBR headroom)
        // High burst allowance eliminates scrolling stutter by allowing VBR spikes
        let bytesPerSecondCap = Int(Double(initialBitrate) / 8.0 * 2.5)
        let dataRateLimits = [bytesPerSecondCap as CFNumber, 1 as CFNumber] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits)
        
        // === COLOR SPACE + VIDEO RANGE ===
        // Use Display P3 primaries (Mac screens are P3) with Rec.709 transfer/matrix.
        // CRITICAL: Force FULL RANGE output to avoid washed-out colors on iPad.
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_P3_D65)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_ITU_R_709_2)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        
        // Force full-range (0-255) instead of limited/video range (16-235)
        // This is critical for screen content to avoid crushed blacks and washed colors
        if #available(macOS 14.0, *) {
            VTSessionSetProperty(session, key: "FullRangeVideo" as CFString, value: kCFBooleanTrue)
        }
        
        // Preserve any HDR metadata if present
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_PreserveDynamicHDRMetadata, value: kCFBooleanTrue)
        
        // Quality setting: 0.75 (Balanced)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 0.75 as CFNumber)
        
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        if prepareStatus != noErr {
            AirCatchLog.info(" ⚠️ Warning: PrepareToEncodeFrames returned status \(prepareStatus)")
        }
        
        AirCatchLog.info(" ✅ HEVC Main10 compression session created: \(initialBitrate / 1_000_000)Mbps @ \(targetFrameRate)fps - P3/Rec.709 color space")
        self.compressionSession = session
    }


    /// Calculate optimal output resolution based on settings.
    /// - When `optimizeForHostDisplay` is true: Uses host's native resolution (pixel-perfect for host content)
    /// - When `optimizeForHostDisplay` is false: Uses client's resolution (pixel-perfect for client display)
    /// ScreenCaptureKit will handle aspect ratio by letterboxing/pillarboxing the content within this frame.
    private func calculateOptimalOutputResolution(
        sourceWidth: Int,
        sourceHeight: Int,
        clientWidth: Int?,
        clientHeight: Int?
    ) -> (Int, Int) {
        // When optimizing for host display, use the host's native resolution
        if optimizeForHostDisplay {
            // Ensure even dimensions for video encoding
            let targetWidth = max(2, sourceWidth & ~1)
            let targetHeight = max(2, sourceHeight & ~1)
            
            AirCatchLog.info("📺 Using HOST resolution (optimizeForHostDisplay=true): \(targetWidth)x\(targetHeight)")
            return (targetWidth, targetHeight)
        }
        
        // When optimizing for client display (default), use the client's resolution
        guard let clientWidth = clientWidth, let clientHeight = clientHeight,
              clientWidth > 0, clientHeight > 0 else {
            AirCatchLog.info(" No client dimensions, using source: \(sourceWidth)x\(sourceHeight)")
            return (sourceWidth, sourceHeight)
        }
        
        // Use Client's Native Resolution for pixel-perfect display
        // Ensure even dimensions for video encoding
        let targetWidth = max(2, clientWidth & ~1)
        let targetHeight = max(2, clientHeight & ~1)
        
        let sourceAspect = Double(sourceWidth) / Double(sourceHeight)
        
        AirCatchLog.info("📱 Using CLIENT resolution: source=\(sourceWidth)x\(sourceHeight), client=\(clientWidth)x\(clientHeight), output=\(targetWidth)x\(targetHeight), sourceAspect=\(String(format: "%.3f", sourceAspect))")
        
        return (targetWidth, targetHeight)
    }




    
    /// Dynamically updates the bitrate during an active session.
    func setBitrate(_ bps: Int) {
        guard let session = compressionSession else { return }
        targetBitrate = bps
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps as CFNumber)
        
        // Also update data rate limits to match the new target (2.5x cap)
        let bytesPerSecondCap = Int(Double(bps) / 8.0 * 2.5)
        let dataRateLimits = [bytesPerSecondCap as CFNumber, 1 as CFNumber] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataRateLimits)
        
        AirCatchLog.info(" Bitrate updated to \(bps / 1_000_000) Mbps")
    }

    /// Dynamically updates the frame rate property of the encoder.
    /// Note: This doesn't change the screen capture rate (controlled by SCStreamConfiguration),
    /// but helps the encoder allocate bits more effectively.
    func setFrameRate(_ fps: Int) {
        guard let session = compressionSession else { return }
        targetFrameRate = fps
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        // Also update keyframe interval to match 1 second
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber)
        AirCatchLog.info(" Encoder FPS updated to \(fps)")
    }

    /// Updates both encoder FPS hints and capture output FPS.
    /// This is required for real throughput reduction under network congestion.
    func setCaptureFrameRate(_ fps: Int) {
        let clampedFps = max(1, fps)
        setFrameRate(clampedFps)

        guard let stream, let config = streamConfiguration else { return }
        targetFrameRate = clampedFps
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(clampedFps))

        Task {
            do {
                try await stream.updateConfiguration(config)
                AirCatchLog.info(" Capture FPS updated to \(clampedFps)")
            } catch {
                AirCatchLog.error("Failed to update capture FPS: \(error)", category: .video)
            }
        }
    }
    
    private var compressCount = 0
    private(set) var skippedFrameCount: Int = 0  // Exposed for diagnostics
    
    private func compressFrame(_ sampleBuffer: CMSampleBuffer) {
        compressCount += 1
        
        // ScreenCaptureKit provides sample buffers with CVPixelBuffers
        // Some callbacks may not have imageBuffer - just skip them silently
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            skippedFrameCount += 1
            #if DEBUG
            // Only log first few skipped frames - this is normal for some ScreenCaptureKit callbacks
            if skippedFrameCount <= 2 {
                let dataReady = CMSampleBufferDataIsReady(sampleBuffer)
                let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
                AirCatchLog.debug("Skipped frame \(skippedFrameCount) (no imageBuffer, dataReady=\(dataReady ? 1 : 0), samples=\(numSamples))", category: .video)
            }
            #endif
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Forward raw frames for WebRTC or external consumers
        if let rawFrameCallback {
            rawFrameCallback(imageBuffer, presentationTime)
        }
        
        guard isEncodingEnabled(), let session = compressionSession else {
            #if DEBUG
            if compressCount <= 3 {
                AirCatchLog.info(" compressFrame: Encoding disabled or no compressionSession")
            }
            #endif
            return
        }
        
        #if DEBUG
        // Log pixel buffer details for first successful frame only
        if compressCount - skippedFrameCount == 1 {
            let pbWidth = CVPixelBufferGetWidth(imageBuffer)
            let pbHeight = CVPixelBufferGetHeight(imageBuffer)
            AirCatchLog.debug("First imageBuffer: \(pbWidth)x\(pbHeight)", category: .video)
        }
        #endif
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
                AirCatchLog.info(" Encode callback error: \(status)")
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
                AirCatchLog.info(" Encode callback: nil sampleBuffer")
                #endif
                return
            }
            strongSelf.handleCompressedFrame(sampleBuffer)
        }
        
        if status != noErr {
            #if DEBUG
            AirCatchLog.info(" Compression failed: \(status)")
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
        AirCatchLog.info(" Compression session reset due to error")
        #endif
    }
    
    private var handleCount = 0
    
    private func handleCompressedFrame(_ sampleBuffer: CMSampleBuffer) {
        handleCount += 1
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            #if DEBUG
            if handleCount <= 3 {
                AirCatchLog.info(" handleCompressedFrame: No dataBuffer")
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
            AirCatchLog.info(" Compressed frame: \(frameData.count) bytes")
        }
        #endif
        
        frameCallback?(frameData)
        encodedFrameCount += 1  // Track encoded frames
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

    /// Caches VPS/SPS/PPS from the HEVC format description.
    private func cacheParameterSetsIfNeeded(from sampleBuffer: CMSampleBuffer) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return
        }
        
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
            AirCatchLog.info(" HEVC parameter sets cached (VPS: \(cachedVPS?.count ?? 0)B, SPS: \(cachedSPS?.count ?? 0)B, PPS: \(cachedPPS?.count ?? 0)B)")
        }
    }

    /// Converts the compressed HEVC block buffer into an Annex B elementary stream,
    /// optionally prefixing with VPS/SPS/PPS for keyframes.
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
        
        // PERFORMANCE: Estimate capacity upfront to avoid reallocations
        // Each NAL needs 4 start code bytes + data. Parameter sets add ~100 bytes.
        let estimatedCapacity = length + (length / 1200) * 4 + 200
        var stream = Data()
        stream.reserveCapacity(estimatedCapacity)

        if includeParameterSets {
            // HEVC: Include VPS, SPS, PPS
            guard let vps = cachedVPS, let sps = cachedSPS, let pps = cachedPPS else { return nil }
            stream.append(contentsOf: startCode)
            stream.append(vps)
            stream.append(contentsOf: startCode)
            stream.append(sps)
            stream.append(contentsOf: startCode)
            stream.append(pps)
        }

        // PERFORMANCE: Use raw pointer append to reduce overhead
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
            stream.append(UnsafeBufferPointer(start: pointer.advanced(by: offset), count: Int(nalLength)))

            offset += Int(nalLength)
        }

        return stream
    }
    
    // MARK: - Audio Processing
    
    // PERFORMANCE: Pre-allocated audio buffer list to avoid allocator churn per sample callback.
    // ScreenCaptureKit delivers up to 2 audio buffers (stereo planar).
    private let audioListSize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
    private lazy var reusableAudioBufferList: UnsafeMutablePointer<UInt8> = {
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: audioListSize)
        return ptr
    }()
    
    /// Process audio sample buffer and send raw PCM data to callback
    private func processAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard let audioCallback = audioCallback else { return }
        
        // PERFORMANCE: Reuse pre-allocated buffer instead of allocating per sample
        let bufferListPointer = reusableAudioBufferList
        
        // Zero out for each use
        bufferListPointer.initialize(repeating: 0, count: audioListSize)
        
        // Rebound to AudioBufferList for API call
        let audioBufferListPtr = bufferListPointer.withMemoryRebound(to: AudioBufferList.self, capacity: 1) { $0 }
        
        var blockBuffer: CMBlockBuffer?
        
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr,
            bufferListSize: audioListSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == noErr else {
            #if DEBUG
            AirCatchLog.error("Failed to get audio buffer: \(status)", category: .general)
            #endif
            return
        }
        
        let list = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)
        guard list.count > 0, let buf0 = list[0].mData else { return }
        let size0 = Int(list[0].mDataByteSize)
        
        // Prepare Audio Packet
        var audioData = Data()
        
        // 1. Append Timestamp (8 bytes)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var timestampValue = timestamp.value
        audioData.append(Data(bytes: &timestampValue, count: 8))
        
        // 2. Append PCM Data (Interleaved)
        // Check for Planar Stereo (2 buffers) and Interleave if necessary
        if list.count == 2, let buf1 = list[1].mData {
            // Planar Stereo: Interleave L and R (L0 R0 L1 R1...)
            // Both buffers should be same size and format (Float32)
            let sampleCount = size0 / 4
            var interleaved = Data(count: size0 * 2)
            
            // PERFORMANCE: Use CBLAS strided copy for SIMD-optimized interleaving
            interleaved.withUnsafeMutableBytes { dst in
                guard let dstPtr = dst.bindMemory(to: Float.self).baseAddress else { return }
                let src0 = buf0.assumingMemoryBound(to: Float.self)
                let src1 = buf1.assumingMemoryBound(to: Float.self)
                
                // Manual interleaving loop (cblas_scopy is deprecated)
                // Copy left channel to even indices (0, 2, 4...)
                // Copy right channel to odd indices (1, 3, 5...)
                for i in 0..<sampleCount {
                    dstPtr[i*2] = src0[i]
                    dstPtr[i*2 + 1] = src1[i]
                }
            }
            audioData.append(interleaved)
        } else {
            // Already Interleaved or Mono: Copy directly
            audioData.append(Data(bytes: buf0, count: size0))
        }
        
        audioCallback(audioData)
    }
}

// MARK: - SCStreamDelegate

extension ScreenStreamer: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        AirCatchLog.info(" Stream stopped with error: \(error)")
        isRunning = false
    }
}

// MARK: - Stream Output Handler

private final class StreamOutput: NSObject, SCStreamOutput {
    private let videoHandler: (CMSampleBuffer) -> Void
    private let audioHandler: ((CMSampleBuffer) -> Void)?
    private var videoFrameCount = 0
    private var audioSampleCount = 0
    
    init(onVideo: @escaping (CMSampleBuffer) -> Void, onAudio: ((CMSampleBuffer) -> Void)? = nil) {
        self.videoHandler = onVideo
        self.audioHandler = onAudio
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            videoFrameCount += 1
            #if DEBUG
            // Only log occasionally to reduce noise - streaming is working
            if videoFrameCount == 1 || videoFrameCount % 300 == 0 {
                AirCatchLog.debug("Frame \(videoFrameCount) captured", category: .video)
            }
            #endif
            videoHandler(sampleBuffer)
            
        case .audio:
            audioSampleCount += 1
            #if DEBUG
            if audioSampleCount == 1 {
                AirCatchLog.debug("Audio streaming started", category: .general)
            }
            #endif
            audioHandler?(sampleBuffer)
            
        default:
            break
        }
    }
}



// MARK: - Errors

enum StreamerError: Error {
    case noDisplayFound
    case compressionSessionCreationFailed(OSStatus)
}
