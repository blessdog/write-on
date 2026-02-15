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

        // Transcript label at the bottom
        transcriptLabel = NSTextField(frame: NSRect(x: 4, y: 0, width: panelW - 8, height: labelH))
        transcriptLabel.isEditable = false
        transcriptLabel.isSelectable = false
        transcriptLabel.isBezeled = false
        transcriptLabel.drawsBackground = false
        transcriptLabel.backgroundColor = .clear
        transcriptLabel.textColor = .white
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
    }
}
