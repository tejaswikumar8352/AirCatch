//
//  MacKeyboardView.swift
//  AirCatchClient
//
//  Custom Mac-style keyboard for controlling the Mac host.
//

import SwiftUI

// MARK: - Mac Virtual Key Codes

enum MacKeyCode: UInt16 {
    // Function Row
    case escape = 53
    case f1 = 122
    case f2 = 120
    case f3 = 99
    case f4 = 118
    case f5 = 96
    case f6 = 97
    case f7 = 98
    case f8 = 100
    case f9 = 101
    case f10 = 109
    case f11 = 103
    case f12 = 111
    
    // Number Row
    case grave = 50          // ` ~
    case key1 = 18
    case key2 = 19
    case key3 = 20
    case key4 = 21
    case key5 = 23
    case key6 = 22
    case key7 = 26
    case key8 = 28
    case key9 = 25
    case key0 = 29
    case minus = 27          // - _
    case equal = 24          // = +
    case delete = 51         // Backspace
    
    // QWERTY Row
    case tab = 48
    case q = 12
    case w = 13
    case e = 14
    case r = 15
    case t = 17
    case y = 16
    case u = 32
    case i = 34
    case o = 31
    case p = 35
    case leftBracket = 33    // [ {
    case rightBracket = 30   // ] }
    case backslash = 42      // \ |
    
    // ASDF Row
    case capsLock = 57
    case a = 0
    case s = 1
    case d = 2
    case f = 3
    case g = 5
    case h = 4
    case j = 38
    case k = 40
    case l = 37
    case semicolon = 41      // ; :
    case quote = 39          // ' "
    case `return` = 36
    
    // ZXCV Row
    case leftShift = 56
    case z = 6
    case x = 7
    case c = 8
    case v = 9
    case b = 11
    case n = 45
    case m = 46
    case comma = 43          // , <
    case period = 47         // . >
    case slash = 44          // / ?
    case rightShift = 60
    
    // Bottom Row
    case fn = 63
    case leftControl = 59
    case leftOption = 58
    case leftCommand = 55
    case space = 49
    case rightCommand = 54
    case rightOption = 61
    
    // Arrow Keys
    case upArrow = 126
    case downArrow = 125
    case leftArrow = 123
    case rightArrow = 124
}

// MARK: - Key Definition

struct KeyDef: Identifiable {
    let id = UUID()
    let label: String
    let shiftLabel: String?
    let keyCode: MacKeyCode
    let width: CGFloat  // Relative width (1.0 = standard key)
    let isModifier: Bool
    let systemImage: String?
    
    init(_ label: String, shift: String? = nil, code: MacKeyCode, width: CGFloat = 1.0, isModifier: Bool = false, systemImage: String? = nil) {
        self.label = label
        self.shiftLabel = shift
        self.keyCode = code
        self.width = width
        self.isModifier = isModifier
        self.systemImage = systemImage
    }
}

// MARK: - Mac Keyboard View

struct MacKeyboardView: View {
    let onKeyPress: (UInt16, KeyModifiers) -> Void
    
    @State private var shiftPressed = false
    @State private var controlPressed = false
    @State private var optionPressed = false
    @State private var commandPressed = false
    @State private var capsLockOn = false
    
    private var currentModifiers: KeyModifiers {
        KeyModifiers(shift: shiftPressed || capsLockOn, control: controlPressed, option: optionPressed, command: commandPressed)
    }
    
    // Function Row
    private let functionRow: [KeyDef] = [
        KeyDef("esc", code: .escape, width: 1.0),
        KeyDef("F1", code: .f1, systemImage: "sun.min"),
        KeyDef("F2", code: .f2, systemImage: "sun.max"),
        KeyDef("F3", code: .f3, systemImage: "rectangle.split.3x1"),
        KeyDef("F4", code: .f4, systemImage: "magnifyingglass"),
        KeyDef("F5", code: .f5, systemImage: "mic"),
        KeyDef("F6", code: .f6, systemImage: "moon"),
        KeyDef("F7", code: .f7, systemImage: "backward.end.fill"),
        KeyDef("F8", code: .f8, systemImage: "playpause.fill"),
        KeyDef("F9", code: .f9, systemImage: "forward.end.fill"),
        KeyDef("F10", code: .f10, systemImage: "speaker.slash.fill"),
        KeyDef("F11", code: .f11, systemImage: "speaker.wave.1.fill"),
        KeyDef("F12", code: .f12, systemImage: "speaker.wave.3.fill"),
    ]
    
    // Number Row
    private let numberRow: [KeyDef] = [
        KeyDef("`", shift: "~", code: .grave),
        KeyDef("1", shift: "!", code: .key1),
        KeyDef("2", shift: "@", code: .key2),
        KeyDef("3", shift: "#", code: .key3),
        KeyDef("4", shift: "$", code: .key4),
        KeyDef("5", shift: "%", code: .key5),
        KeyDef("6", shift: "^", code: .key6),
        KeyDef("7", shift: "&", code: .key7),
        KeyDef("8", shift: "*", code: .key8),
        KeyDef("9", shift: "(", code: .key9),
        KeyDef("0", shift: ")", code: .key0),
        KeyDef("-", shift: "_", code: .minus),
        KeyDef("=", shift: "+", code: .equal),
        KeyDef("delete", code: .delete, width: 1.5),
    ]
    
    // QWERTY Row
    private let qwertyRow: [KeyDef] = [
        KeyDef("tab", code: .tab, width: 1.5),
        KeyDef("Q", code: .q),
        KeyDef("W", code: .w),
        KeyDef("E", code: .e),
        KeyDef("R", code: .r),
        KeyDef("T", code: .t),
        KeyDef("Y", code: .y),
        KeyDef("U", code: .u),
        KeyDef("I", code: .i),
        KeyDef("O", code: .o),
        KeyDef("P", code: .p),
        KeyDef("[", shift: "{", code: .leftBracket),
        KeyDef("]", shift: "}", code: .rightBracket),
        KeyDef("\\", shift: "|", code: .backslash),
    ]
    
    // ASDF Row
    private let asdfRow: [KeyDef] = [
        KeyDef("caps lock", code: .capsLock, width: 1.75, isModifier: true),
        KeyDef("A", code: .a),
        KeyDef("S", code: .s),
        KeyDef("D", code: .d),
        KeyDef("F", code: .f),
        KeyDef("G", code: .g),
        KeyDef("H", code: .h),
        KeyDef("J", code: .j),
        KeyDef("K", code: .k),
        KeyDef("L", code: .l),
        KeyDef(";", shift: ":", code: .semicolon),
        KeyDef("'", shift: "\"", code: .quote),
        KeyDef("return", code: .return, width: 1.75),
    ]
    
    // ZXCV Row
    private let zxcvRow: [KeyDef] = [
        KeyDef("shift", code: .leftShift, width: 2.25, isModifier: true, systemImage: "shift"),
        KeyDef("Z", code: .z),
        KeyDef("X", code: .x),
        KeyDef("C", code: .c),
        KeyDef("V", code: .v),
        KeyDef("B", code: .b),
        KeyDef("N", code: .n),
        KeyDef("M", code: .m),
        KeyDef(",", shift: "<", code: .comma),
        KeyDef(".", shift: ">", code: .period),
        KeyDef("/", shift: "?", code: .slash),
        KeyDef("shift", code: .rightShift, width: 2.25, isModifier: true, systemImage: "shift"),
    ]
    
    // Bottom Row
    private let bottomRow: [KeyDef] = [
        KeyDef("fn", code: .fn, width: 1.0, isModifier: true, systemImage: "globe"),
        KeyDef("control", code: .leftControl, width: 1.0, isModifier: true, systemImage: "control"),
        KeyDef("option", code: .leftOption, width: 1.0, isModifier: true, systemImage: "option"),
        KeyDef("command", code: .leftCommand, width: 1.25, isModifier: true, systemImage: "command"),
        KeyDef("", code: .space, width: 5.0),  // Space bar
        KeyDef("command", code: .rightCommand, width: 1.25, isModifier: true, systemImage: "command"),
        KeyDef("option", code: .rightOption, width: 1.0, isModifier: true, systemImage: "option"),
    ]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                let padding: CGFloat = 0
                let availableWidth = max(0, geo.size.width - padding * 2)
                let availableHeight = max(0, geo.size.height - padding * 2)

                let keySpacing = max(3, min(10, availableWidth * 0.008))
                let arrowSpacing = max(2, keySpacing * 0.5)

                let functionHeightFactor: CGFloat = 0.85
                let arrowKeyWidthFactor: CGFloat = 0.82
                let arrowUpHeightFactor: CGFloat = 0.46
                let arrowDownHeightFactor: CGFloat = 0.52

                let bottomUnits = rowUnits(bottomRow)
                let bottomSpacingCount = CGFloat(max(0, bottomRow.count - 1))
                let bottomBaseWidth = max(1, (availableWidth - keySpacing * (bottomSpacingCount + 1) - arrowSpacing * 2) / (bottomUnits + arrowKeyWidthFactor * 3))

                let baseCandidates: [CGFloat] = [
                    baseForRow(keys: functionRow, width: availableWidth, keySpacing: keySpacing) / 0.85,
                    baseForRow(keys: numberRow, width: availableWidth, keySpacing: keySpacing),
                    baseForRow(keys: qwertyRow, width: availableWidth, keySpacing: keySpacing),
                    baseForRow(keys: asdfRow, width: availableWidth, keySpacing: keySpacing),
                    baseForRow(keys: zxcvRow, width: availableWidth, keySpacing: keySpacing),
                    bottomBaseWidth
                ]
                let widthBase = baseCandidates.min() ?? 44

                // Height-based sizing to help the keyboard occupy vertical space.
                // 6 rows: function + 4 main + bottom.
                let heightFactors = functionHeightFactor + 4.0 + max(1.0, (arrowUpHeightFactor + arrowDownHeightFactor))
                let totalRowSpacings = keySpacing * 5
                let heightBase = max(1, (availableHeight - totalRowSpacings) / heightFactors)

                let baseKeySize = min(widthBase, heightBase)

                VStack(spacing: keySpacing) {
                    // Function Row
                    HStack(spacing: keySpacing) {
                        ForEach(functionRow) { key in
                            KeyButton(
                                key: key,
                                baseSize: baseKeySize * functionHeightFactor,
                                isPressed: false,
                                showShift: shiftPressed || capsLockOn
                            ) {
                                handleKeyPress(key)
                            }
                        }
                    }

                    // Number Row
                    HStack(spacing: keySpacing) {
                        ForEach(numberRow) { key in
                            KeyButton(
                                key: key,
                                baseSize: baseKeySize,
                                isPressed: false,
                                showShift: shiftPressed || capsLockOn
                            ) {
                                handleKeyPress(key)
                            }
                        }
                    }

                    // QWERTY Row
                    HStack(spacing: keySpacing) {
                        ForEach(qwertyRow) { key in
                            KeyButton(
                                key: key,
                                baseSize: baseKeySize,
                                isPressed: false,
                                showShift: shiftPressed || capsLockOn
                            ) {
                                handleKeyPress(key)
                            }
                        }
                    }

                    // ASDF Row
                    HStack(spacing: keySpacing) {
                        ForEach(asdfRow) { key in
                            KeyButton(
                                key: key,
                                baseSize: baseKeySize,
                                isPressed: key.keyCode == .capsLock ? capsLockOn : false,
                                showShift: shiftPressed || capsLockOn
                            ) {
                                handleKeyPress(key)
                            }
                        }
                    }

                    // ZXCV Row
                    HStack(spacing: keySpacing) {
                        ForEach(zxcvRow) { key in
                            KeyButton(
                                key: key,
                                baseSize: baseKeySize,
                                isPressed: (key.keyCode == .leftShift || key.keyCode == .rightShift) ? shiftPressed : false,
                                showShift: shiftPressed || capsLockOn
                            ) {
                                handleKeyPress(key)
                            }
                        }
                    }

                    // Bottom Row with Arrow Keys
                    HStack(spacing: keySpacing) {
                        ForEach(bottomRow) { key in
                            KeyButton(
                                key: key,
                                baseSize: baseKeySize,
                                isPressed: isModifierPressed(key),
                                showShift: shiftPressed || capsLockOn
                            ) {
                                handleKeyPress(key)
                            }
                        }

                        // Arrow key cluster
                        ArrowKeyCluster(
                            baseKeySize: baseKeySize,
                            arrowKeyWidthFactor: arrowKeyWidthFactor,
                            arrowUpHeightFactor: arrowUpHeightFactor,
                            arrowDownHeightFactor: arrowDownHeightFactor,
                            arrowSpacing: arrowSpacing,
                            onKeyPress: { keyCode in
                                onKeyPress(keyCode, currentModifiers)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func isModifierPressed(_ key: KeyDef) -> Bool {
        switch key.keyCode {
        case .leftControl: return controlPressed
        case .leftOption, .rightOption: return optionPressed
        case .leftCommand, .rightCommand: return commandPressed
        default: return false
        }
    }
    
    private func handleKeyPress(_ key: KeyDef) {
        switch key.keyCode {
        case .capsLock:
            capsLockOn.toggle()
            onKeyPress(key.keyCode.rawValue, KeyModifiers())
        case .leftShift, .rightShift:
            shiftPressed.toggle()
        case .leftControl:
            controlPressed.toggle()
        case .leftOption, .rightOption:
            optionPressed.toggle()
        case .leftCommand, .rightCommand:
            commandPressed.toggle()
        case .fn:
            // Fn key - just send the key code
            onKeyPress(key.keyCode.rawValue, currentModifiers)
        default:
            // Regular key - send with current modifiers
            onKeyPress(key.keyCode.rawValue, currentModifiers)
            // Reset shift after pressing a non-modifier key (like a real keyboard)
            if shiftPressed && !capsLockOn {
                shiftPressed = false
            }
        }
    }
    
    private func rowUnits(_ keys: [KeyDef]) -> CGFloat {
        keys.reduce(0) { $0 + $1.width }
    }

    private func baseForRow(keys: [KeyDef], width: CGFloat, keySpacing: CGFloat) -> CGFloat {
        let units = rowUnits(keys)
        let totalSpacing = keySpacing * CGFloat(max(0, keys.count - 1))
        guard units > 0 else { return 0 }
        return max(1, (width - totalSpacing) / units)
    }
}

// MARK: - Key Button

private struct KeyButton: View {
    let key: KeyDef
    let baseSize: CGFloat
    let isPressed: Bool
    let showShift: Bool
    let action: () -> Void
    
    // Simplified color palette
    private let keyBackground = Color(white: 0.18)
    private let keyBackgroundPressed = Color(white: 0.25)
    private let textPrimary = Color(white: 0.92)
    private let textSecondary = Color(white: 0.55)
    
    private var displayLabel: String {
        if key.keyCode == .space {
            return ""
        }
        if showShift, let shiftLabel = key.shiftLabel {
            return shiftLabel
        }
        return key.label
    }
    
    private var cornerRadius: CGFloat {
        min(10, baseSize * 0.18)
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Simple solid background - much faster than gradients
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPressed ? Color.accentColor : keyBackground)
                
                // Content
                Group {
                    if let systemImage = key.systemImage, key.keyCode != .leftShift && key.keyCode != .rightShift {
                        Image(systemName: systemImage)
                            .font(.system(size: max(12, baseSize * 0.28), weight: .medium))
                    } else if key.keyCode == .leftShift || key.keyCode == .rightShift {
                        Image(systemName: isPressed ? "shift.fill" : "shift")
                            .font(.system(size: max(14, baseSize * 0.32), weight: .medium))
                    } else if key.shiftLabel != nil && !key.isModifier {
                        VStack(spacing: 1) {
                            Text(key.shiftLabel ?? "")
                                .font(.system(size: max(9, baseSize * 0.2), weight: .medium))
                                .foregroundStyle(showShift ? textPrimary : textSecondary)
                            Text(key.label)
                                .font(.system(size: max(14, baseSize * 0.32), weight: .medium))
                                .foregroundStyle(showShift ? textSecondary : textPrimary)
                        }
                    } else {
                        Text(displayLabel)
                            .font(.system(size: key.width > 1.2 ? max(11, baseSize * 0.24) : max(14, baseSize * 0.32), weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(isPressed ? .white : textPrimary)
            }
            .frame(width: baseSize * key.width + (key.width - 1) * 4, height: baseSize)
            // Single lightweight border
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(FastKeyButtonStyle())
    }
}

// Lightweight button style without expensive animations
private struct FastKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Arrow Key Button

private struct ArrowKeyButton: View {
    let systemImage: String
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    
    private let keyBackground = Color(white: 0.18)
    private let textPrimary = Color(white: 0.92)
    
    private var cornerRadius: CGFloat {
        min(6, min(width, height) * 0.15)
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Simple solid background
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(keyBackground)
                
                // Icon
                Image(systemName: systemImage)
                    .font(.system(size: max(10, min(width, height) * 0.35), weight: .semibold))
                    .foregroundStyle(textPrimary)
            }
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(FastKeyButtonStyle())
    }
}

// MARK: - Arrow Key Cluster

private struct ArrowKeyCluster: View {
    let baseKeySize: CGFloat
    let arrowKeyWidthFactor: CGFloat
    let arrowUpHeightFactor: CGFloat
    let arrowDownHeightFactor: CGFloat
    let arrowSpacing: CGFloat
    let onKeyPress: (UInt16) -> Void
    
    var body: some View {
        let arrowKeyWidth = baseKeySize * arrowKeyWidthFactor
        let arrowUpHeight = baseKeySize * arrowUpHeightFactor
        let arrowDownHeight = baseKeySize * arrowDownHeightFactor
        
        VStack(spacing: arrowSpacing) {
            ArrowKeyButton(
                systemImage: "chevron.up",
                width: arrowKeyWidth,
                height: arrowUpHeight
            ) {
                onKeyPress(MacKeyCode.upArrow.rawValue)
            }
            HStack(spacing: arrowSpacing) {
                ArrowKeyButton(
                    systemImage: "chevron.left",
                    width: arrowKeyWidth,
                    height: arrowDownHeight
                ) {
                    onKeyPress(MacKeyCode.leftArrow.rawValue)
                }
                ArrowKeyButton(
                    systemImage: "chevron.down",
                    width: arrowKeyWidth,
                    height: arrowDownHeight
                ) {
                    onKeyPress(MacKeyCode.downArrow.rawValue)
                }
                ArrowKeyButton(
                    systemImage: "chevron.right",
                    width: arrowKeyWidth,
                    height: arrowDownHeight
                ) {
                    onKeyPress(MacKeyCode.rightArrow.rawValue)
                }
            }
        }
    }
}

#Preview {
    MacKeyboardView { keyCode, modifiers in
        print("Key: \(keyCode), Modifiers: shift=\(modifiers.shift) ctrl=\(modifiers.control) opt=\(modifiers.option) cmd=\(modifiers.command)")
    }
    .padding()
    .background(Color.black)
}
