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
    @State private var showKeyboard = false
    
    // Keyboard position and size (draggable/resizable)
    @State private var keyboardPosition: CGPoint = .zero
    @State private var keyboardSize: CGSize = CGSize(width: 600, height: 220)
    @State private var keyboardInitialized = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Solid black background for letterbox/pillarbox areas
                Color.black
                
                if let pixelBuffer = viewModel.pixelBuffer {
                    // Get video dimensions
                    let videoWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
                    let videoHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
                    let videoSize = CGSize(width: videoWidth, height: videoHeight)
                    
                    // Calculate aspect-fit frame
                    let contentFrame = calculateAspectFitFrame(
                        videoSize: videoSize,
                        containerSize: geometry.size
                    )
                    
                    // Calculate letterbox height (bottom black bar)
                    let bottomLetterboxHeight = geometry.size.height - contentFrame.maxY
                    
                    // Video and touch layer
                    ZStack {
                        // Video layer
                        MetalVideoView(
                            pixelBuffer: Binding(
                                get: { viewModel.pixelBuffer },
                                set: { _ in }
                            )
                        )
                        
                        // Touch layer
                        MouseInputView()
                    }
                    .frame(width: contentFrame.width, height: contentFrame.height)
                    .position(x: contentFrame.midX, y: contentFrame.midY)
                    
                    // Keyboard toggle button - positioned in the letterbox area (bottom-right)
                    if bottomLetterboxHeight > 50 {
                        // Place button in the letterbox area when there's enough space
                        KeyboardToggleButton(showKeyboard: $showKeyboard)
                            .position(
                                x: geometry.size.width - 40,
                                y: contentFrame.maxY + (bottomLetterboxHeight / 2)
                            )
                    } else {
                        // Fallback: position at bottom-right corner with some padding
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                KeyboardToggleButton(showKeyboard: $showKeyboard)
                                    .padding(.trailing, 20)
                                    .padding(.bottom, 20)
                            }
                        }
                    }
                    
                    // Mac-style keyboard overlay (draggable & resizable)
                    if showKeyboard {
                        MacKeyboardView(
                            isVisible: $showKeyboard,
                            position: $keyboardPosition,
                            size: $keyboardSize
                        )
                        .onAppear {
                            // Initialize keyboard position to center-bottom
                            if !keyboardInitialized {
                                keyboardPosition = CGPoint(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height - keyboardSize.height / 2 - 20
                                )
                                keyboardInitialized = true
                            }
                        }
                    }
                    
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
        }
        .onReceive(clientManager.videoFrameSubject) { data in
            viewModel.decode(frameData: data)
        }
        .onChange(of: clientManager.state) { _, newState in
            if case .disconnected = newState {
                viewModel.reset()
                showKeyboard = false
            }
            if case .error = newState {
                viewModel.reset()
                showKeyboard = false
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
    @Published var pixelBuffer: CVPixelBuffer?
    var lastTouchLocation: CGPoint?
    private let decoder = VideoDecoder()
    
    override init() {
        super.init()
        decoder.delegate = self
    }
    
    func decode(frameData: Data) {
        decoder.decode(frameData: frameData)
    }
    
    func reset() {
        decoder.reset()
        Task { @MainActor in
            self.pixelBuffer = nil
        }
    }
}


extension VideoStreamViewModel: VideoDecoderDelegate {
    private static var frameLogCount = 0
    
    func decoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        // Only log first frame to reduce noise
        VideoStreamViewModel.frameLogCount += 1
        if VideoStreamViewModel.frameLogCount == 1 {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            AirCatchLog.info("Streaming started: \(width)x\(height)", category: .video)
        }
        
        // Display frame immediately for lowest latency
        DispatchQueue.main.async {
            self.pixelBuffer = pixelBuffer
        }
    }

    
    func decoder(_ decoder: VideoDecoder, didEncounterError error: Error) {
        AirCatchLog.info(" Decode error: \(error)")
        Task { @MainActor in
            self.pixelBuffer = nil
        }
    }
}

#Preview {
    VideoStreamOverlay()
        .environmentObject(ClientManager.shared)
}
