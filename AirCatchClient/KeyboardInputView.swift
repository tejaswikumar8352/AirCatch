//
//  KeyboardInputView.swift
//  AirCatchClient
//
//  On-screen keyboard input using iOS system keyboard.
//  Captures key events and sends them to the Mac host.
//

import SwiftUI
import UIKit

// MARK: - SwiftUI Wrapper

struct KeyboardInputView: View {
    @EnvironmentObject var clientManager: ClientManager
    @Binding var isVisible: Bool
    let letterboxHeight: CGFloat
    
    var body: some View {
        KeyboardInputRepresentable(
            clientManager: clientManager,
            isVisible: $isVisible
        )
        .frame(height: letterboxHeight)
    }
}

// MARK: - UIKit Representable

struct KeyboardInputRepresentable: UIViewRepresentable {
    let clientManager: ClientManager
    @Binding var isVisible: Bool
    
    func makeUIView(context: Context) -> KeyboardCaptureView {
        let view = KeyboardCaptureView()
        view.clientManager = clientManager
        view.onDismiss = { isVisible = false }
        return view
    }
    
    func updateUIView(_ uiView: KeyboardCaptureView, context: Context) {
        if isVisible && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isVisible && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }
}

// MARK: - Keyboard Capture View

class KeyboardCaptureView: UIView, UIKeyInput {
    weak var clientManager: ClientManager?
    var onDismiss: (() -> Void)?
    
    // UIKeyInput protocol
    var hasText: Bool { true }
    
    override var canBecomeFirstResponder: Bool { true }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Called when user types a character
    func insertText(_ text: String) {
        for char in text {
            let keyCode = macOSKeyCode(for: char)
            sendKeyEvent(keyCode: keyCode, character: String(char), isDown: true)
            sendKeyEvent(keyCode: keyCode, character: String(char), isDown: false)
        }
    }
    
    // Called when user presses delete/backspace
    func deleteBackward() {
        let backspaceCode: UInt16 = 51 // macOS backspace key code
        sendKeyEvent(keyCode: backspaceCode, character: nil, isDown: true)
        sendKeyEvent(keyCode: backspaceCode, character: nil, isDown: false)
    }
    
    private func sendKeyEvent(keyCode: UInt16, character: String?, isDown: Bool) {
        clientManager?.sendKeyEvent(
            keyCode: keyCode,
            character: character,
            modifiers: [],
            isKeyDown: isDown
        )
    }
    
    // Map common characters to macOS key codes
    private func macOSKeyCode(for character: Character) -> UInt16 {
        let lowercased = character.lowercased()
        
        // Letters a-z
        if let ascii = lowercased.first?.asciiValue, ascii >= 97 && ascii <= 122 {
            let keyCodeMap: [UInt16] = [
                0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6
            ]
            return keyCodeMap[Int(ascii - 97)]
        }
        
        // Numbers 0-9
        if let ascii = character.asciiValue, ascii >= 48 && ascii <= 57 {
            let numCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
            return numCodes[Int(ascii - 48)]
        }
        
        // Special characters
        switch character {
        case " ": return 49  // Space
        case "\n", "\r": return 36  // Return
        case "\t": return 48  // Tab
        case ".": return 47
        case ",": return 43
        case "/": return 44
        case ";": return 41
        case "'": return 39
        case "[": return 33
        case "]": return 30
        case "\\": return 42
        case "-": return 27
        case "=": return 24
        case "`": return 50
        default: return 0
        }
    }
    
    // Handle hardware keyboard commands
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(action: #selector(handleEscape), input: UIKeyCommand.inputEscape),
            UIKeyCommand(action: #selector(handleTab), input: "\t"),
        ]
    }
    
    @objc private func handleEscape() {
        sendKeyEvent(keyCode: 53, character: nil, isDown: true)
        sendKeyEvent(keyCode: 53, character: nil, isDown: false)
    }
    
    @objc private func handleTab() {
        sendKeyEvent(keyCode: 48, character: "\t", isDown: true)
        sendKeyEvent(keyCode: 48, character: "\t", isDown: false)
    }
}

// MARK: - Keyboard Toggle Button

struct KeyboardToggleButton: View {
    @Binding var showKeyboard: Bool
    @State private var isIdle = false
    @State private var workItem: DispatchWorkItem?
    
    var body: some View {
        Button(action: {
            showKeyboard.toggle()
            resetIdleTimer()
        }) {
            // Apply opacity ONLY to the visual content, NOT the button itself
            // This ensures the button remains fully interactive (clickable) even when "dimmed"
            Image(systemName: showKeyboard ? "keyboard.chevron.compact.down" : "keyboard")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .padding(12)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                )
                .opacity(isIdle ? 0.35 : 1.0) // Visual dimming only
                .animation(.easeInOut(duration: 0.3), value: isIdle)
        }
        .buttonStyle(PlainButtonStyle()) // No extra effects
        .contentShape(Circle()) // Hit target matches the visual circle
        .allowsHitTesting(true) // Explicitly ensure clickability
        .zIndex(100) // Keep on top
        .onAppear {
            resetIdleTimer()
        }
    }
    
    private func resetIdleTimer() {
        isIdle = false
        workItem?.cancel()
        
        let newItem = DispatchWorkItem {
            isIdle = true
        }
        workItem = newItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: newItem)
    }
}
