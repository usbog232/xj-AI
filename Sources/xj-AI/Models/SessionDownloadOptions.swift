import Foundation

enum SessionDownloadKind: String, CaseIterable, Identifiable {
    case subtitles
    case audio

    var id: String { rawValue }
    var title: String { self == .subtitles ? "字幕" : "音频" }
    var symbol: String { self == .subtitles ? "captions.bubble" : "waveform" }
}

enum SubtitleDownloadContent: String, CaseIterable, Identifiable {
    case original
    case translation
    case bilingual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原文"
        case .translation: "译文"
        case .bilingual: "双语"
        }
    }
}

enum AudioDownloadFormat: String, CaseIterable, Identifiable {
    case mp3
    case wav

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct SessionDownloadOptions: Equatable {
    var kind: SessionDownloadKind = .subtitles
    var subtitleContent: SubtitleDownloadContent = .bilingual
    var subtitleFormat: ExportFormat = .srt
    var audioFormat: AudioDownloadFormat = .mp3
}
