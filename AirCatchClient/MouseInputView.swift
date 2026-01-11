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
        
        // 4. Two-Finger Pan (Scroll)
        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerPan(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
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
        if activeTouchCount == 1 {
            forwardTouch(touches, phase: .moved)
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
            let translation = gesture.translation(in: self)
            // Reset translation so we get delta each time
            gesture.setTranslation(.zero, in: self)
            
            // Natural scrolling: swipe up = scroll down, swipe down = scroll up
            let scrollScale: CGFloat = 1.0
            let deltaX = translation.x * scrollScale
            let deltaY = translation.y * scrollScale  // Natural scrolling direction
            
            if abs(deltaX) > 0.5 || abs(deltaY) > 0.5 {
                clientManager?.sendScrollEvent(deltaX: Double(deltaX), deltaY: Double(deltaY))
            }
        default:
            break
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
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
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        
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

}
