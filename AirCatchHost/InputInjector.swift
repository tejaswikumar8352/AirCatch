//
//  InputInjector.swift
//  AirCatchHost
//
//  Handles injection of mouse/keyboard events using CGEvent.
//

import Foundation
import CoreGraphics
import AppKit
import IOKit.hidsystem

// MARK: - NX Media Key Constants
// These are the correct NX key type values from IOKit/hidsystem/ev_keymap.h
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_BRIGHTNESS_UP: Int32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: Int32 = 3
private let NX_KEYTYPE_CAPS_LOCK: Int32 = 4
private let NX_KEYTYPE_HELP: Int32 = 5
private let NX_POWER_KEY: Int32 = 6
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_NUM_LOCK: Int32 = 10
private let NX_KEYTYPE_CONTRAST_UP: Int32 = 11
private let NX_KEYTYPE_CONTRAST_DOWN: Int32 = 12
private let NX_KEYTYPE_EJECT: Int32 = 14
private let NX_KEYTYPE_VIDMIRROR: Int32 = 15
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18
private let NX_KEYTYPE_FAST: Int32 = 19
private let NX_KEYTYPE_REWIND: Int32 = 20
private let NX_KEYTYPE_ILLUMINATION_UP: Int32 = 21
private let NX_KEYTYPE_ILLUMINATION_DOWN: Int32 = 22
private let NX_KEYTYPE_ILLUMINATION_TOGGLE: Int32 = 23

/// Injects mouse and keyboard events into the system.
@MainActor
final class InputInjector {
    static let shared = InputInjector()
    
    private init() {}
    
    /// Converts normalized coordinates (0.0-1.0) to screen coordinates and performs a click.
    /// - Parameters:
    ///   - xPercent: Normalized X coordinate (0.0 = left, 1.0 = right)
    ///   - yPercent: Normalized Y coordinate (0.0 = top, 1.0 = bottom)
    ///   - eventType: The type of touch event to simulate
    func injectClick(xPercent: Double, yPercent: Double, eventType: TouchEventType) {
        guard let point = pointForNormalized(xPercent: xPercent, yPercent: yPercent) else { return }
        
        switch eventType {
        case .began:
            injectMouseDown(at: point)
        case .moved:
            injectMouseDrag(to: point)
        case .ended:
            injectMouseUp(at: point)
        case .cancelled:
            injectMouseUp(at: point)
        case .rightClick:
            injectRightClick(at: point)
        case .doubleClick:
            injectDoubleClick(at: point)
        case .dragBegan:
            injectMouseDown(at: point)
        case .dragMoved:
            injectMouseDrag(to: point)
        case .dragEnded:
            injectMouseUp(at: point)
        }
    }
    
    /// Simulates a single left click at the given screen coordinate.
    func injectSingleClick(at point: CGPoint) {
        injectMouseDown(at: point)
        injectMouseUp(at: point)
    }
    
    /// Simulates a mouse down event.
    private func injectMouseDown(at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            NSLog("[InputInjector] Failed to create mouse down event")
            return
        }
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a mouse up event.
    private func injectMouseUp(at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            NSLog("[InputInjector] Failed to create mouse up event")
            return
        }
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a mouse drag event.
    private func injectMouseDrag(to point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            NSLog("[InputInjector] Failed to create mouse drag event")
            return
        }
        event.post(tap: .cghidEventTap)
    }
    
    /// Moves the mouse cursor without clicking.
    func moveMouse(to point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            NSLog("[InputInjector] Failed to create mouse move event")
            return
        }
        event.post(tap: .cghidEventTap)
    }

    /// Moves the mouse cursor using normalized coordinates (0..1).
    func moveMouse(xPercent: Double, yPercent: Double) {
        guard let point = pointForNormalized(xPercent: xPercent, yPercent: yPercent) else { return }
        moveMouse(to: point)
    }

    /// Moves the mouse cursor using normalized coordinates (0..1) within a specific screen frame.
    func moveMouse(xPercent: Double, yPercent: Double, in screenFrame: CGRect) {
        let point = pointForNormalized(xPercent: xPercent, yPercent: yPercent, in: screenFrame)
        moveMouse(to: point)
    }

    /// Converts normalized coordinates (0.0-1.0) within a specific screen frame and performs a click/drag.
    func injectClick(xPercent: Double, yPercent: Double, eventType: TouchEventType, in screenFrame: CGRect) {
        let point = pointForNormalized(xPercent: xPercent, yPercent: yPercent, in: screenFrame)

        switch eventType {
        case .began:
            injectMouseDown(at: point)
        case .moved:
            injectMouseDrag(to: point)
        case .ended:
            injectMouseUp(at: point)
        case .cancelled:
            injectMouseUp(at: point)
        case .rightClick:
            injectRightClick(at: point)
        case .doubleClick:
            injectDoubleClick(at: point)
        case .dragBegan:
            injectMouseDown(at: point)
        case .dragMoved:
            injectMouseDrag(to: point)
        case .dragEnded:
            injectMouseUp(at: point)
        }
    }
    
    /// Simulates a right click.
    func injectRightClick(at point: CGPoint) {
        guard let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        ),
        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else {
            NSLog("[InputInjector] Failed to create right click events")
            return
        }
        
        downEvent.post(tap: .cghidEventTap)
        upEvent.post(tap: .cghidEventTap)
    }
    
    /// Simulates a double click.
    func injectDoubleClick(at point: CGPoint) {
        // macOS requires the click count to be set for double clicks to be recognized properly by some apps.
        // We simulate: Down(1) -> Up(1) -> Down(2) -> Up(2)
        
        injectClickEvent(at: point, type: .leftMouseDown, count: 1)
        injectClickEvent(at: point, type: .leftMouseUp, count: 1)
        
        injectClickEvent(at: point, type: .leftMouseDown, count: 2)
        injectClickEvent(at: point, type: .leftMouseUp, count: 2)
    }
    
    /// Injects a click at the current mouse position (for trackpad-style input).
    func injectClickAtCurrentPosition(eventType: TouchEventType) {
        let currentPoint = NSEvent.mouseLocation
        // Convert from AppKit coordinates (origin bottom-left) to CG coordinates (origin top-left)
        guard let screen = NSScreen.main else { return }
        let cgPoint = CGPoint(x: currentPoint.x, y: screen.frame.height - currentPoint.y)
        
        switch eventType {
        case .began:
            injectClickEvent(at: cgPoint, type: .leftMouseDown, count: 1)
        case .ended:
            injectClickEvent(at: cgPoint, type: .leftMouseUp, count: 1)
        case .cancelled:
            injectClickEvent(at: cgPoint, type: .leftMouseUp, count: 1)
        case .rightClick:
            injectRightClickEvent(at: cgPoint, type: .rightMouseDown, count: 1)
            injectRightClickEvent(at: cgPoint, type: .rightMouseUp, count: 1)
        case .doubleClick:
            injectClickEvent(at: cgPoint, type: .leftMouseDown, count: 1)
            injectClickEvent(at: cgPoint, type: .leftMouseUp, count: 1)
            injectClickEvent(at: cgPoint, type: .leftMouseDown, count: 2)
            injectClickEvent(at: cgPoint, type: .leftMouseUp, count: 2)
        case .moved:
            break // No action for moved
        case .dragBegan:
            // Mouse down to start drag
            injectClickEvent(at: cgPoint, type: .leftMouseDown, count: 1)
        case .dragEnded:
            // Mouse up to end drag
            injectClickEvent(at: cgPoint, type: .leftMouseUp, count: 1)
        case .dragMoved:
            break // Handled by dragMouseRelative
        }
    }
    
    /// Drags the mouse by a relative delta (mouse button held down).
    func dragMouseRelative(deltaX: Double, deltaY: Double) {
        let currentLocation = NSEvent.mouseLocation
        guard let primaryScreen = NSScreen.screens.first else { return }
        
        let sensitivity: Double = 1.5
        let newAppKitX = currentLocation.x + (deltaX * sensitivity)
        let newAppKitY = currentLocation.y - (deltaY * sensitivity)
        
        let allScreensBounds = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }
        let clampedX = max(allScreensBounds.minX, min(allScreensBounds.maxX, newAppKitX))
        let clampedY = max(allScreensBounds.minY, min(allScreensBounds.maxY, newAppKitY))
        
        let primaryHeight = primaryScreen.frame.height
        let cgPoint = CGPoint(x: clampedX, y: primaryHeight - clampedY)
        
        // Create a mouse drag event (left button held)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) else { return }
        
        event.post(tap: .cghidEventTap)
    }
    
    private func injectClickEvent(at point: CGPoint, type: CGEventType, count: Int64) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        
        event.setIntegerValueField(.mouseEventClickState, value: count)
        event.post(tap: .cghidEventTap)
    }
    
    private func injectRightClickEvent(at point: CGPoint, type: CGEventType, count: Int64) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else { return }
        
        event.setIntegerValueField(.mouseEventClickState, value: count)
        event.post(tap: .cghidEventTap)
    }
    
    /// Simulates a scroll event.
    func injectScroll(deltaX: Int32, deltaY: Int32, at point: CGPoint) {
        // First move mouse to position
        moveMouse(to: point)
        
        NSLog("[InputInjector] Scroll at (\(point.x), \(point.y)) deltaX=\(deltaX) deltaY=\(deltaY)")
        
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            NSLog("[InputInjector] Failed to create scroll event")
            return
        }
        event.post(tap: .cghidEventTap)
    }

    /// Types a unicode string (does not require keycode mapping).
    func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)

        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            NSLog("[InputInjector] Failed to create keyboard events")
            return
        }

        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Presses a macOS virtual key code (e.g. Return=36, Delete=51).
    func pressKey(virtualKey: CGKeyCode) {
        pressKey(virtualKey: virtualKey, shift: false, control: false, option: false, command: false)
    }

    /// Presses a macOS virtual key code with modifier keys.
    func pressKey(virtualKey: CGKeyCode, shift: Bool, control: Bool, option: Bool, command: Bool) {
        // Check if this is a media key (F1-F12 with special functions)
        if let mediaKey = mediaKeyForVirtualKey(virtualKey) {
            postMediaKey(mediaKey)
            return
        }
        
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: false) else {
            NSLog("[InputInjector] Failed to create key press events")
            return
        }
        
        var flags: CGEventFlags = []
        if shift { flags.insert(.maskShift) }
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        if command { flags.insert(.maskCommand) }
        
        down.flags = flags
        up.flags = flags
        
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    // MARK: - Media Keys (NX Key Codes)
    
    /// Maps virtual key codes to NX media key codes
    private func mediaKeyForVirtualKey(_ virtualKey: CGKeyCode) -> Int32? {
        NSLog("[InputInjector] mediaKeyForVirtualKey called with: \(virtualKey)")
        switch virtualKey {
        case 122: return NX_KEYTYPE_BRIGHTNESS_DOWN  // F1 - Brightness Down
        case 120: return NX_KEYTYPE_BRIGHTNESS_UP    // F2 - Brightness Up
        case 99:  return nil  // F3 - Mission Control (use Ctrl+Up or key code)
        case 118: return nil  // F4 - Spotlight (use Cmd+Space)
        case 96:  return nil  // F5 - Dictation
        case 97:  return nil  // F6 - Do Not Disturb
        case 98:  return NX_KEYTYPE_PREVIOUS         // F7 - Previous Track
        case 100: return NX_KEYTYPE_PLAY             // F8 - Play/Pause
        case 101: return NX_KEYTYPE_NEXT             // F9 - Next Track
        case 109: return NX_KEYTYPE_MUTE             // F10 - Mute
        case 103: return NX_KEYTYPE_SOUND_DOWN       // F11 - Volume Down
        case 111: return NX_KEYTYPE_SOUND_UP         // F12 - Volume Up
        case 53:  return nil  // Escape - handle as regular key
        default:
            NSLog("[InputInjector] No media key mapping for virtualKey: \(virtualKey)")
            return nil
        }
    }
    
    /// Posts a media key event (like volume, brightness, play/pause)
    private func postMediaKey(_ key: Int32) {
        NSLog("[InputInjector] Posting media key: \(key)")
        func doKey(down: Bool) {
            let flags: UInt32 = (down ? 0xa00 : 0xb00)
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((key << 16) | Int32(flags)),
                data2: -1
            ) else {
                NSLog("[InputInjector] Failed to create media key event")
                return
            }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }
    
    /// Check if accessibility permissions are granted.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Gets the current main screen frame (always queries fresh to handle resolution changes)
    private func currentMainScreenFrame() -> CGRect? {
        guard let screen = NSScreen.main else {
            NSLog("[InputInjector] No main screen available")
            return nil
        }
        return screen.frame
    }

    private func pointForNormalized(xPercent: Double, yPercent: Double) -> CGPoint? {
        guard let screenFrame = currentMainScreenFrame() else { return nil }
        let x = xPercent * screenFrame.width
        let y = yPercent * screenFrame.height
        return CGPoint(x: x, y: y)
    }

    private func pointForNormalized(xPercent: Double, yPercent: Double, in screenFrame: CGRect) -> CGPoint {
        let x = screenFrame.origin.x + (xPercent * screenFrame.width)
        let y = screenFrame.origin.y + (yPercent * screenFrame.height)
        return CGPoint(x: x, y: y)
    }

    /// Moves the mouse cursor by a relative delta amount (for trackpad mode)
    func moveMouseRelative(deltaX: Double, deltaY: Double) {
        let currentLocation = NSEvent.mouseLocation
        
        // NSEvent.mouseLocation is in AppKit global coordinates (origin at bottom-left of primary screen)
        // Apply delta directly - trackpad sensitivity multiplier for comfortable movement
        let sensitivity: Double = 1.5  // Adjust for trackpad feel
        let newAppKitX = currentLocation.x + (deltaX * sensitivity)
        let newAppKitY = currentLocation.y - (deltaY * sensitivity)  // Subtract because AppKit Y is flipped vs touch
        
        // Get total screen bounds (all screens) in AppKit coordinates
        let allScreensBounds = NSScreen.screens.reduce(CGRect.zero) { $0.union($1.frame) }
        
        // Clamp to screen bounds (AppKit coordinates)
        let clampedX = max(allScreensBounds.minX, min(allScreensBounds.maxX, newAppKitX))
        let clampedY = max(allScreensBounds.minY, min(allScreensBounds.maxY, newAppKitY))
        
        // In AppKit, the origin (0,0) is at the bottom-left of the PRIMARY screen.
        // In CoreGraphics/Quartz, the origin (0,0) is at the top-left of the PRIMARY screen.
        // The primary screen is the one containing the menu bar (NSScreen.screens[0]).
        // For CG conversion: cgY = primaryScreenHeight - appKitY
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryHeight = primaryScreen.frame.height
        let cgPoint = CGPoint(x: clampedX, y: primaryHeight - clampedY)
        
        moveMouse(to: cgPoint)
    }
}

