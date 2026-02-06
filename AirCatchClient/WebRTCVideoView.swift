//
//  WebRTCVideoView.swift
//  AirCatchClient
//
//  SwiftUI wrapper for RTCMTLVideoView.
//

import SwiftUI
import WebRTC

struct WebRTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        view.backgroundColor = .black
        track.add(view)
        context.coordinator.currentTrack = track
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if context.coordinator.currentTrack !== track {
            context.coordinator.currentTrack?.remove(uiView)
            track.add(uiView)
            context.coordinator.currentTrack = track
        }
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.currentTrack?.remove(uiView)
        coordinator.currentTrack = nil
    }

    final class Coordinator {
        var currentTrack: RTCVideoTrack?
    }
}
