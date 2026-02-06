//
//  HostManager.swift
//  AirCatchHost
//
//  Orchestrates networking, screen capture, and client management for the Mac host.
//

import Foundation
import Network
import ScreenCaptureKit
import AppKit
import Combine
import MultipeerConnectivity
import CoreGraphics
import Security
import WebRTC

/// Central manager for the AirCatch host functionality.
@MainActor
final class HostManager: ObservableObject {
    static let shared = HostManager()
    static let statusDidChange = Notification.Name("StreamingStatusChanged")
    
    // PERFORMANCE: Cached JSON coders to avoid allocation per touch event
    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()
    
    // Touch event timing: max age before event is considered stale (200ms)
    private static let maxTouchEventAge: TimeInterval = 0.2
    
    // MARK: - Published State
    
    @Published private(set) var isRunning = false
    @Published private(set) var isStreaming = false
    @Published private(set) var connectedClients = 0
    @Published private(set) var currentPIN: String = "------"
    @Published private(set) var currentBitrate: Int = AirCatchConfig.defaultBitrate
    @Published private(set) var currentFrameRate: Int = AirCatchConfig.defaultFrameRate
    @Published var audioStreamingEnabled: Bool = false
    @Published private(set) var availableDisplays: [String] = []
    

    
    var statusDescription: String {
        if !isRunning {
            return "Stopped"
        } else if isStreaming {
            return "Streaming"
        } else {
            return "Listening"
        }
    }
    
    /// Generates a new random 6-character alphanumeric PIN (729 million combinations vs 10,000)
    func regeneratePIN() {
        // Use uppercase letters + digits, excluding confusing characters (0, O, I, 1, L)
        let allowedChars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
        currentPIN = String((0..<6).map { _ in allowedChars.randomElement()! })
        AirCatchLog.info("New PIN generated")
        crypto.deriveKey(from: currentPIN)  // E2EE: Derive encryption key from PIN
    }
    
    // MARK: - Network Components
    
    private let networkManager = NetworkManager.shared
    private let bonjourAdvertiser = BonjourAdvertiser()
    private let mpcHost = MPCAirCatchHost()
    private let crypto = CryptoManager()  // E2EE encryption
    private let virtualDisplayManager = VirtualDisplayManager.shared
    
    /// Relay client for remote connections (set by HostView when in relay mode)
    var relayClient: RelayClient?

    /// Session tokens granted to clients for reconnection without PIN (cleared on app quit)
    private var trustedSessionTokens: Set<String> = []

    private var tcpAuthChallenges: [ObjectIdentifier: Data] = [:]
    
    // MARK: - Screen Capture
    
    private var screenStreamer: ScreenStreamer?
    private var currentClientDimensions: (width: Int, height: Int)?
    private var currentClientNativeBounds: (width: Int, height: Int)?
    private var currentClientNativeScale: Double?
    private var currentFrameId: UInt32 = 0
    private let maxUDPPayloadSize = AirCatchConfig.maxUDPPayloadSize // Safe UDP payload size (below MTU)

    /// When false, prefer sending video over TCP (higher reliability).
    private var preferLowLatency: Bool = true

    /// When true, keep a short retransmit window for UDP video chunks (wired mode).
    private var losslessVideoEnabled: Bool = true

    private var lastEstimatedBandwidthBps: Int?
    
    /// When true, stream at host's native resolution. When false, scale to client resolution.
    private var optimizeForHostDisplay: Bool = false

    /// Track whether the active session is relay-based for lower default caps.
    private var isRelaySession: Bool = false

    // MARK: - WebRTC (Relay Video)
    private var webRTCSession: WebRTCHostSession?
    private var webRTCActive: Bool = false
    private var lastRelayHandshakePayload: Data?
    private var lastRelayHandshakeAt: TimeInterval = 0

    // PERFORMANCE: Store frame data once instead of duplicating for each chunk
    private struct CachedFrame {
        let createdAt: TimeInterval
        let frameId: UInt32
        let totalChunks: Int
        let maxPayloadSize: Int
        let frameData: Data  // Original frame data, not duplicated per chunk
        
        /// Lazily reconstruct a chunk packet for retransmission
        func chunkPacket(at index: Int) -> Data? {
            guard index >= 0 && index < totalChunks else { return nil }
            
            let start = index * maxPayloadSize
            let end = min(start + maxPayloadSize, frameData.count)
            guard start < frameData.count else { return nil }
            
            var packet = Data()
            packet.reserveCapacity(8 + (end - start))
            
            // Header: [FrameId: 4][ChunkIdx: 2][TotalChunks: 2]
            var fId = frameId.bigEndian
            var idx = UInt16(index).bigEndian
            var total = UInt16(totalChunks).bigEndian
            
            withUnsafeBytes(of: &fId) { packet.append(contentsOf: $0) }
            withUnsafeBytes(of: &idx) { packet.append(contentsOf: $0) }
            withUnsafeBytes(of: &total) { packet.append(contentsOf: $0) }
            
            // Use withUnsafeBytes for zero-copy slice access
            frameData.withUnsafeBytes { rawBuffer in
                packet.append(contentsOf: rawBuffer[start..<end])
            }
            
            return packet
        }
    }

    // FrameID -> cached chunks for retransmit (lossless mode)
    // SAFETY: Only accessed from cachedFramesQueue
    nonisolated(unsafe) private var cachedFrames: [UInt32: CachedFrame] = [:]
    private let cachedFramesQueue = DispatchQueue(label: "com.aircatch.framecache")

    // Target display selection
    private var targetDisplayID: CGDirectDisplayID? = nil
    private var targetScreenFrame: CGRect? = nil
    
    private init() {}
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isRunning else { return }
        
        // Generate a new PIN for this session
        regeneratePIN()
        
        Task {
            do {
                // Start UDP listener on fixed port
                try networkManager.startUDPListener(port: AirCatchConfig.udpPort) { [weak self] packet, endpoint in
                    self?.handleIncomingPacket(packet, from: endpoint)
                }
                
                // Start TCP listener on fixed port
                try networkManager.startTCPListener(
                    port: AirCatchConfig.tcpPort,
                    onConnection: { [weak self] connection in
                        Task { @MainActor in
                            self?.sendTCPAuthChallenge(to: connection)
                        }
                    },
                    onPacket: { [weak self] packet, connection in
                        self?.handleTCPPacket(packet, from: connection)
                    }
                )
                
                // Check for Accessibility Permissions (Required for Mouse/Touch Injection)
                if !InputInjector.shared.hasAccessibilityPermission {
                    Task { @MainActor in
                        let alert = NSAlert()
                        alert.messageText = "Accessibility Permission Required"
                        alert.informativeText = "AirCatch needs Accessibility permission to control the mouse/touch.\n\nGo to System Settings > Privacy & Security > Accessibility and switch on 'AirCatchHost'."
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "Open Settings")
                        alert.addButton(withTitle: "Cancel")
                        
                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                
                // Wait a moment for listeners to bind and get actual ports
                try await Task.sleep(for: .milliseconds(200))
                
                let udpPort = networkManager.actualUDPPort
                let tcpPort = networkManager.actualTCPPort
                
                guard udpPort > 0 else {
                    AirCatchLog.error("Failed to bind UDP listener", category: .network)
                    return
                }
                
                // Advertise via Bonjour with the actual port
                bonjourAdvertiser.startAdvertising(
                    serviceType: AirCatchConfig.bonjourServiceType,
                    udpPort: udpPort,
                    tcpPort: tcpPort,
                    name: Host.current().localizedName ?? "Mac"
                )

                // Advertise via AirCatch (MultipeerConnectivity) for close-range P2P.
                self.setupMPCHostCallbacksIfNeeded()
                self.mpcHost.start()

                isRunning = true
                postStatusChange()
                
                AirCatchLog.info("Started - Listening on UDP:\(udpPort) TCP:\(tcpPort)", category: .network)
                
            } catch {
                AirCatchLog.error("Failed to start: \(error)", category: .network)
            }
        }
    }
    
    func stop() {
        stopWebRTCSession()
        screenStreamer?.stop()
        screenStreamer = nil
        
        networkManager.stopAll()
        bonjourAdvertiser.stopAdvertising()
        mpcHost.stop()
        tcpAuthChallenges.removeAll()
        
        isRunning = false
        isStreaming = false
        connectedClients = 0
        postStatusChange()
        
        AirCatchLog.info("Stopped", category: .network)
    }
    
    // MARK: - Relay Packet Handling
    
    /// Handle packets received from the relay server (from the iPad client)
    func handleRelayPacket(_ packet: Packet) {
        AirCatchLog.info("📥 Host received relay packet: \(packet.type)", category: .network)
        switch packet.type {
        case .handshake:
            AirCatchLog.info("📥 Processing handshake from relay client", category: .network)
            Task { @MainActor in
                self.handleRelayHandshake(payload: packet.payload)
            }
        case .touchEvent:
            handleTouchEvent(packet.payload)
        case .scrollEvent:
            handleScrollEvent(packet.payload)
        case .keyEvent:
            handleKeyEvent(packet.payload)
        case .mediaKeyEvent:
            handleMediaKeyEvent(packet.payload)
        case .ping:
            Task { @MainActor in
                self.handleRelayPingPacket(packet.payload)
            }
        case .qualityReport:
            Task { @MainActor in
                self.handleQualityReport(packet.payload)
            }
        case .videoFrameChunkNack:
            Task { @MainActor in
                self.handleRelayVideoChunkNack(packet.payload)
            }
        case .webrtcSignal:
            Task { @MainActor in
                self.handleWebRTCSignal(packet.payload)
            }
        case .disconnect:
            // Client disconnected via relay
            if connectedClients > 0 {
                connectedClients -= 1
            }
            postStatusChange()
            if connectedClients == 0 {
                stopWebRTCSession()
                stopStreamingAndRestore()
            }
        default:
            AirCatchLog.debug("Relay: Unhandled packet type \(packet.type)", category: .network)
        }
    }
    
    // MARK: - Packet Handling
    
    private nonisolated func handleIncomingPacket(_ packet: Packet, from endpoint: NWEndpoint?) {
        #if DEBUG
        AirCatchLog.debug("Received UDP packet type: \(packet.type)", category: .network)
        #endif
        
        // Register the client endpoint so we can broadcast video frames to it
        if let endpoint = endpoint {
            Task { @MainActor in
                NetworkManager.shared.registerUDPClient(endpoint: endpoint)
            }
        }
    }
    
    private nonisolated func handleTCPPacket(_ packet: Packet, from connection: NWConnection) {
        switch packet.type {
        case .handshake:
            Task { @MainActor in
                self.handleHandshake(payload: packet.payload, from: connection)
            }
        case .videoFrameChunkNack:
            Task { @MainActor in
                self.handleVideoChunkNack(packet.payload, from: connection)
            }
        case .touchEvent:
            Task { @MainActor in
                self.handleTouchEvent(packet.payload)
            }
        case .scrollEvent:
            Task { @MainActor in
                self.handleScrollEvent(packet.payload)
            }
        case .keyEvent:
            Task { @MainActor in
                self.handleKeyEvent(packet.payload)
            }
        case .mediaKeyEvent:
            Task { @MainActor in
                self.handleMediaKeyEvent(packet.payload)
            }
        case .ping:
            Task { @MainActor in
                self.handlePingPacket(packet.payload, from: connection)
            }
        case .qualityReport:
            Task { @MainActor in
                self.handleQualityReport(packet.payload)
            }
        case .disconnect:
            Task { @MainActor in
                self.handleClientDisconnect(connection)
            }
        default:
            break
        }
    }

    private func setupMPCHostCallbacksIfNeeded() {
        // Safe to assign multiple times; closures are idempotent.
        mpcHost.onPeerConnected = { [weak self] peer in
            guard let self else { return }
            // SECURITY: Send auth challenge to client for PIN verification
            self.sendAuthChallenge(to: peer)
        }
        mpcHost.onPacketReceived = { [weak self] packet, peer in
            guard let self else { return }
            self.handleMPCPacket(packet, from: peer)
        }
        mpcHost.onPeerDisconnected = { [weak self] _ in
            guard let self else { return }
            if self.connectedClients > 0 {
                self.connectedClients -= 1
            }
            self.postStatusChange()
            if self.connectedClients == 0 {
                self.stopStreamingAndRestore()
            }
        }
    }

    private func sendTCPAuthChallenge(to connection: NWConnection) {
        var challenge = Data(count: 32)
        let result = challenge.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            AirCatchLog.error("E2EE: Failed to generate TCP auth challenge", category: .network)
            return
        }

        tcpAuthChallenges[ObjectIdentifier(connection)] = challenge
        let authChallenge = AuthChallenge(challenge: challenge)
        if let payload = try? JSONEncoder().encode(authChallenge) {
            networkManager.sendTCP(to: connection, type: .authChallenge, payload: payload)
        }
    }

    private func clearTCPAuthChallenge(for connection: NWConnection) {
        tcpAuthChallenges.removeValue(forKey: ObjectIdentifier(connection))
    }

    private func verifyTCPAuthResponse(_ response: Data, for connection: NWConnection, expectedPIN: String) -> Bool {
        guard let challenge = tcpAuthChallenges[ObjectIdentifier(connection)] else {
            return false
        }
        guard let expected = crypto.computeChallengeResponse(challenge: challenge, pin: expectedPIN) else {
            return false
        }

        guard response.count == expected.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(response, expected) {
            result |= a ^ b
        }
        return result == 0
    }
    
    /// SECURITY: Sends an auth challenge to a newly connected peer.
    private func sendAuthChallenge(to peer: MCPeerID) {
        let challenge = crypto.generateChallenge()
        let authChallenge = AuthChallenge(challenge: challenge)
        
        if let payload = try? JSONEncoder().encode(authChallenge) {
            mpcHost.send(to: peer, type: .authChallenge, payload: payload, mode: .reliable)
            #if DEBUG
            AirCatchLog.info("E2EE: Sent auth challenge to \(peer.displayName)", category: .network)
            #endif
        }
    }
    
    // Helper to stop streaming and restore resolution
    private func stopStreamingAndRestore() {
        stopWebRTCSession()
        stopStreaming()
        // Only restore if we are the last client disconnecting
        if connectedClients == 0 {
            // Destroy virtual display if active
            virtualDisplayManager.destroyVirtualDisplay()
            // Also restore main display if it was changed
            DisplayManager.shared.restoreOriginalResolution()
        }
    }

    private func handleMPCPacket(_ packet: Packet, from peer: MCPeerID) {
        switch packet.type {
        case .handshake:
            handleMPCHandshake(payload: packet.payload, from: peer)
        case .touchEvent:
            handleTouchEvent(packet.payload)
        case .scrollEvent:
            handleScrollEvent(packet.payload)
        case .keyEvent:
            handleKeyEvent(packet.payload)
        case .mediaKeyEvent:
            handleMediaKeyEvent(packet.payload)
        case .audioPCM:
            break
        case .disconnect:
            if connectedClients > 0 {
                connectedClients -= 1
            }
            postStatusChange()
            if connectedClients == 0 {
                stopStreamingAndRestore() // Restore resolution on disconnect
            }
        default:
            break
        }
    }

    private func handleMPCHandshake(payload: Data, from peer: MCPeerID) {
        let handshakeRequest: HandshakeRequest?
        do {
            handshakeRequest = try JSONDecoder().decode(HandshakeRequest.self, from: payload)
        } catch {
            #if DEBUG
            AirCatchLog.error("Failed to decode MPC HandshakeRequest: \(error)", category: .network)
            #endif
            handshakeRequest = nil
        }
        
        // SECURITY: Check session token first (for reconnection), then PIN authentication
        let isAuthenticated: Bool
        var authenticatedPIN: String?
        var grantedSessionToken: String?
        
        // Token-based auth: client sends saved token for instant reconnection
        if let token = handshakeRequest?.sessionToken, trustedSessionTokens.contains(token) {
            isAuthenticated = true
            grantedSessionToken = token  // Reuse existing token
            #if DEBUG
            AirCatchLog.info("🔐 Session token auth succeeded (reconnection)", category: .network)
            #endif
        } else if let authResponse = handshakeRequest?.authResponse {
            // Challenge-response PIN auth
            if crypto.verifyChallengeResponse(authResponse, expectedPIN: currentPIN) {
                isAuthenticated = true
                authenticatedPIN = currentPIN
            } else {
                isAuthenticated = false
            }
            crypto.clearChallenge()
            #if DEBUG
            let authStatus = isAuthenticated ? "succeeded" : "failed"
            AirCatchLog.info("E2EE: Challenge-response auth \(authStatus)", category: .network)
            #endif
        } else {
            // Legacy plaintext PIN (backward compatibility)
            let receivedPIN = handshakeRequest?.pin ?? ""
            isAuthenticated = (receivedPIN == currentPIN)
            if isAuthenticated {
                authenticatedPIN = receivedPIN
            }
            #if DEBUG
            if isAuthenticated {
                AirCatchLog.info("E2EE: Legacy plaintext PIN auth", category: .network)
            }
            #endif
        }
        
        if !isAuthenticated {
            mpcHost.send(to: peer, type: .pairingFailed, payload: Data(), mode: .reliable)
            return
        }

        // Generate new session token if authenticated via PIN (not token)
        if grantedSessionToken == nil {
            grantedSessionToken = UUID().uuidString
            trustedSessionTokens.insert(grantedSessionToken!)
            #if DEBUG
            AirCatchLog.info("🔐 Generated new session token for client", category: .network)
            #endif
        }

        if let pin = authenticatedPIN {
            crypto.deriveKey(from: pin)
        }
        connectedClients += 1

        isRelaySession = false
        currentFrameRate = AirCatchConfig.defaultFrameRate
        currentBitrate = AirCatchConfig.defaultBitrate

        self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
        self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
        
        // Resolution optimization: use client's preference or preset's default
        self.optimizeForHostDisplay = handshakeRequest?.optimizeForHostDisplay ?? false

        if let w = handshakeRequest?.screenWidth, let h = handshakeRequest?.screenHeight, w > 0, h > 0 {
            currentClientNativeBounds = (w, h)
        } else {
            currentClientNativeBounds = nil
        }
        if let nativeScale = handshakeRequest?.nativeScale {
            currentClientNativeScale = nativeScale
        } else {
            currentClientNativeScale = handshakeRequest?.screenScale
        }


        
        // Always use main display (mirror mode)
        let mainID = CGMainDisplayID()
        self.targetDisplayID = mainID
        self.targetScreenFrame = nil
        
        let wantsVideo = handshakeRequest?.requestVideo ?? true

        postStatusChange()

        Task {
            if wantsVideo {
                if !isStreaming {
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight,
                        deviceModel: handshakeRequest?.deviceModel
                    )
                }
            }

            let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
            let ackWidth = screenStreamer?.captureWidth ?? Int(fallbackSize.width)
            let ackHeight = screenStreamer?.captureHeight ?? Int(fallbackSize.height)
            let ack = HandshakeAck(
                width: ackWidth,
                height: ackHeight,
                frameRate: currentFrameRate,
                hostName: Host.current().localizedName ?? "Mac",
                bitrate: currentBitrate,
                isVirtualDisplay: false,
                displayMode: .mirror,
                displayPosition: nil,
                sessionToken: grantedSessionToken
            )

            if let data = try? JSONEncoder().encode(ack) {
                mpcHost.send(to: peer, type: .handshakeAck, payload: data, mode: .reliable)
            }
        }
    }

    @MainActor
    private func handleRelayHandshake(payload: Data) {
        let now = Date().timeIntervalSince1970
        if let lastPayload = lastRelayHandshakePayload,
           lastPayload == payload,
           now - lastRelayHandshakeAt < 1.0 {
            AirCatchLog.info("Relay handshake duplicate ignored", category: .network)
            return
        }
        lastRelayHandshakePayload = payload
        lastRelayHandshakeAt = now

        AirCatchLog.info("🤝 Decoding relay handshake (\(payload.count) bytes)", category: .network)
        let handshakeRequest: HandshakeRequest?
        do {
            handshakeRequest = try JSONDecoder().decode(HandshakeRequest.self, from: payload)
            AirCatchLog.info("🤝 Handshake decoded: device=\(handshakeRequest?.deviceModel ?? "unknown"), video=\(handshakeRequest?.requestVideo ?? true)", category: .network)
        } catch {
            #if DEBUG
            AirCatchLog.error("Failed to decode relay handshake request: \(error)", category: .network)
            #endif
            return
        }

        // SECURITY: Check session token first (for reconnection), then PIN authentication
        var grantedSessionToken: String?
        
        if let token = handshakeRequest?.sessionToken, trustedSessionTokens.contains(token) {
            grantedSessionToken = token
            #if DEBUG
            AirCatchLog.info("🔐 Relay: Session token auth succeeded (reconnection)", category: .network)
            #endif
        } else if let receivedPIN = handshakeRequest?.pin, !receivedPIN.isEmpty {
            let isAuthenticated = (receivedPIN == currentPIN)
            if !isAuthenticated {
                AirCatchLog.error("Relay PIN mismatch", category: .network)
                sendRelayControl(type: .pairingFailed, payload: Data())
                return
            }
            // Generate new token on successful PIN auth
            grantedSessionToken = UUID().uuidString
            trustedSessionTokens.insert(grantedSessionToken!)
            #if DEBUG
            AirCatchLog.info("🔐 Relay: Generated new session token for client", category: .network)
            #endif
        } else {
            // No token and no PIN - require authentication
            AirCatchLog.error("Relay: No session token or PIN provided", category: .network)
            sendRelayControl(type: .pairingFailed, payload: Data())
            return
        }

        connectedClients = max(connectedClients, 1)
        AirCatchLog.info("🤝 Client count: \(connectedClients), starting relay session", category: .network)

        isRelaySession = true
        currentFrameRate = AirCatchConfig.relayInitialFrameRate
        currentBitrate = AirCatchConfig.relayInitialBitrate

        self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
        self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
        self.optimizeForHostDisplay = handshakeRequest?.optimizeForHostDisplay ?? false

        if let w = handshakeRequest?.screenWidth, let h = handshakeRequest?.screenHeight, w > 0, h > 0 {
            currentClientNativeBounds = (w, h)
        } else {
            currentClientNativeBounds = nil
        }
        if let nativeScale = handshakeRequest?.nativeScale {
            currentClientNativeScale = nativeScale
        } else {
            currentClientNativeScale = handshakeRequest?.screenScale
        }

        let wantsVideo = handshakeRequest?.requestVideo ?? true
        let wantsAudio = handshakeRequest?.requestAudio ?? false

        postStatusChange()

        Task {
            if wantsVideo {
                if !isStreaming {
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight,
                        deviceModel: handshakeRequest?.deviceModel,
                        audioEnabled: wantsAudio
                    )
                } else if self.audioStreamingEnabled != wantsAudio {
                    stopStreaming()
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight,
                        deviceModel: handshakeRequest?.deviceModel,
                        audioEnabled: wantsAudio
                    )
                }
            }

            let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
            let ackWidth = screenStreamer?.captureWidth ?? Int(fallbackSize.width)
            let ackHeight = screenStreamer?.captureHeight ?? Int(fallbackSize.height)
            let ack = HandshakeAck(
                width: ackWidth,
                height: ackHeight,
                frameRate: currentFrameRate,
                hostName: Host.current().localizedName ?? "Mac",
                bitrate: currentBitrate,
                isVirtualDisplay: false,
                displayMode: .mirror,
                displayPosition: nil,
                sessionToken: grantedSessionToken
            )

            if let data = try? JSONEncoder().encode(ack) {
                self.sendRelayControl(type: .handshakeAck, payload: data)
            }

            if wantsVideo {
                self.startWebRTCSessionIfNeeded()
                if let width = self.screenStreamer?.captureWidth,
                   let height = self.screenStreamer?.captureHeight {
                    self.webRTCSession?.updateVideoFormat(width: width, height: height, fps: self.currentFrameRate)
                }
            }
        }
    }

    // MARK: - WebRTC Signaling (Relay)

    @MainActor
    private func startWebRTCSessionIfNeeded() {
        guard relayClient?.isConnected == true else { return }
        guard webRTCSession == nil else { return }

        let session = WebRTCHostSession(iceServerURLs: AirCatchConfig.webrtcIceServerURLs)
        session.setEncodingConstraints(
            maxBitrateBps: AirCatchConfig.webrtcMaxBitrate,
            minBitrateBps: AirCatchConfig.webrtcMinBitrate,
            maxFramerate: AirCatchConfig.webrtcMaxFrameRate
        )
        session.onSignal = { [weak self] message in
            Task { @MainActor in
                self?.sendWebRTCSignal(message)
            }
        }
        session.onConnectionStateChange = { [weak self] state in
            Task { @MainActor in
                self?.handleWebRTCStateChange(state)
            }
        }
        session.onDataReceived = { [weak self] data in
             Task { @MainActor in
                 self?.handleWebRTCData(data)
             }
         }

        webRTCSession = session
        session.start()
    }

    @MainActor
    private func stopWebRTCSession() {
        webRTCSession?.close()
        webRTCSession = nil
        webRTCActive = false
    }

    @MainActor
    private func handleWebRTCSignal(_ payload: Data) {
        guard let message = try? JSONDecoder().decode(WebRTCSignalMessage.self, from: payload) else {
            AirCatchLog.error("WebRTC: Failed to decode signal", category: .network)
            return
        }
        if webRTCSession == nil {
            startWebRTCSessionIfNeeded()
        }
        webRTCSession?.handleRemoteSignal(message)
    }

    @MainActor
    private func handleWebRTCData(_ data: Data) {
        // Expected format: [Type: 1] [Length: 4 (BigEndian)] [Payload: N]
        // This matches the format sent by ClientManager.sendControl via RelayClient
        guard data.count >= 5 else { return }
        
        let typeVal = data[0]
        guard let type = PacketType(rawValue: typeVal) else { return }
        
        // Parse BigEndian length
        let length = UInt32(data[1]) << 24 | UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4])
        
        guard data.count >= 5 + Int(length) else { return }
        let payload = data.subdata(in: 5..<5+Int(length))
        
        // Fast path for input events
        switch type {
        case .touchEvent:
            handleTouchEvent(payload)
        case .scrollEvent:
            handleScrollEvent(payload)
        case .keyEvent:
            handleKeyEvent(payload)
        case .mediaKeyEvent:
            handleMediaKeyEvent(payload)
        default:
            break
        }
    }

    @MainActor
    private func sendWebRTCSignal(_ message: WebRTCSignalMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        sendRelayControl(type: .webrtcSignal, payload: data)
    }

    @MainActor
    private func handleWebRTCStateChange(_ state: RTCPeerConnectionState) {
        switch state {
        case .connected:
            webRTCActive = true
            if isRelaySession {
                screenStreamer?.setEncodingEnabled(false)
            }
            AirCatchLog.info("WebRTC connected (relay video active)", category: .network)
        case .failed, .disconnected, .closed:
            webRTCActive = false
            if isRelaySession {
                screenStreamer?.setEncodingEnabled(true)
            }
            AirCatchLog.info("WebRTC disconnected - falling back to relay video", category: .network)
        default:
            break
        }
    }
    
    private nonisolated func handleHandshake(payload: Data, from connection: NWConnection) {
        #if DEBUG
        AirCatchLog.debug("Handshake received from: \(connection.endpoint)", category: .network)
        #endif
        
        Task { @MainActor in
            // Decode the handshake request to extract auth response
            let handshakeRequest: HandshakeRequest?
            do {
                handshakeRequest = try JSONDecoder().decode(HandshakeRequest.self, from: payload)
            } catch {
                AirCatchLog.error("Failed to decode handshake request: \(error)", category: .network)
                networkManager.sendTCP(to: connection, type: .pairingFailed, payload: Data())
                return
            }
            
            // SECURITY: Check session token first (for reconnection), then PIN authentication
            var authenticatedPIN: String?
            var grantedSessionToken: String?
            
            if let token = handshakeRequest?.sessionToken, self.trustedSessionTokens.contains(token) {
                grantedSessionToken = token
                #if DEBUG
                AirCatchLog.info("🔐 TCP: Session token auth succeeded (reconnection)", category: .network)
                #endif
            } else if let authResponse = handshakeRequest?.authResponse {
                // Challenge-response PIN auth
                if self.verifyTCPAuthResponse(authResponse, for: connection, expectedPIN: self.currentPIN) {
                    authenticatedPIN = self.currentPIN
                }
            }
            
            let isAuthenticated = (grantedSessionToken != nil) || (authenticatedPIN != nil)

            if !isAuthenticated {
                #if DEBUG
                AirCatchLog.debug("PIN mismatch for: \(connection.endpoint)", category: .network)
                #endif
                // Send pairing failed response
                networkManager.sendTCP(to: connection, type: .pairingFailed, payload: Data())
                self.clearTCPAuthChallenge(for: connection)
                return
            }

            // Generate new session token if authenticated via PIN (not token)
            if grantedSessionToken == nil {
                grantedSessionToken = UUID().uuidString
                self.trustedSessionTokens.insert(grantedSessionToken!)
                #if DEBUG
                AirCatchLog.info("🔐 TCP: Generated new session token for client", category: .network)
                #endif
            }

            self.clearTCPAuthChallenge(for: connection)
            if let pin = authenticatedPIN {
                self.crypto.deriveKey(from: pin)
            }

            #if DEBUG
            AirCatchLog.debug("Auth verified successfully for: \(connection.endpoint)", category: .network)
            #endif
            connectedClients += 1
            
            isRelaySession = false
            currentFrameRate = AirCatchConfig.defaultFrameRate
            currentBitrate = AirCatchConfig.defaultBitrate

            // Client transport preference
            self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
            self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
            
            // Resolution optimization: use client's preference or preset's default
            self.optimizeForHostDisplay = handshakeRequest?.optimizeForHostDisplay ?? false

            if let w = handshakeRequest?.screenWidth, let h = handshakeRequest?.screenHeight, w > 0, h > 0 {
                currentClientNativeBounds = (w, h)
            } else {
                currentClientNativeBounds = nil
            }
            if let nativeScale = handshakeRequest?.nativeScale {
                currentClientNativeScale = nativeScale
            } else {
                currentClientNativeScale = handshakeRequest?.screenScale
            }
            
            // Always use main display (mirror mode)
            let mainID = CGMainDisplayID()
            self.targetDisplayID = mainID
            self.targetScreenFrame = nil

            // Session features
            let wantsVideo = handshakeRequest?.requestVideo ?? true
            let wantsAudio = handshakeRequest?.requestAudio ?? false
            
            postStatusChange()
            
            // Start/adjust streaming only if video is requested.
            if wantsVideo {
                if !isStreaming {
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight,
                        deviceModel: handshakeRequest?.deviceModel,
                        audioEnabled: wantsAudio
                    )
                } else if self.audioStreamingEnabled != wantsAudio {
                    // Apply audio change for an already-running stream
                    stopStreaming()
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight,
                        deviceModel: handshakeRequest?.deviceModel,
                        audioEnabled: wantsAudio
                    )
                }
            }
            
            // Send handshake acknowledgment with actual capture size (pixels)
            let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
            let ackWidth = screenStreamer?.captureWidth ?? Int(fallbackSize.width)
            let ackHeight = screenStreamer?.captureHeight ?? Int(fallbackSize.height)
            let ack = HandshakeAck(
                width: ackWidth,
                height: ackHeight,
                frameRate: currentFrameRate,
                hostName: Host.current().localizedName ?? "Mac",
                bitrate: currentBitrate,
                isVirtualDisplay: false,
                displayMode: .mirror,
                displayPosition: nil,
                sessionToken: grantedSessionToken
            )
            
            if let data = try? JSONEncoder().encode(ack) {
                networkManager.sendTCP(to: connection, type: .handshakeAck, payload: data)
            }
        }
    }

    // MARK: - Adaptive Bitrate Logic
    
    private var qualityStableCount = 0
    private var frameRateStableCount = 0
    private var frameRateDegradeCount = 0

    @MainActor
    private func handlePingPacket(_ payload: Data, from connection: NWConnection) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            networkManager.sendTCP(to: connection, type: .pong, payload: data)
        }
    }

    @MainActor
    private func handleRelayPingPacket(_ payload: Data) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            sendRelayControl(type: .pong, payload: data)
        }
    }

    @MainActor
    private func handleQualityReport(_ payload: Data) {
        if webRTCActive {
            return
        }
        guard let report = try? JSONDecoder().decode(QualityReport.self, from: payload) else { return }

        if let estimated = report.estimatedBandwidthBps, estimated > 0 {
            lastEstimatedBandwidthBps = estimated
        }

        let minBitrate = BitrateCalculator.minimumBitrate
        let maxBitrate = isRelaySession
            ? min(BitrateCalculator.maximumBitrate, AirCatchConfig.relayMaxBitrate)
            : BitrateCalculator.maximumBitrate
        let maxFPS = isRelaySession
            ? AirCatchConfig.relayMaxFrameRate
            : AirCatchConfig.defaultFrameRate
        let minFPS = 30

        let latencyThreshold = 80.0
        let droppedFrameThreshold = 0
        let decreaseStep = 2_000_000
        let increaseStep = 1_000_000

        let isCongested = report.droppedFrames > droppedFrameThreshold || report.latencyMs > latencyThreshold

        if isCongested {
            frameRateStableCount = 0
            frameRateDegradeCount += 1
            if frameRateDegradeCount >= 2 && currentFrameRate > minFPS {
                currentFrameRate = minFPS
                screenStreamer?.setFrameRate(minFPS)
            }
        } else {
            frameRateDegradeCount = 0
            frameRateStableCount += 1
            if frameRateStableCount >= 4 && currentFrameRate < maxFPS {
                currentFrameRate = maxFPS
                screenStreamer?.setFrameRate(maxFPS)
            }
        }

        let refWidth = currentClientDimensions?.width ?? screenStreamer?.captureWidth ?? 1920
        let refHeight = currentClientDimensions?.height ?? screenStreamer?.captureHeight ?? 1080
        let baseBitrate = BitrateCalculator.calculateOptimal(
            width: refWidth,
            height: refHeight,
            fps: currentFrameRate,
            measuredBandwidth: lastEstimatedBandwidthBps
        )

        var newBitrate = currentBitrate
        var changed = false

        if isCongested {
            qualityStableCount = 0
            newBitrate = max(minBitrate, currentBitrate - decreaseStep)
            if newBitrate != currentBitrate {
                AirCatchLog.info("⚠️ Network congestion (Drop: \(report.droppedFrames), Latency: \(Int(report.latencyMs))ms). Reducing to \(newBitrate/1_000_000)Mbps")
                changed = true
            }
        } else {
            qualityStableCount += 1
            if qualityStableCount > 3 {
                qualityStableCount = 0
                let targetBitrate = min(maxBitrate, baseBitrate)
                if currentBitrate < targetBitrate {
                    newBitrate = min(targetBitrate, currentBitrate + increaseStep)
                    AirCatchLog.info("✅ Network stable. Increasing to \(newBitrate/1_000_000)Mbps")
                    changed = true
                }
            }
        }

        if changed {
            currentBitrate = newBitrate
            screenStreamer?.setBitrate(newBitrate)
        }
    }

    private func handleTouchEvent(_ payload: Data) {
        // PERFORMANCE: Use cached decoder instead of creating new one per event
        guard let touch = try? Self.jsonDecoder.decode(TouchEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode touch event", category: .input)
            #endif
            return
        }
        
        // PERFORMANCE: Discard stale touch events to prevent accumulated delay
        // from causing taps to become long presses
        let eventAge = Date().timeIntervalSince1970 - touch.timestamp
        let isEndingEvent: Bool = {
            switch touch.eventType {
            case .ended, .cancelled, .dragEnded:
                return true
            default:
                return false
            }
        }()

        if eventAge > Self.maxTouchEventAge, !isEndingEvent {
            #if DEBUG
            AirCatchLog.debug("Discarding stale touch event (age: \(String(format: "%.0f", eventAge * 1000))ms)", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received touch: type=\(touch.eventType) age=\(String(format: "%.0f", eventAge * 1000))ms", category: .input)
        #endif
        
        // PERFORMANCE: Removed nested Task - already running on MainActor via caller
        // Get the target display frame (virtual display if active, otherwise main)
        let screenFrame = self.targetDisplayFrame()

        // With virtual display, touch mapping is direct (1:1 pixel-perfect)
        // No letterboxing adjustment needed as the virtual display matches iPad exactly
        var finalNormX = touch.normalizedX
        var finalNormY = touch.normalizedY

        // Only adjust for letterboxing if NOT using virtual display
        // (i.e., when streaming main display with different aspect ratio)
        if !virtualDisplayManager.isVirtualDisplayActive {
            if let (clientW, clientH) = self.currentClientDimensions, clientW > 0, clientH > 0 {
                let hostW = screenFrame.width
                let hostH = screenFrame.height

                if hostW > 0 && hostH > 0 {
                    let hostAspect = hostW / hostH
                    let clientAspect = Double(clientW) / Double(clientH)

                    if hostAspect > clientAspect {
                        let coverageH = clientAspect / hostAspect
                        let barH = (1.0 - coverageH) / 2.0
                        finalNormY = (touch.normalizedY - barH) / coverageH
                    } else {
                        let coverageW = hostAspect / clientAspect
                        let barW = (1.0 - coverageW) / 2.0
                        finalNormX = (touch.normalizedX - barW) / coverageW
                    }
                }
            }
        }

        finalNormX = max(0, min(1, finalNormX))
        finalNormY = max(0, min(1, finalNormY))

        InputInjector.shared.injectClick(
            xPercent: finalNormX,
            yPercent: finalNormY,
            eventType: touch.eventType,
            in: screenFrame
        )
    }
    
    /// Returns the frame of the target display (virtual or main)
    private func targetDisplayFrame() -> CGRect {
        // If virtual display is active, return its frame
        if virtualDisplayManager.isVirtualDisplayActive,
           let virtualFrame = virtualDisplayManager.virtualDisplayFrame {
            return virtualFrame
        }
        
        // Use CoreGraphics for source-of-truth frame (Y-down, instant update)
        if let targetFrame = targetScreenFrame {
            return targetFrame
        }
        return CGDisplayBounds(CGMainDisplayID())
    }
    
    private func mainScreenFrame() -> CGRect {
        return NSScreen.main?.frame ?? .zero
    }
    
    private func handleScrollEvent(_ payload: Data) {
        // PERFORMANCE: Use cached decoder
        guard let scroll = try? Self.jsonDecoder.decode(ScrollEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode scroll event", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received scroll event: deltaX=\(scroll.deltaX), deltaY=\(scroll.deltaY)", category: .input)
        #endif
        
        // PERFORMANCE: Removed nested Task - already on MainActor
        // Get current mouse position for scroll location
        let mouseLocation = NSEvent.mouseLocation
        // Convert to screen coordinates (flip Y for CoreGraphics)
        if let screen = NSScreen.main {
            let cgPoint = CGPoint(x: mouseLocation.x, y: screen.frame.height - mouseLocation.y)
            InputInjector.shared.injectScroll(
                deltaX: Int32(scroll.deltaX),
                deltaY: Int32(scroll.deltaY),
                at: cgPoint
            )
        }
    }
    
    private func handleKeyEvent(_ payload: Data) {
        // PERFORMANCE: Use cached decoder
        guard let keyEvent = try? Self.jsonDecoder.decode(KeyEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode key event", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received key event: keyCode=\(keyEvent.keyCode) char=\(keyEvent.character ?? "") down=\(keyEvent.isKeyDown)", category: .input)
        #endif
        
        // Check if this is a text injection event (paste/multi-char input)
        if let character = keyEvent.character, !character.isEmpty, keyEvent.keyCode == 0 {
            // KeyCode 0 with a character string is our signal for "Injection"
            // PERFORMANCE: Removed nested Task - already on MainActor
            InputInjector.shared.injectText(character)
            return
        }
        
        InputInjector.shared.injectKeyEvent(
            keyCode: keyEvent.keyCode,
            modifiers: keyEvent.modifiers,
            isKeyDown: keyEvent.isKeyDown
        )
    }
    
    private func handleMediaKeyEvent(_ payload: Data) {
        guard let mediaEvent = try? JSONDecoder().decode(MediaKeyEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode media key event", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received media key event: mediaKey=\(mediaEvent.mediaKey)", category: .input)
        #endif
        
        InputInjector.shared.injectMediaKeyEvent(mediaKey: mediaEvent.mediaKey)
    }

    private nonisolated func handleClientDisconnect(_ connection: NWConnection) {
        AirCatchLog.info("Client disconnected: \(connection.endpoint)", category: .network)
        
        Task { @MainActor in
            self.clearTCPAuthChallenge(for: connection)
            connectedClients = max(0, connectedClients - 1)
            postStatusChange()
            
            // Stop streaming if no clients
            if connectedClients == 0 {
                stopStreamingAndRestore()
            }
        }
    }
    
    // MARK: - Screen Streaming
    
    /// Start streaming for relay mode clients
    func startStreaming(clientDimensions: (width: Int, height: Int)) {
        Task {
            await self.startStreaming(
                clientMaxWidth: clientDimensions.width,
                clientMaxHeight: clientDimensions.height,
                deviceModel: nil,
                audioEnabled: self.audioStreamingEnabled
            )
        }
    }
    
    /// Stop streaming for relay mode (public wrapper)
    func stopRelayStreaming() {
        stopStreamingAndRestore()
    }
    
    /// Current client device model (for Sidecar-like iPad detection)
    private var currentClientDeviceModel: String?
    
    private func startStreaming(
        clientMaxWidth: Int? = nil,
        clientMaxHeight: Int? = nil,
        deviceModel: String? = nil,
        audioEnabled: Bool = false
    ) async {
        guard screenStreamer == nil else { return }
        
        if let w = clientMaxWidth, let h = clientMaxHeight {
            self.currentClientDimensions = (w, h)
        } else {
            self.currentClientDimensions = nil
        }
        
        // Store device model for Sidecar-like iPad detection
        self.currentClientDeviceModel = deviceModel
        
        // Store audio preference for restart logic
        self.audioStreamingEnabled = audioEnabled
        
        // Try to create a virtual display
        // This implements Sidecar-like behavior:
        // - Detect iPad model from deviceModel string or resolution
        // - Apply preset resolution with 2x HiDPI scaling
        // - Match iPad's ~4:3 aspect ratio to avoid letterboxing
        var virtualDisplayID: CGDirectDisplayID? = nil
        if !optimizeForHostDisplay,
           let w = clientMaxWidth, let h = clientMaxHeight, w > 0, h > 0 {
            // Pass device model for better iPad detection (Sidecar-like hardware handshake)
            virtualDisplayID = virtualDisplayManager.createVirtualDisplay(
                clientWidth: w,
                clientHeight: h,
                deviceModel: deviceModel
            )
            if virtualDisplayID != nil {
                // Wait for virtual display to be ready
                try? await Task.sleep(for: .milliseconds(500))
                AirCatchLog.info("✅ Using Sidecar-like virtual display: \(virtualDisplayManager.presetName)", category: .video)
            } else {
                AirCatchLog.info("Virtual display unavailable, using main display", category: .video)
            }
        }

        // If no virtual display is available, switch the main display to a HiDPI mirror mode
        // when the client requested "Optimize for Client" (optimizeForHostDisplay == false).
        if !optimizeForHostDisplay, virtualDisplayID == nil,
           let nativeBounds = currentClientNativeBounds,
           let nativeScale = currentClientNativeScale {
            DisplayManager.shared.applyHiDPIMirroring(
                clientNativeWidth: nativeBounds.width,
                clientNativeHeight: nativeBounds.height,
                nativeScale: nativeScale
            )
        }
        
        // Use virtual display if available, otherwise main display
        let captureDisplayID = virtualDisplayID ?? CGMainDisplayID()
        self.targetDisplayID = captureDisplayID

        let targetFPS = AirCatchConfig.defaultFrameRate
        currentFrameRate = targetFPS
        if let clientW = clientMaxWidth, let clientH = clientMaxHeight, clientW > 0, clientH > 0 {
            let initialBitrate = BitrateCalculator.calculateOptimal(
                width: clientW,
                height: clientH,
                fps: targetFPS,
                measuredBandwidth: lastEstimatedBandwidthBps
            )

            currentBitrate = initialBitrate
        } else {
            currentBitrate = AirCatchConfig.defaultBitrate
        }
        
        // PERFORMANCE: Cap bitrate for remote relay sessions to prevent bufferbloat
        // High bitrates (10Mbps+) cause TCP head-of-line blocking on WAN, killing touch input.
        if isRelaySession {
            let remoteCap = 4_000_000 // 4 Mbps
            if currentBitrate > remoteCap {
                AirCatchLog.info("📉 Capping remote bitrate from \(currentBitrate/1_000_000)Mbps to \(remoteCap/1_000_000)Mbps for stability", category: .video)
                currentBitrate = remoteCap
            }
        }
        
        AirCatchLog.info("Starting stream: \(currentBitrate / 1_000_000)Mbps @ \(currentFrameRate)fps, audio: \(audioEnabled), optimizeForHostDisplay: \(optimizeForHostDisplay), displayID: \(captureDisplayID)", category: .video)
        let shouldSendWebRTC = isRelaySession
        screenStreamer = ScreenStreamer(
            targetFrameRate: currentFrameRate,
            targetBitrate: currentBitrate,
            maxClientWidth: clientMaxWidth,
            maxClientHeight: clientMaxHeight,
            targetDisplayID: captureDisplayID,
            audioEnabled: audioEnabled,
            optimizeForHostDisplay: optimizeForHostDisplay,
            encodeVideo: true,
            onFrame: { [weak self] compressedFrame in
                self?.broadcastVideoFrame(compressedFrame)
            },
            onRawFrame: { [weak self] pixelBuffer, time in
                guard shouldSendWebRTC else { return }
                self?.webRTCSession?.sendFrame(pixelBuffer: pixelBuffer, time: time)
            },
            onAudio: audioEnabled ? { [weak self] audioData in
                self?.broadcastAudioFrame(audioData)
            } : nil
        )

        
        do {
            try await screenStreamer?.start()
            isStreaming = true
            postStatusChange()

            if isRelaySession,
               let width = screenStreamer?.captureWidth,
               let height = screenStreamer?.captureHeight {
                webRTCSession?.updateVideoFormat(width: width, height: height, fps: currentFrameRate)
            }
            if isRelaySession && webRTCActive {
                screenStreamer?.setEncodingEnabled(false)
            }
            
            AirCatchLog.info("Screen streaming started", category: .video)
        } catch {
            AirCatchLog.error("Failed to start streaming: \(error)", category: .video)
            screenStreamer = nil
            
            // Check for Screen Capture permission error (SCStreamErrorDomain Code=-3801)
            let nsError = error as NSError
            if nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3801 {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Screen Recording Permission Required"
                    alert.informativeText = "AirCatch needs permission to stream your screen.\n\nGo to System Settings > Privacy & Security > Screen & System Audio Recording and turn on 'AirCatchHost'."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
    
    private func stopStreaming() {
        screenStreamer?.stop()
        screenStreamer = nil
        isStreaming = false
        
        postStatusChange()
        AirCatchLog.info("Screen streaming stopped", category: .video)
    }
    

    // Dedicated queue for video broadcasting to avoid blocking compression
    private let broadcastQueue = DispatchQueue(label: "com.aircatch.broadcast", qos: .userInteractive)

    private nonisolated func pruneCachedFramesIfNeeded(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        // Must be called on cachedFramesQueue
        guard !cachedFrames.isEmpty else { return }

        let oldKeys = cachedFrames
            .filter { now - $0.value.createdAt > AirCatchConfig.frameCacheTTL }
            .map { $0.key }
        for key in oldKeys { cachedFrames.removeValue(forKey: key) }
    }

    private nonisolated func cacheFrameForRetransmit(frameId: UInt32, totalChunks: Int, maxPayloadSize: Int, frameData: Data) {
        // Must be called on cachedFramesQueue
        // Note: losslessVideoEnabled is checked before calling this from broadcastVideoFrame
        
        // PERFORMANCE: Prune asynchronously to avoid blocking the frame caching path
        // Check every 60 frames (once per second at 60fps)
        if frameId % UInt32(AirCatchConfig.cachePruneInterval) == 0 {
            // Dispatch pruning to happen after current frame is cached
            let now = Date().timeIntervalSinceReferenceDate
            cachedFramesQueue.async { [weak self] in
                self?.pruneCachedFramesIfNeeded(now: now)
            }
        }
        
        // PERFORMANCE: Store frame data once instead of per-chunk copies
        cachedFrames[frameId] = CachedFrame(
            createdAt: Date().timeIntervalSinceReferenceDate,
            frameId: frameId,
            totalChunks: totalChunks,
            maxPayloadSize: maxPayloadSize,
            frameData: frameData
        )
    }
    
    // Changed per instructions:
    private func broadcastVideoFrame(_ data: Data) {
        // In relay mode, skip E2EE since there's no PIN-based key exchange
        let isRelayMode = relayClient?.isConnected ?? false
        let sendRelayVideo = !(isRelayMode && webRTCActive)
        
        let frameData: Data
        if isRelayMode {
            // Relay mode: send unencrypted (no PIN exchange possible)
            frameData = data
        } else {
            // Local mode: require encryption
            guard crypto.isReady else {
                #if DEBUG
                AirCatchLog.error("E2EE: Cannot broadcast - encryption not ready", category: .video)
                #endif
                return
            }
            guard let encrypted = crypto.encrypt(data) else {
                #if DEBUG
                AirCatchLog.error("E2EE: Video frame encryption failed - dropping frame", category: .video)
                #endif
                return
            }
            frameData = encrypted
        }
        
        // If client prefers reliability over latency, send complete frames over TCP.
        if !preferLowLatency {
            NetworkManager.shared.broadcastTCP(type: .videoFrame, payload: frameData)
            return
        }

        // Increment frame ID on MainActor before dispatching
        currentFrameId &+= 1
        let frameId = currentFrameId

        // Capture main-actor state needed for the background send.
        let maxPayloadSize = maxUDPPayloadSize
        let shouldCacheForRetransmit = losslessVideoEnabled
        let capturedRelay = relayClient
        // Dispatch to avoid blocking the compression callback thread
        let dataToChunk = frameData  // Use encrypted data for chunking
        broadcastQueue.async { [weak self] in
            guard let self else { return }
            
            let totalLen = dataToChunk.count
            let totalChunks = Int(ceil(Double(totalLen) / Double(maxPayloadSize)))
            
            // Safety check to avoid overflowing 2-byte index
            guard totalChunks <= UInt16.max else {
                AirCatchLog.error("Frame too large: \(totalLen) bytes", category: .video)
                return
            }
            
            if frameId <= 3 || frameId % 60 == 0 {
                AirCatchLog.debug("Broadcasting Frame \(frameId): \(totalLen) bytes, \(totalChunks) chunks", category: .video)
            }
            
            // PERFORMANCE: For relay mode, send full frame without chunking
            // WebSocket/TCP handles fragmentation, so we avoid chunk overhead entirely
            // This reduces message count by ~50x for typical frames
            if sendRelayVideo, let relay = capturedRelay, relay.isConnectedThreadSafe {
                relay.send(type: .videoFrame, payload: dataToChunk)
            }
            
            // Fragment and send via UDP (only for local network, needs small MTU-safe chunks)
            // PERFORMANCE: No longer build chunksForCache - we store frame data directly
            dataToChunk.withUnsafeBytes { rawBuffer in
                for i in 0..<totalChunks {
                    let start = i * maxPayloadSize
                    let end = min(start + maxPayloadSize, totalLen)

                    var packet = Data()
                    packet.reserveCapacity(8 + (end - start))

                    // Header: [FrameId: 4][ChunkIdx: 2][TotalChunks: 2]
                    var fId = frameId.bigEndian
                    var idx = UInt16(i).bigEndian
                    var total = UInt16(totalChunks).bigEndian

                    withUnsafeBytes(of: &fId) { packet.append(contentsOf: $0) }
                    withUnsafeBytes(of: &idx) { packet.append(contentsOf: $0) }
                    withUnsafeBytes(of: &total) { packet.append(contentsOf: $0) }
                    packet.append(contentsOf: rawBuffer[start..<end])

                    NetworkManager.shared.broadcastUDP(type: .videoFrameChunk, payload: packet)
                }
            }

            // PERFORMANCE: Cache frame data once instead of per-chunk copies
            if shouldCacheForRetransmit {
                let frameIdCopy = frameId
                let totalChunksCopy = totalChunks
                let maxPayloadCopy = maxPayloadSize
                let frameDataCopy = dataToChunk
                self.cachedFramesQueue.async {
                    self.cacheFrameForRetransmit(frameId: frameIdCopy, totalChunks: totalChunksCopy, maxPayloadSize: maxPayloadCopy, frameData: frameDataCopy)
                }
            }
        }
    }
    
    /// Broadcasts audio data to all connected clients via UDP
    private func broadcastAudioFrame(_ data: Data) {
        // In relay mode, skip E2EE since there's no PIN-based key exchange
        let isRelayMode = relayClient?.isConnected ?? false

        // E2EE: Encrypt audio data only for local sessions
        let audioData: Data
        if isRelayMode {
            audioData = data
        } else if crypto.isReady, let encrypted = crypto.encrypt(data) {
            audioData = encrypted
        } else {
            audioData = data
        }
        
        // Audio packets are small enough to send in one UDP datagram (typically ~4KB for 48kHz stereo)
        // The data already contains 8-byte timestamp header from ScreenStreamer
        NetworkManager.shared.broadcastUDP(type: .audioPCM, payload: audioData)
        
        // Also send through relay if connected
        if let webrtc = webRTCSession, webrtc.isDataChannelOpen {
            // PERFORMANCE: Send audio via WebRTC Data Channel (UDP) to avoid TCP head-of-line blocking
            // Construct packet: [Type: 1] [Length: 4] [Payload: N]
            var packet = Data()
            packet.append(PacketType.audioPCM.rawValue)
            let length = UInt32(audioData.count)
            packet.append(UInt8((length >> 24) & 0xFF))
            packet.append(UInt8((length >> 16) & 0xFF))
            packet.append(UInt8((length >> 8) & 0xFF))
            packet.append(UInt8(length & 0xFF))
            packet.append(audioData)
            
            webrtc.sendData(packet)
        } else if let relay = relayClient, relay.isConnected {
            relay.send(type: .audioPCM, payload: audioData)
        }
    }

    private func handleVideoChunkNack(_ payload: Data, from connection: NWConnection) {
        let request: VideoChunkNackRequest?
        do {
            request = try JSONDecoder().decode(VideoChunkNackRequest.self, from: payload)
        } catch {
            #if DEBUG
            AirCatchLog.error("Failed to decode VideoChunkNackRequest: \(error)", category: .network)
            #endif
            return
        }
        guard let request else { return }

        guard losslessVideoEnabled else { return }

        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case .hostPort(let host, _) = endpoint else { return }
        let hostString = "\(host)"

        guard let udpEndpoint = NetworkManager.shared.udpEndpoint(forHostString: hostString) else {
            return
        }

        // Thread-safe access to cached frames
        cachedFramesQueue.async { [weak self] in
            guard let self else { return }
            guard let cached = self.cachedFrames[request.frameId] else { return }

            // PERFORMANCE: Lazy chunk reconstruction from stored frame data
            let payloadsToResend: [Data] = request.missingChunkIndices.compactMap { idx in
                cached.chunkPacket(at: Int(idx))
            }

            self.broadcastQueue.async {
                for payload in payloadsToResend {
                    NetworkManager.shared.sendUDP(to: udpEndpoint, type: .videoFrameChunk, payload: payload)
                }
            }
        }
    }

    @MainActor
    private func handleRelayVideoChunkNack(_ payload: Data) {
        let request: VideoChunkNackRequest?
        do {
            request = try JSONDecoder().decode(VideoChunkNackRequest.self, from: payload)
        } catch {
            #if DEBUG
            AirCatchLog.error("Failed to decode relay VideoChunkNackRequest: \(error)", category: .network)
            #endif
            return
        }
        guard let request else { return }
        guard losslessVideoEnabled else { return }

        let capturedRelay = relayClient
        cachedFramesQueue.async { [weak self] in
            guard let self else { return }
            guard let cached = self.cachedFrames[request.frameId] else { return }

            // PERFORMANCE: Lazy chunk reconstruction from stored frame data
            let payloadsToResend: [Data] = request.missingChunkIndices.compactMap { idx in
                cached.chunkPacket(at: Int(idx))
            }

            self.broadcastQueue.async {
                guard let relay = capturedRelay, relay.isConnectedThreadSafe else { return }
                for payload in payloadsToResend {
                    relay.send(type: .videoFrameChunk, payload: payload)
                }
            }
        }
    }

    private func sendRelayControl(type: PacketType, payload: Data) {
        guard let relay = relayClient, relay.isConnected else { return }
        relay.send(type: type, payload: payload)
    }
    
    // MARK: - Notifications
    
    private func postStatusChange() {
        NotificationCenter.default.post(name: Self.statusDidChange, object: isStreaming)
    }
}
