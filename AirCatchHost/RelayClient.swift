//
//  RelayClient.swift
//  AirCatchHost
//
//  WebSocket client for connecting to remote relay server.
//

import Foundation
import Network
import Combine

/// Handles WebSocket connection to remote relay server for AirCatchHost
final class RelayClient: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let delegateQueue = OperationQueue()
    
    @Published private(set) var isConnected = false
    @Published private(set) var roomCode: String = ""
    @Published private(set) var clientConnected = false
    
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
    /// - Parameters:
    ///   - serverURL: WebSocket URL (e.g., "ws://1.2.3.4:8080")
    ///   - roomCode: Room code for client to join (auto-generated if nil)
    func connect(to serverURL: String, roomCode: String? = nil) {
        guard let url = URL(string: serverURL) else {
            onError?("Invalid relay server URL")
            return
        }
        
        self.roomCode = roomCode ?? generateRoomCode()
        
        // Cancel existing connection
        disconnect()
        
        // Create WebSocket connection
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        AirCatchLog.info("🔗 Connecting to relay server: \(serverURL)")
    }
    
    /// Disconnect from relay server
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.clientConnected = false
        }
    }
    
    // MARK: - Data Transmission
    
    /// Send binary data to connected client through relay
    func send(data: Data) {
        guard isConnected else { return }
        
        webSocketTask?.send(.data(data)) { [weak self] error in
            if let error = error {
                AirCatchLog.error("Relay send error: \(error)")
                self?.handleDisconnect(error: error)
            }
        }
    }
    
    /// Send a packet (type + payload) through relay
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
        send(data: packet)
    }
    
    // MARK: - Private Methods
    
    private func generateRoomCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Excluded confusing chars: I, O, 0, 1
        return String((0..<6).map { _ in characters.randomElement()! })
    }
    
    private func registerAsHost() {
        let registration: [String: Any] = [
            "type": "register",
            "role": "host",
            "roomCode": roomCode
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: registration),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            onError?("Failed to create registration message")
            return
        }
        
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                AirCatchLog.error("Registration send error: \(error)")
                self?.onError?("Failed to register with relay server")
            }
        }
        
        AirCatchLog.info("📤 Sent host registration for room: \(roomCode)")
    }
    
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving
                self.receiveMessages()
                
            case .failure(let error):
                AirCatchLog.error("WebSocket receive error: \(error)")
                self.handleDisconnect(error: error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            // JSON control message from server
            handleControlMessage(text)
            
        case .data(let data):
            // Binary data from client (input events, etc.)
            onDataReceived?(data)
            
        @unknown default:
            break
        }
    }
    
    private func handleControlMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "registered":
            let peerConnected = json["peerConnected"] as? Bool ?? false
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = true
                self?.clientConnected = peerConnected
            }
            AirCatchLog.info("✅ Registered as host in room \(roomCode), client connected: \(peerConnected)")
            DispatchQueue.main.async { [weak self] in
                self?.onConnected?()
                if peerConnected {
                    self?.onClientConnected?()
                }
            }
            
        case "peer_connected":
            DispatchQueue.main.async { [weak self] in
                self?.clientConnected = true
            }
            AirCatchLog.info("📱 Client connected to relay")
            DispatchQueue.main.async { [weak self] in
                self?.onClientConnected?()
            }
            
        case "peer_disconnected":
            DispatchQueue.main.async { [weak self] in
                self?.clientConnected = false
            }
            AirCatchLog.info("📴 Client disconnected from relay")
            DispatchQueue.main.async { [weak self] in
                self?.onClientDisconnected?()
            }
            
        case "error":
            let errorMessage = json["message"] as? String ?? "Unknown error"
            AirCatchLog.error("Relay error: \(errorMessage)")
            DispatchQueue.main.async { [weak self] in
                self?.onError?(errorMessage)
            }
            
        default:
            break
        }
    }
    
    private func handleDisconnect(error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.clientConnected = false
        }
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnected?(error)
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension RelayClient: URLSessionWebSocketDelegate {
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, 
                    didOpenWithProtocol protocol: String?) {
        AirCatchLog.info("🔌 WebSocket connected to relay server")
        registerAsHost()
        receiveMessages()
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, 
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
        AirCatchLog.info("WebSocket closed: \(closeCode), reason: \(reasonString)")
        handleDisconnect(error: nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, 
                    didCompleteWithError error: Error?) {
        if let error = error {
            AirCatchLog.error("WebSocket task error: \(error)")
            handleDisconnect(error: error)
        }
    }
}
