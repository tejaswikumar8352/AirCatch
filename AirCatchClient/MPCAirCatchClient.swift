//
//  MPCAirCatchClient.swift
//  AirCatchClient
//
//  MultipeerConnectivity-based “AirCatch” link (Sidecar-like close-range P2P).
//

import Foundation
import MultipeerConnectivity

@MainActor
final class MPCAirCatchClient: NSObject {
    // Service type must be 1–15 chars, lowercase letters/numbers/hyphen.
    private static let serviceType = "aircatch"

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    private var discovered: [String: MCPeerID] = [:] // peer.displayName -> peer

    var onHostFound: ((MCPeerID, [String: String]?) -> Void)?
    var onHostLost: ((MCPeerID) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?
    var onPacketReceived: ((Packet) -> Void)?

    override init() {
        let name = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: name)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        self.browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()

        session.delegate = self
        browser.delegate = self
    }

    func startBrowsing() {
        browser.startBrowsingForPeers()
    }

    func stop() {
        browser.stopBrowsingForPeers()
        discovered.removeAll()
    }

    func disconnect() {
        session.disconnect()
    }

    func peer(named displayName: String) -> MCPeerID? {
        discovered[displayName]
    }

    func connect(to peer: MCPeerID) {
        // Context can later carry pairing metadata. For now we invite and do PIN in handshake.
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
    }

    func send(type: PacketType, payload: Data, mode: MCSessionSendDataMode) {
        guard !session.connectedPeers.isEmpty else { return }
        let datagram = Self.buildDatagram(type: type, payload: payload)
        do {
            try session.send(datagram, toPeers: session.connectedPeers, with: mode)
        } catch {
            // Best-effort: transport will fall back via ClientManager timeout/reconnect logic.
            AirCatchLog.error(" send failed: \(error)")
        }
    }

    private nonisolated static func buildDatagram(type: PacketType, payload: Data) -> Data {
        var data = Data()
        data.reserveCapacity(1 + payload.count)
        data.append(type.rawValue)
        data.append(payload)
        return data
    }

    private nonisolated static func parseDatagram(_ data: Data) -> Packet? {
        guard let first = data.first, let type = PacketType(rawValue: first) else { return nil }
        return Packet(type: type, payload: Data(data.dropFirst()))
    }
}

extension MPCAirCatchClient: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            self.discovered[peerID.displayName] = peerID
            self.onHostFound?(peerID, info)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discovered.removeValue(forKey: peerID.displayName)
            self.onHostLost?(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        AirCatchLog.error(" browse failed: \(error)")
    }
}

extension MPCAirCatchClient: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.onConnected?()
            case .notConnected:
                self.onDisconnected?()
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = Self.parseDatagram(data) else { return }
        Task { @MainActor in
            self.onPacketReceived?(packet)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
