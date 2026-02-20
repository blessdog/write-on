import Cocoa

class OverlayViewController: NSViewController {
    private(set) var waterfall: WaterfallView!
    private var transcriptLabel: NSTextField!
    private var shadowLabels: [NSTextField] = []
    private var pendingText: String?
    private var updateScheduled = false

    override func loadView() {
        let panelW = OverlayPanel.overlayWidth
        let panelH = OverlayPanel.overlayHeight
        let waterfallH: CGFloat = 90
        let labelH = panelH - waterfallH

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear

        // Waterfall view at the top
        waterfall = WaterfallView(
            frame: NSRect(x: (panelW - 260) / 2, y: labelH, width: 260, height: waterfallH)
        )
        waterfall.wantsLayer = true
        waterfall.layer?.backgroundColor = CGColor.clear

        // Shadow labels — stacked black text with increasing blur to create
        // a dark halo that's opaque right behind the text and fades outward.
        let labelFrame = NSRect(x: 4, y: 0, width: panelW - 8, height: labelH)
        let shadowConfigs: [(CGFloat, CGFloat)] = [
            (2,  1.0),
            (4,  1.0),
            (8,  0.9),
            (16, 0.7),
            (26, 0.4),
        ]
        for (i, config) in shadowConfigs.enumerated() {
            let shadowLabel = NSTextField(frame: labelFrame)
            shadowLabel.isEditable = false
            shadowLabel.isSelectable = false
            shadowLabel.isBezeled = false
            shadowLabel.drawsBackground = false
            shadowLabel.backgroundColor = .clear
            shadowLabel.textColor = NSColor.black.withAlphaComponent(config.1)
            shadowLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            shadowLabel.alignment = .center
            shadowLabel.lineBreakMode = .byTruncatingHead
            shadowLabel.maximumNumberOfLines = 2
            shadowLabel.cell?.truncatesLastVisibleLine = true
            shadowLabel.stringValue = ""
            shadowLabel.tag = 100 + i

            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(config.1)
            s.shadowOffset = NSSize(width: 0, height: 0)
            s.shadowBlurRadius = config.0
            shadowLabel.shadow = s

            container.addSubview(shadowLabel)
            shadowLabels.append(shadowLabel)
        }

        // Transcript label on top — teal text
        transcriptLabel = NSTextField(frame: labelFrame)
        transcriptLabel.isEditable = false
        transcriptLabel.isSelectable = false
        transcriptLabel.isBezeled = false
        transcriptLabel.drawsBackground = false
        transcriptLabel.backgroundColor = .clear
        transcriptLabel.textColor = NSColor(red: 0.24, green: 1, blue: 0.85, alpha: 1)
        transcriptLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        transcriptLabel.alignment = .center
        transcriptLabel.lineBreakMode = .byTruncatingHead
        transcriptLabel.maximumNumberOfLines = 2
        transcriptLabel.cell?.truncatesLastVisibleLine = true
        transcriptLabel.stringValue = ""

        container.addSubview(waterfall)
        container.addSubview(transcriptLabel)
        view = container
    }

    func updateTranscript(_ text: String) {
        pendingText = text
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let text = self.pendingText else { return }
            self.updateScheduled = false
            self.transcriptLabel.stringValue = text
            for shadow in self.shadowLabels {
                shadow.stringValue = text
            }
        }
    }
}
