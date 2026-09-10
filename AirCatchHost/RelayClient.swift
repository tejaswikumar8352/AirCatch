//
//  RelayClient.swift
//  AirCatchHost
//
//  WebSocket client for connecting to remote relay server.
//  Supports dual-channel mode: separate sockets for video and control/audio
//  to prevent head-of-line blocking.
//

import Foundation
import Network
import Combine
import CryptoKit
import Security

/// Handles WebSocket connection to remote relay server for AirCatchHost
final class RelayClient: NSObject {
    private static let insecureRelayWSUserDefaultsKey = "allowInsecureRelayWS"
    private static let insecureRelayWSEnvKey = "AIRCATCH_ALLOW_INSECURE_RELAY_WS"
    private static let insecureRelayWSQueryKey = "allowInsecureWs"
    private static let disableTLSPinningUserDefaultsKey = "disableRelayTLSPinning"
    private static let disableTLSPinningEnvKey = "AIRCATCH_DISABLE_RELAY_TLS_PINNING"
    private static let pinnedSPKIUserDefaultsKey = "relayPinnedSPKIByHost"
    private static let defaultPinnedSPKIByHost: [String: Set<String>] = [
        // relay.qai88.com current public key pin (base64 SHA-256 of SecKey external representation)
        "relay.qai88.com": ["1+GESKm46Vf+tOAl5Ny3A1NbS9B5Q7jxy7NXhqoDbDA="],
    ]
    
    // MARK: - Properties
    
    // Dual-channel WebSocket connections
    private var videoSocketTask: URLSessionWebSocketTask?
    private var controlSocketTask: URLSessionWebSocketTask?
    // PERFORMANCE: Separate URLSessions per channel to avoid head-of-line blocking.
    // A shared serial delegateQueue causes video callbacks to delay control callbacks,
    // producing progressive lag over minutes of streaming.
    private var videoURLSession: URLSession!
    private var controlURLSession: URLSession!
    private let videoDelegateQueue = OperationQueue()
    private let controlDelegateQueue = OperationQueue()
    private let connectionLock = NSLock()
    private var _isConnectedAtomic = false
    private var serverURL: URL?
    
    // PERFORMANCE: Backpressure cap for video sends
    // Limits outstanding video send operations to prevent unbounded memory growth
    private let maxOutstandingVideoSends = 3
    private var outstandingVideoSends = 0
    private let videoSendLock = NSLock()
    
    // PERFORMANCE: Time-based send gating for prolonged backpressure.
    // If backpressure has been saturated for > 1s, drop aggressively until it recovers.
    private var backpressureSaturatedSince: TimeInterval = 0
    
    // Track which channels are connected
    private var videoConnected = false
    private var controlConnected = false
    
    private(set) var isConnected = false {
        didSet {
            connectionLock.lock()
            _isConnectedAtomic = isConnected
            connectionLock.unlock()
        }
    }
    private(set) var roomCode: String = ""
    private(set) var clientConnected = false
    
    /// Thread-safe check for connection status (can be called from any queue)
    var isConnectedThreadSafe: Bool {
        connectionLock.lock()
        let result = _isConnectedAtomic
        connectionLock.unlock()
        return result
    }
    
    // Callbacks
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?
    var onClientConnected: (() -> Void)?
    var onClientDisconnected: (() -> Void)?
    var onDataReceived: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        // PERFORMANCE: Each channel gets its own serial queue so video frame
        // processing never blocks control message handling.
        videoDelegateQueue.maxConcurrentOperationCount = 1
        videoDelegateQueue.qualityOfService = .userInitiated
        controlDelegateQueue.maxConcurrentOperationCount = 1
        controlDelegateQueue.qualityOfService = .userInteractive  // Control is highest priority
        videoURLSession = URLSession(configuration: .default, delegate: self, delegateQueue: videoDelegateQueue)
        controlURLSession = URLSession(configuration: .default, delegate: self, delegateQueue: controlDelegateQueue)
    }
    
    // MARK: - Connection
    
    /// Connect to relay server and register as host
    /// Uses single combined socket for compatibility with older servers
    /// - Parameters:
    ///   - serverURL: WebSocket URL (e.g., "ws://1.2.3.4:8080")
    ///   - roomCode: Room code for client to join (auto-generated if nil)
    func connect(to serverURL: String, roomCode: String? = nil) {
        guard let url = URL(string: serverURL) else {
            dispatchToMain { [weak self] in
                self?.onError?("Invalid relay server URL")
            }
            return
        }

        guard isRelayURLAllowed(url) else {
            let message = relayURLValidationErrorMessage()
            dispatchToMain { [weak self] in
                self?.onError?(message)
            }
            return
        }
        
        self.serverURL = url
        self.roomCode = roomCode ?? generateRoomCode()
        
        // Cancel existing connections
        disconnect()
        
        // PERFORMANCE: Dual-channel mode - separate sockets for video and control
        // Prevents head-of-line blocking where large video frames delay touch/input events
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        // PERFORMANCE: Use separate URLSessions so each channel has its own delegate queue.
        controlSocketTask = controlURLSession.webSocketTask(with: request)
        videoSocketTask = videoURLSession.webSocketTask(with: request)
        
        controlSocketTask?.resume()
        videoSocketTask?.resume()
        
        AirCatchLog.info("🔗 Connecting to relay server (dual-channel): \(serverURL)")
    }
    
    /// Disconnect from relay server
    func disconnect() {
        videoSocketTask?.cancel(with: .goingAway, reason: nil)
        controlSocketTask?.cancel(with: .goingAway, reason: nil)
        videoSocketTask = nil
        controlSocketTask = nil
        videoConnected = false
        controlConnected = false
        dispatchToMain { [weak self] in
            self?.isConnected = false
            self?.clientConnected = false
        }
    }
    
    // MARK: - Data Transmission
    
    /// Send video data through video channel (high-bandwidth, can drop under backpressure)
    func sendVideo(data: Data) {
        guard isConnectedThreadSafe else { return }
        
        // PERFORMANCE: Drop video frames if too many sends are outstanding
        // Prevents unbounded memory growth when network is slow
        videoSendLock.lock()
        let outstanding = outstandingVideoSends
        guard outstanding < maxOutstandingVideoSends else {
            // PERFORMANCE: Track how long backpressure has been saturated.
            // If saturated for > 1s, the connection is too slow — caller should
            // consider reducing bitrate/framerate.
            if backpressureSaturatedSince == 0 {
                backpressureSaturatedSince = Date().timeIntervalSinceReferenceDate
            }
            videoSendLock.unlock()
            return  // Drop frame - newer ones will arrive soon
        }
        outstandingVideoSends += 1
        backpressureSaturatedSince = 0  // Reset — we have capacity
        videoSendLock.unlock()
        
        videoSocketTask?.send(.data(data)) { [weak self] error in
            guard let self else { return }
            self.videoSendLock.lock()
            self.outstandingVideoSends = max(0, self.outstandingVideoSends - 1)
            self.videoSendLock.unlock()
            if let error = error {
                AirCatchLog.error("Relay video send error: \(error)")
            }
        }
    }
    
    /// Returns how long (seconds) the video send queue has been continuously saturated.
    /// HostManager can use this to proactively reduce bitrate when relay is slow.
    var backpressureDuration: TimeInterval {
        videoSendLock.lock()
        let since = backpressureSaturatedSince
        videoSendLock.unlock()
        guard since > 0 else { return 0 }
        return Date().timeIntervalSinceReferenceDate - since
    }
    
    /// Send control/audio data through control channel (low-latency, never dropped)
    func sendControl(data: Data) {
        guard isConnectedThreadSafe else { return }
        
        controlSocketTask?.send(.data(data)) { error in
            if let error = error {
                AirCatchLog.error("Relay control send error: \(error)")
            }
        }
    }
    
    /// Send binary data - legacy method, routes to control channel
    func send(data: Data) {
        sendControl(data: data)
    }
    
    /// Send a packet (type + payload) - routes to appropriate channel based on type
    func send(type: PacketType, payload: Data) {
        var packet = Data()
        packet.append(type.rawValue)
        
        // 4-byte big-endian length
        let length = UInt32(payload.count)
        packet.append(UInt8((length >> 24) & 0xFF))
        packet.append(UInt8((length >> 16) & 0xFF))
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        
        packet.append(payload)
        
        // Route based on packet type
        // PERFORMANCE: Audio goes through video channel to avoid flooding
        // the control channel and blocking touch/keyboard events.
        switch type {
        case .videoFrame, .videoFrameChunk, .audioPCM:
            sendVideo(data: packet)
        default:
            sendControl(data: packet)
        }
    }
    
    // MARK: - Private Methods

    private func dispatchToMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
    
    private func generateRoomCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Excluded confusing chars: I, O, 0, 1
        return String((0..<6).map { _ in characters.randomElement()! })
    }

    private func isRelayURLAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "wss" { return true }
        guard scheme == "ws" else { return false }

        let host = (url.host ?? "").lowercased()
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }

        if insecureRelayWSAllowedForTesting(url: url) {
            AirCatchLog.info("Allowing insecure ws:// relay URL for testing (DEBUG override).")
            return true
        }

        return false
    }

    private func relayURLValidationErrorMessage() -> String {
        #if DEBUG
        return "Relay URL must use wss:// (ws:// is allowed only for localhost). For testing use '?allowInsecureWs=1' or set UserDefaults '\(Self.insecureRelayWSUserDefaultsKey)' to true."
        #else
        return "Relay URL must use wss:// (ws:// is allowed only for localhost). For testing use '?allowInsecureWs=1'."
        #endif
    }

    private func insecureRelayWSAllowedForTesting(url: URL) -> Bool {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems,
           items.contains(where: { $0.name.caseInsensitiveCompare(Self.insecureRelayWSQueryKey) == .orderedSame && ($0.value ?? "1") != "0" }) {
            return true
        }

        if let raw = ProcessInfo.processInfo.environment[Self.insecureRelayWSEnvKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !raw.isEmpty {
            if raw == "1" || raw == "true" || raw == "yes" || raw == "on" {
                return true
            }
        }

        if UserDefaults.standard.bool(forKey: Self.insecureRelayWSUserDefaultsKey) {
            return true
        }

        #if DEBUG
        // Debug builds default to allowing non-local ws:// for fast LAN/WAN testing.
        return true
        #else
        return false
        #endif
    }
    
    private static func parseBoolFlag(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes" || value == "on"
    }
    
    private func isTLSPinningDisabled() -> Bool {
        if UserDefaults.standard.bool(forKey: Self.disableTLSPinningUserDefaultsKey) {
            return true
        }
        if let envRaw = ProcessInfo.processInfo.environment[Self.disableTLSPinningEnvKey],
           Self.parseBoolFlag(envRaw) {
            return true
        }
        return false
    }
    
    private func expectedPinnedSPKI(for host: String) -> Set<String>? {
        guard !isTLSPinningDisabled() else { return nil }
        let normalized = host.lowercased()
        
        if let custom = UserDefaults.standard.dictionary(forKey: Self.pinnedSPKIUserDefaultsKey) as? [String: [String]],
           let pins = custom[normalized], !pins.isEmpty {
            return Set(pins)
        }
        
        return Self.defaultPinnedSPKIByHost[normalized]
    }
    
    private static func spkiHashBase64(from trust: SecTrust) -> String? {
        guard let key = SecTrustCopyKey(trust) else { return nil }
        
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(key, &error) as Data? else { return nil }
        
        let digest = SHA256.hash(data: keyData)
        return Data(digest).base64EncodedString()
    }
    
    private func registerAsHost(task: URLSessionWebSocketTask, channel: String) {
        // Only include channel if using dual-channel mode (separate sockets)
        var registration: [String: Any] = [
            "type": "register",
            "role": "host",
            "roomCode": roomCode
        ]
        
        // For backward compatibility, only include channel if not combined mode
        if channel != "combined" && videoSocketTask !== controlSocketTask {
            registration["channel"] = channel
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: registration),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            dispatchToMain { [weak self] in
                self?.onError?("Failed to create registration message")
            }
            return
        }
        
        task.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                AirCatchLog.error("Registration send error (\(channel)): \(error)")
                self?.dispatchToMain {
                    self?.onError?("Failed to register with relay server")
                }
            }
        }
        
        AirCatchLog.info("📤 Sent host registration for room: \(roomCode)")
    }
    
    private func receiveMessages(from task: URLSessionWebSocketTask, channel: String) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message, channel: channel)
                // Continue receiving
                self.receiveMessages(from: task, channel: channel)
                
            case .failure(let error):
                AirCatchLog.error("WebSocket receive error (\(channel)): \(error)")
                self.handleDisconnect(error: error, channel: channel)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message, channel: String) {
        switch message {
        case .string(let text):
            // JSON control message from server
            handleControlMessage(text, channel: channel)
            
        case .data(let data):
            // Binary data from client (input events, handshake)
            // In combined mode or control channel, forward to callback
            if channel == "control" || channel == "combined" {
                onDataReceived?(data)
            }
            
        @unknown default:
            break
        }
    }
    
    private func handleControlMessage(_ text: String, channel: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "registered":
            let peerConnected = json["peerConnected"] as? Bool ?? false
            let registeredChannel = json["channel"] as? String ?? "combined"
            let isCombinedMode = videoSocketTask === controlSocketTask
            
            // Track which channels are connected
            if isCombinedMode || registeredChannel == "combined" {
                videoConnected = true
                controlConnected = true
            } else if registeredChannel == "video" {
                videoConnected = true
            } else if registeredChannel == "control" {
                controlConnected = true
            }
            
            AirCatchLog.info("✅ Registered as host in room \(roomCode), peer: \(peerConnected)")
            
            // Fire callbacks when both channels are connected (or combined mode)
            if videoConnected && controlConnected {
                dispatchToMain { [weak self] in
                    self?.isConnected = true
                    self?.clientConnected = peerConnected
                    self?.onConnected?()
                    if peerConnected {
                        self?.onClientConnected?()
                    }
                }
            }
            
        case "peer_connected":
            // Client connected - wait for both channels before notifying
            let peerChannel = json["channel"] as? String ?? "combined"
            AirCatchLog.info("📱 Client connected (\(peerChannel))")
            
            // Fire callback on control channel connection (triggers once)
            if peerChannel == "control" || peerChannel == "combined" {
                dispatchToMain { [weak self] in
                    self?.clientConnected = true
                    self?.onClientConnected?()
                }
            }
            
        case "peer_disconnected":
            let peerChannel = json["channel"] as? String ?? "combined"
            AirCatchLog.info("📴 Client disconnected (\(peerChannel))")
            
            // Fire disconnect on control channel (more important)
            if peerChannel == "control" || peerChannel == "combined" {
                dispatchToMain { [weak self] in
                    self?.clientConnected = false
                    self?.onClientDisconnected?()
                }
            }
            
        case "error":
            let errorMessage = json["message"] as? String ?? "Unknown error"
            AirCatchLog.error("Relay error (\(channel)): \(errorMessage)")
            dispatchToMain { [weak self] in
                self?.onError?(errorMessage)
            }
            
        default:
            break
        }
    }
    
    private func handleDisconnect(error: Error?, channel: String = "combined") {
        // Track which channel disconnected
        if channel == "video" {
            videoConnected = false
        } else if channel == "control" {
            controlConnected = false
        } else {
            videoConnected = false
            controlConnected = false
        }
        
        // If both channels are disconnected, notify
        if !videoConnected && !controlConnected {
            dispatchToMain { [weak self] in
                self?.isConnected = false
                self?.clientConnected = false
                self?.onDisconnected?(error)
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RelayClient: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let host = challenge.protectionSpace.host.lowercased()
        guard let expectedPins = expectedPinnedSPKI(for: host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        var trustError: CFError?
        guard SecTrustEvaluateWithError(trust, &trustError) else {
            AirCatchLog.error("TLS trust evaluation failed for \(host)")
            dispatchToMain { [weak self] in
                self?.onError?("Relay TLS trust validation failed")
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        guard let actualPin = Self.spkiHashBase64(from: trust) else {
            AirCatchLog.error("TLS pinning failed: unable to extract server key for \(host)")
            dispatchToMain { [weak self] in
                self?.onError?("Relay TLS pin validation failed")
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        guard expectedPins.contains(actualPin) else {
            AirCatchLog.error("TLS pin mismatch for \(host)")
            dispatchToMain { [weak self] in
                self?.onError?("Relay TLS pin mismatch")
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, 
                    didOpenWithProtocol protocol: String?) {
        // Determine channel - combined mode if both sockets are the same
        let isCombinedMode = videoSocketTask === controlSocketTask
        let channel: String
        
        if isCombinedMode {
            channel = "combined"
            videoConnected = true
            controlConnected = true
        } else if webSocketTask === videoSocketTask {
            channel = "video"
        } else {
            channel = "control"
        }
        
        AirCatchLog.info("🔌 WebSocket connected (\(channel) channel)")
        registerAsHost(task: webSocketTask, channel: channel)
        receiveMessages(from: webSocketTask, channel: channel)
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, 
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let isCombinedMode = videoSocketTask === controlSocketTask
        let channel = isCombinedMode ? "combined" : (webSocketTask === videoSocketTask ? "video" : "control")
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
        AirCatchLog.info("WebSocket closed (\(channel)): \(closeCode), reason: \(reasonString)")
        handleDisconnect(error: nil, channel: channel)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, 
                    didCompleteWithError error: Error?) {
        if let error = error {
            let isCombinedMode = videoSocketTask === controlSocketTask
            let channel = isCombinedMode ? "combined" : ((task as? URLSessionWebSocketTask) === videoSocketTask ? "video" : "control")
            AirCatchLog.error("WebSocket task error (\(channel)): \(error)")
            handleDisconnect(error: error, channel: channel)
        }
    }
}
