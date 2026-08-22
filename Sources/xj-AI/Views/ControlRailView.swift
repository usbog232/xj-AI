import SwiftUI

struct ControlRailView: View {
    @EnvironmentObject private var recording: RecordingStore
    @EnvironmentObject private var providers: AIProviderStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 14) {
                audioSourceField
                sourceLanguageField
                targetLanguageField
                translationField
                Spacer(minLength: 8)
                RecordButton().frame(width: 108, alignment: .trailing)
            }
            .frame(minWidth: 720)

            VStack(spacing: 12) {
                HStack(alignment: .bottom, spacing: 12) {
                    audioSourceField
                    sourceLanguageField
                    targetLanguageField
                    Spacer(minLength: 0)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    translationField
                    Spacer(minLength: 0)
                    RecordButton().frame(width: 108, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .frame(minHeight: 96)
        .disabled(recording.phase == .preparing || recording.phase == .stopping)
        .background(AppTheme.root.opacity(0.62))
    }

    private var audioSourceField: some View {
        ControlField(title: "音频来源", width: 132) {
            Picker("音频来源", selection: $recording.audioSource) {
                ForEach(AudioSource.allCases) { source in
                    Label(source.title, systemImage: source.symbol).tag(source)
                }
            }
        }
    }

    private var sourceLanguageField: some View {
        ControlField(title: "源语言", width: 112) {
            Picker("源语言", selection: $recording.sourceLanguage) {
                ForEach(LanguageOption.sourceLanguages) { language in
                    Text(language.title).tag(language.id)
                }
            }
        }
    }

    private var targetLanguageField: some View {
        ControlField(title: "目标语言", width: 108) {
            Picker("目标语言", selection: $recording.targetLanguage) {
                ForEach(LanguageOption.targetLanguages) { language in
                    Text(language.title).tag(language.id)
                }
            }
        }
    }

    private var translationField: some View {
        ControlField(title: "翻译引擎", width: 180) {
            Picker("翻译引擎", selection: $providers.selectedModelID) {
                if let provider = providers.selectedProvider {
                    ForEach(provider.modelIDs, id: \.self) { model in
                        Text("\(provider.name) · \(model)").tag(model)
                    }
                } else {
                    Text("请到设置中配置").tag("")
                }
            }
        }
    }
}

private struct ControlField<Content: View>: View {
    let title: String
    let width: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.muted)
            content
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: width)
        }
    }
}

private struct RecordButton: View {
    @EnvironmentObject private var recording: RecordingStore

    var body: some View {
        Button { recording.toggleRecording() } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(recording.phase.isRecording ? AppTheme.recording : Color.white.opacity(0.78), lineWidth: 2)
                    Circle()
                        .fill(AppTheme.recording)
                        .frame(width: recording.phase.isRecording ? 18 : 25, height: recording.phase.isRecording ? 18 : 25)
                        .clipShape(recording.phase.isRecording ? AnyShape(RoundedRectangle(cornerRadius: 4)) : AnyShape(Circle()))
                }
                .frame(width: 42, height: 42)

                Text(recording.phase.isRecording ? "停止录音" : "开始录音")
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .help(recording.phase.isRecording ? "停止录音 (⌘R)" : "开始录音 (⌘R)")
    }
}
