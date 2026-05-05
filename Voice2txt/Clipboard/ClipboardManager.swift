import Cocoa
import IOKit.hid
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
        let inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        os_log("IOHIDCheckAccess (Input Monitoring): %{public}d", log: log, inputMonitoring.rawValue)
        if inputMonitoring != kIOHIDAccessTypeGranted {
            os_log("Some terminals (e.g. Ghostty) require Input Monitoring permission for synthetic Cmd+V to land. Add this app in System Settings → Privacy & Security → Input Monitoring.", log: log, type: .error)
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
        let writeChangeCount = pasteboard.changeCount

        // Pre-paste delay: give the pasteboard time to settle before posting
        // Cmd+V. 30ms loses the race in some apps; 80ms is safer.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { [self] in
            let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: .cgSessionEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: .cgSessionEventTap)

            // Restore delay: 100ms wasn't enough for terminals like Ghostty
            // that gate paste behind a confirmation prompt — we'd restore the
            // old clipboard before the user confirmed, and the actual paste
            // would read stale content. 2s covers the common confirm case.
            // Guard with changeCount so we don't clobber a copy the user made
            // in the meantime.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                guard pasteboard.changeCount == writeChangeCount else { return }
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
