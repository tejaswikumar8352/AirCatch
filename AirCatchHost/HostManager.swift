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
    @Published private(set) var currentPIN: String = "0000"
    @Published var currentQuality: QualityPreset = .balanced
    @Published private(set) var availableDisplays: [String] = []
    
    // Network mode detection (for UI only - always local P2P)
    var networkMode: NetworkMode {
        return .local
    }
    
    var statusDescription: String {
        if !isRunning {
            return "Stopped"
        } else if isStreaming {
            return "Streaming"
        } else {
            return "Listening"
        }
    }
    
    /// Generates a new random 4-digit PIN
    func regeneratePIN() {
        currentPIN = String(format: "%04d", Int.random(in: 0...9999))
        NSLog("[AirCatchHost] New PIN generated")
    }
    
    // MARK: - Network Components
    
    private let networkManager = NetworkManager.shared
    private let bonjourAdvertiser = BonjourAdvertiser()
    private let mpcHost = MPCAirCatchHost()
    
    // MARK: - Screen Capture
    
    private var screenStreamer: ScreenStreamer?
    private var currentClientDimensions: (width: Int, height: Int)?
    private var currentFrameId: UInt32 = 0
    private let maxUDPPayloadSize = 1200 // Safe UDP payload size (below MTU)

    /// When false, prefer sending video over TCP (higher reliability).
    private var preferLowLatency: Bool = true

    /// When true, keep a short retransmit window for UDP video chunks (wired mode).
    private var losslessVideoEnabled: Bool = true

    private struct CachedFrame {
        let createdAt: TimeInterval
        let totalChunks: Int
        let chunksByIndex: [Int: Data]
    }

    // FrameID -> cached chunks for retransmit (lossless mode)
    private var cachedFrames: [UInt32: CachedFrame] = [:]

    // Target display selection (main vs extended)
    private var targetDisplayID: CGDirectDisplayID? = nil
    private var targetScreenFrame: CGRect? = nil
    
    // Extended display state
    private var virtualDisplayManager = VirtualDisplayManager.shared
    private var isExtendedDisplayActive = false
    private var currentDisplayConfig: ExtendedDisplayConfig?
    
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
                    NSLog("[AirCatchHost] Failed to bind UDP listener")
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
                
                NSLog("[AirCatchHost] Started - Listening on UDP:\(udpPort) TCP:\(tcpPort)")
                
            } catch {
                NSLog("[AirCatchHost] Failed to start: \(error)")
            }
        }
    }
    
    func stop() {
        screenStreamer?.stop()
        screenStreamer = nil
        
        networkManager.stopAll()
        bonjourAdvertiser.stopAdvertising()
        mpcHost.stop()
        
        isRunning = false
        isStreaming = false
        connectedClients = 0
        postStatusChange()
        
        NSLog("[AirCatchHost] Stopped")
    }
    
    // MARK: - Packet Handling
    
    private nonisolated func handleIncomingPacket(_ packet: Packet, from endpoint: NWEndpoint?) {
        #if DEBUG
        NSLog("[AirCatchHost] Received UDP packet type: \(packet.type)")
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
                self.stopStreaming()
            }
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
        case .audioPCM:
            break
        case .disconnect:
            if connectedClients > 0 {
                connectedClients -= 1
            }
            postStatusChange()
            if connectedClients == 0 {
                stopStreaming()
            }
        default:
            break
        }
    }

    private func handleMPCHandshake(payload: Data, from peer: MCPeerID) {
        let handshakeRequest = try? JSONDecoder().decode(HandshakeRequest.self, from: payload)
        let receivedPIN = handshakeRequest?.pin ?? ""

        if receivedPIN != currentPIN {
            mpcHost.send(to: peer, type: .pairingFailed, payload: Data(), mode: .reliable)
            return
        }

        connectedClients += 1

        let previousQuality = currentQuality
        if let preferredQuality = handshakeRequest?.preferredQuality {
            currentQuality = preferredQuality
        }

        self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
        self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
        
        // Handle display configuration (mirror vs extend)
        let displayConfig = handshakeRequest?.displayConfig
        self.currentDisplayConfig = displayConfig
        self.configureTargetDisplay(config: displayConfig, clientWidth: handshakeRequest?.screenWidth, clientHeight: handshakeRequest?.screenHeight)
        
        let wantsVideo = handshakeRequest?.requestVideo ?? true

        postStatusChange()

        Task {
            if wantsVideo {
                if !isStreaming {
                    await startStreaming(clientMaxWidth: handshakeRequest?.screenWidth, clientMaxHeight: handshakeRequest?.screenHeight)
                } else if previousQuality != currentQuality {
                    stopStreaming()
                    await startStreaming(clientMaxWidth: handshakeRequest?.screenWidth, clientMaxHeight: handshakeRequest?.screenHeight)
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
                networkMode: networkMode,
                qualityPreset: currentQuality,
                bitrate: currentQuality.bitrate,
                isVirtualDisplay: self.isExtendedDisplayActive,
                displayMode: displayConfig?.mode ?? .mirror,
                displayPosition: displayConfig?.position
            )

            if let data = try? JSONEncoder().encode(ack) {
                mpcHost.send(to: peer, type: .handshakeAck, payload: data, mode: .reliable)
            }
        }
    }
    
    private nonisolated func handleHandshake(payload: Data, from connection: NWConnection) {
        #if DEBUG
        NSLog("[AirCatchHost] Handshake received from: \(connection.endpoint)")
        #endif
        
        Task { @MainActor in
            // Decode the handshake request to extract PIN
            let handshakeRequest = try? JSONDecoder().decode(HandshakeRequest.self, from: payload)
            let receivedPIN = handshakeRequest?.pin ?? ""
            
            // Verify PIN
            if receivedPIN != currentPIN {
                #if DEBUG
                NSLog("[AirCatchHost] PIN mismatch for: \(connection.endpoint)")
                #endif
                // Send pairing failed response
                networkManager.sendTCP(to: connection, type: .pairingFailed, payload: Data())
                return
            }
            
            #if DEBUG
            NSLog("[AirCatchHost] PIN verified successfully for: \(connection.endpoint)")
            #endif
            connectedClients += 1
            
            // Apply client's preferred quality if specified
            let previousQuality = currentQuality
            if let preferredQuality = handshakeRequest?.preferredQuality {
                currentQuality = preferredQuality
                NSLog("[AirCatchHost] Using client's preferred quality: \(preferredQuality.displayName)")
            }

            // Client transport preference
            self.preferLowLatency = handshakeRequest?.preferLowLatency ?? true
            self.losslessVideoEnabled = handshakeRequest?.losslessVideo ?? false
            
            // Handle display configuration (mirror vs extend)
            let displayConfig = handshakeRequest?.displayConfig
            self.currentDisplayConfig = displayConfig
            self.configureTargetDisplay(config: displayConfig, clientWidth: handshakeRequest?.screenWidth, clientHeight: handshakeRequest?.screenHeight)

            // Session features
            let wantsVideo = handshakeRequest?.requestVideo ?? true
            
            postStatusChange()
            
            // Start/adjust streaming only if video is requested.
            if wantsVideo {
                if !isStreaming {
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight
                    )
                } else if previousQuality != currentQuality {
                    // Apply quality change for an already-running stream
                    stopStreaming()
                    await startStreaming(
                        clientMaxWidth: handshakeRequest?.screenWidth,
                        clientMaxHeight: handshakeRequest?.screenHeight
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
                networkMode: networkMode,
                qualityPreset: currentQuality,
                bitrate: currentQuality.bitrate,
                isVirtualDisplay: self.isExtendedDisplayActive,
                displayMode: displayConfig?.mode ?? .mirror,
                displayPosition: displayConfig?.position
            )
            
            if let data = try? JSONEncoder().encode(ack) {
                networkManager.sendTCP(to: connection, type: .handshakeAck, payload: data)
            }
        }
    }
    
    private func handleTouchEvent(_ payload: Data) {
        guard let touch = try? JSONDecoder().decode(TouchEvent.self, from: payload) else {
            #if DEBUG
            NSLog("[AirCatchHost] Failed to decode touch event")
            #endif
            return
        }
        
        #if DEBUG
        NSLog("[AirCatchHost] Received touch: type=\(touch.eventType)")
        #endif
        
        Task { @MainActor in
            // Absolute positioning touch input (Magic Keyboard/Trackpad mode removed)
            let screenFrame = self.targetDisplayFrame()

            // Adjust for letterboxing/pillarboxing in the stream
            // The stream is exactly client dimensions (e.g. 2778x1940)
            // But Mac content is fit inside it.
            // We must un-map the black bars to get correct screen coordinates.
            var finalNormX = touch.normalizedX
            var finalNormY = touch.normalizedY

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
    
    /// Returns the frame of the currently active target display (main or virtual)
    private func targetDisplayFrame() -> CGRect {
        if isExtendedDisplayActive, let frame = virtualDisplayManager.getVirtualDisplayFrame() {
            return frame
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
            NSLog("[AirCatchHost] Failed to decode scroll event")
            #endif
            return
        }
        
        #if DEBUG
        NSLog("[AirCatchHost] Received scroll event: deltaX=\(scroll.deltaX), deltaY=\(scroll.deltaY)")
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

    private nonisolated func handleClientDisconnect(_ connection: NWConnection) {
        NSLog("[AirCatchHost] Client disconnected: \(connection.endpoint)")
        
        Task { @MainActor in
            connectedClients = max(0, connectedClients - 1)
            postStatusChange()
            
            // Stop streaming if no clients
            if connectedClients == 0 {
                stopStreaming()
            }
        }
    }
    
    // MARK: - Screen Streaming
    
    private func startStreaming(clientMaxWidth: Int? = nil, clientMaxHeight: Int? = nil) async {
        guard screenStreamer == nil else { return }
        
        if let w = clientMaxWidth, let h = clientMaxHeight {
            self.currentClientDimensions = (w, h)
        } else {
            self.currentClientDimensions = nil
        }
        
        NSLog("[AirCatchHost] Starting stream with preset: \(currentQuality.displayName)")
        screenStreamer = ScreenStreamer(
            preset: currentQuality,
            maxClientWidth: clientMaxWidth,
            maxClientHeight: clientMaxHeight,
            onFrame: { [weak self] compressedFrame in
                self?.broadcastVideoFrame(compressedFrame)
            }
        )

        
        do {
            try await screenStreamer?.start()
            isStreaming = true
            postStatusChange()
            NSLog("[AirCatchHost] Screen streaming started")
        } catch {
            NSLog("[AirCatchHost] Failed to start streaming: \(error)")
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
        
        // Destroy virtual display if active
        destroyVirtualDisplayIfNeeded()
        
        postStatusChange()
        NSLog("[AirCatchHost] Screen streaming stopped")
    }

    // MARK: - Virtual Display Management
    
    private func destroyVirtualDisplayIfNeeded() {
        guard isExtendedDisplayActive else { return }
        virtualDisplayManager.destroyVirtualDisplay()
        isExtendedDisplayActive = false
        currentDisplayConfig = nil
        NSLog("[AirCatchHost] Virtual display destroyed")
    }
    
    // MARK: - Display Selection

    private func configureTargetDisplay(extended: Bool) {
        if extended {
            // Create virtual display with default settings
            let config = ExtendedDisplayConfig(mode: .extend, position: .right)
            configureTargetDisplay(config: config, clientWidth: nil, clientHeight: nil)
        } else {
            // Use main display (mirror mode)
            destroyVirtualDisplayIfNeeded()
            let mainID = CGMainDisplayID()
            self.targetDisplayID = mainID
            self.targetScreenFrame = NSScreen.main?.frame
            NSLog("[AirCatchHost] Using main display: \(mainID)")
        }
    }
    
    private func configureTargetDisplay(config: ExtendedDisplayConfig?, clientWidth: Int?, clientHeight: Int?) {
        guard let config = config, config.mode == .extend else {
            // Mirror mode - use main display
            destroyVirtualDisplayIfNeeded()
            let mainID = CGMainDisplayID()
            self.targetDisplayID = mainID
            // IMPORTANT: Set to nil so targetDisplayFrame() uses dynamic CGDisplayBounds(mainID)
            // This ensures we always get the *current* resolution if it changes mid-stream
            self.targetScreenFrame = nil
            self.isExtendedDisplayActive = false
            NSLog("[AirCatchHost] Using main display (mirror mode): \(mainID)")
            return
        }
        
        // Extend mode - create virtual display
        guard virtualDisplayManager.isSupported else {
            NSLog("[AirCatchHost] Virtual display not supported: \(virtualDisplayManager.unavailableReason ?? "Unknown")")
            // Fall back to main display
            let mainID = CGMainDisplayID()
            self.targetDisplayID = mainID
            self.targetScreenFrame = NSScreen.main?.frame
            self.isExtendedDisplayActive = false
            return
        }
        
        // Calculate optimal resolution based on client screen
        let width: Int
        let height: Int
        if let clientWidth = clientWidth, let clientHeight = clientHeight {
            // Use client's native resolution for best quality
            // For HiDPI, we use half the pixel dimensions as logical resolution
            let optimal = VirtualDisplayManager.optimalResolution(for: clientWidth, iPadHeight: clientHeight)
            width = optimal.width
            height = optimal.height
        } else {
            // Default to a reasonable resolution
            width = 1920
            height = 1080
        }
        
        // Create the virtual display
        if let displayID = virtualDisplayManager.createVirtualDisplay(config: config, width: width, height: height) {
            self.targetDisplayID = displayID
            self.targetScreenFrame = virtualDisplayManager.getVirtualDisplayFrame()
            self.isExtendedDisplayActive = true
            NSLog("[AirCatchHost] Created virtual display: \(displayID), size: \(width)x\(height), position: \(config.position.rawValue)")
        } else {
            NSLog("[AirCatchHost] Failed to create virtual display, falling back to main display")
            let mainID = CGMainDisplayID()
            self.targetDisplayID = mainID
            self.targetScreenFrame = NSScreen.main?.frame
            self.isExtendedDisplayActive = false
        }
    }
    
    // Dedicated queue for video broadcasting to avoid blocking compression
    private let broadcastQueue = DispatchQueue(label: "com.aircatch.broadcast", qos: .userInteractive)

    private func pruneCachedFramesIfNeeded(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        // Always prune old frames to prevent memory leaks, regardless of lossless mode
        guard !cachedFrames.isEmpty else { return }

        let oldKeys = cachedFrames
            .filter { now - $0.value.createdAt > 1.0 }
            .map { $0.key }
        for key in oldKeys { cachedFrames.removeValue(forKey: key) }
    }

    private func cacheFrameForRetransmit(frameId: UInt32, totalChunks: Int, chunksByIndex: [Int: Data]) {
        guard losslessVideoEnabled else { return }
        pruneCachedFramesIfNeeded()
        cachedFrames[frameId] = CachedFrame(
            createdAt: Date().timeIntervalSinceReferenceDate,
            totalChunks: totalChunks,
            chunksByIndex: chunksByIndex
        )
    }
    
    // Changed per instructions:
    private func broadcastVideoFrame(_ data: Data) {
        // If client prefers reliability over latency, send complete frames over TCP.
        if !preferLowLatency {
            NetworkManager.shared.broadcastTCP(type: .videoFrame, payload: data)
            return
        }

        // Increment frame ID on MainActor before dispatching
        currentFrameId &+= 1
        let frameId = currentFrameId

        // Capture main-actor state needed for the background send.
        let maxPayloadSize = maxUDPPayloadSize
        let shouldCacheForRetransmit = losslessVideoEnabled
        
        // Dispatch to avoid blocking the compression callback thread
        broadcastQueue.async { [weak self] in
            guard let self else { return }
            
            let totalLen = data.count
            let totalChunks = Int(ceil(Double(totalLen) / Double(maxPayloadSize)))
            
            // Safety check to avoid overflowing 2-byte index
            guard totalChunks <= UInt16.max else {
                NSLog("[AirCatchHost] Frame too large: \(totalLen) bytes")
                return
            }
            
            if frameId <= 3 || frameId % 60 == 0 {
                NSLog("[AirCatchHost] Broadcasting Frame \(frameId): \(totalLen) bytes, \(totalChunks) chunks")
            }
            
            // Fragment and send
            var chunksForCache: [Int: Data] = [:]
            if shouldCacheForRetransmit {
                chunksForCache.reserveCapacity(totalChunks)
            }
            for i in 0..<totalChunks {
                let start = i * maxPayloadSize
                let end = min(start + maxPayloadSize, totalLen)
                let chunkData = data.subdata(in: start..<end)
                
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
                
                // Send chunk via UDP
                NetworkManager.shared.broadcastUDP(type: .videoFrameChunk, payload: packet)

                if shouldCacheForRetransmit {
                    chunksForCache[i] = packet
                }
            }

            if shouldCacheForRetransmit {
                let chunksSnapshot = chunksForCache
                Task { @MainActor in
                    self.cacheFrameForRetransmit(frameId: frameId, totalChunks: totalChunks, chunksByIndex: chunksSnapshot)
                }
            }
        }
    }

    private func handleVideoChunkNack(_ payload: Data, from connection: NWConnection) {
        guard let request = try? JSONDecoder().decode(VideoChunkNackRequest.self, from: payload) else {
            return
        }

        guard losslessVideoEnabled else { return }

        let endpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        guard case .hostPort(let host, _) = endpoint else { return }
        let hostString = "\(host)"

        guard let udpEndpoint = NetworkManager.shared.udpEndpoint(forHostString: hostString) else {
            return
        }

        guard let cached = cachedFrames[request.frameId] else { return }

        let payloadsToResend: [Data] = request.missingChunkIndices.compactMap { idx in
            cached.chunksByIndex[Int(idx)]
        }

        broadcastQueue.async {
            for payload in payloadsToResend {
                NetworkManager.shared.sendUDP(to: udpEndpoint, type: .videoFrameChunk, payload: payload)
            }
        }
    }
    
    // MARK: - Notifications
    
    private func postStatusChange() {
        NotificationCenter.default.post(name: Self.statusDidChange, object: isStreaming)
    }
}

