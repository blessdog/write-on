import Foundation

class AudioLevelProcessor {
    let waveformPoints = 28

    /// Process raw Int16 PCM data into a 28-point waveform array (0.0–1.0).
    func processAudioData(_ data: Data) -> [Float] {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > 0 else {
            return Array(repeating: 0, count: waveformPoints)
        }

        let samples: [Int16] = data.withUnsafeBytes { buffer in
            let ptr = buffer.bindMemory(to: Int16.self)
            return Array(ptr)
        }

        let chunkSize = max(1, sampleCount / waveformPoints)
        var waveform = [Float]()
        waveform.reserveCapacity(waveformPoints)

        for p in 0..<waveformPoints {
            let start = p * chunkSize
            let end = min(start + chunkSize, sampleCount)

            // RMS of chunk
            var sumSquares: Float = 0
            for i in start..<end {
                let s = Float(samples[i]) / 32768.0
                sumSquares += s * s
            }
            let rms = sqrt(sumSquares / Float(max(1, end - start)))

            // Match Python: (rms^0.5) * 2.5, with noise gate at 0.005
            let boosted: Float
            if rms > 0.005 {
                boosted = min(1.0, sqrt(rms) * 2.5)
            } else {
                boosted = 0.0
            }
            waveform.append(boosted)
        }

        return waveform
    }
}
