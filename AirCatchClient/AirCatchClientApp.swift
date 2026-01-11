//
//  AirCatchClientApp.swift
//  AirCatchClient
//
//  Created by teja on 12/14/25.
//

import SwiftUI
import AVFoundation

@main
struct AirCatchClientApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var pipManager = PiPManager.shared
    
    init() {
        // Configure audio session for PiP
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            AirCatchLog.error("Audio session setup failed: \(error)", category: .general)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ClientManager.shared)
                .environmentObject(pipManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                // Auto-start PiP when going to background to keep connection alive
                if ClientManager.shared.state == .streaming {
                    pipManager.startPiP()
                }
            case .active:
                // Stop PiP when returning to foreground
                if pipManager.isPiPActive {
                    pipManager.stopPiP()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
