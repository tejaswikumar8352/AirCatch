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
    nonisolated static let udpPort: UInt16 = 5555
    nonisolated static let tcpPort: UInt16 = 5556
    nonisolated static let bonjourServiceType = "_aircatch._udp."
    nonisolated static let bonjourTCPServiceType = "_aircatch._tcp."

    // Remote (Internet) relay/signaling
    nonisolated static let remoteRelayURL: String = "wss://aircatch.duckdns.org/ws"
    
    // Port aliases for clarity
    nonisolated static let defaultUDPPort: UInt16 = 5555
    nonisolated static let defaultTCPPort: UInt16 = 5556
    
    // Network constants
    static let maxUDPPayloadSize: Int = 1200  // Safe UDP payload size (below MTU)
    
    // Streaming defaults (optimized for HEVC on Apple Silicon)
    static let defaultBitrate: Int = 16_000_000  // 16 Mbps - HEVC sweet spot
    static let defaultFrameRate: Int = 60        // Always 60 FPS
    static let maxTouchEventsPerSecond: Int = 60
    static let reconnectMaxAttempts = 5
    static let reconnectBaseDelay: TimeInterval = 1.0
    
    // Remote Mode Specifics
    static let remoteFrameRate: Int = 30
    static let remoteBitrate: Int = 6_000_000     // 6 Mbps (target range: 4-10)
    static let remoteMinBitrate: Int = 4_000_000  // Floor for adaptive
    static let remoteMaxBitrate: Int = 10_000_000 // Ceiling for adaptive
    static let remoteMinFPS: Int = 20             // Floor when congested
    static let remoteMaxFPS: Int = 30             // Target FPS
    static let remoteGOPDuration: Double = 0.5    // Short GOP (0.5s) for faster recovery
    
    // Resolution limits
    static let maxRenderPixels: Double = 8_000_000  // ~8MP cap for render resolution
    
    // Frame cache settings
    static let frameCacheTTL: TimeInterval = 1.0  // Seconds before cached frames expire
    static let cachePruneInterval: Int = 60       // Prune every N frames
    
    // Quality presets defaults
    static let defaultPreset: QualityPreset = .balanced
}


// MARK: - Quality Presets
// Optimized for HEVC on Apple Silicon (M2/M3)
// 3 presets: one for each use case

enum QualityPreset: String, Codable, CaseIterable {
    case performance  // Light streaming, bandwidth-conscious
    case balanced     // Default - best balance of quality and responsiveness
    case pro          // Maximum quality - best for static content/reading
    
    var bitrate: Int {
        switch self {
        case .performance: return 12_000_000  // 12 Mbps - light streaming
        case .balanced: return 20_000_000     // 20 Mbps - sweet spot
        case .pro: return 32_000_000          // 32 Mbps - high quality
        }
    }
    
    var frameRate: Int {
        return 60  // All presets use 60 FPS
    }
    
    /// Always use HEVC for best quality-per-bit
    var useHEVC: Bool {
        return true
    }
    
    /// Default value for optimize-for-host-display option per preset.
    /// When true, streams at the host's native resolution (may require letterboxing on client).
    /// When false, scales to the client's display resolution for pixel-perfect fit.
    var defaultOptimizeForHostDisplay: Bool {
        // Always use client resolution for pixel-perfect display
        return false
    }
    
    var displayName: String {
        switch self {
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .pro: return "Pro"
        }
    }
    
    var shortName: String {
        displayName
    }
    
    var description: String {
        switch self {
        case .performance: return "12 Mbps • 60 FPS"
        case .balanced: return "20 Mbps • 60 FPS"
        case .pro: return "32 Mbps • 60 FPS"
        }
    }
    
    var icon: String {
        switch self {
        case .performance: return "hare"
        case .balanced: return "scale.3d"
        case .pro: return "sparkles"
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
    case keyEvent = 0x07       // Keyboard input
    case qualityReport = 0x08  // Client reports quality metrics
    case ping = 0x09
    case pong = 0x0A
    case videoFrameChunk = 0x0C
    case pairingFailed = 0x0D  // PIN mismatch
    case videoFrameChunkNack = 0x0E // Client requests resend of missing chunks (lossless mode)
    case audioPCM = 0x0F
    case mediaKeyEvent = 0x10  // Media keys (volume, brightness, play/pause, etc.)
}

// MARK: - Connection/Codec Preferences

enum ConnectionMode: String, Codable {
    case localPeerToPeer
    case localNetwork
    case remote
}

enum CodecPreference: String, Codable {
    case auto
    case hevc
    case h264
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
    let deviceModel: String?        // e.g., "iPad Pro 12.9-inch (6th generation)"
    let screenWidth: Int?           // Client screen width in PIXELS (physical resolution)
    let screenHeight: Int?          // Client screen height in PIXELS (physical resolution)
    let screenScale: Double?        // Native scale factor (typically 2.0 for Retina)
    let nativeBoundsWidth: Int?     // UIScreen.nativeBounds.width (always pixels)
    let nativeBoundsHeight: Int?    // UIScreen.nativeBounds.height (always pixels)
    let preferredQuality: QualityPreset?
    let connectionMode: ConnectionMode?
    let codecPreference: CodecPreference?
    /// Extended display configuration (for virtual display mode)
    let displayConfig: ExtendedDisplayConfig?
    /// Requested session features. If nil, host may assume defaults.
    let requestVideo: Bool?
    /// When true, client requests audio streaming from host.
    let requestAudio: Bool?
    /// Prefer low-latency transport when host must fall back from AirCatch.
    let preferLowLatency: Bool?
    /// When true, client requests lossless-ish video delivery (UDP + retransmit over TCP).
    let losslessVideo: Bool?
    let deviceId: String?           // Unique device identifier for trusted devices
    let pin: String?                // PIN for pairing verification
    /// When true, stream at host's native resolution instead of scaling to client resolution.
    /// This provides higher quality but may require letterboxing on the client.
    let optimizeForHostDisplay: Bool?
    
    init(clientName: String,
         clientVersion: String,
         deviceModel: String? = nil,
         screenWidth: Int? = nil,
         screenHeight: Int? = nil,
         screenScale: Double? = nil,
         nativeBoundsWidth: Int? = nil,
         nativeBoundsHeight: Int? = nil,
         preferredQuality: QualityPreset? = nil,
         connectionMode: ConnectionMode? = nil,
         codecPreference: CodecPreference? = nil,
         displayConfig: ExtendedDisplayConfig? = nil,
         requestVideo: Bool? = nil,
         requestAudio: Bool? = nil,
         preferLowLatency: Bool? = nil,
         losslessVideo: Bool? = nil,
         deviceId: String? = nil,
         pin: String? = nil,
         optimizeForHostDisplay: Bool? = nil) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.deviceModel = deviceModel
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.screenScale = screenScale
        self.nativeBoundsWidth = nativeBoundsWidth
        self.nativeBoundsHeight = nativeBoundsHeight
        self.preferredQuality = preferredQuality
        self.connectionMode = connectionMode
        self.codecPreference = codecPreference
        self.displayConfig = displayConfig
        self.requestVideo = requestVideo
        self.requestAudio = requestAudio
        self.preferLowLatency = preferLowLatency
        self.losslessVideo = losslessVideo
        self.deviceId = deviceId
        self.pin = pin
        self.optimizeForHostDisplay = optimizeForHostDisplay
    }
}

/// Sent by host to acknowledge connection.
struct HandshakeAck: Codable {
    let width: Int
    let height: Int
    let frameRate: Int
    let hostName: String
    let qualityPreset: QualityPreset?
    let bitrate: Int?
    /// Whether virtual display mode is active
    let isVirtualDisplay: Bool?
    /// The display mode (mirror/extend)
    let displayMode: StreamDisplayMode?
    /// Position of extended display (if virtual display is active)
    let displayPosition: ExtendedDisplayPosition?
    
    init(width: Int, height: Int, frameRate: Int, hostName: String,
         qualityPreset: QualityPreset? = nil, bitrate: Int? = nil,
         isVirtualDisplay: Bool? = nil, displayMode: StreamDisplayMode? = nil,
         displayPosition: ExtendedDisplayPosition? = nil) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hostName = hostName
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

// MARK: - Key Event

/// Keyboard modifier flags (matches macOS CGEventFlags)
struct KeyModifiers: OptionSet, Codable {
    let rawValue: UInt32
    
    static let shift     = KeyModifiers(rawValue: 1 << 0)
    static let control   = KeyModifiers(rawValue: 1 << 1)
    static let option    = KeyModifiers(rawValue: 1 << 2)
    static let command   = KeyModifiers(rawValue: 1 << 3)
    static let capsLock  = KeyModifiers(rawValue: 1 << 4)
}

/// Keyboard event sent from client to host
struct KeyEvent: Codable {
    let keyCode: UInt16       // macOS virtual key code
    let character: String?    // The character typed (for text input)
    let modifiers: KeyModifiers
    let isKeyDown: Bool       // true = key press, false = key release
    let timestamp: TimeInterval
    
    init(keyCode: UInt16, character: String? = nil, modifiers: KeyModifiers = [], isKeyDown: Bool, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.keyCode = keyCode
        self.character = character
        self.modifiers = modifiers
        self.isKeyDown = isKeyDown
        self.timestamp = timestamp
    }
}

/// Media key event for system controls (volume, brightness, play/pause, etc.)
struct MediaKeyEvent: Codable {
    let mediaKey: Int32       // NX key type (e.g., NX_KEYTYPE_SOUND_UP = 0)
    let keyCode: UInt16       // Fallback key code
    let timestamp: TimeInterval
    
    init(mediaKey: Int32, keyCode: UInt16, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.mediaKey = mediaKey
        self.keyCode = keyCode
        self.timestamp = timestamp
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
    /// Optional ports advertised via Bonjour TXT (or direct-IP entry).
    let udpPort: UInt16?
    let tcpPort: UInt16?
    /// If present, this host is reachable via AirCatch (MultipeerConnectivity).
    /// Value matches the remote peer's displayName.
    let mpcPeerName: String?
    /// Optional stable host identifier (future-proofing for de-duplication).
    let hostId: String?
    
    init(
        id: String,
        name: String,
        endpoint: Network.NWEndpoint? = nil,
        udpPort: UInt16? = nil,
        tcpPort: UInt16? = nil,
        mpcPeerName: String? = nil,
        hostId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.udpPort = udpPort
        self.tcpPort = tcpPort
        self.mpcPeerName = mpcPeerName
        self.hostId = hostId
    }
    
    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Virtual Display Mode

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

// MARK: - Sidecar-like iPad Display Configuration

/// iPad model-specific display configurations matching Apple Sidecar behavior.
/// Sidecar uses fixed 2x HiDPI scaling with logical resolutions optimized for each iPad model.
/// These are the LOGICAL (point) resolutions - actual pixels are 2x these values.
enum iPadDisplayPreset {
    /// iPad Pro 12.9" (all generations) - ~4:3 aspect ratio
    /// Physical: 2732 × 2048 pixels, Sidecar logical: ~1366 × 1024 points
    case iPadPro129
    
    /// iPad Pro 11" (all generations) - ~4.3:3 aspect ratio  
    /// Physical: 2388 × 1668 pixels, Sidecar logical: ~1194 × 834 points
    case iPadPro11
    
    /// iPad Air 10.9" / iPad 10th gen - ~4.3:3 aspect ratio
    /// Physical: 2360 × 1640 pixels, Sidecar logical: ~1180 × 820 points
    case iPadAir109
    
    /// iPad mini 6th gen - ~4.3:3 aspect ratio
    /// Physical: 2266 × 1488 pixels, Sidecar logical: ~1133 × 744 points
    case iPadMini6
    
    /// iPad 9th gen and older - ~4:3 aspect ratio
    /// Physical: 2160 × 1620 pixels, Sidecar logical: ~1080 × 810 points
    case iPadStandard
    
    /// Unknown/generic iPad - use detected resolution with 2x scaling
    case generic(logicalWidth: Int, logicalHeight: Int)
    
    /// Logical resolution (points) - what macOS renders at
    /// Sidecar displays UI at this size for readable text
    var logicalResolution: (width: Int, height: Int) {
        switch self {
        case .iPadPro129:
            return (1366, 1024)  // ~1366×1024 Retina points
        case .iPadPro11:
            return (1194, 834)   // ~1194×834 Retina points
        case .iPadAir109:
            return (1180, 820)   // ~1180×820 Retina points
        case .iPadMini6:
            return (1133, 744)   // ~1133×744 Retina points
        case .iPadStandard:
            return (1080, 810)   // ~1080×810 Retina points
        case .generic(let w, let h):
            return (w, h)
        }
    }
    
    /// Physical resolution (pixels) - iPad's native panel resolution
    /// This is what the HEVC stream will be encoded at (2x logical)
    var physicalResolution: (width: Int, height: Int) {
        let logical = logicalResolution
        return (logical.width * 2, logical.height * 2)
    }
    
    /// Aspect ratio of the display
    var aspectRatio: Double {
        let logical = logicalResolution
        return Double(logical.width) / Double(logical.height)
    }
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .iPadPro129:
            return "iPad Pro 12.9\""
        case .iPadPro11:
            return "iPad Pro 11\""
        case .iPadAir109:
            return "iPad Air 10.9\""
        case .iPadMini6:
            return "iPad mini"
        case .iPadStandard:
            return "iPad"
        case .generic:
            return "iPad (Custom)"
        }
    }
    
    /// Detect iPad preset from device model string and screen dimensions.
    /// This mimics how macOS identifies iPad hardware during Sidecar handshake.
    ///
    /// - Parameters:
    ///   - deviceModel: The device model string (e.g., "iPad Pro 12.9-inch")
    ///   - physicalWidth: Physical screen width in pixels (landscape)
    ///   - physicalHeight: Physical screen height in pixels (landscape)
    /// - Returns: The matching iPad display preset
    static func detect(deviceModel: String?, physicalWidth: Int, physicalHeight: Int) -> iPadDisplayPreset {
        // Ensure landscape orientation (width > height)
        let width = max(physicalWidth, physicalHeight)
        let height = min(physicalWidth, physicalHeight)
        
        // First try to match by device model string
        if let model = deviceModel?.lowercased() {
            if model.contains("12.9") || model.contains("12,9") {
                return .iPadPro129
            }
            if model.contains("11") && model.contains("pro") {
                return .iPadPro11
            }
            if model.contains("mini") {
                return .iPadMini6
            }
            if model.contains("air") || model.contains("10.9") {
                return .iPadAir109
            }
        }
        
        // Fallback: match by physical resolution
        // iPad Pro 12.9": 2732 × 2048
        if width >= 2700 && height >= 2000 {
            return .iPadPro129
        }
        // iPad Pro 11": 2388 × 1668
        if width >= 2350 && width < 2400 && height >= 1600 && height < 1700 {
            return .iPadPro11
        }
        // iPad Air 10.9": 2360 × 1640
        if width >= 2300 && width < 2400 && height >= 1600 && height < 1700 {
            return .iPadAir109
        }
        // iPad mini 6: 2266 × 1488
        if width >= 2200 && width < 2300 && height >= 1400 && height < 1550 {
            return .iPadMini6
        }
        // iPad standard: 2160 × 1620 (or similar)
        if width >= 2100 && width < 2200 {
            return .iPadStandard
        }
        
        // Generic fallback: calculate logical resolution with 2x scaling
        // Cap to reasonable bounds to avoid overly large virtual displays
        let logicalW = min(1920, width / 2)
        let logicalH = min(1200, height / 2)
        return .generic(logicalWidth: logicalW, logicalHeight: logicalH)
    }
}
