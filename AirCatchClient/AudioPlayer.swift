//
//  AudioPlayer.swift
//  AirCatchClient
//
//  Plays streamed PCM audio from the Mac host using AVAudioEngine.
//

import Foundation
import AVFoundation
import CoreMedia

/// Plays PCM audio streamed from the AirCatch host.
final class AudioPlayer {
    
    // MARK: - Audio Engine
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    // MARK: - Audio Format
    
    // Use standard non-interleaved float32 format for AVAudioEngine compatibility.
    // Host is currently sending Planar Float32 (Left channel only due to implementation limit).
    // We will upmix this to Stereo on playback.
    private let sampleRate: Double = 48000
    private let channelCount: UInt32 = 2
    private lazy var audioFormat: AVAudioFormat? = {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount)
    }()
    
    // MARK: - State
    
    private var isRunning = false
    private var packetCount = 0
    private var hasLoggedResync = false  // Prevents log spam during resyncs
    
    // MARK: - Initialization
    
    init() {
        setupAudioSession()
        setupAudioEngine()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            AirCatchLog.error("Failed to setup audio session: \(error)", category: .general)
        }
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        
        guard let format = audioFormat else {
            AirCatchLog.error("Failed to create audio format", category: .general)
            return
        }
        
        // Connect with the format (Standard Non-Interleaved)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }
    
    // MARK: - Public API
    
    func start() {
        guard !isRunning else { return }
        
        do {
            try audioEngine.start()
            playerNode.play()
            isRunning = true
            AirCatchLog.info("Audio player started", category: .general)
        } catch {
            AirCatchLog.error("Failed to start audio engine: \(error)", category: .general)
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        playerNode.stop()
        audioEngine.stop()
        isRunning = false
        packetCount = 0
        AirCatchLog.info("Audio player stopped", category: .general)
    }
    
    /// Play audio data received from host
    /// - Parameter data: Audio packet with 8-byte timestamp header + PCM data
    func playAudioPacket(_ data: Data) {
        guard isRunning, data.count > 8 else { return }
        
        packetCount += 1
        
        // Skip 8-byte timestamp header
        let pcmData = Data(data.dropFirst(8))
        
        guard let format = audioFormat else { return }
        
        // Calculate frame count assuming Interleaved Stereo Input (L R L R)
        // 2 channels * 4 bytes/sample = 8 bytes/frame
        let bytesPerFrame: UInt32 = 8
        let frameCount = UInt32(pcmData.count) / bytesPerFrame
        
        guard frameCount > 0 else { return }
        
        // Create audio buffer (Stereo, Non-Interleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        
        // De-interleave: Copy L R L R... to [L L L...] and [R R R...]
        pcmData.withUnsafeBytes { rawBufferPointer in
            guard let src = rawBufferPointer.bindMemory(to: Float.self).baseAddress else { return }
            
            if let dstLeft = buffer.floatChannelData?[0], let dstRight = buffer.floatChannelData?[1] {
                // Perform de-interleaving loop
                for i in 0..<Int(frameCount) {
                    dstLeft[i] = src[i*2]
                    dstRight[i] = src[i*2+1]
                }
            }
        }
        
        // --- Drift Correction ---
        // If we have too many queued buffers, we are lagging behind video.
        // ScreenStreamer sends small chunks (approx 10-20ms).
        // 60 buffers ~= 1200ms latency (acceptable for streaming).
        // If we exceed this, flush the queue to "jump" to the present.
        
        if pendingBuffers > 60 {
            // Log sparingly to avoid console spam (only once per resync)
            if !hasLoggedResync {
                AirCatchLog.debug("Audio drift detected (Queue: \(pendingBuffers)). Resyncing...", category: .general)
                hasLoggedResync = true
            }
            playerNode.stop() // Clears all scheduled buffers instantly
            playerNode.play()
            pendingBuffers = 0
            // Reset log flag after a delay to allow future logging
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.hasLoggedResync = false
            }
            // We still play *this* packet so we have something to hear immediately
        }
        
        // Schedule buffer for playback
        pendingBuffers += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async { // Completion might be on background thread
                self?.pendingBuffers = max(0, (self?.pendingBuffers ?? 1) - 1)
            }
        }
        
        #if DEBUG
        if packetCount == 1 {
            AirCatchLog.debug("First audio packet: \(pcmData.count) bytes, \(frameCount) frames (Stereo De-interleave)", category: .general)
        }
        #endif
    }
    
    private var pendingBuffers = 0
}
