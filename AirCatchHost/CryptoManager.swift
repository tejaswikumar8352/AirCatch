//
//  CryptoManager.swift
//  AirCatchHost
//
//  End-to-end encryption using PIN-derived AES-256-GCM.
//  Implements challenge-response PIN verification to avoid plaintext PIN transmission.
//

import Foundation
import CryptoKit

/// Provides end-to-end encryption using AES-256-GCM with PIN-derived key.
/// This ensures neither network sniffers nor the relay server can read data.
final class CryptoManager {
    private var key: SymmetricKey?
    
    // SECURITY: Use unique, version-tagged salts for different derivation purposes
    private static let encryptionSalt = "AirCatch-E2EE-v2-encryption".data(using: .utf8)!
    private static let authSalt = "AirCatch-E2EE-v2-auth".data(using: .utf8)!
    private static let info = "AirCatch-Session".data(using: .utf8)!
    
    // SECURITY: Current challenge for PIN verification (host-side)
    private(set) var currentChallenge: Data?
    
    /// Generates a random 32-byte challenge for PIN verification.
    /// Call this on the host when a client connects.
    func generateChallenge() -> Data {
        var challenge = Data(count: 32)
        challenge.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        currentChallenge = challenge
        return challenge
    }
    
    /// Computes the expected response for a given challenge and PIN (host-side verification).
    /// Returns nil if no key is derived yet.
    func computeChallengeResponse(challenge: Data, pin: String) -> Data? {
        // Derive an authentication key from PIN (separate from encryption key)
        let pinData = Data(pin.utf8)
        let authKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pinData),
            salt: Self.authSalt,
            info: Self.info,
            outputByteCount: 32
        )
        
        // HMAC the challenge with the auth key
        let hmac = HMAC<SHA256>.authenticationCode(for: challenge, using: authKey)
        return Data(hmac)
    }
    
    /// Verifies a client's challenge response against the expected value.
    /// Returns true if the response matches (client knows the correct PIN).
    func verifyChallengeResponse(_ response: Data, expectedPIN: String) -> Bool {
        guard let challenge = currentChallenge else {
            #if DEBUG
            AirCatchLog.error("E2EE: No challenge set for verification", category: .network)
            #endif
            return false
        }
        
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
        currentChallenge = nil
    }
    
    /// Derives a 256-bit AES key from the PIN using HKDF.
    /// Call this when PIN is generated (host) or entered (client).
    func deriveKey(from pin: String) {
        guard !pin.isEmpty else {
            key = nil
            return
        }
        
        let pinData = Data(pin.utf8)
        
        // Use HKDF to derive a strong key from the short PIN
        // Salt ensures different apps with same PIN get different keys
        // Info adds context to the derivation
        key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: pinData),
            salt: Self.encryptionSalt,
            info: Self.info,
            outputByteCount: 32  // 256 bits for AES-256
        )
        
        #if DEBUG
        AirCatchLog.info("E2EE: Key derived from PIN", category: .network)
        #endif
    }
    
    /// Clears the encryption key (call on disconnect).
    func clearKey() {
        key = nil
    }
    
    /// Returns true if encryption is ready.
    var isReady: Bool {
        key != nil
    }
    
    /// Encrypts plaintext data using AES-256-GCM.
    /// Returns: nonce (12) + ciphertext + tag (16), or nil on failure.
    func encrypt(_ plaintext: Data) -> Data? {
        guard let key = key else {
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
        guard let key = key else {
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
