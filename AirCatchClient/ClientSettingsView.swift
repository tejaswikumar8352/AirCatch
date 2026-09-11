//
//  ClientSettingsView.swift
//  AirCatchClient
//
//  Client preferences: transports, streaming defaults, paired devices, security.
//

import SwiftUI

struct ClientSettingsView: View {
    @EnvironmentObject var clientManager: ClientManager

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Default Connection
                Section {
                    Picker("Preferred transport", selection: $clientManager.connectionOption) {
                        ForEach(ClientManager.ConnectionOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Text("AWDL is peer-to-peer between devices (faster, no Wi-Fi router needed). Local Network uses your LAN and is more reliable on shared networks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Connection")
                }

                // MARK: - Streaming
                Section {
                    Toggle("Stream audio from Mac", isOn: $clientManager.audioEnabled)
                    Toggle("Optimize for host display resolution", isOn: $clientManager.optimizeForHostDisplay)
                    Text("When off, the stream is scaled to your iPad's screen for pixel-perfect fit. Turn on to keep the host's native resolution (may letterbox).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Streaming")
                }

                // MARK: - Paired Devices
                Section {
                    if clientManager.savedHosts.isEmpty {
                        Text("No paired devices yet. Connect to a host with its PIN — it'll appear here for one-tap reconnect.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(clientManager.savedHosts) { saved in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.name)
                                    .font(.body)
                                if let address = saved.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("Last connected \(saved.lastConnectedAt, style: .relative) ago")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    clientManager.forgetSavedHost(id: saved.id)
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Paired Devices")
                } footer: {
                    Text("Paired devices remember the PIN (stored in your Keychain) so reconnecting never asks again.")
                }

                // MARK: - Security
                Section {
                    LabeledContent("Encryption", value: "AES-256-GCM")
                    LabeledContent("Key derivation", value: "PBKDF2-SHA256 · 200k rounds")
                    LabeledContent("PIN storage", value: "Keychain")
                } header: {
                    Text("Security")
                } footer: {
                    Text("All traffic is end-to-end encrypted. The PIN is used to derive the encryption key and is never transmitted.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ClientSettingsView()
        .environmentObject(ClientManager.shared)
}
