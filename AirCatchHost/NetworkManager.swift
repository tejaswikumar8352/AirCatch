//
//  NetworkManager.swift
//  AirCatchHost
//
//  Shared networking helper for host side.
//

import Foundation
import Network

final class NetworkManager {
    static let shared = NetworkManager()

    private let queue = DispatchQueue(label: "com.aircatch.network", qos: .userInitiated)
    
    // MARK: - UDP Components
    private var udpListener: NWListener?
    private var udpConnections: [NWConnection] = []
    private var udpClientEndpoints: [NWEndpoint] = []
    private var registeredUDPClients: [NWConnection] = []  // Clients registered via incoming packets
    private var udpReceiveHandler: ((Packet, NWEndpoint?) -> Void)?
    private var udpClientConnection: NWConnection?

    // Best-effort mapping from client IP -> last seen UDP endpoint (for retransmits)
    private var udpEndpointByHost: [String: NWEndpoint] = [:]
    
    // MARK: - TCP Components
    private var tcpListener: NWListener?
    private var tcpConnections: [NWConnection] = []
    private var tcpReceiveHandler: ((Packet, NWConnection) -> Void)?
    private var tcpClientConnection: NWConnection?
    
    // MARK: - Actual bound ports
    private(set) var actualUDPPort: UInt16 = 0
    private(set) var actualTCPPort: UInt16 = 0

    private init() {}

    /// Starts a UDP listener - uses port 0 to let OS pick an available port
    func startUDPListener(port: UInt16 = 0, onPacket: @escaping (Packet, NWEndpoint?) -> Void) throws {
        guard udpListener == nil else { return }
        udpReceiveHandler = onPacket

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true

        // Use NWEndpoint.Port(integerLiteral: 0) to get any available port
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        
        listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
            switch state {
            case .ready:
                if let actualPort = listener.port?.rawValue {
                    self?.actualUDPPort = actualPort
                    NSLog("UDP listener ready on port \(actualPort)")
                }
            case .failed(let error):
                NSLog("UDP listener failed: \(error)")
            case .cancelled:
                break
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.addConnection(connection, to: &self.udpConnections)
            if let endpoint = connection.currentPath?.remoteEndpoint {
                if !self.udpClientEndpoints.contains(where: { $0 == endpoint }) {
                    self.udpClientEndpoints.append(endpoint)
                }
            }
            self.prepareUDPConnection(connection)
            connection.start(queue: self.queue)  // Must start the connection to transition to .ready
        }

        listener.start(queue: queue)
        udpListener = listener
    }
    
    // MARK: - TCP Listener (Host)
    
    /// Starts a TCP listener - uses port 0 to let OS pick an available port
    func startTCPListener(port: UInt16 = 0, onPacket: @escaping (Packet, NWConnection) -> Void) throws {
        guard tcpListener == nil else { return }
        tcpReceiveHandler = onPacket
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        
        // Optimize for interactive video streaming
        parameters.serviceClass = .interactiveVideo
        
        let tcpOption = parameters.defaultProtocolStack.transportProtocol! as! NWProtocolTCP.Options
        tcpOption.enableKeepalive = true
        tcpOption.keepaliveIdle = 2
        tcpOption.noDelay = true // Disable Nagle's algorithm for instant sending
        
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        
        listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
            switch state {
            case .ready:
                if let actualPort = listener.port?.rawValue {
                    self?.actualTCPPort = actualPort
                    NSLog("TCP listener ready on port \(actualPort)")
                }
            case .failed(let error):
                NSLog("TCP listener failed: \(error)")
            case .cancelled:
                break
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.addConnection(connection, to: &self.tcpConnections)
            self.prepareTCPConnection(connection)
        }
        
        listener.start(queue: queue)
        tcpListener = listener
    }

    /// Connects to a UDP endpoint for the client side.
    func connectUDP(to host: String, port: UInt16, onPacket: @escaping (Packet, NWEndpoint?) -> Void) {
        udpReceiveHandler = onPacket

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            NSLog("Invalid UDP port \(port)")
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection.stateUpdateHandler = { (state: NWConnection.State) in
            switch state {
            case .failed(let error):
                NSLog("UDP connection failed: \(error)")
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
            NSLog("UDP send skipped: no active connection")
            return
        }
        let datagram = buildDatagram(type: type, payload: payload)
        connection.send(content: datagram, completion: NWConnection.SendCompletion.contentProcessed({ error in
            if let error {
                NSLog("UDP send error: \(error)")
            }
        }))
    }

    /// Sends a UDP packet back to a specific endpoint (host reply path).
    func sendUDP(to endpoint: NWEndpoint, type: PacketType, payload: Data) {
        let connection = NWConnection(to: endpoint, using: .udp)
        prepareUDPConnection(connection)
        connection.start(queue: queue)
        let datagram = buildDatagram(type: type, payload: payload)
        connection.send(content: datagram, completion: NWConnection.SendCompletion.contentProcessed({ error in
            if let error {
                NSLog("UDP send error: \(error)")
            }
            connection.cancel()
        }))
    }
    
    /// Broadcasts a UDP packet to all connected clients.
    func broadcastUDP(type: PacketType, payload: Data) {
        let datagram = buildDatagram(type: type, payload: payload)
        
        // Log occasionally to debug connection tracking
        if type == .videoFrameChunk && Int.random(in: 0...1000) == 0 {
             let states = udpConnections.map { "\($0.endpoint) \($0.state)" }
             NSLog("[NetworkManager] Broadcasting chunk to \(udpConnections.count) clients: \(states)")
        }
        
        var sentCount = 0
        for connection in udpConnections {
            if connection.state == .ready {
                connection.send(content: datagram, completion: NWConnection.SendCompletion.contentProcessed({ _ in
                    // Error logging commented out to reduce noise
                }))
                sentCount += 1
            } else {
                // NSLog("Skipping connection \(connection.endpoint) - State: \(connection.state)")
            }
        }
        
        // Also send to manually registered clients (from incoming UDP packets)
        for connection in registeredUDPClients where connection.state == .ready {
            connection.send(content: datagram, completion: NWConnection.SendCompletion.contentProcessed({ error in
                if let error {
                    NSLog("UDP broadcast to registered client error: \(error)")
                }
            }))
        }
    }
    
    /// Registers a client endpoint for UDP broadcasting (called when receiving UDP packets from clients)
    func registerUDPClient(endpoint: NWEndpoint) {
        // Check if already registered
        guard !udpClientEndpoints.contains(where: { $0 == endpoint }) else { return }
        
        udpClientEndpoints.append(endpoint)

        if case .hostPort(let host, _) = endpoint {
            udpEndpointByHost["\(host)"] = endpoint
        }
        
        // Create a connection to send data back to this client
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("UDP client connection ready: \(endpoint)")
            case .failed(let error):
                NSLog("UDP client connection failed: \(error)")
            default:
                break
            }
        }
        connection.start(queue: queue)
        registeredUDPClients.append(connection)
        
        NSLog("[NetworkManager] Registered UDP client: \(endpoint)")
    }

    func udpEndpoint(forHostString hostString: String) -> NWEndpoint? {
        udpEndpointByHost[hostString]
    }
    
    /// Broadcasts a TCP packet to all connected clients.
    func broadcastTCP(type: PacketType, payload: Data) {
        let datagram = buildTCPPacket(type: type, payload: payload)
        
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.tcpConnections where connection.state == .ready {
                connection.send(content: datagram, completion: NWConnection.SendCompletion.contentProcessed({ error in
                    if let error {
                        NSLog("TCP broadcast error: \(error)")
                    }
                }))
            }
        }
    }
    
    // MARK: - TCP Client Methods
    
    /// Connects to a TCP endpoint for reliable messaging.
    func connectTCP(to host: String, port: UInt16, onPacket: @escaping (Packet, NWConnection) -> Void) {
        tcpReceiveHandler = onPacket
        
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            NSLog("Invalid TCP port \(port)")
            return
        }
        
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self] (state: NWConnection.State) in
            switch state {
            case .ready:
                NSLog("TCP connected to \(host):\(port)")
                self?.tcpClientConnection = connection
            case .failed(let error):
                NSLog("TCP connection failed: \(error)")
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
            NSLog("TCP send skipped: no active connection")
            return
        }
        sendTCP(to: connection, type: type, payload: payload)
    }
    
    /// Sends a TCP packet to a specific connection.
    func sendTCP(to connection: NWConnection, type: PacketType, payload: Data) {
        let packet = buildTCPPacket(type: type, payload: payload)
        connection.send(content: packet, completion: NWConnection.SendCompletion.contentProcessed({ error in
            if let error {
                NSLog("TCP send error: \(error)")
            }
        }))
    }

    /// Tears down all UDP resources.
    func stopUDP() {
        udpListener?.cancel()
        udpListener = nil

        udpClientConnection?.cancel()
        udpClientConnection = nil

        udpConnections.forEach { $0.cancel() }
        udpConnections.removeAll()
        udpClientEndpoints.removeAll()
        
        registeredUDPClients.forEach { $0.cancel() }
        registeredUDPClients.removeAll()
        
        udpReceiveHandler = nil
    }
    
    /// Tears down all TCP resources.
    func stopTCP() {
        tcpListener?.cancel()
        tcpListener = nil
        
        tcpClientConnection?.cancel()
        tcpClientConnection = nil
        
        tcpConnections.forEach { $0.cancel() }
        tcpConnections.removeAll()
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
                NSLog("UDP connection failed: \(error)")
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
                NSLog("UDP receive error: \(error)")
            }

            if let data, let packet = self.parsePacket(from: data) {
                self.udpReceiveHandler?(packet, connection.endpoint)
            }

            switch connection.state {
            case .cancelled:
                break
            case .failed(_):
                break
            default:
                self.receiveLoop(on: connection)
            }
        }
    }
    
    // MARK: - TCP Connection Setup
    
    private func prepareTCPConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                NSLog("TCP connection failed: \(error)")
                if let self {
                    self.removeConnection(connection, from: &self.tcpConnections)
                }
            case .cancelled:
                if let self {
                    self.removeConnection(connection, from: &self.tcpConnections)
                }
            default:
                break
            }
        }
        tcpReceiveLoop(on: connection)
        connection.start(queue: queue)
    }
    
    private func tcpReceiveLoop(on connection: NWConnection) {
        // First read the header (1 byte type + 4 bytes length)
        connection.receive(minimumIncompleteLength: 5, maximumLength: 5) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            
            if let error {
                NSLog("TCP receive error: \(error)")
                return
            }
            
            if isComplete {
                // Connection closed
                self.tcpReceiveHandler?(Packet(type: .disconnect, payload: Data()), connection)
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
                self.tcpReceiveHandler?(Packet(type: type, payload: Data()), connection)
                self.tcpReceiveLoop(on: connection)
                return
            }
            
            // Read the payload
            connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] payloadData, _, _, error in
                guard let self else { return }
                
                if let error {
                    NSLog("TCP payload receive error: \(error)")
                }
                
                if let payloadData {
                    self.tcpReceiveHandler?(Packet(type: type, payload: payloadData), connection)
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

// MARK: - Connection Helpers

private extension NetworkManager {
    func addConnection(_ connection: NWConnection, to list: inout [NWConnection]) {
        if !list.contains(where: { $0 === connection }) {
            list.append(connection)
        }
    }
    
    func removeConnection(_ connection: NWConnection, from list: inout [NWConnection]) {
        list.removeAll { $0 === connection }
    }
}

