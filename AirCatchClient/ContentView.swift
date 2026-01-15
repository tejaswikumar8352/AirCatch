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
                    selectedPreset: $clientManager.selectedPreset,
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
        .animation(.snappy(duration: 0.25), value: showPINOverlay)
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

    var body: some View {
        ZStack {
            DevicesBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    RemoteHostCard {
                        clientManager.connectionOption = .remote
                        let remoteHost = DiscoveredHost(id: "remote", name: "Remote Host")
                        selectedHostId = remoteHost.id
                        onConnectTapped(remoteHost)
                    }

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
        if host.mpcPeerName != nil { return "P2P available" }
        return "Local network"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.name)
                            .font(.headline)
                            .foregroundStyle(.white)

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

private struct RemoteHostCard: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Host")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Connect over the internet")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: "globe")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Text("Requires relay server")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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

            VStack(spacing: 16) {
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
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - PIN Overlay

private struct PINEntryOverlay: View {
    let hostName: String
    @Binding var pin: String
    @Binding var selectedPreset: QualityPreset
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
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .onChange(of: pin) { _, newValue in
                        pin = String(newValue.filter { $0.isNumber }.prefix(4))
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)

                if showsQualityOptions {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Quality", selection: $selectedPreset) {
                            ForEach(QualityPreset.allCases, id: \.self) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Connection", selection: $connectionOption) {
                            ForEach(ClientManager.ConnectionOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        Toggle("Stream Audio", isOn: $audioEnabled)
                            .toggleStyle(.switch)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)

                    Button("Connect", action: onConnect)
                        .buttonStyle(.borderedProminent)
                        .disabled(pin.count != 4)
                }
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 380)
        }
        .onAppear { isFocused = true }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClientManager.shared)
}
