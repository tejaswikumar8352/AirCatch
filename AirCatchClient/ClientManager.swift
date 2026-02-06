//
//  ClientManager.swift
//  AirCatchClient
//
//  Orchestrates network discovery, connection, and video stream handling.
//

import Foundation
import Network
@preconcurrency import Combine
import UIKit
import MultipeerConnectivity
@preconcurrency import WebRTC

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
    
    /// User-friendly description of the current state
    var displayDescription: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Searching for hosts..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .streaming:
            return "Streaming"
        case .error(let message):
            return "Error: \(message)"
        }
    }
    
    /// Whether the state represents an active/healthy connection
    var isConnected: Bool {
        switch self {
        case .connected, .streaming:
            return true
        default:
            return false
        }
    }
}

/// Central manager for the AirCatch client.
@MainActor
final class ClientManager: ObservableObject {
    static let shared = ClientManager()
    
    // PERFORMANCE: Cached JSON encoder to avoid allocation per touch event
    private static let jsonEncoder = JSONEncoder()

    enum ConnectionOption: String, CaseIterable, Identifiable {
        case udpPeerToPeerAWDL = "udp_p2p_awdl"
        case udpNetworkFramework = "udp_network"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .udpPeerToPeerAWDL:
                return "AWDL"
            case .udpNetworkFramework:
                return "Local Network"
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
    nonisolated(unsafe) let videoFrameSubject = PassthroughSubject<Data, Never>()

    private nonisolated let udpProcessingQueue = DispatchQueue(
        label: "com.aircatch.udp.processing",
        qos: .userInitiated
    )
    private nonisolated let videoFrameQueue = DispatchQueue(
        label: "com.aircatch.video.frames",
        qos: .userInitiated
    )
    private nonisolated let streamingFlag: AtomicBool = .init(false)
    private nonisolated let audioEnabledFlag: AtomicBool = .init(false)
    
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var connectedHost: DiscoveredHost?
    @Published var screenInfo: HandshakeAck?
    @Published var webRTCVideoTrack: RTCVideoTrack?
    
    /// Debug: Distance to detected surface
    @Published var debugDistance: Float?
    
    /// Debug: Detailed connection status
    @Published var debugConnectionStatus: String = "Idle"
    
    /// PIN entered by user for pairing
    @Published var enteredPIN: String = ""
    @Published var relayPINOverride: String = ""
    
    /// SECURITY: Challenge received from host for PIN verification
    private var pendingAuthChallenge: Data?
    
    /// Session token from host for reconnection without PIN (Keychain-backed)
    private var savedSessionToken: String? {
        get { Self.loadTokenFromKeychain() }
        set { Self.saveTokenToKeychain(newValue) }
    }
    
    // MARK: - Keychain Token Storage
    private static let keychainService = "com.aircatch.sessiontoken"
    private static let keychainAccount = "sessionToken"
    
    private static func saveTokenToKeychain(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        
        guard let token = token, let data = token.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    private static func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Connection mode for video/control.
    @Published var connectionOption: ConnectionOption = .udpPeerToPeerAWDL

    /// Whether the current/next handshake is requesting video streaming.
    @Published private(set) var videoRequested: Bool = false
    
    /// User preference: Stream audio from host
    @Published var audioEnabled: Bool = false {
        didSet {
            audioEnabledFlag.set(audioEnabled)
        }
    }
    
    /// User preference: Optimize streaming for host display resolution
    /// When true, streams at host's native resolution (may require letterboxing on client).
    /// When false, scales to client's display resolution for pixel-perfect fit.
    @Published var optimizeForHostDisplay: Bool = false
    
    // MARK: - Components
    // NOTE: latestFrameData was removed - use videoFrameSubject (PassthroughSubject) instead
    // to avoid SwiftUI view thrashing at 60 FPS
    
    private let networkManager = NetworkManager.shared
    private let bonjourBrowser = BonjourBrowser()
    private let mpcClient = MPCAirCatchClient()
    private let audioPlayer = AudioPlayer()

    private let crypto = CryptoManager()  // E2EE decryption
    private var relayClient: RelayClient?
    private var webRTCSession: WebRTCClientSession?
    private var webRTCActive: Bool = false
    private var relayHandshakeSent = false
    private var lastRelayHandshakeAt: TimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

    
    // Video Reassembly
    private let reassembler = VideoReassembler()
    private lazy var udpStreamProcessor = makeUDPStreamProcessor()

    // Telemetry
    private var telemetryTimer: Timer?
    private var lastPingTimestamp: TimeInterval?
    private var lastRttMs: Double = 0
    private var lastReportTimestamp: TimeInterval?
    private nonisolated let receivedBytesCounter: AtomicInt = .init(0)
    
    private init() {
        setupBonjourCallbacks()
        setupMPCCallbacks()
        setupAutoConnectLogic()
        audioEnabledFlag.set(audioEnabled)
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
        stopTelemetry()
        audioPlayer.stop()
        streamingFlag.set(false)
        screenInfo = nil
        relayClient = nil
        stopWebRTCSession()
        
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

    // MARK: - Relay Mode

    func startRelaySession(with relayClient: RelayClient) {
        stopDiscovery()
        stopWebRTCSession()
        self.relayClient = relayClient
        relayHandshakeSent = false
        lastRelayHandshakeAt = 0
        pendingRequestVideo = true
        videoRequested = true
        streamingFlag.set(false)
        state = .connected
        debugConnectionStatus = "Connected (Relay)"
        if audioEnabled {
            audioPlayer.start()
        }
        sendRelayHandshake()
    }

    func stopRelaySession(shouldRestartDiscovery: Bool = true) {
        relayClient = nil
        audioPlayer.stop()
        streamingFlag.set(false)
        stopWebRTCSession()
        relayHandshakeSent = false
        lastRelayHandshakeAt = 0
        videoRequested = false
        state = .disconnected
        debugConnectionStatus = "Disconnected (Relay)"
        if shouldRestartDiscovery {
            startDiscovery()
        }
    }

    private func sendRelayHandshake() {
        let now = Date().timeIntervalSince1970
        if relayHandshakeSent, now - lastRelayHandshakeAt < 1.0 {
            #if DEBUG
            AirCatchLog.info("Skipping duplicate relay handshake", category: .network)
            #endif
            return
        }
        relayHandshakeSent = true
        lastRelayHandshakeAt = now
        AirCatchLog.info("📤 Sending relay handshake to host", category: .network)
        let request = makeHandshakeRequest(authResponse: nil, connectionMode: nil)
        if let data = try? JSONEncoder().encode(request) {
            AirCatchLog.info("📤 Handshake data size: \(data.count) bytes", category: .network)
            sendControl(type: .handshake, payload: data)
        }
    }

    // MARK: - WebRTC (Relay Video)

    private func ensureWebRTCSession() -> WebRTCClientSession {
        if let session = webRTCSession {
            return session
        }

        let session = WebRTCClientSession(iceServerURLs: AirCatchConfig.webrtcIceServerURLs)
        session.onSignal = { [weak self] message in
            self?.sendWebRTCSignal(message)
        }
        session.onRemoteVideoTrack = { [weak self] track in
            Task { @MainActor in
                self?.webRTCVideoTrack = track
                self?.setStreamingStateIfNeeded(debugStatus: "Streaming (WebRTC)")
            }
        }
        session.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                self?.handleWebRTCStateChange(state)
            }
        }
        
        session.onDataReceived = { [weak self] data in
            guard let self else { return }
             // PERFORMANCE: Received audio/control via WebRTC Data Channel (UDP)
             // Parsing manual packet format: [Type: 1] [Length: 4] [Payload: N]
             guard data.count >= 5 else { return }
             
             let typeVal = data[0]
             guard let type = PacketType(rawValue: typeVal) else { return }
             
             // Parse BigEndian length
             // Parse BigEndian length
             let b1 = UInt32(data[1])
             let b2 = UInt32(data[2])
             let b3 = UInt32(data[3])
             let b4 = UInt32(data[4])
             let length = (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
             
             guard data.count >= 5 + Int(length) else { return }
             let payload = data.subdata(in: 5..<5+Int(length))
             
             // Process exactly like a TCP/UDP packet
             let packet = Packet(type: type, payload: payload)
             self.udpStreamProcessor.handle(packet)
        }

        webRTCSession = session
        return session
    }

    private func handleWebRTCSignal(_ payload: Data) {
        guard let message = try? JSONDecoder().decode(WebRTCSignalMessage.self, from: payload) else {
            AirCatchLog.error("WebRTC: Failed to decode signal", category: .network)
            return
        }
        let session = ensureWebRTCSession()
        session.handleRemoteSignal(message)
    }

    private func sendWebRTCSignal(_ message: WebRTCSignalMessage) {
        guard let relay = relayClient, relay.isConnected else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        relay.send(type: .webrtcSignal, payload: data)
    }

    private func handleWebRTCStateChange(_ state: RTCPeerConnectionState) {
        switch state {
        case .connected:
            webRTCActive = true
        case .failed, .disconnected, .closed:
            webRTCActive = false
            webRTCVideoTrack = nil
        default:
            break
        }
    }

    private func stopWebRTCSession() {
        webRTCSession?.close()
        webRTCSession = nil
        webRTCVideoTrack = nil
        webRTCActive = false
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
                    hostId: existing.hostId
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
                        hostId: existing.hostId
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
                    hostId: hostId ?? existing.hostId
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
                        hostId: hostId
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
                        hostId: existing.hostId
                    )
                }
            }
        }

        mpcClient.onPacketReceived = nil
        mpcClient.onConnected = nil
        mpcClient.onDisconnected = nil
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
        
        // E2EE: Derive encryption key from PIN
        crypto.deriveKey(from: enteredPIN)

        // MultipeerConnectivity is kept for discovery only.
        
        // Resolve the service endpoint to get IP address
        resolveAndConnect(host: host)
    }

    // MARK: - Challenge-Response Authentication
    
    /// SECURITY: Handles auth challenge from host, computes HMAC response, sends handshake.
    private func handleAuthChallenge(_ payload: Data) {
        guard let authChallenge = try? JSONDecoder().decode(AuthChallenge.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("E2EE: Failed to decode auth challenge", category: .network)
            #endif
            return
        }
        
        pendingAuthChallenge = authChallenge.challenge
        debugConnectionStatus = "Connected - authenticating"
        
        #if DEBUG
        AirCatchLog.info("E2EE: Received auth challenge (v\(authChallenge.version)), sending response", category: .network)
        #endif
        
        // Now send handshake with auth response instead of plaintext PIN
        let response = crypto.computeChallengeResponse(challenge: authChallenge.challenge, pin: enteredPIN)
        pendingAuthChallenge = nil
        sendHandshake(authResponse: response)
    }
    
    /// Returns a detailed device model string for Sidecar-like iPad detection.
    /// Uses the hardware identifier (e.g., "iPad14,3") to look up the marketing name.
    private static func detailedDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Map common iPad identifiers to marketing names
        // This helps the host detect iPad model for Sidecar-like resolution presets
        let modelMap: [String: String] = [
            // iPad Pro 12.9-inch
            "iPad8,5": "iPad Pro 12.9-inch (3rd generation)",
            "iPad8,6": "iPad Pro 12.9-inch (3rd generation)",
            "iPad8,7": "iPad Pro 12.9-inch (3rd generation)",
            "iPad8,8": "iPad Pro 12.9-inch (3rd generation)",
            "iPad8,11": "iPad Pro 12.9-inch (4th generation)",
            "iPad8,12": "iPad Pro 12.9-inch (4th generation)",
            "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
            "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
            "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
            "iPad16,5": "iPad Pro 13-inch (M4)",
            "iPad16,6": "iPad Pro 13-inch (M4)",
            
            // iPad Pro 11-inch
            "iPad8,1": "iPad Pro 11-inch (1st generation)",
            "iPad8,2": "iPad Pro 11-inch (1st generation)",
            "iPad8,3": "iPad Pro 11-inch (1st generation)",
            "iPad8,4": "iPad Pro 11-inch (1st generation)",
            "iPad8,9": "iPad Pro 11-inch (2nd generation)",
            "iPad8,10": "iPad Pro 11-inch (2nd generation)",
            "iPad13,4": "iPad Pro 11-inch (3rd generation)",
            "iPad13,5": "iPad Pro 11-inch (3rd generation)",
            "iPad13,6": "iPad Pro 11-inch (3rd generation)",
            "iPad13,7": "iPad Pro 11-inch (3rd generation)",
            "iPad14,3": "iPad Pro 11-inch (4th generation)",
            "iPad14,4": "iPad Pro 11-inch (4th generation)",
            "iPad16,3": "iPad Pro 11-inch (M4)",
            "iPad16,4": "iPad Pro 11-inch (M4)",
            
            // iPad Air
            "iPad13,1": "iPad Air (4th generation)",
            "iPad13,2": "iPad Air (4th generation)",
            "iPad13,16": "iPad Air (5th generation)",
            "iPad13,17": "iPad Air (5th generation)",
            "iPad14,8": "iPad Air 11-inch (M2)",
            "iPad14,9": "iPad Air 11-inch (M2)",
            "iPad14,10": "iPad Air 13-inch (M2)",
            "iPad14,11": "iPad Air 13-inch (M2)",
            
            // iPad mini
            "iPad14,1": "iPad mini (6th generation)",
            "iPad14,2": "iPad mini (6th generation)",
            
            // iPad (standard)
            "iPad12,1": "iPad (9th generation)",
            "iPad12,2": "iPad (9th generation)",
            "iPad13,18": "iPad (10th generation)",
            "iPad13,19": "iPad (10th generation)",
        ]
        
        return modelMap[identifier] ?? "iPad \(identifier)"
    }

    private func makeHandshakeRequest(authResponse: Data?, connectionMode: ConnectionMode?) -> HandshakeRequest {
        let isRelay = relayClient != nil
        // Get iPad display properties for Sidecar-like hardware handshake
        // nativeBounds always returns PIXELS (unaffected by Display Zoom)
        let windowScenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let screen = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .screen
            ?? windowScenes.first?.screen

        let nativeBounds = screen?.nativeBounds ?? CGRect(x: 0, y: 0, width: 2048, height: 1536)
        let scale = screen?.scale ?? 2.0
        let nativeScale = screen?.nativeScale ?? scale

        let nativeW = Int(nativeBounds.width)
        let nativeH = Int(nativeBounds.height)

        let physicalWidth = max(nativeW, nativeH)
        let physicalHeight = min(nativeW, nativeH)

        let deviceModel = Self.detailedDeviceModel()

        #if DEBUG
        AirCatchLog.info("📱 iPad Sidecar handshake:", category: .video)
        AirCatchLog.info("   Device: \(deviceModel)", category: .video)
        AirCatchLog.info("   Native: \(physicalWidth)×\(physicalHeight) pixels", category: .video)
        AirCatchLog.info("   Scale: \(scale)x", category: .video)
        #endif

        let relayPIN = isRelay ? relayPINOverride.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let pinValue = relayPIN.isEmpty ? nil : relayPIN

        return HandshakeRequest(
            clientName: UIDevice.current.name,
            clientVersion: "2.0",
            deviceModel: deviceModel,
            screenWidth: physicalWidth,
            screenHeight: physicalHeight,
            screenScale: scale,
            nativeScale: nativeScale,
            nativeBoundsWidth: Int(nativeBounds.width),
            nativeBoundsHeight: Int(nativeBounds.height),
            connectionMode: connectionMode,
            codecPreference: .auto,
            displayConfig: nil,  // Mirror mode only (extend display removed)
            requestVideo: pendingRequestVideo,
            requestAudio: audioEnabled,
            preferLowLatency: true,
            losslessVideo: !isRelay,
            pin: pinValue,
            authResponse: authResponse,
            sessionToken: savedSessionToken,  // Send saved token for reconnection
            optimizeForHostDisplay: optimizeForHostDisplay
        )
    }

    /// Handle ping from Host and respond with pong
    private func handlePingPacket(_ payload: Data) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            sendControl(type: .pong, payload: data)
        }
    }

    private func handlePongPacket(_ payload: Data) {
        guard let pong = try? JSONDecoder().decode(PongPacket.self, from: payload) else { return }
        let now = Date().timeIntervalSince1970
        
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let lastPing = self.lastPingTimestamp {
                self.lastRttMs = max(0, (now - lastPing) * 1000.0)
            } else {
                self.lastRttMs = max(0, (now - pong.pingTimestamp) * 1000.0)
            }
        }
    }

    private func startTelemetry() {
        stopTelemetry()

        // Timer fires on main run loop but callback closure is not automatically MainActor-isolated.
        // Use Task to properly dispatch to MainActor.
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPingAndReport()
            }
        }
    }

    private func stopTelemetry() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        lastPingTimestamp = nil
        lastRttMs = 0
        lastReportTimestamp = nil
        _ = receivedBytesCounter.swap(0)
    }

    private func sendPingAndReport() {
        let usingWebRTC = webRTCActive || webRTCVideoTrack != nil
        let now = Date().timeIntervalSince1970
        lastPingTimestamp = now
        let ping = PingPacket(timestamp: now)
        if let data = try? JSONEncoder().encode(ping) {
            sendControl(type: .ping, payload: data)
        }

        let bytesSinceLastReport = receivedBytesCounter.swap(0)
        let estimatedBandwidth: Int?
        if let lastReportTimestamp {
            let elapsed = max(0.001, now - lastReportTimestamp)
            let bps = Int(Double(bytesSinceLastReport * 8) / elapsed)
            estimatedBandwidth = bps
        } else {
            estimatedBandwidth = nil
        }

        lastReportTimestamp = now

        if usingWebRTC {
            return
        }

        let report = QualityReport(
            droppedFrames: 0,
            latencyMs: lastRttMs,
            jitterMs: 0,
            estimatedBandwidthBps: estimatedBandwidth
        )
        if let reportData = try? JSONEncoder().encode(report) {
            sendControl(type: .qualityReport, payload: reportData)
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
        // Wait for auth challenge before sending the handshake.
        networkManager.connectTCP(
            to: hostIP,
            port: tcpPort,
            includePeerToPeer: connectionOption.includePeerToPeer,
            requiredInterfaceType: nil,
            onConnected: { _ in
                Task { @MainActor in
                    ClientManager.shared.debugConnectionStatus = "Connected - awaiting auth challenge"
                }
        }) { packet, _ in
            ClientManager.shared.handleTCPPacket(packet)
        }
        
        // Connect UDP for video frames
        let udpProcessor = udpStreamProcessor
        let udpProcessingQueue = udpProcessingQueue
        networkManager.connectUDP(
            to: hostIP,
            port: udpPort,
            includePeerToPeer: connectionOption.includePeerToPeer,
            requiredInterfaceType: nil
        ) { packet, _ in
            udpProcessingQueue.async {
                udpProcessor.handle(packet)
            }
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
    
    private func sendHandshake(authResponse: Data?) {
        guard let authResponse else {
            state = .error("Authentication failed")
            return
        }

        let request = makeHandshakeRequest(authResponse: authResponse, connectionMode: currentConnectionMode())
        
        if let data = try? JSONEncoder().encode(request) {
            sendControl(type: .handshake, payload: data)
            #if DEBUG
            AirCatchLog.info(" Sent handshake: video=\(pendingRequestVideo)")
            #endif
        }
    }

    private func currentConnectionMode() -> ConnectionMode {
        switch connectionOption {
        case .udpPeerToPeerAWDL:
            return .localPeerToPeer
        case .udpNetworkFramework:
            return .localNetwork
        }
    }

    private func sendControl(type: PacketType, payload: Data) {
        // PERFORMANCE: Prefer WebRTC Data Channel (UDP) for lowest latency
        if let webrtc = webRTCSession, webrtc.isDataChannelOpen {
            // Reconstruct packet with headers (Type + Length) to match Host's expected format
            var packet = Data()
            packet.append(type.rawValue)
            let length = UInt32(payload.count)
            packet.append(UInt8((length >> 24) & 0xFF))
            packet.append(UInt8((length >> 16) & 0xFF))
            packet.append(UInt8((length >> 8) & 0xFF))
            packet.append(UInt8(length & 0xFF))
            packet.append(payload)
            
            webrtc.sendData(packet)
            return
        }

        if let relay = relayClient, relay.isConnected {
            relay.send(type: type, payload: payload)
            return
        }
        networkManager.sendTCP(type: type, payload: payload)
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
        case .authChallenge:
            handleAuthChallenge(packet.payload)
        case .handshakeAck:
            handleHandshakeAck(packet.payload)
        case .videoFrame:
            recordIncomingBytes(packet.payload.count)
            // SECURITY: Decrypt video frames - reject if decryption fails
            guard let frameData = crypto.decrypt(packet.payload) else {
                #if DEBUG
                AirCatchLog.error("E2EE: TCP video frame decryption failed - dropping packet", category: .video)
                #endif
                return
            }
            let subject = UncheckedSendable(videoFrameSubject)
            videoFrameQueue.async {
                subject.value.send(frameData)
            }
            setStreamingStateIfNeeded(debugStatus: "Streaming (TCP)")
        case .pairingFailed:
            // Wrong PIN - disconnect and show error
            #if DEBUG
            AirCatchLog.info(" Pairing failed - wrong PIN")
            #endif
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = .error("Wrong PIN")
                self.enteredPIN = "" // Clear the PIN
            }
            // Don't call disconnect() as we're already handling state
        case .ping:
            handlePingPacket(packet.payload)
        case .pong:
            handlePongPacket(packet.payload)
        case .disconnect:
            // Server requested disconnect? Usually we just want to reconnect.
            // But if it's explicit, maybe we should stop?
            // For stability, let's treat it as a drop and try to reconnect.
            DispatchQueue.main.async { [weak self] in
                self?.disconnect(shouldRetry: true)
            }
        default:
            break
        }
    }
    
    // MARK: - Relay Packet Handling
    
    /// Handle packets received from the relay server (video/audio from Host)
    /// Note: Relay packets are NOT encrypted since there's no PIN-based key exchange in relay mode
    func handleRelayPacket(_ packet: Packet) {
        let videoFrameQueue = videoFrameQueue
        let videoFrameSubject = UncheckedSendable(videoFrameSubject)
        let usingWebRTC = webRTCVideoTrack != nil || webRTCActive
        switch packet.type {
        case .videoFrame:
            if usingWebRTC { return }
            recordIncomingBytes(packet.payload.count)
            // Relay mode: no encryption, use payload directly
            videoFrameQueue.async {
                videoFrameSubject.value.send(packet.payload)
            }
            setStreamingStateIfNeeded(debugStatus: "Streaming (Relay)")
        case .pong:
            handlePongPacket(packet.payload)
        case .ping:
            handlePingPacket(packet.payload)
        case .videoFrameChunk:
            if usingWebRTC { return }
            recordIncomingBytes(packet.payload.count)
            // Handle chunked video via reassembler (no decryption needed for relay)
            reassembler.process(
                chunk: packet.payload,
                losslessEnabled: false,
                onNack: { [weak self] frameId, missingChunks in
                    guard let self else { return }
                    let request = VideoChunkNackRequest(frameId: frameId, missingChunkIndices: missingChunks)
                    if let data = try? JSONEncoder().encode(request) {
                        self.sendControl(type: .videoFrameChunkNack, payload: data)
                    }
                },
                onComplete: { [weak self] frameData in
                    guard let self = self else { return }
                    // Relay mode: no encryption, use frame directly
                    videoFrameQueue.async {
                        videoFrameSubject.value.send(frameData)
                    }
                    self.setStreamingStateIfNeeded(debugStatus: "Streaming (Relay)")
                }
            )
        case .audioPCM:
            // Relay mode: no encryption, use payload directly
            if audioEnabled {
                audioPlayer.playAudioPacket(packet.payload)
            }
        case .handshakeAck:
            handleHandshakeAck(packet.payload)
        case .webrtcSignal:
            handleWebRTCSignal(packet.payload)
        case .pairingFailed:
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = .error("Wrong PIN")
                self.enteredPIN = ""
                self.stopRelaySession(shouldRestartDiscovery: false)
            }
        case .disconnect:
            // Host disconnected from relay
            DispatchQueue.main.async { [weak self] in
                self?.stopRelaySession()
            }
        default:
            #if DEBUG
            AirCatchLog.debug("Relay: Unhandled packet type \(packet.type)", category: .network)
            #endif
        }
    }
    
    private func startStreamingIfNeeded() {
        guard state == .connected else {
            streamingFlag.set(false)
            return
        }
        state = .streaming
        reconnectAttempts = 0 // Reset success
        debugConnectionStatus = "Streaming (UDP)"
        if audioEnabled {
            audioPlayer.start()
        }
    }
    
    private func makeUDPStreamProcessor() -> UDPStreamProcessor {
        let videoFrameQueue = videoFrameQueue
        let videoFrameSubject = UncheckedSendable(videoFrameSubject)
        let audioEnabledFlag = audioEnabledFlag
        let streamingFlag = streamingFlag
        let crypto = crypto
        let reassembler = reassembler
        let audioPlayer = audioPlayer
        let recordBytes: (Int) -> Void = { [receivedBytesCounter] count in
            receivedBytesCounter.add(count)
        }
        let onFrame: (Data) -> Void = { data in
            videoFrameQueue.async {
                videoFrameSubject.value.send(data)
            }
        }
        let onStreamingStart: () -> Void = { [weak self] in
            Task { @MainActor in
                self?.startStreamingIfNeeded()
            }
        }
        let onNack: (UInt32, [UInt16]) -> Void = { [weak self] frameId, missingChunkIndices in
            guard let self else { return }
            guard !missingChunkIndices.isEmpty else { return }
            let request = VideoChunkNackRequest(frameId: frameId, missingChunkIndices: missingChunkIndices)
            if let payload = try? JSONEncoder().encode(request) {
                Task { @MainActor in
                    self.sendControl(type: .videoFrameChunkNack, payload: payload)
                }
            }
        }
        return UDPStreamProcessor(
            crypto: crypto,
            reassembler: reassembler,
            audioPlayer: audioPlayer,
            audioEnabled: audioEnabledFlag,
            streamingState: streamingFlag,
            recordIncomingBytes: recordBytes,
            onFrame: onFrame,
            onStreamingStart: onStreamingStart,
            onNack: onNack
        )
    }

    
    private func handleHandshakeAck(_ payload: Data) {
        guard let ack = try? JSONDecoder().decode(HandshakeAck.self, from: payload) else {
            #if DEBUG
            AirCatchLog.info(" Failed to decode handshake ack")
            #endif
            return
        }
        
        // Save session token for future reconnections without PIN
        if let token = ack.sessionToken {
            savedSessionToken = token
            #if DEBUG
            AirCatchLog.info("🔐 Saved session token for reconnection")
            #endif
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.screenInfo = ack
            self.streamingFlag.set(false)
            self.state = .connected
            self.startTelemetry()
        }
        
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
        
        // NOTE: No throttling for local modes - user wants lowest latency possible
        
        // Timestamp is critical for detecting stale events on host side
        let event = TouchEvent(
            normalizedX: normalizedX,
            normalizedY: normalizedY,
            eventType: eventType,
            timestamp: Date().timeIntervalSince1970
        )
        
        // PERFORMANCE: Use cached encoder instead of creating new one per event
        if let data = try? Self.jsonEncoder.encode(event) {
            sendControl(type: .touchEvent, payload: data)
        }
    }

    /// Sends a pinch/zoom event to the Mac host.
    func sendPinchEvent(scale: Double, velocity: Double) {
        guard state == .connected || state == .streaming else { return }
        // Use scroll event with special encoding for pinch
        // macOS interprets cmd+scroll as zoom in many apps
        let zoomDelta = (scale - 1.0) * 10.0  // Convert scale to scroll-like delta
        let event = ScrollEvent(deltaX: 0, deltaY: zoomDelta)
        // PERFORMANCE: Use cached encoder
        if let data = try? Self.jsonEncoder.encode(event) {
            sendControl(type: .scrollEvent, payload: data)
        }
    }

    /// Sends a scroll event to the Mac host (for two-finger scroll on iPad).
    func sendScrollEvent(deltaX: Double, deltaY: Double) {
        guard state == .connected || state == .streaming else { return }
        let event = ScrollEvent(deltaX: deltaX, deltaY: deltaY)
        // PERFORMANCE: Use cached encoder
        if let data = try? Self.jsonEncoder.encode(event) {
            sendControl(type: .scrollEvent, payload: data)
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
        // PERFORMANCE: Use cached encoder
        if let data = try? Self.jsonEncoder.encode(event) {
            sendControl(type: .keyEvent, payload: data)
        }
    }
    
    /// Sends a text injection event for multi-character input (paste).
    /// PERFORMANCE: Sends entire string in one event instead of per-character key events.
    func sendTextInjection(_ text: String) {
        guard state == .connected || state == .streaming else { return }
        guard !text.isEmpty else { return }
        // KeyCode 0 + character string signals text injection on host
        let event = KeyEvent(
            keyCode: 0,
            character: text,
            modifiers: [],
            isKeyDown: true
        )
        if let data = try? Self.jsonEncoder.encode(event) {
            sendControl(type: .keyEvent, payload: data)
        }
    }
    
    /// Sends a media key event (volume, brightness, play/pause, etc.) to the Mac host.
    func sendMediaKeyEvent(mediaKey: Int32, keyCode: UInt16) {
        guard state == .connected || state == .streaming else { return }
        let event = MediaKeyEvent(mediaKey: mediaKey, keyCode: keyCode)
        // PERFORMANCE: Use cached encoder
        if let data = try? Self.jsonEncoder.encode(event) {
            sendControl(type: .mediaKeyEvent, payload: data)
        }
    }

    private nonisolated func recordIncomingBytes(_ count: Int) {
        Task { @MainActor in
            receivedBytesCounter.add(count)
        }
    }

    private nonisolated func setStreamingStateIfNeeded(debugStatus: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.state != .streaming {
                self.state = .streaming
            }
            self.reconnectAttempts = 0
            self.debugConnectionStatus = debugStatus
        }
    }

}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class AtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    nonisolated init(_ value: Bool) {
        self.value = value
    }

    func get() -> Bool {
        lock.lock()
        let current = value
        lock.unlock()
        return current
    }

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func compareAndSet(expected: Bool, newValue: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if value == expected {
            value = newValue
            return true
        }
        return false
    }
}

private final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int

    nonisolated init(_ value: Int) {
        self.value = value
    }

    func add(_ delta: Int) {
        lock.lock()
        value += delta
        lock.unlock()
    }

    func swap(_ newValue: Int) -> Int {
        lock.lock()
        let oldValue = value
        value = newValue
        lock.unlock()
        return oldValue
    }
}

private final class UDPStreamProcessor {
    private let crypto: CryptoManager
    private let reassembler: VideoReassembler
    private let audioPlayer: AudioPlayer
    private let audioEnabled: AtomicBool
    private let streamingState: AtomicBool
    private let recordIncomingBytes: (Int) -> Void
    private let onFrame: (Data) -> Void
    private let onStreamingStart: () -> Void
    private let onNack: (UInt32, [UInt16]) -> Void
    private var udpPacketCount = 0

    init(
        crypto: CryptoManager,
        reassembler: VideoReassembler,
        audioPlayer: AudioPlayer,
        audioEnabled: AtomicBool,
        streamingState: AtomicBool,
        recordIncomingBytes: @escaping (Int) -> Void,
        onFrame: @escaping (Data) -> Void,
        onStreamingStart: @escaping () -> Void,
        onNack: @escaping (UInt32, [UInt16]) -> Void
    ) {
        self.crypto = crypto
        self.reassembler = reassembler
        self.audioPlayer = audioPlayer
        self.audioEnabled = audioEnabled
        self.streamingState = streamingState
        self.recordIncomingBytes = recordIncomingBytes
        self.onFrame = onFrame
        self.onStreamingStart = onStreamingStart
        self.onNack = onNack
    }

    func handle(_ packet: Packet) {
        udpPacketCount += 1
        #if DEBUG
        if udpPacketCount <= 5 {
            AirCatchLog.info(" Received UDP packet #\(udpPacketCount): type=\(packet.type)")
        }
        #endif

        switch packet.type {
        case .videoFrame:
            recordIncomingBytes(packet.payload.count)
            guard let frameData = crypto.decrypt(packet.payload) else {
                #if DEBUG
                AirCatchLog.error("E2EE: UDP video frame decryption failed - dropping packet", category: .video)
                #endif
                return
            }
            onFrame(frameData)
            markStreamingIfNeeded()

        case .videoFrameChunk:
            recordIncomingBytes(packet.payload.count)
            handleVideoChunk(packet.payload)

        case .audioPCM:
            recordIncomingBytes(packet.payload.count)
            guard audioEnabled.get() else { return }
            guard let audioData = crypto.decrypt(packet.payload) else {
                #if DEBUG
                AirCatchLog.error("E2EE: UDP audio decryption failed - dropping packet", category: .general)
                #endif
                return
            }
            audioPlayer.playAudioPacket(audioData)

        default:
            break
        }
    }

    private func markStreamingIfNeeded() {
        if streamingState.compareAndSet(expected: false, newValue: true) {
            onStreamingStart()
        }
    }

    private func handleVideoChunk(_ data: Data) {
        guard data.count > 8 else { return }
        let frameId = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        let chunkIdx = Int(UInt16(data[4]) << 8 | UInt16(data[5]))

        if frameId % 60 == 0 && chunkIdx == 0 {
            // AirCatchLog.info(" Rx Chunk: F\(frameId) C\(chunkIdx)") -- Removed for performance
        }

        reassembler.process(
            chunk: data,
            losslessEnabled: true,
            onNack: { [weak self] frameId, missingChunkIndices in
                self?.onNack(frameId, missingChunkIndices)
            },
            onComplete: { [weak self] fullFrame in
                guard let self else { return }
                guard let decryptedFrame = self.crypto.decrypt(fullFrame) else {
                    #if DEBUG
                    AirCatchLog.error("E2EE: Reassembled frame decryption failed - dropping", category: .video)
                    #endif
                    return
                }
                self.onFrame(decryptedFrame)
                self.markStreamingIfNeeded()
            }
        )
    }
}

// MARK: - Video Reassembler (Thread-Safe)

private final class VideoReassembler {
    private struct ChunkSlice {
        let data: Data
        let payloadRange: Range<Data.Index>
    }

    private struct FrameAssembly {
        var totalChunks: Int
        var chunks: [Int: ChunkSlice]
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
        let payloadRange = 8..<data.count
        let payloadSize = payloadRange.count
        
        chunkCount += 1
        #if DEBUG
        if chunkCount <= 10 {
            AirCatchLog.debug(" Chunk \(chunkCount): F\(frameId) C\(chunkIdx)/\(totalChunks) size=\(payloadSize)")
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
                var chunksDict = [Int: ChunkSlice]()
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
            self.reassemblyBuffer[frameId]?.chunks[chunkIdx] = ChunkSlice(
                data: data,
                payloadRange: payloadRange
            )
            
            // Check completion
            if let assembly = self.reassemblyBuffer[frameId], assembly.chunks.count == totalChunks {
                // Reassemble
                let totalSize = assembly.chunks.values.reduce(0) { $0 + $1.payloadRange.count }
                var fullFrame = Data(count: totalSize)
                var success = true
                fullFrame.withUnsafeMutableBytes { destBuffer in
                    guard let destBase = destBuffer.baseAddress else {
                        success = false
                        return
                    }
                    var offset = 0
                    for i in 0..<totalChunks {
                        guard let slice = assembly.chunks[i] else {
                            AirCatchLog.debug(" Missing chunk \(i) for frame \(frameId)")
                            success = false
                            return
                        }
                        slice.data.withUnsafeBytes { srcBuffer in
                            guard let srcBase = srcBuffer.baseAddress else {
                                success = false
                                return
                            }
                            let start = srcBase.advanced(by: slice.payloadRange.lowerBound)
                            memcpy(destBase.advanced(by: offset), start, slice.payloadRange.count)
                        }
                        if !success {
                            return
                        }
                        offset += slice.payloadRange.count
                    }
                }
                if !success {
                    return
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
