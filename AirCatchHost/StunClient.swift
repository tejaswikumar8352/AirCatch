//
//  StunClient.swift
//  AirCatchHost
//
//  Minimal STUN binding discovery (best-effort).
//

import Foundation
import Network

enum StunClient {
    struct MappedAddress {
        let ip: String
        let port: UInt16
    }

    static func discoverMappedAddress(
        host: String = "stun.l.google.com",
        port: UInt16 = 19302,
        timeout: TimeInterval = 2.0,
        completion: @escaping (MappedAddress?) -> Void
    ) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(nil)
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .udp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                sendBindingRequest(on: connection, timeout: timeout, completion: completion)
            case .failed:
                completion(nil)
            default:
                break
            }
        }
        connection.start(queue: .global())
    }

    private static func sendBindingRequest(
        on connection: NWConnection,
        timeout: TimeInterval,
        completion: @escaping (MappedAddress?) -> Void
    ) {
        let transactionId = (0..<12).map { _ in UInt8.random(in: 0...255) }
        var request = Data()
        request.append(contentsOf: [0x00, 0x01]) // Binding Request
        request.append(contentsOf: [0x00, 0x00]) // Length
        request.append(contentsOf: [0x21, 0x12, 0xA4, 0x42]) // Magic cookie
        request.append(contentsOf: transactionId)

        connection.send(content: request, completion: .contentProcessed { _ in
            connection.receiveMessage { data, _, _, _ in
                let mapped = data.flatMap { parseBindingResponse($0, transactionId: transactionId) }
                completion(mapped)
                connection.cancel()
            }
        })

        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            completion(nil)
            connection.cancel()
        }
    }

    private static func parseBindingResponse(_ data: Data, transactionId: [UInt8]) -> MappedAddress? {
        guard data.count >= 20 else { return nil }
        let messageType = UInt16(data[0]) << 8 | UInt16(data[1])
        guard messageType == 0x0101 else { return nil }

        let magicCookie = [UInt8](data[4..<8])
        guard magicCookie == [0x21, 0x12, 0xA4, 0x42] else { return nil }

        let receivedTransaction = [UInt8](data[8..<20])
        guard receivedTransaction == transactionId else { return nil }

        var offset = 20
        while offset + 4 <= data.count {
            let attrType = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let attrLen = Int(UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3]))
            offset += 4

            if attrType == 0x0020, offset + attrLen <= data.count {
                // XOR-MAPPED-ADDRESS
                let family = data[offset + 1]
                let xPort = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
                let port = xPort ^ 0x2112

                if family == 0x01 { // IPv4
                    let xAddress = [UInt8](data[(offset + 4)..<(offset + 8)])
                    let address = zip(xAddress, [0x21, 0x12, 0xA4, 0x42]).map { $0 ^ $1 }
                    let ip = address.map(String.init).joined(separator: ".")
                    return MappedAddress(ip: ip, port: port)
                }
            }

            offset += attrLen
        }

        return nil
    }
}
