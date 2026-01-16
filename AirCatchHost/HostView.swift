
import SwiftUI

struct HostView: View {
    @ObservedObject private var hostManager = HostManager.shared
    @State private var isStreaming = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.2")
                .font(.system(size: 48))
                .foregroundColor(.blue)
                .padding(.top, 20)
            
            Text("AirCatch Host")
                .font(.title)
                .fontWeight(.bold)
            
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
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 8)
            }
            
            if isStreaming {
                Label("Streaming Active", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1), in: Capsule())
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for connection...")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            Divider()
                .padding(.horizontal)
            
            HStack {
                Button(action: {
                    hostManager.regeneratePIN()
                }) {
                    Label("New PIN", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("\(hostManager.connectedClients) clients")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .frame(width: 350)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StreamingStatusChanged"))) { _ in
            isStreaming = HostManager.shared.isStreaming
        }
    }
}
