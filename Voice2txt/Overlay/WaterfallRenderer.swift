import Foundation
import MetalKit
import simd

struct WaterfallVertex {
    var px: Float
    var py: Float
    var r: Float
    var g: Float
    var b: Float
    var a: Float
}

class WaterfallRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice?
    private var pipelineState: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?

    private let numLines = 16
    private let wavePoints = 28

    private var waveforms: [[Float]] = []
    private var isTranscribing = false
    private var frameCount: Int = 0

    private let viewWidth: Float = 260
    private let viewHeight: Float = 90

    // Brand teal color (0.24, 1.0, 0.85)
    private let tealR: Float = 0.24
    private let tealG: Float = 1.0
    private let tealB: Float = 0.85

    func setup(device: MTLDevice, pixelFormat: MTLPixelFormat) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load Metal library")
            return
        }

        let vertexFunction = library.makeFunction(name: "waterfallVertex")
        let fragmentFunction = library.makeFunction(name: "waterfallFragment")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        // Alpha blending for transparent background
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Vertex descriptor matching WaterfallVertex struct
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 8   // 2 floats (px, py) = 8 bytes
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = 24      // 6 floats = 24 bytes

        descriptor.vertexDescriptor = vertexDescriptor

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to create pipeline state: \(error)")
        }
    }

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

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        frameCount += 1

        guard let pipelineState = pipelineState,
              let commandQueue = commandQueue,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)

        let vertices: [WaterfallVertex]

        if isTranscribing {
            vertices = buildTranscribingVertices()
        } else {
            vertices = buildWaterfallVertices()
        }

        if !vertices.isEmpty {
            let buffer = device?.makeBuffer(
                bytes: vertices,
                length: vertices.count * MemoryLayout<WaterfallVertex>.stride,
                options: .storageModeShared
            )

            if let buffer = buffer {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)

                let lineCount = vertices.count / wavePoints
                for line in 0..<lineCount {
                    encoder.drawPrimitives(
                        type: .lineStrip,
                        vertexStart: line * wavePoints,
                        vertexCount: wavePoints
                    )
                }
            }
        }

        encoder.endEncoding()
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    // MARK: - Vertex Building

    // Subtle shadow offsets for waveform lines — just enough contrast
    private var glowOffsets: [(Float, Float, Float)] {
        let px: Float = 1.0 / viewWidth * 2.0
        let py: Float = 1.0 / viewHeight * 2.0
        return [
            (0,       py * 2,  0.35),  // below
            (0,      -py * 2,  0.35),  // above
            (px * 2,  0,       0.3),   // right
            (-px * 2, 0,       0.3),   // left
        ]
    }

    private func buildWaterfallVertices() -> [WaterfallVertex] {
        guard !waveforms.isEmpty else { return [] }

        var shadowVertices: [WaterfallVertex] = []
        var brightVertices: [WaterfallVertex] = []
        let baseY: Float = viewHeight - 10
        let lineSpacing: Float = 4.5
        let maxAmplitude: Float = 30
        let waveWidth: Float = viewWidth - 24
        let offsets = glowOffsets

        for row in stride(from: waveforms.count - 1, through: 0, by: -1) {
            let waveform = waveforms[row]
            let frac = Float(row) / Float(max(numLines - 1, 1))
            let y = baseY - Float(row) * lineSpacing

            let perspective: Float = 1.0 - frac * 0.4
            let w = waveWidth * perspective
            let xOffset = (viewWidth - w) / 2
            let brightness: Float = 1.0 - frac * 0.6

            // Precompute NDC coords for this row
            var ndcCoords: [(Float, Float)] = []
            for (i, amp) in waveform.enumerated() {
                let px = xOffset + (Float(i) / Float(max(waveform.count - 1, 1))) * w
                let dy = amp * maxAmplitude * perspective
                let ndcX = (px / viewWidth) * 2.0 - 1.0
                let ndcY = 1.0 - ((y - dy) / viewHeight) * 2.0
                ndcCoords.append((ndcX, ndcY))
            }

            // Each glow offset produces one complete line strip
            for (ox, oy, oa) in offsets {
                for (ndcX, ndcY) in ndcCoords {
                    shadowVertices.append(WaterfallVertex(
                        px: ndcX + ox, py: ndcY + oy,
                        r: 0, g: 0, b: 0, a: oa
                    ))
                }
            }

            // Bright line strip — teal scaled by brightness
            for (ndcX, ndcY) in ndcCoords {
                brightVertices.append(WaterfallVertex(
                    px: ndcX, py: ndcY,
                    r: tealR * brightness, g: tealG * brightness, b: tealB * brightness, a: 1.0
                ))
            }
        }

        return shadowVertices + brightVertices
    }

    private func buildTranscribingVertices() -> [WaterfallVertex] {
        var shadowVertices: [WaterfallVertex] = []
        var brightVertices: [WaterfallVertex] = []
        let baseY: Float = viewHeight - 10
        let lineSpacing: Float = 4.5
        let waveWidth: Float = viewWidth - 24
        let t = Float(frameCount) * 0.05
        let offsets = glowOffsets

        let rowCount = min(8, numLines)
        for row in stride(from: rowCount - 1, through: 0, by: -1) {
            let frac = Float(row) / Float(numLines)
            let y = baseY - Float(row) * lineSpacing
            let alpha: Float = 1.0 - frac * 0.7

            // Precompute NDC coords for this row
            var ndcCoords: [(Float, Float)] = []
            for i in 0..<wavePoints {
                let px: Float = 12 + (Float(i) / Float(wavePoints - 1)) * waveWidth
                let dy = sin(t + Float(i) * 0.3 + Float(row) * 0.5) * 3 * alpha
                let ndcX = (px / viewWidth) * 2.0 - 1.0
                let ndcY = 1.0 - ((y + dy) / viewHeight) * 2.0
                ndcCoords.append((ndcX, ndcY))
            }

            // Each glow offset produces one complete line strip
            for (ox, oy, oa) in offsets {
                for (ndcX, ndcY) in ndcCoords {
                    shadowVertices.append(WaterfallVertex(
                        px: ndcX + ox, py: ndcY + oy,
                        r: 0, g: 0, b: 0, a: oa
                    ))
                }
            }

            // Bright line strip — teal scaled by alpha
            for (ndcX, ndcY) in ndcCoords {
                brightVertices.append(WaterfallVertex(
                    px: ndcX, py: ndcY,
                    r: tealR * alpha, g: tealG * alpha, b: tealB * alpha, a: 1.0
                ))
            }
        }

        return shadowVertices + brightVertices
    }
}
