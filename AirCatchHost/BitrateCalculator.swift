//
//  BitrateCalculator.swift
//  AirCatchHost
//
//  **Proactive Bitrate Intelligence**
//  Calculates optimal bitrate based on:
//  1. Client resolution (pixels × bits-per-pixel × fps)
//  2. Network bandwidth (measured via probe)
//  3. Encoder capability (learned from history)
//

import Foundation

/// Calculates optimal streaming bitrate based on resolution and network conditions.
struct BitrateCalculator {
    
    // MARK: - Constants (Tuned for HEVC on Apple Silicon)
    
    /// Bits per pixel for HEVC at "good" quality (industry standard: 0.05-0.15 for HEVC)
    /// Lower = more compression, higher = better quality
    /// 0.07 is a sweet spot for screen content (sharp text, flat colors)
    static let bitsPerPixel: Double = 0.07
    
    /// Minimum acceptable bitrate (floor)
    static let minimumBitrate: Int = 5_000_000  // 5 Mbps
    
    /// Maximum bitrate (encoder-friendly ceiling)
    static let maximumBitrate: Int = 50_000_000 // 50 Mbps
    
    /// Safety margin for network bandwidth (use only 70% of measured speed)
    static let networkSafetyMargin: Double = 0.70
    
    // MARK: - Resolution-Based Calculation
    
    /// Calculates theoretical bitrate needed for given resolution and frame rate.
    /// Formula: pixels × bpp × fps
    ///
    /// Example:
    ///   - iPad Pro 12.9": 2732 × 2048 = 5,595,136 pixels
    ///   - At 60fps with 0.07 bpp: 5,595,136 × 0.07 × 60 = 23.5 Mbps
    ///
    /// - Parameters:
    ///   - width: Client display width in pixels
    ///   - height: Client display height in pixels
    ///   - fps: Target frames per second
    /// - Returns: Calculated bitrate in bits per second
    static func calculateForResolution(width: Int, height: Int, fps: Int = 60) -> Int {
        let pixels = Double(width * height)
        let theoreticalBitrate = pixels * bitsPerPixel * Double(fps)
        
        // Clamp to min/max bounds
        let clampedBitrate = max(Double(minimumBitrate), min(theoreticalBitrate, Double(maximumBitrate)))
        
        AirCatchLog.info("📐 Resolution-based bitrate: \(width)×\(height) @ \(fps)fps → \(Int(clampedBitrate) / 1_000_000) Mbps", category: .video)
        
        return Int(clampedBitrate)
    }
    
    // MARK: - Network-Aware Calculation
    
    /// Combines resolution-based calculation with measured network bandwidth.
    /// Uses the LOWER of the two to ensure smooth streaming.
    ///
    /// - Parameters:
    ///   - width: Client display width
    ///   - height: Client display height
    ///   - fps: Target FPS
    ///   - measuredBandwidth: Network bandwidth in bps (optional, from probe)
    /// - Returns: Optimal bitrate that respects both resolution needs and network capacity
    static func calculateOptimal(
        width: Int,
        height: Int,
        fps: Int = 60,
        measuredBandwidth: Int? = nil
    ) -> Int {
        // Step 1: Calculate resolution-based bitrate
        let resolutionBitrate = calculateForResolution(width: width, height: height, fps: fps)
        
        // Step 2: If we have network measurement, cap to safe bandwidth
        if let bandwidth = measuredBandwidth, bandwidth > 0 {
            let safeBandwidth = Int(Double(bandwidth) * networkSafetyMargin)
            let optimalBitrate = min(resolutionBitrate, safeBandwidth)
            
            AirCatchLog.info("🌐 Network-capped bitrate: measured=\(bandwidth / 1_000_000)Mbps, safe=\(safeBandwidth / 1_000_000)Mbps → using \(optimalBitrate / 1_000_000) Mbps", category: .network)
            
            return max(minimumBitrate, optimalBitrate)
        }
        
        // No network measurement available, use resolution-based only
        return resolutionBitrate
    }
    
    // MARK: - Quality Descriptions
    
    /// Returns a human-readable quality level for a given bitrate.
    static func qualityDescription(for bitrate: Int) -> String {
        switch bitrate {
        case 0..<10_000_000:
            return "Low (fast network)"
        case 10_000_000..<25_000_000:
            return "Medium (balanced)"
        case 25_000_000..<40_000_000:
            return "High (good quality)"
        default:
            return "Ultra (maximum quality)"
        }
    }
}
