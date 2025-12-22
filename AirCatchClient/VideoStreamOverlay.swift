//
//  VideoStreamOverlay.swift
//  AirCatchClient
//
//  Displays the decoded video stream with proper aspect ratio (letterboxed).
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
                // Solid black background for proper letterboxing/pillarboxing
                Color.black
                
                if let pixelBuffer = viewModel.pixelBuffer {
                    ZStack {
                        MetalVideoView(
                            pixelBuffer: Binding(
                                get: { viewModel.pixelBuffer },
                                set: { _ in }
                            )
                        )
                        .contentShape(Rectangle()) // Essential for layout
                        
                        // Unified Input Overlay (Touch + Mouse)
                        // Placed on top to capture all input
                        MouseInputView()
                    }
                    .frame(
                        width: videoRect(in: geometry.size, pixelBuffer: pixelBuffer).width,
                        height: videoRect(in: geometry.size, pixelBuffer: pixelBuffer).height
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    
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
            }
            if case .error = newState {
                viewModel.reset()
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Video Rect Calculation
    
    private func aspectRatio(pixelBuffer: CVPixelBuffer?) -> CGFloat {
        if let pixelBuffer {
            let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
            let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
            if width > 0 && height > 0 {
                return width / height
            }
        }
        if let info = clientManager.screenInfo {
            return CGFloat(info.width) / CGFloat(info.height)
        }
        return 16.0 / 9.0
    }
    
    /// Calculates the letterboxed video rect within the container.
    private func videoRect(in containerSize: CGSize, pixelBuffer: CVPixelBuffer) -> CGSize {
        let videoAspect = aspectRatio(pixelBuffer: pixelBuffer)
        let containerAspect = containerSize.width / containerSize.height
        
        if videoAspect > containerAspect {
            let width = containerSize.width
            let height = width / videoAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * videoAspect
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - View Model

final class VideoStreamViewModel: NSObject, ObservableObject {
    @Published var pixelBuffer: CVPixelBuffer?
    var lastTouchLocation: CGPoint?
    private let decoder = H264Decoder()
    
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

extension VideoStreamViewModel: H264DecoderDelegate {
    func decoder(_ decoder: H264Decoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        NSLog("[VideoStreamViewModel] Received pixelBuffer: \(width)x\(height)")
        Task { @MainActor in
            self.pixelBuffer = pixelBuffer
        }
    }
    
    func decoder(_ decoder: H264Decoder, didEncounterError error: Error) {
        NSLog("[VideoStreamViewModel] Decode error: \(error)")
        Task { @MainActor in
            self.pixelBuffer = nil
        }
    }
}

#Preview {
    VideoStreamOverlay()
        .environmentObject(ClientManager.shared)
}
