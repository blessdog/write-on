import Foundation

enum RecordingMode {
    case long   // double-tap Ctrl
    case short  // hold Right Option
}

enum AppState {
    case idle
    case recording(RecordingMode)
    case transcribing
}

class AppStateManager {
    private(set) var state: AppState = .idle

    var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = state { return true }
        return false
    }

    func transition(to newState: AppState) {
        state = newState
    }
}
