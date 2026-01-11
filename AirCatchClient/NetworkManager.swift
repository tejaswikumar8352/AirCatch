//
//  NetworkManager.swift
//  AirCatchClient
//
//  Networking helper for client side.
//

import Foundation
import Network

final class NetworkManager {
    static let shared = NetworkManager()

    private let queue = DispatchQueue(label: "com.aircatch.network", qos: .userInitiated)
    
    // MARK: - UDP Components
    private var udpClientConnection: NWConnection?
    private var udpReceiveHandler: (@MainActor (Packet, NWEndpoint?) -> Void)?
    
    // MARK: - TCP Components
    private var tcpClientConnection: NWConnection?
    private var tcpReceiveHandler: (@MainActor (Packet, NWConnection) -> Void)?

    private init() {}

    /// Connects to a UDP endpoint for the client side.
    func connectUDP(
        to host: String,
        port: UInt16,
        includePeerToPeer: Bool = true,
        requiredInterfaceType: NWInterface.InterfaceType? = nil,
        onPacket: @MainActor @escaping (Packet, NWEndpoint?) -> Void
    ) {
        udpReceiveHandler = onPacket

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AirCatchLog.error("Invalid UDP port \(port)")
            return
        }

        let parameters = NWParameters.udp
        parameters.includePeerToPeer = includePeerToPeer
        if let requiredInterfaceType {
            parameters.requiredInterfaceType = requiredInterfaceType
        }
        parameters.serviceClass = .interactiveVideo

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        connection.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .failed(let error):
                AirCatchLog.error("UDP connection failed: \(error)")
            case .cancelled:
                break
            default:
                break
            }
        }

        prepareUDPConnection(connection)
        connection.start(queue: queue)
        udpClientConnection = connection
    }

    /// Sends a UDP packet on the active client connection.
    func sendUDP(type: PacketType, payload: Data) {
        guard let connection = udpClientConnection else {
            AirCatchLog.error("UDP send skipped: no active connection")
            return
        }
        let datagram = buildDatagram(type: type, payload: payload)
        connection.send(content: datagram, completion: NWConnection.SendCompletion.contentProcessed({ error in
            if let error {
                AirCatchLog.error("UDP send error: \(error)")
            }
        }))
    }
    
    // MARK: - TCP Client Methods
    
    /// Connects to a TCP endpoint for reliable messaging.
    func connectTCP(
        to host: String,
        port: UInt16,
        includePeerToPeer: Bool = true,
        requiredInterfaceType: NWInterface.InterfaceType? = nil,
        onConnected: ((NWConnection) -> Void)? = nil,
        onPacket: @MainActor @escaping (Packet, NWConnection) -> Void
    ) {
        tcpReceiveHandler = onPacket
        
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            AirCatchLog.error("Invalid TCP port \(port)")
            return
        }
        
        // P2P Enabled Parameters with Low Latency
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = includePeerToPeer
        if let requiredInterfaceType {
            parameters.requiredInterfaceType = requiredInterfaceType
        }
        
        // Optimize for interactive video streaming
        parameters.serviceClass = .interactiveVideo
        
        if let tcpOption = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOption.enableKeepalive = true
            tcpOption.keepaliveIdle = 2
            tcpOption.noDelay = true // Disable Nagle's algorithm for instant sending
        } else {
            AirCatchLog.error(" ⚠️ TCP options unavailable; using defaults")
        }
        
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            switch state {
            case .ready:
                AirCatchLog.error("TCP connected to \(host):\(port)")
                self?.tcpClientConnection = connection
                onConnected?(connection)
            case .failed(let error):
                AirCatchLog.error("TCP connection failed: \(error)")
            case .cancelled:
                break
            default:
                break
            }
        }
        
        prepareTCPConnection(connection)
        connection.start(queue: queue)
    }
    
    /// Sends a TCP packet on the active client connection.
    func sendTCP(type: PacketType, payload: Data) {
        guard let connection = tcpClientConnection else {
            AirCatchLog.error("TCP send skipped: no active connection")
            return
        }
        let packet = buildTCPPacket(type: type, payload: payload)
        connection.send(content: packet, completion: NWConnection.SendCompletion.contentProcessed({ error in
            if let error {
                AirCatchLog.error("TCP send error: \(error)")
            }
        }))
    }

    /// Tears down all UDP resources.
    func stopUDP() {
        udpClientConnection?.cancel()
        udpClientConnection = nil
        udpReceiveHandler = nil
    }
    
    /// Tears down all TCP resources.
    func stopTCP() {
        tcpClientConnection?.cancel()
        tcpClientConnection = nil
        tcpReceiveHandler = nil
    }
    
    /// Tears down all network resources.
    func stopAll() {
        stopUDP()
        stopTCP()
    }

    private func prepareUDPConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .failed(let error):
                AirCatchLog.error("UDP connection failed: \(error)")
            case .cancelled:
                break
            default:
                break
            }
        }
        receiveLoop(on: connection)
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                AirCatchLog.error("UDP receive error: \(error)")
            }

            if let data, let packet = self.parsePacket(from: data) {
                let handler = self.udpReceiveHandler
                Task { @MainActor in
                    handler?(packet, connection.endpoint)
                }
            }

            switch connection.state {
            case .cancelled, .failed:
                return
            default:
                self.receiveLoop(on: connection)
            }
        }
    }
    
    // MARK: - TCP Connection Setup
    
    private func prepareTCPConnection(_ connection: NWConnection) {
        tcpReceiveLoop(on: connection)
        // Note: connection.start() is called in connectTCP() after this function
    }
    
    private func tcpReceiveLoop(on connection: NWConnection) {
        // First read the header (1 byte type + 4 bytes length)
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            
            if let error {
                AirCatchLog.error("TCP receive error: \(error)")
                return
            }
            
            if isComplete {
                // Connection closed
                let handler = self.tcpReceiveHandler
                Task { @MainActor in
                    handler?(Packet(type: .disconnect, payload: Data()), connection)
                }
                return
            }
            
            guard let data, data.count == 5 else {
                if connection.state == .ready {
                    self.tcpReceiveLoop(on: connection)
                }
                return
            }
            
            guard let type = PacketType(rawValue: data[0]) else {
                self.tcpReceiveLoop(on: connection)
                return
            }
            
            // Parse payload length (big endian)
            let length = Int(data[1]) << 24 | Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
            
            if length == 0 {
                let handler = self.tcpReceiveHandler
                Task { @MainActor in
                    handler?(Packet(type: type, payload: Data()), connection)
                }
                self.tcpReceiveLoop(on: connection)
                return
            }
            
            // Read the payload
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] payloadData, _, _, error in
                guard let self else { return }
                
                if let error {
                    AirCatchLog.error("TCP payload receive error: \(error)")
                }
                
                if let payloadData {
                    let handler = self.tcpReceiveHandler
                    let packet = Packet(type: type, payload: payloadData)
                    Task { @MainActor in
                        handler?(packet, connection)
                    }
                }
                
                if connection.state == .ready {
                    self.tcpReceiveLoop(on: connection)
                }
            }
        }
    }

    private func parsePacket(from data: Data) -> Packet? {
        guard let first = data.first, let type = PacketType(rawValue: first) else { return nil }
        let payload = data.dropFirst()
        return Packet(type: type, payload: Data(payload))
    }

    private func buildDatagram(type: PacketType, payload: Data) -> Data {
        var datagram = Data()
        datagram.reserveCapacity(1 + payload.count)
        datagram.append(type.rawValue)
        datagram.append(payload)
        return datagram
    }
    
    /// Builds a TCP packet with length-prefixed format: [type:1][length:4][payload:N]
    private func buildTCPPacket(type: PacketType, payload: Data) -> Data {
        var packet = Data()
        packet.reserveCapacity(5 + payload.count)
        packet.append(type.rawValue)
        
        // Length as 4 bytes big endian
        let length = UInt32(payload.count)
        packet.append(UInt8((length >> 24) & 0xFF))
        packet.append(UInt8((length >> 16) & 0xFF))
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        
        packet.append(payload)
        return packet
    }
}
