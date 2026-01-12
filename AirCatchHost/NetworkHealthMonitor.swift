//
//  NetworkHealthMonitor.swift
//  AirCatchHost
//
//  **Encoder-Aware Adaptive Mode**
//  Industry-leading approach: measures actual encoder output FPS and adjusts bitrate
//  to maintain smooth 60fps. Uses a PID-like control loop for stable convergence.
//

import Foundation
import Combine

/// Monitors encoder throughput and dynamically adjusts bitrate to maintain target FPS.
/// This is smarter than network-based adaptive because it directly measures the bottleneck.
@MainActor
final class NetworkHealthMonitor: ObservableObject {
    static let shared = NetworkHealthMonitor()
    
    // MARK: - Published State
    
    @Published private(set) var currentBitrate: Int = 15_000_000  // Start conservative (15 Mbps)
    @Published private(set) var actualFPS: Double = 0
    @Published private(set) var targetFPS: Int = 60
    @Published private(set) var isStable: Bool = false
    @Published private(set) var signalQuality: SignalQuality = .unknown
    @Published private(set) var averageRTT: Double = 0  // milliseconds
    
    // MARK: - Signal Quality (for P2P connections)
    
    enum SignalQuality: String {
        case excellent = "Excellent"  // RTT < 10ms
        case good = "Good"            // RTT 10-30ms
        case fair = "Fair"            // RTT 30-50ms
        case poor = "Poor"            // RTT > 50ms
        case unknown = "Unknown"
        
        /// Maximum bitrate allowed for this signal quality
        var maxBitrate: Int {
            switch self {
            case .excellent: return 50_000_000  // 50 Mbps
            case .good: return 35_000_000       // 35 Mbps
            case .fair: return 20_000_000       // 20 Mbps
            case .poor: return 10_000_000       // 10 Mbps
            case .unknown: return 50_000_000    // No limit if unknown
            }
        }
    }
    
    // MARK: - Configuration (Tuned for HEVC on Apple Silicon)
    
    private let minBitrate: Int = 5_000_000      // 5 Mbps floor
    private let maxBitrate: Int = 50_000_000     // 50 Mbps ceiling (encoder-friendly)
    private let bitrateStepUp: Int = 2_000_000   // Gentle step up (2 Mbps)
    private let bitrateStepDown: Int = 5_000_000 // Aggressive step down (5 Mbps)
    
    private let fpsThresholdLow: Double = 55.0   // Below this = encoder struggling
    private let fpsThresholdHigh: Double = 58.0  // Above this = headroom to increase
    
    // MARK: - RTT Tracking
    
    private var rttSamples: [Double] = []
    private let maxRTTSamples = 10
    
    // MARK: - Internal State
    
    private var adjustmentTimer: Timer?
    private var lastFrameCount: Int = 0
    private var lastSkippedCount: Int = 0  // For capture issue detection
    private var lastMeasurementTime: Date = Date()
    private var consecutiveStableReadings: Int = 0
    
    // Capture issue detection (to avoid reducing bitrate for capture problems)
    private(set) var captureSuccessRate: Double = 1.0
    private(set) var isCaptureIssue: Bool = false
    private var hasLoggedCaptureIssue: Bool = false
    
    // Warmup: Don't reduce bitrate for first few cycles (allow system to stabilize)
    private var adjustmentCount: Int = 0
    private let warmupCycles: Int = 3  // 6 seconds warmup (3 cycles × 2 seconds)
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start adaptive monitoring with proactive bitrate calculation
    /// - Parameters:
    ///   - clientWidth: Client's screen width (for resolution-based calculation)
    ///   - clientHeight: Client's screen height
    ///   - fps: Target FPS (default 60)
    func start(clientWidth: Int? = nil, clientHeight: Int? = nil, fps: Int = 60) {
        // Calculate optimal starting bitrate based on resolution
        if let width = clientWidth, let height = clientHeight, width > 0, height > 0 {
            let calculatedBitrate = BitrateCalculator.calculateOptimal(
                width: width,
                height: height,
                fps: fps,
                measuredBandwidth: nil  // TODO: Add network probe
            )
            currentBitrate = calculatedBitrate
            AirCatchLog.info("🧠 Proactive start: \(width)×\(height) → \(calculatedBitrate / 1_000_000) Mbps", category: .video)
        } else {
            currentBitrate = 15_000_000  // Fallback to 15 Mbps
        }
        
        // Reset state
        actualFPS = 0
        isStable = false
        consecutiveStableReadings = 0
        lastFrameCount = 0
        lastSkippedCount = 0
        adjustmentCount = 0  // Reset warmup counter
        lastMeasurementTime = Date()
        
        // Start measurement loop (every 2 seconds)
        adjustmentTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in
                self.measureAndAdjust()
            }
        }
        
        AirCatchLog.info("Encoder-Aware Adaptive started (Target: \(targetFPS)fps)", category: .video)
    }
    
    /// Stop monitoring
    func stop() {
        adjustmentTimer?.invalidate()
        adjustmentTimer = nil
        AirCatchLog.info("Encoder-Aware Adaptive stopped", category: .video)
    }
    
    /// Called by HostManager to update encoder stats
    /// - Parameters:
    ///   - frameCount: Total frames successfully encoded
    ///   - skippedCount: Frames skipped due to capture issues (no imageBuffer)
    func updateFromEncoder(frameCount: Int, skippedCount: Int = 0) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastMeasurementTime)
        
        guard elapsed > 0.5 else { return } // Ignore if too soon
        
        let framesDelta = frameCount - lastFrameCount
        let skippedDelta = skippedCount - lastSkippedCount
        
        actualFPS = Double(framesDelta) / elapsed
        
        // Detect capture issues: if many frames skipped, it's a capture problem, not encoder
        let totalAttempted = framesDelta + skippedDelta
        if totalAttempted > 0 {
            captureSuccessRate = Double(framesDelta) / Double(totalAttempted)
        }
        
        // If capture success rate is low, don't blame the encoder
        if captureSuccessRate < 0.7 && skippedDelta > 10 {
            isCaptureIssue = true
            if !hasLoggedCaptureIssue {
                AirCatchLog.info("⚠️ Capture issue detected: \(Int((1.0 - captureSuccessRate) * 100))% frames dropped (not encoder issue)", category: .video)
                hasLoggedCaptureIssue = true
            }
        } else {
            isCaptureIssue = false
            hasLoggedCaptureIssue = false
        }
        
        lastFrameCount = frameCount
        lastSkippedCount = skippedCount
        lastMeasurementTime = now
    }
    
    /// Record RTT sample from ping/pong for signal quality estimation
    /// - Parameter rttMs: Round-trip time in milliseconds
    func recordRTT(_ rttMs: Double) {
        rttSamples.append(rttMs)
        if rttSamples.count > maxRTTSamples {
            rttSamples.removeFirst()
        }
        
        // Calculate average RTT
        averageRTT = rttSamples.reduce(0, +) / Double(rttSamples.count)
        
        // Determine signal quality based on RTT
        let oldQuality = signalQuality
        switch averageRTT {
        case 0..<10:
            signalQuality = .excellent
        case 10..<30:
            signalQuality = .good
        case 30..<50:
            signalQuality = .fair
        default:
            signalQuality = .poor
        }
        
        // Log if quality changed
        if signalQuality != oldQuality && oldQuality != .unknown {
            AirCatchLog.info("📶 Signal: \(signalQuality.rawValue) (RTT: \(String(format: "%.0f", averageRTT))ms) → Max \(signalQuality.maxBitrate / 1_000_000) Mbps", category: .network)
        }
    }
    
    // MARK: - PID-like Control Loop
    
    private func measureAndAdjust() {
        // Safety: if no FPS data, don't adjust
        guard actualFPS > 0 else { return }
        
        // Calculate effective max bitrate (limited by signal quality for P2P)
        let effectiveMaxBitrate = min(maxBitrate, signalQuality.maxBitrate)
        
        // If current bitrate exceeds signal-based cap, reduce immediately
        if currentBitrate > effectiveMaxBitrate {
            currentBitrate = effectiveMaxBitrate
            AirCatchLog.info("📶 Signal cap: Bitrate → \(currentBitrate / 1_000_000) Mbps (Signal: \(signalQuality.rawValue))", category: .video)
        }
        
        if actualFPS < fpsThresholdLow {
            // Warmup: Don't reduce bitrate for first few cycles (allow system to stabilize)
            adjustmentCount += 1
            if adjustmentCount <= warmupCycles {
                AirCatchLog.debug("⏳ Warmup cycle \(adjustmentCount)/\(warmupCycles) - skipping bitrate reduction", category: .video)
                return
            }
            
            // Check if this is a capture issue (not encoder problem)
            if isCaptureIssue {
                // Don't reduce bitrate for capture issues - just wait for them to resolve
                isStable = false
                consecutiveStableReadings = 0
                return
            }
            
            // ENCODER IS STRUGGLING - Reduce bitrate immediately
            let newBitrate = max(currentBitrate - bitrateStepDown, minBitrate)
            if newBitrate != currentBitrate {
                currentBitrate = newBitrate
                isStable = false
                consecutiveStableReadings = 0
                AirCatchLog.info("📉 Adaptive: FPS=\(String(format: "%.1f", actualFPS)) → Bitrate DOWN to \(currentBitrate / 1_000_000) Mbps", category: .video)
            }
        } else if actualFPS >= fpsThresholdHigh && currentBitrate < effectiveMaxBitrate {
            // ENCODER HAS HEADROOM - Try increasing bitrate (gentle)
            consecutiveStableReadings += 1
            
            // Only increase after 3 consecutive stable readings (6 seconds)
            if consecutiveStableReadings >= 3 {
                let newBitrate = min(currentBitrate + bitrateStepUp, effectiveMaxBitrate)
                if newBitrate != currentBitrate {
                    currentBitrate = newBitrate
                    consecutiveStableReadings = 0
                    AirCatchLog.info("📈 Adaptive: FPS=\(String(format: "%.1f", actualFPS)) → Bitrate UP to \(currentBitrate / 1_000_000) Mbps", category: .video)
                }
            }
            isStable = true
        } else {
            // SWEET SPOT - Hold current bitrate
            isStable = true
            consecutiveStableReadings = 0
        }
    }
}
