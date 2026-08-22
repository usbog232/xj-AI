import Foundation

struct TranscriptSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var original: String
    var translation: String
    var isTranslationPending: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        original: String,
        translation: String = "",
        isTranslationPending: Bool = true
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.original = original
        self.translation = translation
        self.isTranslationPending = isTranslationPending
    }
}
