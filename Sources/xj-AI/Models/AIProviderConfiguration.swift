import Foundation

enum AIProviderKind: String, Codable, CaseIterable, Identifiable {
    case openAI
    case deepSeek
    case ollama
    case llamaCpp
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .ollama: "Ollama"
        case .llamaCpp: "llama.cpp"
        case .custom: "自定义"
        }
    }

    var symbol: String {
        switch self {
        case .openAI: "sparkles"
        case .deepSeek: "brain.head.profile"
        case .ollama: "desktopcomputer"
        case .llamaCpp: "server.rack"
        case .custom: "slider.horizontal.3"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com/v1"
        case .ollama: "http://127.0.0.1:11434/v1"
        case .llamaCpp: "http://127.0.0.1:8080/v1"
        case .custom: "http://127.0.0.1:8080/v1"
        }
    }

    var defaultModels: [String] {
        switch self {
        case .openAI: ["gpt-4o-mini"]
        case .deepSeek: ["deepseek-chat"]
        case .ollama: ["qwen3:4b"]
        case .llamaCpp: ["local-model"]
        case .custom: []
        }
    }

    var apiKeyOptional: Bool {
        self == .ollama || self == .llamaCpp || self == .custom
    }
}

struct AIProviderConfiguration: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: AIProviderKind
    var baseURL: String
    var modelIDs: [String]
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        modelIDs: [String],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.modelIDs = modelIDs
        self.isEnabled = isEnabled
    }

    static func preset(_ kind: AIProviderKind) -> AIProviderConfiguration {
        AIProviderConfiguration(
            name: kind.title,
            kind: kind,
            baseURL: kind.defaultBaseURL,
            modelIDs: kind.defaultModels
        )
    }
}
