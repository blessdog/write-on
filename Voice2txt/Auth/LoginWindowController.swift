import Cocoa

protocol LoginWindowControllerDelegate: AnyObject {
    func loginWindowDidAuthenticate(session: AuthSession)
    func loginWindowDidCancel()
}

class LoginWindowController: NSObject {
    weak var delegate: LoginWindowControllerDelegate?

    private var window: NSWindow!
    private var emailField: NSTextField!
    private var passwordField: NSSecureTextField!
    private var actionButton: NSButton!
    private var googleButton: NSButton!
    private var toggleButton: NSButton!
    private var statusLabel: NSTextField!
    private var forgotButton: NSButton!


    func showWindow() {
        if window != nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w: CGFloat = 380
        let h: CGFloat = 420

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Write On — Sign In"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)

        let contentView = window.contentView!

        // Logo
        let logo = NSTextField(labelWithString: "WriteOn")
        logo.font = NSFont.monospacedSystemFont(ofSize: 22, weight: .bold)
        logo.textColor = .white
        logo.frame = NSRect(x: (w - 200) / 2, y: h - 65, width: 200, height: 30)
        logo.alignment = .center
        contentView.addSubview(logo)

        // Google Sign In button
        googleButton = NSButton(frame: NSRect(x: 40, y: h - 110, width: w - 80, height: 34))
        googleButton.title = "  Continue with Google"
        googleButton.bezelStyle = .rounded
        googleButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        googleButton.target = self
        googleButton.action = #selector(googleSignIn)
        contentView.addSubview(googleButton)

        // Divider
        let dividerY = h - 140
        let dividerLeft = NSBox(frame: NSRect(x: 40, y: dividerY, width: (w - 120) / 2, height: 1))
        dividerLeft.boxType = .separator
        contentView.addSubview(dividerLeft)

        let orLabel = NSTextField(labelWithString: "or")
        orLabel.font = NSFont.systemFont(ofSize: 10)
        orLabel.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)
        orLabel.frame = NSRect(x: (w - 20) / 2, y: dividerY - 5, width: 20, height: 14)
        orLabel.alignment = .center
        contentView.addSubview(orLabel)

        let dividerRight = NSBox(frame: NSRect(x: (w + 20) / 2, y: dividerY, width: (w - 120) / 2, height: 1))
        dividerRight.boxType = .separator
        contentView.addSubview(dividerRight)

        // Email
        let emailLabel = makeLabel("Email", y: h - 175)
        contentView.addSubview(emailLabel)

        emailField = NSTextField(frame: NSRect(x: 40, y: h - 200, width: w - 80, height: 28))
        emailField.placeholderString = "you@example.com"
        emailField.font = NSFont.systemFont(ofSize: 13)
        emailField.bezelStyle = .roundedBezel
        contentView.addSubview(emailField)

        // Password
        let passLabel = makeLabel("Password", y: h - 235)
        contentView.addSubview(passLabel)

        passwordField = NSSecureTextField(frame: NSRect(x: 40, y: h - 260, width: w - 80, height: 28))
        passwordField.placeholderString = "••••••••"
        passwordField.font = NSFont.systemFont(ofSize: 13)
        passwordField.bezelStyle = .roundedBezel
        contentView.addSubview(passwordField)

        // Action button
        actionButton = NSButton(frame: NSRect(x: 40, y: h - 305, width: w - 80, height: 34))
        actionButton.title = "Sign In"
        actionButton.bezelStyle = .rounded
        actionButton.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        actionButton.target = self
        actionButton.action = #selector(actionButtonClicked)
        actionButton.keyEquivalent = "\r"
        contentView.addSubview(actionButton)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 40, y: h - 335, width: w - 80, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        contentView.addSubview(statusLabel)

        // Toggle sign in / sign up
        toggleButton = NSButton(frame: NSRect(x: 40, y: h - 365, width: w - 80, height: 20))
        toggleButton.title = "Don't have an account? Sign Up"
        toggleButton.bezelStyle = .inline
        toggleButton.isBordered = false
        toggleButton.font = NSFont.systemFont(ofSize: 11)
        toggleButton.contentTintColor = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
        toggleButton.target = self
        toggleButton.action = #selector(toggleMode)
        contentView.addSubview(toggleButton)

        // Forgot password
        forgotButton = NSButton(frame: NSRect(x: 40, y: h - 390, width: w - 80, height: 20))
        forgotButton.title = "Forgot Password?"
        forgotButton.bezelStyle = .inline
        forgotButton.isBordered = false
        forgotButton.font = NSFont.systemFont(ofSize: 11)
        forgotButton.contentTintColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)
        forgotButton.target = self
        forgotButton.action = #selector(forgotPassword)
        contentView.addSubview(forgotButton)

        // Tab order: email → password → sign in button
        emailField.nextKeyView = passwordField
        passwordField.nextKeyView = actionButton
        actionButton.nextKeyView = emailField

        window.initialFirstResponder = emailField
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }

    private func makeLabel(_ text: String, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)
        label.frame = NSRect(x: 40, y: y, width: 300, height: 16)
        return label
    }

    @objc private func googleSignIn() {
        let url = AuthManager.shared.getGoogleOAuthURL()
        NSWorkspace.shared.open(url)
        statusLabel.stringValue = "Complete sign-in in your browser..."
        statusLabel.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)
    }

    @objc private func toggleMode() {
        // Open signup page in browser
        if let url = URL(string: "https://write-on.app/signup/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func actionButtonClicked() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue

        guard !email.isEmpty, !password.isEmpty else {
            statusLabel.stringValue = "Please enter email and password"
            return
        }

        guard password.count >= 6 else {
            statusLabel.stringValue = "Password must be at least 6 characters"
            return
        }

        statusLabel.stringValue = "Signing in..."
        statusLabel.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)
        actionButton.isEnabled = false

        Task {
            do {
                let session = try await AuthManager.shared.signIn(email: email, password: password)

                await MainActor.run {
                    actionButton.isEnabled = true
                    delegate?.loginWindowDidAuthenticate(session: session)
                    close()
                }
            } catch {
                await MainActor.run {
                    actionButton.isEnabled = true
                    statusLabel.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
                    statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func forgotPassword() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            statusLabel.stringValue = "Enter your email first"
            return
        }

        statusLabel.stringValue = "Sending reset email..."
        statusLabel.textColor = NSColor(red: 0.4, green: 0.54, blue: 0.51, alpha: 1)

        Task {
            do {
                try await AuthManager.shared.resetPassword(email: email)
                await MainActor.run {
                    statusLabel.textColor = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
                    statusLabel.stringValue = "Reset email sent! Check your inbox."
                }
            } catch {
                await MainActor.run {
                    statusLabel.textColor = NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
                    statusLabel.stringValue = error.localizedDescription
                }
            }
        }
    }
}

extension LoginWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if !SessionManager.shared.isLoggedIn {
            delegate?.loginWindowDidCancel()
        }
    }
}
