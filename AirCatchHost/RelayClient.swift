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

/// Handles WebSocket connection to remote relay server for AirCatchHost
final class RelayClient: NSObject {
    private static let insecureRelayWSUserDefaultsKey = "allowInsecureRelayWS"
    private static let insecureRelayWSEnvKey = "AIRCATCH_ALLOW_INSECURE_RELAY_WS"
    private static let insecureRelayWSQueryKey = "allowInsecureWs"
    
    // MARK: - Properties
    
    // Dual-channel WebSocket connections
    private var videoSocketTask: URLSessionWebSocketTask?
    private var controlSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let delegateQueue = OperationQueue()
    private let connectionLock = NSLock()
    private var _isConnectedAtomic = false
    private var serverURL: URL?
    
    // PERFORMANCE: Backpressure cap for video sends
    // Limits outstanding video send operations to prevent unbounded memory growth
    private let maxOutstandingVideoSends = 3
    private var outstandingVideoSends = 0
    private let videoSendLock = NSLock()
    
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
        delegateQueue.maxConcurrentOperationCount = 1
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
    }
    
    // MARK: - Connection
    
    /// Connect to relay server and register as host
    /// Uses single combined socket for compatibility with older servers
    /// - Parameters:
    ///   - serverURL: WebSocket URL (e.g., "ws://1.2.3.4:8080")
    ///   - roomCode: Room code for client to join (auto-generated if nil)
    func connect(to serverURL: String, roomCode: String? = nil) {
        guard let url = URL(string: serverURL) else {
            onError?("Invalid relay server URL")
            return
        }

        guard isRelayURLAllowed(url) else {
            onError?(relayURLValidationErrorMessage())
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
        
        controlSocketTask = urlSession.webSocketTask(with: request)
        videoSocketTask = urlSession.webSocketTask(with: request)  // Separate socket for video
        
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
        DispatchQueue.main.async { [weak self] in
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
        guard outstandingVideoSends < maxOutstandingVideoSends else {
            videoSendLock.unlock()
            return  // Drop frame - newer ones will arrive soon
        }
        outstandingVideoSends += 1
        videoSendLock.unlock()
        
        videoSocketTask?.send(.data(data)) { [weak self] error in
            guard let self else { return }
            self.videoSendLock.lock()
            self.outstandingVideoSends -= 1
            self.videoSendLock.unlock()
            if let error = error {
                AirCatchLog.error("Relay video send error: \(error)")
            }
        }
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
        switch type {
        case .videoFrame, .videoFrameChunk:
            sendVideo(data: packet)
        default:
            sendControl(data: packet)
        }
    }
    
    // MARK: - Private Methods
    
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
            onError?("Failed to create registration message")
            return
        }
        
        task.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                AirCatchLog.error("Registration send error (\(channel)): \(error)")
                self?.onError?("Failed to register with relay server")
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
                DispatchQueue.main.async { [weak self] in
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
                DispatchQueue.main.async { [weak self] in
                    self?.clientConnected = true
                    self?.onClientConnected?()
                }
            }
            
        case "peer_disconnected":
            let peerChannel = json["channel"] as? String ?? "combined"
            AirCatchLog.info("📴 Client disconnected (\(peerChannel))")
            
            // Fire disconnect on control channel (more important)
            if peerChannel == "control" || peerChannel == "combined" {
                DispatchQueue.main.async { [weak self] in
                    self?.clientConnected = false
                    self?.onClientDisconnected?()
                }
            }
            
        case "error":
            let errorMessage = json["message"] as? String ?? "Unknown error"
            AirCatchLog.error("Relay error (\(channel)): \(errorMessage)")
            DispatchQueue.main.async { [weak self] in
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
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.clientConnected = false
                self?.onDisconnected?(error)
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RelayClient: URLSessionWebSocketDelegate {
    
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
