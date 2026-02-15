import Cocoa
import os.log

private let log = OSLog(subsystem: "com.voice2txt.app", category: "clipboard")

class ClipboardManager {
    private let src = CGEventSource(stateID: .combinedSessionState)

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        os_log("AXIsProcessTrusted: %{public}@", log: log, "\(trusted)")
        if !trusted {
            os_log("CGEvent posting requires Accessibility permission. Add this app in System Settings → Privacy & Security → Accessibility.", log: log, type: .error)
        }
    }

    /// Copy text to clipboard and paste it into the frontmost app with a single Cmd+V.
    func pasteFromClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Small delay to ensure clipboard is set
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: .cgSessionEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: .cgSessionEventTap)
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func resetStreaming() {
        // No-op — kept for API compatibility
    }
}
