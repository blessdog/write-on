import Cocoa
import CoreAudio
import os.log
import Sparkle

private let log = OSLog(subsystem: "com.writeon.app", category: "general")

private let logFileHandle: FileHandle? = {
    let dir = NSHomeDirectory() + "/Library/Caches/com.writeon.app"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let path = dir + "/writeon.log"
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    return FileHandle(forWritingAtPath: path)
}()

func v2log(_ message: String) {
    os_log("%{public}@", log: log, type: .default, message)
    print(message)
    let ts = ISO8601DateFormatter().string(from: Date())
    if let data = "[\(ts)] \(message)\n".data(using: .utf8) {
        logFileHandle?.seekToEndOfFile()
        logFileHandle?.write(data)
    }
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

    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var loginWindowController: LoginWindowController?
    private var preferencesWindowController: PreferencesWindowController?
    private var welcomeWindowController: WelcomeWindowController?
    private var cachedUserStatus: UserStatus?
    private var usageRefreshTimer: Timer?
    private var mouseFollowTimer: Timer?
    private var oauthHandled = false
    private var didFinishLaunching = false

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            v2log("Received URL: \(url.absoluteString.prefix(300))")
            guard url.scheme == "writeon" else { continue }
            // Try fragment first (implicit flow), then query params (PKCE)
            if let fragment = url.fragment, !fragment.isEmpty {
                handleOAuthCallback(fragment: fragment)
            } else if let query = url.query, !query.isEmpty {
                handleOAuthCallback(fragment: query)
            }
        }
    }

    private func handleOAuthCallback(fragment: String) {
        guard !oauthHandled else {
            v2log("OAuth callback ignored (already handled)")
            return
        }
        oauthHandled = true

        v2log("OAuth fragment received (\(fragment.count) chars): \(fragment.prefix(200))")
        do {
            let session = try AuthManager.shared.sessionFromOAuthFragment(fragment)
            v2log("OAuth session created — userId: \(session.userId.prefix(8))..., email: \(session.email)")

            SessionManager.shared.saveSession(session)
            loginWindowController?.close()
            configureWebSocket()
            if !didFinishLaunching {
                finishLaunching()
            } else {
                // Re-login after sign-out: restart hotkeys (stopped during sign-out)
                hotkeyManager.start()
            }
            refreshUserStatus()
            showOnboardingIfNeeded()
            v2log("Signed in via Google as \(session.email.isEmpty ? "(email pending)" : session.email)")
        } catch {
            oauthHandled = false
            v2log("OAuth token parse error: \(error) — fragment: \(fragment.prefix(300))")
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        v2log("App launching — isLoggedIn: \(SessionManager.shared.isLoggedIn)")

        // Request accessibility if not already granted (non-blocking)
        if !AXIsProcessTrusted() {
            // This prompts macOS to show its own "allow accessibility" dialog
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Check for existing session
        if SessionManager.shared.isLoggedIn {
            configureWebSocket()
            finishLaunching()
            refreshUserStatus()
            showOnboardingIfNeeded()
        } else {
            showLoginWindow()
        }
    }

    private func configureWebSocket() {
        // Use proxy with Supabase JWT
        deepgramWebSocket.useProxy = true
        deepgramWebSocket.language = LanguageManager.shared.currentLanguage
    }

    private func finishLaunching() {
        guard !didFinishLaunching else { return }
        didFinishLaunching = true
        setupStatusItem()

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

        v2log("Write On ready.")
        v2log("  \(hotkeyManager.longConfig.display) → start long recording (tap again to stop)")
        v2log("  \(hotkeyManager.shortConfig.display) → short recording (release to stop)")
        v2log("  Ctrl+V            → paste last transcript")
    }

    // MARK: - Status Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Write On")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Signed in as...
        if let email = SessionManager.shared.email {
            let signedIn = NSMenuItem(title: "Signed in as \(email)", action: nil, keyEquivalent: "")
            signedIn.isEnabled = false
            menu.addItem(signedIn)
        }

        // Usage
        if let status = cachedUserStatus {
            let usageItem = NSMenuItem(title: "Usage: \(status.usageDescription)", action: nil, keyEquivalent: "")
            usageItem.isEnabled = false
            menu.addItem(usageItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Transcript History submenu
        let historyItem = NSMenuItem(title: "Transcript History", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        let history = TranscriptHistory.shared.history

        if history.isEmpty {
            let emptyItem = NSMenuItem(title: "No transcripts yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            for (index, entry) in history.enumerated() {
                let title = "\(entry.timeAgo) — \(entry.preview)"
                let item = NSMenuItem(title: title, action: #selector(pasteHistoryItem(_:)), keyEquivalent: "")
                item.tag = index
                item.target = self
                historyMenu.addItem(item)
            }
            historyMenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        // Language submenu
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in LanguageManager.shared.availableLanguages {
            let item = NSMenuItem(title: lang.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.representedObject = lang.code
            item.target = self
            if lang.code == LanguageManager.shared.currentLanguage {
                item.state = .on
            }
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(NSMenuItem.separator())

        // Preferences
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        // Check for Updates
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)

        // Upgrade (for free users)
        if let status = cachedUserStatus, !status.isPro {
            let upgradeItem = NSMenuItem(title: "Upgrade to Pro", action: #selector(openUpgrade), keyEquivalent: "")
            upgradeItem.target = self
            menu.addItem(upgradeItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Sign Out
        let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: "")
        signOutItem.target = self
        menu.addItem(signOutItem)

        // Quit
        menu.addItem(NSMenuItem(title: "Quit Write On", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func setStatusIcon(_ name: String) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Write On")
        }
    }

    // MARK: - Menu Actions

    @objc private func pasteHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        let history = TranscriptHistory.shared.history
        guard index < history.count else { return }
        clipboardManager.pasteText(history[index].text)
        v2log("Pasting history item \(index)")
    }

    @objc private func clearHistory() {
        TranscriptHistory.shared.clearHistory()
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        LanguageManager.shared.currentLanguage = code
        deepgramWebSocket.language = code
        rebuildMenu()
        v2log("Language set to: \(code)")
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
            preferencesWindowController?.hotkeyManager = hotkeyManager
        }
        preferencesWindowController?.showWindow()
    }

    @objc private func openUpgrade() {
        NSWorkspace.shared.open(URL(string: "https://write-on.app/pricing/")!)
    }

    @objc private func signOut() {
        SessionManager.shared.clearSession()
        cachedUserStatus = nil
        usageRefreshTimer?.invalidate()
        usageRefreshTimer = nil
        oauthHandled = false
        hotkeyManager.stop()
        rebuildMenu()
        showLoginWindow()
        v2log("Signed out")
    }

    // MARK: - Auth

    private func showLoginWindow() {
        loginWindowController = LoginWindowController()
        loginWindowController?.delegate = self
        loginWindowController?.showWindow()
    }

    private func refreshUserStatus() {
        Task {
            guard let token = try? await SessionManager.shared.getValidToken() else { return }
            do {
                let status = try await AuthManager.shared.fetchUserStatus(accessToken: token)
                await MainActor.run {
                    self.cachedUserStatus = status
                    self.rebuildMenu()

                    // Proactively warn if free tier is exhausted
                    if !status.isPro {
                        let limit = status.monthlyLimitMinutes ?? 15
                        if status.usedMinutes >= limit {
                            v2log("Free tier exhausted on login (\(status.usageDescription))")
                            self.showRateLimitAlert()
                        }
                    }
                }
            } catch {
                v2log("Failed to fetch user status: \(error)")
            }
        }

        // Refresh every 5 minutes
        usageRefreshTimer?.invalidate()
        usageRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshUserStatus()
        }
    }

    // MARK: - Onboarding

    private func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasSeenOnboarding") else { return }
        welcomeWindowController = WelcomeWindowController()
        welcomeWindowController?.delegate = self
        welcomeWindowController?.showWindow()
    }

    private func flashStatusItem() {
        guard let button = statusItem?.button else { return }
        let teal = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
        let originalImage = button.image
        let flashImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Write On")

        var flashCount = 0
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            if flashCount >= 6 {
                timer.invalidate()
                button.image = originalImage
                button.contentTintColor = nil
                return
            }
            if flashCount % 2 == 0 {
                button.image = flashImage
                button.contentTintColor = teal
            } else {
                button.image = originalImage
                button.contentTintColor = nil
            }
            flashCount += 1
        }
    }

    // MARK: - Rate Limiting

    private func showRateLimitAlert() {
        let alert = NSAlert()
        alert.messageText = "Free Tier Limit Reached"
        alert.informativeText = "You've used your 15 free minutes this month.\n\nUpgrade to Pro for unlimited transcription."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Upgrade")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openUpgrade()
        }
    }

    // MARK: - Overlay Mouse Tracking

    private func startMouseTracking() {
        guard UserDefaults.standard.bool(forKey: "overlay.followMouse") else { return }
        mouseFollowTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.overlayPanel.followMouse()
        }
    }

    private func stopMouseTracking() {
        mouseFollowTimer?.invalidate()
        mouseFollowTimer = nil
    }
}

// MARK: - LoginWindowControllerDelegate

extension AppDelegate: LoginWindowControllerDelegate {
    func loginWindowDidAuthenticate(session: AuthSession) {
        SessionManager.shared.saveSession(session)
        configureWebSocket()
        if !didFinishLaunching {
            finishLaunching()
        } else {
            hotkeyManager.start()
        }
        refreshUserStatus()
        showOnboardingIfNeeded()
        v2log("Signed in as \(session.email)")
    }

    func loginWindowDidCancel() {
        NSApp.terminate(nil)
    }
}

// MARK: - HotkeyManagerDelegate

extension AppDelegate: HotkeyManagerDelegate {
    func hotkeyManagerDidStartRecording(mode: RecordingMode) {
        guard appState.isIdle else { return }

        // Block recording if free tier is exhausted
        if let status = cachedUserStatus, !status.isPro {
            let limit = status.monthlyLimitMinutes ?? 15
            if status.usedMinutes >= limit {
                v2log("Recording blocked — free tier limit reached (\(status.usageDescription))")
                showRateLimitAlert()
                return
            }
        }

        appState.transition(to: .recording(mode))
        frontmostAppTracker.saveFrontmostApp()
        soundFeedback.playStartSound()
        transcriptAssembler.reset()
        clipboardManager.resetStreaming()
        overlayViewController.updateTranscript("")

        // Get a valid token before connecting
        Task {
            do {
                let token = try await SessionManager.shared.getValidToken()
                await MainActor.run {
                    self.deepgramWebSocket.authToken = token
                    // Always pick up the latest language setting (may have changed in Preferences)
                    self.deepgramWebSocket.language = LanguageManager.shared.currentLanguage
                    self.deepgramWebSocket.connect()
                    self.audioCaptureManager.preferredDeviceID = AudioDeviceID(UserDefaults.standard.integer(forKey: "audio.inputDeviceID"))
                    self.audioCaptureManager.startCapture()

                    self.waterfallRenderer.reset()
                    self.overlayPanel.showOnMouseScreen()
                    self.startMouseTracking()
                    self.setStatusIcon("mic.badge.plus")
                }
            } catch {
                await MainActor.run {
                    v2log("Auth error: \(error)")
                    self.appState.transition(to: .idle)
                    self.soundFeedback.playStopSound()
                }
            }
        }

        v2log("Recording started (\(mode) mode)")
    }

    func hotkeyManagerDidStopRecording() {
        guard appState.isRecording else { return }

        appState.transition(to: .transcribing)
        audioCaptureManager.stopCapture()
        soundFeedback.playStopSound()
        stopMouseTracking()

        waterfallRenderer.setTranscribing(true)
        setStatusIcon("ellipsis.circle")

        deepgramWebSocket.finalize()
        v2log("Recording stopped, transcribing...")
    }

    func hotkeyManagerDidRequestPaste() {
        clipboardManager.pasteStoredTranscript()
        v2log("Ctrl+V: pasting stored transcript")
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
        stopMouseTracking()

        overlayPanel.hide()
        setStatusIcon("mic.fill")
        appState.transition(to: .idle)

        guard !transcript.isEmpty else {
            let overLimit: Bool = {
                guard let status = cachedUserStatus, !status.isPro else { return false }
                let limit = status.monthlyLimitMinutes ?? 15
                return status.usedMinutes >= limit
            }()
            if deepgramWebSocket.wasRateLimited || overLimit {
                v2log("Rate limited — showing upgrade prompt")
                showRateLimitAlert()
            } else {
                v2log("(no speech detected)")
            }
            return
        }

        // Prepend a space so the pasted text doesn't jam against existing text
        let pasteText = " " + transcript

        // Store in encrypted history
        TranscriptHistory.shared.addTranscript(transcript)
        clipboardManager.storeTranscript(pasteText)
        rebuildMenu()

        // Reactivate the app the user was in, then paste
        frontmostAppTracker.reactivateSavedApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [self] in
            clipboardManager.pasteStoredTranscript()
        }

        let preview = String(transcript.prefix(80))
        v2log("Transcript pasted: \(preview)\(transcript.count > 80 ? "..." : "")")

        // Refresh usage after each transcription
        refreshUserStatus()
    }

    func deepgramWebSocket(_ ws: DeepgramWebSocket, didEncounterError error: Error) {
        v2log("WebSocket error: \(error)")
    }

    func deepgramWebSocketDidReceiveAuthError(_ ws: DeepgramWebSocket) {
        v2log("Auth error — token may be expired")
        Task {
            do {
                let token = try await SessionManager.shared.getValidToken()
                await MainActor.run {
                    self.deepgramWebSocket.authToken = token
                }
            } catch {
                await MainActor.run {
                    self.signOut()
                }
            }
        }
    }

    func deepgramWebSocketDidReceiveRateLimitError(_ ws: DeepgramWebSocket, message: String) {
        v2log("Rate limit: \(message)")
        DispatchQueue.main.async {
            self.showRateLimitAlert()
        }
    }
}

// MARK: - WelcomeWindowControllerDelegate

extension AppDelegate: WelcomeWindowControllerDelegate {
    func welcomeWindowDidDismiss() {
        welcomeWindowController = nil
        flashStatusItem()
        v2log("Onboarding complete — menu bar icon flashed")
    }

    func welcomeWindowDidRequestPreferences() {
        showPreferences()
    }
}
