//
//  AirCatchHostApp.swift
//  AirCatchHost
//
//  Menu bar application for screen streaming to iOS devices.
//

import SwiftUI

@main
struct AirCatchHostApp: App {
    @NSApplicationDelegateAdaptor(HostAppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar extra only - no main window
        MenuBarExtra("AirCatch", systemImage: "display") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @ObservedObject private var hostManager = HostManager.shared
    @State private var isStreaming = false
    
    var body: some View {
        VStack(spacing: 12) {
            Text("AirCatch Host")
                .font(.headline)
            
            Divider()
            
            // PIN Display
            VStack(spacing: 4) {
                Text("Connection PIN")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(hostManager.currentPIN)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
            
            Button("New PIN") {
                hostManager.regeneratePIN()
            }
            .buttonStyle(.bordered)
            
            Divider()
            
            if isStreaming {
                Label("Streaming Active", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.green)
            } else {
                Label("Waiting for connection...", systemImage: "hourglass")
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 200)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StreamingStatusChanged"))) { notification in
            if let streaming = notification.object as? Bool {
                isStreaming = streaming
            }
        }
    }
}

final class HostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions for input injection
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
        
        HostManager.shared.start()
    }
}
