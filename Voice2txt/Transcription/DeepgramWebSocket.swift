import Foundation

protocol DeepgramWebSocketDelegate: AnyObject {
    func deepgramWebSocket(_ ws: DeepgramWebSocket, didReceiveTranscript text: String, isFinal: Bool)
    func deepgramWebSocketDidClose(_ ws: DeepgramWebSocket)
    func deepgramWebSocket(_ ws: DeepgramWebSocket, didEncounterError error: Error)
}

class DeepgramWebSocket {
    weak var delegate: DeepgramWebSocketDelegate?
    var apiKey: String = ""

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var keepAliveTimer: Timer?
    private var isConnected = false

    func connect() {
        guard !apiKey.isEmpty else {
            print("DeepgramWebSocket: No API key")
            return
        }

        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "interim_results", value: "false"),
            URLQueryItem(name: "smart_format", value: "true"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        self.urlSession = session

        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()
        isConnected = true

        receiveMessage()

        DispatchQueue.main.async {
            self.keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
                self?.sendKeepAlive()
            }
        }
    }

    func sendAudio(_ data: Data) {
        guard isConnected else { return }
        webSocketTask?.send(.data(data)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    func finalize() {
        guard isConnected else { return }

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
    }

    func disconnect() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        isConnected = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
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
                DispatchQueue.main.async {
                    self.keepAliveTimer?.invalidate()
                    self.keepAliveTimer = nil
                    self.isConnected = false
                    self.delegate?.deepgramWebSocketDidClose(self)
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        guard let type = json["type"] as? String, type == "Results" else {
            return
        }

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String else {
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false

        if !transcript.isEmpty {
            DispatchQueue.main.async {
                self.delegate?.deepgramWebSocket(self, didReceiveTranscript: transcript, isFinal: isFinal)
            }
        }
    }
}
