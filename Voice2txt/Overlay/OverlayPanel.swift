import Cocoa

class OverlayPanel: NSPanel {
    static let overlayWidth: CGFloat = 360
    static let overlayHeight: CGFloat = 130

    private var currentScreenIndex: Int = -1

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
        let screen = screenForMouse()
        positionOnScreen(screen)
        orderFrontRegardless()
    }

    func followMouse() {
        let screen = screenForMouse()
        let newIndex = NSScreen.screens.firstIndex(of: screen) ?? 0

        if newIndex != currentScreenIndex {
            currentScreenIndex = newIndex
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrameOrigin(positionForScreen(screen))
            }
        }
    }

    func hide() {
        orderOut(nil)
        currentScreenIndex = -1
    }

    private func screenForMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func positionForScreen(_ screen: NSScreen) -> NSPoint {
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.origin.x + (visibleFrame.width - Self.overlayWidth) / 2
        let y = visibleFrame.origin.y + 20
        return NSPoint(x: x, y: y)
    }

    private func positionOnScreen(_ screen: NSScreen) {
        currentScreenIndex = NSScreen.screens.firstIndex(of: screen) ?? 0
        setFrameOrigin(positionForScreen(screen))
    }
}
