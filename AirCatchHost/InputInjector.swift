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
// These are the NX key type values from IOKit/hidsystem/ev_keymap.h
// Only keeping the ones actually used by injectMediaKeyEvent
private let NX_KEYTYPE_SOUND_UP: Int32 = 0
private let NX_KEYTYPE_SOUND_DOWN: Int32 = 1
private let NX_KEYTYPE_MUTE: Int32 = 7
private let NX_KEYTYPE_PLAY: Int32 = 16
private let NX_KEYTYPE_NEXT: Int32 = 17
private let NX_KEYTYPE_PREVIOUS: Int32 = 18

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
            #if DEBUG
            AirCatchLog.debug(" Failed to create mouse down event")
            #endif
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
            #if DEBUG
            AirCatchLog.debug(" Failed to create mouse up event")
            #endif
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
            #if DEBUG
            AirCatchLog.debug(" Failed to create mouse drag event")
            #endif
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
            #if DEBUG
            AirCatchLog.debug(" Failed to create mouse move event")
            #endif
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
            #if DEBUG
            AirCatchLog.debug(" Failed to create right click events")
            #endif
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
        
        #if DEBUG
        AirCatchLog.debug(" Scroll at (\(point.x), \(point.y)) deltaX=\(deltaX) deltaY=\(deltaY)")
        #endif
        
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            #if DEBUG
            AirCatchLog.debug(" Failed to create scroll event")
            #endif
            return
        }
        event.post(tap: .cghidEventTap)
    }

    
    /// Check if accessibility permissions are granted.
    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Gets the current main screen frame (always queries fresh to handle resolution changes)
    private func currentMainScreenFrame() -> CGRect? {
        guard let screen = NSScreen.main else {
            #if DEBUG
            AirCatchLog.debug(" No main screen available")
            #endif
            return nil
        }
        return screen.frame
    }

    private func pointForNormalized(xPercent: Double, yPercent: Double) -> CGPoint? {
        guard let screenFrame = currentMainScreenFrame() else { return nil }
        // CGEvent uses global display coordinates with origin at top-left of primary display
        let x = xPercent * screenFrame.width
        let y = yPercent * screenFrame.height
        return CGPoint(x: x, y: y)
    }

    /// Converts normalized (0-1) coordinates to CGEvent screen coordinates.
    /// CGEvent uses a coordinate system with origin at the top-left of the primary display.
    /// For multi-monitor setups, secondary displays can have negative or offset origins.
    private func pointForNormalized(xPercent: Double, yPercent: Double, in screenFrame: CGRect) -> CGPoint {
        // screenFrame is in AppKit coordinates (origin at bottom-left of primary screen)
        // CGEvent coordinates have origin at top-left of primary screen
        // We need to convert properly
        
        guard let primaryScreen = NSScreen.screens.first else {
            // Fallback - assume simple case
            let x = screenFrame.origin.x + (xPercent * screenFrame.width)
            let y = screenFrame.origin.y + (yPercent * screenFrame.height)
            return CGPoint(x: x, y: y)
        }
        
        let primaryHeight = primaryScreen.frame.height
        
        // Calculate the position within the target screen (in AppKit coords)
        let appKitX = screenFrame.origin.x + (xPercent * screenFrame.width)
        // In AppKit, Y increases upward, but we want yPercent=0 to be at TOP of screen
        let appKitY = screenFrame.origin.y + screenFrame.height - (yPercent * screenFrame.height)
        
        // Convert from AppKit (bottom-left origin) to CG (top-left origin)
        let cgX = appKitX
        let cgY = primaryHeight - appKitY
        
        return CGPoint(x: cgX, y: cgY)
    }

    // MARK: - Keyboard Input
    
    /// Injects a keyboard event into the system.
    /// - Parameters:
    ///   - keyCode: macOS virtual key code
    ///   - modifiers: Modifier keys (shift, control, option, command)
    ///   - isKeyDown: true for key press, false for key release
    func injectKeyEvent(keyCode: UInt16, modifiers: KeyModifiers, isKeyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: isKeyDown) else {
            #if DEBUG
            AirCatchLog.debug(" Failed to create keyboard event for keyCode: \(keyCode)")
            #endif
            return
        }
        
        // Set modifier flags
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.capsLock) {
            flags.insert(.maskAlphaShift)
        }
        
        event.flags = flags
        event.post(tap: .cghidEventTap)
        
        #if DEBUG
        AirCatchLog.debug(" Injected key event: keyCode=\(keyCode) down=\(isKeyDown)")
        #endif
    }
    
    /// Injects a media key event (volume, brightness, play/pause, etc.) using HID system events.
    /// - Parameter mediaKey: The NX key type constant (e.g., NX_KEYTYPE_SOUND_UP = 0)
    nonisolated func injectMediaKeyEvent(mediaKey: Int32) {
        // Run on background thread to avoid blocking main thread
        DispatchQueue.global(qos: .userInteractive).async {
            // Use IOKit HID post for media keys - the proper macOS way
            func doKey(down: Bool) {
                let flags = NSEvent.ModifierFlags(rawValue: (down ? 0xa00 : 0xb00))
                let data1 = Int((Int(mediaKey) << 16) | ((down ? 0xa : 0xb) << 8))
                
                let event = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: NSPoint.zero,
                    modifierFlags: flags,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: data1,
                    data2: -1
                )
                event?.cgEvent?.post(tap: .cgSessionEventTap)
            }
            
            doKey(down: true)
            Thread.sleep(forTimeInterval: 0.05)
            doKey(down: false)
            
            #if DEBUG
            AirCatchLog.debug(" Injected media key event: mediaKey=\(mediaKey)")
            #endif
        }
    }

    /// Injects a text string directly as keyboard input.
    /// This is useful for paste operations or speech-to-text where constructing individual key events is inefficient.
    /// - Parameter text: The string to inject.
    func injectText(_ text: String) {
        // We support control characters used by incremental speech corrections.
        // - U+0008 BACKSPACE => deleteBackward (keyCode 51)
        // - U+007F DELETE    => deleteBackward (common in some streams)
        // Normal text is still injected via keyboardSetUnicodeString (chunked).

        func injectUnicodeText(_ unicodeText: String) {
            guard !unicodeText.isEmpty else { return }

            // Limited to ~20 UTF-16 code units per event by CGEventKeyboardSetUnicodeString.
            // We'll chunk by Character count as a conservative heuristic.
            let maxChunkSize = 20
            var startIndex = unicodeText.startIndex

            while startIndex < unicodeText.endIndex {
                let endIndex = unicodeText.index(startIndex, offsetBy: maxChunkSize, limitedBy: unicodeText.endIndex) ?? unicodeText.endIndex
                let chunk = String(unicodeText[startIndex..<endIndex])

                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }
                let utf16Chars = Array(chunk.utf16)
                event.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                event.post(tap: .cghidEventTap)

                if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                    upEvent.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
                    upEvent.post(tap: .cghidEventTap)
                }

                startIndex = endIndex
            }
        }

        func injectDeleteBackward(times: Int) {
            guard times > 0 else { return }
            for _ in 0..<times {
                injectKeyEvent(keyCode: 51, modifiers: [], isKeyDown: true)
                injectKeyEvent(keyCode: 51, modifiers: [], isKeyDown: false)
            }
        }

        var buffer = ""
        var pendingDeletes = 0

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x08, 0x7F:
                // Flush any normal text before deleting.
                injectUnicodeText(buffer)
                buffer.removeAll(keepingCapacity: true)
                pendingDeletes += 1
            default:
                if pendingDeletes > 0 {
                    injectDeleteBackward(times: pendingDeletes)
                    pendingDeletes = 0
                }
                buffer.unicodeScalars.append(scalar)
            }
        }

        injectUnicodeText(buffer)
        if pendingDeletes > 0 {
            injectDeleteBackward(times: pendingDeletes)
        }
        
        #if DEBUG
        AirCatchLog.debug(" Injected text length: \(text.count)")
        #endif
    }
}

