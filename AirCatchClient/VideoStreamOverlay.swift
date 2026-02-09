//
//  VideoStreamOverlay.swift
//  AirCatchClient
//
//  Displays the decoded video stream with aspect-fit (letterboxing/pillarboxing).
//  Touch coordinates are correctly mapped to the video content area.
//

import SwiftUI
import CoreVideo
import CoreMedia
import Combine

struct VideoStreamOverlay: View {
    @EnvironmentObject var clientManager: ClientManager
    @StateObject private var viewModel = VideoStreamViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Solid black background for letterbox/pillarbox areas
                Color.black
                
                let webRTCTrack = clientManager.webRTCVideoTrack
                let hasVideo = webRTCTrack != nil || viewModel.hasFrame

                if hasVideo {
                    let videoSize: CGSize = {
                        if let frameSize = viewModel.frameSize {
                            return frameSize
                        }
                        if let screenInfo = clientManager.screenInfo {
                            return CGSize(width: CGFloat(screenInfo.width), height: CGFloat(screenInfo.height))
                        }
                        return geometry.size
                    }()
                    
                    // Calculate aspect-fit frame
                    let contentFrame = calculateAspectFitFrame(
                        videoSize: videoSize,
                        containerSize: geometry.size
                    )
                    
                    // Video and touch layer
                    ZStack {
                        // Video layer
                        if let webRTCTrack {
                            WebRTCVideoView(track: webRTCTrack)
                        } else {
                            MetalVideoView(viewModel: viewModel)
                        }
                        
                        // Touch layer
                        MouseInputView()
                    }
                    .frame(width: contentFrame.width, height: contentFrame.height)
                    .position(x: contentFrame.midX, y: contentFrame.midY)
                    
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .onReceive(clientManager.videoFrameSubject) { data in
            if clientManager.webRTCVideoTrack == nil {
                viewModel.decode(frameData: data)
            }
        }
        .onChange(of: clientManager.webRTCVideoTrack) { _, newValue in
            if newValue != nil {
                viewModel.reset()
            }
        }
        .onChange(of: clientManager.state) { _, newState in
            if case .disconnected = newState {
                viewModel.reset()
            }
            if case .error = newState {
                viewModel.reset()
            }
        }
        .ignoresSafeArea()
    }
    
    /// Calculate aspect-fit frame (letterboxed/pillarboxed) for video content
    private func calculateAspectFitFrame(videoSize: CGSize, containerSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        
        let videoAspect = videoSize.width / videoSize.height
        let containerAspect = containerSize.width / containerSize.height
        
        let fitWidth: CGFloat
        let fitHeight: CGFloat
        
        if videoAspect > containerAspect {
            // Video is wider than container - fit to width, letterbox top/bottom
            fitWidth = containerSize.width
            fitHeight = containerSize.width / videoAspect
        } else {
            // Video is taller than container - fit to height, pillarbox left/right
            fitHeight = containerSize.height
            fitWidth = containerSize.height * videoAspect
        }
        
        let x = (containerSize.width - fitWidth) / 2
        let y = (containerSize.height - fitHeight) / 2
        
        return CGRect(x: x, y: y, width: fitWidth, height: fitHeight)
    }
}


// MARK: - View Model (Immediate Frame Display)

final class VideoStreamViewModel: NSObject, ObservableObject {
    @Published private(set) var hasFrame: Bool = false
    @Published private(set) var frameSize: CGSize?
    var lastTouchLocation: CGPoint?
    private let decoder = VideoDecoder()
    private let frameSinkLock = NSLock()
    private var frameSink: ((CVPixelBuffer) -> Void)?
    private let streamStateLock = NSLock()
    private var cachedHasFrame = false
    private var cachedFrameSize: CGSize?
    
    override init() {
        super.init()
        decoder.delegate = self
    }
    
    func decode(frameData: Data) {
        decoder.decode(frameData: frameData)
    }
    
    func setFrameSink(_ sink: @escaping (CVPixelBuffer) -> Void) {
        frameSinkLock.lock()
        frameSink = sink
        frameSinkLock.unlock()
    }

    func clearFrameSink() {
        frameSinkLock.lock()
        frameSink = nil
        frameSinkLock.unlock()
    }

    func reset() {
        decoder.reset()
        streamStateLock.lock()
        cachedHasFrame = false
        cachedFrameSize = nil
        streamStateLock.unlock()
        Task { @MainActor [weak self] in
            self?.hasFrame = false
            self?.frameSize = nil
        }
    }

    private func pushFrameToSink(_ pixelBuffer: CVPixelBuffer) {
        frameSinkLock.lock()
        let sink = frameSink
        frameSinkLock.unlock()
        sink?(pixelBuffer)
    }
}


extension VideoStreamViewModel: VideoDecoderDelegate {
    private static var frameLogCount = 0
    
    func decoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        pushFrameToSink(pixelBuffer)

        // Only log first frame to reduce noise
        VideoStreamViewModel.frameLogCount += 1
        if VideoStreamViewModel.frameLogCount == 1 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            AirCatchLog.info("Streaming started: \(width)x\(height)", category: .video)
        }

        let newSize = CGSize(
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )

        var shouldPublish = false
        streamStateLock.lock()
        if !cachedHasFrame || cachedFrameSize != newSize {
            cachedHasFrame = true
            cachedFrameSize = newSize
            shouldPublish = true
        }
        streamStateLock.unlock()

        if shouldPublish {
            Task { @MainActor [weak self] in
                self?.hasFrame = true
                self?.frameSize = newSize
            }
        }
    }

    
    func decoder(_ decoder: VideoDecoder, didEncounterError error: Error) {
        AirCatchLog.info(" Decode error: \(error)")
        streamStateLock.lock()
        cachedHasFrame = false
        cachedFrameSize = nil
        streamStateLock.unlock()
        Task { @MainActor [weak self] in
            self?.hasFrame = false
            self?.frameSize = nil
        }
    }
}

#Preview {
    VideoStreamOverlay()
        .environmentObject(ClientManager.shared)
}
