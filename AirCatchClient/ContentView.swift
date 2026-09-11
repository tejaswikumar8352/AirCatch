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

    // Manual direct-IP connection state (e.g., Tailscale address)
    @State private var showManualOverlay = false


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
                            onManualTapped: {
                                showManualOverlay = true
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
            if showManualOverlay {
                ManualConnectOverlay(
                    pin: $clientManager.enteredPIN,
                    audioEnabled: $clientManager.audioEnabled,
                    onConnect: { ipAddress in
                        showManualOverlay = false
                        clientManager.connectManually(toIPAddress: ipAddress, requestVideo: true)
                    },
                    onCancel: {
                        showManualOverlay = false
                        clientManager.enteredPIN = ""
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.snappy(duration: 0.25), value: showPINOverlay)
        .animation(.snappy(duration: 0.25), value: showManualOverlay)
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
    let onManualTapped: () -> Void

    var body: some View {
        ZStack {
            DevicesBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    // Manual Connect Button (direct IP / Tailscale)
                    Button(action: onManualTapped) {
                        HStack {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manual Connect")
                                    .font(.headline)
                                Text("Direct IP or Tailscale address")
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
                    featureRow(icon: "point.3.connected.trianglepath.dotted", text: "Local network and direct IP (Tailscale) modes")
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

// MARK: - Manual Connect Overlay

private struct ManualConnectOverlay: View {
    @Binding var pin: String
    @Binding var audioEnabled: Bool
    let onConnect: (String) -> Void
    let onCancel: () -> Void

    @State private var ipAddress = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case address, pin
    }

    /// Accepts IPv4 (100.12.34.56), IPv6 (fd7a:...), and dotted hostnames.
    private var sanitizedAddress: String {
        ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValidAddress: Bool {
        let address = sanitizedAddress
        guard !address.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF.:")
        return address.rangeOfCharacter(from: allowed.inverted) == nil
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 16) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 36))
                    .foregroundStyle(.purple)

                Text("Manual Connect")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Enter your Mac's IP address (e.g., its Tailscale address like 100.x.y.z) and connection PIN.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Host Address")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("100.12.34.56", text: $ipAddress)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .address)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PIN")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("XXXXXX", text: $pin)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .pin)
                            .onChange(of: pin) { _, newValue in
                                pin = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                            }
                    }

                    Toggle("Stream Audio", isOn: $audioEnabled)
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: 280)

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)

                    Button("Connect", action: { onConnect(sanitizedAddress) })
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(!isValidAddress || pin.count != 6)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: 380)
        }
        .onAppear { focusedField = .address }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClientManager.shared)
}
