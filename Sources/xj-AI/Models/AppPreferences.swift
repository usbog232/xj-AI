import Foundation

struct AppPreferences {
    static let ollamaHostKey = "ollamaHost"
    static let ollamaModelKey = "ollamaModel"
    static let sourceLanguageKey = "sourceLanguage"
    static let targetLanguageKey = "targetLanguage"
    static let audioSourceKey = "audioSource"
    static let selectedApplicationKey = "selectedApplication"
    static let autoSaveKey = "autoSave"
    static let recordsDirectoryKey = "recordsDirectory"
    static let speechEngineKey = "speechRecognitionEngine"
    static let localSpeechModelKey = "localSpeechModel"
    static let lanSpeechProtocolKey = "lanSpeechProtocol"
    static let lanSpeechBaseURLKey = "lanSpeechBaseURL"
    static let lanSpeechModelKey = "lanSpeechModel"
    static let speechChunkDurationKey = "speechChunkDuration"
    static let floatingSubtitleContentModeKey = "floatingSubtitleContentMode"

    static let defaultOllamaHost = "http://127.0.0.1:11434"
    static let defaultOllamaModel = "qwen3:4b"
}
