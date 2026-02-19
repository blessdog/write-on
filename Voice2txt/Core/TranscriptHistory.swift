import Foundation
import Security
import CryptoKit

struct TranscriptEntry: Codable {
    let text: String
    let timestamp: Date
    let durationSeconds: Double

    var preview: String {
        let maxLen = 60
        if text.count <= maxLen { return text }
        return String(text.prefix(maxLen)) + "..."
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

class TranscriptHistory {
    static let shared = TranscriptHistory()

    private let maxEntries = 20
    private let storageKey = "com.writeon.app.transcript-history"
    private var entries: [TranscriptEntry] = []

    private init() {
        entries = loadEncrypted()
    }

    var history: [TranscriptEntry] { entries }
    var mostRecent: TranscriptEntry? { entries.first }

    func addTranscript(_ text: String, durationSeconds: Double = 0) {
        let entry = TranscriptEntry(
            text: text,
            timestamp: Date(),
            durationSeconds: durationSeconds
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        saveEncrypted()
    }

    func clearHistory() {
        entries.removeAll()
        saveEncrypted()
    }

    // MARK: - AES-GCM Encryption

    private func aesEncrypt(data: Data, key: Data) -> Data? {
        let symmetricKey = SymmetricKey(data: key)
        guard let sealedBox = try? AES.GCM.seal(data, using: symmetricKey) else { return nil }
        return sealedBox.combined
    }

    private func aesDecrypt(data: Data, key: Data) -> Data? {
        let symmetricKey = SymmetricKey(data: key)
        guard let sealedBox = try? AES.GCM.SealedBox(combined: data),
              let decrypted = try? AES.GCM.open(sealedBox, using: symmetricKey) else { return nil }
        return decrypted
    }

    // Keep for migrating v2.x data
    private func xorDecrypt(data: Data, key: Data) -> Data {
        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ key[i % key.count]
        }
        return result
    }

    // MARK: - Encrypted storage using Keychain

    private func saveEncrypted() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        guard let encrypted = aesEncrypt(data: data, key: getOrCreateEncryptionKey()) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: storageKey,
            kSecAttrAccount as String: "history",
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: storageKey,
            kSecAttrAccount as String: "history",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: encrypted,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadEncrypted() -> [TranscriptEntry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: storageKey,
            kSecAttrAccount as String: "history",
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let encrypted = result as? Data else {
            return []
        }

        let key = getOrCreateEncryptionKey()

        // Try AES-GCM first (v3.0+ format)
        if let decrypted = aesDecrypt(data: encrypted, key: key),
           let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: decrypted) {
            return entries
        }

        // Fall back to XOR (v2.x format) and migrate
        let xorDecrypted = xorDecrypt(data: encrypted, key: key)
        if let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: xorDecrypted) {
            // One-time migration: re-save as AES
            self.entries = entries
            saveEncrypted()
            return entries
        }

        // Both failed — corrupted data
        return []
    }

    private func getOrCreateEncryptionKey() -> Data {
        let keyService = "com.writeon.app.encryption"
        let keyAccount = "history-key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let keyData = result as? Data {
            return keyData
        }

        // Generate new 32-byte random key
        var keyData = Data(count: 32)
        keyData.withUnsafeMutableBytes { ptr in
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, ptr.baseAddress!)
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keyService,
            kSecAttrAccount as String: keyAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: keyData,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)

        return keyData
    }
}
