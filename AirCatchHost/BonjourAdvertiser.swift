//
//  BonjourAdvertiser.swift
//  AirCatchHost
//
//  Advertises the host service via Bonjour/mDNS for auto-discovery.
//

import Foundation
import Network
import AppKit

/// Advertises the AirCatch host service on the local network.
final class BonjourAdvertiser {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.aircatch.bonjour")
    
    /// Starts advertising the service.
    /// - Parameters:
    ///   - serviceType: The Bonjour service type (e.g., "_aircatch._udp.")
    ///   - port: The port number to advertise
    ///   - name: The service name (typically the Mac's name)
    func startAdvertising(serviceType: String, port: UInt16, name: String) {
        stopAdvertising() // Stop any existing advertiser first
        
        do {
            // Create a listener that will advertise our service
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true
            // Don't restrict to wifi - allow Ethernet/USB connections too
            
            // Use ephemeral port for the advertiser - the actual service port is bound by NetworkManager
            // The service advertisement includes the port info in TXT record
            let listener = try NWListener(using: parameters)
            
            // Configure the service advertisement with the actual working port
            listener.service = NWListener.Service(
                name: name,
                type: serviceType,
                domain: "local.",
                txtRecord: createTXTRecord()
            )
            
            listener.serviceRegistrationUpdateHandler = { serviceChange in
                switch serviceChange {
                case .add(let endpoint):
                    AirCatchLog.info("Service registered: \(endpoint)", category: .network)
                case .remove(let endpoint):
                    AirCatchLog.debug("Service removed: \(endpoint)", category: .network)
                @unknown default:
                    break
                }
            }
            
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AirCatchLog.info("Started advertising '\(name)' as \(serviceType) on port \(port)", category: .network)
                case .failed(let error):
                    AirCatchLog.error("Bonjour listener failed: \(error)", category: .network)
                case .cancelled:
                    AirCatchLog.debug("Bonjour listener cancelled", category: .network)
                default:
                    break
                }
            }
            
            // We don't need to handle connections here - the main UDP listener does that
            listener.newConnectionHandler = { _ in }
            
            listener.start(queue: queue)
            self.listener = listener
            
        } catch {
            AirCatchLog.error("Failed to start advertising: \(error)", category: .network)
        }
    }
    
    /// Stops the Bonjour advertisement.
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        AirCatchLog.debug("Stopped advertising", category: .network)
    }
    
    /// Creates a TXT record with additional service metadata.
    private func createTXTRecord() -> NWTXTRecord {
        var record = NWTXTRecord()
        record["version"] = "1.0"
        record["platform"] = "macOS"
        
        // Include screen info
        if let screen = NSScreen.main {
            record["width"] = String(Int(screen.frame.width))
            record["height"] = String(Int(screen.frame.height))
        }
        
        return record
    }
}
