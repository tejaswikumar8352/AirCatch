//
//  SettingsView.swift
//  AirCatchHost
//
//  Host preferences: streaming defaults, pairing security, network info.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hostManager = HostManager.shared
    @AppStorage("hostAutoStartOnLaunch") private var autoStartOnLaunch = true
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Streaming") {
                Picker("Preferred framerate", selection: $hostManager.preferredFrameRate) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Text("New streams start at this rate; adaptive logic lowers it if the network congests.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Start listening when AirCatch Host launches", isOn: $autoStartOnLaunch)
                    .help("When off, the host sits idle until you restart it from the app.")
            }

            Section("Pairing & Security") {
                LabeledContent("Current PIN") {
                    Text(String(repeating: "•", count: 6))
                        .font(.system(.body, design: .monospaced))
                }
                Text("The PIN is persisted; tapping “Show PIN” on the main window reveals it. Rotating the PIN unpairs every device.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Reset PIN…", role: .destructive) {
                    showResetConfirm = true
                }
                .alert("Reset PIN and forget all paired devices?", isPresented: $showResetConfirm) {
                    Button("Reset PIN", role: .destructive) {
                        hostManager.resetAllPairings()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Every iPad that has paired before will need to re-pair using the new PIN.")
                }
            }

            Section("Network") {
                LabeledContent("TCP control port", value: "5556 (all interfaces)")
                LabeledContent("UDP video port", value: "5555 (all interfaces)")
                LabeledContent("Discovery", value: "Bonjour (_aircatch._tcp) + direct-IP (Tailscale)")
                Text("Tailscale connections arrive over the utun interface; the host binds to wildcard so it accepts them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Encryption", value: "AES-256-GCM + PBKDF2-SHA256 (200k)")
                Text("Direct-connection only: no relay server, no cloud account.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    SettingsView()
}
