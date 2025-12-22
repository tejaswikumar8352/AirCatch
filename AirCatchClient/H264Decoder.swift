//
//  H264Decoder.swift
//  AirCatchClient
//
//  Hardware-accelerated H.264 decoder using VideoToolbox.
//

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Delegate protocol for decoded frame output.
protocol H264DecoderDelegate: AnyObject {
    func decoder(_ decoder: H264Decoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
    func decoder(_ decoder: H264Decoder, didEncounterError error: Error)
}

/// Hardware-accelerated H.264 decoder.
final class H264Decoder {
    weak var delegate: H264DecoderDelegate?
    
    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?
    
    private var spsData: Data?
    private var ppsData: Data?
    
    private let queue = DispatchQueue(label: "com.aircatch.h264decoder")
    
    // MARK: - Public API
    
    /// Decodes a compressed frame.
    /// - Parameter frameData: Raw H.264 data with 8-byte timestamp header
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
            self?.formatDescription = nil
        }
    }
    
    // MARK: - Private Implementation
    
    private var frameCount = 0
    
    private func processFrame(_ frameData: Data) {
        frameCount += 1
        // Skip 8-byte timestamp header
        guard frameData.count > 8 else {
            NSLog("[H264Decoder] Frame too small: \(frameData.count) bytes")
            return
        }
        let nalData = Data(frameData.dropFirst(8))
        
        // Parse NAL units
        let nalUnits = parseNALUnits(from: nalData)
        
        if frameCount <= 3 {
            NSLog("[H264Decoder] Frame \(frameCount): \(nalUnits.count) NAL units from \(nalData.count) bytes")
        }
        
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
    
    private func processNALUnit(_ nalUnit: Data) {
        guard !nalUnit.isEmpty else { return }
        
        let nalType = nalUnit[0] & 0x1F
        
        switch nalType {
        case 7: // SPS
            spsData = nalUnit
            tryCreateFormatDescription()
            
        case 8: // PPS
            ppsData = nalUnit
            tryCreateFormatDescription()
            
        case 1, 5: // Non-IDR slice (1) or IDR slice (5)
            decodeVideoFrame(nalUnit, isIDR: nalType == 5)
            
        default:
            break
        }
    }
    
    private func tryCreateFormatDescription() {
        guard let sps = spsData, let pps = ppsData else { return }
        guard formatDescription == nil else { return }
        
        // Create format description from SPS/PPS
        var newFormatDescription: CMFormatDescription?

        let status: OSStatus = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                guard let spsBase = spsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsBase = ppsBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return -1
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
        
        if status == noErr, let desc = newFormatDescription {
            formatDescription = desc
            createDecompressionSession()
            NSLog("[H264Decoder] Format description created")
        }
    }
    
    private func createDecompressionSession() {
        guard let formatDesc = formatDescription else { return }
        
        invalidateSession()
        
        let decoderSpecification: [String: Any] = [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true
        ]
        
        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        
        var outputCallback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { decompressionOutputRefCon, _, status, _, imageBuffer, presentationTimeStamp, _ in
                guard status == noErr, let imageBuffer = imageBuffer else { return }
                
                let decoder = Unmanaged<H264Decoder>.fromOpaque(decompressionOutputRefCon!).takeUnretainedValue()
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
        
        if status == noErr {
            decompressionSession = session
            NSLog("[H264Decoder] Decompression session created")
        } else {
            NSLog("[H264Decoder] Failed to create session: \(status)")
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
        let decodeFlags: VTDecodeFrameFlags = [._EnableAsynchronousDecompression, ._EnableTemporalProcessing]
        
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: decodeFlags,
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
    }
    
    private var decodedCount = 0
    
    private func handleDecodedFrame(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        decodedCount += 1
        if decodedCount <= 5 {
            NSLog("[H264Decoder] Decoded frame \(decodedCount): \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
        }
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

enum H264DecoderError: Error {
    case formatDescriptionCreationFailed
    case sessionCreationFailed(OSStatus)
    case decodeFailed(OSStatus)
}
