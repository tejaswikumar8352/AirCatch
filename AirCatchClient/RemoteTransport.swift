//
//  RemoteTransport.swift
//  AirCatchClient
//
//  Relay-based transport for Remote mode (Internet).
//

import Foundation
import Network

final class RemoteTransport {
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
    private var state: State = .idle
    private var onTCPPacket: (@MainActor (Packet) -> Void)?
    private var onUDPPacket: (@MainActor (Packet) -> Void)?
    private var onStateChange: (@MainActor (State) -> Void)?

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

        state = .connecting
        Task { @MainActor in
            onStateChange(.connecting)
        }

        let request = URLRequest(url: url)
        let task = URLSession(configuration: .default).webSocketTask(with: request)
        webSocket = task
        task.resume()

        send(message: RemoteMessage(type: "register", sessionId: sessionId, role: .client, channel: nil, payload: nil))
        sendLocalCandidate()
        receiveLoop()

        state = .ready
        Task { @MainActor in
            onStateChange(.ready)
        }
    }

    func stop() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        state = .idle
    }

    func sendTCP(type: PacketType, payload: Data) {
        sendPacket(channel: .tcp, type: type, payload: payload)
    }

    func sendUDP(type: PacketType, payload: Data) {
        sendPacket(channel: .udp, type: type, payload: payload)
    }

    private func sendPacket(channel: Channel, type: PacketType, payload: Data) {
        let datagram = buildDatagram(type: type, payload: payload)
        let encoded = datagram.base64EncodedString()
        let message = RemoteMessage(type: "relay", sessionId: sessionId, role: nil, channel: channel, payload: encoded)
        send(message: message)
    }

    private func send(message: RemoteMessage) {
        guard let webSocket else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        
        // Fix: Send JSON control messages as Text frames (.string)
        if let jsonString = String(data: data, encoding: .utf8) {
            webSocket.send(.string(jsonString)) { error in
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
            if self.webSocket != nil {
                self.receiveLoop()
            }
        }
    }
    
    // Handle binary frames (Direct video data)
    private func handleIncomingData(_ data: Data) {
         // Optimization: If it looks like JSON (starts with '{'), try parsing as JSON first.
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
             // Assume UDP channel for binary video data from Host
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
         // Placeholder
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
