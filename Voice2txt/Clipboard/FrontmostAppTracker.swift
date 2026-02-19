import Cocoa

class FrontmostAppTracker {
    private(set) var savedApp: NSRunningApplication?

    func saveFrontmostApp() {
        let app = NSWorkspace.shared.frontmostApplication
        // Don't save Voice2txt itself as the target
        if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
            savedApp = app
        }
        v2log("FrontmostAppTracker: saved \(savedApp?.localizedName ?? "nil") (\(savedApp?.bundleIdentifier ?? "?"))")
    }

    func reactivateSavedApp() {
        if #available(macOS 14.0, *) {
            savedApp?.activate()
        } else {
            savedApp?.activate(options: [])
        }
    }
}
