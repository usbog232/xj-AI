import Foundation

enum SpeechRecognitionEngine: String, CaseIterable, Identifiable, Sendable {
    case apple
    case localWhisper
    case lan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple 自带识别"
        case .localWhisper: "本地 Whisper"
        case .lan: "局域网识别"
        }
    }

    var shortTitle: String {
        switch self {
        case .apple: "Apple Speech"
        case .localWhisper: "Whisper 本地模型"
        case .lan: "局域网 ASR"
        }
    }

    var symbol: String {
        switch self {
        case .apple: "apple.logo"
        case .localWhisper: "cpu"
        case .lan: "network"
        }
    }
}

enum LANRecognitionProtocol: String, CaseIterable, Identifiable, Sendable {
    case openAI
    case whisperCpp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI 兼容"
        case .whisperCpp: "whisper.cpp Server"
        }
    }

    var exampleURL: String {
        switch self {
        case .openAI: "http://192.168.1.20:8000/v1"
        case .whisperCpp: "http://192.168.1.20:8080"
        }
    }

    var endpointDescription: String {
        switch self {
        case .openAI: "请求 /v1/audio/transcriptions，可兼容常见 Whisper/Faster-Whisper 服务。"
        case .whisperCpp: "请求 whisper.cpp 官方 /inference multipart 接口。"
        }
    }
}

struct LocalSpeechModel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let fileName: String
    let sizeLabel: String
    let languagesLabel: String
    let summary: String
    let downloadURL: URL

    static let catalog: [LocalSpeechModel] = [
        model(
            id: "tiny-q5_1",
            title: "Tiny Q5",
            fileName: "ggml-tiny-q5_1.bin",
            size: "31 MB",
            languages: "多语",
            summary: "最快、占用最小，适合实时字幕；精度较低。"
        ),
        model(
            id: "tiny.en-q5_1",
            title: "Tiny English Q5",
            fileName: "ggml-tiny.en-q5_1.bin",
            size: "31 MB",
            languages: "英语",
            summary: "最快，仅识别英语。"
        ),
        model(
            id: "base-q5_1",
            title: "Base Q5",
            fileName: "ggml-base-q5_1.bin",
            size: "57 MB",
            languages: "多语",
            summary: "速度与准确率更均衡，推荐日常使用。"
        ),
        model(
            id: "base.en-q5_1",
            title: "Base English Q5",
            fileName: "ggml-base.en-q5_1.bin",
            size: "57 MB",
            languages: "英语",
            summary: "仅英语，比多语 Base 更稳定。"
        ),
        model(
            id: "small-q5_1",
            title: "Small Q5",
            fileName: "ggml-small-q5_1.bin",
            size: "182 MB",
            languages: "多语",
            summary: "准确率更高，首次加载和识别会稍慢。"
        )
    ]

    private static func model(
        id: String,
        title: String,
        fileName: String,
        size: String,
        languages: String,
        summary: String
    ) -> LocalSpeechModel {
        LocalSpeechModel(
            id: id,
            title: title,
            fileName: fileName,
            sizeLabel: size,
            languagesLabel: languages,
            summary: summary,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
        )
    }
}

struct ChunkRecognitionConfiguration: Sendable {
    let engine: SpeechRecognitionEngine
    let language: String
    let localModelURL: URL?
    let lanProtocol: LANRecognitionProtocol
    let lanBaseURL: String
    let lanModel: String
    let lanAPIKey: String
    let chunkDuration: TimeInterval
}
