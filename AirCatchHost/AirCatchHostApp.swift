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
        // Main Window - ensures app is visible on launch (prevents "silent launch" rejection)
        WindowGroup {
            HostView()
                .navigationTitle("AirCatch Host")
        }
        .windowResizability(.contentSize)
        .commands {
            // Standard commands (Sidebar, etc.) could go here
            CommandGroup(replacing: .newItem) { } // Disable "New Window" to keep it simple
        }

        // Optional Menu Bar interactive status
        MenuBarExtra("AirCatch", systemImage: "display") {
            Button("Show AirCatch Host") {
                NSApp.activate(ignoringOtherApps: true)
                // Logic to bring window to front would go here
            }
            Divider()
            Text("PIN: \(HostManager.shared.currentPIN)")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
// Removed inline MenuBarView as it is now replaced by HostView.swift

final class HostAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions for input injection
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
        
        HostManager.shared.start()
    }
}
