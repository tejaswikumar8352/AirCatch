//
//  SharedModels.swift
//  AirCatchHost
//
//  Shared data models for host/client communication.
//

import Foundation
import os

// MARK: - Logging



enum AirCatchLog {
    enum Category: String {
        case network = "Network"
        case video = "Video"
        case input = "Input"
        case general = "General"
    }
    
    nonisolated private static let subsystem = "com.aircatch.host"
    
    nonisolated static func info(_ message: String, category: Category = .general) {
        os_log(.info, log: OSLog(subsystem: subsystem, category: category.rawValue), "%{public}@", message)
    }
    
    nonisolated static func error(_ message: String, category: Category = .general) {
        os_log(.error, log: OSLog(subsystem: subsystem, category: category.rawValue), "%{public}@", message)
    }
    
    nonisolated static func debug(_ message: String, category: Category = .general) {
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
    
    // Streaming defaults (optimized for HEVC on Apple Silicon)
    static let defaultBitrate: Int = 16_000_000  // 16 Mbps - HEVC sweet spot
    static let defaultFrameRate: Int = 60        // Always 60 FPS
    static let maxTouchEventsPerSecond: Int = 60
    
    // Quality presets defaults
    static let defaultPreset: QualityPreset = .balanced
}

// MARK: - Network Mode

enum NetworkMode: String, Codable {
    case local   // Same network, P2P/AWDL - max quality
    case remote  // Internet/NAT - adaptive quality
    
    var displayName: String {
        switch self {
        case .local: return "Local Network"
        case .remote: return "Remote Connection"
        }
    }
}

// MARK: - Quality Presets
// Optimized for HEVC on Apple Silicon (M2/M3)
// 3 presets: one for each use case

enum QualityPreset: String, Codable, CaseIterable {
    case performance  // Lowest latency, great for interaction-heavy use
    case balanced     // Default - best balance of quality and responsiveness
    case quality      // Maximum quality - best for static content/reading
    
    var bitrate: Int {
        switch self {
        case .performance: return 14_000_000  // 14 Mbps - minimal network load
        case .balanced: return 20_000_000     // 20 Mbps - sweet spot
        case .quality: return 30_000_000      // 30 Mbps - maximum quality
        }
    }
    
    var frameRate: Int {
        return 60  // Always 60 FPS
    }
    
    /// Always use HEVC for best quality-per-bit
    var useHEVC: Bool {
        return true
    }
    
    var displayName: String {
        switch self {
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .quality: return "Quality"
        }
    }
    
    var shortName: String {
        displayName
    }
    
    var description: String {
        switch self {
        case .performance: return "Lowest latency"
        case .balanced: return "Best balance"
        case .quality: return "Maximum quality"
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
    case qualityReport = 0x08  // Client reports quality metrics
    case ping = 0x09
    case pong = 0x0A
    case qualityAdjust = 0x0B
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

// MARK: - Quality Adjustment

struct QualityAdjustment: Codable {
    let preset: QualityPreset
    let reason: String
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
    let requestedMode: NetworkMode? // Client can request specific mode
    /// Extended display configuration (for virtual display mode)
    let displayConfig: ExtendedDisplayConfig?
    /// Requested session features. If nil, host may assume defaults.
    let requestVideo: Bool?
    /// Prefer low-latency transport when host must fall back from AirCatch.
    let preferLowLatency: Bool?
    /// When true, client requests lossless-ish video delivery (UDP + retransmit over TCP).
    let losslessVideo: Bool?
    let deviceId: String?           // Unique device identifier for trusted devices
    let pin: String?                // PIN for pairing verification
    
    init(clientName: String, clientVersion: String, deviceModel: String? = nil,
         screenWidth: Int? = nil, screenHeight: Int? = nil,
         preferredQuality: QualityPreset? = nil,
         requestedMode: NetworkMode? = nil,
         displayConfig: ExtendedDisplayConfig? = nil,
         requestVideo: Bool? = nil,
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
        self.requestedMode = requestedMode
        self.displayConfig = displayConfig
        self.requestVideo = requestVideo
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
    /// Whether virtual display mode is active
    let isVirtualDisplay: Bool?
    /// The display mode (mirror/extend)
    let displayMode: StreamDisplayMode?
    /// Position of extended display (if virtual display is active)
    let displayPosition: ExtendedDisplayPosition?
    
    init(width: Int, height: Int, frameRate: Int, hostName: String,
         networkMode: NetworkMode? = nil, qualityPreset: QualityPreset? = nil, bitrate: Int? = nil,
         isVirtualDisplay: Bool? = nil, displayMode: StreamDisplayMode? = nil,
         displayPosition: ExtendedDisplayPosition? = nil) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hostName = hostName
        self.networkMode = networkMode
        self.qualityPreset = qualityPreset
        self.bitrate = bitrate
        self.isVirtualDisplay = isVirtualDisplay
        self.displayMode = displayMode
        self.displayPosition = displayPosition
    }
}

// MARK: - Touch Event Models

/// Touch event sent from client to host.
struct TouchEvent: Codable {
    let normalizedX: Double
    let normalizedY: Double
    let eventType: TouchEventType
    let timestamp: TimeInterval
    let sequenceNumber: UInt32?  // For ordering/deduplication
    
    init(normalizedX: Double,
         normalizedY: Double,
         eventType: TouchEventType,
         timestamp: TimeInterval = Date().timeIntervalSince1970,
         sequenceNumber: UInt32? = nil) {
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.eventType = eventType
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

// MARK: - Quality Report

struct QualityReport: Codable {
    let droppedFrames: Int
    let latencyMs: Double
    let jitterMs: Double
    let timestamp: TimeInterval
    
    // Aliases for compatibility
    var framesDropped: Int { droppedFrames }
    var averageLatency: Double { latencyMs }
    var framesReceived: Int { 0 } // Placeholder as it wasn't in original model
    
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
    let sequenceNumber: UInt32?
    let clientTimestamp: TimeInterval?
    
    init(timestamp: TimeInterval = Date().timeIntervalSince1970, sequenceNumber: UInt32? = nil, clientTimestamp: TimeInterval? = nil) {
        self.timestamp = timestamp
        self.sequenceNumber = sequenceNumber
        self.clientTimestamp = clientTimestamp
    }
}

struct PongPacket: Codable {
    let sequenceNumber: UInt32?
    let clientTimestamp: TimeInterval
    let hostTimestamp: TimeInterval
    
    init(sequenceNumber: UInt32? = nil, clientTimestamp: TimeInterval, hostTimestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.sequenceNumber = sequenceNumber
        self.clientTimestamp = clientTimestamp
        self.hostTimestamp = hostTimestamp
    }
}

// MARK: - Video Frame Header

struct VideoFrameHeader {
    let timestamp: Int64
    let frameNumber: UInt32
    let isKeyFrame: Bool
}

// MARK: - Extended Display Types

/// Display streaming mode - mirror vs extend
enum StreamDisplayMode: String, Codable, CaseIterable {
    case mirror = "Mirror"
    case extend = "Extend Display"
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .mirror: return "Mirror your Mac screen to iPad"
        case .extend: return "Use iPad as a second display"
        }
    }
}

/// Position of extended display relative to main display
enum ExtendedDisplayPosition: String, Codable, CaseIterable {
    case right = "Right"
    case left = "Left"
    case above = "Above"
    case below = "Below"
    
    var displayName: String { rawValue }
}

/// Extended display configuration sent from client
struct ExtendedDisplayConfig: Codable {
    let mode: StreamDisplayMode
    let position: ExtendedDisplayPosition
    let resolution: ExtendedDisplayResolution?
    
    init(mode: StreamDisplayMode = .mirror,
         position: ExtendedDisplayPosition = .right,
         resolution: ExtendedDisplayResolution? = nil) {
        self.mode = mode
        self.position = position
        self.resolution = resolution
    }
}

/// Resolution options for extended display
enum ExtendedDisplayResolution: String, Codable, CaseIterable {
    case native = "Native"           // iPad native resolution
    case matched = "Matched"         // Match main display scale
    case retina = "Retina"           // 2x scaling for HiDPI
    case standard = "Standard"       // 1x scaling
    
    var displayName: String { rawValue }
}

// MARK: - Display Info

struct DisplayInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let width: Int
    let height: Int
    let isMain: Bool
    
    init(id: String, name: String, width: Int, height: Int, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.isMain = isMain
    }
}

