import Foundation
import Accelerate

class AudioLevelProcessor {
    let waveformPoints = 28

    /// Process raw Int16 PCM data into a 28-point waveform array (0.0–1.0).
    func processAudioData(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else {
            return Array(repeating: 0, count: waveformPoints)
        }

        // Convert Int16 samples to Float using vDSP
        let floatSamples: [Float] = data.withUnsafeBytes { buffer in
            let int16Ptr = buffer.bindMemory(to: Int16.self)
            var floats = [Float](repeating: 0, count: sampleCount)
            vDSP_vflt16(int16Ptr.baseAddress!, 1, &floats, 1, vDSP_Length(sampleCount))
            // Normalize to -1.0...1.0
            var scale: Float = 1.0 / 32768.0
            vDSP_vsmul(floats, 1, &scale, &floats, 1, vDSP_Length(sampleCount))
            return floats
        }

        let chunkSize = max(1, sampleCount / waveformPoints)
        var waveform = [Float](repeating: 0, count: waveformPoints)

        for p in 0..<waveformPoints {
            let start = p * chunkSize
            let end = min(start + chunkSize, sampleCount)
            let count = end - start
            guard count > 0 else { continue }

            // vDSP RMS
            var rms: Float = 0
            vDSP_rmsqv(floatSamples.withUnsafeBufferPointer { $0.baseAddress! + start }, 1, &rms, vDSP_Length(count))

            // Noise gate + perceptual boost
            if rms > 0.005 {
                waveform[p] = min(1.0, sqrt(rms) * 2.5)
            }
        }

        return waveform
    }
}
