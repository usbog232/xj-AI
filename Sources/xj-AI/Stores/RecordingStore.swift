import AppKit
import AVFoundation
import Foundation
import Speech

@MainActor
final class RecordingStore: ObservableObject {
    @Published private(set) var phase: RecordingPhase = .idle
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var liveTranscript = ""
    @Published private(set) var audioLevels: [Double] = (0..<100).map { index in
        let primary = abs(sin(Double(index) * 0.39))
        let secondary = abs(cos(Double(index) * 0.17))
        return 0.08 + primary * secondary * 0.28
    }
    @Published private(set) var applications: [CapturableApplication] = []
    @Published var statusMessage = "准备就绪"
    @Published var lastExportURL: URL?

    @Published var audioSource: AudioSource {
        didSet {
            UserDefaults.standard.set(audioSource.rawValue, forKey: AppPreferences.audioSourceKey)
            if audioSource == .application {
                Task { await refreshApplications() }
            }
        }
    }
    @Published var selectedApplicationID: String {
        didSet { UserDefaults.standard.set(selectedApplicationID, forKey: AppPreferences.selectedApplicationKey) }
    }
    @Published var sourceLanguage: String {
        didSet { UserDefaults.standard.set(sourceLanguage, forKey: AppPreferences.sourceLanguageKey) }
    }
    @Published var targetLanguage: String {
        didSet {
            UserDefaults.standard.set(targetLanguage, forKey: AppPreferences.targetLanguageKey)
            providerStore.targetLanguage = LanguageOption.title(for: targetLanguage, in: LanguageOption.targetLanguages)
        }
    }
    @Published var autoSave: Bool {
        didSet {
            UserDefaults.standard.set(autoSave, forKey: AppPreferences.autoSaveKey)
            sessionStore.persistenceEnabled = autoSave
        }
    }

    let sessionStore: SessionStore
    let persistence: SessionPersistence
    let providerStore: AIProviderStore
    let speechStore: SpeechRecognitionStore

    private let appleSpeech = SpeechRecognitionService()
    private let chunkedSpeech = ChunkedSpeechRecognitionService()
    private let microphone = MicrophoneCaptureService()
    private let systemAudio = SystemAudioCaptureService()
    private var elapsedTimer: Timer?
    private var flushTimer: Timer?
    private var activeSessionID: UUID?
    private var activeAudioURL: URL?
    private var activeRecognitionEngine: SpeechRecognitionEngine?
    private var currentRecognitionSegments: [RecognizedSpeechSegment] = []
    private var committedRecognitionTail: [String] = []
    private var committedRecognitionTime: TimeInterval = -1
    private var lastSegmentEnd: TimeInterval = 0

    init(
        sessionStore: SessionStore,
        providerStore: AIProviderStore,
        speechStore: SpeechRecognitionStore,
        persistence: SessionPersistence = SessionPersistence()
    ) {
        self.sessionStore = sessionStore
        self.providerStore = providerStore
        self.speechStore = speechStore
        self.persistence = persistence
        let defaults = UserDefaults.standard
        audioSource = AudioSource(rawValue: defaults.string(forKey: AppPreferences.audioSourceKey) ?? "") ?? .microphone
        selectedApplicationID = defaults.string(forKey: AppPreferences.selectedApplicationKey) ?? ""
        sourceLanguage = defaults.string(forKey: AppPreferences.sourceLanguageKey) ?? "auto"
        targetLanguage = defaults.string(forKey: AppPreferences.targetLanguageKey) ?? "zh-CN"
        autoSave = defaults.object(forKey: AppPreferences.autoSaveKey) as? Bool ?? true
        sessionStore.persistenceEnabled = autoSave
    }

    var recognitionStatusTitle: String {
        switch speechStore.selectedEngine {
        case .apple:
            return switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: "Apple 识别可用"
            case .denied, .restricted: "Apple 识别未授权"
            case .notDetermined: "等待 Apple 识别授权"
            @unknown default: "Apple 识别状态未知"
            }
        case .localWhisper:
            return speechStore.engineReady ? "本地 Whisper 可用" : "需要下载本地语音模型"
        case .lan:
            return speechStore.engineReady ? "局域网识别已配置" : "局域网识别配置无效"
        }
    }

    var recognitionStatusIsReady: Bool {
        switch speechStore.selectedEngine {
        case .apple: SFSpeechRecognizer.authorizationStatus() == .authorized
        case .localWhisper, .lan: speechStore.engineReady
        }
    }

    var recordsDirectory: URL { persistence.recordsDirectory }

    func bootstrap() {
        Task {
            if audioSource == .application {
                await refreshApplications()
            }
            await refreshTranslationModels()
        }
    }

    func toggleRecording() {
        Task {
            if phase.isRecording { await stopRecording() }
            else if !phase.isBusy { await startRecording() }
        }
    }

    func startRecording() async {
        guard !phase.isBusy else { return }
        phase = .preparing
        statusMessage = "正在准备\(speechStore.selectedEngine.title)…"
        elapsed = 0
        liveTranscript = ""
        currentRecognitionSegments = []
        committedRecognitionTail = []
        committedRecognitionTime = -1
        lastSegmentEnd = 0

        do {
            let recognitionEngine = speechStore.selectedEngine
            activeRecognitionEngine = recognitionEngine
            if recognitionEngine == .apple {
                let speechStatus = await SpeechRecognitionService.requestAuthorization()
                guard speechStatus == .authorized else {
                    throw SpeechRecognitionService.RecognitionError.permissionDenied
                }
            }
            if audioSource == .microphone {
                guard await MicrophoneCaptureService.requestPermission() else {
                    throw MicrophoneCaptureService.CaptureError.permissionDenied
                }
            }

            let resolvedLocale = resolvedSourceLocale()
            let sessionID = UUID()
            let audioURL: URL
            if autoSave {
                audioURL = try persistence.audioURL(sessionID: sessionID)
            } else {
                audioURL = FileManager.default.temporaryDirectory.appending(path: "xj-AI-\(sessionID.uuidString).caf")
            }
            activeAudioURL = audioURL

            switch recognitionEngine {
            case .apple:
                try appleSpeech.start(localeIdentifier: resolvedLocale) { [weak self] update in
                    Task { @MainActor in self?.receiveRecognition(update) }
                } onError: { [weak self] error in
                    Task { @MainActor in self?.handleRecognitionError(error) }
                }
            case .localWhisper, .lan:
                try chunkedSpeech.start(
                    configuration: speechStore.configuration(language: sourceLanguage)
                ) { [weak self] result in
                    await self?.receiveChunkRecognition(result)
                } onError: { [weak self] error in
                    Task { @MainActor in self?.handleRecognitionError(error) }
                }
            }

            let appleSpeech = appleSpeech
            let chunkedSpeech = chunkedSpeech
            switch audioSource {
            case .microphone:
                try microphone.start(recordTo: audioURL) { buffer in
                    if recognitionEngine == .apple { appleSpeech.append(buffer) }
                    else { chunkedSpeech.append(buffer) }
                } onLevel: { [weak self] level in
                    Task { @MainActor in self?.appendLevel(level) }
                }
            case .systemAudio, .application:
                let appID = audioSource == .application ? selectedApplicationID : nil
                try await systemAudio.start(applicationBundleID: appID, recordTo: audioURL) { sample in
                    if recognitionEngine == .apple { appleSpeech.append(sample) }
                    else { chunkedSpeech.append(sample) }
                } onLevel: { [weak self] level in
                    Task { @MainActor in self?.appendLevel(level) }
                }
            }

            _ = sessionStore.createLiveSession(
                id: sessionID,
                source: audioSource,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                model: providerStore.selectedModelID
            )
            activeSessionID = sessionID

            phase = .recording
            switch recognitionEngine {
            case .apple:
                statusMessage = "正在使用 Apple Speech 设备端识别"
            case .localWhisper:
                statusMessage = "正在使用 \(speechStore.selectedLocalModel?.title ?? "本地 Whisper") 离线识别"
            case .lan:
                statusMessage = "正在使用局域网语音识别 · 每 \(Int(speechStore.chunkDuration)) 秒分段"
            }
            startTimers(flushAppleSpeech: recognitionEngine == .apple)
        } catch {
            await stopCaptureOnly()
            appleSpeech.stop()
            await chunkedSpeech.stop()
            activeRecognitionEngine = nil
            phase = .failed(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard phase.isRecording || phase == .preparing else { return }
        phase = .stopping
        elapsedTimer?.invalidate()
        flushTimer?.invalidate()
        elapsedTimer = nil
        flushTimer = nil
        let recognitionEngine = activeRecognitionEngine ?? speechStore.selectedEngine
        if recognitionEngine == .apple {
            await flushCurrentText()
            appleSpeech.finishAudio()
        }
        await stopCaptureOnly()
        if recognitionEngine == .apple {
            appleSpeech.stop()
        } else {
            await chunkedSpeech.finish()
        }

        if let activeSessionID {
            sessionStore.finalize(
                sessionID: activeSessionID,
                duration: elapsed,
                audioFileName: autoSave ? "\(activeSessionID.uuidString).caf" : nil
            )
        }
        if !autoSave, let activeAudioURL {
            try? FileManager.default.removeItem(at: activeAudioURL)
        }
        activeAudioURL = nil
        activeSessionID = nil
        activeRecognitionEngine = nil
        liveTranscript = ""
        phase = .idle
        statusMessage = autoSave ? "已自动保存" : "录音已停止"
    }

    func refreshApplications() async {
        do {
            applications = try await systemAudio.availableApplications()
            if selectedApplicationID.isEmpty { selectedApplicationID = applications.first?.id ?? "" }
        } catch {
            applications = []
        }
    }

    func refreshTranslationModels() async {
        await providerStore.refreshModels()
    }

    func exportSelected(_ format: ExportFormat) {
        guard let session = sessionStore.selectedSession else {
            statusMessage = SessionPersistence.PersistenceError.sessionMissing.localizedDescription
            return
        }
        do {
            let url = try persistence.export(session, format: format)
            lastExportURL = url
            statusMessage = "已导出 \(format.title)"
            persistence.reveal(url)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func chooseRecordsDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 xj-AI 记录目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = recordsDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        persistence.setRecordsDirectory(url)
        objectWillChange.send()
        statusMessage = "保存目录已更新"
    }

    func openRecordsDirectory() {
        do {
            try persistence.openRecordsDirectory()
            statusMessage = "已在 Finder 中打开保存目录"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func downloadSessions(withIDs ids: Set<UUID>, options: SessionDownloadOptions) {
        guard !phase.isBusy else { return }
        let selected = sessionStore.records(withIDs: ids)
        guard !selected.isEmpty else {
            statusMessage = "请先选择需要下载的记录"
            return
        }

        let panel = NSOpenPanel()
        panel.title = "选择会话下载目录"
        panel.prompt = "下载到这里"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        statusMessage = options.kind == .audio ? "正在转换音频…" : "正在导出字幕…"
        Task {
            do {
                let result = try await persistence.download(
                    selected,
                    options: options,
                    to: destination
                )
                persistence.reveal(result.directory)
                if result.skippedCount > 0 {
                    statusMessage = "已下载 \(result.exportedCount) 条，跳过 \(result.skippedCount) 条无音频记录"
                } else {
                    statusMessage = "已下载 \(result.exportedCount) 条记录"
                }
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func deleteSessions(withIDs ids: Set<UUID>) -> Bool {
        guard !phase.isBusy else {
            statusMessage = "录音进行中，无法删除记录"
            return false
        }
        do {
            let count = try sessionStore.deleteSessions(withIDs: ids)
            statusMessage = count > 0 ? "已删除 \(count) 条记录及本地文件" : "没有选中记录"
            return count > 0
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func newIdleSession() {
        guard !phase.isBusy else { return }
        let id = sessionStore.createLiveSession(
            source: audioSource,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            model: providerStore.selectedModelID
        )
        sessionStore.selectedSessionID = id
        statusMessage = "已新建会话"
    }

    private func receiveRecognition(_ update: SpeechRecognitionUpdate) {
        currentRecognitionSegments = update.segments
        liveTranscript = RecognitionDelta.pendingText(
            formattedText: update.formattedText,
            segments: update.segments,
            committedTail: committedRecognitionTail,
            committedThrough: committedRecognitionTime
        )
        if update.isFinal { Task { await flushCurrentText() } }
    }

    private func receiveChunkRecognition(_ result: ChunkRecognitionResult) async {
        guard let sessionID = activeSessionID else { return }
        let original = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }

        let segment = TranscriptSegment(
            startTime: result.startTime,
            endTime: max(result.endTime, result.startTime + 0.5),
            original: original
        )
        sessionStore.addSegment(segment, to: sessionID)

        if sourceLanguage == targetLanguage {
            sessionStore.updateTranslation(original, segmentID: segment.id, sessionID: sessionID)
            return
        }
        do {
            let translation = try await providerStore.translate(original)
            sessionStore.updateTranslation(translation, segmentID: segment.id, sessionID: sessionID)
        } catch {
            sessionStore.updateTranslation("翻译暂不可用", segmentID: segment.id, sessionID: sessionID)
            statusMessage = error.localizedDescription
        }
    }

    private func flushCurrentText() async {
        let original = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, let sessionID = activeSessionID else { return }

        let end = elapsed
        let start = max(lastSegmentEnd, end - 3.2)
        lastSegmentEnd = end
        committedRecognitionTime = max(
            committedRecognitionTime,
            RecognitionDelta.latestEndTime(in: currentRecognitionSegments) ?? committedRecognitionTime
        )
        committedRecognitionTail = RecognitionDelta.tail(in: currentRecognitionSegments)
        liveTranscript = ""

        let segment = TranscriptSegment(startTime: start, endTime: max(end, start + 0.5), original: original)
        sessionStore.addSegment(segment, to: sessionID)

        if sourceLanguage == targetLanguage {
            sessionStore.updateTranslation(original, segmentID: segment.id, sessionID: sessionID)
            return
        }

        do {
            let translation = try await providerStore.translate(original)
            sessionStore.updateTranslation(translation, segmentID: segment.id, sessionID: sessionID)
        } catch {
            sessionStore.updateTranslation("翻译暂不可用", segmentID: segment.id, sessionID: sessionID)
            statusMessage = error.localizedDescription
        }
    }

    private func startTimers(flushAppleSpeech: Bool) {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
        if flushAppleSpeech {
            flushTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.flushCurrentText() }
            }
        }
    }

    private func appendLevel(_ level: Double) {
        audioLevels.append(level)
        if audioLevels.count > 100 { audioLevels.removeFirst(audioLevels.count - 100) }
    }

    private func handleRecognitionError(_ error: Error) {
        guard phase.isRecording else { return }
        statusMessage = error.localizedDescription
    }

    private func stopCaptureOnly() async {
        microphone.stop()
        await systemAudio.stop()
    }

    private func resolvedSourceLocale() -> String {
        guard sourceLanguage == "auto" else { return sourceLanguage }
        let preferred = Locale.preferredLanguages.first ?? "en-US"
        if preferred.hasPrefix("zh"), targetLanguage.hasPrefix("zh") { return "en-US" }
        return preferred
    }
}
