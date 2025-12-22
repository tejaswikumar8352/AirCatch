//
//  SharedModels.swift
//  AirCatchClient
//
//  Shared data models for host/client communication.
//

import Foundation
import Network
import os

// MARK: - Logging



enum AirCatchLog {
    enum Category: String {
        case network = "Network"
        case video = "Video"
        case input = "Input"
        case general = "General"
    }
    
    nonisolated private static let subsystem = "com.aircatch.client"
    
    static func info(_ message: String, category: Category = .general) {
        os_log(.info, log: OSLog(subsystem: subsystem, category: category.rawValue), "%{public}@", message)
    }
    
    static func error(_ message: String, category: Category = .general) {
        os_log(.error, log: OSLog(subsystem: subsystem, category: category.rawValue), "%{public}@", message)
    }
    
    static func debug(_ message: String, category: Category = .general) {
        os_log(.debug, log: OSLog(subsystem: subsystem, category: category.rawValue), "%{public}@", message)
    }
}

// MARK: - Configuration Constants

enum AirCatchConfig {
    static let udpPort: UInt16 = 5555
    static let tcpPort: UInt16 = 5556
    static let bonjourServiceType = "_aircatch._udp."
    static let bonjourTCPServiceType = "_aircatch._tcp."
    
    // Port aliases for clarity
    static let defaultUDPPort: UInt16 = udpPort
    static let defaultTCPPort: UInt16 = tcpPort
    
    // Streaming defaults (use Balanced preset values)
    static let defaultBitrate: Int = 30_000_000  // 30 Mbps
    static let defaultFrameRate: Int = 45
    static let maxTouchEventsPerSecond: Int = 60
    static let reconnectMaxAttempts = 5
    static let reconnectBaseDelay: TimeInterval = 1.0
    
    // Quality presets defaults
    static let defaultPreset: QualityPreset = .balanced
}

// MARK: - Network Mode

enum NetworkMode: String, Codable {
    case local   // Same network, P2P - max quality
    case remote  // Internet/NAT - adaptive quality
}

// MARK: - Quality Presets

enum QualityPreset: String, Codable, CaseIterable {
    case clarity   // 35 Mbps, 30fps - best for text/documents
    case balanced  // 30 Mbps, 45fps - general use (default)
    case smooth    // 25 Mbps, 60fps - video/animations
    case max       // 50 Mbps, 60fps - maximum quality
    
    var bitrate: Int {
        switch self {
        case .clarity: return 35_000_000
        case .balanced: return 30_000_000
        case .smooth: return 25_000_000
        case .max: return 50_000_000
        }
    }
    
    var frameRate: Int {
        switch self {
        case .clarity: return 30
        case .balanced: return 45
        case .smooth, .max: return 60
        }
    }
    
    var displayName: String {
        switch self {
        case .clarity: return "Clarity (30fps)"
        case .balanced: return "Balanced (45fps)"
        case .smooth: return "Smooth (60fps)"
        case .max: return "Max Quality"
        }
    }
    
    var shortName: String {
        switch self {
        case .clarity: return "Clarity"
        case .balanced: return "Balanced"
        case .smooth: return "Smooth"
        case .max: return "Max"
        }
    }
    
    var description: String {
        switch self {
        case .clarity: return "Best for text & documents"
        case .balanced: return "General use"
        case .smooth: return "Video & animations"
        case .max: return "Maximum quality"
        }
    }
}

// MARK: - Packet Types

enum PacketType: UInt8 {
    case videoFrame = 0x01
    case touchEvent = 0x02
    case handshake = 0x03
    case handshakeAck = 0x04
    case disconnect = 0x05
    case scrollEvent = 0x06
    case keyboardEvent = 0x07
    case qualityReport = 0x08  // Client reports quality metrics
    case ping = 0x09
    case pong = 0x0A
    case videoFrameChunk = 0x0C
    case pairingFailed = 0x0D  // PIN mismatch
    case videoFrameChunkNack = 0x0E // Client requests resend of missing chunks (lossless mode)
    case audioPCM = 0x0F
}

struct Packet {
    let type: PacketType
    let payload: Data
}

// MARK: - Lossless Video (UDP Retransmit)

/// Sent by client over TCP when some UDP chunks for a frame are missing.
struct VideoChunkNackRequest: Codable {
    let frameId: UInt32
    let missingChunkIndices: [UInt16]
}

// MARK: - Handshake Models

/// Sent by client to initiate connection.
struct HandshakeRequest: Codable {
    let clientName: String
    let clientVersion: String
    let deviceModel: String?        // e.g., "iPad Pro 12.9"
    let screenWidth: Int?           // Client screen width
    let screenHeight: Int?          // Client screen height
    let preferredQuality: QualityPreset?
    /// Requested session features. If nil, host may assume defaults.
    let requestVideo: Bool?
    let requestKeyboard: Bool?
    let requestTrackpad: Bool?
    /// Prefer low-latency transport when host must fall back from AirCatch.
    let preferLowLatency: Bool?
    /// When true, client requests lossless-ish video delivery (UDP + retransmit over TCP).
    let losslessVideo: Bool?
    let deviceId: String?           // Unique device identifier for trusted devices
    let pin: String?                // PIN for pairing verification
    
    init(clientName: String,
         clientVersion: String,
         deviceModel: String? = nil,
         screenWidth: Int? = nil,
         screenHeight: Int? = nil,
         preferredQuality: QualityPreset? = nil,
         requestVideo: Bool? = nil,
         requestKeyboard: Bool? = nil,
         requestTrackpad: Bool? = nil,
         preferLowLatency: Bool? = nil,
         losslessVideo: Bool? = nil,
         deviceId: String? = nil,
         pin: String? = nil) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.deviceModel = deviceModel
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.preferredQuality = preferredQuality
        self.requestVideo = requestVideo
        self.requestKeyboard = requestKeyboard
        self.requestTrackpad = requestTrackpad
        self.preferLowLatency = preferLowLatency
        self.losslessVideo = losslessVideo
        self.deviceId = deviceId
        self.pin = pin
    }
}

/// Sent by host to acknowledge connection.
struct HandshakeAck: Codable {
    let width: Int
    let height: Int
    let frameRate: Int
    let hostName: String
    let networkMode: NetworkMode?   // Detected network mode
    let qualityPreset: QualityPreset?
    let bitrate: Int?
    
    init(width: Int, height: Int, frameRate: Int, hostName: String,
         networkMode: NetworkMode? = nil, qualityPreset: QualityPreset? = nil, bitrate: Int? = nil) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hostName = hostName
        self.networkMode = networkMode
        self.qualityPreset = qualityPreset
        self.bitrate = bitrate
    }
}

// MARK: - Touch Event Models

/// Touch event sent from client to host.
struct TouchEvent: Codable {
    let normalizedX: Double
    let normalizedY: Double
    let eventType: TouchEventType
    /// When true, host interprets motion events as pointer movement (not dragging).
    let isTrackpad: Bool?
    /// Delta movement for trackpad mode (relative movement)
    let deltaX: Double?
    let deltaY: Double?
    let timestamp: TimeInterval
    let sequenceNumber: UInt32?  // For ordering/deduplication
    
    init(normalizedX: Double,
         normalizedY: Double,
         eventType: TouchEventType,
         isTrackpad: Bool? = nil,
         deltaX: Double? = nil,
         deltaY: Double? = nil,
         timestamp: TimeInterval = Date().timeIntervalSince1970,
         sequenceNumber: UInt32? = nil) {
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.eventType = eventType
        self.isTrackpad = isTrackpad
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
    }
}

/// Type of touch event.
enum TouchEventType: String, Codable {
    case began
    case moved
    case ended
    case cancelled
    case rightClick
    case doubleClick
    // Drag events (click-hold and move)
    case dragBegan
    case dragMoved
    case dragEnded
}

// MARK: - Scroll Event

struct ScrollEvent: Codable {
    let deltaX: Double
    let deltaY: Double
    let timestamp: TimeInterval
    
    init(deltaX: Double, deltaY: Double, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.timestamp = timestamp
    }
}

// MARK: - Keyboard Event

struct KeyboardEvent: Codable {
    let keyCode: UInt16
    let characters: String?
    let isKeyDown: Bool
    let modifiers: KeyModifiers
    let timestamp: TimeInterval
    
    init(keyCode: UInt16, characters: String? = nil, isKeyDown: Bool,
         modifiers: KeyModifiers = KeyModifiers(), timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.keyCode = keyCode
        self.characters = characters
        self.isKeyDown = isKeyDown
        self.modifiers = modifiers
        self.timestamp = timestamp
    }
}

struct KeyModifiers: Codable {
    let shift: Bool
    let control: Bool
    let option: Bool
    let command: Bool
    
    init(shift: Bool = false, control: Bool = false, option: Bool = false, command: Bool = false) {
        self.shift = shift
        self.control = control
        self.option = option
        self.command = command
    }
}

// MARK: - Quality Report

struct QualityReport: Codable {
    let droppedFrames: Int
    let latencyMs: Double
    let jitterMs: Double
    let timestamp: TimeInterval
    
    init(droppedFrames: Int, latencyMs: Double, jitterMs: Double,
         timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.droppedFrames = droppedFrames
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.timestamp = timestamp
    }
}

// MARK: - Ping/Pong for Latency Measurement

struct PingPacket: Codable {
    let timestamp: TimeInterval
    
    init(timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.timestamp = timestamp
    }
}

struct PongPacket: Codable {
    let pingTimestamp: TimeInterval
    let pongTimestamp: TimeInterval
    
    init(pingTimestamp: TimeInterval, pongTimestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.pingTimestamp = pingTimestamp
        self.pongTimestamp = pongTimestamp
    }
}

// MARK: - Discovered Host

struct DiscoveredHost: Identifiable, Equatable {
    let id: String
    let name: String
    let endpoint: Network.NWEndpoint?
    /// If present, this host is reachable via AirCatch (MultipeerConnectivity).
    /// Value matches the remote peer's displayName.
    let mpcPeerName: String?
    /// Optional stable host identifier (future-proofing for de-duplication).
    let hostId: String?
    let isDirectIP: Bool  // True if connected via direct IP (remote mode)
    
    init(
        id: String,
        name: String,
        endpoint: Network.NWEndpoint? = nil,
        mpcPeerName: String? = nil,
        hostId: String? = nil,
        isDirectIP: Bool = false
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.mpcPeerName = mpcPeerName
        self.hostId = hostId
        self.isDirectIP = isDirectIP
    }
    
    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.id == rhs.id
    }
}
