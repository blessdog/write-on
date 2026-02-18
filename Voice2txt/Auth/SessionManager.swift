import Foundation
import Security

class SessionManager {
    static let shared = SessionManager()

    private let keychainService = "com.writeon.app.auth"
    private let accessTokenAccount = "access_token"
    private let refreshTokenAccount = "refresh_token"
    private let expiresAtAccount = "expires_at"
    private let userIdAccount = "user_id"
    private let emailAccount = "email"

    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var cachedExpiresAt: Date?
    private var cachedUserId: String?
    private var cachedEmail: String?

    private init() {
        loadFromKeychain()
    }

    var isLoggedIn: Bool {
        return cachedAccessToken != nil && cachedRefreshToken != nil
    }

    var email: String? { cachedEmail }
    var userId: String? { cachedUserId }
    var accessToken: String? { cachedAccessToken }
    var refreshToken: String? { cachedRefreshToken }

    func saveSession(_ session: AuthSession) {
        cachedAccessToken = session.accessToken
        cachedRefreshToken = session.refreshToken
        cachedExpiresAt = session.expiresAt
        cachedUserId = session.userId
        cachedEmail = session.email

        saveToKeychain(session.accessToken, account: accessTokenAccount)
        saveToKeychain(session.refreshToken, account: refreshTokenAccount)
        saveToKeychain(String(session.expiresAt.timeIntervalSince1970), account: expiresAtAccount)
        saveToKeychain(session.userId, account: userIdAccount)
        saveToKeychain(session.email, account: emailAccount)
    }

    func getValidToken() async throws -> String {
        guard let accessToken = cachedAccessToken, let refreshToken = cachedRefreshToken else {
            throw AuthError.serverError("Not logged in")
        }

        // If token expires in less than 5 minutes, refresh
        let buffer: TimeInterval = 5 * 60
        if let expiresAt = cachedExpiresAt, expiresAt.timeIntervalSinceNow < buffer {
            let newSession = try await AuthManager.shared.refreshToken(refreshToken)
            saveSession(newSession)
            return newSession.accessToken
        }

        return accessToken
    }

    func clearSession() {
        cachedAccessToken = nil
        cachedRefreshToken = nil
        cachedExpiresAt = nil
        cachedUserId = nil
        cachedEmail = nil

        deleteFromKeychain(account: accessTokenAccount)
        deleteFromKeychain(account: refreshTokenAccount)
        deleteFromKeychain(account: expiresAtAccount)
        deleteFromKeychain(account: userIdAccount)
        deleteFromKeychain(account: emailAccount)
    }

    // MARK: - Keychain

    private func loadFromKeychain() {
        cachedAccessToken = loadFromKeychain(account: accessTokenAccount)
        cachedRefreshToken = loadFromKeychain(account: refreshTokenAccount)
        cachedUserId = loadFromKeychain(account: userIdAccount)
        cachedEmail = loadFromKeychain(account: emailAccount)

        if let expiresStr = loadFromKeychain(account: expiresAtAccount),
           let interval = TimeInterval(expiresStr) {
            cachedExpiresAt = Date(timeIntervalSince1970: interval)
        }
    }

    private func saveToKeychain(_ value: String, account: String) {
        let data = value.data(using: .utf8)!

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: data,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
