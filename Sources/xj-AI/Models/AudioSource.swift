import Foundation

enum AudioSource: String, CaseIterable, Codable, Identifiable {
    case microphone
    case systemAudio
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "麦克风"
        case .systemAudio: "系统音频"
        case .application: "选择应用"
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic"
        case .systemAudio: "speaker.wave.2"
        case .application: "macwindow"
        }
    }
}

struct CapturableApplication: Identifiable, Hashable {
    let id: String
    let name: String
    let processID: Int32
}

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let title: String

    static let sourceLanguages = [
        LanguageOption(id: "auto", title: "自动检测"),
        LanguageOption(id: "en-US", title: "英语（美国）"),
        LanguageOption(id: "zh-CN", title: "简体中文"),
        LanguageOption(id: "ja-JP", title: "日语"),
        LanguageOption(id: "ko-KR", title: "韩语"),
        LanguageOption(id: "fr-FR", title: "法语"),
        LanguageOption(id: "de-DE", title: "德语"),
        LanguageOption(id: "es-ES", title: "西班牙语")
    ]

    static let targetLanguages = [
        LanguageOption(id: "zh-CN", title: "简体中文"),
        LanguageOption(id: "en-US", title: "英语"),
        LanguageOption(id: "ja-JP", title: "日语"),
        LanguageOption(id: "ko-KR", title: "韩语"),
        LanguageOption(id: "fr-FR", title: "法语"),
        LanguageOption(id: "de-DE", title: "德语"),
        LanguageOption(id: "es-ES", title: "西班牙语")
    ]

    static func title(for identifier: String, in options: [LanguageOption]) -> String {
        options.first(where: { $0.id == identifier })?.title ?? identifier
    }
}
