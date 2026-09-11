
import SwiftUI

struct HostView: View {
    @ObservedObject private var hostManager = HostManager.shared
    @State private var isStreaming = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 20) {
            // App Icon
            Image(systemName: "display.2")
                .font(.system(size: 48))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .padding(.top, 20)

            Text("AirCatch Host")
                .font(.title)
                .fontWeight(.bold)

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal)

            // Pairing section — PIN is hidden by default; revealed on request or via the button
            pairingSection

            // Connection status
            connectionStatusSection

            Divider()
                .padding(.horizontal)

            // Controls
            HStack {
                Button(action: { showSettings = true }) {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: hostManager.connectedClients > 0 ? "ipad.and.arrow.forward" : "ipad")
                        .foregroundColor(hostManager.connectedClients > 0 ? .green : .secondary)
                    Text("\(hostManager.connectedClients) client\(hostManager.connectedClients == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: HostManager.statusDidChange)) { _ in
            isStreaming = HostManager.shared.isStreaming
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .frame(minWidth: 460, minHeight: 420)
        }
    }

    // MARK: - Subviews

    /// Pairing area: PIN hidden until a paired request arrives or the user presses "Show PIN".
    private var pairingSection: some View {
        VStack(spacing: 10) {
            if hostManager.pairingRequested {
                HStack(spacing: 6) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundColor(.accentColor)
                    Text("An iPad is asking to pair")
                        .font(.subheadline.weight(.semibold))
                }

                pinDisplay
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                Button(action: { hostManager.acknowledgePairingRequest() }) {
                    Text("Done")
                        .frame(minWidth: 90)
                }
                .buttonStyle(.bordered)
            } else {
                Text("Pairing PIN is hidden")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("To pair a new iPad, tap its entry on the iPad — the PIN appears here.\nYou can also reveal it manually below.")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)

                Button(action: { hostManager.revealPINManually() }) {
                    Text("Show PIN")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var pinDisplay: some View {
        HStack(spacing: 4) {
            ForEach(Array(hostManager.currentPIN.enumerated()), id: \.offset) { _, char in
                Text(String(char))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .frame(width: 36, height: 50)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    private var connectionStatusSection: some View {
        Group {
            if isStreaming {
                VStack(spacing: 6) {
                    Label("Streaming Active", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text("Adaptive • \(hostManager.currentBitrate / 1_000_000) Mbps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else if hostManager.isRunning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Listening for connections…")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                Label("Host Stopped", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .padding()
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if hostManager.isRunning {
            return isStreaming ? .green : .orange
        }
        return .red
    }

    private var statusDescription: String {
        hostManager.statusDescription
    }
}
