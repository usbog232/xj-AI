import Foundation
import XCTest
@testable import xj_AI

final class RecognitionDeltaTests: XCTestCase {
    func testInitialRecognitionReturnsWholeFormattedText() {
        let text = "Hello, world."
        let segments = makeSegments(["Hello", "world"], in: text)

        XCTAssertEqual(
            RecognitionDelta.pendingText(
                formattedText: text,
                segments: segments,
                committedTail: [],
                committedThrough: -1
            ),
            "Hello, world."
        )
    }

    func testEarlierRevisionDoesNotReplayCommittedTranscript() {
        let revised = "I think they're trying out the midterm results."
        let segments = makeSegments(
            ["I", "think", "they're", "trying", "out", "the", "midterm", "results"],
            in: revised
        )

        XCTAssertEqual(
            RecognitionDelta.pendingText(
                formattedText: revised,
                segments: segments,
                committedTail: ["i", "think", "they", "are", "trying"],
                committedThrough: 4
            ),
            "out the midterm results."
        )
    }

    func testNoNewTimestampReturnsNoDuplicateText() {
        let revised = "I think they're trying."
        let segments = makeSegments(["I", "think", "they're", "trying"], in: revised)

        XCTAssertEqual(
            RecognitionDelta.pendingText(
                formattedText: revised,
                segments: segments,
                committedTail: ["i", "think", "they're", "trying"],
                committedThrough: 4
            ),
            ""
        )
    }

    func testTimestampResetStillReturnsFollowingWords() {
        let next = "I think they're trying out the midterm results."
        let segments = makeSegments(
            ["I", "think", "they're", "trying", "out", "the", "midterm", "results"],
            in: next
        )

        XCTAssertEqual(
            RecognitionDelta.pendingText(
                formattedText: next,
                segments: segments,
                committedTail: ["i", "think", "they're", "trying"],
                committedThrough: 38
            ),
            "out the midterm results."
        )
    }

    func testFreshUtteranceWithoutOverlapIsAccepted() {
        let next = "A completely new sentence starts here."
        let segments = makeSegments(
            ["A", "completely", "new", "sentence", "starts", "here"],
            in: next
        )

        XCTAssertEqual(
            RecognitionDelta.pendingText(
                formattedText: next,
                segments: segments,
                committedTail: ["the", "previous", "utterance"],
                committedThrough: 38
            ),
            next
        )
    }

    private func makeSegments(_ words: [String], in text: String) -> [RecognizedSpeechSegment] {
        let nsText = text as NSString
        var cursor = 0
        return words.enumerated().map { index, word in
            let searchRange = NSRange(location: cursor, length: nsText.length - cursor)
            let range = nsText.range(of: word, options: [], range: searchRange)
            cursor = range.location + range.length
            return RecognizedSpeechSegment(
                substring: word,
                timestamp: TimeInterval(index),
                duration: 1,
                substringRange: range
            )
        }
    }
}
