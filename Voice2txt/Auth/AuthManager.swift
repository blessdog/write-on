import Foundation

struct AuthSession {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let expiresAt: Date
    let userId: String
    let email: String
}

enum AuthError: LocalizedError {
    case invalidResponse
    case serverError(String)
    case networkError(Error)
    case confirmationRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .serverError(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        case .confirmationRequired: return "Check your email for a confirmation link, then sign in."
        }
    }
}

class AuthManager {
    static let shared = AuthManager()

    private let supabaseURL = "https://oknhmmjpzkujiuhvwnuf.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9rbmhtbWpwemt1aml1aHZ3bnVmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEyODIxOTksImV4cCI6MjA4Njg1ODE5OX0.mWu4uaUQTMS7jutA5_OBxU9H0GhKGRtcJ6Pc2nNWzCw"

    private init() {}

    func configure(url: String, anonKey: String) {
        // Allow runtime configuration for testing
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        let url = URL(string: "\(supabaseURL)/auth/v1/signup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }

        if http.statusCode >= 400 {
            let msg = json["error_description"] as? String
                ?? json["msg"] as? String
                ?? json["error"] as? String
                ?? "Unknown error"
            throw AuthError.serverError(msg)
        }

        // If email confirmation is required, Supabase returns user object without tokens
        if json["access_token"] == nil {
            throw AuthError.confirmationRequired
        }

        return try parseAuthResponse(data: data, response: response)
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email, "password": password]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try parseAuthResponse(data: data, response: response)
    }

    func refreshToken(_ refreshToken: String) async throws -> AuthSession {
        let url = URL(string: "\(supabaseURL)/auth/v1/token?grant_type=refresh_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try parseAuthResponse(data: data, response: response)
    }

    func resetPassword(email: String) async throws {
        let url = URL(string: "\(supabaseURL)/auth/v1/recover")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        let body: [String: String] = ["email": email]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.serverError("Failed to send reset email")
        }
    }

    func getGoogleOAuthURL() -> URL {
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: "https://write-on.app/auth/callback/"),
        ]
        return components.url!
    }

    func sessionFromOAuthFragment(_ fragment: String) throws -> AuthSession {
        // Parse URL fragment: access_token=...&refresh_token=...&expires_in=...
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = String(kv[0])
                let value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                params[key] = value
            }
        }

        guard let accessToken = params["access_token"],
              let refreshToken = params["refresh_token"],
              let expiresInStr = params["expires_in"],
              let expiresIn = Int(expiresInStr) else {
            throw AuthError.invalidResponse
        }

        // Decode user info directly from JWT (avoids network call)
        let (userId, email) = decodeJWT(accessToken)

        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            userId: userId,
            email: email
        )
    }

    /// Decode a Supabase JWT to extract sub (userId) and email claims
    private func decodeJWT(_ token: String) -> (userId: String, email: String) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return ("", "") }

        var base64 = String(parts[1])
        // Pad to multiple of 4 for base64 decoding
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        // JWT uses base64url encoding
        base64 = base64.replacingOccurrences(of: "-", with: "+")
                        .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("", "")
        }

        let userId = json["sub"] as? String ?? ""
        let email = json["email"] as? String ?? ""
        return (userId, email)
    }

    func fetchUser(accessToken: String) async throws -> (userId: String, email: String) {
        let url = URL(string: "\(supabaseURL)/auth/v1/user")!
        var request = URLRequest(url: url)
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }

        let userId = json["id"] as? String ?? ""
        let email = json["email"] as? String ?? ""
        return (userId, email)
    }

    func fetchUserStatus(accessToken: String) async throws -> UserStatus {
        let url = URL(string: "wss://voice2txt-proxy.rfanselman.workers.dev/user/status".replacingOccurrences(of: "wss://", with: "https://"))!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }

        return UserStatus(
            subscription: json["subscription"] as? String ?? "free",
            usedMinutes: json["usedMinutes"] as? Double ?? 0,
            monthlyLimitMinutes: json["monthlyLimitMinutes"] as? Double,
            month: json["month"] as? String ?? ""
        )
    }

    private func parseAuthResponse(data: Data, response: URLResponse) throws -> AuthSession {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }

        if http.statusCode >= 400 {
            let msg = json["error_description"] as? String
                ?? json["msg"] as? String
                ?? json["error"] as? String
                ?? "Unknown error"
            throw AuthError.serverError(msg)
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int else {
            throw AuthError.invalidResponse
        }

        let user = json["user"] as? [String: Any]
        let userId = user?["id"] as? String ?? ""
        let email = user?["email"] as? String ?? ""

        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)),
            userId: userId,
            email: email
        )
    }
}

struct UserStatus {
    let subscription: String
    let usedMinutes: Double
    let monthlyLimitMinutes: Double?
    let month: String

    var isPro: Bool { subscription == "pro" || subscription == "lifetime" }
    var isLifetime: Bool { subscription == "lifetime" }

    var usageDescription: String {
        if isPro { return "Unlimited" }
        let limit = monthlyLimitMinutes ?? 15
        return String(format: "%.1f / %.0f min", usedMinutes, limit)
    }
}
