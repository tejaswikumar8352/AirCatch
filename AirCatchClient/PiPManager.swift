//
//  PiPManager.swift
//  AirCatchClient
//
//  Picture-in-Picture support for keeping the app alive when backgrounded.
//  Uses AVSampleBufferDisplayLayer to render video frames in PiP mode.
//

import AVKit
import UIKit
import CoreMedia
import Combine

/// Manages Picture-in-Picture for the AirCatch video stream.
@MainActor
final class PiPManager: NSObject, ObservableObject {
    static let shared = PiPManager()
    
    // MARK: - Published State
    
    @Published var isPiPActive = false
    @Published var isPiPPossible = false
    
    // MARK: - Private Properties
    
    private var pipController: AVPictureInPictureController?
    private var displayLayer: AVSampleBufferDisplayLayer?
    private var pipContentSource: AVPictureInPictureController.ContentSource?
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Setup
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            AirCatchLog.info(" Failed to setup audio session: \(error)")
        }
    }
    
    /// Sets up PiP with a sample buffer display layer for rendering video.
    func setupPiP(containerView: UIView) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            AirCatchLog.info(" PiP not supported on this device")
            isPiPPossible = false
            return
        }
        
        // Create the display layer
        let layer = AVSampleBufferDisplayLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = containerView.bounds
        containerView.layer.addSublayer(layer)
        self.displayLayer = layer
        
        // Create PiP content source
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        self.pipContentSource = contentSource
        
        // Create the PiP controller
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = controller
        
        isPiPPossible = true
        AirCatchLog.info(" PiP setup complete")
    }
    
    /// Updates the display layer frame when container resizes.
    func updateFrame(_ frame: CGRect) {
        displayLayer?.frame = frame
    }
    
    // MARK: - Video Frame Rendering
    
    /// Renders a CVPixelBuffer to the PiP display layer.
    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard let displayLayer = displayLayer else { return }
        
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        guard let format = formatDescription else { return }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: format,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        guard let buffer = sampleBuffer else { return }
        
        if #available(iOS 18.0, *) {
            displayLayer.sampleBufferRenderer.enqueue(buffer)
        } else {
            displayLayer.enqueue(buffer)
        }
    }
    
    // MARK: - PiP Control
    
    func startPiP() {
        guard let controller = pipController, controller.isPictureInPicturePossible else {
            AirCatchLog.info(" Cannot start PiP - not possible")
            return
        }
        controller.startPictureInPicture()
    }
    
    func stopPiP() {
        pipController?.stopPictureInPicture()
    }
    
    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PiPManager: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            AirCatchLog.info(" PiP will start")
        }
    }
    
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
            AirCatchLog.info(" PiP started")
        }
    }
    
    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            AirCatchLog.info(" PiP will stop")
        }
    }
    
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
            AirCatchLog.info(" PiP stopped")
        }
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in
            AirCatchLog.info(" PiP failed to start: \(error)")
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension PiPManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        // Always "playing" for live stream
    }
    
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // Handle size change if needed
    }
    
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) {
        // No-op for live stream, immediately call completion
        completion()
    }
}

