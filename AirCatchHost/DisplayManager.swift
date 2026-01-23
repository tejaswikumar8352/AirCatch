//
//  DisplayManager.swift
//  AirCatchHost
//
//  Manages the Host display resolution to match the Client's aspect ratio.
//  This simulates a "Virtual Display" experience by eliminating black bars on the Client side.
//  Prioritizes HiDPI modes to ensure the Host UI remains readable (User Space size vs Raw Pixels).
//

import Foundation
import CoreGraphics
import AppKit

final class DisplayManager {
    static let shared = DisplayManager()
    
    private var originalMode: CGDisplayMode?
    private var isResolutionChanged = false
    
    private let displayID = CGMainDisplayID()
    
    private init() {}
    
    /// Switches the main display to a resolution that matches the client's aspect ratio.
    /// Prioritizes HiDPI modes where the "Points" size is close to the client's logical size,
    /// but the "Pixels" count is high (Retina).
    func matchClientResolution(clientWidth: Int, clientHeight: Int) {
        guard !isResolutionChanged else { return } // Already executed
        
        // Save original mode to restore later
        guard let current = CGDisplayCopyDisplayMode(displayID) else {
            AirCatchLog.error("Failed to get current display mode")
            return
        }
        originalMode = current
        
        // Check if current mode already matches client aspect ratio well
        let currentAspect = Double(current.width) / Double(current.height)
        let targetAspect = Double(clientWidth) / Double(clientHeight)
        if abs(currentAspect - targetAspect) < 0.02 {
            AirCatchLog.info("Current resolution already matches client aspect ratio")
            return
        }
        
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            AirCatchLog.error("Failed to list display modes")
            return
        }
        
        // Find best match:
        // 1. Must match aspect ratio (within small tolerance)
        // 2. Must be HiDPI (if available) - Critical for readable UI
        // 3. Prefer highest resolution among matches
        
        // Sort modes by preference:
        // 1. Better aspect ratio match (closest to 0 diff)
        // 2. HiDPI (Points < Pixels) is better
        // 3. Higher resolution is better
        
        let sortedModes = modes.sorted { (m1, m2) -> Bool in
            let w1 = Double(m1.width)
            let h1 = Double(m1.height)
            let a1 = w1 / h1
            let diff1 = abs(a1 - targetAspect)
            let isHiDPI1 = m1.pixelWidth > m1.width
            
            let w2 = Double(m2.width)
            let h2 = Double(m2.height)
            let a2 = w2 / h2
            let diff2 = abs(a2 - targetAspect)
            let isHiDPI2 = m2.pixelWidth > m2.width
            
            // If aspect ratio difference is significant, prefer the closer one
            if abs(diff1 - diff2) > 0.05 {
                return diff1 < diff2
            }
            
            // If aspect ratios are similar, prefer HiDPI
            if isHiDPI1 != isHiDPI2 {
                return isHiDPI1
            }
            
            // Finally prefer higher resolution
            return m1.width > m2.width
        }
        
        let bestMode = sortedModes.first
        
        guard let mode = bestMode else {
            AirCatchLog.info("No matching resolution found for aspect ratio \(targetAspect)")
            return
        }
        
        AirCatchLog.info("Switching resolution to: \(mode.width)x\(mode.height) (Points) / \(mode.pixelWidth)x\(mode.pixelHeight) (Pixels)")
        
        // Perform the switch
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayWithDisplayMode(config, displayID, mode, nil)
        
        let error = CGCompleteDisplayConfiguration(config, .permanently)
        if error == .success {
            isResolutionChanged = true
        } else {
            AirCatchLog.error("Resolution switch failed: \(error)")
        }
    }
    
    /// Restores the display to its original resolution.
    func restoreOriginalResolution() {
        guard isResolutionChanged, let original = originalMode else { return }
        
        AirCatchLog.info("Restoring original resolution: \(original.width)x\(original.height)")
        
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayWithDisplayMode(config, displayID, original, nil)
        CGCompleteDisplayConfiguration(config, .permanently)
        
        isResolutionChanged = false
        originalMode = nil
    }
}
