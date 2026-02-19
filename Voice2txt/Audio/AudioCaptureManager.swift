import AVFoundation
import CoreAudio

protocol AudioCaptureManagerDelegate: AnyObject {
    func audioCaptureManager(_ manager: AudioCaptureManager, didCapturePCMData data: Data)
}

struct AudioInputDevice {
    let id: AudioDeviceID
    let name: String
    let isBluetooth: Bool
}

class AudioCaptureManager {
    weak var delegate: AudioCaptureManagerDelegate?

    private var engine = AVAudioEngine()
    private var isCapturing = false
    private var savedSystemDefault: AudioDeviceID = 0

    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    /// Preferred device ID. Set to 0 to use built-in mic (or system default if no built-in).
    var preferredDeviceID: AudioDeviceID = 0

    // MARK: - Device Discovery

    static func availableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize) == noErr else {
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return []
        }

        var result: [AudioInputDevice] = []
        for deviceID in deviceIDs {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize) == noErr, streamSize > 0 else {
                continue
            }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(streamSize))
            defer { bufferListPointer.deallocate() }
            guard AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &streamSize, bufferListPointer) == noErr else {
                continue
            }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &name) == noErr,
               let cfName = name?.takeUnretainedValue() {
                let bt = isBluetooth(deviceID)
                result.append(AudioInputDevice(id: deviceID, name: cfName as String, isBluetooth: bt))
            }
        }
        return result
    }

    // MARK: - Device Helpers

    private static func isBluetooth(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport)
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func builtInMicID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for device in availableInputDevices() {
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &transport)
            if transport == kAudioDeviceTransportTypeBuiltIn {
                return device.id
            }
        }
        return nil
    }

    private static func getSystemDefaultInput() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return deviceID
    }

    private static func setSystemDefaultInput(_ deviceID: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID = deviceID
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &devID
        )
    }

    // MARK: - Capture

    func startCapture() {
        guard !isCapturing else { return }

        // Save current system default so we can restore it on stop
        savedSystemDefault = AudioCaptureManager.getSystemDefaultInput()

        // Resolve which device to use
        let targetDevice = resolveDeviceID(preferredDeviceID)

        // If we need a specific device, set it as system default
        // AVAudioEngine always uses the system default — AudioUnitSetProperty is unreliable
        if targetDevice != 0 && targetDevice != savedSystemDefault {
            v2log("AudioCapture: switching system input to device \(targetDevice)")
            AudioCaptureManager.setSystemDefaultInput(targetDevice)
            usleep(200_000) // 200ms for system to register
        }

        // Create engine — it picks up whatever is now the system default
        engine = AVAudioEngine()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        v2log("AudioCapture: format=\(inputFormat.sampleRate)Hz/\(inputFormat.channelCount)ch")

        guard inputFormat.sampleRate > 0 else {
            v2log("AudioCapture: invalid input format (0 Hz)")
            restoreSystemDefault()
            return
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            v2log("AudioCapture: failed to create target format")
            restoreSystemDefault()
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            v2log("AudioCapture: failed to create converter")
            restoreSystemDefault()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
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
            v2log("AudioCapture: failed to start engine: \(error)")
            restoreSystemDefault()
        }
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        restoreSystemDefault()
    }

    private func restoreSystemDefault() {
        // Only restore if the saved default was NOT Bluetooth
        // (If user had Bose as default, we switched to built-in — keep it that way)
        if savedSystemDefault != 0 && !AudioCaptureManager.isBluetooth(savedSystemDefault) {
            AudioCaptureManager.setSystemDefaultInput(savedSystemDefault)
        }
        savedSystemDefault = 0
    }

    /// Resolves preferred device to actual device ID.
    /// - 0 (default): use built-in mic
    /// - Bluetooth device: skip it, use built-in mic
    /// - Valid non-Bluetooth: use it
    /// - Invalid/disconnected: fall back to built-in mic
    private func resolveDeviceID(_ preferredID: AudioDeviceID) -> AudioDeviceID {
        if preferredID == 0 {
            if let builtIn = AudioCaptureManager.builtInMicID() {
                v2log("AudioCapture: using built-in mic (\(builtIn))")
                return builtIn
            }
            v2log("AudioCapture: no built-in mic, using system default")
            return 0
        }

        if AudioCaptureManager.isBluetooth(preferredID) {
            v2log("AudioCapture: preference is Bluetooth (\(preferredID)) — using built-in mic instead")
            if let builtIn = AudioCaptureManager.builtInMicID() {
                return builtIn
            }
            return 0
        }

        let devices = AudioCaptureManager.availableInputDevices()
        if devices.contains(where: { $0.id == preferredID }) {
            v2log("AudioCapture: using selected device \(preferredID)")
            return preferredID
        }

        v2log("AudioCapture: device \(preferredID) not found — using built-in mic")
        if let builtIn = AudioCaptureManager.builtInMicID() {
            return builtIn
        }
        return 0
    }
}
