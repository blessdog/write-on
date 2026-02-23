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
    // Legacy modifier-only mode (isModifier == true): uses keyCode + modFlag
    var keyCode: UInt16 = 61                      // Right Option
    var modFlag: NSEvent.ModifierFlags = .option

    // Two-key combo mode (isModifier == false): uses key1 + key2
    // key1/key2 can be ANY keys (regular or modifier keyCodes)
    var key1: UInt16 = 0
    var key2: UInt16 = 0

    var isModifier: Bool = true
    var display: String = "Hold Right Option"
}

// MARK: - CGEventTap callback (file-scope, @convention(c))

private func shortKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    // Re-enable tap if macOS disables it due to timeout
    if type == .tapDisabledByTimeout {
        if let tap = manager.shortKeyEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let key1 = manager.shortConfig.key1
    let key2 = manager.shortConfig.key2

    // Safety: don't match if keys aren't configured
    if key1 == 0 && key2 == 0 { return Unmanaged.passRetained(event) }

    guard keyCode == key1 || keyCode == key2 else {
        return Unmanaged.passRetained(event)
    }

    if type == .keyDown {
        // Ignore key repeats
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            if manager.shortKey1Held && manager.shortKey2Held { return nil }
            return Unmanaged.passRetained(event)
        }

        if keyCode == key1 { manager.shortKey1Held = true }
        if keyCode == key2 { manager.shortKey2Held = true }

        // Both keys held — start recording
        if manager.shortKey1Held && manager.shortKey2Held && !manager.isRecording {
            manager.isRecording = true
            manager.holdKeyHeld = true
            DispatchQueue.main.async {
                manager.delegate?.hotkeyManagerDidStartRecording(mode: .short)
            }
        }

        // Suppress the key if either key of our combo is involved
        if manager.shortKey1Held && manager.shortKey2Held {
            return nil
        }
        // If only one key is held, pass through (it might be a normal keystroke)
        return Unmanaged.passRetained(event)
    }

    if type == .keyUp {
        if keyCode == key1 { manager.shortKey1Held = false }
        if keyCode == key2 { manager.shortKey2Held = false }

        if manager.holdKeyHeld {
            manager.holdKeyHeld = false
            if manager.isRecording {
                manager.isRecording = false
                DispatchQueue.main.async {
                    manager.delegate?.hotkeyManagerDidStopRecording()
                }
            }
            return nil // suppress
        }
        return Unmanaged.passRetained(event)
    }

    return Unmanaged.passRetained(event)
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

    // fileprivate so the CGEventTap callback can access them
    fileprivate var holdKeyHeld = false
    fileprivate var isRecording = false
    fileprivate var shortKey1Held = false
    fileprivate var shortKey2Held = false
    private var previousFlags: NSEvent.ModifierFlags = []

    // CGEventTap for two-key short recording
    fileprivate var shortKeyEventTap: CFMachPort?
    private var shortKeyRunLoopSource: CFRunLoopSource?

    private(set) var longConfig = LongHotkeyConfig()
    fileprivate(set) var shortConfig = ShortHotkeyConfig()

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
        if defaults.object(forKey: "hotkey.short.key1") != nil {
            shortConfig.key1 = UInt16(defaults.integer(forKey: "hotkey.short.key1"))
        }
        if defaults.object(forKey: "hotkey.short.key2") != nil {
            shortConfig.key2 = UInt16(defaults.integer(forKey: "hotkey.short.key2"))
        }
        if defaults.object(forKey: "hotkey.short.isModifier") != nil {
            shortConfig.isModifier = defaults.bool(forKey: "hotkey.short.isModifier")
        } else {
            shortConfig.isModifier = true // backward compat: default to modifier mode
        }
        // Migration: if combo mode but key1/key2 were never saved, reset to modifier mode
        if !shortConfig.isModifier && shortConfig.key1 == 0 && shortConfig.key2 == 0 {
            shortConfig.isModifier = true
            shortConfig.keyCode = 61
            shortConfig.modFlag = .option
            shortConfig.display = "Hold Right Option"
            // Persist the fix
            defaults.set(true, forKey: "hotkey.short.isModifier")
            defaults.set(Int(61), forKey: "hotkey.short.keyCode")
            defaults.set(Int(NSEvent.ModifierFlags.option.rawValue), forKey: "hotkey.short.modFlag")
            defaults.set("Hold Right Option", forKey: "hotkey.short.display")
        }
        if let display = defaults.string(forKey: "hotkey.short.display") {
            shortConfig.display = display
        }
    }

    func reloadConfig() {
        let wasCombo = !shortConfig.isModifier
        loadConfig()
        // Reset state so new config takes effect cleanly
        doubleTapTimestamps.removeAll()
        holdKeyHeld = false
        shortKey1Held = false
        shortKey2Held = false

        // Reinstall or remove CGEventTap based on new config
        if shortConfig.isModifier {
            removeShortKeyEventTap()
        } else if !wasCombo || shortKeyEventTap == nil {
            removeShortKeyEventTap()
            installShortKeyEventTap()
        } else {
            // Config changed but still combo mode — reinstall with new keyCodes
            removeShortKeyEventTap()
            installShortKeyEventTap()
        }
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
        defaults.set(Int(config.key1), forKey: "hotkey.short.key1")
        defaults.set(Int(config.key2), forKey: "hotkey.short.key2")
        defaults.set(config.isModifier, forKey: "hotkey.short.isModifier")
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

        // Install CGEventTap for two-key short recording
        if !shortConfig.isModifier {
            installShortKeyEventTap()
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
        removeShortKeyEventTap()
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

        // Short recording: hold modifier key (only when configured for modifier mode)
        if shortConfig.isModifier && keyCode == shortConfig.keyCode {
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

        // Two-key combo: track modifier keyCodes via flagsChanged
        // (CGEventTap only sees regular keyDown/keyUp, not modifier changes)
        if !shortConfig.isModifier {
            let key1 = shortConfig.key1
            let key2 = shortConfig.key2
            let isKey1Modifier = HotkeyManager.modifierNameForKeyCode[key1] != nil
            let isKey2Modifier = HotkeyManager.modifierNameForKeyCode[key2] != nil

            if isKey1Modifier && keyCode == key1 {
                let modName = HotkeyManager.modifierNameForKeyCode[key1]!
                let modFlag = HotkeyManager.modifierFlagForName[modName]!
                shortKey1Held = flags.contains(modFlag)
            }
            if isKey2Modifier && keyCode == key2 {
                let modName = HotkeyManager.modifierNameForKeyCode[key2]!
                let modFlag = HotkeyManager.modifierFlagForName[modName]!
                shortKey2Held = flags.contains(modFlag)
            }

            if shortKey1Held && shortKey2Held && !isRecording {
                isRecording = true
                holdKeyHeld = true
                delegate?.hotkeyManagerDidStartRecording(mode: .short)
            } else if holdKeyHeld && (!shortKey1Held || !shortKey2Held) {
                holdKeyHeld = false
                if isRecording {
                    isRecording = false
                    delegate?.hotkeyManagerDidStopRecording()
                }
            }

            // Only return early if this event was for one of our combo keys
            if (isKey1Modifier && keyCode == key1) || (isKey2Modifier && keyCode == key2) {
                previousFlags = flags
                return
            }
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

    // MARK: - CGEventTap for Two-Key Short Recording

    private func installShortKeyEventTap() {
        // Only install if at least one key is a regular (non-modifier) key
        let key1IsMod = HotkeyManager.modifierNameForKeyCode[shortConfig.key1] != nil
        let key2IsMod = HotkeyManager.modifierNameForKeyCode[shortConfig.key2] != nil
        if key1IsMod && key2IsMod {
            // Both keys are modifiers — handled entirely via flagsChanged, no tap needed
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue),
            callback: shortKeyEventTapCallback,
            userInfo: refcon
        ) else {
            print("Failed to create CGEventTap — check Accessibility permissions")
            return
        }

        shortKeyEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        shortKeyRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeShortKeyEventTap() {
        if let source = shortKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            shortKeyRunLoopSource = nil
        }
        if let tap = shortKeyEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            shortKeyEventTap = nil
        }
    }
}
