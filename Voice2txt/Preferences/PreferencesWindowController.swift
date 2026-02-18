import Cocoa

class PreferencesWindowController: NSObject {
    private var window: NSWindow?
    private var hotkeyField: NSTextField!
    private var hotkeyStatusLabel: NSTextField!
    private var languagePopup: NSPopUpButton!
    private var micPopup: NSPopUpButton!

    func showWindow() {
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 480
        let h: CGFloat = 480

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Write On — Preferences"
        win.center()
        win.isReleasedWhenClosed = false
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

        let longRecordLabel = descLabel("Long Recording (toggle):", y: y)
        content.addSubview(longRecordLabel)
        y -= 28

        hotkeyField = NSTextField(frame: NSRect(x: 40, y: y, width: 200, height: 24))
        hotkeyField.placeholderString = "Double-tap Ctrl"
        hotkeyField.stringValue = UserDefaults.standard.string(forKey: "hotkey.longRecord") ?? "Double-tap Ctrl"
        hotkeyField.isEditable = false
        hotkeyField.bezelStyle = .roundedBezel
        hotkeyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        content.addSubview(hotkeyField)

        let recordBtn = NSButton(frame: NSRect(x: 250, y: y, width: 100, height: 24))
        recordBtn.title = "Set Hotkey"
        recordBtn.bezelStyle = .rounded
        recordBtn.target = self
        recordBtn.action = #selector(startHotkeyCapture)
        content.addSubview(recordBtn)
        y -= 22

        hotkeyStatusLabel = NSTextField(labelWithString: "")
        hotkeyStatusLabel.frame = NSRect(x: 40, y: y, width: 350, height: 16)
        hotkeyStatusLabel.font = NSFont.systemFont(ofSize: 10)
        hotkeyStatusLabel.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)
        content.addSubview(hotkeyStatusLabel)
        y -= 40

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
        micPopup.addItem(withTitle: "System Default")
        micPopup.lastItem?.tag = 0
        let devices = AudioCaptureManager.availableInputDevices()
        let savedDeviceID = UserDefaults.standard.integer(forKey: "audio.inputDeviceID")
        for device in devices {
            micPopup.addItem(withTitle: device.name)
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

    private func sectionLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        label.textColor = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
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

    @objc private func startHotkeyCapture() {
        hotkeyField.stringValue = "Press keys..."
        hotkeyStatusLabel.stringValue = "Press your desired key combination"
        hotkeyStatusLabel.textColor = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)

        // Listen for the next key event
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }

            if event.type == .keyDown {
                let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let keyName = self.keyName(for: event.keyCode, modifiers: mods)

                // Check for system conflicts
                if self.isSystemHotkey(keyCode: event.keyCode, modifiers: mods) {
                    self.hotkeyStatusLabel.stringValue = "This key combination is used by the system. Choose another."
                    self.hotkeyStatusLabel.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
                    self.hotkeyField.stringValue = keyName
                } else {
                    self.hotkeyField.stringValue = keyName
                    self.hotkeyStatusLabel.stringValue = "Hotkey set!"
                    self.hotkeyStatusLabel.textColor = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
                    UserDefaults.standard.set(keyName, forKey: "hotkey.longRecord")
                }
                return nil // consume the event
            }
            return event
        }
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
        NSWorkspace.shared.open(URL(string: "https://write-on.app/dashboard/")!)
    }

    private func keyName(for keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }

        let keyNames: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            51: "Delete", 53: "Escape",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            123: "Left", 124: "Right", 125: "Down", 126: "Up",
        ]

        let key = keyNames[keyCode] ?? "Key\(keyCode)"
        parts.append(key)
        return parts.joined(separator: "+")
    }

    private func isSystemHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let cmd = modifiers.contains(.command)
        let shift = modifiers.contains(.shift)

        // Common macOS system hotkeys
        if cmd {
            switch keyCode {
            case 12: return true  // Cmd+Q (quit)
            case 13: return true  // Cmd+W (close window)
            case 4: return true   // Cmd+H (hide)
            case 46: return true  // Cmd+M (minimize)
            case 48 where shift: return true // Cmd+Shift+Tab
            case 48: return true  // Cmd+Tab (app switcher)
            case 49: return true  // Cmd+Space (Spotlight)
            default: break
            }
        }

        // Cmd+Shift+3/4/5 (screenshots)
        if cmd && shift && (keyCode == 20 || keyCode == 21 || keyCode == 23) {
            return true
        }

        return false
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
