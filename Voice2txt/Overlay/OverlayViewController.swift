import Cocoa
import MetalKit

/// Transparent MTKView subclass that reports non-opaque to the window system.
class TransparentMTKView: MTKView {
    override var isOpaque: Bool { false }
}

class OverlayViewController: NSViewController {
    private let renderer: WaterfallRenderer
    private var mtkView: MTKView!
    private var transcriptLabel: NSTextField!

    init(renderer: WaterfallRenderer) {
        self.renderer = renderer
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func loadView() {
        let panelW = OverlayPanel.overlayWidth
        let panelH = OverlayPanel.overlayHeight
        let waterfallH: CGFloat = 90
        let labelH = panelH - waterfallH

        let container = NSView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        container.wantsLayer = true
        container.layer?.backgroundColor = CGColor.clear

        // Metal waterfall at the top
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            view = container
            return
        }

        mtkView = TransparentMTKView(
            frame: NSRect(x: (panelW - 260) / 2, y: labelH, width: 260, height: waterfallH),
            device: device
        )
        mtkView.delegate = renderer
        mtkView.preferredFramesPerSecond = 30
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.wantsLayer = true
        if let layer = mtkView.layer {
            layer.isOpaque = false
            layer.backgroundColor = CGColor.clear
        }
        renderer.setup(device: device, pixelFormat: mtkView.colorPixelFormat)

        // Shadow labels — stacked black text with increasing blur to create
        // a dark halo that's opaque right behind the text and fades outward.
        // No boxes, no backgrounds — just shadow.
        let labelFrame = NSRect(x: 4, y: 0, width: panelW - 8, height: labelH)
        let shadowConfigs: [(CGFloat, CGFloat)] = [
            // (blur radius, alpha) — tight and dark first, then wider and lighter
            (2,  1.0),   // near-zero blur, full black — dark right behind text
            (4,  1.0),   // tight glow
            (8,  0.9),   // medium spread
            (16, 0.7),   // wide fade
            (26, 0.4),   // outer haze
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

        container.addSubview(mtkView)
        container.addSubview(transcriptLabel)
        view = container
    }

    func updateTranscript(_ text: String) {
        transcriptLabel.stringValue = text
        for i in 0..<5 {
            if let shadow = view.subviews.first(where: { $0.tag == 100 + i }) as? NSTextField {
                shadow.stringValue = text
            }
        }
    }
}
