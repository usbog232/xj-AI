import AppKit
import Foundation
import Speech

@MainActor
final class SpeechRecognitionStore: ObservableObject {
    @Published var selectedEngine: SpeechRecognitionEngine {
        didSet {
            defaults.set(selectedEngine.rawValue, forKey: AppPreferences.speechEngineKey)
            operationMessage = defaultOperationMessage(for: selectedEngine)
        }
    }
    @Published var selectedLocalModelID: String {
        didSet { defaults.set(selectedLocalModelID, forKey: AppPreferences.localSpeechModelKey) }
    }
    @Published var lanProtocol: LANRecognitionProtocol {
        didSet {
            defaults.set(lanProtocol.rawValue, forKey: AppPreferences.lanSpeechProtocolKey)
            if oldValue != lanProtocol {
                lanBaseURL = adjustedBaseURL(lanBaseURL, for: lanProtocol)
                operationMessage = "已切换为 \(lanProtocol.title)，请确认地址后测试连接。"
            }
        }
    }
    @Published var lanBaseURL: String {
        didSet { defaults.set(lanBaseURL, forKey: AppPreferences.lanSpeechBaseURLKey) }
    }
    @Published var lanModel: String {
        didSet { defaults.set(lanModel, forKey: AppPreferences.lanSpeechModelKey) }
    }
    @Published var lanAPIKey: String {
        didSet { keychain.set(lanAPIKey, for: Self.lanAPIKeyAccount) }
    }
    @Published var chunkDuration: Double {
        didSet { defaults.set(chunkDuration, forKey: AppPreferences.speechChunkDurationKey) }
    }

    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var operationMessage = "Apple Speech 使用系统内置语言资源。"
    @Published private(set) var isTesting = false

    let models = LocalSpeechModel.catalog

    private static let lanAPIKeyAccount = "speech-recognition-lan-api-key"
    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let fileManager: FileManager
    private var downloads: [String: URLSessionDownloadTask] = [:]

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainStore = KeychainStore(),
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.fileManager = fileManager

        selectedEngine = SpeechRecognitionEngine(
            rawValue: defaults.string(forKey: AppPreferences.speechEngineKey) ?? ""
        ) ?? .apple
        selectedLocalModelID = defaults.string(forKey: AppPreferences.localSpeechModelKey)
            ?? LocalSpeechModel.catalog.first!.id
        lanProtocol = LANRecognitionProtocol(
            rawValue: defaults.string(forKey: AppPreferences.lanSpeechProtocolKey) ?? ""
        ) ?? .openAI
        lanBaseURL = defaults.string(forKey: AppPreferences.lanSpeechBaseURLKey)
            ?? "http://127.0.0.1:8000/v1"
        lanModel = defaults.string(forKey: AppPreferences.lanSpeechModelKey) ?? "whisper-1"
        lanAPIKey = keychain.value(for: Self.lanAPIKeyAccount)
        let savedChunkDuration = defaults.double(forKey: AppPreferences.speechChunkDurationKey)
        chunkDuration = savedChunkDuration > 0 ? savedChunkDuration : 4
        operationMessage = defaultOperationMessage(for: selectedEngine)
    }

    var selectedLocalModel: LocalSpeechModel? {
        models.first(where: { $0.id == selectedLocalModelID })
    }

    var modelsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appending(path: "xj-AI/SpeechModels", directoryHint: .isDirectory)
    }

    var selectedLocalModelURL: URL? {
        guard let selectedLocalModel else { return nil }
        let url = modelURL(for: selectedLocalModel)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    var engineReady: Bool {
        switch selectedEngine {
        case .apple: SFSpeechRecognizer.authorizationStatus() == .authorized
        case .localWhisper: selectedLocalModelURL != nil && LocalWhisperTranscriber.helperURL != nil
        case .lan: URL(string: lanBaseURL)?.host != nil
        }
    }

    var selectedEngineDetail: String {
        switch selectedEngine {
        case .apple:
            "设备端实时流式；需要 macOS 语音识别权限。"
        case .localWhisper:
            selectedLocalModel.map { "\($0.title) · \($0.languagesLabel) · 音频不离开本机" }
                ?? "尚未选择模型"
        case .lan:
            "\(lanProtocol.title) · \(lanBaseURL)"
        }
    }

    func isDownloaded(_ model: LocalSpeechModel) -> Bool {
        fileManager.fileExists(atPath: modelURL(for: model).path)
    }

    func modelURL(for model: LocalSpeechModel) -> URL {
        modelsDirectory.appending(path: model.fileName)
    }

    func download(_ model: LocalSpeechModel) {
        guard downloads[model.id] == nil else { return }
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            operationMessage = "无法创建模型目录：\(error.localizedDescription)"
            return
        }

        operationMessage = "正在下载 \(model.title)…"
        downloadProgress[model.id] = 0
        let destination = modelURL(for: model)
        let task = URLSession.shared.downloadTask(with: model.downloadURL) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in self.finishDownload(model, message: "下载失败：\(error.localizedDescription)") }
                return
            }
            guard let temporaryURL,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                Task { @MainActor in self.finishDownload(model, message: "下载失败：服务器没有返回模型文件。") }
                return
            }
            do {
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.moveItem(at: temporaryURL, to: destination)
                Task { @MainActor in
                    self.selectedLocalModelID = model.id
                    self.finishDownload(model, message: "\(model.title) 已下载并设为当前本地模型。")
                }
            } catch {
                Task { @MainActor in self.finishDownload(model, message: "保存模型失败：\(error.localizedDescription)") }
            }
        }
        downloads[model.id] = task
        task.resume()

        Task { [weak self, weak task] in
            while let self, let task, task.state == .running {
                self.downloadProgress[model.id] = task.progress.fractionCompleted
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    func cancelDownload(_ model: LocalSpeechModel) {
        downloads[model.id]?.cancel()
        downloads[model.id] = nil
        downloadProgress[model.id] = nil
        operationMessage = "已取消下载 \(model.title)。"
    }

    func delete(_ model: LocalSpeechModel) throws {
        let url = modelURL(for: model)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        operationMessage = "已删除 \(model.title)。"
        objectWillChange.send()
    }

    func openModelsDirectory() {
        do {
            try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            NSWorkspace.shared.open(modelsDirectory)
            operationMessage = "已在 Finder 中打开语音模型目录。"
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func testSelectedConfiguration(language: String) async {
        guard !isTesting else { return }
        isTesting = true
        operationMessage = "正在测试 \(selectedEngine.title)…"
        defer { isTesting = false }

        do {
            switch selectedEngine {
            case .apple:
                let status = await SpeechRecognitionService.requestAuthorization()
                guard status == .authorized else {
                    throw SpeechRecognitionService.RecognitionError.permissionDenied
                }
                operationMessage = "Apple Speech 权限正常；具体语言资源会在开始录音时检查。"
            case .localWhisper:
                guard let modelURL = selectedLocalModelURL else {
                    throw LocalWhisperTranscriber.TranscriptionError.modelMissing
                }
                let text = try await LocalWhisperTranscriber().transcribe(
                    samples: Array(repeating: 0, count: 16_000),
                    modelURL: modelURL,
                    language: language
                )
                operationMessage = text.isEmpty ? "本地模型加载成功。" : "本地模型测试成功：\(text)"
            case .lan:
                let client = LANTranscriptionClient(
                    protocolKind: lanProtocol,
                    baseURL: lanBaseURL,
                    model: lanModel,
                    apiKey: lanAPIKey
                )
                _ = try await client.transcribe(
                    samples: Array(repeating: 0, count: 16_000),
                    language: language
                )
                operationMessage = "局域网语音识别服务连接成功。"
            }
        } catch {
            operationMessage = error.localizedDescription
        }
    }

    func configuration(language: String) -> ChunkRecognitionConfiguration {
        ChunkRecognitionConfiguration(
            engine: selectedEngine,
            language: language,
            localModelURL: selectedLocalModelURL,
            lanProtocol: lanProtocol,
            lanBaseURL: lanBaseURL,
            lanModel: lanModel,
            lanAPIKey: lanAPIKey,
            chunkDuration: chunkDuration
        )
    }

    private func finishDownload(_ model: LocalSpeechModel, message: String) {
        downloads[model.id] = nil
        downloadProgress[model.id] = nil
        operationMessage = message
        objectWillChange.send()
    }

    private func defaultOperationMessage(for engine: SpeechRecognitionEngine) -> String {
        switch engine {
        case .apple: "Apple Speech 使用系统内置语言资源。"
        case .localWhisper:
            selectedLocalModelURL == nil
                ? "请选择并下载一个 Whisper 小模型。"
                : "本地 Whisper 已准备好，音频不会离开本机。"
        case .lan: "请填写可信的局域网 ASR 地址，然后测试连接。"
        }
    }

    private func adjustedBaseURL(_ value: String, for protocolKind: LANRecognitionProtocol) -> String {
        guard var components = URLComponents(string: value), components.host != nil else { return value }
        switch protocolKind {
        case .openAI:
            if components.path.isEmpty || components.path == "/" { components.path = "/v1" }
        case .whisperCpp:
            if components.path == "/v1" || components.path == "/v1/" { components.path = "" }
        }
        return components.url?.absoluteString ?? value
    }
}
