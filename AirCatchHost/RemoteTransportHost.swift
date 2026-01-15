//
//  RemoteTransportHost.swift
//  AirCatchHost
//
//  Relay-based transport for Remote mode (Internet).
//

import Foundation

final class RemoteTransportHost {
    enum Channel: String, Codable {
        case tcp
        case udp
    }

    enum Role: String, Codable {
        case client
        case host
    }

    struct RemoteMessage: Codable {
        let type: String
        let sessionId: String
        let role: Role?
        let channel: Channel?
        let payload: String?
    }

    enum State {
        case idle
        case connecting
        case ready
        case failed(String)
    }

    private var webSocket: URLSessionWebSocketTask?
    private var sessionId: String = ""
    private var onTCPPacket: (@MainActor (Packet) -> Void)?
    private var onUDPPacket: (@MainActor (Packet) -> Void)?
    private var onStateChange: (@MainActor (State) -> Void)?
    
    // Flow Control
    private var pendingBytes: Int = 0
    private let maxPendingBytes = 1_000_000 // 1MB buffer limit (approx 2-3 frames)
    private let maxMessageSize = 500_000    // 500KB - Safety limit for single message
    
    // Thread safety for pendingBytes
    private let queue = DispatchQueue(label: "com.aircatch.remotehost.queue")

    func start(
        sessionId: String,
        relayURL: String = AirCatchConfig.remoteRelayURL,
        onTCPPacket: @MainActor @escaping (Packet) -> Void,
        onUDPPacket: @MainActor @escaping (Packet) -> Void,
        onStateChange: @MainActor @escaping (State) -> Void
    ) {
        self.sessionId = sessionId
        self.onTCPPacket = onTCPPacket
        self.onUDPPacket = onUDPPacket
        self.onStateChange = onStateChange

        guard let url = URL(string: relayURL) else {
            Task { @MainActor in
                onStateChange(.failed("Invalid relay URL"))
            }
            return
        }

        let request = URLRequest(url: url)
        let task = URLSession(configuration: .default).webSocketTask(with: request)
        webSocket = task
        task.resume()

        send(message: RemoteMessage(type: "register", sessionId: sessionId, role: .host, channel: nil, payload: nil))
        sendLocalCandidate()
        receiveLoop()

        Task { @MainActor in
            onStateChange(.ready)
        }
    }

    func stop() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        queue.sync { pendingBytes = 0 }
    }

    func updateSessionId(_ newSessionId: String) {
        guard newSessionId != sessionId else { return }
        sessionId = newSessionId
        send(message: RemoteMessage(type: "register", sessionId: newSessionId, role: .host, channel: nil, payload: nil))
    }

    func sendTCP(type: PacketType, payload: Data) {
        sendPacket(channel: .tcp, type: type, payload: payload)
    }

    func sendUDP(type: PacketType, payload: Data) {
        // UDP path handles video frames. Check flow control.
        if type == .videoFrame || type == .videoFrameChunk {
             let currentPending = queue.sync { pendingBytes }
             if currentPending > maxPendingBytes {
                 // Drop frame if backpressure is high
                 AirCatchLog.info("Dropping remote frame (backpressure: \(currentPending) bytes)", category: .network)
                 return
             }
        }
        sendPacket(channel: .udp, type: type, payload: payload)
    }

    private func sendPacket(channel: Channel, type: PacketType, payload: Data) {
        guard let webSocket else { return }
        
        // Safety check for message size
        if payload.count > maxMessageSize {
             AirCatchLog.error("Packet too large for remote transport: \(payload.count)", category: .network)
             return
        }

        // BINARY OPTIMIZATION:
        // For video data (high bandwidth), send directly as binary without JSON/Base64 overhead.
        // We add a 1-byte header for PacketType so the receiver knows what it is.
        // Format: [1 byte Type] [Payload...]
        
        if (type == .videoFrame || type == .videoFrameChunk) && channel == .udp {
             var binaryMsg = Data()
             binaryMsg.reserveCapacity(1 + payload.count)
             binaryMsg.append(type.rawValue)
             binaryMsg.append(payload)
             
             let msgSize = binaryMsg.count
             queue.sync { pendingBytes += msgSize }
             
             webSocket.send(.data(binaryMsg)) { [weak self] error in
                 guard let self else { return }
                 self.queue.sync { self.pendingBytes -= msgSize }
                 
                 if let error {
                     AirCatchLog.error("Remote binary send error: \(error)", category: .network)
                 }
             }
             return
        }

        // Fallback for control messages: JSON wrapped (legacy compatible for small messages)
        let datagram = buildDatagram(type: type, payload: payload)
        let encoded = datagram.base64EncodedString()
        let message = RemoteMessage(type: "relay", sessionId: sessionId, role: nil, channel: channel, payload: encoded)
        send(message: message)
    }

    private func send(message: RemoteMessage) {
        guard let webSocket else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        
        // Fix: Send JSON control messages as Text frames (.string)
        // The Relay Server expects JSON in text frames to parse them as control commands.
        // Binary frames are blindly relayed as video data.
        if let jsonString = String(data: data, encoding: .utf8) {
            queue.sync { pendingBytes += data.count }
            
            webSocket.send(.string(jsonString)) { [weak self] error in
                guard let self else { return }
                self.queue.sync { self.pendingBytes -= data.count }
                
                if let error {
                    AirCatchLog.error("Remote send error: \(error)", category: .network)
                }
            }
        }
    }

    private func receiveLoop() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    self.onStateChange?(.failed(error.localizedDescription))
                }
            case .success(let message):
                switch message {
                case .data(let data):
                    self.handleIncomingData(data)
                case .string(let text):
                    if let data = text.data(using: .utf8) {
                        self.handleIncomingJSON(data)
                    }
                @unknown default:
                    break
                }
            }
            // Continue loop if not stopped
            if self.webSocket != nil {
                self.receiveLoop()
            }
        }
    }
    
    // Handle binary frames (Direct video data)
    private func handleIncomingData(_ data: Data) {
         // Optimization: If it looks like JSON (starts with '{'), try parsing as JSON first.
         // Otherwise treat as binary packet.
         if let firstByte = data.first, firstByte == 0x7B { // '{' ASCII
             handleIncomingJSON(data)
             return
         }
         
         // Direct Binary Packet: [Type: 1 byte] [Payload...]
         guard data.count >= 1 else { return }
         guard let type = PacketType(rawValue: data[0]) else { return }
         
         let payload = data.dropFirst()
         let packet = Packet(type: type, payload: Data(payload))
         
         Task { @MainActor in
             // Assume UDP channel for binary video data
             self.onUDPPacket?(packet)
         }
    }

    private func handleIncomingJSON(_ data: Data) {
        guard let message = try? JSONDecoder().decode(RemoteMessage.self, from: data) else { return }
        
        if message.type == "relay", let channel = message.channel, let payload = message.payload,
           let packetData = Data(base64Encoded: payload),
           let packet = parseDatagram(packetData) {
            Task { @MainActor in
                switch channel {
                case .tcp:
                    self.onTCPPacket?(packet)
                case .udp:
                    self.onUDPPacket?(packet)
                }
            }
            return
        }

        if message.type == "candidate", let payload = message.payload {
            AirCatchLog.info("Remote candidate received: \(payload)", category: .network)
        }
    }

    private func sendLocalCandidate() {
        // STUN/Candidate logic - keeping as placeholder if you switch to webrtc later
        // Currently redundant for relay-only but harmless.
    }

    private func buildDatagram(type: PacketType, payload: Data) -> Data {
        var datagram = Data()
        datagram.reserveCapacity(1 + payload.count)
        datagram.append(type.rawValue)
        datagram.append(payload)
        return datagram
    }

    private func parseDatagram(_ data: Data) -> Packet? {
        guard let first = data.first, let type = PacketType(rawValue: first) else { return nil }
        let payload = data.dropFirst()
        return Packet(type: type, payload: Data(payload))
    }

}
