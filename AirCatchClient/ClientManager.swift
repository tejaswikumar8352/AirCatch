//
//  ClientManager.swift
//  AirCatchClient
//
//  Orchestrates network discovery, connection, and video stream handling.
//

import Foundation
import Network
import Combine
import UIKit
import MultipeerConnectivity

/// Connection state machine
enum ConnectionState: Equatable {
    case disconnected
    case discovering
    case connecting
    case connected
    case streaming
    case error(String)
    
    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.discovering, .discovering),
             (.connecting, .connecting),
             (.connected, .connected),
             (.streaming, .streaming):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Central manager for the AirCatch client.
@MainActor
final class ClientManager: ObservableObject {
    static let shared = ClientManager()

    enum ConnectionOption: String, CaseIterable, Identifiable {
        case udpPeerToPeerAWDL = "udp_p2p_awdl"
        case udpNetworkFramework = "udp_network"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .udpPeerToPeerAWDL:
                return "UDP + P2P (AWDL)"
            case .udpNetworkFramework:
                return "UDP + Network"
            }
        }

        var includePeerToPeer: Bool {
            switch self {
            case .udpPeerToPeerAWDL:
                return true
            case .udpNetworkFramework:
                return false
            }
        }
    }
    
    // MARK: - Published State
    
    @Published var state: ConnectionState = .disconnected
    // REMOVED: @Published var latestFrameData: Data? - Causes SwiftUI thrashing
    
    // High-performance video path (Direct to Metal)
    let videoFrameSubject = PassthroughSubject<Data, Never>()
    
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var connectedHost: DiscoveredHost?
    @Published var screenInfo: HandshakeAck?
    
    /// Debug: Distance to detected surface
    @Published var debugDistance: Float?
    
    /// Debug: Detailed connection status
    @Published var debugConnectionStatus: String = "Idle"
    
    /// PIN entered by user for pairing
    @Published var enteredPIN: String = ""
    
    /// Selected quality preset
    @Published var selectedPreset: QualityPreset = .balanced

    /// Connection mode for video/control.
    @Published var connectionOption: ConnectionOption = .udpPeerToPeerAWDL

    /// Whether the current/next handshake is requesting video streaming.
    @Published private(set) var videoRequested: Bool = false
    
    /// User preference: Stream audio from host
    @Published var audioEnabled: Bool = false
    
    // MARK: - Video Frame Output
    
    /// Latest compressed video frame data for the renderer
    @Published private(set) var latestFrameData: Data?
    
    // MARK: - Components
    
    private let networkManager = NetworkManager.shared
    private let bonjourBrowser = BonjourBrowser()
    private let mpcClient = MPCAirCatchClient()
    private let audioPlayer = AudioPlayer()
    private var cancellables = Set<AnyCancellable>()

    private enum ActiveLink {
        case network
        case aircatch
    }

    private var activeLink: ActiveLink = .network
    
    // Video Reassembly
    private let reassembler = VideoReassembler()
    
    private init() {
        setupBonjourCallbacks()
        setupMPCCallbacks()
        setupAutoConnectLogic()
        // Do not start discovery immediately on init
    }
    
    // MARK: - Lifecycle
    
    func startDiscovery() {
        guard state == .disconnected else { return }
        
        state = .discovering
        bonjourBrowser.startBrowsing(serviceType: AirCatchConfig.bonjourServiceType)
        mpcClient.startBrowsing()
        #if DEBUG
        AirCatchLog.info(" Started Bonjour discovery")
        #endif
    }
    
    func stopDiscovery() {
        bonjourBrowser.stopBrowsing()
        mpcClient.stop()
        discoveredHosts.removeAll()
        
        if state == .discovering {
            state = .disconnected
        }
    }
    
    func disconnect(shouldRetry: Bool = false) {
        networkManager.stopAll()
        mpcClient.disconnect()
        audioPlayer.stop()
        screenInfo = nil
        latestFrameData = nil
        activeLink = .network
        
        if shouldRetry {
             attemptReconnect()
        } else {
            connectedHost = nil
            state = .disconnected
            // Restart discovery
            startDiscovery()
            #if DEBUG
            AirCatchLog.info(" Disconnected")
            #endif
        }
    }
    
    // MARK: - Bonjour Setup
    
    private func setupBonjourCallbacks() {
        bonjourBrowser.onHostFound = { host in
            if let idx = ClientManager.shared.discoveredHosts.firstIndex(where: { $0.id == host.id }) {
                // If the host was first discovered via MPC, it may have endpoint=nil.
                // Merge Bonjour's resolved endpoint into the existing entry.
                let existing = ClientManager.shared.discoveredHosts[idx]
                ClientManager.shared.discoveredHosts[idx] = DiscoveredHost(
                    id: existing.id,
                    name: existing.name,
                    endpoint: host.endpoint ?? existing.endpoint,
                    udpPort: host.udpPort ?? existing.udpPort,
                    tcpPort: host.tcpPort ?? existing.tcpPort,
                    mpcPeerName: existing.mpcPeerName,
                    hostId: existing.hostId,
                    isDirectIP: existing.isDirectIP
                )
            } else {
                ClientManager.shared.discoveredHosts.append(host)
            }
            #if DEBUG
            AirCatchLog.info(" Found host: \(host.name)")
            #endif
        }

        bonjourBrowser.onHostLost = { host in
            if let idx = ClientManager.shared.discoveredHosts.firstIndex(where: { $0.id == host.id }) {
                let existing = ClientManager.shared.discoveredHosts[idx]
                if existing.mpcPeerName != nil {
                    // Keep the entry if it's still reachable via MPC; just clear Bonjour endpoint.
                    ClientManager.shared.discoveredHosts[idx] = DiscoveredHost(
                        id: existing.id,
                        name: existing.name,
                        endpoint: nil,
                        udpPort: existing.udpPort,
                        tcpPort: existing.tcpPort,
                        mpcPeerName: existing.mpcPeerName,
                        hostId: existing.hostId,
                        isDirectIP: existing.isDirectIP
                    )
                } else {
                    ClientManager.shared.discoveredHosts.remove(at: idx)
                }
            }
            #if DEBUG
            AirCatchLog.info(" Lost host: \(host.name)")
            #endif
        }
    }

    private func setupMPCCallbacks() {
        mpcClient.onHostFound = { peer, info in
            let hostName = info?["name"] ?? peer.displayName
            let hostId = info?["hostId"]

            // Merge into existing entry by name (best-effort; Bonjour doesn't expose a stable hostId today).
            if let idx = ClientManager.shared.discoveredHosts.firstIndex(where: { $0.name == hostName }) {
                let existing = ClientManager.shared.discoveredHosts[idx]
                ClientManager.shared.discoveredHosts[idx] = DiscoveredHost(
                    id: existing.id,
                    name: existing.name,
                    endpoint: existing.endpoint,
                    udpPort: existing.udpPort,
                    tcpPort: existing.tcpPort,
                    mpcPeerName: peer.displayName,
                    hostId: hostId ?? existing.hostId,
                    isDirectIP: existing.isDirectIP
                )
            } else {
                ClientManager.shared.discoveredHosts.append(
                    DiscoveredHost(
                        id: hostName,
                        name: hostName,
                        endpoint: nil,
                        udpPort: nil,
                        tcpPort: nil,
                        mpcPeerName: peer.displayName,
                        hostId: hostId,
                        isDirectIP: false
                    )
                )
            }
        }

        mpcClient.onHostLost = { peer in
            // Only clear MPC capability; keep Bonjour entry if present.
            for i in ClientManager.shared.discoveredHosts.indices {
                if ClientManager.shared.discoveredHosts[i].mpcPeerName == peer.displayName {
                    let existing = ClientManager.shared.discoveredHosts[i]
                    ClientManager.shared.discoveredHosts[i] = DiscoveredHost(
                        id: existing.id,
                        name: existing.name,
                        endpoint: existing.endpoint,
                        udpPort: existing.udpPort,
                        tcpPort: existing.tcpPort,
                        mpcPeerName: nil,
                        hostId: existing.hostId,
                        isDirectIP: existing.isDirectIP
                    )
                }
            }
        }

        mpcClient.onPacketReceived = { [weak self] packet in
            guard let self else { return }
            switch packet.type {
            case .handshakeAck, .pairingFailed, .disconnect:
                self.handleTCPPacket(packet)
            case .videoFrame, .videoFrameChunk:
                self.handleAirCatchPacket(packet)
            case .touchEvent:
                break
            default:
                break
            }
        }

        mpcClient.onConnected = { [weak self] in
            guard let self else { return }
            self.activeLink = .aircatch
            self.debugConnectionStatus = "Connected (AirCatch)"
            self.sendHandshakeViaAirCatch()
        }

        mpcClient.onDisconnected = { [weak self] in
            guard let self else { return }
            // Treat as a drop; try fallback reconnect.
            self.disconnect(shouldRetry: true)
        }
    }
    
    // MARK: - Auto-Connect Logic
    
    private func setupAutoConnectLogic() {
        // Auto-connect logic removed as AR is disabled.
        // Users now select a host manually from the list.
    }
    
    // MARK: - Connection
    
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    private var pendingRequestVideo: Bool = true

    /// Connects to a host with the requested session features.
    func connect(
        to host: DiscoveredHost,
        requestVideo: Bool = true
    ) {
        // Removed: guard state == .discovering else { return }
        // This allows reconnection logic to work

        pendingRequestVideo = requestVideo
        videoRequested = requestVideo
        
        state = .connecting
        connectedHost = host
        reconnectAttempts = 0 // Reset on manual connect

        // MultipeerConnectivity is kept for discovery, but we always use Network.framework
        // for the actual stream/control connection.
        
        // For direct IP hosts, connect immediately
        if host.isDirectIP, let endpoint = host.endpoint,
           case .hostPort(let nwHost, _) = endpoint {
            let hostString: String
            switch nwHost {
            case .ipv4(let addr):
                hostString = "\(addr)"
            case .ipv6(let addr):
                hostString = "\(addr)"
            case .name(let name, _):
                hostString = name
            @unknown default:
                hostString = "\(nwHost)"
            }
            debugConnectionStatus = "Connecting to \(hostString) (Remote)..."
            establishConnection(hostIP: hostString)
            return
        }
        
        // Resolve the service endpoint to get IP address
        resolveAndConnect(host: host)
    }
    
    /// Connects directly to a Mac via IP address (for remote/internet connections)
    /// - Parameters:
    ///   - ipAddress: The public IP or hostname of the Mac
    ///   - port: The TCP port (default: 5556)
    ///   - name: Display name for the host
    func connectByIP(
        ipAddress: String,
        port: UInt16 = AirCatchConfig.tcpPort,
        name: String = "Remote Mac"
    ) {
        #if DEBUG
        AirCatchLog.info(" Connecting by direct IP: \(ipAddress):\(port)")
        #endif
        
        // Create a discovered host entry for the direct IP
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AirCatchLog.error("Invalid port: \(port)", category: .network)
            return
        }
        
        let directHost = DiscoveredHost(
            id: "direct-\(ipAddress)-\(port)",
            name: name,
            endpoint: NWEndpoint.hostPort(host: NWEndpoint.Host(ipAddress), port: nwPort),
            udpPort: nil,
            tcpPort: port,
            mpcPeerName: nil,
            hostId: nil,
            isDirectIP: true
        )
        
        // Add to discovered hosts if not already there
        if !discoveredHosts.contains(where: { $0.id == directHost.id }) {
            discoveredHosts.append(directHost)
        }
        
        // Connect to it
        connect(to: directHost, requestVideo: true)
    }

    private func sendHandshakeViaAirCatch() {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let screen: UIScreen? = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
            ?? windowScenes.first?.screen
        
        // Use bounds * scale to get actual render resolution (accounts for "More Space" mode)
        let bounds = screen?.bounds ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let scale = screen?.scale ?? 2.0
        let renderW = Int(bounds.size.width * scale)
        let renderH = Int(bounds.size.height * scale)
        let capped = capRenderResolution(width: renderW, height: renderH)
        let maxW = max(capped.width, capped.height)
        let maxH = min(capped.width, capped.height)
        
        #if DEBUG
        AirCatchLog.info("Screen resolution: bounds=\(bounds.width)x\(bounds.height) scale=\(scale) render=\(maxW)x\(maxH)", category: .video)
        #endif

        let request = HandshakeRequest(
            clientName: UIDevice.current.name,
            clientVersion: "1.0",
            deviceModel: UIDevice.current.model,
            screenWidth: maxW,
            screenHeight: maxH,
            preferredQuality: selectedPreset,
            displayConfig: nil,  // Mirror mode only (extend display removed)
            requestVideo: pendingRequestVideo,
            requestAudio: audioEnabled,
            preferLowLatency: true,
            losslessVideo: true,
            pin: enteredPIN.isEmpty ? nil : enteredPIN
        )

        if let data = try? JSONEncoder().encode(request) {
            mpcClient.send(type: .handshake, payload: data, mode: .reliable)
        }
    }

    private func handleAirCatchPacket(_ packet: Packet) {
        switch packet.type {
        case .videoFrame:
            videoFrameSubject.send(packet.payload)
            if state == .connected {
                state = .streaming
                reconnectAttempts = 0
                debugConnectionStatus = "Streaming (AirCatch)"
            }
        case .videoFrameChunk:
            handleVideoChunk(packet.payload)
            if state == .connected {
                state = .streaming
                reconnectAttempts = 0
                debugConnectionStatus = "Streaming (AirCatch)"
            }
        case .audioPCM:
            // Handle audio frame
            break
        case .ping:
            // Respond to ping with pong for RTT measurement
            handlePingPacket(packet.payload)
        default:
            break
        }
    }
    
    /// Handle ping from Host and respond with pong
    private func handlePingPacket(_ payload: Data) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            // Respond via MPC (handles internally if no peers)
            mpcClient.send(type: .pong, payload: data, mode: .reliable)
        }
    }
    
    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts, let host = connectedHost else {
            state = .disconnected
            startDiscovery()
            return
        }
        
        reconnectAttempts += 1
        let delay = pow(2.0, Double(reconnectAttempts)) // 2, 4, 8, 16...
        #if DEBUG
        AirCatchLog.info(" Reconnecting in \(delay)s (Attempt \(reconnectAttempts))")
        #endif
        state = .connecting // Updates UI to "Connecting..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.resolveAndConnect(host: host)
        }
    }
    
    private func resolveAndConnect(host: DiscoveredHost) {
        #if DEBUG
        debugConnectionStatus = "Resolving endpoint..."
        #endif

        guard let endpoint = host.endpoint else {
            #if DEBUG
            AirCatchLog.info(" No Bonjour endpoint for host: \(host.name)")
            #endif
            disconnect(shouldRetry: true)
            return
        }
        
        // Create a connection to resolve the endpoint
        // Bonjour service is UDP, so we use UDP to resolving the endpoint
        let parameters = NWParameters.udp
        parameters.includePeerToPeer = connectionOption.includePeerToPeer
        let connection = NWConnection(to: endpoint, using: parameters)
        
        connection.stateUpdateHandler = { (newState: NWConnection.State) in
            Task { @MainActor in
                ClientManager.shared.debugConnectionStatus = "Endpoint state: \(newState)"
            }
            switch newState {
            case .ready:
                // Connection established - get the resolved IP
                if let path = connection.currentPath,
                   let endpoint = path.remoteEndpoint,
                   case .hostPort(let resolvedHost, _) = endpoint {
                    let hostString = "\(resolvedHost)"
                    
                    // Stop listening to updates so we don't log "cancelled"
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    
                    Task { @MainActor in
                        ClientManager.shared.establishConnection(hostIP: hostString)
                    }
                }
            case .failed(let error):
                AirCatchLog.info(" Resolution failed: \(error)")
                connection.stateUpdateHandler = nil
                connection.cancel()
                Task { @MainActor in
                     ClientManager.shared.disconnect(shouldRetry: true)
                }
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func establishConnection(hostIP: String) {
        #if DEBUG
        debugConnectionStatus = "Connecting to \(hostIP)..."
        AirCatchLog.info(" Connecting to \(hostIP)")
        #endif
        
        let tcpPort = connectedHost?.tcpPort ?? AirCatchConfig.tcpPort
        let udpPort = connectedHost?.udpPort ?? AirCatchConfig.udpPort

        // Connect TCP for touch events and handshake
        // We now wait for onConnected to send the handshake to avoid race condition
        networkManager.connectTCP(
            to: hostIP,
            port: tcpPort,
            includePeerToPeer: connectionOption.includePeerToPeer,
            requiredInterfaceType: nil,
            onConnected: { _ in
            Task { @MainActor in
                ClientManager.shared.sendHandshake()
            }
        }) { packet, _ in
            ClientManager.shared.handleTCPPacket(packet)
        }
        
        // Connect UDP for video frames
        networkManager.connectUDP(
            to: hostIP,
            port: udpPort,
            includePeerToPeer: connectionOption.includePeerToPeer,
            requiredInterfaceType: nil
        ) { packet, _ in
            ClientManager.shared.handleUDPPacket(packet)
        }
        
        // Send a dummy UDP packet to "punch a hole" / register the connection with the Host listener
        // The Host needs to receive at least one packet to know we are here listening for broadcast
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay to ensure socket ready
            NetworkManager.shared.sendUDP(type: .handshake, payload: Data())
            #if DEBUG
            AirCatchLog.info(" Sent UDP ping")
            #endif
        }
    }
    
    private func sendHandshake() {
        // Prefer an active UIWindowScene screen. Avoids deprecated UIScreen.main / UIScreen.screens.
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let screen: UIScreen? = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
            ?? windowScenes.first?.screen
        
        // Use bounds * scale to get actual render resolution (accounts for "More Space" mode)
        let bounds = screen?.bounds ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let scale = screen?.scale ?? 2.0
        let renderW = Int(bounds.size.width * scale)
        let renderH = Int(bounds.size.height * scale)
        let capped = capRenderResolution(width: renderW, height: renderH)
        let maxW = max(capped.width, capped.height)
        let maxH = min(capped.width, capped.height)
        
        #if DEBUG
        AirCatchLog.info("Screen resolution: bounds=\(bounds.width)x\(bounds.height) scale=\(scale) render=\(maxW)x\(maxH)", category: .video)
        #endif

        let request = HandshakeRequest(
            clientName: UIDevice.current.name,
            clientVersion: "1.0",
            deviceModel: UIDevice.current.model,
            screenWidth: maxW,
            screenHeight: maxH,
            // REMOTE OPTIMIZATION: Force Performance preset (25 Mbps) for direct IP/WAN connections
            preferredQuality: (connectedHost?.isDirectIP == true) ? .performance : selectedPreset,
            displayConfig: nil,  // Mirror mode only (extend display removed)
            requestVideo: pendingRequestVideo,
            requestAudio: audioEnabled,
            preferLowLatency: true,
            losslessVideo: true,
            pin: enteredPIN.isEmpty ? nil : enteredPIN
        )
        
        if let data = try? JSONEncoder().encode(request) {
            networkManager.sendTCP(type: .handshake, payload: data)
            #if DEBUG
            AirCatchLog.info(" Sent handshake: video=\(pendingRequestVideo) preset=\(selectedPreset.displayName)")
            #endif
        }
    }

    /// Caps the streaming render resolution to improve sharp text and reduce encoder pressure.
    ///
    /// iPad “More Space” can report very high render sizes (e.g., 2778×1940). At the current
    /// bitrates, that tends to reduce text clarity. Capping to ~4MP preserves sharpness.
    private func capRenderResolution(width: Int, height: Int) -> (width: Int, height: Int) {
        let w = max(1, width)
        let h = max(1, height)

        // UNLOCKED: Allow full Retina resolution (approx 5.6MP for iPad Pro 12.9)
        // M-series chips can easily handle 8MP decoding.
        let maxPixels = AirCatchConfig.maxRenderPixels 
        let pixels = Double(w) * Double(h)
        guard pixels > maxPixels else { return (w, h) }

        let scale = sqrt(maxPixels / pixels)
        var newW = Int(Double(w) * scale)
        var newH = Int(Double(h) * scale)

        // Align to even values (VideoToolbox friendly).
        newW = max(2, newW & ~1)
        newH = max(2, newH & ~1)

        return (newW, newH)
    }
    
    // MARK: - Packet Handling
    
    private func handleTCPPacket(_ packet: Packet) {
        switch packet.type {
        case .handshakeAck:
            handleHandshakeAck(packet.payload)
        case .videoFrame:
            // Receive video frames via TCP
            videoFrameSubject.send(packet.payload)
            if state == .connected {
                state = .streaming
                reconnectAttempts = 0
                debugConnectionStatus = "Streaming (TCP)"
            }
        case .pairingFailed:
            // Wrong PIN - disconnect and show error
            #if DEBUG
            AirCatchLog.info(" Pairing failed - wrong PIN")
            #endif
            state = .error("Wrong PIN")
            enteredPIN = "" // Clear the PIN
            // Don't call disconnect() as we're already handling state
        case .disconnect:
            // Server requested disconnect? Usually we just want to reconnect.
            // But if it's explicit, maybe we should stop?
            // For stability, let's treat it as a drop and try to reconnect.
            disconnect(shouldRetry: true)
        default:
            break
        }
    }
    
    private var udpPacketCount = 0
    
    private func handleUDPPacket(_ packet: Packet) {
        udpPacketCount += 1
        #if DEBUG
        if udpPacketCount <= 5 {
            AirCatchLog.info(" Received UDP packet #\(udpPacketCount): type=\(packet.type)")
        }
        #endif
        
        switch packet.type {
        case .videoFrame:
            // UDP complete frame (legacy/fallback)
            videoFrameSubject.send(packet.payload)
            updateStreamingState()
            
        case .videoFrameChunk:
            // Handle fragmented video frame
            handleVideoChunk(packet.payload)
            
        case .audioPCM:
            // Play audio packet
            audioPlayer.playAudioPacket(packet.payload)
            
        default:
            break
        }
    }
    
    private func updateStreamingState() {
        if state == .connected {
            Task { @MainActor in
                state = .streaming
                reconnectAttempts = 0 // Reset success
                debugConnectionStatus = "Streaming (UDP)"
                audioPlayer.start()
            }
        }
    }
    
    private func handleVideoChunk(_ data: Data) {
        guard data.count > 8 else { return }
        // Safe byte-by-byte parsing to avoid unaligned memory access crashes
        let frameId = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        let chunkIdx = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
        
        if frameId % 60 == 0 && chunkIdx == 0 {
             // AirCatchLog.info(" Rx Chunk: F\(frameId) C\(chunkIdx)") -- Removed for performance
        }
        
        reassembler.process(
            chunk: data,
            losslessEnabled: true,
            onNack: { [weak self] frameId, missingChunkIndices in
                guard let self else { return }
                guard self.activeLink == .network else { return }
                guard !missingChunkIndices.isEmpty else { return }
                let request = VideoChunkNackRequest(frameId: frameId, missingChunkIndices: missingChunkIndices)
                if let payload = try? JSONEncoder().encode(request) {
                    self.networkManager.sendTCP(type: .videoFrameChunkNack, payload: payload)
                }
            },
            onComplete: { [weak self] fullFrame in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Send frame to decoder (no logging - streaming is working)
                self.videoFrameSubject.send(fullFrame)
                self.updateStreamingState()
            }
        })
    }

    
    private func handleHandshakeAck(_ payload: Data) {
        guard let ack = try? JSONDecoder().decode(HandshakeAck.self, from: payload) else {
            #if DEBUG
            AirCatchLog.info(" Failed to decode handshake ack")
            #endif
            return
        }
        
        screenInfo = ack
        state = .connected
        
        #if DEBUG
        AirCatchLog.info(" Connected! Screen: \(ack.width)x\(ack.height) @ \(ack.frameRate)fps")
        #endif
    }
    
    // MARK: - Touch Events
    
    /// Sends a touch event to the Mac host.
    /// - Parameters:
    ///   - normalizedX: X coordinate normalized to 0.0-1.0
    ///   - normalizedY: Y coordinate normalized to 0.0-1.0
    ///   - eventType: The type of touch event
    func sendTouchEvent(normalizedX: Double, normalizedY: Double, eventType: TouchEventType) {
        guard state == .connected || state == .streaming else { return }
        
        // NOTE: No throttling for P2P mode - user wants lowest latency possible
        // Throttling would be added here for remote/WAN connections in Phase 3
        
        let event = TouchEvent(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            eventType: eventType
        )
        
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .touchEvent, payload: data, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .touchEvent, payload: data)
            }
        }
    }

    /// Sends a pinch/zoom event to the Mac host.
    func sendPinchEvent(scale: Double, velocity: Double) {
        guard state == .connected || state == .streaming else { return }
        // Use scroll event with special encoding for pinch
        // macOS interprets cmd+scroll as zoom in many apps
        let zoomDelta = (scale - 1.0) * 10.0  // Convert scale to scroll-like delta
        let event = ScrollEvent(deltaX: 0, deltaY: zoomDelta)
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .scrollEvent, payload: data, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .scrollEvent, payload: data)
            }
        }
    }

    /// Sends a scroll event to the Mac host (for two-finger scroll on iPad).
    func sendScrollEvent(deltaX: Double, deltaY: Double) {
        guard state == .connected || state == .streaming else { return }
        let event = ScrollEvent(deltaX: deltaX, deltaY: deltaY)
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .scrollEvent, payload: data, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .scrollEvent, payload: data)
            }
        }
    }

    /// Sends a keyboard event to the Mac host.
    func sendKeyEvent(keyCode: UInt16, character: String?, modifiers: KeyModifiers, isKeyDown: Bool) {
        guard state == .connected || state == .streaming else { return }
        let event = KeyEvent(
            keyCode: keyCode,
            character: character,
            modifiers: modifiers,
            isKeyDown: isKeyDown
        )
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .keyEvent, payload: data, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .keyEvent, payload: data)
            }
        }
    }
    
    /// Sends a media key event (volume, brightness, play/pause, etc.) to the Mac host.
    func sendMediaKeyEvent(mediaKey: Int32, keyCode: UInt16) {
        guard state == .connected || state == .streaming else { return }
        let event = MediaKeyEvent(mediaKey: mediaKey, keyCode: keyCode)
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .mediaKeyEvent, payload: data, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .mediaKeyEvent, payload: data)
            }
        }
    }

}

// MARK: - Video Reassembler (Thread-Safe)

private final class VideoReassembler {
    private struct FrameAssembly {
        var totalChunks: Int
        var chunks: [Int: Data]
        var firstSeenAt: TimeInterval
        var lastNackSentAt: TimeInterval
        var nackedIndices: Set<Int>
    }

    private var reassemblyBuffer: [UInt32: FrameAssembly] = [:]
    private let queue = DispatchQueue(label: "com.aircatch.reassembly")
    private var chunkCount = 0
    private var frameCount = 0
    
    func process(
        chunk data: Data,
        losslessEnabled: Bool,
        onNack: @escaping (UInt32, [UInt16]) -> Void,
        onComplete: @escaping (Data) -> Void
    ) {
        // Header: [FrameId: 4][ChunkIdx: 2][TotalChunks: 2]
        guard data.count > 8 else { return }
        
        // Safe byte-by-byte parsing to avoid unaligned memory access crashes
        let frameId = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        let chunkIdx = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
        let totalChunks = Int(UInt16(data[6]) << 8 | UInt16(data[7]))
        let chunkData = data.subdata(in: 8..<data.count)
        
        chunkCount += 1
        #if DEBUG
        if chunkCount <= 10 {
            AirCatchLog.debug(" Chunk \(chunkCount): F\(frameId) C\(chunkIdx)/\(totalChunks) size=\(chunkData.count)")
        }
        #endif
        
        queue.async { [weak self] in
            guard let self else { return }

            let now = Date().timeIntervalSinceReferenceDate
            let nackDelay: TimeInterval = 0.02
            let nackMinInterval: TimeInterval = 0.03
            let maxMissingPerNack = 64
            
            // Cleanup old frames - collect keys first to avoid mutation during iteration
            if self.reassemblyBuffer.count > 8 {
                let keysToRemove = self.reassemblyBuffer
                    .filter { now - $0.value.firstSeenAt > 1.0 }
                    .map { $0.key }
                for key in keysToRemove { self.reassemblyBuffer.removeValue(forKey: key) }
            }
            
            // Store chunk
            if self.reassemblyBuffer[frameId] == nil {
                // Pre-allocate dictionary with expected capacity to reduce memory churn
                var chunksDict = [Int: Data]()
                chunksDict.reserveCapacity(totalChunks)
                self.reassemblyBuffer[frameId] = FrameAssembly(
                    totalChunks: totalChunks,
                    chunks: chunksDict,
                    firstSeenAt: now,
                    lastNackSentAt: 0,
                    nackedIndices: []
                )
            }
            // If totalChunks changes (shouldn't), trust the latest header.
            self.reassemblyBuffer[frameId]?.totalChunks = totalChunks
            self.reassemblyBuffer[frameId]?.chunks[chunkIdx] = chunkData
            
            // Check completion
            if let assembly = self.reassemblyBuffer[frameId], assembly.chunks.count == totalChunks {
                // Reassemble
                var fullFrame = Data()
                fullFrame.reserveCapacity(assembly.chunks.values.reduce(0) { $0 + $1.count })
                for i in 0..<totalChunks {
                    if let part = assembly.chunks[i] {
                        fullFrame.append(part)
                    } else {
                        AirCatchLog.debug(" Missing chunk \(i) for frame \(frameId)")
                        return
                    }
                }
                
                // Success
                self.frameCount += 1
                #if DEBUG
                if self.frameCount <= 5 {
                    AirCatchLog.debug(" Completed frame \(self.frameCount): \(fullFrame.count) bytes")
                }
                #endif
                self.reassemblyBuffer.removeValue(forKey: frameId)
                onComplete(fullFrame)
                return
            }

            // Lossless mode: request retransmit of missing chunks once we’ve waited long enough.
            if losslessEnabled, var assembly = self.reassemblyBuffer[frameId] {
                let age = now - assembly.firstSeenAt
                if age >= nackDelay, now - assembly.lastNackSentAt >= nackMinInterval {
                    var missing: [UInt16] = []
                    missing.reserveCapacity(16)
                    for i in 0..<assembly.totalChunks {
                        if assembly.chunks[i] == nil, !assembly.nackedIndices.contains(i) {
                            missing.append(UInt16(i))
                            if missing.count >= maxMissingPerNack { break }
                        }
                    }
                    if !missing.isEmpty {
                        assembly.lastNackSentAt = now
                        for idx in missing { assembly.nackedIndices.insert(Int(idx)) }
                        self.reassemblyBuffer[frameId] = assembly
                        onNack(frameId, missing)
                    }
                }
            }
        }
    }
}
