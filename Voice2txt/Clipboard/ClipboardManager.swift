import Cocoa
import os.log

private let log = OSLog(subsystem: "com.writeon.app", category: "clipboard")

class ClipboardManager {
    private let src = CGEventSource(stateID: .combinedSessionState)

    private(set) var storedTranscript: String?

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        os_log("AXIsProcessTrusted: %{public}@", log: log, "\(trusted)")
        if !trusted {
            os_log("CGEvent posting requires Accessibility permission. Add this app in System Settings → Privacy & Security → Accessibility.", log: log, type: .error)
        }
    }

    func storeTranscript(_ text: String) {
        storedTranscript = text
    }

    func pasteStoredTranscript() {
        guard let transcript = storedTranscript, !transcript.isEmpty else { return }
        pasteText(transcript)
    }

    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let savedItems: [(NSPasteboard.PasteboardType, Data)] = pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                if let data = item.data(forType: type) {
                    return (type, data)
                }
                return nil
            }
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: .cgSessionEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: .cgSessionEventTap)

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                pasteboard.clearContents()
                if savedItems.isEmpty { return }
                let item = NSPasteboardItem()
                for (type, data) in savedItems {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
    }

    func resetStreaming() {
        // No-op — kept for API compatibility
    }
}
