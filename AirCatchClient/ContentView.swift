//
//  ContentView.swift
//  AirCatchClient
//
//  Created by teja on 12/14/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var clientManager: ClientManager
    @State private var showPINSheet = false
    @State private var pinTargetHost: DiscoveredHost?
    @State private var pendingConnectIntent: ConnectIntent?
    @State private var selectedHostId: DiscoveredHost.ID?
    @State private var sidebarSelection: SidebarItem = .devices
    @State private var showInputOverlay = false

    private enum ConnectIntent {
        case video
        case input(keyboard: Bool, trackpad: Bool)
    }

    fileprivate enum SidebarItem: Hashable {
        case devices
        case about
    }

    private var selectedHost: DiscoveredHost? {
        guard let selectedHostId else { return nil }
        return clientManager.discoveredHosts.first(where: { $0.id == selectedHostId })
    }
    
    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom != .pad {
                Text("AirCatchClient is iPad-only")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            } else {
                NavigationSplitView {
                    Sidebar(selection: $sidebarSelection)
                } detail: {
                    switch sidebarSelection {
                    case .devices:
                        DevicesScreen(
                            selectedHostId: $selectedHostId,
                            onConnectTapped: { host in
                                pinTargetHost = host
                                pendingConnectIntent = .video
                                clientManager.enteredPIN = ""
                                showPINSheet = true
                            },
                            onKeyboardTapped: {
                                startOrToggleInputSession(keyboard: true, trackpad: clientManager.trackpadEnabled)
                            },
                            onTrackpadTapped: {
                                startOrToggleInputSession(keyboard: clientManager.keyboardEnabled, trackpad: true)
                            },
                            onKeyboardOffTapped: {
                                startOrToggleInputSession(keyboard: false, trackpad: clientManager.trackpadEnabled)
                            },
                            onTrackpadOffTapped: {
                                startOrToggleInputSession(keyboard: clientManager.keyboardEnabled, trackpad: false)
                            }
                        )
                    case .about:
                        AboutScreen()
                    }
                }
                .fullScreenCover(isPresented: $showInputOverlay) {
                    InputSessionOverlay(
                        keyboardEnabled: $clientManager.keyboardEnabled,
                        trackpadEnabled: $clientManager.trackpadEnabled,
                        onClose: {
                            clientManager.endInputSession()
                            showInputOverlay = false
                        }
                    )
                    .environmentObject(clientManager)
                }
                .overlay {
                    if clientManager.videoRequested && (clientManager.state == .connected || clientManager.state == .streaming) {
                        VideoStreamOverlay()
                            .environmentObject(clientManager)
                            .transition(.opacity)
                    }
                }
            }
        }
        .onAppear { clientManager.startDiscovery() }
        .overlay {
            if showPINSheet {
                PINEntryOverlay(
                    hostName: pinTargetHost?.name ?? "Mac",
                    pin: $clientManager.enteredPIN,
                    selectedPreset: $clientManager.selectedPreset,
                    connectionOption: $clientManager.connectionOption,
                    showsQualityOptions: {
                        if case .video? = pendingConnectIntent { return true }
                        return false
                    }(),
                    onConnect: {
                        guard let host = pinTargetHost, let intent = pendingConnectIntent else {
                            showPINSheet = false
                            return
                        }
                        showPINSheet = false
                        switch intent {
                        case .video:
                            clientManager.connect(to: host, requestVideo: true)
                        case .input(let keyboard, let trackpad):
                            clientManager.beginInputSession(host: host, keyboard: keyboard, trackpad: trackpad)
                            showInputOverlay = keyboard || trackpad
                        }
                        pendingConnectIntent = nil
                    },
                    onCancel: {
                        showPINSheet = false
                        pinTargetHost = nil
                        pendingConnectIntent = nil
                        clientManager.enteredPIN = ""
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.snappy(duration: 0.25), value: showPINSheet)
    }

    private func title(for item: SidebarItem) -> String {
        switch item {
        case .devices: return "Devices"
        case .about: return "About"
        }
    }

    private func startOrToggleInputSession(keyboard: Bool, trackpad: Bool) {
        let host = selectedHost ?? clientManager.discoveredHosts.first
        guard let host else { return }

        // If input is already bound to a Mac, keep it bound until turned off.
        if let bound = clientManager.inputBoundHost, bound != host {
            showInputOverlay = true
            return
        }

        // If already connected to this host, apply immediately.
        if (clientManager.state == .connected || clientManager.state == .streaming), clientManager.connectedHost == host {
            clientManager.beginInputSession(host: host, keyboard: keyboard, trackpad: trackpad)
            showInputOverlay = keyboard || trackpad
            if !(keyboard || trackpad) {
                clientManager.endInputSession()
            }
            return
        }

        pinTargetHost = host
        pendingConnectIntent = .input(keyboard: keyboard, trackpad: trackpad)
        clientManager.enteredPIN = ""
        showPINSheet = true
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var selection: ContentView.SidebarItem

    var body: some View {
        List {
            Section {
                sidebarRow(.devices, title: "Devices", systemImage: "display")
                sidebarRow(.about, title: "About", systemImage: "info.circle")
            }
        }
        .navigationTitle("AirCatch")
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func sidebarRow(_ item: ContentView.SidebarItem, title: String, systemImage: String) -> some View {
        Button {
            selection = item
        } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Devices Screen

private struct DevicesScreen: View {
    @EnvironmentObject var clientManager: ClientManager
    @Binding var selectedHostId: DiscoveredHost.ID?

    let onConnectTapped: (DiscoveredHost) -> Void
    let onKeyboardTapped: () -> Void
    let onTrackpadTapped: () -> Void
    let onKeyboardOffTapped: () -> Void
    let onTrackpadOffTapped: () -> Void

    var body: some View {
        ZStack {
            DevicesBackground()
                .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    HStack(alignment: .center, spacing: 20) {
                        Spacer(minLength: 0)
                        cardsContent
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
            }
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var cardsContent: some View {
        if clientManager.discoveredHosts.isEmpty {
            // Scanning card
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Scanning nearby…")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 220, height: 240)
            .airCatchCard(cornerRadius: 24)
        } else {
            ForEach(clientManager.discoveredHosts) { host in
                DeviceCard(
                    host: host,
                    isConnecting: clientManager.state == .connecting && clientManager.connectedHost == host,
                    onConnect: { onConnectTapped(host) }
                )
            }
            
            InputCard(
                keyboardEnabled: clientManager.keyboardEnabled,
                trackpadEnabled: clientManager.trackpadEnabled,
                onKeyboardTapped: onKeyboardTapped,
                onTrackpadTapped: onTrackpadTapped,
                onKeyboardOffTapped: onKeyboardOffTapped,
                onTrackpadOffTapped: onTrackpadOffTapped
            )
        }
    }
}

private struct DevicesBackground: View {
    var body: some View {
        // Try loading from asset catalog first, then from bundle
        Group {
            if let uiImage = UIImage(named: "bg") ?? UIImage(named: "bg.jpeg") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback gradient if image not found
                Color(uiColor: .systemBackground)
            }
        }
        .ignoresSafeArea()
    }
}

private struct DeviceCard: View {
    let host: DiscoveredHost
    let isConnecting: Bool
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: icon
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.title.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                Spacer()
            }
            
            Spacer()
            
            // Device name and status
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(isConnecting ? "Connecting…" : "Ready to Connect")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer().frame(height: 16)
            
            // Connect button
            Button(action: onConnect) {
                if isConnecting {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                } else {
                    Text("Connect")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                }
            }
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(20)
        .frame(width: 220, height: 260)
        .airCatchCard(cornerRadius: 24)
    }
}

private struct InputCard: View {
    let keyboardEnabled: Bool
    let trackpadEnabled: Bool
    let onKeyboardTapped: () -> Void
    let onTrackpadTapped: () -> Void
    let onKeyboardOffTapped: () -> Void
    let onTrackpadOffTapped: () -> Void

    private var trackpadSymbolName: String {
        if UIImage(systemName: "trackpad") != nil {
            return "trackpad"
        }
        return "rectangle.and.hand.point.up.left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: icon
            HStack {
                Image(systemName: "keyboard")
                    .font(.title.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                
                Spacer()
            }
            
            Spacer()
            
            // Title and status
            VStack(alignment: .leading, spacing: 4) {
                Text("Magic Keyboard & Trackpad")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Ready to Use")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            
            Spacer().frame(height: 16)
            
            // Toggle buttons
            HStack(spacing: 10) {
                InputToggleButton(
                    title: "Keyboard",
                    isOn: keyboardEnabled,
                    onTap: { keyboardEnabled ? onKeyboardOffTapped() : onKeyboardTapped() }
                )
                InputToggleButton(
                    title: "Trackpad",
                    isOn: trackpadEnabled,
                    onTap: { trackpadEnabled ? onTrackpadOffTapped() : onTrackpadTapped() }
                )
            }
        }
        .padding(20)
        .frame(width: 220, height: 260)
        .airCatchCard(cornerRadius: 24)
    }
}

private struct InputToggleButton: View {
    let title: String
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
        }
        .background(
            isOn ? Color.accentColor : Color.white.opacity(0.2),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .animation(.snappy(duration: 0.18), value: isOn)
    }
}

private struct CapsuleToggleButton: View {
    let title: String
    let isOn: Bool
    let onOn: () -> Void
    let onOff: () -> Void

    var body: some View {
        Button(action: { isOn ? onOff() : onOn() }) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minWidth: 92)
        }
        .buttonStyle(.bordered)
        .tint(isOn ? .accentColor : .secondary)
        .animation(.snappy(duration: 0.18), value: isOn)
    }
}

private struct QualityControls: View {
    @Binding var selectedPreset: QualityPreset
    @Binding var connectionOption: ClientManager.ConnectionOption

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality")
                .font(.headline)

            QualityPresetSlider(preset: $selectedPreset)

            HStack {
                Text("Clarity\n(30fps)")
                Spacer()
                Text("Balanced\n(45fps)")
                Spacer()
                Text("Smooth\n(60fps)")
                Spacer()
                Text("Max\n(60fps)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(selectedPreset.description)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                Text("Connection")
                    .font(.subheadline)
                Spacer()
                Picker("Connection", selection: $connectionOption) {
                    ForEach(ClientManager.ConnectionOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(18)
        .airCatchCard(cornerRadius: 22)
    }
}

private struct AirCatchCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // Blur layer that lets background show through
                    TransparentBlurView()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    // Subtle tint for legibility
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(colorScheme == .dark
                              ? Color.white.opacity(0.08)
                              : Color.black.opacity(0.03))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }
}

/// A UIKit-backed blur that is truly translucent (shows background through).
private struct TransparentBlurView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let view = UIVisualEffectView(effect: blurEffect)
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

private extension View {
    func airCatchCard(cornerRadius: CGFloat) -> some View {
        modifier(AirCatchCardModifier(cornerRadius: cornerRadius))
    }
}

private struct QualityPresetSlider: View {
    @Binding var preset: QualityPreset
    @State private var position: CGFloat = 1
    @GestureState private var isDragging = false

    private let stepCount: Int = 4
    private let baseThumbWidth: CGFloat = 54
    private let pressedThumbWidth: CGFloat = 78
    private let baseThumbHeight: CGFloat = 32
    private let pressedThumbHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let trackWidth = max(1, geo.size.width)
            let usableWidth = max(1, trackWidth - baseThumbWidth)
            let currentThumbWidth = isDragging ? pressedThumbWidth : baseThumbWidth
            let currentThumbHeight = isDragging ? pressedThumbHeight : baseThumbHeight
            let thumbCenterX = thumbCenterX(trackWidth: trackWidth, usableWidth: usableWidth)
            let thumbLeftX = thumbCenterX - (currentThumbWidth / 2)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.secondary.opacity(0.22))
                    .frame(height: 6)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(.tint.opacity(0.35))
                    .frame(width: thumbCenterX, height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)

                Capsule(style: .circular)
                    .fill(.ultraThinMaterial.opacity(isDragging ? 0.65 : 1.0))
                    .frame(width: currentThumbWidth, height: currentThumbHeight)
                    .overlay {
                        Capsule(style: .circular)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                    .offset(x: thumbLeftX)
            }
            .contentShape(Rectangle())
            .onAppear {
                position = CGFloat(index(for: preset))
            }
            .onChange(of: preset) { _, newValue in
                if !isDragging {
                    withAnimation(.snappy(duration: 0.22)) {
                        position = CGFloat(index(for: newValue))
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { value in
                        let minCenterX = baseThumbWidth / 2
                        let maxCenterX = trackWidth - (baseThumbWidth / 2)
                        let clampedCenterX = min(max(minCenterX, value.location.x), maxCenterX)
                        let percent = (clampedCenterX - minCenterX) / usableWidth
                        let newPosition = percent * CGFloat(stepCount - 1)
                        position = newPosition

                        let snapped = Int(round(newPosition))
                        let newPreset = preset(for: snapped)
                        if newPreset != preset {
                            preset = newPreset
                        }
                    }
                    .onEnded { _ in
                        let snapped = CGFloat(index(for: preset))
                        withAnimation(.snappy(duration: 0.22)) {
                            position = snapped
                        }
                    }
            )
            .animation(.snappy(duration: 0.18), value: isDragging)
        }
        .frame(height: 36)
        .accessibilityValue(Text(preset.displayName))
    }

    private func thumbCenterX(trackWidth: CGFloat, usableWidth: CGFloat) -> CGFloat {
        let clamped = min(max(0, position), CGFloat(stepCount - 1))
        let percent = clamped / CGFloat(stepCount - 1)
        let minCenterX = baseThumbWidth / 2
        let maxCenterX = trackWidth - (baseThumbWidth / 2)
        return minCenterX + percent * (maxCenterX - minCenterX)
    }

    private func preset(for index: Int) -> QualityPreset {
        switch min(max(0, index), 3) {
        case 0: return .clarity
        case 1: return .balanced
        case 2: return .smooth
        default: return .max
        }
    }

    private func index(for preset: QualityPreset) -> Int {
        switch preset {
        case .clarity: return 0
        case .balanced: return 1
        case .smooth: return 2
        case .max: return 3
        }
    }
}

// MARK: - About Screen

private struct AboutScreen: View {
    var body: some View {
        ZStack {
            DevicesBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "display")
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
                
                Text("AirCatch")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                
                Text("Version 1.0")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                
                Text("Stream your Mac to iPad wirelessly")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(40)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PIN Entry Overlay

private struct PINEntryOverlay: View {
    let hostName: String
    @Binding var pin: String
    @Binding var selectedPreset: QualityPreset
    @Binding var connectionOption: ClientManager.ConnectionOption
    let showsQualityOptions: Bool
    let onConnect: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Dim background - tap to cancel
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            // Native system material panel
            VStack(spacing: 24) {
                // Header
                Text("Enter PIN")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                // PIN Dots Display
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        PINDotView(isFilled: index < pin.count, isActive: index == pin.count)
                    }
                }
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }

                // Hidden text field for keyboard input
                TextField("", text: $pin)
                    .keyboardType(.numberPad)
                    .focused($isFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .onChange(of: pin) { _, newValue in
                        if newValue.count > 4 {
                            pin = String(newValue.prefix(4))
                        }
                        pin = newValue.filter { $0.isNumber }
                    }

                if showsQualityOptions {
                    VStack(spacing: 12) {
                        // Quality Section - with container
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Quality")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            
                            HStack(spacing: 2) {
                                ForEach(QualityPreset.allCases, id: \.self) { preset in
                                    QualityOptionButton(
                                        title: preset.shortName,
                                        isSelected: selectedPreset == preset,
                                        onTap: { selectedPreset = preset }
                                    )
                                }
                            }
                            .padding(4)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        
                        // Connection Section - with container
                        HStack {
                            Text("Connection")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Picker("", selection: $connectionOption) {
                                ForEach(ClientManager.ConnectionOption.allCases) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.primary)
                        }
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }

                // Buttons
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button(action: onConnect) {
                        Text("Connect")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .background(
                        pin.count == 4 ? Color.accentColor : Color.accentColor.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .disabled(pin.count != 4)
                }
            }
            .padding(24)
            .frame(width: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.2), radius: 40, x: 0, y: 20)
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - PIN Dot View

private struct PINDotView: View {
    let isFilled: Bool
    let isActive: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 2)
                .frame(width: 44, height: 44)
            
            if isFilled {
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
            } else if isActive {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.white.opacity(0.8))
                    .frame(width: 2, height: 20)
            }
        }
    }
}

// MARK: - Quality Option Button

private struct QualityOptionButton: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.white.opacity(0.25) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isSelected)
    }
}

#Preview {
    ContentView()
        .environmentObject(ClientManager.shared)
}
