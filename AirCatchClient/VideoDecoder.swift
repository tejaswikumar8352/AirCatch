//
//  VideoDecoder.swift
//  AirCatchClient
//
//  Hardware-accelerated HEVC/H.264 decoder using VideoToolbox.
//

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Delegate protocol for decoded frame output.
protocol VideoDecoderDelegate: AnyObject {
    func decoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    func decoder(_ decoder: VideoDecoder, didEncounterError error: Error)
}

/// Hardware-accelerated HEVC (H.265) and H.264 decoder with Sidecar-level optimization.
final class VideoDecoder {
    weak var delegate: VideoDecoderDelegate?
    
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    private var detectedCodec: CMVideoCodecType = kCMVideoCodecType_H264
    
    // H.264 parameter sets
    private var spsData: Data?
    private var ppsData: Data?
    
    // HEVC parameter sets (VPS required for HEVC)
    private var vpsData: Data?
    
    private let queue = DispatchQueue(label: "com.aircatch.universal_decoder", qos: .userInteractive)
    
    // MARK: - Public API
    
    /// Decodes a compressed frame.
    /// - Parameter frameData: Raw HEVC/H.264 data with 8-byte timestamp header
    func decode(frameData: Data) {
        queue.async { [weak self] in
            self?.processFrame(frameData)
        }
    }
    
    func reset() {
        queue.async { [weak self] in
            self?.invalidateSession()
            self?.spsData = nil
            self?.ppsData = nil
            self?.vpsData = nil
            self?.formatDescription = nil
            self?.detectedCodec = kCMVideoCodecType_H264
        }
    }
    
    // MARK: - Private Implementation
    
    private var frameCount = 0
    
    private func processFrame(_ frameData: Data) {
        frameCount += 1
        // Skip 8-byte timestamp header
        guard frameData.count > 8 else {
            #if DEBUG
            if frameCount <= 3 {
                AirCatchLog.debug(" Frame too small: \(frameData.count) bytes")
            }
            #endif
            return
        }
        let nalData = Data(frameData.dropFirst(8))
        
        // Parse NAL units
        let nalUnits = parseNALUnits(from: nalData)
        
        // Only log first frame
        #if DEBUG
        if frameCount == 1 {
            AirCatchLog.debug(" Frame 1: \(nalUnits.count) NAL units from \(nalData.count) bytes")
        }
        #endif
        
        for nalUnit in nalUnits {
            processNALUnit(nalUnit)
        }
    }
    
    private func parseNALUnits(from data: Data) -> [Data] {
        var nalUnits: [Data] = []
        var i = 0
        var startIndex = 0
        
        while i < data.count - 3 {
            // Check for start code (0x00 0x00 0x01 or 0x00 0x00 0x00 0x01)
            let isStartCode3 = data[i] == 0 && data[i+1] == 0 && data[i+2] == 1
            let isStartCode4 = i < data.count - 4 && data[i] == 0 && data[i+1] == 0 && data[i+2] == 0 && data[i+3] == 1
            
            if isStartCode3 || isStartCode4 {
                // If we've found a previous NAL unit, extract it
                if startIndex > 0 {
                    let nalData = data[startIndex..<i]
                    if !nalData.isEmpty {
                        nalUnits.append(Data(nalData))
                    }
                }
                
                // Move past the start code
                let startCodeLength = isStartCode4 ? 4 : 3
                startIndex = i + startCodeLength
                i = startIndex
            } else {
                i += 1
            }
        }
        
        // Don't forget the last NAL unit
        if startIndex < data.count {
            nalUnits.append(Data(data[startIndex...]))
        }
        
        return nalUnits
    }
    private var nalProcessCount = 0
    
    private func processNALUnit(_ nalUnit: Data) {
        guard !nalUnit.isEmpty else { return }
        
        let firstByte = nalUnit[0]
        
        // HEVC detection: check if this looks like an HEVC NAL unit
        // HEVC NAL header: forbidden_zero_bit(1) + nal_unit_type(6) + nuh_layer_id(6) + nuh_temporal_id_plus1(3)
        // VPS=32, SPS=33, PPS=34 are in the type 32-34 range
        // For HEVC, the NAL type is (firstByte >> 1) & 0x3F
        let potentialHEVCType = (firstByte >> 1) & 0x3F
        
        // Detect HEVC if we see VPS/SPS/PPS types OR if we've already detected HEVC
        let isHEVC = detectedCodec == kCMVideoCodecType_HEVC || 
                     potentialHEVCType == 32 || potentialHEVCType == 33 || potentialHEVCType == 34
        
        nalProcessCount += 1
        #if DEBUG
        // Only log first 5 NAL units for debugging
        if nalProcessCount <= 5 {
            let nalType = isHEVC ? Int(potentialHEVCType) : Int(firstByte & 0x1F)
            AirCatchLog.debug("NAL #\(nalProcessCount): type=\(nalType), isHEVC=\(isHEVC ? 1 : 0), size=\(nalUnit.count)", category: .video)
        }
        #endif
        
        if isHEVC {
            // HEVC NAL type is in bits 1-6 of first byte
            let nalType = (firstByte >> 1) & 0x3F
            
            switch nalType {
            case 32: // VPS
                vpsData = nalUnit
                detectedCodec = kCMVideoCodecType_HEVC
                tryCreateFormatDescription()
                
            case 33: // SPS
                spsData = nalUnit
                detectedCodec = kCMVideoCodecType_HEVC
                tryCreateFormatDescription()
                
            case 34: // PPS
                ppsData = nalUnit
                detectedCodec = kCMVideoCodecType_HEVC
                tryCreateFormatDescription()
                
            case 19, 20: // IDR slices (IDR_W_RADL, IDR_N_LP)
                decodeVideoFrame(nalUnit, isIDR: true)
                
            case 0...9: // Non-IDR slices (TRAIL_N, TRAIL_R, etc.)
                decodeVideoFrame(nalUnit, isIDR: false)
                
            case 16...21: // Other keyframe types (BLA, CRA, etc.)
                decodeVideoFrame(nalUnit, isIDR: true)
                
            default:
                #if DEBUG
                if nalProcessCount <= 10 {
                    AirCatchLog.debug(" HEVC unknown NAL type \(nalType), skipping")
                }
                #endif
                break
            }
        } else {
            // H.264 NAL type is in bits 0-4 of the first byte
            let nalType = firstByte & 0x1F
            
            switch nalType {
            case 7: // SPS
                spsData = nalUnit
                detectedCodec = kCMVideoCodecType_H264
                tryCreateFormatDescription()
                
            case 8: // PPS
                ppsData = nalUnit
                detectedCodec = kCMVideoCodecType_H264
                tryCreateFormatDescription()
                
            case 5: // IDR slice
                decodeVideoFrame(nalUnit, isIDR: true)
                
            case 1: // Non-IDR slice
                decodeVideoFrame(nalUnit, isIDR: false)
                
            default:
                break
            }
        }
    }
    
    private func tryCreateFormatDescription() {
        guard let sps = spsData, let pps = ppsData else { return }
        guard formatDescription == nil else { return }
        
        var newFormatDescription: CMFormatDescription?
        let status: OSStatus
        
        if detectedCodec == kCMVideoCodecType_HEVC {
            // HEVC requires VPS, SPS, PPS
            guard let vps = vpsData else { return }
            
            status = vps.withUnsafeBytes { vpsBytes in
                sps.withUnsafeBytes { spsBytes in
                    pps.withUnsafeBytes { ppsBytes in
                        guard let vpsBase = vpsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                              let spsBase = spsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                              let ppsBase = ppsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return OSStatus(-1)
                        }
                        
                        let parameterSetPointers: [UnsafePointer<UInt8>] = [vpsBase, spsBase, ppsBase]
                        let parameterSetSizes: [Int] = [vps.count, sps.count, pps.count]
                        
                        return parameterSetPointers.withUnsafeBufferPointer { pointers in
                            parameterSetSizes.withUnsafeBufferPointer { sizes in
                                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                                    allocator: kCFAllocatorDefault,
                                    parameterSetCount: 3,
                                    parameterSetPointers: pointers.baseAddress!,
                                    parameterSetSizes: sizes.baseAddress!,
                                    nalUnitHeaderLength: 4,
                                    extensions: nil,
                                    formatDescriptionOut: &newFormatDescription
                                )
                            }
                        }
                    }
                }
            }
            AirCatchLog.debug(" Creating HEVC format description")
        } else {
            // H.264 format description from SPS/PPS
            status = sps.withUnsafeBytes { spsBytes in
                pps.withUnsafeBytes { ppsBytes in
                    guard let spsBase = spsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let ppsBase = ppsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return OSStatus(-1)
                    }

                    let parameterSetPointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                    let parameterSetSizes: [Int] = [sps.count, pps.count]

                    return parameterSetPointers.withUnsafeBufferPointer { pointers in
                        parameterSetSizes.withUnsafeBufferPointer { sizes in
                            CMVideoFormatDescriptionCreateFromH264ParameterSets(
                                allocator: kCFAllocatorDefault,
                                parameterSetCount: 2,
                                parameterSetPointers: pointers.baseAddress!,
                                parameterSetSizes: sizes.baseAddress!,
                                nalUnitHeaderLength: 4,
                                formatDescriptionOut: &newFormatDescription
                            )
                        }
                    }
                }
            }
            AirCatchLog.debug(" Creating H.264 format description")
        }
        
        if status == noErr, let desc = newFormatDescription {
            formatDescription = desc
            createDecompressionSession()
            #if DEBUG
            let codecName = detectedCodec == kCMVideoCodecType_HEVC ? "HEVC" : "H.264"
            AirCatchLog.debug(" \(codecName) format description created successfully")
            #endif
        } else {
            #if DEBUG
            AirCatchLog.debug(" Failed to create format description: \(status)")
            #endif
        }
    }
    
    private func createDecompressionSession() {
        guard let formatDesc = formatDescription else { return }
        
        invalidateSession()
        
        // Force hardware acceleration for best quality
        let decoderSpecification: [String: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String: true
        ]
        
        // Output in BGRA for Metal compatibility, optimized for display
        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary
        ]
        
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, _, status, infoFlags, imageBuffer, presentationTimeStamp, _ in
                let decoder = Unmanaged<VideoDecoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
                
                if status != noErr {
                    decoder.callbackErrorCount += 1
                    #if DEBUG
                    if decoder.callbackErrorCount <= 5 {
                        AirCatchLog.debug(" Decompression callback error: \(status), flags: \(infoFlags.rawValue)")
                    }
                    #endif
                    return
                }
                
                guard let imageBuffer = imageBuffer else {
                    decoder.callbackNullCount += 1
                    #if DEBUG
                    if decoder.callbackNullCount <= 5 {
                        AirCatchLog.debug(" Decompression callback: null imageBuffer, flags: \(infoFlags.rawValue)")
                    }
                    #endif
                    return
                }
                
                decoder.handleDecodedFrame(imageBuffer, presentationTime: presentationTimeStamp)
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: decoderSpecification as CFDictionary,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: &outputCallback,
            decompressionSessionOut: &session
        )
        
        if status == noErr, let session = session {
            decompressionSession = session
            
            // Sidecar-level optimization: real-time + minimal latency
            VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_ThreadCount, value: 0 as CFNumber) // Auto thread count

            // Ensure YUV -> RGB conversion uses P3 color space to match encoder output.
            // This reduces "washed out" / saturation differences across devices.
            let props: CFDictionary = [
                kVTPixelTransferPropertyKey_DestinationColorPrimaries: kCVImageBufferColorPrimaries_P3_D65,
                kVTPixelTransferPropertyKey_DestinationTransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2,
                kVTPixelTransferPropertyKey_DestinationYCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2
            ] as CFDictionary
            VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_PixelTransferProperties, value: props)
            
            #if DEBUG
            let codecName = detectedCodec == kCMVideoCodecType_HEVC ? "HEVC" : "H.264"
            AirCatchLog.debug(" \(codecName) decompression session created - Sidecar-optimized")
            #endif
        } else {
            #if DEBUG
            AirCatchLog.debug(" Failed to create decompression session: \(status)")
            #endif
        }
    }
    
    private func decodeVideoFrame(_ nalUnit: Data, isIDR: Bool) {
        guard let session = decompressionSession,
              let formatDesc = formatDescription else {
            return
        }
        
        // Convert to AVCC format (length-prefixed)
        var avccData = Data()
        var length = UInt32(nalUnit.count).bigEndian
        avccData.append(Data(bytes: &length, count: 4))
        avccData.append(nalUnit)
        
        // Create a block buffer that copies the data (avoid dangling pointer)
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avccData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return }
        avccData.withUnsafeBytes { buffer in
            if let base = buffer.baseAddress {
                CMBlockBufferReplaceDataBytes(
                    with: base,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: avccData.count
                )
            }
        }
        
        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = avccData.count
        
        let timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        var timingInfoCopy = timingInfo
        
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfoCopy,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        
        guard let sample = sampleBuffer else { return }
        
        // Decode
        var flagsOut = VTDecodeInfoFlags()
        // Use 1x real-time playback for immediate frame output (lowest latency)
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression, ._1xRealTimePlayback]
        
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
        
        if decodeStatus != noErr {
            decodeErrorCount += 1
            #if DEBUG
            if decodeErrorCount <= 5 {
                AirCatchLog.debug(" ❌ Decode error: \(decodeStatus), isIDR: \(isIDR), NAL size: \(nalUnit.count)")
            }
            #endif
        }
    }
    
    private var decodedCount = 0
    private var decodeErrorCount = 0
    private var callbackErrorCount = 0
    private var callbackNullCount = 0
    
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        decodedCount += 1
        #if DEBUG
        // Only log first decoded frame
        if decodedCount == 1 {
            AirCatchLog.debug("First decoded frame: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))", category: .video)
        }
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.decoder(self, didOutputPixelBuffer: pixelBuffer, presentationTime: presentationTime)
        }
    }
    
    private func invalidateSession() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
    }
    
    deinit {
        invalidateSession()
    }
}

// MARK: - Decoder Error

enum VideoDecoderError: Error {
    case formatDescriptionCreationFailed
    case sessionCreationFailed(OSStatus)
    case decodeFailed(OSStatus)
}
