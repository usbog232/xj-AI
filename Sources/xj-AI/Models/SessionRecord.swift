import Foundation

struct SessionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    let createdAt: Date
    var duration: TimeInterval
    var source: AudioSource
    var sourceLanguage: String
    var targetLanguage: String
    var translationModel: String
    var segments: [TranscriptSegment]
    var audioFileName: String?

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        source: AudioSource = .microphone,
        sourceLanguage: String = "auto",
        targetLanguage: String = "zh-CN",
        translationModel: String = "qwen3:4b",
        segments: [TranscriptSegment] = [],
        audioFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.translationModel = translationModel
        self.segments = segments
        self.audioFileName = audioFileName
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case srt
    case vtt
    case txt

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var symbol: String { self == .txt ? "doc.text" : "captions.bubble" }
}

enum RecordingPhase: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .preparing, .recording, .stopping: true
        default: false
        }
    }

    var isRecording: Bool { self == .recording }
}
