import Cocoa

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidStartRecording(mode: RecordingMode)
    func hotkeyManagerDidStopRecording()
    func hotkeyManagerDidRequestPaste()
}

class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var ctrlPressTimestamps: [TimeInterval] = []
    private let doubleTapWindow: TimeInterval = 0.3

    private var rightOptionHeld = false
    private var isRecording = false

    // Track previous modifier flags to detect press vs release
    private var previousFlags: NSEvent.ModifierFlags = []

    @discardableResult
    func start() -> Bool {
        // Use NSEvent global monitor — works reliably with NSApplication's event loop
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Monitor key-down events for Ctrl+V paste trigger
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        if flagsMonitor == nil {
            print("Failed to create global event monitor.")
            return false
        }
        return true
    }

    func stop() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Ctrl+V (keyCode 9 = 'v') — paste stored transcript
        if event.keyCode == 9 && event.modifierFlags.contains(.control) &&
           !event.modifierFlags.contains(.command) {
            delegate?.hotkeyManagerDidRequestPaste()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let keyCode = event.keyCode

        // Right Option: keyCode 61
        if keyCode == 61 {
            if flags.contains(.option) {
                // Right Option pressed
                if !rightOptionHeld && !isRecording {
                    rightOptionHeld = true
                    isRecording = true
                    delegate?.hotkeyManagerDidStartRecording(mode: .short)
                }
            } else {
                // Right Option released
                if rightOptionHeld {
                    rightOptionHeld = false
                    if isRecording {
                        isRecording = false
                        delegate?.hotkeyManagerDidStopRecording()
                    }
                }
            }
            previousFlags = flags
            return
        }

        // Control keys: 59 (left), 62 (right)
        if keyCode == 59 || keyCode == 62 {
            if flags.contains(.control) {
                // Control pressed
                let now = ProcessInfo.processInfo.systemUptime

                if isRecording && !rightOptionHeld {
                    // Single Ctrl stops a long recording
                    isRecording = false
                    ctrlPressTimestamps.removeAll()
                    delegate?.hotkeyManagerDidStopRecording()
                    previousFlags = flags
                    return
                }

                // Track press times for double-tap detection
                ctrlPressTimestamps = ctrlPressTimestamps.filter { now - $0 < doubleTapWindow }
                ctrlPressTimestamps.append(now)

                if ctrlPressTimestamps.count >= 2 {
                    ctrlPressTimestamps.removeAll()
                    if !isRecording {
                        isRecording = true
                        delegate?.hotkeyManagerDidStartRecording(mode: .long)
                    }
                }
            }
            // Ctrl release — ignored, we only track presses
        }

        previousFlags = flags
    }
}
