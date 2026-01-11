//
//  DriverKitClient.swift
//  AirCatchHost
//
//  Client for communicating with the AirCatchDisplayDriver DriverKit extension.
//  This provides the Swift interface to create and manage virtual displays.
//

import Foundation
import Combine
import CoreGraphics
import IOKit
import SystemExtensions

// MARK: - External Method Selectors (must match driver's enum)

private enum AirCatchDisplayDriverMethod: UInt64 {
    case connectDisplay = 0
    case disconnectDisplay = 1
    case getDisplayInfo = 2
    case getFramebuffer = 3
    case updateFramebuffer = 4
}

// MARK: - Display Configuration

struct VirtualDisplayConfiguration: Sendable {
    var width: UInt32
    var height: UInt32
    var refreshRate: UInt32
    
    nonisolated static let defaultiPadPro129 = VirtualDisplayConfiguration(
        width: 2732 / 2,  // Logical resolution (Retina)
        height: 2048 / 2,
        refreshRate: 60
    )
    
    nonisolated static let defaultiPadPro11 = VirtualDisplayConfiguration(
        width: 2388 / 2,
        height: 1668 / 2,
        refreshRate: 60
    )
    
    nonisolated static let default1080p = VirtualDisplayConfiguration(
        width: 1920,
        height: 1080,
        refreshRate: 60
    )
}

// MARK: - DriverKit Client

@MainActor
final class DriverKitClient: NSObject, ObservableObject {
    static let shared = DriverKitClient()
    
    // Driver connection
    private var connection: io_connect_t = 0
    private var isConnected = false
    
    // Published state
    @Published private(set) var driverInstalled = false
    @Published private(set) var driverActive = false
    @Published private(set) var displayConnected = false
    @Published private(set) var displayID: CGDirectDisplayID?
    @Published private(set) var displayFrame: CGRect = .zero
    @Published private(set) var lastError: String?
    
    // Extension activation
    private var activationRequest: OSSystemExtensionRequest?
    
    // Service name (must match Info.plist IOKitPersonalities key)
    private let serviceName = "AirCatchDisplayDriver"
    private let dextIdentifier = "com.aircatch.displaydriver"
    
    private override init() {
        super.init()
    }
    
    // MARK: - Driver Installation
    
    /// Request to install/activate the DriverKit system extension
    func installDriver() {
        AirCatchLog.info(" Requesting driver installation")
        
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: dextIdentifier,
            queue: .main
        )
        request.delegate = self
        
        activationRequest = request
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    /// Request to uninstall/deactivate the driver
    func uninstallDriver() {
        AirCatchLog.info(" Requesting driver uninstallation")
        
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: dextIdentifier,
            queue: .main
        )
        request.delegate = self
        
        OSSystemExtensionManager.shared.submitRequest(request)
    }
    
    // MARK: - Driver Connection
    
    /// Connect to the installed driver
    func connectToDriver() -> Bool {
        guard !isConnected else {
            AirCatchLog.info(" Already connected to driver")
            return true
        }
        
        // Find the service
        var iterator: io_iterator_t = 0
        let matchingDict = IOServiceMatching(serviceName)
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard result == KERN_SUCCESS else {
            lastError = "Failed to find driver service: \(result)"
            AirCatchLog.info(" \(lastError ?? "Unknown error")")
            return false
        }
        
        defer { IOObjectRelease(iterator) }
        
        // Get the first matching service
        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            lastError = "Driver service not found"
            AirCatchLog.info(" \(lastError ?? "Unknown error")")
            return false
        }
        
        defer { IOObjectRelease(service) }
        
        // Open a connection
        let openResult = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard openResult == KERN_SUCCESS else {
            lastError = "Failed to open driver connection: \(openResult)"
            AirCatchLog.info(" \(lastError ?? "Unknown error")")
            return false
        }
        
        isConnected = true
        driverActive = true
        AirCatchLog.info(" Connected to driver")
        return true
    }
    
    /// Disconnect from the driver
    func disconnectFromDriver() {
        guard isConnected else { return }
        
        IOServiceClose(connection)
        connection = 0
        isConnected = false
        driverActive = false
        
        AirCatchLog.info(" Disconnected from driver")
    }
    
    // MARK: - Virtual Display Control
    
    /// Create and connect a virtual display
    func connectDisplay(config: VirtualDisplayConfiguration = .default1080p) -> Bool {
        guard isConnected else {
            lastError = "Not connected to driver"
            return false
        }
        
        AirCatchLog.info(" Connecting display: \(config.width)x\(config.height) @ \(config.refreshRate)Hz")
        
        // Prepare input
        var input: [UInt64] = [
            UInt64(config.width),
            UInt64(config.height),
            UInt64(config.refreshRate)
        ]
        
        let inputCount = UInt32(input.count)
        
        // Call driver method
        let result = IOConnectCallScalarMethod(
            connection,
            UInt32(AirCatchDisplayDriverMethod.connectDisplay.rawValue),
            &input,
            inputCount,
            nil,
            nil
        )
        
        guard result == KERN_SUCCESS else {
            lastError = "Failed to connect display: \(result)"
            AirCatchLog.info(" \(lastError ?? "Unknown error")")
            return false
        }
        
        displayConnected = true
        displayFrame = CGRect(x: 0, y: 0, width: Int(config.width), height: Int(config.height))
        
        // Query for the actual display ID (would need to enumerate displays)
        findVirtualDisplayID()
        
        AirCatchLog.info(" Display connected successfully")
        return true
    }
    
    /// Disconnect the virtual display
    func disconnectDisplay() -> Bool {
        guard isConnected else { return false }
        
        AirCatchLog.info(" Disconnecting display")
        
        let result = IOConnectCallScalarMethod(
            connection,
            UInt32(AirCatchDisplayDriverMethod.disconnectDisplay.rawValue),
            nil,
            0,
            nil,
            nil
        )
        
        guard result == KERN_SUCCESS else {
            lastError = "Failed to disconnect display: \(result)"
            AirCatchLog.info(" \(lastError ?? "Unknown error")")
            return false
        }
        
        displayConnected = false
        displayID = nil
        displayFrame = .zero
        
        AirCatchLog.info(" Display disconnected")
        return true
    }
    
    /// Get current display information
    func getDisplayInfo() -> (width: UInt32, height: UInt32, refreshRate: UInt32, isConnected: Bool)? {
        guard isConnected else { return nil }
        
        var output: [UInt64] = [0, 0, 0, 0]
        var outputCount = UInt32(output.count)
        
        let result = IOConnectCallScalarMethod(
            connection,
            UInt32(AirCatchDisplayDriverMethod.getDisplayInfo.rawValue),
            nil,
            0,
            &output,
            &outputCount
        )
        
        guard result == KERN_SUCCESS else {
            AirCatchLog.info(" Failed to get display info: \(result)")
            return nil
        }
        
        return (
            width: UInt32(output[0]),
            height: UInt32(output[1]),
            refreshRate: UInt32(output[2]),
            isConnected: output[3] != 0
        )
    }
    
    // MARK: - Private Helpers
    
    private func findVirtualDisplayID() {
        // Enumerate displays to find the virtual one
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        
        // Look for a display matching our expected characteristics
        for display in displays {
            let bounds = CGDisplayBounds(display)
            if bounds.size == displayFrame.size {
                displayID = display
                displayFrame = bounds
                AirCatchLog.info(" Found virtual display: \(display) at \(bounds)")
                break
            }
        }
    }
}

// MARK: - System Extension Request Delegate

extension DriverKitClient: OSSystemExtensionRequestDelegate {
    nonisolated func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        AirCatchLog.info(" Replacing extension version \(existing.bundleVersion) with \(ext.bundleVersion)")
        return .replace
    }
    
    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        AirCatchLog.info(" Extension requires user approval in System Settings > Privacy & Security")
        Task { @MainActor in
            self.lastError = "Please approve the driver in System Settings > Privacy & Security"
        }
    }
    
    nonisolated func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        AirCatchLog.info(" Extension request finished with result: \(result.rawValue)")
        
        Task { @MainActor in
            switch result {
            case .completed:
                self.driverInstalled = true
                self.lastError = nil
                AirCatchLog.info(" Driver installed successfully")
                
                // Try to connect to the driver
                _ = self.connectToDriver()
                
            case .willCompleteAfterReboot:
                self.lastError = "Driver will be available after reboot"
                AirCatchLog.info(" Reboot required")
                
            @unknown default:
                self.lastError = "Unknown result: \(result.rawValue)"
            }
        }
    }
    
    nonisolated func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        AirCatchLog.info(" Extension request failed: \(error.localizedDescription)")
        
        Task { @MainActor in
            self.driverInstalled = false
            self.lastError = error.localizedDescription
        }
    }
}
