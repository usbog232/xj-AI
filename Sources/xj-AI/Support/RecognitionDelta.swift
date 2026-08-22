import Foundation

enum RecognitionDelta {
    private static let tailLimit = 48
    private static let directAnchorLimit = 12

    static func pendingText(
        formattedText: String,
        segments: [RecognizedSpeechSegment],
        committedTail: [String],
        committedThrough: TimeInterval
    ) -> String {
        let trimmedText = formattedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return "" }

        guard !segments.isEmpty else {
            // A non-empty Apple transcription normally includes segments. If it does not,
            // only accept the initial result; replaying later cumulative text would duplicate it.
            return committedTail.isEmpty ? trimmedText : ""
        }

        guard !committedTail.isEmpty else { return trimmedText }

        let indexedSegments = segments.compactMap { segment -> (RecognizedSpeechSegment, String)? in
            let normalized = normalize(segment.substring)
            return normalized.isEmpty ? nil : (segment, normalized)
        }
        let currentTokens = indexedSegments.map(\.1)
        guard !currentTokens.isEmpty else { return "" }

        guard let boundary = matchingBoundary(
            committedTail: committedTail,
            current: indexedSegments,
            committedThrough: committedThrough
        ) else {
            // Apple can start a fresh utterance and reset its text/timestamps. With no
            // meaningful textual overlap, this is new speech rather than cumulative text.
            return trimmedText
        }
        guard boundary < indexedSegments.count else { return "" }

        let firstPending = indexedSegments[boundary].0

        let nsText = formattedText as NSString
        let start = firstPending.substringRange.location
        if start >= 0, start <= nsText.length {
            return nsText.substring(from: start)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return indexedSegments[boundary...].map { $0.0.substring }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tail(in segments: [RecognizedSpeechSegment]) -> [String] {
        Array(segments.map(\.substring).map(normalize).filter { !$0.isEmpty }.suffix(tailLimit))
    }

    static func latestEndTime(in segments: [RecognizedSpeechSegment]) -> TimeInterval? {
        segments.map(\.endTime).max()
    }

    private static func matchingBoundary(
        committedTail: [String],
        current: [(RecognizedSpeechSegment, String)],
        committedThrough: TimeInterval
    ) -> Int? {
        let currentTokens = current.map(\.1)
        let maximumAnchor = min(directAnchorLimit, committedTail.count, currentTokens.count)

        if maximumAnchor > 0 {
            for length in stride(from: maximumAnchor, through: 1, by: -1) {
                if length == 1, committedTail.count > 1 { continue }
                let anchor = Array(committedTail.suffix(length))
                var matches: [Int] = []
                guard currentTokens.count >= length else { continue }
                for start in 0...(currentTokens.count - length) {
                    if Array(currentTokens[start..<(start + length)]) == anchor {
                        matches.append(start)
                    }
                }
                if !matches.isEmpty {
                    let bestStart = matches.min { lhs, rhs in
                        let lhsEnd = current[lhs + length - 1].0.endTime
                        let rhsEnd = current[rhs + length - 1].0.endTime
                        return abs(lhsEnd - committedThrough) < abs(rhsEnd - committedThrough)
                    } ?? matches[matches.count - 1]
                    return bestStart + length
                }
            }
        }

        return lcsBoundary(committedTail: committedTail, currentTokens: currentTokens)
    }

    private static func lcsBoundary(committedTail: [String], currentTokens: [String]) -> Int? {
        let old = Array(committedTail.suffix(tailLimit))
        let currentStart = max(0, currentTokens.count - tailLimit * 2)
        let new = Array(currentTokens[currentStart...])
        guard !old.isEmpty, !new.isEmpty else { return nil }

        var table = Array(
            repeating: Array(repeating: 0, count: new.count + 1),
            count: old.count + 1
        )
        for oldIndex in 1...old.count {
            for newIndex in 1...new.count {
                if old[oldIndex - 1] == new[newIndex - 1] {
                    table[oldIndex][newIndex] = table[oldIndex - 1][newIndex - 1] + 1
                } else {
                    table[oldIndex][newIndex] = max(
                        table[oldIndex - 1][newIndex],
                        table[oldIndex][newIndex - 1]
                    )
                }
            }
        }

        let matchCount = table[old.count][new.count]
        guard matchCount >= min(2, old.count) else { return nil }

        var oldIndex = old.count
        var newIndex = new.count
        var lastMatchedNewIndex: Int?
        while oldIndex > 0, newIndex > 0 {
            if old[oldIndex - 1] == new[newIndex - 1] {
                lastMatchedNewIndex = max(lastMatchedNewIndex ?? -1, newIndex - 1)
                oldIndex -= 1
                newIndex -= 1
            } else if table[oldIndex - 1][newIndex] >= table[oldIndex][newIndex - 1] {
                oldIndex -= 1
            } else {
                newIndex -= 1
            }
        }

        return lastMatchedNewIndex.map { currentStart + $0 + 1 }
    }

    private static func normalize(_ token: String) -> String {
        token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }
}
