import Cocoa
import os.log

private let log = OSLog(subsystem: "com.voice2txt.app", category: "general")

/// Log to both os_log (visible in `log stream`) and stdout.
func v2log(_ message: String) {
    os_log("%{public}@", log: log, type: .default, message)
    print(message)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let appState = AppStateManager()
    private let hotkeyManager = HotkeyManager()
    private let audioCaptureManager = AudioCaptureManager()
    private let audioLevelProcessor = AudioLevelProcessor()
    private let deepgramWebSocket = DeepgramWebSocket()
    private let transcriptAssembler = TranscriptAssembler()
    private let clipboardManager = ClipboardManager()
    private let frontmostAppTracker = FrontmostAppTracker()
    private var overlayPanel: OverlayPanel!
    private var overlayViewController: OverlayViewController!
    private var waterfallRenderer: WaterfallRenderer!
    private let soundFeedback = SoundFeedback()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let apiKey = Configuration.loadAPIKey() else {
            let alert = NSAlert()
            alert.messageText = "API Key Missing"
            alert.informativeText = "Set DEEPGRAM_API_KEY environment variable or create ~/.config/voice2txt/api_key"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()

        deepgramWebSocket.apiKey = apiKey
        deepgramWebSocket.delegate = self

        hotkeyManager.delegate = self
        audioCaptureManager.delegate = self

        waterfallRenderer = WaterfallRenderer()
        overlayViewController = OverlayViewController(renderer: waterfallRenderer)
        overlayPanel = OverlayPanel()
        overlayPanel.contentViewController = overlayViewController

        if hotkeyManager.start() {
            v2log("Global event monitor active — hotkeys ready")
        } else {
            v2log("Failed to create global event monitor. Check Accessibility permission.")
        }

        clipboardManager.checkAccessibility()
        v2log("Voice2txt ready.")
        v2log("  Double-tap Ctrl   \u{2192} start long recording (Ctrl to stop)")
        v2log("  Hold Right Option \u{2192} short recording (release to stop)")
        v2log("  Transcript streams into active app as you speak")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice2txt")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Voice2txt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setStatusIcon(_ name: String) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Voice2txt")
        }
    }
}

// MARK: - HotkeyManagerDelegate

extension AppDelegate: HotkeyManagerDelegate {
    func hotkeyManagerDidStartRecording(mode: RecordingMode) {
        guard appState.isIdle else { return }

        appState.transition(to: .recording(mode))
        frontmostAppTracker.saveFrontmostApp()
        soundFeedback.playStartSound()
        transcriptAssembler.reset()
        clipboardManager.resetStreaming()

        deepgramWebSocket.connect()
        audioCaptureManager.startCapture()

        waterfallRenderer.reset()
        overlayPanel.showOnMouseScreen()
        setStatusIcon("mic.badge.plus")

        v2log("Recording started (\(mode) mode)")
    }

    func hotkeyManagerDidStopRecording() {
        guard appState.isRecording else { return }

        appState.transition(to: .transcribing)
        audioCaptureManager.stopCapture()
        soundFeedback.playStopSound()

        waterfallRenderer.setTranscribing(true)
        setStatusIcon("ellipsis.circle")

        deepgramWebSocket.finalize()
        v2log("Recording stopped, transcribing...")
    }
}

// MARK: - AudioCaptureManagerDelegate

extension AppDelegate: AudioCaptureManagerDelegate {
    func audioCaptureManager(_ manager: AudioCaptureManager, didCapturePCMData data: Data) {
        deepgramWebSocket.sendAudio(data)

        let waveform = audioLevelProcessor.processAudioData(data)
        DispatchQueue.main.async {
            self.waterfallRenderer.pushWaveform(waveform)
        }
    }
}

// MARK: - DeepgramWebSocketDelegate

extension AppDelegate: DeepgramWebSocketDelegate {
    func deepgramWebSocket(_ ws: DeepgramWebSocket, didReceiveTranscript text: String, isFinal: Bool) {
        transcriptAssembler.addResult(text: text, isFinal: isFinal)

        // Show live transcript in the overlay — no pasting during recording
        let currentText = transcriptAssembler.fullTranscript
        overlayViewController.updateTranscript(currentText)

        if isFinal {
            v2log("Final: \(text)")
        }
    }

    func deepgramWebSocketDidClose(_ ws: DeepgramWebSocket) {
        let transcript = transcriptAssembler.fullTranscript
        transcriptAssembler.reset()
        deepgramWebSocket.disconnect()

        overlayPanel.hide()
        setStatusIcon("mic.fill")
        appState.transition(to: .idle)

        guard !transcript.isEmpty else {
            v2log("(no speech detected)")
            return
        }

        // Single paste of the full transcript — no garbling possible
        clipboardManager.pasteFromClipboard(transcript)
        let preview = String(transcript.prefix(80))
        v2log("Done: \(preview)\(transcript.count > 80 ? "..." : "")")
    }

    func deepgramWebSocket(_ ws: DeepgramWebSocket, didEncounterError error: Error) {
        v2log("WebSocket error: \(error)")
    }
}
