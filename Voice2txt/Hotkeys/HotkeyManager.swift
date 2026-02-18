import Cocoa

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidStartRecording(mode: RecordingMode)
    func hotkeyManagerDidStopRecording()
    func hotkeyManagerDidRequestPaste()
}

// MARK: - Hotkey Configuration

enum LongHotkeyMode: String {
    case doubleTap
    case combo
}

struct LongHotkeyConfig {
    var mode: LongHotkeyMode = .doubleTap
    var keyCodes: Set<UInt16> = [59, 62]         // Left/Right Ctrl
    var modFlag: NSEvent.ModifierFlags = .control
    var comboKeyCode: UInt16 = 0                  // keyCode for combo mode (e.g. 17 = T)
    var display: String = "Double-tap Ctrl"
}

struct ShortHotkeyConfig {
    var keyCode: UInt16 = 61                      // Right Option
    var modFlag: NSEvent.ModifierFlags = .option
    var display: String = "Hold Right Option"
}

class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?

    // Modifier keyCode lookup
    static let modifierKeyCodes: [String: Set<UInt16>] = [
        "control": [59, 62],
        "command": [54, 55],
        "option":  [58, 61],
        "shift":   [56, 60],
    ]

    static let modifierFlagForName: [String: NSEvent.ModifierFlags] = [
        "control": .control,
        "command": .command,
        "option":  .option,
        "shift":   .shift,
    ]

    static let modifierNameForKeyCode: [UInt16: String] = {
        var map: [UInt16: String] = [:]
        for (name, codes) in modifierKeyCodes {
            for code in codes {
                map[code] = name
            }
        }
        return map
    }()

    static let displayNameForModifier: [String: String] = [
        "control": "Ctrl",
        "command": "Cmd",
        "option":  "Option",
        "shift":   "Shift",
    ]

    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var doubleTapTimestamps: [TimeInterval] = []
    private let doubleTapWindow: TimeInterval = 0.3

    private var holdKeyHeld = false
    private var isRecording = false
    private var previousFlags: NSEvent.ModifierFlags = []

    private(set) var longConfig = LongHotkeyConfig()
    private(set) var shortConfig = ShortHotkeyConfig()

    // MARK: - Config

    func loadConfig() {
        let defaults = UserDefaults.standard

        // Long hotkey
        if let modeStr = defaults.string(forKey: "hotkey.long.type"),
           let mode = LongHotkeyMode(rawValue: modeStr) {
            longConfig.mode = mode
        }
        if let codesArray = defaults.array(forKey: "hotkey.long.keyCodes") as? [Int], !codesArray.isEmpty {
            longConfig.keyCodes = Set(codesArray.map { UInt16($0) })
        }
        if defaults.object(forKey: "hotkey.long.modFlag") != nil {
            longConfig.modFlag = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "hotkey.long.modFlag")))
        }
        if defaults.object(forKey: "hotkey.long.comboKey") != nil {
            longConfig.comboKeyCode = UInt16(defaults.integer(forKey: "hotkey.long.comboKey"))
        }
        if let display = defaults.string(forKey: "hotkey.long.display") {
            longConfig.display = display
        }

        // Short hotkey
        if defaults.object(forKey: "hotkey.short.keyCode") != nil {
            shortConfig.keyCode = UInt16(defaults.integer(forKey: "hotkey.short.keyCode"))
        }
        if defaults.object(forKey: "hotkey.short.modFlag") != nil {
            shortConfig.modFlag = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: "hotkey.short.modFlag")))
        }
        if let display = defaults.string(forKey: "hotkey.short.display") {
            shortConfig.display = display
        }
    }

    func reloadConfig() {
        loadConfig()
        // Reset state so new config takes effect cleanly
        doubleTapTimestamps.removeAll()
        holdKeyHeld = false
    }

    static func saveLongConfig(_ config: LongHotkeyConfig) {
        let defaults = UserDefaults.standard
        defaults.set(config.mode.rawValue, forKey: "hotkey.long.type")
        defaults.set(config.keyCodes.map { Int($0) }, forKey: "hotkey.long.keyCodes")
        defaults.set(Int(config.modFlag.rawValue), forKey: "hotkey.long.modFlag")
        defaults.set(Int(config.comboKeyCode), forKey: "hotkey.long.comboKey")
        defaults.set(config.display, forKey: "hotkey.long.display")
    }

    static func saveShortConfig(_ config: ShortHotkeyConfig) {
        let defaults = UserDefaults.standard
        defaults.set(Int(config.keyCode), forKey: "hotkey.short.keyCode")
        defaults.set(Int(config.modFlag.rawValue), forKey: "hotkey.short.modFlag")
        defaults.set(config.display, forKey: "hotkey.short.display")
    }

    // MARK: - Start / Stop

    @discardableResult
    func start() -> Bool {
        loadConfig()

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

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

    // MARK: - Event Handling

    private func handleKeyDown(_ event: NSEvent) {
        // Ctrl+V (keyCode 9 = 'v') — paste stored transcript (always hardcoded)
        if event.keyCode == 9 && event.modifierFlags.contains(.control) &&
           !event.modifierFlags.contains(.command) {
            delegate?.hotkeyManagerDidRequestPaste()
        }

        // Combo mode for long recording: modifier+key toggles recording
        if longConfig.mode == .combo && event.keyCode == longConfig.comboKeyCode {
            if event.modifierFlags.contains(longConfig.modFlag) {
                if isRecording && !holdKeyHeld {
                    isRecording = false
                    delegate?.hotkeyManagerDidStopRecording()
                } else if !isRecording {
                    isRecording = true
                    delegate?.hotkeyManagerDidStartRecording(mode: .long)
                }
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags
        let keyCode = event.keyCode

        // Short recording: hold modifier key
        if keyCode == shortConfig.keyCode {
            if flags.contains(shortConfig.modFlag) {
                if !holdKeyHeld && !isRecording {
                    holdKeyHeld = true
                    isRecording = true
                    delegate?.hotkeyManagerDidStartRecording(mode: .short)
                }
            } else {
                if holdKeyHeld {
                    holdKeyHeld = false
                    if isRecording {
                        isRecording = false
                        delegate?.hotkeyManagerDidStopRecording()
                    }
                }
            }
            previousFlags = flags
            return
        }

        // Long recording: double-tap mode
        if longConfig.mode == .doubleTap && longConfig.keyCodes.contains(keyCode) {
            if flags.contains(longConfig.modFlag) {
                let now = ProcessInfo.processInfo.systemUptime

                if isRecording && !holdKeyHeld {
                    // Single tap of the modifier stops a long recording
                    isRecording = false
                    doubleTapTimestamps.removeAll()
                    delegate?.hotkeyManagerDidStopRecording()
                    previousFlags = flags
                    return
                }

                doubleTapTimestamps = doubleTapTimestamps.filter { now - $0 < doubleTapWindow }
                doubleTapTimestamps.append(now)

                if doubleTapTimestamps.count >= 2 {
                    doubleTapTimestamps.removeAll()
                    if !isRecording {
                        isRecording = true
                        delegate?.hotkeyManagerDidStartRecording(mode: .long)
                    }
                }
            }
        }

        previousFlags = flags
    }
}
