import AppKit
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case audio, dictation, providers, translation, localModels, advanced, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .audio: "音频 / 混音"
        case .dictation: "听写"
        case .providers: "AI Provider"
        case .translation: "翻译"
        case .localModels: "本地模型"
        case .advanced: "高级"
        case .about: "关于"
        }
    }
    var symbol: String {
        switch self {
        case .audio: "waveform"
        case .dictation: "keyboard"
        case .providers: "cpu"
        case .translation: "translate"
        case .localModels: "server.rack"
        case .advanced: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @State private var selection: SettingsSection = .providers
    let onBack: (() -> Void)?

    init(onBack: (() -> Void)? = nil) { self.onBack = onBack }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if let onBack {
                    Button(action: onBack) {
                        Label("返回实时翻译", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).frame(height: 42)
                    }
                    .buttonStyle(.plain).padding(.top, 10)
                }
                Text("设置")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.top, onBack == nil ? 18 : 8).padding(.bottom, 8)
                ForEach(SettingsSection.allCases) { section in
                    Button { selection = section } label: {
                        Label(section.title, systemImage: section.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).frame(height: 38)
                            .background(selection == section ? Color.white.opacity(0.1) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain).padding(.horizontal, 8)
                }
                Spacer()
                Label("配置只保存在这台 Mac", systemImage: "lock.shield")
                    .font(.caption2).foregroundStyle(.secondary).padding(16)
            }
            .frame(width: 218).background(.ultraThinMaterial)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.root)
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .audio: AudioSettingsPage()
        case .dictation: DictationSettingsPage()
        case .providers: ProviderSettingsPage()
        case .translation: TranslationSettingsPage()
        case .localModels: LocalModelsSettingsPage()
        case .advanced: AdvancedSettingsPage()
        case .about: AboutSettingsPage()
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 24, weight: .bold))
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                content
            }
            .padding(30).frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)) }
    }
}

private struct AudioSettingsPage: View {
    @AppStorage("microphoneEnabled") private var microphoneEnabled = true
    @AppStorage("systemAudioEnabled") private var systemAudioEnabled = false
    @AppStorage("microphoneGain") private var microphoneGain = 0.7
    @AppStorage("systemAudioGain") private var systemAudioGain = 0.7
    var body: some View {
        SettingsPage(title: "音频 / 混音", subtitle: "选择麦克风、系统声音或指定应用；两路可以同时启用。") {
            HStack(alignment: .top, spacing: 14) {
                audioCard("麦克风", "mic", $microphoneEnabled, $microphoneGain)
                audioCard("系统音", "speaker.wave.2", $systemAudioEnabled, $systemAudioGain)
            }
            Text("系统音采集使用 macOS 屏幕录制权限，但 xj-AI 只读取音频样本，不保存屏幕画面。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func audioCard(_ title: String, _ symbol: String, _ enabled: Binding<Bool>, _ gain: Binding<Double>) -> some View {
        SettingsCard {
            HStack { Label(title, systemImage: symbol).font(.headline); Spacer(); Toggle("", isOn: enabled).labelsHidden() }
            LabeledContent("增益") {
                HStack { Slider(value: gain, in: 0...1); Text("\(Int(gain.wrappedValue * 100))%").monospacedDigit().frame(width: 38) }
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct DictationSettingsPage: View {
    @AppStorage("dictationShortcut") private var shortcut = "⌃ ⌥ D"
    @AppStorage("dictationSavesToLibrary") private var savesToLibrary = true
    var body: some View {
        SettingsPage(title: "听写", subtitle: "全局热键按一下开始，再按一下停止；结果复制到剪贴板。") {
            SettingsCard {
                LabeledContent("快捷键") { TextField("快捷键", text: $shortcut).frame(width: 150) }
                Toggle("听写结果保存到内容库", isOn: $savesToLibrary)
                Text("跨应用自动粘贴需要辅助功能权限；未授权时仍会复制到剪贴板。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProviderSettingsPage: View {
    @EnvironmentObject private var providers: AIProviderStore
    @State private var pendingDeletion: UUID?
    var body: some View {
        SettingsPage(title: "AI Provider", subtitle: "翻译和 AI 功能的共同底座。支持云模型、本机服务与局域网 OpenAI 兼容服务。") {
            SettingsCard {
                Label("使用云端 Provider 时，转录文字会发送给该服务商；本机或局域网服务由你控制。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 6) {
                    ForEach(providers.providers) { provider in
                        Button { providers.selectProvider(provider.id) } label: {
                            HStack {
                                Image(systemName: provider.kind.symbol).frame(width: 20)
                                Text(provider.name).lineLimit(1); Spacer()
                                Circle().fill(provider.isEnabled ? Color.green : Color.gray).frame(width: 7, height: 7)
                            }
                            .padding(.horizontal, 10).frame(height: 40)
                            .background(providers.selectedProviderID == provider.id ? Color.accentColor.opacity(0.22) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                    Menu {
                        ForEach(AIProviderKind.allCases) { kind in
                            Button { providers.addProvider(kind) } label: { Label(kind.title, systemImage: kind.symbol) }
                        }
                    } label: {
                        Label("添加 Provider", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).frame(height: 38)
                    }.menuStyle(.borderlessButton)
                }.padding(12).frame(width: 210, alignment: .top)
                Divider()
                Group {
                    if let index = providers.providers.firstIndex(where: { $0.id == providers.selectedProviderID }) {
                        ProviderEditor(
                            provider: $providers.providers[index],
                            apiKey: Binding(
                                get: { providers.apiKey(for: providers.providers[index].id) },
                                set: { providers.setAPIKey($0, for: providers.providers[index].id) }
                            ),
                            onDelete: { pendingDeletion = providers.providers[index].id }
                        )
                    } else {
                        ContentUnavailableView("添加一个 Provider", systemImage: "cpu", description: Text("选择云服务或本机 / 局域网模型服务。"))
                    }
                }.padding(18).frame(maxWidth: .infinity, minHeight: 390, alignment: .topLeading)
            }
            .background(Color.black.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)) }
        }
        .confirmationDialog("删除这个 Provider？", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let id = pendingDeletion { providers.deleteProvider(id) }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        }
    }
}

private struct ProviderEditor: View {
    @EnvironmentObject private var providers: AIProviderStore
    @Binding var provider: AIProviderConfiguration
    @Binding var apiKey: String
    let onDelete: () -> Void
    @State private var manualModel = ""
    @State private var showsKey = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Provider 名称", text: $provider.name).font(.headline)
                Toggle("启用", isOn: $provider.isEnabled)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API Key").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    if showsKey { TextField(provider.kind.apiKeyOptional ? "可留空" : "sk-…", text: $apiKey) }
                    else { SecureField(provider.kind.apiKeyOptional ? "可留空" : "sk-…", text: $apiKey) }
                    Button { showsKey.toggle() } label: { Image(systemName: showsKey ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                }
                Text("API Key 保存在 macOS 钥匙串，不写入配置文件。").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("API Base URL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("http://192.168.1.20:8080/v1", text: $provider.baseURL).textFieldStyle(.roundedBorder)
                if provider.kind == .llamaCpp || provider.kind == .custom {
                    Text("可填写本机 127.0.0.1，也可填写局域网服务器 IP；服务需兼容 OpenAI /v1 接口。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("模型").font(.caption.weight(.semibold)).foregroundStyle(.secondary); Spacer(); Button("获取模型") { Task { await providers.refreshModels(for: provider.id) } } }
                if provider.modelIDs.isEmpty { Text("还没有模型——从服务获取，或手动添加模型 ID。").font(.caption).foregroundStyle(.secondary) }
                FlowLayout(spacing: 7) {
                    ForEach(provider.modelIDs, id: \.self) { model in
                        HStack(spacing: 6) {
                            Text(model).lineLimit(1)
                            Button { providers.removeModel(model, from: provider.id) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless)
                        }
                        .font(.caption).padding(.horizontal, 9).frame(height: 28)
                        .background(Color.white.opacity(0.07)).clipShape(Capsule())
                    }
                }
                HStack {
                    TextField("手动添加模型 ID", text: $manualModel)
                    Button("添加") { providers.addModel(manualModel, to: provider.id); manualModel = "" }
                }
            }
            HStack {
                Button("测试连接") { Task { await providers.refreshModels(for: provider.id) } }.buttonStyle(.borderedProminent)
                if case .testing = providers.connectionState { ProgressView().controlSize(.small) }
                Text(providers.connectionState.title).font(.caption).foregroundStyle(connectionColor)
            }
        }
    }
    private var connectionColor: Color {
        if case .failure = providers.connectionState { return .red }
        if case .success = providers.connectionState { return .green }
        return .secondary
    }
}

private struct TranslationSettingsPage: View {
    @EnvironmentObject private var providers: AIProviderStore
    var body: some View {
        SettingsPage(title: "翻译", subtitle: "选择 Provider、模型、目标语言和提示词模板。") {
            SettingsCard {
                Toggle("实时字幕翻译", isOn: $providers.liveTranslationEnabled)
                LabeledContent("Provider") {
                    Picker("Provider", selection: $providers.selectedProviderID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(providers.enabledProviders) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().frame(width: 280)
                }
                LabeledContent("模型") {
                    Picker("模型", selection: $providers.selectedModelID) {
                        if let provider = providers.selectedProvider { ForEach(provider.modelIDs, id: \.self) { Text($0).tag($0) } }
                    }.labelsHidden().frame(width: 280)
                }
                LabeledContent("目标语言") { TextField("简体中文", text: $providers.targetLanguage).frame(width: 280) }
            }
            SettingsCard {
                Text("提示词 · {{targetLang}} · {{text}}").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextEditor(text: $providers.promptTemplate)
                    .font(.system(.body, design: .monospaced)).frame(minHeight: 120).padding(8)
                    .background(Color.black.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button("测试翻译") { Task { await providers.testTranslation() } }.buttonStyle(.borderedProminent)
                    Text(providers.connectionState.title).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct LocalModelsSettingsPage: View {
    @EnvironmentObject private var providers: AIProviderStore
    @EnvironmentObject private var speech: SpeechRecognitionStore
    @EnvironmentObject private var recording: RecordingStore
    @State private var pendingModelDeletion: LocalSpeechModel?

    var body: some View {
        SettingsPage(
            title: "本地模型与语音识别",
            subtitle: "选择 Apple 自带识别、下载 Whisper 小模型离线识别，或连接局域网语音识别服务。"
        ) {
            recognitionEngineCard

            switch speech.selectedEngine {
            case .apple:
                appleRecognitionCard
            case .localWhisper:
                localSpeechModels
            case .lan:
                lanRecognitionCard
            }

            SettingsCard {
                HStack {
                    Label("识别状态", systemImage: speech.engineReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(speech.engineReady ? Color.green : Color.orange)
                    Text(speech.operationMessage).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if speech.isTesting { ProgressView().controlSize(.small) }
                    Button("测试当前识别引擎") {
                        Task { await speech.testSelectedConfiguration(language: recording.sourceLanguage) }
                    }
                    .disabled(recording.phase.isBusy || speech.isTesting)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("本地翻译服务").font(.headline)
                Text("下面的 Ollama / llama.cpp 仍用于翻译文字，不负责语音识别。")
                    .font(.caption).foregroundStyle(.secondary)
                localTranslationCard(
                    "llama.cpp Server",
                    "本机或局域网 OpenAI 兼容翻译服务，常用地址 http://127.0.0.1:8080/v1。",
                    .llamaCpp
                )
                localTranslationCard(
                    "Ollama",
                    "本机或局域网翻译服务，常用地址 http://127.0.0.1:11434/v1。",
                    .ollama
                )
            }
        }
        .confirmationDialog(
            "删除本地语音模型？",
            isPresented: Binding(
                get: { pendingModelDeletion != nil },
                set: { if !$0 { pendingModelDeletion = nil } }
            ),
            presenting: pendingModelDeletion
        ) { model in
            Button("删除 \(model.title)", role: .destructive) {
                try? speech.delete(model)
                pendingModelDeletion = nil
            }
            Button("取消", role: .cancel) { pendingModelDeletion = nil }
        } message: { model in
            Text("将删除已下载的 \(model.fileName)，以后仍可重新下载。")
        }
    }

    private var recognitionEngineCard: some View {
        SettingsCard {
            Text("实时语音识别引擎").font(.headline)
            Picker("实时语音识别引擎", selection: $speech.selectedEngine) {
                ForEach(SpeechRecognitionEngine.allCases) { engine in
                    Label(engine.title, systemImage: engine.symbol).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .disabled(recording.phase.isBusy)

            LabeledContent("音频语言") {
                Picker("音频语言", selection: $recording.sourceLanguage) {
                    ForEach(LanguageOption.sourceLanguages) { language in
                        Text(language.title).tag(language.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            if speech.selectedEngine != .apple {
                LabeledContent("识别分段") {
                    HStack {
                        Slider(value: $speech.chunkDuration, in: 2...8, step: 1)
                            .frame(width: 170)
                        Text("\(Int(speech.chunkDuration)) 秒")
                            .monospacedDigit().frame(width: 44)
                    }
                }
                Text("短分段延迟低，长分段语义更完整。推荐 4 秒；每段独立识别，不会在后面突然合并成长段。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appleRecognitionCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "apple.logo").font(.title2).frame(width: 34)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple 自带识别").font(.headline)
                    Text("使用 macOS Speech 框架的设备端实时识别。零模型下载、延迟最低；不同语言是否可离线使用取决于系统已安装的语言资源。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("音频不会发送到局域网或云端。首次使用需要语音识别权限。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var localSpeechModels: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Whisper 本地小模型").font(.headline)
                    Text("模型下载到 xj-AI 的独立目录；识别完全离线。Q5 量化模型更小，适合实时分段。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { speech.openModelsDirectory() } label: {
                    Label("打开模型目录", systemImage: "folder")
                }
            }

            ForEach(speech.models) { model in
                SettingsCard {
                    HStack(spacing: 14) {
                        Image(systemName: speech.selectedLocalModelID == model.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(speech.selectedLocalModelID == model.id ? Color.accentColor : Color.secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(model.title).font(.headline)
                                Text(model.sizeLabel).foregroundStyle(.secondary)
                                Text(model.languagesLabel)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8).frame(height: 24)
                                    .background(Color.white.opacity(0.07)).clipShape(Capsule())
                                if speech.isDownloaded(model) {
                                    Text("已下载").font(.caption.weight(.medium)).foregroundStyle(.green)
                                }
                            }
                            Text(model.summary).font(.caption).foregroundStyle(.secondary)
                            if let progress = speech.downloadProgress[model.id] {
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 320)
                            }
                        }
                        Spacer()
                        if speech.downloadProgress[model.id] != nil {
                            Button("取消") { speech.cancelDownload(model) }
                        } else if speech.isDownloaded(model) {
                            Button(speech.selectedLocalModelID == model.id ? "使用中" : "设为当前") {
                                speech.selectedLocalModelID = model.id
                            }
                            .disabled(speech.selectedLocalModelID == model.id || recording.phase.isBusy)
                            Button(role: .destructive) { pendingModelDeletion = model } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(recording.phase.isBusy)
                        } else {
                            Button { speech.download(model) } label: {
                                Label("下载", systemImage: "arrow.down.to.line")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
    }

    private var lanRecognitionCard: some View {
        SettingsCard {
            Label("局域网语音识别", systemImage: "network").font(.headline)
            Text("可以这样配置：xj-AI 每隔几秒把一段 WAV 音频发送到你指定的局域网 ASR 服务，收到原文后再进入翻译。")
                .font(.caption).foregroundStyle(.secondary)

            LabeledContent("服务协议") {
                Picker("服务协议", selection: $speech.lanProtocol) {
                    ForEach(LANRecognitionProtocol.allCases) { protocolKind in
                        Text(protocolKind.title).tag(protocolKind)
                    }
                }
                .labelsHidden().frame(width: 240)
            }
            LabeledContent("Base URL") {
                TextField(speech.lanProtocol.exampleURL, text: $speech.lanBaseURL)
                    .textFieldStyle(.roundedBorder).frame(width: 420)
            }
            if speech.lanProtocol == .openAI {
                LabeledContent("模型 ID") {
                    TextField("whisper-1", text: $speech.lanModel)
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                }
            }
            LabeledContent("API Key") {
                SecureField("可留空", text: $speech.lanAPIKey)
                    .textFieldStyle(.roundedBorder).frame(width: 280)
            }
            Text(speech.lanProtocol.endpointDescription)
                .font(.caption).foregroundStyle(.secondary)
            Label("选择局域网识别后，原始音频会发送到这个地址。请只使用你信任的内网服务器，不要把 whisper.cpp 服务直接暴露到公网。", systemImage: "exclamationmark.shield")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func localTranslationCard(_ title: String, _ subtitle: String, _ kind: AIProviderKind) -> some View {
        SettingsCard {
            HStack {
                Image(systemName: kind.symbol).font(.title2).frame(width: 34)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("添加到 Provider") { providers.addProvider(kind) }.buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct AdvancedSettingsPage: View {
    @EnvironmentObject private var recording: RecordingStore
    var body: some View {
        SettingsPage(title: "高级", subtitle: "存储、权限与诊断选项。") {
            SettingsCard {
                Toggle("自动保存录音、转写与翻译", isOn: $recording.autoSave)
                LabeledContent("保存目录") {
                    HStack {
                        Text(recording.recordsDirectory.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle)
                        Button {
                            recording.openRecordsDirectory()
                        } label: {
                            Label("打开", systemImage: "folder")
                        }
                        Button("更改…") { recording.chooseRecordsDirectory() }
                    }
                }
            }
            SettingsCard {
                LabeledContent("语音识别", value: recording.recognitionStatusTitle)
                LabeledContent("系统音频", value: SystemAudioCaptureService.hasScreenCapturePermission ? "已授权" : "首次使用时申请")
                Button("打开隐私与安全性设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }
}

private struct AboutSettingsPage: View {
    var body: some View {
        SettingsPage(title: "关于", subtitle: "xj-AI 本地实时翻译工具") {
            SettingsCard {
                HStack(spacing: 14) {
                    Image(systemName: "waveform.circle.fill").font(.system(size: 48)).foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("xj-AI").font(.title2.bold()); Text("版本 0.2.0 · 本地优先")
                        Text("支持 Apple / Whisper / 局域网语音识别、系统音频与多种翻译 Provider。").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
