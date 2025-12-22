//
//  InputSessionOverlay.swift
//  AirCatchClient
//
//  Input-only overlay for Keyboard/Trackpad sessions.
//

import SwiftUI
import UIKit

struct InputSessionOverlay: View {
    @EnvironmentObject private var clientManager: ClientManager

    @Binding var keyboardEnabled: Bool
    @Binding var trackpadEnabled: Bool

    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Premium dark background with vignette
            PremiumKeyboardBackground()
                .ignoresSafeArea()

            // Content
            Group {
                if trackpadEnabled {
                    VStack(spacing: 16) {
                        Spacer(minLength: 54)

                        TrackpadSurface()
                            .environmentObject(clientManager)
                            .padding(.horizontal, 18)

                        if keyboardEnabled {
                            MacKeyboardView { keyCode, modifiers in
                                clientManager.sendKeyCode(keyCode, modifiers: modifiers)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                    }
                } else if keyboardEnabled {
                    // Keyboard-only: occupy the entire screen.
                    MacKeyboardView { keyCode, modifiers in
                        clientManager.sendKeyCode(keyCode, modifiers: modifiers)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.clear
                }
            }

            // Header overlay (doesn't steal space from keyboard)
            VStack(spacing: 0) {
                HStack {
                    Button("Close") { onClose() }
                        .buttonStyle(.bordered)

                    Spacer()

                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Keep the trailing side balanced.
                    Color.clear
                        .frame(width: 64, height: 1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                Spacer()
            }
        }
    }

    private var trackpadSymbolName: String {
        // Some iOS versions/symbol sets don't include "trackpad".
        if UIImage(systemName: "trackpad") != nil {
            return "trackpad"
        }
        return "rectangle.and.hand.point.up.left"
    }

    private var title: String {
        switch (keyboardEnabled, trackpadEnabled) {
        case (true, true):
            return "Keyboard + Trackpad"
        case (true, false):
            return "Keyboard"
        case (false, true):
            return "Trackpad"
        default:
            return "Input"
        }
    }
}

private struct TrackpadSurface: View {
    @EnvironmentObject private var clientManager: ClientManager

    var body: some View {
        ZStack {
            // Trackpad background - subtle dark material
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.15))
            
            TrackpadInputView()
                .environmentObject(clientManager)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 380)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        }
    }
}

// MARK: - Trackpad Input

struct TrackpadInputView: UIViewRepresentable {
    @EnvironmentObject var clientManager: ClientManager

    func makeUIView(context: Context) -> TrackpadHandlingView {
        let view = TrackpadHandlingView()
        view.clientManager = clientManager
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TrackpadHandlingView, context: Context) {
        uiView.clientManager = clientManager
    }
}

final class TrackpadHandlingView: UIView {
    weak var clientManager: ClientManager?

    // Single finger tracking
    private var touchStartPoint: CGPoint = .zero
    private var lastTouchPoint: CGPoint = .zero
    private var touchStartTime: TimeInterval = 0
    private var hasMoved = false
    
    // Drag state
    private var isDragging = false
    private var dragStartTimer: Timer?
    private let dragHoldDuration: TimeInterval = 0.25  // Time to hold before drag starts
    
    // Two-finger tracking for scroll
    private var twoFingerStartPoints: [UITouch: CGPoint] = [:]
    private var lastTwoFingerCenter: CGPoint = .zero
    private var lastPinchDistance: CGFloat = 0
    private var isScrolling = false
    private var isPinching = false

    // Gesture thresholds
    private let tapMaxDuration: TimeInterval = 0.22
    private let tapMaxDistance: CGFloat = 12
    private let scrollThreshold: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGestures()
    }

    private func setupGestures() {
        // Two-finger tap for right click
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        addGestureRecognizer(twoFingerTap)
        
        // Long press for drag (like tap-and-hold to drag on Mac trackpad)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = dragHoldDuration
        longPress.allowableMovement = 8
        addGestureRecognizer(longPress)
        
        // Pinch for zoom
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)
        
        // Two-finger pan for scroll
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)
    }

    // MARK: - Touch Handling (Single Finger Move & Tap)
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        let allTouches = event?.allTouches ?? touches
        
        // Only handle single-finger for pointer movement
        if allTouches.count == 1, let touch = touches.first {
            touchStartPoint = touch.location(in: self)
            lastTouchPoint = touchStartPoint
            touchStartTime = touch.timestamp
            hasMoved = false
            isDragging = false
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        let allTouches = event?.allTouches ?? touches
        
        // Single finger movement
        if allTouches.count == 1, let touch = touches.first {
            let location = touch.location(in: self)
            
            let deltaX = location.x - lastTouchPoint.x
            let deltaY = location.y - lastTouchPoint.y
            lastTouchPoint = location
            
            if location.distance(to: touchStartPoint) > 3 {
                hasMoved = true
            }
            
            if isDragging {
                // Dragging mode - send drag move
                clientManager?.sendTrackpadDragMove(deltaX: Double(deltaX), deltaY: Double(deltaY))
            } else {
                // Normal pointer movement
                clientManager?.sendTrackpadDelta(deltaX: Double(deltaX), deltaY: Double(deltaY))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        let allTouches = event?.allTouches ?? touches
        
        // End drag if active
        if isDragging {
            clientManager?.sendTrackpadDragEnded()
            isDragging = false
            return
        }
        
        // Check for tap (single finger, quick, no movement)
        if allTouches.count == 1, let touch = touches.first {
            let location = touch.location(in: self)
            let duration = touch.timestamp - touchStartTime
            let distance = location.distance(to: touchStartPoint)

            if !hasMoved && duration <= tapMaxDuration && distance <= tapMaxDistance {
                clientManager?.sendTrackpadClick()
            }
        }
        
        dragStartTimer?.invalidate()
        dragStartTimer = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        if isDragging {
            clientManager?.sendTrackpadDragEnded()
            isDragging = false
        }
        
        dragStartTimer?.invalidate()
        dragStartTimer = nil
    }

    // MARK: - Gesture Handlers
    
    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            clientManager?.sendTrackpadRightClick()
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Start dragging
            isDragging = true
            clientManager?.sendTrackpadDragBegan()
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        case .changed:
            // Movement is handled in touchesMoved
            break
        case .ended, .cancelled:
            if isDragging {
                clientManager?.sendTrackpadDragEnded()
                isDragging = false
            }
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .changed:
            // Send zoom/pinch as scroll with command key simulation
            let scale = gesture.scale
            let velocity = gesture.velocity
            clientManager?.sendPinchEvent(scale: Double(scale), velocity: Double(velocity))
            gesture.scale = 1.0  // Reset for incremental updates
        default:
            break
        }
    }
    
    @objc private func handleTwoFingerPan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .changed:
            let translation = gesture.translation(in: self)
            // Natural scrolling (inverted)
            let scrollX = -translation.x * 0.5
            let scrollY = -translation.y * 0.5
            clientManager?.sendScrollEvent(deltaX: Double(scrollX), deltaY: Double(scrollY))
            gesture.setTranslation(.zero, in: self)
        default:
            break
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Keyboard Capture

struct KeyboardCapture: UIViewRepresentable {
    let onInsert: (String) -> Void
    let onDelete: (Int) -> Void
    let onReturn: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textColor = .clear
        tv.tintColor = .clear
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.delegate = context.coordinator
        tv.isScrollEnabled = false
        tv.text = ""
        // Avoid repeatedly forcing first-responder in updateUIView;
        // it can trigger noisy RTI/keyboard layout warnings.
        DispatchQueue.main.async { tv.becomeFirstResponder() }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Intentionally no-op: don't thrash first responder.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onInsert: onInsert, onDelete: onDelete, onReturn: onReturn)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let onInsert: (String) -> Void
        let onDelete: (Int) -> Void
        let onReturn: () -> Void

        init(onInsert: @escaping (String) -> Void, onDelete: @escaping (Int) -> Void, onReturn: @escaping () -> Void) {
            self.onInsert = onInsert
            self.onDelete = onDelete
            self.onReturn = onReturn
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Handle return explicitly to avoid the text view growing.
            if text == "\n" {
                onReturn()
                return false
            }

            if range.length > 0, text.isEmpty {
                onDelete(range.length)
                return false
            }

            if !text.isEmpty {
                onInsert(text)
                return false
            }

            return false
        }
    }
}

// MARK: - Premium Keyboard Background

private struct PremiumKeyboardBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Base dark graphite
                Color(white: 0.08)
                
                // Subtle radial gradient for depth (vignette effect)
                RadialGradient(
                    colors: [
                        Color(white: 0.12),
                        Color(white: 0.08),
                        Color(white: 0.05)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: max(geo.size.width, geo.size.height) * 0.7
                )
                
                // Top ambient light
                LinearGradient(
                    colors: [
                        Color(white: 0.15).opacity(0.3),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                
                // Subtle noise texture simulation via overlapping gradients
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.15)
                    ],
                    center: UnitPoint(x: 0.3, y: 0.3),
                    startRadius: geo.size.width * 0.1,
                    endRadius: geo.size.width * 0.8
                )
                
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.1)
                    ],
                    center: UnitPoint(x: 0.7, y: 0.7),
                    startRadius: geo.size.width * 0.05,
                    endRadius: geo.size.width * 0.6
                )
            }
        }
    }
}
