//
//  MouseInputView.swift
//  AirCatchClient
//
//  Unified input handler for Touch and Mouse events.
//

import SwiftUI
import UIKit

struct MouseInputView: UIViewRepresentable {
    @EnvironmentObject var clientManager: ClientManager
    
    func makeUIView(context: Context) -> MouseHandlingView {
        let view = MouseHandlingView()
        view.clientManager = clientManager
        view.isMultipleTouchEnabled = true
        return view
    }
    
    func updateUIView(_ uiView: MouseHandlingView, context: Context) {
        uiView.clientManager = clientManager
    }
}


class MouseHandlingView: UIView, UIGestureRecognizerDelegate {
    weak var clientManager: ClientManager?
    private var twoFingerPanGesture: UIPanGestureRecognizer?
    private var activeTouchCount: Int = 0

    // PERFORMANCE: Throttle continuous events to 0.008s (~120Hz max).
    private var lastMoveTime: CFTimeInterval = 0
    private var lastPanTime: CFTimeInterval = 0
    private var lastPinchTime: CFTimeInterval = 0
    private let localThrottleInterval: CFTimeInterval = 0.008

    private func activeThrottleInterval() -> CFTimeInterval {
        localThrottleInterval
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    private func setupGestures() {
        // 1. Right Click (Secondary Button)
        let rightClick = UITapGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
        rightClick.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        rightClick.buttonMaskRequired = .secondary
        addGestureRecognizer(rightClick)

        // 2. Double Tap (Double Click)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // 3. Long Press (Touch Right Click)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.6
        addGestureRecognizer(longPress)

        // 4. Two-Finger Pan (Scroll) — also receives trackpad/mouse-wheel scroll
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        twoFingerPan.allowedScrollTypesMask = [.discrete, .continuous]
        twoFingerPan.delegate = self
        addGestureRecognizer(twoFingerPan)
        self.twoFingerPanGesture = twoFingerPan

        // 5. Pinch (Zoom)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow two-finger pan to work simultaneously
        return true
    }
    
    // MARK: - Touch Handling (Primary Pointer / Finger)
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        activeTouchCount = event?.allTouches?.count ?? touches.count
        // Only forward single-finger touches for click/drag
        if activeTouchCount == 1 {
            forwardTouch(touches, phase: .began)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        activeTouchCount = event?.allTouches?.count ?? touches.count
        // Only forward single-finger touches for drag
        // PERFORMANCE: Throttle to 120Hz to reduce event flood on ProMotion displays
        if activeTouchCount == 1 {
            let now = CACurrentMediaTime()
            if now - lastMoveTime >= activeThrottleInterval() {
                lastMoveTime = now
                forwardTouch(touches, phase: .moved)
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let remainingTouches = (event?.allTouches?.count ?? 1) - touches.count
        // Only forward if this was a single-finger interaction
        if activeTouchCount == 1 {
            forwardTouch(touches, phase: .ended)
        }
        activeTouchCount = max(0, remainingTouches)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if activeTouchCount == 1 {
            forwardTouch(touches, phase: .cancelled)
        }
        activeTouchCount = 0
    }
    
    private func forwardTouch(_ touches: Set<UITouch>, phase: TouchEventType) {
        guard let touch = touches.first, clientManager != nil else { return }
        
        let location = touch.location(in: self)
        sendEvent(location: location, type: phase)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleRightClick(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        sendEvent(location: location, type: .rightClick)
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        sendEvent(location: location, type: .doubleClick)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            let location = gesture.location(in: self)
            sendEvent(location: location, type: .rightClick)
        }
    }
    
    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            // PERFORMANCE: Throttle to 120Hz
            let now = CACurrentMediaTime()
            guard now - lastPanTime >= activeThrottleInterval() else {
                gesture.setTranslation(.zero, in: self)  // Still reset to get cumulative delta
                return
            }
            lastPanTime = now
            
            let translation = gesture.translation(in: self)
            // Reset translation so we get delta each time
            gesture.setTranslation(.zero, in: self)
            
            // Natural scrolling: swipe up = scroll down, swipe down = scroll up
            let scrollScale: CGFloat = 1.0
            let deltaX = translation.x * scrollScale
            let deltaY = translation.y * scrollScale  // Natural scrolling direction
            
            // Filter out zero-delta scroll events
            if abs(deltaX) < 0.5 && abs(deltaY) < 0.5 { return }
            clientManager?.sendScrollEvent(deltaX: Double(deltaX), deltaY: Double(deltaY))
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            // PERFORMANCE: Throttle to 120Hz
            let now = CACurrentMediaTime()
            guard now - lastPinchTime >= activeThrottleInterval() else {
                return
            }
            lastPinchTime = now
            
            let scale = gesture.scale
            let velocity = gesture.velocity
            
            // Send pinch event if there's meaningful change
            if abs(scale - 1.0) > 0.01 {
                clientManager?.sendPinchEvent(scale: Double(scale), velocity: Double(velocity))
                // Reset scale to get delta each time
                gesture.scale = 1.0
            }
        default:
            break
        }
    }
    
    // MARK: - Helper
    
    private func sendEvent(location: CGPoint, type: TouchEventType) {
        guard let scene = window?.windowScene, scene.activationState == .foregroundActive else { return }
        let width = bounds.width
        let height = bounds.height
        guard width > 1, height > 1 else { return }
        
        // Since this view is now sized to match the video content exactly,
        // normalization is straightforward
        let normalizedX = location.x / width
        let normalizedY = location.y / height
        
        // Clamp to 0-1 range
        let clampedX = max(0, min(1, Double(normalizedX)))
        let clampedY = max(0, min(1, Double(normalizedY)))
        
        #if DEBUG
        // Log touch coordinates for first few touches to debug offset
        // NSLog("[MouseInputView] Touch: loc=(%.1f,%.1f) bounds=(%.1f,%.1f) norm=(%.3f,%.3f)", location.x, location.y, width, height, clampedX, clampedY) -- Disabled for performance
        #endif
        
        clientManager?.sendTouchEvent(
            normalizedX: clampedX,
            normalizedY: clampedY,
            eventType: type
        )
    }

    // MARK: - Hardware Keyboard (Magic Keyboard)

    // iOS delivers hardware-keyboard presses to the key window's first responder,
    // so this view must take focus while the stream is on screen.
    override var canBecomeFirstResponder: Bool {
        guard let scene = window?.windowScene, scene.activationState == .foregroundActive else { return false }
        guard bounds.width > 1 && bounds.height > 1 else { return false }
        return true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && canBecomeFirstResponder && !isFirstResponder {
            becomeFirstResponder()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if window != nil && canBecomeFirstResponder && !isFirstResponder {
            becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: [UIPress] = []
        for press in presses {
            if !forwardKeyPress(press, isKeyDown: true) {
                unhandled.append(press)
            }
        }
        if !unhandled.isEmpty {
            super.pressesBegan(Set(unhandled), with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: [UIPress] = []
        for press in presses {
            if !forwardKeyPress(press, isKeyDown: false) {
                unhandled.append(press)
            }
        }
        if !unhandled.isEmpty {
            super.pressesEnded(Set(unhandled), with: event)
        }
    }

    @discardableResult
    private func forwardKeyPress(_ press: UIPress, isKeyDown: Bool) -> Bool {
        guard let key = press.key, let clientManager else { return false }

        // Multi-character or non-ASCII output (e.g. option-composed characters)
        // goes through the host's text injector instead of single-key events.
        if isKeyDown, key.modifierFlags.contains(.alternate),
           !key.characters.isEmpty,
           !key.characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            clientManager.sendTextInjection(key.characters)
            return true
        }

        guard let keyCode = Self.macOSKeyCode(for: key.keyCode) else {
            #if DEBUG
            NSLog("[MouseHandlingView] Unmapped HID usage \(key.keyCode.rawValue)")
            #endif
            return false
        }

        var modifiers = KeyModifiers()
        let flags = key.modifierFlags
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.alphaShift) { modifiers.insert(.capsLock) }

        // For unmodified character keys, also send the character so the host can
        // fall back to text injection if the layout mapping ever misses.
        let character: String?
        if isKeyDown, modifiers.isEmpty, !key.charactersIgnoringModifiers.isEmpty {
            character = key.charactersIgnoringModifiers
        } else {
            character = nil
        }

        clientManager.sendKeyEvent(
            keyCode: keyCode,
            character: character,
            modifiers: modifiers,
            isKeyDown: isKeyDown
        )
        return true
    }

    /// Maps UIKeyboardHIDUsage (USB HID codes) to macOS virtual key codes.
    private static func macOSKeyCode(for usage: UIKeyboardHIDUsage) -> UInt16? {
        hidToMac[usage.rawValue]
    }

    private static let hidToMac: [Int: UInt16] = [
        // Letters: HID 0x04-0x1D -> ANSI virtual codes
        4: 0x00, 5: 0x0B, 6: 0x08, 7: 0x02, 8: 0x0E, 9: 0x03, 10: 0x05, 11: 0x04,
        12: 0x22, 13: 0x26, 14: 0x28, 15: 0x25, 16: 0x2E, 17: 0x2D, 18: 0x1F,
        19: 0x23, 20: 0x0C, 21: 0x0F, 22: 0x01, 23: 0x11, 24: 0x20, 25: 0x09,
        26: 0x0D, 27: 0x07, 28: 0x10, 29: 0x06,
        // Digits: HID 0x1E-0x27
        30: 0x12, 31: 0x13, 32: 0x14, 33: 0x15, 34: 0x17, 35: 0x16,
        36: 0x1A, 37: 0x1C, 38: 0x19, 39: 0x1D,
        // Editing/whitespace
        40: 0x24,  // Return
        41: 0x35,  // Escape
        42: 0x33,  // Backspace (Delete backward)
        43: 0x30,  // Tab
        44: 0x31,  // Space
        // Punctuation
        45: 0x1B,  // -
        46: 0x18,  // =
        47: 0x21,  // [
        48: 0x1E,  // ]
        49: 0x2A,  // \
        51: 0x29,  // ;
        52: 0x27,  // '
        53: 0x32,  // `
        54: 0x2B,  // ,
        55: 0x2F,  // .
        56: 0x2C,  // /
        57: 0x39,  // Caps Lock
        // Function keys F1-F12: HID 0x3A-0x45
        58: 0x7A, 59: 0x78, 60: 0x63, 61: 0x76, 62: 0x60, 63: 0x61,
        64: 0x62, 65: 0x64, 66: 0x65, 67: 0x6D, 68: 0x67, 69: 0x6F,
        // Navigation
        74: 0x73,  // Home
        75: 0x74,  // Page Up
        76: 0x75,  // Forward Delete
        77: 0x77,  // End
        78: 0x79,  // Page Down
        79: 0x7C,  // Right Arrow
        80: 0x7B,  // Left Arrow
        81: 0x7D,  // Down Arrow
        82: 0x7E,  // Up Arrow
        // Keypad: HID 0x54-0x63
        84: 0x4B,  // Keypad /
        85: 0x43,  // Keypad *
        86: 0x4E,  // Keypad -
        87: 0x45,  // Keypad +
        88: 0x4C,  // Keypad Enter
        89: 0x53, 90: 0x54, 91: 0x55, 92: 0x56, 93: 0x57,
        94: 0x58, 95: 0x59, 96: 0x5B, 97: 0x5C, 98: 0x52, 99: 0x41,
        // Modifiers: HID 0xE0-0xE7
        224: 0x3B, // Left Control
        225: 0x38, // Left Shift
        226: 0x3A, // Left Option
        227: 0x37, // Left Command
        228: 0x3E, // Right Control
        229: 0x3C, // Right Shift
        230: 0x3D, // Right Option
        231: 0x36, // Right Command
    ]

}
