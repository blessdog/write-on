import Cocoa

protocol WelcomeWindowControllerDelegate: AnyObject {
    func welcomeWindowDidDismiss()
}

class WelcomeWindowController: NSObject {
    weak var delegate: WelcomeWindowControllerDelegate?

    private var window: NSWindow!

    func showWindow() {
        if window != nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 520
        let h: CGFloat = 520

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Write On"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)

        let contentView = window.contentView!
        let teal = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)

        // Checkmark icon
        let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Ready")!
        let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .regular)
        let tintedImage = checkImage.withSymbolConfiguration(config)!
        let checkView = NSImageView(frame: NSRect(x: (w - 60) / 2, y: h - 100, width: 60, height: 60))
        checkView.image = tintedImage
        checkView.contentTintColor = teal
        contentView.addSubview(checkView)

        // Heading
        let heading = NSTextField(labelWithString: "Write On is ready!")
        heading.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        heading.textColor = .white
        heading.alignment = .center
        heading.frame = NSRect(x: 20, y: h - 145, width: w - 40, height: 30)
        contentView.addSubview(heading)

        // Subtitle
        let subtitle = NSTextField(labelWithString: "Look for the mic icon in your menu bar.")
        subtitle.font = NSFont.systemFont(ofSize: 14)
        subtitle.textColor = NSColor(red: 0.88, green: 0.94, blue: 0.92, alpha: 1)
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 20, y: h - 175, width: w - 40, height: 20)
        contentView.addSubview(subtitle)

        // "HOW TO USE" section header
        let sectionHeader = NSTextField(labelWithString: "HOW TO USE")
        sectionHeader.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        sectionHeader.textColor = teal
        sectionHeader.frame = NSRect(x: 50, y: h - 220, width: 200, height: 16)
        contentView.addSubview(sectionHeader)

        // Separator line
        let separator = NSBox(frame: NSRect(x: 50, y: h - 228, width: w - 100, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        // Row 1: Double-tap Ctrl
        addInstructionRow(
            to: contentView,
            y: h - 270,
            width: w,
            hotkey: "Double-tap Ctrl",
            description: "Start a long recording.\nTap Ctrl again to stop."
        )

        // Row 2: Hold Right Option
        addInstructionRow(
            to: contentView,
            y: h - 320,
            width: w,
            hotkey: "Hold Right Option",
            description: "Quick recording.\nRelease to stop."
        )

        // Row 3: Auto-paste
        addInstructionRow(
            to: contentView,
            y: h - 370,
            width: w,
            hotkey: "Auto-paste",
            description: "Your speech appears wherever\nyour cursor is."
        )

        // "Got it!" button
        let gotItButton = NSButton(frame: NSRect(x: (w - 200) / 2, y: 40, width: 200, height: 40))
        gotItButton.title = "Got it!"
        gotItButton.bezelStyle = .rounded
        gotItButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        gotItButton.target = self
        gotItButton.action = #selector(dismiss)
        gotItButton.keyEquivalent = "\r"
        contentView.addSubview(gotItButton)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func addInstructionRow(to parent: NSView, y: CGFloat, width: CGFloat, hotkey: String, description: String) {
        let teal = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)

        let hotkeyLabel = NSTextField(labelWithString: hotkey)
        hotkeyLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        hotkeyLabel.textColor = teal
        hotkeyLabel.frame = NSRect(x: 50, y: y, width: 180, height: 18)
        parent.addSubview(hotkeyLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = NSColor(red: 0.88, green: 0.94, blue: 0.92, alpha: 1)
        descLabel.maximumNumberOfLines = 2
        descLabel.frame = NSRect(x: 50, y: y - 30, width: width - 100, height: 30)
        parent.addSubview(descLabel)
    }

    @objc private func dismiss() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        window?.close()
        window = nil
        delegate?.welcomeWindowDidDismiss()
    }
}

extension WelcomeWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        delegate?.welcomeWindowDidDismiss()
    }
}
