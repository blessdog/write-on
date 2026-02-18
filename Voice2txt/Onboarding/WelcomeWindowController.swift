import Cocoa

protocol WelcomeWindowControllerDelegate: AnyObject {
    func welcomeWindowDidDismiss()
    func welcomeWindowDidRequestPreferences()
}

class WelcomeWindowController: NSObject {
    weak var delegate: WelcomeWindowControllerDelegate?

    private var window: NSWindow!
    private let teal = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
    private let offWhite = NSColor(red: 0.88, green: 0.94, blue: 0.92, alpha: 1)
    private let cardBg = NSColor(red: 0.10, green: 0.10, blue: 0.14, alpha: 1)
    private let bgColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)

    func showWindow() {
        if window != nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 600
        let h: CGFloat = 620

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
        window.backgroundColor = bgColor
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)

        // ScrollView wrapping everything
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay

        let contentWidth = w
        let contentHeight: CGFloat = 780 // tall enough for all sections
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        docView.wantsLayer = true
        docView.layer?.backgroundColor = bgColor.cgColor
        scrollView.documentView = docView
        window.contentView!.addSubview(scrollView)

        let inset: CGFloat = 50
        let cardW: CGFloat = contentWidth - inset * 2
        var y: CGFloat = contentHeight // build top-down

        // ── Header ──
        y -= 16 // top padding

        let micImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Mic")!
        let micConfig = NSImage.SymbolConfiguration(pointSize: 36, weight: .regular)
        let micView = NSImageView(frame: NSRect(x: (contentWidth - 44) / 2, y: y - 44, width: 44, height: 44))
        micView.image = micImage.withSymbolConfiguration(micConfig)!
        micView.contentTintColor = teal
        docView.addSubview(micView)
        y -= 56

        let heading = NSTextField(labelWithString: "Welcome to Write On")
        heading.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        heading.textColor = .white
        heading.alignment = .center
        heading.frame = NSRect(x: 20, y: y - 28, width: contentWidth - 40, height: 28)
        docView.addSubview(heading)
        y -= 36

        let subtitle = NSTextField(labelWithString: "Here's everything you need to know.")
        subtitle.font = NSFont.systemFont(ofSize: 13)
        subtitle.textColor = offWhite.withAlphaComponent(0.7)
        subtitle.alignment = .center
        subtitle.frame = NSRect(x: 20, y: y - 18, width: contentWidth - 40, height: 18)
        docView.addSubview(subtitle)
        y -= 36

        // ── Section 1: Menu bar ──
        let section1Height: CGFloat = 90
        let section1 = makeCard(frame: NSRect(x: inset, y: y - section1Height, width: cardW, height: section1Height))
        docView.addSubview(section1)

        let menuBarIcon = NSImage(systemSymbolName: "menubar.arrow.up.rectangle", accessibilityDescription: "Menu bar")!
        let menuBarConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let menuBarView = NSImageView(frame: NSRect(x: 16, y: section1Height - 38, width: 28, height: 28))
        menuBarView.image = menuBarIcon.withSymbolConfiguration(menuBarConfig)!
        menuBarView.contentTintColor = teal
        section1.addSubview(menuBarView)

        let s1Title = NSTextField(labelWithString: "Write On lives in your menu bar")
        s1Title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        s1Title.textColor = .white
        s1Title.frame = NSRect(x: 52, y: section1Height - 36, width: cardW - 68, height: 18)
        section1.addSubview(s1Title)

        let s1Body = makeWrappingLabel(
            "Look for the mic icon at the top of your screen. Click it to see your account, usage, history, and settings. The app has no dock icon — it stays out of your way.",
            width: cardW - 36
        )
        s1Body.frame.origin = NSPoint(x: 18, y: 10)
        section1.addSubview(s1Body)

        y -= (section1Height + 14)

        // ── Section 2: How to record ──
        let longDisplay = UserDefaults.standard.string(forKey: "hotkey.long.display") ?? "Double-tap Ctrl"
        let shortDisplay = UserDefaults.standard.string(forKey: "hotkey.short.display") ?? "Hold Right Option"

        let s2LabelY = y
        let s2Label = NSTextField(labelWithString: "How to record")
        s2Label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        s2Label.textColor = teal.withAlphaComponent(0.7)
        s2Label.frame = NSRect(x: inset + 4, y: s2LabelY - 16, width: 200, height: 16)
        docView.addSubview(s2Label)
        y -= 22

        // Card 1: Long recording
        let card1H: CGFloat = 82
        let card1 = makeCard(frame: NSRect(x: inset, y: y - card1H, width: cardW, height: card1H))
        docView.addSubview(card1)

        let longBadges = badgeTexts(from: longDisplay)
        var lastBadgeMaxX: CGFloat = 16
        for (i, text) in longBadges.enumerated() {
            let badge = makeKeyBadge(text)
            badge.frame.origin = NSPoint(x: lastBadgeMaxX + (i > 0 ? 8 : 0), y: card1H - 38)
            card1.addSubview(badge)
            lastBadgeMaxX = badge.frame.maxX
        }

        let desc1Title = NSTextField(labelWithString: "\(longDisplay) to start. Tap again to stop.")
        desc1Title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        desc1Title.textColor = .white
        desc1Title.frame = NSRect(x: 16, y: card1H - 58, width: cardW - 32, height: 16)
        card1.addSubview(desc1Title)

        let desc1Sub = NSTextField(labelWithString: "For dictating paragraphs, emails, notes")
        desc1Sub.font = NSFont.systemFont(ofSize: 11)
        desc1Sub.textColor = offWhite.withAlphaComponent(0.6)
        desc1Sub.frame = NSRect(x: 16, y: card1H - 76, width: cardW - 32, height: 14)
        card1.addSubview(desc1Sub)

        y -= (card1H + 10)

        // Card 2: Quick recording
        let card2H: CGFloat = 82
        let card2 = makeCard(frame: NSRect(x: inset, y: y - card2H, width: cardW, height: card2H))
        docView.addSubview(card2)

        let shortBadge = makeKeyBadge(shortDisplay.replacingOccurrences(of: "Hold ", with: ""))
        shortBadge.frame.origin = NSPoint(x: 16, y: card2H - 38)
        card2.addSubview(shortBadge)

        let desc2Title = NSTextField(labelWithString: "\(shortDisplay) to record. Release to stop.")
        desc2Title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        desc2Title.textColor = .white
        desc2Title.frame = NSRect(x: 16, y: card2H - 58, width: cardW - 32, height: 16)
        card2.addSubview(desc2Title)

        let desc2Sub = NSTextField(labelWithString: "For quick messages, search queries")
        desc2Sub.font = NSFont.systemFont(ofSize: 11)
        desc2Sub.textColor = offWhite.withAlphaComponent(0.6)
        desc2Sub.frame = NSRect(x: 16, y: card2H - 76, width: cardW - 32, height: 14)
        card2.addSubview(desc2Sub)

        y -= (card2H + 6)

        let cursorHint = NSTextField(labelWithString: "Your words appear wherever your cursor is.")
        cursorHint.font = NSFont.systemFont(ofSize: 11)
        cursorHint.textColor = offWhite.withAlphaComponent(0.5)
        cursorHint.alignment = .center
        cursorHint.frame = NSRect(x: inset, y: y - 14, width: cardW, height: 14)
        docView.addSubview(cursorHint)
        y -= 28

        // ── Section 3: Customize ──
        let section3Height: CGFloat = 110
        let section3 = makeCard(frame: NSRect(x: inset, y: y - section3Height, width: cardW, height: section3Height))
        docView.addSubview(section3)

        let gearIcon = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Preferences")!
        let gearConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let gearView = NSImageView(frame: NSRect(x: 16, y: section3Height - 38, width: 28, height: 28))
        gearView.image = gearIcon.withSymbolConfiguration(gearConfig)!
        gearView.contentTintColor = teal
        section3.addSubview(gearView)

        let s3Title = NSTextField(labelWithString: "Customize your experience")
        s3Title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        s3Title.textColor = .white
        s3Title.frame = NSRect(x: 52, y: section3Height - 36, width: cardW - 68, height: 18)
        section3.addSubview(s3Title)

        let s3Body = makeWrappingLabel(
            "Change your hotkeys, language, or overlay style. Access Preferences anytime from the menu bar icon.",
            width: cardW - 150
        )
        s3Body.frame.origin = NSPoint(x: 18, y: 14)
        section3.addSubview(s3Body)

        let prefsButton = NSButton(frame: NSRect(x: cardW - 130, y: 14, width: 118, height: 28))
        prefsButton.title = "Open Preferences"
        prefsButton.bezelStyle = .rounded
        prefsButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        prefsButton.contentTintColor = teal
        prefsButton.target = self
        prefsButton.action = #selector(openPreferences)
        section3.addSubview(prefsButton)

        y -= (section3Height + 14)

        // ── Section 4: Closing & reopening ──
        let section4Height: CGFloat = 80
        let section4 = makeCard(frame: NSRect(x: inset, y: y - section4Height, width: cardW, height: section4Height))
        docView.addSubview(section4)

        let quitIcon = NSImage(systemSymbolName: "arrow.uturn.left.circle", accessibilityDescription: "Quit and reopen")!
        let quitConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let quitView = NSImageView(frame: NSRect(x: 16, y: section4Height - 38, width: 28, height: 28))
        quitView.image = quitIcon.withSymbolConfiguration(quitConfig)!
        quitView.contentTintColor = teal
        section4.addSubview(quitView)

        let s4Title = NSTextField(labelWithString: "Closing & reopening")
        s4Title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        s4Title.textColor = .white
        s4Title.frame = NSRect(x: 52, y: section4Height - 36, width: cardW - 68, height: 18)
        section4.addSubview(s4Title)

        let s4Body = makeWrappingLabel(
            "To quit, click the menu bar icon and choose Quit. To reopen, launch Write On from your Applications folder — it'll appear right back in your menu bar.",
            width: cardW - 36
        )
        s4Body.frame.origin = NSPoint(x: 18, y: 8)
        section4.addSubview(s4Body)

        y -= (section4Height + 24)

        // ── Get Started button ──
        let buttonW: CGFloat = 200
        let getStarted = NSButton(frame: NSRect(x: (contentWidth - buttonW) / 2, y: y - 40, width: buttonW, height: 40))
        getStarted.title = "Get Started"
        getStarted.bezelStyle = .rounded
        getStarted.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        getStarted.contentTintColor = teal
        getStarted.target = self
        getStarted.action = #selector(dismiss)
        getStarted.keyEquivalent = "\r"
        docView.addSubview(getStarted)

        // Scroll to top
        docView.scroll(NSPoint(x: 0, y: contentHeight - h))

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Helpers

    private func badgeTexts(from display: String) -> [String] {
        if display.hasPrefix("Double-tap ") {
            let mod = String(display.dropFirst("Double-tap ".count))
            return [mod, mod]
        } else if display.contains("+") {
            return display.components(separatedBy: "+")
        } else {
            return [display]
        }
    }

    private func makeCard(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.backgroundColor = cardBg.cgColor
        card.layer?.cornerRadius = 12
        return card
    }

    private func makeKeyBadge(_ text: String) -> NSView {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let textW = ceil(textSize.width) + 4 // extra buffer for rendering
        let textH = ceil(textSize.height)
        let padH: CGFloat = 14
        let padV: CGFloat = 6
        let badgeW = textW + padH * 2
        let badgeH = textH + padV * 2

        let badge = NSView(frame: NSRect(x: 0, y: 0, width: badgeW, height: badgeH))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1).cgColor
        badge.layer?.cornerRadius = 6
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = teal.withAlphaComponent(0.4).cgColor

        let shadow = NSView(frame: NSRect(x: 0, y: 0, width: badgeW, height: 3))
        shadow.wantsLayer = true
        shadow.layer?.backgroundColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1).cgColor
        shadow.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        shadow.layer?.cornerRadius = 6
        badge.addSubview(shadow)

        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = teal
        label.alignment = .center
        label.frame = NSRect(x: padH, y: padV, width: textW, height: textH)
        badge.addSubview(label)

        return badge
    }

    private func makeWrappingLabel(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = offWhite.withAlphaComponent(0.6)
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.preferredMaxLayoutWidth = width
        label.frame.size = NSSize(width: width, height: 32)
        return label
    }

    @objc private func openPreferences() {
        delegate?.welcomeWindowDidRequestPreferences()
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
