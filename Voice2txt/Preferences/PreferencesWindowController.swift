import Cocoa

class PreferencesWindowController: NSObject {
    private var window: NSWindow?
    private var languagePopup: NSPopUpButton!
    private var micPopup: NSPopUpButton!

    // Hotkey UI
    private var longHotkeyLabel: NSTextField!
    private var longChangeButton: NSButton!
    private var shortHotkeyLabel: NSTextField!
    private var shortChangeButton: NSButton!
    private var conflictLabel: NSTextField!

    // Capture state
    private var capturingLong = false
    private var capturingShort = false
    private var captureMonitors: [Any] = []
    private var captureModifierTimer: Timer?
    private var capturedModifierName: String?
    private var capturedModifierKeyCodes: Set<UInt16>?
    private var capturedModifierFlag: NSEvent.ModifierFlags?

    // Reference to HotkeyManager for reloading
    var hotkeyManager: HotkeyManager?

    private let teal = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 480
        let h: CGFloat = 520

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Write On — Preferences"
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        win.titlebarAppearsTransparent = true
        win.appearance = NSAppearance(named: .darkAqua)
        self.window = win

        let content = win.contentView!
        var y = h - 50

        // ── Hotkeys Section ──
        let hotkeyHeader = sectionLabel("Hotkeys", y: y)
        content.addSubview(hotkeyHeader)
        y -= 30

        // Long Recording row
        let longLabel = descLabel("Long Recording:", y: y)
        content.addSubview(longLabel)

        let longDisplay = UserDefaults.standard.string(forKey: "hotkey.long.display") ?? "Double-tap Ctrl"
        longHotkeyLabel = NSTextField(labelWithString: longDisplay)
        longHotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        longHotkeyLabel.textColor = teal
        longHotkeyLabel.frame = NSRect(x: 180, y: y, width: 170, height: 18)
        content.addSubview(longHotkeyLabel)

        longChangeButton = NSButton(frame: NSRect(x: 360, y: y - 3, width: 70, height: 24))
        longChangeButton.title = "Change"
        longChangeButton.bezelStyle = .rounded
        longChangeButton.font = NSFont.systemFont(ofSize: 11)
        longChangeButton.target = self
        longChangeButton.action = #selector(startCaptureLong)
        content.addSubview(longChangeButton)
        y -= 30

        // Short Recording row
        let quickLabel = descLabel("Quick Recording:", y: y)
        content.addSubview(quickLabel)

        let shortDisplay = UserDefaults.standard.string(forKey: "hotkey.short.display") ?? "Hold Right Option"
        shortHotkeyLabel = NSTextField(labelWithString: shortDisplay)
        shortHotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        shortHotkeyLabel.textColor = teal
        shortHotkeyLabel.frame = NSRect(x: 180, y: y, width: 170, height: 18)
        content.addSubview(shortHotkeyLabel)

        shortChangeButton = NSButton(frame: NSRect(x: 360, y: y - 3, width: 70, height: 24))
        shortChangeButton.title = "Change"
        shortChangeButton.bezelStyle = .rounded
        shortChangeButton.font = NSFont.systemFont(ofSize: 11)
        shortChangeButton.target = self
        shortChangeButton.action = #selector(startCaptureShort)
        content.addSubview(shortChangeButton)
        y -= 24

        // Conflict warning label (hidden by default)
        conflictLabel = NSTextField(labelWithString: "")
        conflictLabel.font = NSFont.systemFont(ofSize: 11)
        conflictLabel.textColor = NSColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        conflictLabel.frame = NSRect(x: 40, y: y, width: w - 80, height: 16)
        conflictLabel.isHidden = true
        content.addSubview(conflictLabel)
        y -= 30

        // ── Transcription Section ──
        let transcriptionHeader = sectionLabel("Transcription", y: y)
        content.addSubview(transcriptionHeader)
        y -= 30

        let langLabel = descLabel("Language:", y: y)
        content.addSubview(langLabel)

        languagePopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 200, height: 28))
        let languages = LanguageManager.shared.availableLanguages
        for lang in languages {
            languagePopup.addItem(withTitle: lang.name)
            languagePopup.lastItem?.representedObject = lang.code
        }
        if let currentIndex = languages.firstIndex(where: { $0.code == LanguageManager.shared.currentLanguage }) {
            languagePopup.selectItem(at: currentIndex)
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        content.addSubview(languagePopup)
        y -= 30

        let micLabel = descLabel("Microphone:", y: y)
        content.addSubview(micLabel)

        micPopup = NSPopUpButton(frame: NSRect(x: 160, y: y - 2, width: 270, height: 28))
        micPopup.addItem(withTitle: "Built-in Microphone (Default)")
        micPopup.lastItem?.tag = 0
        let devices = AudioCaptureManager.availableInputDevices()
        let savedDeviceID = UserDefaults.standard.integer(forKey: "audio.inputDeviceID")
        for device in devices {
            let title = device.isBluetooth ? "\(device.name) (Bluetooth)" : device.name
            micPopup.addItem(withTitle: title)
            micPopup.lastItem?.tag = Int(device.id)
            if Int(device.id) == savedDeviceID {
                micPopup.selectItem(withTag: savedDeviceID)
            }
        }
        micPopup.target = self
        micPopup.action = #selector(micChanged)
        content.addSubview(micPopup)
        y -= 50

        // ── Overlay Section ──
        let overlayHeader = sectionLabel("Overlay", y: y)
        content.addSubview(overlayHeader)
        y -= 30

        let followMouseCheck = NSButton(checkboxWithTitle: "Follow mouse across monitors", target: self, action: #selector(followMouseToggled))
        followMouseCheck.frame = NSRect(x: 40, y: y, width: 300, height: 20)
        followMouseCheck.state = UserDefaults.standard.bool(forKey: "overlay.followMouse") ? .on : .off
        followMouseCheck.contentTintColor = NSColor(red: 0.88, green: 0.94, blue: 0.92, alpha: 1)
        content.addSubview(followMouseCheck)
        y -= 50

        // ── Account Section ──
        let accountHeader = sectionLabel("Account", y: y)
        content.addSubview(accountHeader)
        y -= 30

        if let email = SessionManager.shared.email {
            let emailLabel = descLabel("Email: \(email)", y: y)
            content.addSubview(emailLabel)
            y -= 25
        }

        let dashboardBtn = NSButton(frame: NSRect(x: 40, y: y, width: 160, height: 24))
        dashboardBtn.title = "Open Dashboard"
        dashboardBtn.bezelStyle = .rounded
        dashboardBtn.target = self
        dashboardBtn.action = #selector(openDashboard)
        content.addSubview(dashboardBtn)

        // ── Privacy Notice ──
        let privacyLabel = NSTextField(labelWithString: "Your transcripts are encrypted on-device and never stored on our servers.")
        privacyLabel.frame = NSRect(x: 40, y: 20, width: w - 80, height: 30)
        privacyLabel.font = NSFont.systemFont(ofSize: 10)
        privacyLabel.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 0.7)
        privacyLabel.maximumNumberOfLines = 2
        content.addSubview(privacyLabel)

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Hotkey Capture

    @objc private func startCaptureLong() {
        cancelCapture()
        capturingLong = true
        longChangeButton.title = "Press keys..."
        longChangeButton.isEnabled = false
        shortChangeButton.isEnabled = false
        conflictLabel.isHidden = true
        beginCapture(forLong: true)
    }

    @objc private func startCaptureShort() {
        cancelCapture()
        capturingShort = true
        shortChangeButton.title = "Press keys..."
        shortChangeButton.isEnabled = false
        longChangeButton.isEnabled = false
        conflictLabel.isHidden = true
        beginCapture(forLong: false)
    }

    private func beginCapture(forLong: Bool) {
        // Local monitors capture events while the Preferences window is key
        let flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleCaptureFlags(event, forLong: forLong)
            return nil // consume the event
        }
        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleCaptureKeyDown(event, forLong: forLong)
            return nil // consume the event
        }
        captureMonitors = [flagsMonitor as Any, keyMonitor as Any]
    }

    private func handleCaptureFlags(_ event: NSEvent, forLong: Bool) {
        let keyCode = event.keyCode

        // Identify which modifier was pressed
        guard let modName = HotkeyManager.modifierNameForKeyCode[keyCode] else { return }

        let isPress = event.modifierFlags.contains(HotkeyManager.modifierFlagForName[modName]!)

        if isPress {
            // Modifier pressed — store it and wait to see if a key follows
            capturedModifierName = modName
            capturedModifierKeyCodes = HotkeyManager.modifierKeyCodes[modName]
            capturedModifierFlag = HotkeyManager.modifierFlagForName[modName]

            if forLong {
                // For long recording: wait 0.5s — if no key arrives, treat as double-tap mode
                captureModifierTimer?.invalidate()
                captureModifierTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    self?.finishCaptureLongDoubleTap()
                }
            } else {
                // For short recording: modifier-only is valid immediately
                finishCaptureShort(keyCode: keyCode)
            }
        }
        // Releases are ignored during capture
    }

    private func handleCaptureKeyDown(_ event: NSEvent, forLong: Bool) {
        guard forLong else {
            // Short recording only accepts modifier-only presses
            cancelCapture()
            showConflict("Quick Recording must be a modifier key only (Ctrl, Cmd, Option, Shift)")
            return
        }

        // Cancel the modifier-only timer since a key was pressed
        captureModifierTimer?.invalidate()
        captureModifierTimer = nil

        guard let modName = capturedModifierName,
              let modFlag = capturedModifierFlag else {
            // No modifier was held, press Escape to cancel
            if event.keyCode == 53 { // Escape
                cancelCapture()
            }
            return
        }

        // Escape cancels
        if event.keyCode == 53 {
            cancelCapture()
            return
        }

        // Check for system hotkey conflicts
        let comboKeyCode = event.keyCode
        if checkConflict(modName: modName, keyCode: comboKeyCode) {
            return
        }

        // Save as combo mode
        let keyName = keyNameForCode(comboKeyCode)
        let displayModifier = HotkeyManager.displayNameForModifier[modName] ?? modName.capitalized
        let display = "\(displayModifier)+\(keyName)"

        let config = LongHotkeyConfig(
            mode: .combo,
            keyCodes: HotkeyManager.modifierKeyCodes[modName] ?? [],
            modFlag: modFlag,
            comboKeyCode: comboKeyCode,
            display: display
        )
        HotkeyManager.saveLongConfig(config)
        longHotkeyLabel.stringValue = display
        hotkeyManager?.reloadConfig()
        endCapture()
    }

    private func finishCaptureLongDoubleTap() {
        guard let modName = capturedModifierName,
              let modFlag = capturedModifierFlag else {
            cancelCapture()
            return
        }

        let displayModifier = HotkeyManager.displayNameForModifier[modName] ?? modName.capitalized
        let display = "Double-tap \(displayModifier)"

        let config = LongHotkeyConfig(
            mode: .doubleTap,
            keyCodes: HotkeyManager.modifierKeyCodes[modName] ?? [],
            modFlag: modFlag,
            comboKeyCode: 0,
            display: display
        )
        HotkeyManager.saveLongConfig(config)
        longHotkeyLabel.stringValue = display
        hotkeyManager?.reloadConfig()
        endCapture()
    }

    private func finishCaptureShort(keyCode: UInt16) {
        guard let modName = capturedModifierName,
              let modFlag = capturedModifierFlag else {
            cancelCapture()
            return
        }

        let isRight = [62, 61, 60, 54].contains(keyCode) // Right Ctrl, Right Opt, Right Shift, Right Cmd
        let side = isRight ? "Right " : ""
        let displayModifier = HotkeyManager.displayNameForModifier[modName] ?? modName.capitalized
        let display = "Hold \(side)\(displayModifier)"

        let config = ShortHotkeyConfig(
            keyCode: keyCode,
            modFlag: modFlag,
            display: display
        )
        HotkeyManager.saveShortConfig(config)
        shortHotkeyLabel.stringValue = display
        hotkeyManager?.reloadConfig()
        endCapture()
    }

    private func cancelCapture() {
        captureModifierTimer?.invalidate()
        captureModifierTimer = nil
        capturedModifierName = nil
        capturedModifierKeyCodes = nil
        capturedModifierFlag = nil
        endCapture()
    }

    private func endCapture() {
        for monitor in captureMonitors {
            NSEvent.removeMonitor(monitor)
        }
        captureMonitors.removeAll()
        captureModifierTimer?.invalidate()
        captureModifierTimer = nil
        capturedModifierName = nil
        capturedModifierKeyCodes = nil
        capturedModifierFlag = nil
        capturingLong = false
        capturingShort = false

        longChangeButton?.title = "Change"
        longChangeButton?.isEnabled = true
        shortChangeButton?.title = "Change"
        shortChangeButton?.isEnabled = true
    }

    // MARK: - Conflict Detection

    private static let conflictingCombos: [(String, UInt16)] = [
        ("command", 12),  // Cmd+Q
        ("command", 13),  // Cmd+W
        ("command", 4),   // Cmd+H
        ("command", 46),  // Cmd+M
        ("command", 48),  // Cmd+Tab
        ("command", 49),  // Cmd+Space
    ]

    private static let conflictingShiftCombos: [(String, NSEvent.ModifierFlags, UInt16)] = [
        ("command", .shift, 20),  // Cmd+Shift+3
        ("command", .shift, 21),  // Cmd+Shift+4
        ("command", .shift, 23),  // Cmd+Shift+5
    ]

    private func checkConflict(modName: String, keyCode: UInt16) -> Bool {
        for (mod, key) in Self.conflictingCombos {
            if modName == mod && keyCode == key {
                let keyName = keyNameForCode(keyCode)
                let displayMod = HotkeyManager.displayNameForModifier[modName] ?? modName
                showConflict("Conflicts with system hotkey \(displayMod)+\(keyName)")
                cancelCapture()
                return true
            }
        }
        return false
    }

    private func showConflict(_ message: String) {
        conflictLabel.stringValue = message
        conflictLabel.isHidden = false
    }

    // MARK: - Key Name Lookup

    private func keyNameForCode(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 10: "?", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "Tab", 49: "Space", 50: "`",
        ]
        return names[keyCode] ?? "Key\(keyCode)"
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        label.textColor = teal
        label.frame = NSRect(x: 30, y: y, width: 300, height: 18)
        return label
    }

    private func descLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor(red: 0.88, green: 0.94, blue: 0.92, alpha: 1)
        label.frame = NSRect(x: 40, y: y, width: 300, height: 18)
        return label
    }

    @objc private func languageChanged() {
        guard let code = languagePopup.selectedItem?.representedObject as? String else { return }
        LanguageManager.shared.currentLanguage = code
    }

    @objc private func micChanged() {
        let deviceID = micPopup.selectedItem?.tag ?? 0
        UserDefaults.standard.set(deviceID, forKey: "audio.inputDeviceID")
    }

    @objc private func followMouseToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "overlay.followMouse")
    }

    @objc private func openDashboard() {
        let access = SessionManager.shared.accessToken ?? ""
        let refresh = SessionManager.shared.refreshToken ?? ""
        let url = "https://write-on.app/dashboard/#access_token=\(access)&refresh_token=\(refresh)&type=bearer"
        NSWorkspace.shared.open(URL(string: url)!)
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        cancelCapture()
        window = nil
    }
}
