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

class KeyboardCaptureView: UIView, UIKeyInput, UITextInput {
    weak var clientManager: ClientManager?
    var onDismiss: (() -> Void)?
    
    // MARK: - Dictation Duplicate Detection
    
    /// The last multi-character text that was inserted (dictation sends multiple chars)
    private var lastDictatedText: String = ""
    /// Timestamp of when the last dictation text was inserted
    private var lastDictationTime: Date = .distantPast
    /// Window to detect duplicate dictation (iOS bug sends same text twice)
    private let dictationDebounceWindow: TimeInterval = 1.5
    
    /// Stores the last committed text length to detect what's new
    private var lastCommittedText: String = ""
    /// Tracks in-progress dictation (marked text)
    private var currentMarkedText: String = ""
    /// Set when unmarkText is called - indicates next insertText should be skipped
    private var pendingDictationCommit: Bool = false
    /// Tracks if we've sent any marked text (dictation in progress)
    private var hasSentMarkedText: Bool = false
    
    // UIKeyInput protocol
    var hasText: Bool { !lastCommittedText.isEmpty }
    
    override var canBecomeFirstResponder: Bool { true }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - UIKeyInput
    
    // Called when user types a character OR dictation commits final text
    func insertText(_ text: String) {
        let now = Date()
        let timeSinceLastDictation = now.timeIntervalSince(lastDictationTime)
        
        #if DEBUG
        print("📝 insertText: '\(text)' lastDictated='\(lastDictatedText)' elapsed=\(String(format: "%.2f", timeSinceLastDictation))s")
        #endif
        
        // Detect duplicate dictation text (iOS bug workaround)
        // If we get the same multi-character text within the debounce window, skip it
        if text.count > 1 && text == lastDictatedText && timeSinceLastDictation < dictationDebounceWindow {
            #if DEBUG
            print("📝 SKIPPED duplicate dictation: '\(text)'")
            #endif
            return
        }
        
        // If pendingDictationCommit is set (from setMarkedText flow), also skip
        if pendingDictationCommit {
            pendingDictationCommit = false
            hasSentMarkedText = false
            currentMarkedText = ""
            lastCommittedText += text
            #if DEBUG
            print("📝 SKIPPED (pendingDictationCommit): '\(text)'")
            #endif
            return
        }
        
        // Track multi-character inserts as potential dictation
        if text.count > 1 {
            lastDictatedText = text
            lastDictationTime = now
        }
        
        // Send the text
        for char in text {
            let keyCode = macOSKeyCode(for: char)
            sendKeyEvent(keyCode: keyCode, character: String(char), isDown: true)
            sendKeyEvent(keyCode: keyCode, character: String(char), isDown: false)
        }
        lastCommittedText += text
    }
    
    // Called when user presses delete/backspace
    func deleteBackward() {
        let backspaceCode: UInt16 = 51 // macOS backspace key code
        sendKeyEvent(keyCode: backspaceCode, character: nil, isDown: true)
        sendKeyEvent(keyCode: backspaceCode, character: nil, isDown: false)
        if !lastCommittedText.isEmpty {
            lastCommittedText.removeLast()
        }
    }
    
    // MARK: - UITextInput (Required for Dictation)
    
    /// Called during dictation with progressive updates
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        #if DEBUG
        print("📝 setMarkedText called: '\(markedText ?? "nil")' currentMarked='\(currentMarkedText)'")
        #endif
        
        guard let newMarked = markedText, !newMarked.isEmpty else {
            // Dictation cleared
            currentMarkedText = ""
            return
        }
        
        hasSentMarkedText = true
        
        // Calculate what's NEW since last marked text update
        let delta: String
        if newMarked.hasPrefix(currentMarkedText) {
            // New text extends the old - only send the new part
            delta = String(newMarked.dropFirst(currentMarkedText.count))
        } else {
            // Text was corrected/changed - send all (corrections are rare)
            delta = newMarked
        }
        
        #if DEBUG
        print("📝 Sending delta: '\(delta)'")
        #endif
        
        // Send new characters to Mac
        for char in delta {
            let keyCode = macOSKeyCode(for: char)
            sendKeyEvent(keyCode: keyCode, character: String(char), isDown: true)
            sendKeyEvent(keyCode: keyCode, character: String(char), isDown: false)
        }
        
        currentMarkedText = newMarked
    }
    
    func unmarkText() {
        #if DEBUG
        print("📝 unmarkText called, hasSentMarked=\(hasSentMarkedText)")
        #endif
        
        // Called when dictation finalizes - next insertText should be skipped
        if hasSentMarkedText {
            pendingDictationCommit = true
        }
        currentMarkedText = ""
    }
    
    // MARK: - UITextInput Required Properties/Methods (minimal implementation)
    
    var markedTextRange: UITextRange? { nil }
    var markedTextStyle: [NSAttributedString.Key : Any]? {
        get { nil }
        set { }
    }
    var selectedTextRange: UITextRange? {
        get { nil }
        set { }
    }
    var beginningOfDocument: UITextPosition { KeyboardTextPosition(offset: 0) }
    var endOfDocument: UITextPosition { KeyboardTextPosition(offset: lastCommittedText.count) }
    var inputDelegate: UITextInputDelegate?
    var tokenizer: UITextInputTokenizer { UITextInputStringTokenizer(textInput: self) }
    
    func text(in range: UITextRange) -> String? { nil }
    func replace(_ range: UITextRange, withText text: String) { insertText(text) }
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? { nil }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? { nil }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection, offset: Int) -> UITextPosition? { nil }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult { .orderedSame }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { 0 }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? { nil }
    func characterRange(byExtending position: UITextPosition, in direction: UITextLayoutDirection) -> UITextRange? { nil }
    func baseWritingDirection(for position: UITextPosition, in direction: UITextStorageDirection) -> NSWritingDirection { .natural }
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) { }
    func firstRect(for range: UITextRange) -> CGRect { bounds }
    func caretRect(for position: UITextPosition) -> CGRect { .zero }
    func closestPosition(to point: CGPoint) -> UITextPosition? { nil }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { nil }
    func characterRange(at point: CGPoint) -> UITextRange? { nil }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    
    // MARK: - Key Event Sending
    
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

// MARK: - Helper Types for UITextInput

private class KeyboardTextPosition: UITextPosition {
    let offset: Int
    init(offset: Int) { self.offset = offset }
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
