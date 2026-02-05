
import SwiftUI

struct HostView: View {
    @ObservedObject private var hostManager = HostManager.shared
    @State private var isStreaming = false
    
    // Relay mode settings
    @AppStorage("useRelayMode") private var useRelayMode = false
    @AppStorage("relayServerURL") private var relayServerURL = "ws://"
    @State private var relayRoomCode = ""
    @State private var isRelayConnected = false
    @State private var isClientConnected = false
    @State private var relayError: String?
    
    // Relay client instance
    @StateObject private var relayClient = RelayClient()
    
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
            
            // Connection Mode Toggle
            Picker("Mode", selection: $useRelayMode) {
                Text("Local (LAN)").tag(false)
                Text("Remote Relay").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: useRelayMode) { _, newValue in
                if !newValue {
                    relayClient.disconnect()
                    relayRoomCode = ""
                    isRelayConnected = false
                    isClientConnected = false
                }
            }
            
            if useRelayMode {
                // Relay Mode UI
                relayModeSection
            } else {
                // Local Mode UI (PIN)
                localModeSection
            }
            
            // Connection status
            connectionStatusSection
            
            Divider()
                .padding(.horizontal)
            
            // Controls
            HStack {
                if useRelayMode {
                    Button(action: {
                        if isRelayConnected {
                            relayClient.disconnect()
                        } else {
                            connectToRelay()
                        }
                    }) {
                        Label(isRelayConnected ? "Disconnect" : "Connect", 
                              systemImage: isRelayConnected ? "wifi.slash" : "wifi")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: {
                        hostManager.regeneratePIN()
                    }) {
                        Label("New PIN", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                
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
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: HostManager.statusDidChange)) { _ in
            isStreaming = HostManager.shared.isStreaming
        }
        .onAppear {
            setupRelayCallbacks()
        }
    }
    
    // MARK: - Subviews
    
    private var localModeSection: some View {
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
    }
    
    private var relayModeSection: some View {
        VStack(spacing: 12) {
            // Relay Server URL
            VStack(alignment: .leading, spacing: 4) {
                Text("Relay Server")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("ws://your-ec2-ip:8080", text: $relayServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(isRelayConnected)
            }
            .padding(.horizontal)
            
            // Room Code Display
            if isRelayConnected && !relayRoomCode.isEmpty {
                VStack(spacing: 8) {
                    Text("Room Code")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 4) {
                        ForEach(Array(relayRoomCode.enumerated()), id: \.offset) { _, char in
                            Text(String(char))
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .frame(width: 32, height: 44)
                                .background(Color.purple.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    
                    Text("Share this code with iPad client")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            // Error display
            if let error = relayError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
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
            } else if useRelayMode && isRelayConnected {
                if isClientConnected {
                    Label("Client connected via relay", systemImage: "checkmark.circle")
                        .foregroundColor(.green)
                        .padding()
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for client to join...")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            } else if hostManager.isRunning && !useRelayMode {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for connection...")
                        .foregroundColor(.secondary)
                }
                .padding()
            } else if useRelayMode && !isRelayConnected {
                Label("Not connected to relay", systemImage: "wifi.exclamationmark")
                    .foregroundColor(.orange)
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
        if useRelayMode {
            if isClientConnected { return .green }
            if isRelayConnected { return .orange }
            return .red
        } else {
            if hostManager.isRunning {
                return isStreaming ? .green : .orange
            }
            return .red
        }
    }
    
    private var statusDescription: String {
        if useRelayMode {
            if isClientConnected { return "Client Connected" }
            if isRelayConnected { return "Waiting for Client" }
            return "Relay Disconnected"
        } else {
            return hostManager.statusDescription
        }
    }
    
    // MARK: - Methods
    
    private func connectToRelay() {
        relayError = nil
        relayClient.connect(to: relayServerURL, roomCode: nil)
    }
    
    private func setupRelayCallbacks() {
        relayClient.onConnected = { [self] in
            isRelayConnected = true
            relayRoomCode = relayClient.roomCode
            relayError = nil
        }
        
        relayClient.onDisconnected = { _ in
            isRelayConnected = false
            isClientConnected = false
            relayRoomCode = ""
        }
        
        relayClient.onClientConnected = { [self] in
            isClientConnected = true
            // Set the relay client on HostManager so it can send video through it
            HostManager.shared.relayClient = relayClient
        }
        
        relayClient.onClientDisconnected = { [self] in
            isClientConnected = false
            // Stop streaming when client disconnects
            Task { @MainActor in
                HostManager.shared.stopRelayStreaming()
                HostManager.shared.relayClient = nil
            }
        }
        
        relayClient.onError = { error in
            relayError = error
        }
        
        // Forward received data to HostManager for processing
        relayClient.onDataReceived = { data in
            // Parse packet and handle via HostManager
            // This will be the input events from client
            guard data.count >= 5 else { return }
            let type = data[0]
            let length = Int(UInt32(data[1]) << 24 | UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4]))
            let payloadStart = 5
            let payloadEnd = min(data.count, payloadStart + length)
            guard payloadEnd >= payloadStart else { return }
            let payload = data[payloadStart..<payloadEnd]
            
            if let packetType = PacketType(rawValue: type) {
                let packet = Packet(type: packetType, payload: Data(payload))
                // Process packet through HostManager (touch, scroll, key events)
                Task { @MainActor in
                    HostManager.shared.handleRelayPacket(packet)
                }
            }
        }
    }
}
