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
        NSLog("[AirCatchHost] New PIN generated: \(currentPIN)")
    }
    
    // MARK: - Network Components
    
    private let networkManager = NetworkManager.shared
    private let bonjourAdvertiser = BonjourAdvertiser()
    private let mpcHost = MPCAirCatchHost()
    
    // MARK: - Screen Capture
    
    private var screenStreamer: ScreenStreamer?
    private var currentFrameId: UInt32 = 0
    private let maxUDPPayloadSize = 1200 // Safe UDP payload size (below MTU)

    /// When false, prefer sending video over TCP (higher reliability).
    private var preferLowLatency: Bool = true

    /// When true, keep a short retransmit window for UDP video chunks (wired mode).
    private var losslessVideoEnabled: Bool = false

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
                    port: udpPort,
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
        NSLog("[AirCatchHost] Received UDP packet type: \(packet.type)")
        
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
        case .keyboardEvent:
            Task { @MainActor in
                self.handleKeyboardEvent(packet.payload)
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
        case .keyboardEvent:
            handleKeyboardEvent(packet.payload)
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
        self.configureTargetDisplay(extended: handshakeRequest?.extendedDisplay == true)
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
                bitrate: currentQuality.bitrate
            )

            if let data = try? JSONEncoder().encode(ack) {
                mpcHost.send(to: peer, type: .handshakeAck, payload: data, mode: .reliable)
            }
        }
    }
    
    private nonisolated func handleHandshake(payload: Data, from connection: NWConnection) {
        NSLog("[AirCatchHost] Handshake received from: \(connection.endpoint)")
        
        Task { @MainActor in
            // Decode the handshake request to extract PIN
            let handshakeRequest = try? JSONDecoder().decode(HandshakeRequest.self, from: payload)
            let receivedPIN = handshakeRequest?.pin ?? ""
            
            // Verify PIN
            if receivedPIN != currentPIN {
                NSLog("[AirCatchHost] PIN mismatch: expected \(currentPIN), got \(receivedPIN)")
                // Send pairing failed response
                networkManager.sendTCP(to: connection, type: .pairingFailed, payload: Data())
                return
            }
            
            NSLog("[AirCatchHost] PIN verified successfully for: \(connection.endpoint)")
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
            self.configureTargetDisplay(extended: handshakeRequest?.extendedDisplay == true)

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
                bitrate: currentQuality.bitrate
            )
            
            if let data = try? JSONEncoder().encode(ack) {
                networkManager.sendTCP(to: connection, type: .handshakeAck, payload: data)
            }
        }
    }
    
    private func handleTouchEvent(_ payload: Data) {
        guard let touch = try? JSONDecoder().decode(TouchEvent.self, from: payload) else {
            NSLog("[AirCatchHost] Failed to decode touch event")
            return
        }
        
        NSLog("[AirCatchHost] Received touch: type=\(touch.eventType) isTrackpad=\(touch.isTrackpad ?? false) deltaX=\(touch.deltaX ?? 0) deltaY=\(touch.deltaY ?? 0)")
        
        Task { @MainActor in
            // Handle trackpad events with delta-based movement (like a real Mac trackpad)
            if touch.isTrackpad == true {
                // Handle drag with delta movement
                if let deltaX = touch.deltaX, let deltaY = touch.deltaY, touch.eventType == .dragMoved {
                    NSLog("[AirCatchHost] Trackpad drag move: (\(deltaX), \(deltaY))")
                    InputInjector.shared.dragMouseRelative(deltaX: deltaX, deltaY: deltaY)
                    return
                }
                
                // Delta-based relative movement (pointer move, no button)
                if let deltaX = touch.deltaX, let deltaY = touch.deltaY, touch.eventType == .moved {
                    InputInjector.shared.moveMouseRelative(deltaX: deltaX, deltaY: deltaY)
                    return
                }
                
                NSLog("[AirCatchHost] Trackpad event: \(touch.eventType)")
                
                // Trackpad clicks use current mouse position
                switch touch.eventType {
                case .began:
                    // Mouse down at current position
                    InputInjector.shared.injectClickAtCurrentPosition(eventType: .began)
                case .ended:
                    // Mouse up at current position
                    InputInjector.shared.injectClickAtCurrentPosition(eventType: .ended)
                case .rightClick:
                    InputInjector.shared.injectClickAtCurrentPosition(eventType: .rightClick)
                case .doubleClick:
                    InputInjector.shared.injectClickAtCurrentPosition(eventType: .doubleClick)
                case .dragBegan:
                    // Start drag (mouse down, hold)
                    InputInjector.shared.injectClickAtCurrentPosition(eventType: .dragBegan)
                case .dragEnded:
                    // End drag (mouse up)
                    InputInjector.shared.injectClickAtCurrentPosition(eventType: .dragEnded)
                case .moved:
                    // Legacy absolute positioning fallback - always use current screen frame
                    let screenFrame = self.mainScreenFrame()
                    InputInjector.shared.moveMouse(xPercent: touch.normalizedX, yPercent: touch.normalizedY, in: screenFrame)
                default:
                    break
                }
            } else {
                // Non-trackpad (direct touch) uses absolute positioning - ALWAYS query current screen frame
                // This ensures resolution changes are picked up immediately
                let screenFrame = self.mainScreenFrame()
                InputInjector.shared.injectClick(
                    xPercent: touch.normalizedX,
                    yPercent: touch.normalizedY,
                    eventType: touch.eventType,
                    in: screenFrame
                )
            }
        }
    }
    
    private func mainScreenFrame() -> CGRect {
        return NSScreen.main?.frame ?? .zero
    }
    
    private func handleScrollEvent(_ payload: Data) {
        guard let scroll = try? JSONDecoder().decode(ScrollEvent.self, from: payload) else {
            NSLog("[AirCatchHost] Failed to decode scroll event")
            return
        }
        
        NSLog("[AirCatchHost] Received scroll event: deltaX=\(scroll.deltaX), deltaY=\(scroll.deltaY)")
        
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

    private func handleKeyboardEvent(_ payload: Data) {
        guard let evt = try? JSONDecoder().decode(KeyboardEvent.self, from: payload) else {
            NSLog("[AirCatchHost] Failed to decode keyboard event")
            return
        }

        if let text = evt.characters, !text.isEmpty {
            // Only type on keyDown to avoid doubling.
            if evt.isKeyDown {
                InputInjector.shared.typeText(text)
            }
            return
        }

        // Note: keyCode 0 is the 'A' key in macOS, so we must NOT filter it out!
        guard evt.isKeyDown else { return }
        InputInjector.shared.pressKey(
            virtualKey: CGKeyCode(evt.keyCode),
            shift: evt.modifiers.shift,
            control: evt.modifiers.control,
            option: evt.modifiers.option,
            command: evt.modifiers.command
        )
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
        
        NSLog("[AirCatchHost] Starting stream with preset: \(currentQuality.displayName)")
        screenStreamer = ScreenStreamer(
            preset: currentQuality,
            maxClientWidth: clientMaxWidth,
            maxClientHeight: clientMaxHeight,
            targetDisplayID: targetDisplayID
        ) { [weak self] compressedFrame in
            self?.broadcastVideoFrame(compressedFrame)
        } onAudio: { audioData in
            // Audio rides on TCP for reliability and ordering.
            NetworkManager.shared.broadcastTCP(type: .audioPCM, payload: audioData)

            // If a client is connected via MPC, send audio there too.
            // (Video is still primarily Network.framework; this just enables audio for input-only MPC sessions.)
            Task { @MainActor in
                self.mpcHost.broadcast(type: .audioPCM, payload: audioData, mode: .unreliable)
            }
        }
        
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
        postStatusChange()
        NSLog("[AirCatchHost] Screen streaming stopped")
    }

    // MARK: - Display Selection

    private func configureTargetDisplay(extended: Bool) {
        let mainID = CGMainDisplayID()

        let screenIDs: [CGDirectDisplayID] = NSScreen.screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let num = screen.deviceDescription[key] as? NSNumber else { return nil }
            return CGDirectDisplayID(num.uint32Value)
        }

        let chosenID: CGDirectDisplayID?
        if extended {
            chosenID = screenIDs.first(where: { $0 != mainID }) ?? mainID
        } else {
            chosenID = mainID
        }

        self.targetDisplayID = chosenID

        if let chosenID,
           let chosenScreen = NSScreen.screens.first(where: {
               let key = NSDeviceDescriptionKey("NSScreenNumber")
               guard let num = $0.deviceDescription[key] as? NSNumber else { return false }
               return CGDirectDisplayID(num.uint32Value) == chosenID
           }) {
            self.targetScreenFrame = chosenScreen.frame
        } else {
            self.targetScreenFrame = nil
        }

        if extended {
            NSLog("[AirCatchHost] Extended display requested. Using displayID=\(String(describing: chosenID)) frame=\(String(describing: targetScreenFrame))")
        } else {
            NSLog("[AirCatchHost] Using main display. displayID=\(String(describing: chosenID))")
        }
    }
    
    // Dedicated queue for video broadcasting to avoid blocking compression
    private let broadcastQueue = DispatchQueue(label: "com.aircatch.broadcast", qos: .userInteractive)

    private func pruneCachedFramesIfNeeded(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        guard losslessVideoEnabled, !cachedFrames.isEmpty else { return }

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
                
                packet.append(contentsOf: withUnsafeBytes(of: &fId) { Array($0) })
                packet.append(contentsOf: withUnsafeBytes(of: &idx) { Array($0) })
                packet.append(contentsOf: withUnsafeBytes(of: &total) { Array($0) })
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

