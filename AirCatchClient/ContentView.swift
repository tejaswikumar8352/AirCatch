//
//  ContentView.swift
//  AirCatchClient
//
//  Main client UI (video + touch/scroll only).
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var clientManager: ClientManager

    @State private var sidebarSelection: SidebarItem = .devices
    @State private var selectedHostId: DiscoveredHost.ID?

    @State private var showPINOverlay = false
    @State private var pinTargetHost: DiscoveredHost?
    
    // Relay connection state
    @State private var showRelayOverlay = false
    @AppStorage("relayServerURL") private var relayServerURL = "ws://3.84.120.156:8080"
    @State private var relayRoomCode = ""
    @StateObject private var relayClient = RelayClient()
    @State private var relayError: String?


    fileprivate enum SidebarItem: Hashable {
        case devices
        case about
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
                                clientManager.enteredPIN = ""
                                showPINOverlay = true
                            },
                            onRelayTapped: {
                                showRelayOverlay = true
                            }
                        )
                    case .about:
                        AboutScreen()
                    }
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
            if showPINOverlay {
                PINEntryOverlay(
                    hostName: pinTargetHost?.name ?? "Mac",
                    pin: $clientManager.enteredPIN,
                    audioEnabled: $clientManager.audioEnabled,
                    connectionOption: $clientManager.connectionOption,
                    showsQualityOptions: true,
                    onConnect: {
                        guard let host = pinTargetHost else {
                            showPINOverlay = false
                            return
                        }
                        showPINOverlay = false
                        clientManager.connect(to: host, requestVideo: true)
                    },
                    onCancel: {
                        showPINOverlay = false
                        pinTargetHost = nil
                        clientManager.enteredPIN = ""
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .overlay {
            if showRelayOverlay {
                RelayConnectOverlay(
                    serverURL: $relayServerURL,
                    roomCode: $relayRoomCode,
                    audioEnabled: $clientManager.audioEnabled,
                    error: relayError,
                    isConnecting: relayClient.isConnected && !relayClient.hostConnected,
                    onConnect: {
                        relayError = nil
                        clientManager.relayPINOverride = relayRoomCode
                        relayClient.connect(to: relayServerURL, roomCode: relayRoomCode)
                    },
                    onCancel: {
                        showRelayOverlay = false
                        relayClient.disconnect()
                        relayRoomCode = ""
                        relayError = nil
                        clientManager.stopRelaySession(shouldRestartDiscovery: false)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.snappy(duration: 0.25), value: showPINOverlay)
        .animation(.snappy(duration: 0.25), value: showRelayOverlay)
        .onAppear {
            setupRelayCallbacks()
        }
    }
    
    private func setupRelayCallbacks() {
        relayClient.onHostConnected = { [self] in
            showRelayOverlay = false
            clientManager.startRelaySession(with: relayClient)
            AirCatchLog.info("Host connected via relay - ready to stream")
        }

        relayClient.onHostDisconnected = { [self] in
            clientManager.stopRelaySession()
        }

        relayClient.onDisconnected = { [self] _ in
            clientManager.stopRelaySession(shouldRestartDiscovery: false)
        }
        
        relayClient.onError = { error in
            relayError = error
        }
        
        relayClient.onDataReceived = { data in
            // Forward received data to ClientManager for video/audio processing
            AirCatchLog.info("📥 Client received \(data.count) bytes from relay")
            guard data.count >= 5 else { 
                AirCatchLog.error("📥 Packet too small: \(data.count) bytes")
                return 
            }
            let type = data[0]
            let length = Int(UInt32(data[1]) << 24 | UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4]))
            let payloadStart = 5
            let payloadEnd = min(data.count, payloadStart + length)
            guard payloadEnd >= payloadStart else { 
                AirCatchLog.error("📥 Invalid payload bounds")
                return 
            }
            let payload = data[payloadStart..<payloadEnd]
            
            if let packetType = PacketType(rawValue: type) {
                AirCatchLog.info("📥 Client received packet type: \(packetType)")
                let packet = Packet(type: packetType, payload: Data(payload))
                Task { @MainActor in
                    ClientManager.shared.handleRelayPacket(packet)
                }
            } else {
                AirCatchLog.error("📥 Unknown packet type: \(type)")
            }
        }
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

// MARK: - Devices

private struct DevicesScreen: View {
    @EnvironmentObject var clientManager: ClientManager
    @Binding var selectedHostId: DiscoveredHost.ID?

    let onConnectTapped: (DiscoveredHost) -> Void
    let onRelayTapped: () -> Void

    var body: some View {
        ZStack {
            DevicesBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    
                    // Remote Relay Button
                    Button(action: onRelayTapped) {
                        HStack {
                            Image(systemName: "globe")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remote Relay")
                                    .font(.headline)
                                Text("Connect via cloud server")
                                    .font(.caption)
                                    .opacity(0.7)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .opacity(0.55)
                        }
                        .foregroundStyle(.white)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.25), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Text("Local Network")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 8)

                    if clientManager.discoveredHosts.isEmpty {
                        Text("Searching for AirCatch Hosts…")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.vertical, 18)
                    } else {
                        ForEach(clientManager.discoveredHosts) { host in
                            HostCard(
                                host: host,
                                isSelected: selectedHostId == host.id,
                                onTap: {
                                    selectedHostId = host.id
                                    onConnectTapped(host)
                                }
                            )
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        Text("Devices")
            .font(.title2.bold())
            .foregroundStyle(.white)
    }
}

private struct HostCard: View {
    let host: DiscoveredHost
    let isSelected: Bool
    let onTap: () -> Void

    private var subtitle: String {
        if host.mpcPeerName != nil && host.endpoint != nil {
            return "P2P + Local network"
        } else if host.mpcPeerName != nil {
            return "P2P available"
        }
        return "Local network"
    }
    
    private var statusColor: Color {
        if host.mpcPeerName != nil {
            return .green
        }
        return .blue
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(host.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }

                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }

                if let udp = host.udpPort, let tcp = host.tcpPort {
                    Text("UDP \(udp) · TCP \(tcp)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}


private struct DevicesBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.10, blue: 0.16),
                Color(red: 0.05, green: 0.06, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [Color.accentColor.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 60,
                endRadius: 520
            )
        }
    }
}

// MARK: - About

private struct AboutScreen: View {
    var body: some View {
        ZStack {
            DevicesBackground().ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "display")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)

                Text("AirCatch")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Stream your Mac to iPad wirelessly")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                Divider()
                    .background(.white.opacity(0.3))
                    .padding(.horizontal, 40)
                
                VStack(alignment: .leading, spacing: 12) {
                    featureRow(icon: "bolt.fill", text: "Ultra-low latency HEVC streaming")
                    featureRow(icon: "lock.shield.fill", text: "End-to-end encrypted (AES-256-GCM)")
                    featureRow(icon: "display.2", text: "Pixel-perfect display matching")
                    featureRow(icon: "globe", text: "Local network and P2P modes")
                    featureRow(icon: "hand.tap.fill", text: "Full touch & keyboard support")
                }
                .padding(.horizontal, 20)
                
                Text("Version 1.0")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - PIN Overlay

private struct PINEntryOverlay: View {
    let hostName: String
    @Binding var pin: String
    @Binding var audioEnabled: Bool
    @Binding var connectionOption: ClientManager.ConnectionOption
    let showsQualityOptions: Bool
    let onConnect: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                Text("Connect to \(hostName)")
                    .font(.headline)
                    .foregroundStyle(.primary)

                TextField("PIN", text: $pin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .onChange(of: pin) { _, newValue in
                        // Allow uppercase letters and digits, max 6 chars
                        pin = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)

                VStack(alignment: .leading, spacing: 10) {
                    if showsQualityOptions {
                        HStack {
                            Text("Connection")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $connectionOption) {
                                ForEach(ClientManager.ConnectionOption.allCases) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                    
                    // Audio toggle available for all modes
                    Toggle("Stream Audio", isOn: $audioEnabled)
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: 260, alignment: .leading)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)

                    Button("Connect", action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.count != 6)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 380)
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Relay Connect Overlay

private struct RelayConnectOverlay: View {
    @Binding var serverURL: String
    @Binding var roomCode: String
    @Binding var audioEnabled: Bool
    let error: String?
    let isConnecting: Bool
    let onConnect: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case serverURL, roomCode
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }
            
            VStack(spacing: 16) {
                Image(systemName: "globe")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)
                
                Text("Remote Relay Connection")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Connect to your Mac through a relay server when not on the same network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Relay Server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("ws://3.84.120.156:8080", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .serverURL)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Room Code / Master Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("XXXXXX", text: $roomCode)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .roomCode)
                            .onChange(of: roomCode) { _, newValue in
                                roomCode = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            }
                    }

                    Toggle("Stream Audio", isOn: $audioEnabled)
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: 280)
                
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                
                if isConnecting {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                    
                    let hasRoomCode = roomCode.count == 6
                    Button("Connect", action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(serverURL.count < 10 || !hasRoomCode || isConnecting)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 380)
        }
        .onAppear { focusedField = .roomCode }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClientManager.shared)
}
