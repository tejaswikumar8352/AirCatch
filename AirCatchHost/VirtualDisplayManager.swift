//
//  VirtualDisplayManager.swift
//  AirCatchHost
//
//  Manages virtual display creation for extend display mode.
//  Uses DriverKit when available, falls back to secondary display detection.
//

import Foundation
import CoreGraphics
import AppKit
import Combine

// MARK: - DriverKit Availability Flag
// Set to false until Apple approves DriverKit entitlements
private let DRIVERKIT_ENABLED = false

/// Manages creation and lifecycle of a virtual display for extend display mode.
@MainActor
final class VirtualDisplayManager: ObservableObject {
    static let shared = VirtualDisplayManager()
    
    // MARK: - Published State
    
    @Published private(set) var isActive = false
    @Published private(set) var displayID: CGDirectDisplayID?
    @Published private(set) var displayFrame: CGRect?
    @Published private(set) var lastError: String?
    @Published private(set) var isDriverKitAvailable = false
    
    // Configuration
    private var currentConfig: ExtendedDisplayConfig?
    
    // DriverKit client (only used when DRIVERKIT_ENABLED is true)
    private var driverKitClient: DriverKitClient? {
        DRIVERKIT_ENABLED ? DriverKitClient.shared : nil
    }
    
    private init() {
        // Check if DriverKit driver is available
        checkDriverKitAvailability()
    }
    
    // MARK: - DriverKit Availability
    
    private func checkDriverKitAvailability() {
        guard DRIVERKIT_ENABLED else {
            isDriverKitAvailable = false
            NSLog("[VirtualDisplayManager] DriverKit is disabled - waiting for Apple entitlement approval")
            return
        }
        
        // Try to connect to the driver
        if let client = driverKitClient, client.connectToDriver() {
            isDriverKitAvailable = true
            NSLog("[VirtualDisplayManager] DriverKit driver is available")
        } else {
            isDriverKitAvailable = false
            NSLog("[VirtualDisplayManager] DriverKit driver not available - will use fallback methods")
        }
    }
    
    /// Install the DriverKit driver (requires user approval)
    func installDriver() {
        guard DRIVERKIT_ENABLED else {
            lastError = "DriverKit is not available. Waiting for Apple entitlement approval."
            NSLog("[VirtualDisplayManager] Cannot install driver - DriverKit disabled")
            return
        }
        driverKitClient?.installDriver()
    }
    
    // MARK: - Public API
    
    /// Attempt to create a virtual display with the specified configuration.
    /// - Parameters:
    ///   - config: Extended display configuration
    ///   - width: Width in pixels
    ///   - height: Height in pixels
    /// - Returns: The display ID of the created virtual display, or nil if not supported
    func createVirtualDisplay(config: ExtendedDisplayConfig, width: Int, height: Int) -> CGDirectDisplayID? {
        currentConfig = config
        
        // Try DriverKit first (if enabled)
        if DRIVERKIT_ENABLED {
            if isDriverKitAvailable {
                return createVirtualDisplayWithDriverKit(width: width, height: height)
            }
            
            // Try to connect to driver if not already connected
            if let client = driverKitClient, client.connectToDriver() {
                isDriverKitAvailable = true
                return createVirtualDisplayWithDriverKit(width: width, height: height)
            }
        }
        
        // Fallback: Check for existing secondary display
        NSLog("[VirtualDisplayManager] DriverKit not available, checking for secondary displays")
        if let secondaryDisplay = findSecondaryDisplay() {
            return useExistingDisplay(secondaryDisplay, config: config)
        }
        
        lastError = "Extend display requires a secondary display connected. DriverKit virtual displays pending Apple approval."
        NSLog("[VirtualDisplayManager] \(lastError ?? "Unknown error")")
        return nil
    }
    
    /// Create virtual display using DriverKit driver
    private func createVirtualDisplayWithDriverKit(width: Int, height: Int) -> CGDirectDisplayID? {
        guard let client = driverKitClient else { return nil }
        
        let config = VirtualDisplayConfiguration(
            width: UInt32(width),
            height: UInt32(height),
            refreshRate: 60
        )
        
        if client.connectDisplay(config: config) {
            // Wait a moment for macOS to register the display
            Thread.sleep(forTimeInterval: 0.5)
            
            if let displayID = client.displayID {
                self.displayID = displayID
                self.displayFrame = client.displayFrame
                self.isActive = true
                
                NSLog("[VirtualDisplayManager] Created virtual display via DriverKit: \(displayID)")
                return displayID
            }
        }
        
        lastError = client.lastError ?? "Failed to create virtual display"
        NSLog("[VirtualDisplayManager] DriverKit display creation failed: \(lastError ?? "Unknown error")")
        return nil
    }
    
    /// Destroy the current virtual display if one exists.
    func destroyVirtualDisplay() {
        guard isActive else { return }
        
        // If using DriverKit, disconnect the display
        if DRIVERKIT_ENABLED && isDriverKitAvailable {
            _ = driverKitClient?.disconnectDisplay()
        }
        
        displayID = nil
        displayFrame = nil
        isActive = false
        currentConfig = nil
        
        NSLog("[VirtualDisplayManager] Virtual display session ended")
    }
    
    /// Get the screen frame for the virtual display (for input coordinate mapping).
    func getVirtualDisplayFrame() -> CGRect? {
        guard isActive, let displayID = displayID else { return nil }
        
        // Query the current bounds from CoreGraphics
        let bounds = CGDisplayBounds(displayID)
        return bounds
    }
    
    // MARK: - Secondary Display Detection
    
    /// Find an existing secondary display that could be used for extend mode.
    private func findSecondaryDisplay() -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        
        guard displayCount > 1 else { return nil }
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        
        let mainDisplay = CGMainDisplayID()
        
        // Find a display that's not the main display
        for display in displays where display != mainDisplay {
            NSLog("[VirtualDisplayManager] Found secondary display: \(display)")
            return display
        }
        
        return nil
    }
    
    /// Use an existing secondary display for extend mode.
    private func useExistingDisplay(_ displayID: CGDirectDisplayID, config: ExtendedDisplayConfig) -> CGDirectDisplayID {
        self.displayID = displayID
        self.displayFrame = CGDisplayBounds(displayID)
        self.isActive = true
        self.currentConfig = config
        
        NSLog("[VirtualDisplayManager] Using existing secondary display: \(displayID), frame: \(displayFrame ?? .zero)")
        
        return displayID
    }
    
    // MARK: - Availability
    
    /// Check if virtual display creation is supported.
    var isSupported: Bool {
        // Supported if DriverKit is available or there's an existing secondary display
        if isDriverKitAvailable { return true }
        
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        return displayCount > 1
    }
    
    /// Get a description of why virtual display might not be available.
    var unavailableReason: String? {
        if isSupported {
            return nil
        }
        
        if !isDriverKitAvailable {
            return "Virtual display driver not installed. Click 'Install Driver' in the menu bar, then approve in System Settings > Privacy & Security."
        }
        
        return "No secondary display available"
    }
}

// MARK: - Helper Extension

extension VirtualDisplayManager {
    /// Calculate the optimal resolution for the virtual display based on iPad screen.
    static func optimalResolution(for iPadWidth: Int, iPadHeight: Int, scaleFactor: Double = 2.0) -> (width: Int, height: Int) {
        // iPad Pro 12.9" native: 2732 x 2048
        // iPad Pro 11" native: 2388 x 1668
        // For HiDPI, we typically want the logical resolution
        let logicalWidth = Int(Double(iPadWidth) / scaleFactor)
        let logicalHeight = Int(Double(iPadHeight) / scaleFactor)
        
        // Round to nearest 8 for encoder compatibility
        let alignedWidth = (logicalWidth + 7) & ~7
        let alignedHeight = (logicalHeight + 7) & ~7
        
        return (alignedWidth, alignedHeight)
    }
}

