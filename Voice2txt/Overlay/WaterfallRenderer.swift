import Cocoa

class WaterfallView: NSView {
    private let numLines = 16
    private let wavePoints = 28

    private var waveforms: [[Float]] = []
    private var isTranscribing = false
    private var frameCount: Int = 0
    private var animationTimer: Timer?

    private let tealR: CGFloat = 0.24
    private let tealG: CGFloat = 1.0
    private let tealB: CGFloat = 0.85

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    func pushWaveform(_ waveform: [Float]) {
        waveforms.insert(waveform, at: 0)
        if waveforms.count > numLines {
            waveforms.removeLast()
        }
    }

    func setTranscribing(_ transcribing: Bool) {
        isTranscribing = transcribing
    }

    func reset() {
        waveforms.removeAll()
        isTranscribing = false
        frameCount = 0
    }

    func startAnimation() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    func stopAnimation() {
        if Thread.isMainThread {
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.animationTimer?.invalidate()
                self?.animationTimer = nil
            }
        }
    }

    // MARK: - Drawing

    private var glowOffsets: [(CGFloat, CGFloat, CGFloat)] {
        [
            (0,    1,  0.3),   // below
            (0,   -1,  0.3),   // above
            (1,    0,  0.25),  // right
            (-1,   0,  0.25),  // left
        ]
    }

    override func draw(_ dirtyRect: NSRect) {
        frameCount += 1

        // Clear to transparent using .copy compositing (sourceOver would be a no-op with clear)
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)

        let viewW = bounds.width
        let viewH = bounds.height

        if isTranscribing {
            drawTranscribing(viewW: viewW, viewH: viewH)
        } else {
            drawWaterfall(viewW: viewW, viewH: viewH)
        }
    }

    private func drawWaterfall(viewW: CGFloat, viewH: CGFloat) {
        guard !waveforms.isEmpty else { return }

        let baseY: CGFloat = 10  // bottom-up in non-flipped coords
        let lineSpacing: CGFloat = 4.5
        let maxAmplitude: CGFloat = 30
        let waveWidth: CGFloat = viewW - 24
        let offsets = glowOffsets

        // Draw back-to-front: oldest rows first (highest index), newest last (index 0)
        for row in stride(from: waveforms.count - 1, through: 0, by: -1) {
            let waveform = waveforms[row]
            let frac = CGFloat(row) / CGFloat(max(numLines - 1, 1))
            let y = baseY + CGFloat(row) * lineSpacing

            let perspective: CGFloat = 1.0 - frac * 0.4
            let w = waveWidth * perspective
            let xOffset = (viewW - w) / 2
            let brightness: CGFloat = 1.0 - frac * 0.6

            // Precompute view-space points
            var points: [NSPoint] = []
            for (i, amp) in waveform.enumerated() {
                let px = xOffset + (CGFloat(i) / CGFloat(max(waveform.count - 1, 1))) * w
                let dy = CGFloat(amp) * maxAmplitude * perspective
                points.append(NSPoint(x: px, y: y + dy))
            }

            guard points.count >= 2 else { continue }

            // Shadow passes
            for (ox, oy, oa) in offsets {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: points[0].x + ox, y: points[0].y + oy))
                for p in points.dropFirst() {
                    path.line(to: NSPoint(x: p.x + ox, y: p.y + oy))
                }
                path.lineWidth = 1.0
                NSColor.black.withAlphaComponent(oa).setStroke()
                path.stroke()
            }

            // Bright teal line
            let path = NSBezierPath()
            path.move(to: points[0])
            for p in points.dropFirst() {
                path.line(to: p)
            }
            path.lineWidth = 1.0
            NSColor(red: tealR * brightness, green: tealG * brightness, blue: tealB * brightness, alpha: 1.0).setStroke()
            path.stroke()
        }
    }

    private func drawTranscribing(viewW: CGFloat, viewH: CGFloat) {
        let baseY: CGFloat = 10
        let lineSpacing: CGFloat = 4.5
        let waveWidth: CGFloat = viewW - 24
        let t = CGFloat(frameCount) * 0.05
        let offsets = glowOffsets

        let rowCount = min(8, numLines)
        for row in stride(from: rowCount - 1, through: 0, by: -1) {
            let frac = CGFloat(row) / CGFloat(numLines)
            let y = baseY + CGFloat(row) * lineSpacing
            let alpha: CGFloat = 1.0 - frac * 0.7

            var points: [NSPoint] = []
            for i in 0..<wavePoints {
                let px: CGFloat = 12 + (CGFloat(i) / CGFloat(wavePoints - 1)) * waveWidth
                let dy = sin(Float(t) + Float(i) * 0.3 + Float(row) * 0.5) * 3 * Float(alpha)
                points.append(NSPoint(x: px, y: y + CGFloat(dy)))
            }

            guard points.count >= 2 else { continue }

            // Shadow passes
            for (ox, oy, oa) in offsets {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: points[0].x + ox, y: points[0].y + oy))
                for p in points.dropFirst() {
                    path.line(to: NSPoint(x: p.x + ox, y: p.y + oy))
                }
                path.lineWidth = 1.0
                NSColor.black.withAlphaComponent(oa).setStroke()
                path.stroke()
            }

            // Bright teal line
            let path = NSBezierPath()
            path.move(to: points[0])
            for p in points.dropFirst() {
                path.line(to: p)
            }
            path.lineWidth = 1.0
            NSColor(red: tealR * alpha, green: tealG * alpha, blue: tealB * alpha, alpha: 1.0).setStroke()
            path.stroke()
        }
    }
}
