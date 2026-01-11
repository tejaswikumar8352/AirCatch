//
//  MPCAirCatchHost.swift
//  AirCatchHost
//
//  MultipeerConnectivity-based “AirCatch” link (Sidecar-like close-range P2P).
//

import Foundation
import MultipeerConnectivity

@MainActor
final class MPCAirCatchHost: NSObject {
    // Service type must be 1–15 chars, lowercase letters/numbers/hyphen.
    private static let serviceType = "aircatch"

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser

    var onPacketReceived: ((Packet, MCPeerID) -> Void)?
    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    override init() {
        let hostName = Host.current().localizedName ?? "Mac"
        self.myPeerID = MCPeerID(displayName: hostName)
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)

        let discoveryInfo: [String: String] = [
            "name": hostName,
            "hostId": Self.getOrCreateHostId()
        ]
        self.advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: discoveryInfo, serviceType: Self.serviceType)

        super.init()

        session.delegate = self
        advertiser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
    }

    var hasConnectedPeers: Bool {
        !session.connectedPeers.isEmpty
    }

    func send(to peer: MCPeerID, type: PacketType, payload: Data, mode: MCSessionSendDataMode) {
        let datagram = Self.buildDatagram(type: type, payload: payload)
        do {
            try session.send(datagram, toPeers: [peer], with: mode)
        } catch {
            AirCatchLog.error(" send failed: \(error)")
        }
    }

    func broadcast(type: PacketType, payload: Data, mode: MCSessionSendDataMode) {
        guard !session.connectedPeers.isEmpty else { return }
        let datagram = Self.buildDatagram(type: type, payload: payload)
        do {
            try session.send(datagram, toPeers: session.connectedPeers, with: mode)
        } catch {
            AirCatchLog.error(" broadcast failed: \(error)")
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

    private static func getOrCreateHostId() -> String {
        let key = "com.aircatch.hostId"
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        defaults.set(newId, forKey: key)
        return newId
    }
}

extension MPCAirCatchHost: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept invitations; pairing is still enforced via PIN in the handshake.
        Task { @MainActor in
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        AirCatchLog.error(" advertise failed: \(error)")
    }
}

extension MPCAirCatchHost: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.onPeerConnected?(peerID)
            case .notConnected:
                self.onPeerDisconnected?(peerID)
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
            self.onPacketReceived?(packet, peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
