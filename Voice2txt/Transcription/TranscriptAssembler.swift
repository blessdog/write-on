import Foundation

class TranscriptAssembler {
    private var finalSegments: [String] = []
    private var pendingInterim: String = ""
    private static let punctuationRegex = try! NSRegularExpression(pattern: "([.!?])([A-Z])")

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
        return Self.punctuationRegex.stringByReplacingMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw),
            withTemplate: "$1 $2"
        )
    }

    func reset() {
        finalSegments.removeAll()
        pendingInterim = ""
    }
}
