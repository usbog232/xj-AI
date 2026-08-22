import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var recording: RecordingStore
    @EnvironmentObject private var providers: AIProviderStore
    @EnvironmentObject private var speech: SpeechRecognitionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("会话设置")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "pin")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)

                InspectorSection(title: "语音识别") {
                    Label(speech.selectedEngine.shortTitle, systemImage: speech.selectedEngine.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .xjControlSurface()
                    Text(speech.selectedEngineDetail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if recording.audioSource == .application {
                    InspectorSection(title: "采集应用") {
                        Picker("采集应用", selection: $recording.selectedApplicationID) {
                            if !recording.selectedApplicationID.isEmpty,
                               !recording.applications.contains(where: { $0.id == recording.selectedApplicationID }) {
                                Text("正在载入所选应用…")
                                    .tag(recording.selectedApplicationID)
                            }
                            if recording.applications.isEmpty {
                                Text("没有可用应用").tag("")
                            }
                            ForEach(recording.applications) { app in
                                Text(app.name).tag(app.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }
                }

                InspectorSection(title: "翻译引擎") {
                    HStack {
                        Image(systemName: providers.selectedProvider?.kind.symbol ?? "cpu")
                        Text("\(providers.selectedProvider?.name ?? "未配置") · \(providers.selectedModelID)")
                            .lineLimit(1)
                        Spacer()
                        Circle()
                            .fill(providerIsReady ? AppTheme.success : AppTheme.warning)
                            .frame(width: 7, height: 7)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .xjControlSurface()
                    Text(providerStatusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppTheme.muted)
                }

                InspectorSection(title: "自动保存") {
                    Toggle("自动保存录音、转写、翻译与时间轴", isOn: $recording.autoSave)
                        .toggleStyle(.switch)
                        .font(.system(size: 12.5))
                        .disabled(recording.phase.isBusy)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("保存路径")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppTheme.muted)
                        HStack {
                            Text(recording.recordsDirectory.path(percentEncoded: false))
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                recording.openRecordsDirectory()
                            } label: {
                                Label("打开", systemImage: "folder")
                            }
                            .controlSize(.small)
                            Button("更改…") { recording.chooseRecordsDirectory() }
                                .controlSize(.small)
                        }
                    }
                }

                InspectorSection(title: "导出") {
                    HStack(spacing: 8) {
                        ForEach(ExportFormat.allCases) { format in
                            Button { recording.exportSelected(format) } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: format.symbol)
                                        .font(.system(size: 15))
                                    Text(format.title)
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 58)
                            }
                            .buttonStyle(.plain)
                            .xjControlSurface()
                        }
                    }
                }

                Button("刷新本地模型") {
                    Task { await recording.refreshTranslationModels() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.live)
            }
            .padding(18)
        }
        .background(AppTheme.root.opacity(0.78))
    }

    private var providerIsReady: Bool {
        if case .success = providers.connectionState { return true }
        return providers.selectedProvider != nil && !providers.selectedModelID.isEmpty
    }

    private var providerStatusText: String {
        switch providers.connectionState {
        case .success(let message), .failure(let message): message
        case .testing: "正在检测模型服务…"
        case .idle: providers.selectedProvider == nil ? "请在设置中添加 Provider。" : "可在设置中测试连接。"
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
            content
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
        }
    }
}
