import Foundation

protocol DeepgramWebSocketDelegate: AnyObject {
    func deepgramWebSocket(_ ws: DeepgramWebSocket, didReceiveTranscript text: String, isFinal: Bool)
    func deepgramWebSocketDidClose(_ ws: DeepgramWebSocket)
    func deepgramWebSocket(_ ws: DeepgramWebSocket, didEncounterError error: Error)
    func deepgramWebSocketDidReceiveAuthError(_ ws: DeepgramWebSocket)
    func deepgramWebSocketDidReceiveRateLimitError(_ ws: DeepgramWebSocket, message: String)
}

// Default implementations for new delegate methods
extension DeepgramWebSocketDelegate {
    func deepgramWebSocketDidReceiveAuthError(_ ws: DeepgramWebSocket) {}
    func deepgramWebSocketDidReceiveRateLimitError(_ ws: DeepgramWebSocket, message: String) {}
}

class DeepgramWebSocket {
    weak var delegate: DeepgramWebSocketDelegate?

    // Auth: either Supabase JWT (via proxy) or direct Deepgram API key
    var authToken: String = ""
    var useProxy: Bool = true
    var language: String = "en"

    private var webSocketTask: URLSessionWebSocketTask?
    private lazy var urlSession: URLSession = URLSession(configuration: .default)
    private var keepAliveTimer: Timer?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var pendingAudioChunks: [Data] = []
    private var shouldReconnect = false
    private var didReceiveAnyResult = false
    private(set) var wasRateLimited = false
    private var finalizeTimeoutWork: DispatchWorkItem?

    func connect() {
        let baseURL: String
        let authHeader: String

        if useProxy {
            baseURL = Configuration.proxyWSURL
            authHeader = "Bearer \(authToken)"
        } else {
            baseURL = "wss://api.deepgram.com/v1/listen"
            authHeader = "Token \(authToken)"
        }

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "paragraphs", value: "true"),
            URLQueryItem(name: "language", value: language),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        // Cancel any pending finalize timeout from a previous session
        finalizeTimeoutWork?.cancel()
        finalizeTimeoutWork = nil

        let task = urlSession.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        isConnected = true
        reconnectAttempts = 0
        shouldReconnect = true
        didReceiveAnyResult = false
        wasRateLimited = false

        receiveMessage()

        DispatchQueue.main.async {
            self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
                self?.sendKeepAlive()
            }
        }
    }

    func sendAudio(_ data: Data) {
        guard isConnected else {
            if shouldReconnect {
                pendingAudioChunks.append(data)
            }
            return
        }
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    func finalize() {
        shouldReconnect = false

        // If never connected, fire close immediately so app doesn't hang
        guard isConnected else {
            DispatchQueue.main.async {
                self.delegate?.deepgramWebSocketDidClose(self)
            }
            return
        }

        let finalizeMsg = #"{"type":"Finalize"}"#
        webSocketTask?.send(.string(finalizeMsg)) { [weak self] error in
            if let error = error {
                print("WebSocket finalize error: \(error)")
            }
            let closeMsg = #"{"type":"CloseStream"}"#
            self?.webSocketTask?.send(.string(closeMsg)) { error in
                if let error = error {
                    print("WebSocket close stream error: \(error)")
                }
            }
        }

        // Safety timeout — if server doesn't close within 5s, force close
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self, self.isConnected else { return }
            v2log("WebSocket finalize timeout — forcing close")
            self.isConnected = false
            self.keepAliveTimer?.invalidate()
            self.keepAliveTimer = nil
            self.webSocketTask?.cancel(with: .normalClosure, reason: nil)
            self.webSocketTask = nil
            self.delegate?.deepgramWebSocketDidClose(self)
        }
        finalizeTimeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutWork)
    }

    func disconnect() {
        shouldReconnect = false
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        isConnected = false
        pendingAudioChunks.removeAll()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func attemptReconnect() {
        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
            DispatchQueue.main.async {
                self.delegate?.deepgramWebSocketDidClose(self)
            }
            return
        }

        reconnectAttempts += 1
        print("WebSocket reconnecting (attempt \(reconnectAttempts)/\(maxReconnectAttempts))...")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.connect()

            // Send any buffered audio
            let buffered = self.pendingAudioChunks
            self.pendingAudioChunks.removeAll()
            for chunk in buffered {
                self.sendAudio(chunk)
            }
        }
    }

    private func sendKeepAlive() {
        guard isConnected else { return }
        let msg = #"{"type":"KeepAlive"}"#
        webSocketTask?.send(.string(msg)) { error in
            if let error = error {
                print("WebSocket keep-alive error: \(error)")
            }
        }
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                self.receiveMessage()

            case .failure(let error):
                let nsError = error as NSError
                // 57 = socket not connected (normal close)
                if nsError.code != 57 {
                    print("WebSocket receive error: \(error)")
                }

                // Detect HTTP 429 (rate limit) from WebSocket upgrade rejection
                // URLSession reports this as error code 2 (invalidServerResponse) in POSIXErrorCode domain
                // or the closeCode on the task itself
                let closeCode = self.webSocketTask?.closeCode ?? .invalid
                if closeCode.rawValue == 429 || nsError.code == 429 ||
                   (nsError.domain == "NSPOSIXErrorDomain" && !self.didReceiveAnyResult && self.reconnectAttempts >= self.maxReconnectAttempts - 1) {
                    self.wasRateLimited = true
                }

                DispatchQueue.main.async {
                    self.keepAliveTimer?.invalidate()
                    self.keepAliveTimer = nil
                    self.isConnected = false

                    if self.shouldReconnect && self.reconnectAttempts < self.maxReconnectAttempts {
                        self.attemptReconnect()
                    } else {
                        DispatchQueue.main.async {
                            self.delegate?.deepgramWebSocketDidClose(self)
                        }
                    }
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let type = json["type"] as? String ?? ""

        // Rate limit error from proxy
        if type == "Error" || type == "error" {
            let message = json["message"] as? String ?? json["error"] as? String ?? "Unknown error"
            let statusCode = json["status"] as? Int ?? json["code"] as? Int ?? 0
            if statusCode == 429 || message.lowercased().contains("limit") || message.lowercased().contains("quota") {
                wasRateLimited = true
                DispatchQueue.main.async {
                    self.delegate?.deepgramWebSocketDidReceiveRateLimitError(self, message: message)
                }
            } else if statusCode == 401 || statusCode == 403 || message.lowercased().contains("auth") {
                DispatchQueue.main.async {
                    self.delegate?.deepgramWebSocketDidReceiveAuthError(self)
                }
            }
            return
        }

        guard type == "Results" else { return }

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String else {
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false
        didReceiveAnyResult = true

        if !transcript.isEmpty {
            DispatchQueue.main.async {
                self.delegate?.deepgramWebSocket(self, didReceiveTranscript: transcript, isFinal: isFinal)
            }
        }
    }
}
