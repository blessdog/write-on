import AVFoundation

protocol AudioCaptureManagerDelegate: AnyObject {
    func audioCaptureManager(_ manager: AudioCaptureManager, didCapturePCMData data: Data)
}

class AudioCaptureManager {
    weak var delegate: AudioCaptureManagerDelegate?

    private var engine = AVAudioEngine()
    private var isCapturing = false

    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    func startCapture() {
        guard !isCapturing else { return }

        // Fresh engine each session to avoid stale input node format
        engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            print("Failed to create target audio format")
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let ratio = self.targetSampleRate / inputFormat.sampleRate
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error != nil { return }
            guard let int16Data = convertedBuffer.int16ChannelData else { return }

            let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: int16Data[0], count: byteCount)

            self.delegate?.audioCaptureManager(self, didCapturePCMData: data)
        }

        do {
            try engine.start()
            isCapturing = true
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }
}
