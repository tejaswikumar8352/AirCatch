//
//  MacKeyboardView.swift
//  AirCatchClient
//
//  Custom Mac-style keyboard that can be dragged and resized.
//  Matches MacBook keyboard layout with all modifier keys.
//

import SwiftUI

// MARK: - Mac Keyboard View

struct MacKeyboardView: View {
    @EnvironmentObject var clientManager: ClientManager
    @Binding var isVisible: Bool
    @Binding var position: CGPoint
    @Binding var size: CGSize
    
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var shiftActive = false
    @State private var controlActive = false
    @State private var optionActive = false
    @State private var commandActive = false
    @State private var capsLockActive = false
    @State private var fnActive = false
    
    private let minWidth: CGFloat = 300
    private let minHeight: CGFloat = 150
    
    var body: some View {
        VStack(spacing: 0) {
            // Invisible drag area at top for repositioning
            Color.clear
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            position = CGPoint(
                                x: position.x + value.translation.width,
                                y: position.y + value.translation.height
                            )
                        }
                )
            
            // Keyboard content
            VStack(spacing: 2) {
                // Function row
                functionRow
                
                // Number row
                numberRow
                
                // QWERTY row
                qwertyRow
                
                // ASDF row
                asdfRow
                
                // ZXCV row
                zxcvRow
                
                // Bottom row (modifiers + space)
                bottomRow
            }
            .padding(4)
            
            // Resize handle - larger touch target for finger
            HStack {
                Spacer()
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                size = CGSize(
                                    width: max(minWidth, size.width + value.translation.width),
                                    height: max(minHeight, size.height + value.translation.height)
                                )
                            }
                    )
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.ultraThinMaterial.opacity(0.85))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 10)
        .position(position)
    }
    
    // MARK: - Keyboard Rows
    
    private var functionRow: some View {
        HStack(spacing: 2) {
            keyButton("esc", keyCode: 53, width: 1.0)
            // F1-F12 matching Apple keyboard layout - show F-number with icon
            functionKeyButton("F1", icon: "sun.min", keyCode: 122, mediaKey: 3, width: 1.0)      // Brightness Down
            functionKeyButton("F2", icon: "sun.max", keyCode: 120, mediaKey: 2, width: 1.0)      // Brightness Up
            functionKeyButton("F3", icon: "rectangle.3.group", keyCode: 99, mediaKey: nil, width: 1.0)  // Mission Control
            functionKeyButton("F4", icon: "magnifyingglass", keyCode: 118, mediaKey: nil, width: 1.0)   // Spotlight
            functionKeyButton("F5", icon: "mic", keyCode: 96, mediaKey: nil, width: 1.0)         // Dictation
            functionKeyButton("F6", icon: "moon", keyCode: 97, mediaKey: nil, width: 1.0)        // Do Not Disturb
            functionKeyButton("F7", icon: "backward", keyCode: 98, mediaKey: 20, width: 1.0)     // Rewind
            functionKeyButton("F8", icon: "playpause", keyCode: 100, mediaKey: 16, width: 1.0)   // Play/Pause
            functionKeyButton("F9", icon: "forward", keyCode: 101, mediaKey: 19, width: 1.0)     // Fast Forward
            functionKeyButton("F10", icon: "speaker.slash", keyCode: 109, mediaKey: 7, width: 1.0)  // Mute
            functionKeyButton("F11", icon: "speaker.wave.1", keyCode: 103, mediaKey: 1, width: 1.0) // Volume Down
            functionKeyButton("F12", icon: "speaker.wave.3", keyCode: 111, mediaKey: 0, width: 1.0) // Volume Up
            keyButton("⏏", keyCode: 51, width: 1.0)
        }
    }
    
    private var numberRow: some View {
        HStack(spacing: 2) {
            keyButton("`", keyCode: 50, width: 1.0)
            keyButton("1", keyCode: 18, width: 1.0)
            keyButton("2", keyCode: 19, width: 1.0)
            keyButton("3", keyCode: 20, width: 1.0)
            keyButton("4", keyCode: 21, width: 1.0)
            keyButton("5", keyCode: 23, width: 1.0)
            keyButton("6", keyCode: 22, width: 1.0)
            keyButton("7", keyCode: 26, width: 1.0)
            keyButton("8", keyCode: 28, width: 1.0)
            keyButton("9", keyCode: 25, width: 1.0)
            keyButton("0", keyCode: 29, width: 1.0)
            keyButton("-", keyCode: 27, width: 1.0)
            keyButton("=", keyCode: 24, width: 1.0)
            keyButton("delete", keyCode: 51, width: 1.5, isSmall: true)
        }
    }
    
    private var qwertyRow: some View {
        HStack(spacing: 2) {
            keyButton("tab", keyCode: 48, width: 1.5, isSmall: true)
            keyButton("Q", keyCode: 12, width: 1.0)
            keyButton("W", keyCode: 13, width: 1.0)
            keyButton("E", keyCode: 14, width: 1.0)
            keyButton("R", keyCode: 15, width: 1.0)
            keyButton("T", keyCode: 17, width: 1.0)
            keyButton("Y", keyCode: 16, width: 1.0)
            keyButton("U", keyCode: 32, width: 1.0)
            keyButton("I", keyCode: 34, width: 1.0)
            keyButton("O", keyCode: 31, width: 1.0)
            keyButton("P", keyCode: 35, width: 1.0)
            keyButton("[", keyCode: 33, width: 1.0)
            keyButton("]", keyCode: 30, width: 1.0)
            keyButton("\\", keyCode: 42, width: 1.0)
        }
    }
    
    private var asdfRow: some View {
        HStack(spacing: 2) {
            modifierButton("caps", isActive: $capsLockActive, keyCode: 57, width: 1.8)
            keyButton("A", keyCode: 0, width: 1.0)
            keyButton("S", keyCode: 1, width: 1.0)
            keyButton("D", keyCode: 2, width: 1.0)
            keyButton("F", keyCode: 3, width: 1.0)
            keyButton("G", keyCode: 5, width: 1.0)
            keyButton("H", keyCode: 4, width: 1.0)
            keyButton("J", keyCode: 38, width: 1.0)
            keyButton("K", keyCode: 40, width: 1.0)
            keyButton("L", keyCode: 37, width: 1.0)
            keyButton(";", keyCode: 41, width: 1.0)
            keyButton("'", keyCode: 39, width: 1.0)
            keyButton("return", keyCode: 36, width: 1.8, isSmall: true)
        }
    }
    
    private var zxcvRow: some View {
        HStack(spacing: 2) {
            modifierButton("shift", isActive: $shiftActive, keyCode: 56, width: 2.2)
            keyButton("Z", keyCode: 6, width: 1.0)
            keyButton("X", keyCode: 7, width: 1.0)
            keyButton("C", keyCode: 8, width: 1.0)
            keyButton("V", keyCode: 9, width: 1.0)
            keyButton("B", keyCode: 11, width: 1.0)
            keyButton("N", keyCode: 45, width: 1.0)
            keyButton("M", keyCode: 46, width: 1.0)
            keyButton(",", keyCode: 43, width: 1.0)
            keyButton(".", keyCode: 47, width: 1.0)
            keyButton("/", keyCode: 44, width: 1.0)
            modifierButton("shift", isActive: $shiftActive, keyCode: 60, width: 2.2)
        }
    }
    
    private var bottomRow: some View {
        HStack(spacing: 2) {
            modifierButton("fn", isActive: $fnActive, keyCode: 63, width: 1.0)
            modifierButton("⌃", isActive: $controlActive, keyCode: 59, width: 1.0)
            modifierButton("⌥", isActive: $optionActive, keyCode: 58, width: 1.0)
            modifierButton("⌘", isActive: $commandActive, keyCode: 55, width: 1.3)
            keyButton("", keyCode: 49, width: 5.0) // Space bar
            modifierButton("⌘", isActive: $commandActive, keyCode: 54, width: 1.3)
            modifierButton("⌥", isActive: $optionActive, keyCode: 61, width: 1.0)
            // Arrow keys
            VStack(spacing: 1) {
                keyButton("▲", keyCode: 126, width: 1.0, height: 0.5)
                HStack(spacing: 1) {
                    keyButton("◀", keyCode: 123, width: 1.0, height: 0.5)
                    keyButton("▼", keyCode: 125, width: 1.0, height: 0.5)
                    keyButton("▶", keyCode: 124, width: 1.0, height: 0.5)
                }
            }
        }
    }
    
    // MARK: - Key Buttons
    
    private func keyButton(_ label: String, keyCode: UInt16, width: CGFloat, height: CGFloat = 1.0, isSmall: Bool = false) -> some View {
        let baseWidth = (size.width - 40) / 15
        let baseHeight = (size.height - 60) / 6
        
        return Button(action: {
            sendKey(keyCode: keyCode)
        }) {
            Text(label)
                .font(.system(size: isSmall ? 8 : 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: baseWidth * width, height: baseHeight * height)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
        }
        .buttonStyle(KeyButtonStyle())
    }
    
    private func modifierButton(_ label: String, isActive: Binding<Bool>, keyCode: UInt16, width: CGFloat) -> some View {
        let baseWidth = (size.width - 40) / 15
        let baseHeight = (size.height - 60) / 6
        
        return Button(action: {
            isActive.wrappedValue.toggle()
            sendModifierKey(keyCode: keyCode, isDown: isActive.wrappedValue)
        }) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: baseWidth * width, height: baseHeight)
                .background(isActive.wrappedValue ? Color.blue.opacity(0.7) : Color.black.opacity(0.8))
                .cornerRadius(4)
        }
        .buttonStyle(KeyButtonStyle())
    }
    
    private func functionKeyButton(_ label: String, icon: String, keyCode: UInt16, mediaKey: Int32?, width: CGFloat) -> some View {
        let baseWidth = (size.width - 40) / 15
        let baseHeight = (size.height - 60) / 6
        
        return Button(action: {
            if let mediaKey = mediaKey {
                sendMediaKey(mediaKey: mediaKey, keyCode: keyCode)
            } else {
                sendKey(keyCode: keyCode)
            }
        }) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 7, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(width: baseWidth * width, height: baseHeight)
            .background(Color.black.opacity(0.8))
            .cornerRadius(4)
        }
        .buttonStyle(KeyButtonStyle())
    }
    
    // MARK: - Key Sending
    
    private func sendKey(keyCode: UInt16) {
        var modifiers: KeyModifiers = []
        if shiftActive { modifiers.insert(.shift) }
        if controlActive { modifiers.insert(.control) }
        if optionActive { modifiers.insert(.option) }
        if commandActive { modifiers.insert(.command) }
        if capsLockActive { modifiers.insert(.capsLock) }
        
        // Send key down
        clientManager.sendKeyEvent(keyCode: keyCode, character: nil, modifiers: modifiers, isKeyDown: true)
        // Send key up
        clientManager.sendKeyEvent(keyCode: keyCode, character: nil, modifiers: modifiers, isKeyDown: false)
        
        // Reset non-sticky modifiers after key press
        if !capsLockActive {
            shiftActive = false
            controlActive = false
            optionActive = false
            commandActive = false
        }
    }
    
    private func sendMediaKey(mediaKey: Int32, keyCode: UInt16) {
        // Send media key event to host
        clientManager.sendMediaKeyEvent(mediaKey: mediaKey, keyCode: keyCode)
    }
    
    private func sendModifierKey(keyCode: UInt16, isDown: Bool) {
        clientManager.sendKeyEvent(keyCode: keyCode, character: nil, modifiers: [], isKeyDown: isDown)
    }
    
    private func functionKeyCode(_ num: Int) -> UInt16 {
        let codes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        return codes[num - 1]
    }
}

// MARK: - Key Button Style

struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.blue
        MacKeyboardView(
            isVisible: .constant(true),
            position: .constant(CGPoint(x: 400, y: 300)),
            size: .constant(CGSize(width: 600, height: 220))
        )
        .environmentObject(ClientManager.shared)
    }
}
