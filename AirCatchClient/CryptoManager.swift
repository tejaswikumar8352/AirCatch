//
//  CryptoManager.swift
//  AirCatchClient
//
//  End-to-end encryption using PIN-derived AES-256-GCM.
//  Implements challenge-response PIN verification to avoid plaintext PIN transmission.
//

import Foundation
import CryptoKit
import CommonCrypto

/// Provides end-to-end encryption using AES-256-GCM with PIN-derived key.
/// This ensures neither network sniffers nor intermediaries can read data.
nonisolated final class CryptoManager: @unchecked Sendable {
    private var key: SymmetricKey?
    private let lock = NSLock()
    
    // SECURITY: Use unique, version-tagged salts for different derivation purposes
    private static let encryptionSalt = "AirCatch-E2EE-v2-encryption".data(using: .utf8)!
    private static let authSalt = "AirCatch-E2EE-v2-auth".data(using: .utf8)!
    private nonisolated static let pbkdfRounds: UInt32 = 200_000
    private nonisolated static let derivedKeyLength: Int = 32
    
    private static func deriveKeyMaterial(pin: String, salt: Data) -> Data? {
        var derived = Data(count: Self.derivedKeyLength)
        let passwordLength = pin.lengthOfBytes(using: .utf8)
        guard passwordLength > 0 else { return nil }
        
        let status = salt.withUnsafeBytes { saltBytes in
            derived.withUnsafeMutableBytes { derivedBytes in
                pin.withCString { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr,
                        passwordLength,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        Self.pbkdfRounds,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        Self.derivedKeyLength
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            #if DEBUG
            AirCatchLog.error("E2EE: PBKDF2 key derivation failed (\(status))", category: .network)
            #endif
            return nil
        }
        return derived
    }
    
    /// Computes a challenge response for PIN verification (client-side).
    /// The response is HMAC-SHA256(challenge, authKey) where authKey is derived from PIN.
    nonisolated func computeChallengeResponse(challenge: Data, pin: String) -> Data? {
        guard !pin.isEmpty else { return nil }
        
        guard let authKeyData = Self.deriveKeyMaterial(pin: pin, salt: Self.authSalt) else {
            return nil
        }
        let authKey = SymmetricKey(data: authKeyData)
        
        // HMAC the challenge with the auth key
        let hmac = HMAC<SHA256>.authenticationCode(for: challenge, using: authKey)
        return Data(hmac)
    }
    
    /// Derives a 256-bit AES key from the PIN using PBKDF2-HMAC-SHA256.
    /// Call this when PIN is generated (host) or entered (client).
    nonisolated func deriveKey(from pin: String) {
        guard !pin.isEmpty else {
            lock.lock()
            key = nil
            lock.unlock()
            return
        }
        
        guard let keyData = Self.deriveKeyMaterial(pin: pin, salt: Self.encryptionSalt) else {
            lock.lock()
            key = nil
            lock.unlock()
            return
        }
        lock.lock()
        key = SymmetricKey(data: keyData)
        lock.unlock()
        
        #if DEBUG
        AirCatchLog.info("E2EE: Key derived from PIN", category: .network)
        #endif
    }

    /// Installs a raw 256-bit key directly (the persistent pairing media key).
    /// Used after a successful pairing handshake instead of the PIN-derived key, so
    /// reconnecting is independent of the host's current PIN.
    nonisolated func setRawKey(_ data: Data) {
        guard !data.isEmpty else {
            lock.lock()
            key = nil
            lock.unlock()
            return
        }
        lock.lock()
        key = SymmetricKey(data: data)
        lock.unlock()
    }

    /// Decrypts a payload that was sealed with a PIN-derived key, WITHOUT touching
    /// the installed session key. Used to unwrap the persistent media key delivered
    /// during initial pairing.
    nonisolated func unwrapWithPIN(_ ciphertext: Data, pin: String) -> Data? {
        guard let keyData = Self.deriveKeyMaterial(pin: pin, salt: Self.encryptionSalt) else {
            return nil
        }
        guard ciphertext.count >= 29 else { return nil }
        let wrappingKey = SymmetricKey(data: keyData)
        guard let box = try? AES.GCM.SealedBox(combined: ciphertext) else { return nil }
        return try? AES.GCM.open(box, using: wrappingKey)
    }

    /// Clears the encryption key (call on disconnect).
    nonisolated func clearKey() {
        lock.lock()
        key = nil
        lock.unlock()
    }
    
    /// Returns true if encryption is ready.
    nonisolated var isReady: Bool {
        lock.lock()
        let ready = key != nil
        lock.unlock()
        return ready
    }
    
    /// Encrypts plaintext data using AES-256-GCM.
    /// Returns: nonce (12) + ciphertext + tag (16), or nil on failure.
    nonisolated func encrypt(_ plaintext: Data) -> Data? {
        lock.lock()
        let key = key
        lock.unlock()
        guard let key else {
            #if DEBUG
            AirCatchLog.error("E2EE: Encrypt failed - no key", category: .network)
            #endif
            return nil
        }
        
        do {
            let sealed = try AES.GCM.seal(plaintext, using: key)
            return sealed.combined  // nonce + ciphertext + tag
        } catch {
            #if DEBUG
            AirCatchLog.error("E2EE: Encrypt failed - \(error)", category: .network)
            #endif
            return nil
        }
    }
    
    /// Decrypts ciphertext (nonce + ciphertext + tag) using AES-256-GCM.
    /// Returns plaintext or nil if decryption fails (wrong key, tampered data).
    nonisolated func decrypt(_ ciphertext: Data) -> Data? {
        lock.lock()
        let key = key
        lock.unlock()
        guard let key else {
            #if DEBUG
            AirCatchLog.error("E2EE: Decrypt failed - no key", category: .network)
            #endif
            return nil
        }
        
        // Minimum size: 12 (nonce) + 1 (data) + 16 (tag) = 29 bytes
        guard ciphertext.count >= 29 else {
            #if DEBUG
            AirCatchLog.error("E2EE: Decrypt failed - data too short", category: .network)
            #endif
            return nil
        }
        
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            #if DEBUG
            AirCatchLog.error("E2EE: Decrypt failed - \(error)", category: .network)
            #endif
            return nil
        }
    }
}
