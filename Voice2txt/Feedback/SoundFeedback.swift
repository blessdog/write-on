import AppKit

class SoundFeedback {
    func playStartSound() {
        NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)?.play()
    }

    func playStopSound() {
        NSSound(contentsOfFile: "/System/Library/Sounds/Pop.aiff", byReference: true)?.play()
    }
}
