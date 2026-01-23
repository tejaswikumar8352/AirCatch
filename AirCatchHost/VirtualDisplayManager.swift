//
//  VirtualDisplayManager.swift
//  AirCatchHost
//
//  Creates a virtual display matching the iPad's resolution using CGVirtualDisplay.
//  Implements Apple Sidecar-like display behavior:
//  - Fixed 2x HiDPI scaling (Retina mode)
//  - Automatic iPad model detection with preset resolutions
//  - 4:3-ish aspect ratios matching iPad hardware
//  - No letterboxing when aspect ratios match
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - CGVirtualDisplay Private API Bridging

// CGVirtualDisplayDescriptor
@objc private class CGVirtualDisplayDescriptor: NSObject {
    @objc var queue: DispatchQueue?
    @objc var name: String?
    @objc var maxPixelsWide: Int = 0
    @objc var maxPixelsHigh: Int = 0
    @objc var sizeInMillimeters: CGSize = .zero
    @objc var serialNum: UInt32 = 0
    @objc var productID: UInt32 = 0
    @objc var vendorID: UInt32 = 0
    
    @objc var redPrimary: CGPoint = CGPoint(x: 0.6400, y: 0.3300)
    @objc var greenPrimary: CGPoint = CGPoint(x: 0.3000, y: 0.6000)
    @objc var bluePrimary: CGPoint = CGPoint(x: 0.1500, y: 0.0600)
    @objc var whitePoint: CGPoint = CGPoint(x: 0.3127, y: 0.3290)
    
    override init() {
        super.init()
    }
}

// CGVirtualDisplayMode
@objc private class CGVirtualDisplayMode: NSObject {
    @objc var width: Int = 0
    @objc var height: Int = 0
    @objc var refreshRate: Double = 60.0
    
    @objc init(width: Int, height: Int, refreshRate: Double = 60.0) {
        self.width = width
        self.height = height
        self.refreshRate = refreshRate
        super.init()
    }
}

// CGVirtualDisplaySettings
@objc private class CGVirtualDisplaySettings: NSObject {
    @objc var hiDPI: Bool = true
    @objc var modes: [CGVirtualDisplayMode] = []
    
    override init() {
        super.init()
    }
}

// CGVirtualDisplay
@objc private class CGVirtualDisplay: NSObject {
    @objc var displayID: CGDirectDisplayID = 0
    
    @objc init?(descriptor: CGVirtualDisplayDescriptor) {
        super.init()
        // Will be replaced by dynamic lookup
    }
    
    @objc func applySettings(_ settings: CGVirtualDisplaySettings) -> Bool {
        return false
    }
}

// MARK: - Virtual Display Manager

final class VirtualDisplayManager {
    static let shared = VirtualDisplayManager()
    
    private var virtualDisplay: AnyObject?
    private(set) var virtualDisplayID: CGDirectDisplayID?
    private(set) var isVirtualDisplayActive: Bool = false
    
    // Display configuration - stored in LOGICAL points (not pixels)
    // This matches Sidecar behavior: macOS renders at logical resolution,
    // iPad's 2x Retina display provides sharpness
    private(set) var displayWidth: Int = 0   // Logical width (points)
    private(set) var displayHeight: Int = 0  // Logical height (points)
    private(set) var displayFrame: CGRect = .zero
    
    // The detected iPad display preset (for logging/debugging)
    private(set) var detectedPreset: iPadDisplayPreset?
    
    // Physical size calculation for proper Mac UI scaling
    // Target ~110 PPI which is standard Mac display density (matches Sidecar)
    private let targetPPI: Double = 110.0
    
    private init() {}
    
    // MARK: - Public API
    
    /// Creates a virtual display using Sidecar-like resolution logic.
    ///
    /// **How Sidecar determines display properties:**
    /// 1. Mac queries iPad's hardware specifications during connection
    /// 2. Mac identifies iPad model and applies preset configuration
    /// 3. Fixed 2x HiDPI scaling is used (logical pixels = physical pixels / 2)
    /// 4. Resolution matches iPad's ~4:3 aspect ratio to avoid distortion
    ///
    /// **CRITICAL for sharpness:**
    /// - Virtual display is created at PHYSICAL resolution (e.g., 2388×1668)
    /// - With hiDPI=true, macOS provides a 2x HiDPI mode (1194×834 logical)
    /// - This gives true Retina rendering at full iPad resolution
    ///
    /// - Parameters:
    ///   - clientWidth: The client's screen width in PIXELS (physical resolution)
    ///   - clientHeight: The client's screen height in PIXELS (physical resolution)
    ///   - deviceModel: Optional device model string for better detection
    /// - Returns: The CGDirectDisplayID of the virtual display, or nil if creation failed
    @discardableResult
    func createVirtualDisplay(
        clientWidth: Int,
        clientHeight: Int,
        deviceModel: String? = nil
    ) -> CGDirectDisplayID? {
        // Don't create duplicate
        if isVirtualDisplayActive {
            AirCatchLog.info("Virtual display already active, destroying first")
            destroyVirtualDisplay()
        }
        
        // Detect iPad model and get Sidecar-like resolution preset
        let preset = iPadDisplayPreset.detect(
            deviceModel: deviceModel,
            physicalWidth: clientWidth,
            physicalHeight: clientHeight
        )
        self.detectedPreset = preset
        
        // Get both logical and physical resolutions
        let logicalRes = preset.logicalResolution
        let physicalRes = preset.physicalResolution
        
        // IMPORTANT: Create virtual display at PHYSICAL resolution
        // With hiDPI=true, macOS will offer HiDPI modes (logical = physical/2)
        // This gives us TRUE Retina rendering, not upscaled blurry output
        let physicalWidth = physicalRes.width
        let physicalHeight = physicalRes.height
        let logicalWidth = logicalRes.width
        let logicalHeight = logicalRes.height
        
        // Calculate physical size for ~220 PPI (Retina density)
        // This is 2x the standard 110 PPI, matching iPad's actual pixel density
        let retinaTargetPPI: Double = 220.0
        let widthMM = (Double(physicalWidth) / retinaTargetPPI) * 25.4
        let heightMM = (Double(physicalHeight) / retinaTargetPPI) * 25.4
        
        AirCatchLog.info("🖥️ Sidecar-like display: \(preset.displayName)")
        AirCatchLog.info("   iPad physical: \(clientWidth)×\(clientHeight) pixels")
        AirCatchLog.info("   Creating at: \(physicalWidth)×\(physicalHeight) pixels (FULL resolution)")
        AirCatchLog.info("   HiDPI logical: \(logicalWidth)×\(logicalHeight) points (2x Retina)")
        AirCatchLog.info("   Aspect ratio: \(String(format: "%.2f", preset.aspectRatio)):1")
        AirCatchLog.info("   Physical size: \(Int(widthMM))×\(Int(heightMM))mm @ \(Int(retinaTargetPPI)) PPI")
        
        // Create virtual display at PHYSICAL resolution with HiDPI enabled
        // macOS will then offer a HiDPI mode that renders at full resolution
        if let displayID = createCGVirtualDisplay(
            width: physicalWidth,
            height: physicalHeight,
            widthMM: widthMM,
            heightMM: heightMM,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight
        ) {
            virtualDisplayID = displayID
            // Store LOGICAL dimensions (what macOS UI renders at)
            displayWidth = logicalWidth
            displayHeight = logicalHeight
            isVirtualDisplayActive = true
            
            // Wait for display to appear, then set the HiDPI mode
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.updateDisplayFrame()
                // Select the HiDPI mode at logical resolution
                self.setHiDPIMode(displayID: displayID, logicalWidth: logicalWidth, logicalHeight: logicalHeight)
            }
            
            AirCatchLog.info("✅ Virtual display created: ID=\(displayID)")
            AirCatchLog.info("   Physical: \(physicalWidth)×\(physicalHeight), HiDPI: \(logicalWidth)×\(logicalHeight)")
            return displayID
        }
        
        AirCatchLog.error("❌ Failed to create virtual display")
        return nil
    }
    
    /// Sets the display to the HiDPI mode at the specified logical resolution
    private func setHiDPIMode(displayID: CGDirectDisplayID, logicalWidth: Int, logicalHeight: Int) {
        // Get all display modes including HiDPI
        let options: [CFString: Any] = [kCGDisplayShowDuplicateLowResolutionModes: true]
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, options as CFDictionary) as? [CGDisplayMode] else {
            AirCatchLog.info("Could not get display modes")
            return
        }
        
        AirCatchLog.info("Available modes for display \(displayID):")
        
        var bestHiDPIMode: CGDisplayMode? = nil
        var bestNonHiDPIMode: CGDisplayMode? = nil
        
        for mode in modes {
            let isHiDPI = mode.pixelWidth > mode.width
            let modeDesc = "\(mode.width)×\(mode.height) (pixels: \(mode.pixelWidth)×\(mode.pixelHeight)) \(isHiDPI ? "HiDPI" : "")"
            AirCatchLog.info("   - \(modeDesc)")
            
            // Look for HiDPI mode at our logical resolution
            if mode.width == logicalWidth && mode.height == logicalHeight && isHiDPI {
                bestHiDPIMode = mode
                AirCatchLog.info("   ✓ Found target HiDPI mode!")
            }
            // Fallback: non-HiDPI at logical resolution
            else if mode.width == logicalWidth && mode.height == logicalHeight && !isHiDPI {
                bestNonHiDPIMode = mode
            }
        }
        
        // Prefer HiDPI mode, fall back to non-HiDPI
        let targetMode = bestHiDPIMode ?? bestNonHiDPIMode
        
        if let mode = targetMode {
            let isHiDPI = mode.pixelWidth > mode.width
            let result = CGDisplaySetDisplayMode(displayID, mode, nil)
            if result == .success {
                AirCatchLog.info("✅ Set display to \(mode.width)×\(mode.height) \(isHiDPI ? "(HiDPI - SHARP!)" : "(non-HiDPI)")")
                if isHiDPI {
                    AirCatchLog.info("   Rendering at \(mode.pixelWidth)×\(mode.pixelHeight) pixels for true Retina quality")
                }
            } else {
                AirCatchLog.error("Failed to set display mode: \(result)")
            }
        } else {
            AirCatchLog.info("Target mode \(logicalWidth)×\(logicalHeight) not found, using default")
        }
    }
    
    /// Legacy method - kept for compatibility
    private func setExactResolutionMode(displayID: CGDirectDisplayID, width: Int, height: Int) {
        setHiDPIMode(displayID: displayID, logicalWidth: width, logicalHeight: height)
    }
    
    /// Destroys the virtual display and cleans up resources.
    func destroyVirtualDisplay() {
        guard isVirtualDisplayActive else { return }
        
        virtualDisplay = nil
        virtualDisplayID = nil
        displayWidth = 0
        displayHeight = 0
        displayFrame = .zero
        isVirtualDisplayActive = false
        
        AirCatchLog.info("Virtual display destroyed")
    }
    
    /// Returns the bounds of the virtual display for screen capture.
    func getDisplayBounds() -> CGRect {
        guard let displayID = virtualDisplayID else {
            return CGDisplayBounds(CGMainDisplayID())
        }
        return CGDisplayBounds(displayID)
    }
    
    /// Returns the frame of the virtual display, or nil if not active.
    var virtualDisplayFrame: CGRect? {
        guard isVirtualDisplayActive, let displayID = virtualDisplayID else {
            return nil
        }
        return CGDisplayBounds(displayID)
    }
    
    /// Converts normalized touch coordinates (0-1) to virtual display screen coordinates.
    func convertTouchToScreen(normalizedX: Double, normalizedY: Double) -> CGPoint {
        let bounds = getDisplayBounds()
        return CGPoint(
            x: bounds.origin.x + (normalizedX * bounds.width),
            y: bounds.origin.y + (normalizedY * bounds.height)
        )
    }
    
    // MARK: - Private Implementation
    
    private func createCGVirtualDisplay(
        width: Int,
        height: Int,
        widthMM: Double,
        heightMM: Double,
        logicalWidth: Int,
        logicalHeight: Int
    ) -> CGDirectDisplayID? {
        // Load CGVirtualDisplay class dynamically
        guard let virtualDisplayClass = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
            AirCatchLog.error("CGVirtualDisplay class not found - requires macOS 14+")
            return nil
        }
        
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type else {
            AirCatchLog.error("CGVirtualDisplayDescriptor class not found")
            return nil
        }
        
        guard let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type else {
            AirCatchLog.error("CGVirtualDisplaySettings class not found")
            return nil
        }
        
        guard let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type else {
            AirCatchLog.error("CGVirtualDisplayMode class not found")
            return nil
        }
        
        // Create descriptor with PHYSICAL resolution as max
        let descriptor = descriptorClass.init()
        descriptor.setValue(DispatchQueue.main, forKey: "queue")
        descriptor.setValue("AirCatch Virtual Display", forKey: "name")
        descriptor.setValue(width, forKey: "maxPixelsWide")   // Physical width
        descriptor.setValue(height, forKey: "maxPixelsHigh")  // Physical height
        descriptor.setValue(CGSize(width: widthMM, height: heightMM), forKey: "sizeInMillimeters")
        descriptor.setValue(UInt32(12345), forKey: "serialNum")
        descriptor.setValue(UInt32(0xAC01), forKey: "productID")  // "AC" for AirCatch
        descriptor.setValue(UInt32(0x1234), forKey: "vendorID")
        
        // Create the virtual display
        let initSelector = NSSelectorFromString("initWithDescriptor:")
        guard descriptor.responds(to: initSelector) || virtualDisplayClass.instancesRespond(to: initSelector) else {
            // Try alternate initialization
            return createVirtualDisplayAlternate(
                displayClass: virtualDisplayClass,
                descriptorClass: descriptorClass,
                settingsClass: settingsClass,
                modeClass: modeClass,
                width: width,
                height: height,
                widthMM: widthMM,
                heightMM: heightMM,
                logicalWidth: logicalWidth,
                logicalHeight: logicalHeight
            )
        }
        
        let display = virtualDisplayClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
        guard let virtualDisplay = display?.perform(initSelector, with: descriptor)?.takeUnretainedValue() as? NSObject else {
            AirCatchLog.error("Failed to init CGVirtualDisplay with descriptor")
            return nil
        }
        
        // Create settings with HiDPI mode ENABLED
        let settings = settingsClass.init()
        settings.setValue(true, forKey: "hiDPI")  // CRITICAL: Enable HiDPI
        
        // Create multiple modes:
        // 1. HiDPI mode at logical resolution (will render at 2x = physical)
        // 2. Non-HiDPI mode at physical resolution (for compatibility)
        var modes: [NSObject] = []
        
        // Mode 1: HiDPI at logical resolution (preferred)
        // This is the Sidecar-like mode - logical 1194×834 renders at 2388×1668 pixels
        if let hiDPIMode = modeClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject {
            hiDPIMode.setValue(logicalWidth, forKey: "width")
            hiDPIMode.setValue(logicalHeight, forKey: "height")
            hiDPIMode.setValue(60.0, forKey: "refreshRate")
            modes.append(hiDPIMode)
            AirCatchLog.info("Adding HiDPI mode: \(logicalWidth)×\(logicalHeight) @ 60Hz (renders at \(width)×\(height))")
        }
        
        // Mode 2: Full physical resolution (non-HiDPI fallback)
        if let physicalMode = modeClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject {
            physicalMode.setValue(width, forKey: "width")
            physicalMode.setValue(height, forKey: "height")
            physicalMode.setValue(60.0, forKey: "refreshRate")
            modes.append(physicalMode)
            AirCatchLog.info("Adding physical mode: \(width)×\(height) @ 60Hz")
        }
        
        settings.setValue(modes, forKey: "modes")
        
        // Apply settings
        let applySelector = NSSelectorFromString("applySettings:")
        if virtualDisplay.responds(to: applySelector) {
            _ = virtualDisplay.perform(applySelector, with: settings)
        }
        
        // Get display ID
        if let displayID = virtualDisplay.value(forKey: "displayID") as? CGDirectDisplayID, displayID != 0 {
            self.virtualDisplay = virtualDisplay
            return displayID
        }
        
        return nil
    }
    
    private func createVirtualDisplayAlternate(
        displayClass: NSObject.Type,
        descriptorClass: NSObject.Type,
        settingsClass: NSObject.Type,
        modeClass: NSObject.Type,
        width: Int,
        height: Int,
        widthMM: Double,
        heightMM: Double,
        logicalWidth: Int,
        logicalHeight: Int
    ) -> CGDirectDisplayID? {
        // Alternative creation method for different macOS versions
        AirCatchLog.info("Trying alternate virtual display creation method")
        
        // Create using property-based initialization
        let descriptor = descriptorClass.init()
        
        // Set all properties using KVC - use PHYSICAL resolution for max pixels
        let properties: [String: Any] = [
            "queue": DispatchQueue.main,
            "name": "AirCatch Virtual Display",
            "maxPixelsWide": width,      // Physical width
            "maxPixelsHigh": height,     // Physical height
            "sizeInMillimeters": CGSize(width: widthMM, height: heightMM),
            "serialNum": UInt32(12345),
            "productID": UInt32(0xAC01),
            "vendorID": UInt32(0x1234)
        ]
        
        for (key, value) in properties {
            if descriptor.responds(to: NSSelectorFromString(key)) || 
               descriptor.responds(to: NSSelectorFromString("set\(key.prefix(1).uppercased())\(key.dropFirst()):")) {
                descriptor.setValue(value, forKey: key)
            }
        }
        
        // Try to create display with descriptor
        if let display = try? displayClass.perform(NSSelectorFromString("displayWithDescriptor:"), with: descriptor)?.takeUnretainedValue() as? NSObject {
            if let displayID = display.value(forKey: "displayID") as? CGDirectDisplayID, displayID != 0 {
                
                // Apply settings with HiDPI enabled
                let settings = settingsClass.init()
                settings.setValue(true, forKey: "hiDPI")
                
                // Add both HiDPI and physical modes
                var modes: [NSObject] = []
                
                // HiDPI mode at logical resolution
                let hiDPIMode = modeClass.init()
                hiDPIMode.setValue(logicalWidth, forKey: "width")
                hiDPIMode.setValue(logicalHeight, forKey: "height")
                hiDPIMode.setValue(60.0, forKey: "refreshRate")
                modes.append(hiDPIMode)
                
                // Physical mode
                let physicalMode = modeClass.init()
                physicalMode.setValue(width, forKey: "width")
                physicalMode.setValue(height, forKey: "height")
                physicalMode.setValue(60.0, forKey: "refreshRate")
                modes.append(physicalMode)
                
                settings.setValue(modes, forKey: "modes")
                
                _ = try? display.perform(NSSelectorFromString("applySettings:"), with: settings)
                
                self.virtualDisplay = display
                return displayID
            }
        }
        
        return nil
    }
    
    private func updateDisplayFrame() {
        guard let displayID = virtualDisplayID else { return }
        displayFrame = CGDisplayBounds(displayID)
        AirCatchLog.info("Virtual display frame updated: \(displayFrame)")
    }
}

// MARK: - Resolution Helper

extension VirtualDisplayManager {
    /// The logical width (same as displayWidth since we create at logical resolution)
    var logicalWidth: Int {
        return displayWidth
    }
    
    var logicalHeight: Int {
        return displayHeight
    }
    
    /// Returns the scaling factor (2.0 for true HiDPI Retina)
    var scaleFactor: CGFloat {
        return 2.0
    }
    
    /// Returns the physical (pixel) resolution for video encoding
    /// This is 2x the logical resolution (Sidecar-like HiDPI)
    var physicalWidth: Int {
        return displayWidth * 2
    }
    
    var physicalHeight: Int {
        return displayHeight * 2
    }
    
    /// Returns the detected iPad preset name (for debugging)
    var presetName: String {
        return detectedPreset?.displayName ?? "Unknown"
    }
}