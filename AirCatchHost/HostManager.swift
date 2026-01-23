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

/// Central manager for the AirCatch host functionality.
@MainActor
final class HostManager: ObservableObject {
    static let shared = HostManager()
    static let statusDidChange = Notification.Name("StreamingStatusChanged")
    
    // MARK: - Published State
    
    @Published private(set) var isRunning = false
    @Published private(set) var isStreaming = false
    @Published private(set) var connectedClients = 0
    @Published private(set) var currentPIN: String = "------"
    @Published var currentQuality: QualityPreset = .balanced
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
        remoteTransport.updateSessionId(currentPIN)
        crypto.deriveKey(from: currentPIN)  // E2EE: Derive encryption key from PIN
    }
    
    // MARK: - Network Components
    
    private let networkManager = NetworkManager.shared
    private let bonjourAdvertiser = BonjourAdvertiser()
    private let mpcHost = MPCAirCatchHost()
    private let remoteTransport = RemoteTransportHost()
    private let crypto = CryptoManager()  // E2EE encryption
    private let virtualDisplayManager = VirtualDisplayManager.shared
    
    // MARK: - Screen Capture
    
    private var screenStreamer: ScreenStreamer?
    private var currentClientDimensions: (width: Int, height: Int)?
    private var currentFrameId: UInt32 = 0
    private let maxUDPPayloadSize = AirCatchConfig.maxUDPPayloadSize // Safe UDP payload size (below MTU)

    /// When false, prefer sending video over TCP (higher reliability).
    private var preferLowLatency: Bool = true

    /// When true, keep a short retransmit window for UDP video chunks (wired mode).
    private var losslessVideoEnabled: Bool = true

    /// Whether the active session is a Remote (Internet) session.
    private var remoteSessionActive: Bool = false
    private var remoteCodecPreference: CodecPreference? = nil
    
    /// When true, stream at host's native resolution. When false, scale to client resolution.
    private var optimizeForHostDisplay: Bool = false

    private struct CachedFrame {
        let createdAt: TimeInterval
        let totalChunks: Int
        let chunksByIndex: [Int: Data]
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
                try networkManager.startTCPListener(port: AirCatchConfig.tcpPort) { [weak self] packet, connection in
                    self?.handleTCPPacket(packet, from: connection)
                }
                
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

                // Remote relay (Internet) listener
                self.remoteTransport.start(
                    sessionId: self.currentPIN,
                    onTCPPacket: { [weak self] packet in
                        self?.handleRemoteTCPPacket(packet)
                    },
                    onUDPPacket: { [weak self] packet in
                        self?.handleRemoteUDPPacket(packet)
                    },
                    onStateChange: { state in
                        switch state {
                        case .failed(let error):
                            AirCatchLog.error("Remote relay failed: \(error)", category: .network)
                        default:
                            break
                        }
                    }
                )
                
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
        mpcHost.stop()
        remoteTransport.stop()
        remoteSessionActive = false
        
        isRunning = false
        isStreaming = false
        connectedClients = 0
        postStatusChange()
        
        AirCatchLog.info("Stopped", category: .network)
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

    @MainActor
    private func handleRemoteTCPPacket(_ packet: Packet) {
        switch packet.type {
        case .handshake:
            Task { @MainActor in
                await handleRemoteHandshake(payload: packet.payload)
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
            handleRemotePingPacket(packet.payload)
        case .qualityReport:
            handleRemoteQualityReport(packet.payload)
        case .disconnect:
            handleRemoteDisconnect()
        default:
            break
        }
    }

    @MainActor
    private func handleRemoteUDPPacket(_ packet: Packet) {
        switch packet.type {
        case .videoFrameChunkNack:
            // Lossless retransmit disabled in Remote mode
            break
        default:
            break
        }

    }

    private func setupMPCHostCallbacksIfNeeded() {
        // Safe to assign multiple times; closures are idempotent.
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
    
    // Helper to stop streaming and restore resolution
    private func stopStreamingAndRestore() {
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
        let receivedPIN = handshakeRequest?.pin ?? ""

        if receivedPIN != currentPIN {
            mpcHost.send(to: peer, type: .pairingFailed, payload: Data(), mode: .reliable)
            return
        }

        // Local session (non-remote)
        remoteSessionActive = false
        remoteCodecPreference = nil

        connectedClients += 1

        let previousQuality = currentQuality
        if let preferredQuality = handshakeRequest?.preferredQuality {
            currentQuality = preferredQuality
        }

        self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
        self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
        
        // Resolution optimization: use client's preference or preset's default
        self.optimizeForHostDisplay = handshakeRequest?.optimizeForHostDisplay ?? currentQuality.defaultOptimizeForHostDisplay

        // Local TCP "Virtual Display" Logic: Switch Resolution to match client (HiDPI)
        if let w = handshakeRequest?.screenWidth, let h = handshakeRequest?.screenHeight, w > 0, h > 0 {
             // Apply resolution match for better full-screen experience
             DisplayManager.shared.matchClientResolution(clientWidth: w, clientHeight: h)
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
                } else if previousQuality != currentQuality {
                    stopStreaming()
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
                frameRate: currentQuality.frameRate,
                hostName: Host.current().localizedName ?? "Mac",
                qualityPreset: currentQuality,
                bitrate: currentQuality.bitrate,
                isVirtualDisplay: false,
                displayMode: .mirror,
                displayPosition: nil
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
            // Decode the handshake request to extract PIN
            let handshakeRequest: HandshakeRequest?
            do {
                handshakeRequest = try JSONDecoder().decode(HandshakeRequest.self, from: payload)
            } catch {
                AirCatchLog.error("Failed to decode handshake request: \(error)", category: .network)
                networkManager.sendTCP(to: connection, type: .pairingFailed, payload: Data())
                return
            }
            let receivedPIN = handshakeRequest?.pin ?? ""
            
            // Verify PIN
            if receivedPIN != currentPIN {
                #if DEBUG
                AirCatchLog.debug("PIN mismatch for: \(connection.endpoint)", category: .network)
                #endif
                // Send pairing failed response
                networkManager.sendTCP(to: connection, type: .pairingFailed, payload: Data())
                return
            }

            // Local session (non-remote)
            self.remoteSessionActive = false
            self.remoteCodecPreference = nil
            
            #if DEBUG
            AirCatchLog.debug("PIN verified successfully for: \(connection.endpoint)", category: .network)
            #endif
            connectedClients += 1
            
            // Apply client's preferred quality if specified
            let previousQuality = currentQuality
            if let preferredQuality = handshakeRequest?.preferredQuality {
                currentQuality = preferredQuality
                AirCatchLog.info("Using client's preferred quality: \(preferredQuality.displayName)", category: .video)
                
                // Apply new bitrate/FPS immediately if streaming
                if let streamer = self.screenStreamer {
                    streamer.setBitrate(currentQuality.bitrate)
                    streamer.setFrameRate(currentQuality.frameRate)
                }
            }

            // Client transport preference
            self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
            self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
            
            // Resolution optimization: use client's preference or preset's default
            self.optimizeForHostDisplay = handshakeRequest?.optimizeForHostDisplay ?? currentQuality.defaultOptimizeForHostDisplay
            
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
                } else if previousQuality != currentQuality || self.audioStreamingEnabled != wantsAudio {
                    // Apply quality/audio change for an already-running stream
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
                frameRate: currentQuality.frameRate,
                hostName: Host.current().localizedName ?? "Mac",
                qualityPreset: currentQuality,
                bitrate: currentQuality.bitrate,
                isVirtualDisplay: false,
                displayMode: .mirror,
                displayPosition: nil
            )
            
            if let data = try? JSONEncoder().encode(ack) {
                networkManager.sendTCP(to: connection, type: .handshakeAck, payload: data)
            }
        }
    }

    @MainActor
    private func handleRemoteHandshake(payload: Data) async {
        let handshakeRequest: HandshakeRequest?
        do {
            handshakeRequest = try JSONDecoder().decode(HandshakeRequest.self, from: payload)
        } catch {
            AirCatchLog.error("Failed to decode remote handshake: \(error)", category: .network)
            remoteTransport.sendTCP(type: .pairingFailed, payload: Data())
            return
        }

        let receivedPIN = handshakeRequest?.pin ?? ""
        guard receivedPIN == currentPIN else {
            remoteTransport.sendTCP(type: .pairingFailed, payload: Data())
            return
        }

        remoteSessionActive = true
        connectedClients += 1
        
        // --- REMOTE QUALITY POLICY ENFORCEMENT ---
        // Force HEVC Main (8-bit) for best compatibility/bandwidth ratio
        remoteCodecPreference = .hevc
        
        // Remote mode: prioritize latency, disable retransmit
        self.preferLowLatency = true
        self.losslessVideoEnabled = false
        
        // Remote mode: always use client resolution to minimize bandwidth over internet
        self.optimizeForHostDisplay = false

        // Always use main display (mirror mode)
        let mainID = CGMainDisplayID()
        self.targetDisplayID = mainID
        self.targetScreenFrame = nil

        let wantsVideo = handshakeRequest?.requestVideo ?? true
        let wantsAudio = handshakeRequest?.requestAudio ?? false
        
        // Use client's native resolution directly (no cap)
        // iPad sends its current display mode (Default or More Space)
        let clientW = handshakeRequest?.screenWidth
        let clientH = handshakeRequest?.screenHeight
        
        if let w = clientW, let h = clientH {
            AirCatchLog.info("Remote mode using client native resolution: \(w)x\(h)", category: .video)
        }

        postStatusChange()

        if wantsVideo {
            // Apply Remote Settings explicitly
            currentQuality = .balanced // Placeholder, will be overridden by direct calls below
            
            if !isStreaming {
                await startStreaming(
                    clientMaxWidth: clientW,
                    clientMaxHeight: clientH,
                    deviceModel: handshakeRequest?.deviceModel,
                    audioEnabled: wantsAudio
                )
            } else {
                stopStreaming()
                await startStreaming(
                    clientMaxWidth: clientW,
                    clientMaxHeight: clientH,
                    deviceModel: handshakeRequest?.deviceModel,
                    audioEnabled: wantsAudio
                )
            }
            

            
            // INITIAL Remote Bitrate & FPS (Target 6-8 Mbps, 30 FPS)
            if let streamer = self.screenStreamer {
                // Start conservatively at 6 Mbps
                streamer.setBitrate(6_000_000)
                streamer.setFrameRate(30)
                AirCatchLog.info("Remote mode started: 6Mbps @ 30fps (Adaptive 4-10Mbps)", category: .video)
            }
        }

        let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        let ackWidth = screenStreamer?.captureWidth ?? Int(fallbackSize.width)
        let ackHeight = screenStreamer?.captureHeight ?? Int(fallbackSize.height)
        
        // Send ACK with the initial values
        let ack = HandshakeAck(
            width: ackWidth,
            height: ackHeight,
            frameRate: 30, // Target FPS
            hostName: Host.current().localizedName ?? "Mac",
            qualityPreset: nil, // Indicates custom/enforced quality
            bitrate: 6_000_000, // Initial bitrate
            isVirtualDisplay: false,
            displayMode: .mirror,
            displayPosition: nil
        )

        if let data = try? JSONEncoder().encode(ack) {
            remoteTransport.sendTCP(type: .handshakeAck, payload: data)
        }
    }

    @MainActor
    private func handleRemoteDisconnect() {
        remoteSessionActive = false
        connectedClients = max(0, connectedClients - 1)
        postStatusChange()
        if connectedClients == 0 {
            stopStreaming()
        }
    }
    
    // MARK: - Adaptive Bitrate Logic
    
    private var currentRemoteBitrate: Int = 6_000_000
    private var currentRemoteFPS: Int = 30
    private var qualityStableCount = 0
    
    @MainActor
    private func handleRemoteQualityReport(_ payload: Data) {
        guard remoteSessionActive else { return }
        guard let report = try? JSONDecoder().decode(QualityReport.self, from: payload) else { return }
        
        // Thresholds
        let latencyThreshold = 150.0 // ms
        let droppedFrameThreshold = 0
        
        var newBitrate = currentRemoteBitrate
        var newFPS = currentRemoteFPS
        var changed = false
        
        // Congestion Detected?
        if report.droppedFrames > droppedFrameThreshold || report.latencyMs > latencyThreshold {
            qualityStableCount = 0
            
            // Back off aggressively
            newBitrate = max(AirCatchConfig.remoteMinBitrate, currentRemoteBitrate - 1_000_000)
            
            // If already at minimum bitrate, drop FPS
            if newBitrate == AirCatchConfig.remoteMinBitrate {
                newFPS = AirCatchConfig.remoteMinFPS
            }
            
            if newBitrate != currentRemoteBitrate || newFPS != currentRemoteFPS {
                AirCatchLog.info("⚠️ Network congestion (Drop: \(report.droppedFrames), Latency: \(Int(report.latencyMs))ms). Reducing to \(newBitrate/1_000_000)Mbps @ \(newFPS)fps")
                changed = true
            }
            
        } else {
            // Stable - Attempt Recovery
            qualityStableCount += 1
            
            // Only increase after 5 seconds of stability (assuming 1 report/sec)
            if qualityStableCount > 5 {
                qualityStableCount = 0 // Reset counter to pace increases
                
                // Recover FPS first
                if currentRemoteFPS < AirCatchConfig.remoteMaxFPS {
                    newFPS = AirCatchConfig.remoteMaxFPS
                    AirCatchLog.info("✅ Stability recovered. Restoring \(AirCatchConfig.remoteMaxFPS) FPS.")
                    changed = true
                } 
                // Then recover Bitrate
                else if currentRemoteBitrate < AirCatchConfig.remoteMaxBitrate {
                    newBitrate = min(AirCatchConfig.remoteMaxBitrate, currentRemoteBitrate + 500_000)
                    AirCatchLog.info("✅ Network stable. Increasing to \(newBitrate/1_000_000)Mbps")
                    changed = true
                }
            }
        }
        
        if changed {
            currentRemoteBitrate = newBitrate
            currentRemoteFPS = newFPS
            if let streamer = self.screenStreamer {
                streamer.setBitrate(newBitrate)
                streamer.setFrameRate(newFPS)
            }
        }
    }

    @MainActor
    private func handlePingPacket(_ payload: Data, from connection: NWConnection) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            networkManager.sendTCP(to: connection, type: .pong, payload: data)
        }
    }

    @MainActor
    private func handleRemotePingPacket(_ payload: Data) {
        guard let ping = try? JSONDecoder().decode(PingPacket.self, from: payload) else { return }
        let pong = PongPacket(pingTimestamp: ping.timestamp)
        if let data = try? JSONEncoder().encode(pong) {
            remoteTransport.sendTCP(type: .pong, payload: data)
        }
    }

    @MainActor
    private func handleQualityReport(_ payload: Data) {
        guard remoteSessionActive else { return }
        guard let _ = try? JSONDecoder().decode(QualityReport.self, from: payload) else { return }

        // For remote mode, use fixed 5Mbps bitrate and HEVC codec
        // No adaptive switching - keeps stream stable without restarts
        let remoteBitrate = 5_000_000  // 5 Mbps fixed for remote
        if let streamer = self.screenStreamer {
            streamer.setBitrate(remoteBitrate)
        }
        // Always use HEVC for remote - no codec switching to avoid decoder mismatch
    }

    @MainActor
    private func updateRemoteCodecIfNeeded(_ target: CodecPreference) {
        // Disabled for remote mode - codec switching causes decoder mismatch on client
        // Just update preference for next session, don't restart stream
        guard remoteSessionActive else { return }
        remoteCodecPreference = target
    }
    
    private func handleTouchEvent(_ payload: Data) {
        guard let touch = try? JSONDecoder().decode(TouchEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode touch event", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received touch: type=\(touch.eventType)", category: .input)
        #endif
        
        Task { @MainActor in
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
        guard let scroll = try? JSONDecoder().decode(ScrollEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode scroll event", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received scroll event: deltaX=\(scroll.deltaX), deltaY=\(scroll.deltaY)", category: .input)
        #endif
        
        Task { @MainActor in
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
    }
    
    private func handleKeyEvent(_ payload: Data) {
        guard let keyEvent = try? JSONDecoder().decode(KeyEvent.self, from: payload) else {
            #if DEBUG
            AirCatchLog.error("Failed to decode key event", category: .input)
            #endif
            return
        }
        
        #if DEBUG
        AirCatchLog.debug("Received key event: keyCode=\(keyEvent.keyCode) char=\(keyEvent.character ?? "") down=\(keyEvent.isKeyDown)", category: .input)
        #endif
        
        // Check if this is a text injection event (Voice Typing)
        if let character = keyEvent.character, !character.isEmpty, keyEvent.keyCode == 0 {
            // KeyCode 0 with a character string is our signal for "Injection"
            Task { @MainActor in
                InputInjector.shared.injectText(character)
            }
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
            connectedClients = max(0, connectedClients - 1)
            postStatusChange()
            
            // Stop streaming if no clients
            if connectedClients == 0 {
                stopStreamingAndRestore()
            }
        }
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
        } else {
            self.currentClientDimensions = nil
        }
        
        // Store device model for Sidecar-like iPad detection
        self.currentClientDeviceModel = deviceModel
        
        // Store audio preference for restart logic
        self.audioStreamingEnabled = audioEnabled
        
        // For local connections (not remote), try to create a virtual display
        // This implements Sidecar-like behavior:
        // - Detect iPad model from deviceModel string or resolution
        // - Apply preset resolution with 2x HiDPI scaling
        // - Match iPad's ~4:3 aspect ratio to avoid letterboxing
        var virtualDisplayID: CGDirectDisplayID? = nil
        if !remoteSessionActive, !optimizeForHostDisplay,
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
        
        // Use virtual display if available, otherwise main display
        let captureDisplayID = virtualDisplayID ?? CGMainDisplayID()
        self.targetDisplayID = captureDisplayID
        
        AirCatchLog.info("Starting stream with preset: \(currentQuality.displayName), audio: \(audioEnabled), optimizeForHostDisplay: \(optimizeForHostDisplay), displayID: \(captureDisplayID)", category: .video)
        screenStreamer = ScreenStreamer(
            preset: currentQuality,
            maxClientWidth: clientMaxWidth,
            maxClientHeight: clientMaxHeight,
            targetDisplayID: captureDisplayID,
            codecOverride: remoteSessionActive ? remoteCodecPreference : nil,
            audioEnabled: audioEnabled,
            optimizeForHostDisplay: optimizeForHostDisplay,
            onFrame: { [weak self] compressedFrame in
                self?.broadcastVideoFrame(compressedFrame)
            },
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

    private nonisolated func cacheFrameForRetransmit(frameId: UInt32, totalChunks: Int, chunksByIndex: [Int: Data]) {
        // Must be called on cachedFramesQueue
        // Note: losslessVideoEnabled is checked before calling this from broadcastVideoFrame
        // Prune only every 60 frames (once per second at 60fps) for performance
        if frameId % UInt32(AirCatchConfig.cachePruneInterval) == 0 {
            pruneCachedFramesIfNeeded()
        }
        cachedFrames[frameId] = CachedFrame(
            createdAt: Date().timeIntervalSinceReferenceDate,
            totalChunks: totalChunks,
            chunksByIndex: chunksByIndex
        )
    }
    
    // Changed per instructions:
    private func broadcastVideoFrame(_ data: Data) {
        // E2EE: Encrypt video data if crypto is ready
        let frameData: Data
        if crypto.isReady, let encrypted = crypto.encrypt(data) {
            frameData = encrypted
        } else {
            frameData = data  // Fallback to unencrypted (shouldn't happen after handshake)
        }
        
        // Remote mode: always send complete frames via TCP (WebSocket is already TCP-based)
        // Chunking over WebSocket creates too many messages and overwhelms the connection
        if remoteSessionActive {
            remoteTransport.sendTCP(type: .videoFrame, payload: frameData)
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
        let isRemoteSession = remoteSessionActive
        
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
            
            // Fragment and send
            var chunksForCache: [Int: Data] = [:]
            if shouldCacheForRetransmit {
                chunksForCache.reserveCapacity(totalChunks)
            }
            for i in 0..<totalChunks {
                let start = i * maxPayloadSize
                let end = min(start + maxPayloadSize, totalLen)
                let chunkData = dataToChunk.subdata(in: start..<end)
                
                var packet = Data()
                packet.reserveCapacity(8 + chunkData.count)
                
                // Header: [FrameId: 4][ChunkIdx: 2][TotalChunks: 2]
                var fId = frameId.bigEndian
                var idx = UInt16(i).bigEndian
                var total = UInt16(totalChunks).bigEndian

                withUnsafeBytes(of: &fId) { packet.append(contentsOf: $0) }
                withUnsafeBytes(of: &idx) { packet.append(contentsOf: $0) }
                withUnsafeBytes(of: &total) { packet.append(contentsOf: $0) }
                packet.append(chunkData)
                
                // Send chunk via UDP (remote relay or local broadcast)
                if isRemoteSession {
                    self.remoteTransport.sendUDP(type: .videoFrameChunk, payload: packet)
                } else {
                    NetworkManager.shared.broadcastUDP(type: .videoFrameChunk, payload: packet)
                }

                if shouldCacheForRetransmit {
                    chunksForCache[i] = packet
                }
            }

            if shouldCacheForRetransmit {
                let chunksSnapshot = chunksForCache
                let frameIdCopy = frameId
                let totalChunksCopy = totalChunks
                self.cachedFramesQueue.async {
                    self.cacheFrameForRetransmit(frameId: frameIdCopy, totalChunks: totalChunksCopy, chunksByIndex: chunksSnapshot)
                }
            }
        }
    }
    
    /// Broadcasts audio data to all connected clients via UDP
    private func broadcastAudioFrame(_ data: Data) {
        // E2EE: Encrypt audio data
        let audioData: Data
        if crypto.isReady, let encrypted = crypto.encrypt(data) {
            audioData = encrypted
        } else {
            audioData = data
        }
        
        // Audio packets are small enough to send in one UDP datagram (typically ~4KB for 48kHz stereo)
        // The data already contains 8-byte timestamp header from ScreenStreamer
        if remoteSessionActive {
            remoteTransport.sendUDP(type: .audioPCM, payload: audioData)
        } else {
            NetworkManager.shared.broadcastUDP(type: .audioPCM, payload: audioData)
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

            let payloadsToResend: [Data] = request.missingChunkIndices.compactMap { idx in
                cached.chunksByIndex[Int(idx)]
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
}

