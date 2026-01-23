
import SwiftUI

struct HostView: View {
    @ObservedObject private var hostManager = HostManager.shared
    @State private var isStreaming = false
    
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
                    .fill(hostManager.isRunning ? (isStreaming ? Color.green : Color.orange) : Color.red)
                    .frame(width: 10, height: 10)
                Text(hostManager.statusDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .padding(.horizontal)
            
            // PIN Display
            VStack(spacing: 8) {
                Text("Connection PIN")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(Array(hostManager.currentPIN.enumerated()), id: \.offset) { index, char in
                        Text(String(char))
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .frame(width: 36, height: 50)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 8)
                
                Text("Enter this PIN on your iPad")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            // Connection status
            if isStreaming {
                VStack(spacing: 6) {
                    Label("Streaming Active", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    Text("\(hostManager.currentQuality.displayName) • \(hostManager.currentQuality.bitrate / 1_000_000) Mbps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else if hostManager.isRunning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for connection...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                Label("Host Stopped", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Divider()
                .padding(.horizontal)
            
            // Controls
            HStack {
                Button(action: {
                    hostManager.regeneratePIN()
                }) {
                    Label("New PIN", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: hostManager.connectedClients > 0 ? "ipad.and.arrow.forward" : "ipad")
                        .foregroundColor(hostManager.connectedClients > 0 ? .green : .secondary)
                    Text("\\(hostManager.connectedClients) client\\(hostManager.connectedClients == 1 ? \"\" : \"s\")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 350)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: HostManager.statusDidChange)) { _ in
            isStreaming = HostManager.shared.isStreaming
        }
    }
}
