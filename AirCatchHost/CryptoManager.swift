//
//  CryptoManager.swift
//  AirCatchHost
//
//  End-to-end encryption using PIN-derived AES-256-GCM.
//  Implements challenge-response PIN verification to avoid plaintext PIN transmission.
//

import Foundation
import CryptoKit
import CommonCrypto

/// Provides end-to-end encryption using AES-256-GCM with PIN-derived key.
/// This ensures neither network sniffers nor intermediaries can read data.
final class CryptoManager {
    private var key: SymmetricKey?
    private let lock = NSLock()
    
    // SECURITY: Use unique, version-tagged salts for different derivation purposes
    private static let encryptionSalt = "AirCatch-E2EE-v2-encryption".data(using: .utf8)!
    private static let authSalt = "AirCatch-E2EE-v2-auth".data(using: .utf8)!
    private nonisolated static let pbkdfRounds: UInt32 = 200_000
    private nonisolated static let derivedKeyLength: Int = 32
    
    // SECURITY: Current challenge for PIN verification (host-side)
    private var currentChallenge: Data?
    
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
    
    /// Generates a random 32-byte challenge for PIN verification.
    /// Call this on the host when a client connects.
    func generateChallenge() -> Data {
        var challenge = Data(count: 32)
        challenge.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        lock.lock()
        currentChallenge = challenge
        lock.unlock()
        return challenge
    }
    
    /// Computes the expected response for a given challenge and PIN (host-side verification).
    /// Returns nil if no key is derived yet.
    func computeChallengeResponse(challenge: Data, pin: String) -> Data? {
        guard let authKeyData = Self.deriveKeyMaterial(pin: pin, salt: Self.authSalt) else {
            return nil
        }
        let authKey = SymmetricKey(data: authKeyData)
        
        // HMAC the challenge with the auth key
        let hmac = HMAC<SHA256>.authenticationCode(for: challenge, using: authKey)
        return Data(hmac)
    }
    
    /// Verifies a client's challenge response against the expected value.
    /// Returns true if the response matches (client knows the correct PIN).
    func verifyChallengeResponse(_ response: Data, expectedPIN: String) -> Bool {
        lock.lock()
        guard let challenge = currentChallenge else {
            lock.unlock()
            #if DEBUG
            AirCatchLog.error("E2EE: No challenge set for verification", category: .network)
            #endif
            return false
        }
        lock.unlock()
        
        guard let expected = computeChallengeResponse(challenge: challenge, pin: expectedPIN) else {
            return false
        }
        
        // Constant-time comparison to prevent timing attacks
        guard response.count == expected.count else { return false }
        var result: UInt8 = 0
        for (a, b) in zip(response, expected) {
            result |= a ^ b
        }
        return result == 0
    }
    
    /// Clears the current challenge after verification.
    func clearChallenge() {
        lock.lock()
        currentChallenge = nil
        lock.unlock()
    }
    
    /// Derives a 256-bit AES key from the PIN using PBKDF2-HMAC-SHA256.
    /// Call this when PIN is generated (host) or entered (client).
    func deriveKey(from pin: String) {
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
    
    /// Clears the encryption key (call on disconnect).
    func clearKey() {
        lock.lock()
        key = nil
        lock.unlock()
    }
    
    /// Returns true if encryption is ready.
    var isReady: Bool {
        lock.lock()
        let ready = key != nil
        lock.unlock()
        return ready
    }
    
    /// Encrypts plaintext data using AES-256-GCM.
    /// Returns: nonce (12) + ciphertext + tag (16), or nil on failure.
    func encrypt(_ plaintext: Data) -> Data? {
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
    func decrypt(_ ciphertext: Data) -> Data? {
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
