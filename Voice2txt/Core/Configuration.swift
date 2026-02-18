import Foundation
import Security

enum Configuration {
    // Supabase
    static let supabaseURL = "https://oknhmmjpzkujiuhvwnuf.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9rbmhtbWpwemt1aml1aHZ3bnVmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyODIxOTksImV4cCI6MjA4Njg1ODE5OX0.mWu4uaUQTMS7jutA5_OBxU9H0GhKGRtcJ6Pc2nNWzCw"

    // Proxy WebSocket (Cloudflare Worker)
    static let proxyWSURL = "wss://voice2txt-proxy.rfanselman.workers.dev/ws"
    static let proxyHTTPURL = "https://voice2txt-proxy.rfanselman.workers.dev"

    // Keychain — legacy Deepgram key (kept for migration)
    private static let keychainService = "com.writeon.app.deepgram"
    private static let keychainAccount = "api_key"

    static func hasLegacyAPIKey() -> Bool {
        return loadAPIKey() != nil
    }

    static func loadAPIKey() -> String? {
        if let key = loadAPIKeyFromKeychain(), !key.isEmpty {
            return key
        }
        if let key = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"],
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let configPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/voice2txt/api_key").path
        if let key = try? String(contentsOfFile: configPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            saveAPIKeyToKeychain(key)
            return key
        }
        return nil
    }

    static func saveAPIKeyToKeychain(_ key: String) {
        let keyData = key.data(using: .utf8)!
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: keyData,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func removeLegacyAPIKey() {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
    }

    private static func loadAPIKeyFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }
}
