import Cocoa
import os.log

private let log = OSLog(subsystem: "com.voice2txt.app", category: "clipboard")

class ClipboardManager {
    private var typedText = ""
    private let src = CGEventSource(stateID: .combinedSessionState)
    private let queue = DispatchQueue(label: "com.voice2txt.clipboard")

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        os_log("AXIsProcessTrusted: %{public}@", log: log, "\(trusted)")
        if !trusted {
            os_log("CGEvent posting requires Accessibility permission. Add this app in System Settings → Privacy & Security → Accessibility.", log: log, type: .error)
        }
    }

    /// Stream text into the frontmost app via clipboard + Cmd+V.
    func updateStreamingText(_ newText: String) {
        let commonLen = zip(typedText, newText).prefix(while: { $0 == $1 }).count
        let deleteCount = typedText.count - commonLen
        let newPart = String(newText.dropFirst(commonLen))
        typedText = newText

        queue.async {
            if deleteCount > 0 {
                self.pressBackspace(count: deleteCount)
                usleep(10_000) // 10ms for backspaces to process
            }
            if !newPart.isEmpty {
                self.pasteText(newPart)
                usleep(10_000) // 10ms for paste to process
            }
        }
    }

    func resetStreaming() {
        typedText = ""
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Private

    private func pasteText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Cmd+V (key code 9 = V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgSessionEventTap)
    }

    private func pressBackspace(count: Int) {
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: true)
            down?.post(tap: .cgSessionEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: false)
            up?.post(tap: .cgSessionEventTap)
        }
    }

}
