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

/// Central manager for the AirCatch host functionality.
@MainActor
final class HostManager: ObservableObject {
    static let shared = HostManager()
    static let statusDidChange = Notification.Name("StreamingStatusChanged")
    
    private final class InputStateCache: @unchecked Sendable {
        private let lock = NSLock()
        private var isVirtualDisplayActive = false
        private var clientDimensions: (width: Int, height: Int)?

        func snapshot() -> (isVirtualDisplayActive: Bool, clientDimensions: (width: Int, height: Int)?) {
            lock.lock()
            let snapshot = (isVirtualDisplayActive, clientDimensions)
            lock.unlock()
            return snapshot
        }

        func setVirtualDisplayActive(_ value: Bool) {
            lock.lock()
            isVirtualDisplayActive = value
            lock.unlock()
        }

        func setClientDimensions(_ value: (width: Int, height: Int)?) {
            lock.lock()
            clientDimensions = value
            lock.unlock()
        }
    }
    
    // PERFORMANCE: Cached JSON coders to avoid allocation per touch event
    // nonisolated(unsafe): These are thread-safe reference types used from inputProcessingQueue
    private nonisolated static let jsonEncoder = JSONEncoder()
    private nonisolated static let jsonDecoder = JSONDecoder()
    
    // Input queue timing. Uses host receive time to avoid client/host clock skew issues.
    private nonisolated static let maxInputQueueDelay: TimeInterval = 0.50
    
    // PERFORMANCE: Dedicated high-priority queue for input processing
    // Avoids main thread latency for touch/scroll/key events
    private nonisolated let inputProcessingQueue = DispatchQueue(
        label: "com.aircatch.input.processing",
        qos: .userInteractive
    )
    
    // Thread-safe cached copies of MainActor state for nonisolated input handlers.
    // Updated from MainActor when connection state changes; read from inputProcessingQueue.
    private nonisolated let inputStateCache = InputStateCache()
    
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

    /// Session tokens granted to clients for reconnection without PIN.
    /// Value is absolute expiry timestamp (epoch seconds).
    private var trustedSessionTokens: [String: TimeInterval] = [:]
    private nonisolated static let sessionTokenTTL: TimeInterval = 24 * 60 * 60
    private nonisolated static let maxTrustedSessionTokens: Int = 64

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

    /// Track whether the active local session is strict AWDL over MPC.
    private var mpcSessionActive: Bool = false

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

                // AWDL/P2P now runs over Network.framework sockets with includePeerToPeer.
                // Keep MPC disabled to avoid parallel transport overhead.

                isRunning = true
                postStatusChange()
                
                AirCatchLog.info("Started - Listening on UDP:\(udpPort) TCP:\(tcpPort)", category: .network)
                
            } catch {
                AirCatchLog.error("Failed to start: \(error)", category: .network)
            }
        }
    }
    
    func stop() {
        screenStreamer?.stop()
        screenStreamer = nil

        networkManager.stopAll()
        bonjourAdvertiser.stopAdvertising()
        tcpAuthChallenges.removeAll()

        isRunning = false
        isStreaming = false
        mpcSessionActive = false
        connectedClients = 0
        postStatusChange()
        
        AirCatchLog.info("Stopped", category: .network)
    }
    
    // MARK: - Input Event Routing

    private nonisolated func enqueueTouchEvent(_ payload: Data) {
        let receivedAt = Date().timeIntervalSinceReferenceDate
        inputProcessingQueue.async { [weak self] in
            self?.handleTouchEvent(payload, receivedAt: receivedAt)
        }
    }

    private nonisolated func enqueueScrollEvent(_ payload: Data) {
        let receivedAt = Date().timeIntervalSinceReferenceDate
        inputProcessingQueue.async { [weak self] in
            self?.handleScrollEvent(payload, receivedAt: receivedAt)
        }
    }

    private nonisolated func enqueueKeyEvent(_ payload: Data) {
        inputProcessingQueue.async { [weak self] in
            self?.handleKeyEvent(payload)
        }
    }

    private nonisolated func enqueueMediaKeyEvent(_ payload: Data) {
        inputProcessingQueue.async { [weak self] in
            self?.handleMediaKeyEvent(payload)
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
            enqueueTouchEvent(packet.payload)
        case .scrollEvent:
            enqueueScrollEvent(packet.payload)
        case .keyEvent:
            enqueueKeyEvent(packet.payload)
        case .mediaKeyEvent:
            enqueueMediaKeyEvent(packet.payload)
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
        // PERFORMANCE: Nonisolated fast-path for input events from MPC.
        // Routes touch/scroll/key directly to inputProcessingQueue without
        // the MainActor hop that handleMPCPacket would otherwise require.
        mpcHost.onInputReceived = { [weak self] packet, _ in
            guard let self else { return }
            switch packet.type {
            case .touchEvent:
                self.enqueueTouchEvent(packet.payload)
            case .scrollEvent:
                self.enqueueScrollEvent(packet.payload)
            case .keyEvent:
                self.enqueueKeyEvent(packet.payload)
            case .mediaKeyEvent:
                self.enqueueMediaKeyEvent(packet.payload)
            default:
                break
            }
        }
        mpcHost.onPeerDisconnected = { [weak self] _ in
            guard let self else { return }
            self.mpcSessionActive = false
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
        stopStreaming()
        // Only restore if we are the last client disconnecting
        if connectedClients == 0 {
            mpcSessionActive = false
            // Destroy virtual display if active
            virtualDisplayManager.destroyVirtualDisplay()
            self.setCachedVirtualDisplayActive(false)
            // Also restore main display if it was changed
            DisplayManager.shared.restoreOriginalResolution()
        }
    }

    private func handleMPCPacket(_ packet: Packet, from peer: MCPeerID) {
        switch packet.type {
        case .handshake:
            handleMPCHandshake(payload: packet.payload, from: peer)
        case .ping:
            handleMPCPingPacket(packet.payload, to: peer)
        case .qualityReport:
            Task { @MainActor in
                self.handleQualityReport(packet.payload)
            }
        case .touchEvent:
            enqueueTouchEvent(packet.payload)
        case .scrollEvent:
            enqueueScrollEvent(packet.payload)
        case .keyEvent:
            enqueueKeyEvent(packet.payload)
        case .mediaKeyEvent:
            enqueueMediaKeyEvent(packet.payload)
        case .videoFrameChunkNack:
            break
        case .audioPCM:
            break
        case .disconnect:
            if connectedClients > 0 {
                connectedClients -= 1
            }
            postStatusChange()
            if connectedClients == 0 {
                mpcSessionActive = false
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
        if let token = handshakeRequest?.sessionToken, isTrustedSessionToken(token) {
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
            // SECURITY: No legacy plaintext PIN fallback - require challenge-response auth
            isAuthenticated = false
            #if DEBUG
            AirCatchLog.error("E2EE: No auth response provided - rejecting", category: .network)
            #endif
        }
        
        if !isAuthenticated {
            mpcHost.send(to: peer, type: .pairingFailed, payload: Data(), mode: .reliable)
            return
        }

        // Generate new session token if authenticated via PIN (not token)
        if grantedSessionToken == nil {
            grantedSessionToken = Self.generateSecureToken()
            storeTrustedSessionToken(grantedSessionToken!)
            #if DEBUG
            AirCatchLog.info("🔐 Generated new session token for client", category: .network)
            #endif
        }

        if let pin = authenticatedPIN {
            crypto.deriveKey(from: pin)
        }
        connectedClients += 1

        mpcSessionActive = true
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
            
            if let token = handshakeRequest?.sessionToken, self.isTrustedSessionToken(token) {
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
                grantedSessionToken = Self.generateSecureToken()
                self.storeTrustedSessionToken(grantedSessionToken!)
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
            
            mpcSessionActive = false
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
    // PERFORMANCE: Prevent rapid bitrate oscillation with a cooldown timer.
    // Without this, sessions bounce between high and low bitrate every few seconds,
    // causing jerky video and encoder stalls.
    private var lastBitrateChangeAt: TimeInterval = 0
    private let bitrateChangeCooldown: TimeInterval = 4.0  // seconds between changes

    @MainActor
    private func handlePingPacket(_ payload: Data, from connection: NWConnection) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            networkManager.sendTCP(to: connection, type: .pong, payload: data)
        }
    }

    private func handleMPCPingPacket(_ payload: Data, to peer: MCPeerID) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            mpcHost.send(to: peer, type: .pong, payload: data, mode: .unreliable)
        }
    }

    @MainActor
    private func handleQualityReport(_ payload: Data) {
        guard let report = try? JSONDecoder().decode(QualityReport.self, from: payload) else { return }

        if let estimated = report.estimatedBandwidthBps, estimated > 0 {
            lastEstimatedBandwidthBps = estimated
        }

        let minBitrate = BitrateCalculator.minimumBitrate
        let maxBitrate = BitrateCalculator.maximumBitrate
        let maxFPS = AirCatchConfig.defaultFrameRate
        let minFPS = 30

        let latencyThreshold = 150.0
        let droppedFrameThreshold = 0
        let decreaseStep = 2_000_000
        let increaseStep = 1_000_000

        let isCongested = report.droppedFrames > droppedFrameThreshold || report.latencyMs > latencyThreshold

        if isCongested {
            frameRateStableCount = 0
            frameRateDegradeCount += 1
            if frameRateDegradeCount >= 2 && currentFrameRate > minFPS {
                currentFrameRate = minFPS
                screenStreamer?.setCaptureFrameRate(minFPS)
            }
        } else {
            frameRateDegradeCount = 0
            frameRateStableCount += 1
            if frameRateStableCount >= 4 && currentFrameRate < maxFPS {
                currentFrameRate = maxFPS
                screenStreamer?.setCaptureFrameRate(maxFPS)
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
        let now = Date().timeIntervalSince1970

        if isCongested {
            qualityStableCount = 0
            // PERFORMANCE: Allow immediate decrease (no cooldown) to recover from congestion fast.
            newBitrate = max(minBitrate, currentBitrate - decreaseStep)
            if newBitrate != currentBitrate {
                AirCatchLog.info("⚠️ Network congestion (Drop: \(report.droppedFrames), Latency: \(Int(report.latencyMs))ms). Reducing to \(newBitrate/1_000_000)Mbps")
                changed = true
            }
        } else {
            qualityStableCount += 1
            // PERFORMANCE: Require several stable reports before increasing bitrate,
            // and enforce a cooldown between changes.
            // This prevents rapid oscillation that causes encoder stalls and jerky video.
            let stableCountNeeded = 3
            if qualityStableCount > stableCountNeeded {
                // Enforce cooldown: don't increase bitrate if we changed recently
                guard now - lastBitrateChangeAt >= bitrateChangeCooldown else { return }
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
            lastBitrateChangeAt = now
        }
    }

    // PERFORMANCE: nonisolated - runs on inputProcessingQueue for lowest latency
    private nonisolated func handleTouchEvent(_ payload: Data, receivedAt: TimeInterval) {
        // PERFORMANCE: Use cached decoder instead of creating new one per event
        guard let touch = try? Self.jsonDecoder.decode(TouchEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode touch event", category: .input)
            #endif
            return
        }
        let cachedState = cachedInputStateSnapshot()
        
        // Discard stale events based on host-side queue delay (not cross-device wall clock).
        let queueDelay = Date().timeIntervalSinceReferenceDate - receivedAt
        let maxQueueDelay = Self.maxInputQueueDelay
        let isEndingEvent: Bool = {
            switch touch.eventType {
            case .ended, .cancelled, .dragEnded:
                return true
            default:
                return false
            }
        }()

        if queueDelay > maxQueueDelay, !isEndingEvent {
            #if DEBUG
            AirCatchLog.debug("Discarding stale touch event (queue delay: \(String(format: "%.0f", queueDelay * 1000))ms)", category: .input)
            #endif
            return
        }
        
        // Get the target display frame - use main display bounds (thread-safe)
        let screenFrame = CGDisplayBounds(CGMainDisplayID())

        // With virtual display, touch mapping is direct (1:1 pixel-perfect)
        // No letterboxing adjustment needed as the virtual display matches iPad exactly
        var finalNormX = touch.normalizedX
        var finalNormY = touch.normalizedY

        // Only adjust for letterboxing if NOT using virtual display
        // (i.e., when streaming main display with different aspect ratio)
        if !cachedState.isVirtualDisplayActive {
            if let (clientW, clientH) = cachedState.clientDimensions, clientW > 0, clientH > 0 {
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
    
    // PERFORMANCE: nonisolated - runs on inputProcessingQueue
    private nonisolated func handleScrollEvent(_ payload: Data, receivedAt: TimeInterval) {
        let cachedState = cachedInputStateSnapshot()
        let queueDelay = Date().timeIntervalSinceReferenceDate - receivedAt
        let maxQueueDelay = Self.maxInputQueueDelay
        if queueDelay > maxQueueDelay {
            return
        }

        // PERFORMANCE: Use cached decoder
        guard let scroll = try? Self.jsonDecoder.decode(ScrollEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode scroll event", category: .input)
            #endif
            return
        }
        
        // Get current mouse position for scroll location
        let mouseLocation = CGEvent(source: nil)?.location ?? .zero
        InputInjector.shared.injectScroll(
            deltaX: Int32(scroll.deltaX),
            deltaY: Int32(scroll.deltaY),
            at: mouseLocation
        )
    }
    
    // PERFORMANCE: nonisolated - runs on inputProcessingQueue
    private nonisolated func handleKeyEvent(_ payload: Data) {
        // PERFORMANCE: Use cached decoder
        guard let keyEvent = try? Self.jsonDecoder.decode(KeyEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode key event", category: .input)
            #endif
            return
        }
        
        // Check if this is a text injection event (paste/multi-char input)
        if let character = keyEvent.character, !character.isEmpty, keyEvent.keyCode == 0 {
            InputInjector.shared.injectText(character)
            return
        }
        
        InputInjector.shared.injectKeyEvent(
            keyCode: keyEvent.keyCode,
            modifiers: keyEvent.modifiers,
            isKeyDown: keyEvent.isKeyDown
        )
    }
    
    // PERFORMANCE: nonisolated - runs on inputProcessingQueue
    private nonisolated func handleMediaKeyEvent(_ payload: Data) {
        // PERFORMANCE: Use cached decoder
        guard let mediaEvent = try? Self.jsonDecoder.decode(MediaKeyEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode media key event", category: .input)
            #endif
            return
        }
        
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
    
    private nonisolated func cachedInputStateSnapshot() -> (isVirtualDisplayActive: Bool, clientDimensions: (width: Int, height: Int)?) {
        inputStateCache.snapshot()
    }

    private nonisolated func setCachedVirtualDisplayActive(_ value: Bool) {
        inputStateCache.setVirtualDisplayActive(value)
    }

    private nonisolated func setCachedClientDimensions(_ value: (width: Int, height: Int)?) {
        inputStateCache.setClientDimensions(value)
    }

    // MARK: - Screen Streaming

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
            self.setCachedClientDimensions((w, h))
        } else {
            self.currentClientDimensions = nil
            self.setCachedClientDimensions(nil)
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
        setCachedVirtualDisplayActive(false)
        if !optimizeForHostDisplay,
           let w = clientMaxWidth, let h = clientMaxHeight, w > 0, h > 0 {
            // Pass device model for better iPad detection (Sidecar-like hardware handshake)
            virtualDisplayID = virtualDisplayManager.createVirtualDisplay(
                clientWidth: w,
                clientHeight: h,
                deviceModel: deviceModel
            )
            if virtualDisplayID != nil {
                self.setCachedVirtualDisplayActive(true)
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

        // Tailscale initial bitrate cap to avoid saturating DERP relays before feedback arrives.
        // The client asks for TCP (preferLowLatency = false) when on Tailscale.
        if !preferLowLatency {
            currentBitrate = min(currentBitrate, 8_000_000)
        }

        AirCatchLog.info("Starting stream: \(currentBitrate / 1_000_000)Mbps @ \(currentFrameRate)fps, audio: \(audioEnabled), optimizeForHostDisplay: \(optimizeForHostDisplay), displayID: \(captureDisplayID)", category: .video)
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
            onRawFrame: nil,
            onAudio: audioEnabled ? { [weak self] audioData in
                self?.broadcastAudioFrame(audioData)
            } : nil
        )


        do {
            try await screenStreamer?.start()
            isStreaming = true
            postStatusChange()

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
        // SECURITY: All media must remain encrypted end-to-end.
        let sendMPCVideo = mpcSessionActive
        guard crypto.isReady else {
            #if DEBUG
            AirCatchLog.error("E2EE: Dropping video frame - encryption key not ready", category: .video)
            #endif
            return
        }
        guard let frameData = crypto.encrypt(data) else {
            #if DEBUG
            AirCatchLog.error("E2EE: Video frame encryption failed - dropping frame", category: .video)
            #endif
            return
        }

        // Strict AWDL mode: route media over MPC only (no router/IP path).
        if sendMPCVideo {
            // PERFORMANCE: Always use .reliable for MPC video frames.
            // MCSession's .unreliable mode silently drops messages > ~64KB,
            // which includes most HEVC keyframes (100-300KB at 16Mbps).
            // A dropped keyframe causes ~1 second of frozen/corrupt video
            // because all subsequent P-frames are undecodable until the
            // next keyframe arrives. .reliable adds ~1-2ms latency but
            // guarantees delivery, eliminating periodic stalls.
            mpcHost.broadcast(type: .videoFrame, payload: frameData, mode: .reliable)
            return
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
            
            // Fragment and send via UDP (needs small MTU-safe chunks)
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
        // SECURITY: All media must remain encrypted end-to-end.
        guard crypto.isReady else {
            #if DEBUG
            AirCatchLog.error("E2EE: Dropping audio frame - encryption key not ready", category: .video)
            #endif
            return
        }
        guard let audioData = crypto.encrypt(data) else {
            #if DEBUG
            AirCatchLog.error("E2EE: Audio frame encryption failed - dropping frame", category: .video)
            #endif
            return
        }

        // Strict AWDL mode: route audio over MPC only.
        if mpcSessionActive {
            mpcHost.broadcast(type: .audioPCM, payload: audioData, mode: .unreliable)
            return
        }

        // Audio packets are small enough to send in one UDP datagram (typically ~4KB for 48kHz stereo)
        // The data already contains 8-byte timestamp header from ScreenStreamer
        NetworkManager.shared.broadcastUDP(type: .audioPCM, payload: audioData)
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

    // MARK: - Notifications
    
    private func postStatusChange() {
        NotificationCenter.default.post(name: Self.statusDidChange, object: isStreaming)
    }
    
    // MARK: - Security Helpers
    
    private func pruneExpiredSessionTokens(now: TimeInterval = Date().timeIntervalSince1970) {
        trustedSessionTokens = trustedSessionTokens.filter { $0.value > now }
    }
    
    private func isTrustedSessionToken(_ token: String, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        pruneExpiredSessionTokens(now: now)
        guard let expiry = trustedSessionTokens[token], expiry > now else {
            trustedSessionTokens.removeValue(forKey: token)
            return false
        }
        // Sliding TTL keeps active devices connected while expiring stale tokens.
        trustedSessionTokens[token] = now + Self.sessionTokenTTL
        return true
    }
    
    private func storeTrustedSessionToken(_ token: String, now: TimeInterval = Date().timeIntervalSince1970) {
        pruneExpiredSessionTokens(now: now)
        trustedSessionTokens[token] = now + Self.sessionTokenTTL
        
        let overflow = trustedSessionTokens.count - Self.maxTrustedSessionTokens
        guard overflow > 0 else { return }
        
        let byExpiry = trustedSessionTokens.sorted { $0.value < $1.value }
        for (tokenToRemove, _) in byExpiry.prefix(overflow) {
            trustedSessionTokens.removeValue(forKey: tokenToRemove)
        }
    }
    
    /// SECURITY: Generate cryptographically secure session token using SecRandomCopyBytes
    private static func generateSecureToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else {
            // Fallback to UUID if secure random fails (should never happen)
            return UUID().uuidString
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    /// SECURITY: Constant-time string comparison to prevent timing attacks
    private static func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(aBytes, bBytes) {
            result |= x ^ y
        }
        return result == 0
    }
}
