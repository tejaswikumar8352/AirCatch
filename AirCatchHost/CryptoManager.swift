//
//  CryptoManager.swift
//  AirCatchHost
//
//  End-to-end encryption using PIN-derived AES-256-GCM.
//

import Foundation
import CryptoKit

/// Provides end-to-end encryption using AES-256-GCM with PIN-derived key.
/// This ensures neither network sniffers nor the relay server can read data.
final class CryptoManager {
    private var key: SymmetricKey?
    private static let salt = "AirCatch-E2EE-v1".data(using: .utf8)!
    private static let info = "AirCatch-Session".data(using: .utf8)!
    
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
            salt: Self.salt,
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
