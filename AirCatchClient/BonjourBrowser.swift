//
//  BonjourBrowser.swift
//  AirCatchClient
//
//  Discovers AirCatch hosts on the local network via Bonjour.
//

import Foundation
import Network

/// Browses for AirCatch host services on the local network.
final class BonjourBrowser {
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.aircatch.bonjour.browser")
    
    var onHostFound: (@MainActor (DiscoveredHost) -> Void)?
    var onHostLost: (@MainActor (DiscoveredHost) -> Void)?
    
    /// Starts browsing for the specified Bonjour service type.
    func startBrowsing(serviceType: String) {
        guard browser == nil else { return }
        
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: "local.")
        // P2P Enabled Parameters for Browsing
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                AirCatchLog.info("Browsing for \(serviceType)", category: .network)
            case .failed(let error):
                AirCatchLog.error("Browse failed: \(error)", category: .network)
            case .cancelled:
                AirCatchLog.debug("Bonjour browser cancelled", category: .network)
            default:
                break
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self else { return }
            
            for change in changes {
                switch change {
                case .added(let result):
                    if case .service(let name, _, _, _) = result.endpoint {
                        let host = DiscoveredHost(
                            id: name,
                            name: name,
                            endpoint: result.endpoint,
                            isDirectIP: false
                        )
                        let handler = self.onHostFound
                        Task { @MainActor in
                            handler?(host)
                        }
                    }
                    
                case .removed(let result):
                    if case .service(let name, _, _, _) = result.endpoint {
                        let host = DiscoveredHost(
                            id: name,
                            name: name,
                            endpoint: result.endpoint,
                            isDirectIP: false
                        )
                        let handler = self.onHostLost
                        Task { @MainActor in
                            handler?(host)
                        }
                    }
                    
                default:
                    break
                }
            }
        }
        
        browser.start(queue: queue)
        self.browser = browser
    }
    
    /// Stops browsing.
    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }
}
