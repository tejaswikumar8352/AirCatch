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

    /// Input-only features (independent of video streaming).
    @Published var keyboardEnabled: Bool = false
    @Published var trackpadEnabled: Bool = false
    @Published private(set) var inputBoundHost: DiscoveredHost?

    /// Whether the current/next handshake is requesting video streaming.
    @Published private(set) var videoRequested: Bool = false
    
    // MARK: - Video Frame Output
    
    /// Latest compressed video frame data for the renderer
    @Published private(set) var latestFrameData: Data?
    
    // MARK: - Components
    
    private let networkManager = NetworkManager.shared
    private let bonjourBrowser = BonjourBrowser()
    private let mpcClient = MPCAirCatchClient()
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
        NSLog("[ClientManager] Started Bonjour discovery")
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
            NSLog("[ClientManager] Disconnected")
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
                    mpcPeerName: existing.mpcPeerName,
                    hostId: existing.hostId,
                    isDirectIP: existing.isDirectIP
                )
            } else {
                ClientManager.shared.discoveredHosts.append(host)
            }
            NSLog("[ClientManager] Found host: \(host.name)")
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
                        mpcPeerName: existing.mpcPeerName,
                        hostId: existing.hostId,
                        isDirectIP: existing.isDirectIP
                    )
                } else {
                    ClientManager.shared.discoveredHosts.remove(at: idx)
                }
            }
            NSLog("[ClientManager] Lost host: \(host.name)")
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
            case .touchEvent, .keyboardEvent:
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
    private var pendingRequestKeyboard: Bool = false
    private var pendingRequestTrackpad: Bool = false

    /// Connects to a host with the requested session features.
    func connect(
        to host: DiscoveredHost,
        requestVideo: Bool = true,
        requestKeyboard: Bool = false,
        requestTrackpad: Bool = false
    ) {
        // Removed: guard state == .discovering else { return }
        // This allows reconnection logic to work

        // Enforce: input stays bound to the first selected Mac until turned off.
        if let bound = inputBoundHost, (keyboardEnabled || trackpadEnabled), bound != host {
            state = .error("Keyboard/Trackpad is active. Turn it off to switch Macs.")
            return
        }

        pendingRequestVideo = requestVideo
        pendingRequestKeyboard = requestKeyboard
        pendingRequestTrackpad = requestTrackpad
        videoRequested = requestVideo
        
        state = .connecting
        connectedHost = host
        reconnectAttempts = 0 // Reset on manual connect

        // Practical note: MultipeerConnectivity is great for discovery/control, but is
        // often worse than raw UDP/TCP for real-time high-bitrate video.
        // Use AirCatch (MPC) only for input-only sessions; keep video on Network.framework.
        if !requestVideo, let peerName = host.mpcPeerName, let peer = mpcClient.peer(named: peerName) {
            debugConnectionStatus = "Connecting (AirCatch)..."
            activeLink = .aircatch
            mpcClient.connect(to: peer)

            // Fallback timer in case AirCatch isn't available at range.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    guard let self else { return }
                    if self.state == .connecting && self.activeLink == .aircatch {
                        self.activeLink = .network
                        self.mpcClient.disconnect()
                        self.resolveAndConnect(host: host)
                    }
                }
            }
            return
        }
        
        // Resolve the service endpoint to get IP address
        resolveAndConnect(host: host)
    }

    private func sendHandshakeViaAirCatch() {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let screen: UIScreen? = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
            ?? windowScenes.first?.screen
        let nativeBounds = screen?.nativeBounds ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let nativeW = Int(nativeBounds.size.width)
        let nativeH = Int(nativeBounds.size.height)
        let maxW = max(nativeW, nativeH)
        let maxH = min(nativeW, nativeH)

        let request = HandshakeRequest(
            clientName: UIDevice.current.name,
            clientVersion: "1.0",
            deviceModel: UIDevice.current.model,
            screenWidth: maxW,
            screenHeight: maxH,
            preferredQuality: selectedPreset,
            requestVideo: pendingRequestVideo,
            requestKeyboard: pendingRequestKeyboard,
            requestTrackpad: pendingRequestTrackpad,
            preferLowLatency: true,
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
        default:
            break
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
        NSLog("[ClientManager] Reconnecting in \(delay)s (Attempt \(reconnectAttempts))")
        state = .connecting // Updates UI to "Connecting..."
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.resolveAndConnect(host: host)
        }
    }
    
    private func resolveAndConnect(host: DiscoveredHost) {
        debugConnectionStatus = "Resolving endpoint..."

        guard let endpoint = host.endpoint else {
            NSLog("[ClientManager] No Bonjour endpoint for host: \(host.name)")
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
                NSLog("[ClientManager] Resolution failed: \(error)")
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
        debugConnectionStatus = "Connecting to \(hostIP)..."
        NSLog("[ClientManager] Connecting to \(hostIP)")
        
        // Connect TCP for touch events and handshake
        // We now wait for onConnected to send the handshake to avoid race condition
        networkManager.connectTCP(
            to: hostIP,
            port: AirCatchConfig.tcpPort,
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
            port: AirCatchConfig.udpPort,
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
            NSLog("[ClientManager] Sent UDP ping")
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
        let nativeBounds = screen?.nativeBounds ?? CGRect(x: 0, y: 0, width: 1024, height: 768)
        let nativeW = Int(nativeBounds.size.width)
        let nativeH = Int(nativeBounds.size.height)
        let maxW = max(nativeW, nativeH)
        let maxH = min(nativeW, nativeH)

        let request = HandshakeRequest(
            clientName: UIDevice.current.name,
            clientVersion: "1.0",
            deviceModel: UIDevice.current.model,
            screenWidth: maxW,
            screenHeight: maxH,
            preferredQuality: selectedPreset,
            requestVideo: pendingRequestVideo,
            requestKeyboard: pendingRequestKeyboard,
            requestTrackpad: pendingRequestTrackpad,
            preferLowLatency: true,
            pin: enteredPIN.isEmpty ? nil : enteredPIN
        )
        
        if let data = try? JSONEncoder().encode(request) {
            networkManager.sendTCP(type: .handshake, payload: data)
            NSLog("[ClientManager] Sent handshake: video=\(pendingRequestVideo) kb=\(pendingRequestKeyboard) tp=\(pendingRequestTrackpad) connection=\(connectionOption.displayName) preset=\(selectedPreset.displayName)")
        }
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
            NSLog("[ClientManager] Pairing failed - wrong PIN")
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
        if udpPacketCount <= 5 {
            NSLog("[ClientManager] Received UDP packet #\(udpPacketCount): type=\(packet.type)")
        }
        
        switch packet.type {
        case .videoFrame:
            // UDP complete frame (legacy/fallback)
            videoFrameSubject.send(packet.payload)
            updateStreamingState()
            
        case .videoFrameChunk:
            // Handle fragmented video frame
            handleVideoChunk(packet.payload)
            
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
            }
        }
    }
    
    private func handleVideoChunk(_ data: Data) {
        guard data.count > 8 else { return }
        // Safe byte-by-byte parsing to avoid unaligned memory access crashes
        let frameId = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        let chunkIdx = Int(UInt16(data[4]) << 8 | UInt16(data[5]))
        
        if frameId % 60 == 0 && chunkIdx == 0 {
             NSLog("[ClientManager] Rx Chunk: F\(frameId) C\(chunkIdx)")
        }
        
        reassembler.process(
            chunk: data,
            losslessEnabled: false,
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
                NSLog("[ClientManager] Sending frame to decoder: \(fullFrame.count) bytes, state=\(self.state)")
                self.videoFrameSubject.send(fullFrame)
                self.updateStreamingState()
            }
        })
    }

    
    private func handleHandshakeAck(_ payload: Data) {
        guard let ack = try? JSONDecoder().decode(HandshakeAck.self, from: payload) else {
            NSLog("[ClientManager] Failed to decode handshake ack")
            return
        }
        
        screenInfo = ack
        state = .connected
        
        NSLog("[ClientManager] Connected! Screen: \(ack.width)x\(ack.height) @ \(ack.frameRate)fps")
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
            eventType: eventType,
            isTrackpad: nil
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

    /// Sends a trackpad-style pointer event to the Mac host.
    func sendTrackpadEvent(normalizedX: Double, normalizedY: Double, eventType: TouchEventType) {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            eventType: eventType,
            isTrackpad: true
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
    
    /// Sends a trackpad delta movement (relative pointer movement like a Mac trackpad).
    func sendTrackpadDelta(deltaX: Double, deltaY: Double) {
        guard state == .connected || state == .streaming else {
            NSLog("[ClientManager] sendTrackpadDelta BLOCKED - state is \(state)")
            return
        }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .moved,
            isTrackpad: true,
            deltaX: deltaX,
            deltaY: deltaY
        )
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .touchEvent, payload: data, mode: .unreliable)
            case .network:
                networkManager.sendTCP(type: .touchEvent, payload: data)
            }
        }
    }
    
    /// Sends a trackpad click (left click at current mouse position).
    func sendTrackpadClick() {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .began,
            isTrackpad: true
        )
        let endEvent = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .ended,
            isTrackpad: true
        )
        if let downData = try? JSONEncoder().encode(event),
           let upData = try? JSONEncoder().encode(endEvent) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .touchEvent, payload: downData, mode: .reliable)
                mpcClient.send(type: .touchEvent, payload: upData, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .touchEvent, payload: downData)
                networkManager.sendTCP(type: .touchEvent, payload: upData)
            }
        }
    }
    
    /// Sends a trackpad right-click.
    func sendTrackpadRightClick() {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .rightClick,
            isTrackpad: true
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
    
    /// Sends a trackpad double-click.
    func sendTrackpadDoubleClick() {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .doubleClick,
            isTrackpad: true
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
    
    /// Sends a drag begin event (mouse down and hold).
    func sendTrackpadDragBegan() {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .dragBegan,
            isTrackpad: true
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
    
    /// Sends a drag move event (mouse drag with button held).
    func sendTrackpadDragMove(deltaX: Double, deltaY: Double) {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .dragMoved,
            isTrackpad: true,
            deltaX: deltaX,
            deltaY: deltaY
        )
        if let data = try? JSONEncoder().encode(event) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .touchEvent, payload: data, mode: .unreliable)
            case .network:
                networkManager.sendTCP(type: .touchEvent, payload: data)
            }
        }
    }
    
    /// Sends a drag end event (mouse up after drag).
    func sendTrackpadDragEnded() {
        guard state == .connected || state == .streaming else { return }
        let event = TouchEvent(
            normalizedX: 0,
            normalizedY: 0,
            eventType: .dragEnded,
            isTrackpad: true
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

    /// Sends a keyboard text payload (unicode) to the Mac host.
    func sendKeyboardText(_ text: String) {
        guard (state == .connected || state == .streaming), !text.isEmpty else { return }

        let evt = KeyboardEvent(
            keyCode: 0,
            characters: text,
            isKeyDown: true,
            modifiers: KeyModifiers()
        )
        if let data = try? JSONEncoder().encode(evt) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .keyboardEvent, payload: data, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .keyboardEvent, payload: data)
            }
        }
    }

    /// Sends a special key (e.g. backspace) to the Mac host.
    func sendSpecialKeyCode(_ keyCode: UInt16) {
        sendKeyCode(keyCode, modifiers: KeyModifiers())
    }

    /// Sends a key code with modifiers to the Mac host.
    func sendKeyCode(_ keyCode: UInt16, modifiers: KeyModifiers) {
        guard state == .connected || state == .streaming else { return }
        let evtDown = KeyboardEvent(keyCode: keyCode, characters: nil, isKeyDown: true, modifiers: modifiers)
        let evtUp = KeyboardEvent(keyCode: keyCode, characters: nil, isKeyDown: false, modifiers: modifiers)
        if let down = try? JSONEncoder().encode(evtDown) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .keyboardEvent, payload: down, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .keyboardEvent, payload: down)
            }
        }
        if let up = try? JSONEncoder().encode(evtUp) {
            switch activeLink {
            case .aircatch:
                mpcClient.send(type: .keyboardEvent, payload: up, mode: .reliable)
            case .network:
                networkManager.sendTCP(type: .keyboardEvent, payload: up)
            }
        }
    }

    // MARK: - Input-only Session Control

    func beginInputSession(host: DiscoveredHost, keyboard: Bool, trackpad: Bool) {
        if inputBoundHost == nil {
            inputBoundHost = host
        }
        guard inputBoundHost == host else { return }

        keyboardEnabled = keyboard
        trackpadEnabled = trackpad

        if state == .connected || state == .streaming, connectedHost == host {
            return
        }

        connect(to: host, requestVideo: false, requestKeyboard: keyboard, requestTrackpad: trackpad)
    }

    func endInputSession() {
        keyboardEnabled = false
        trackpadEnabled = false
        inputBoundHost = nil
        if !videoRequested {
            disconnect(shouldRetry: false)
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
        if chunkCount <= 10 {
            NSLog("[Reassembler] Chunk \(chunkCount): F\(frameId) C\(chunkIdx)/\(totalChunks) size=\(chunkData.count)")
        }
        
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
                self.reassemblyBuffer[frameId] = FrameAssembly(
                    totalChunks: totalChunks,
                    chunks: [:],
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
                for i in 0..<totalChunks {
                    if let part = assembly.chunks[i] {
                        fullFrame.append(part)
                    } else {
                        NSLog("[Reassembler] Missing chunk \(i) for frame \(frameId)")
                        return
                    }
                }
                
                // Success
                self.frameCount += 1
                if self.frameCount <= 5 {
                    NSLog("[Reassembler] Completed frame \(self.frameCount): \(fullFrame.count) bytes")
                }
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
