import Foundation

class TranscriptAssembler {
    private var finalSegments: [String] = []
    private var pendingInterim: String = ""

    func addResult(text: String, isFinal: Bool) {
        if isFinal {
            finalSegments.append(text)
            pendingInterim = ""
        } else {
            pendingInterim = text
        }
    }

    var fullTranscript: String {
        var parts = finalSegments
        if !pendingInterim.isEmpty {
            parts.append(pendingInterim)
        }
        let raw = parts.joined(separator: " ")
        // Deepgram sometimes omits spaces after sentence-ending punctuation
        return raw.replacingOccurrences(
            of: "([.!?])([A-Z])",
            with: "$1 $2",
            options: .regularExpression
        )
    }

    func reset() {
        finalSegments.removeAll()
        pendingInterim = ""
    }
}
