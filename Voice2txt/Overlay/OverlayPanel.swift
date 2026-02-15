import Cocoa

class OverlayPanel: NSPanel {
    static let overlayWidth: CGFloat = 360
    static let overlayHeight: CGFloat = 130

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.overlayWidth, height: Self.overlayHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
    }

    func showOnMouseScreen() {
        let mouseLocation = NSEvent.mouseLocation

        let screen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let visibleFrame = screen.visibleFrame

        // Center horizontally, near bottom of visible area
        let x = visibleFrame.origin.x + (visibleFrame.width - Self.overlayWidth) / 2
        let y = visibleFrame.origin.y + 20

        setFrameOrigin(NSPoint(x: x, y: y))
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }
}
