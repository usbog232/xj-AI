import SwiftUI

struct FloatingSubtitleView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var recording: RecordingStore
    @EnvironmentObject private var providers: AIProviderStore
    @EnvironmentObject private var subtitleWindow: SubtitleWindowController

    @AppStorage("floatingSubtitleFontSize") private var fontSize = 25.0
    @AppStorage("floatingSubtitleOpacity") private var backgroundOpacity = 0.78
    @AppStorage(AppPreferences.floatingSubtitleContentModeKey)
    private var contentMode: FloatingSubtitleContentMode = .bilingual

    private var recentSegments: [TranscriptSegment] {
        Array((sessions.selectedSession?.segments ?? []).suffix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            captionCanvas
        }
        .background(.black.opacity(backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
        .padding(1)
        .frame(minWidth: 520, minHeight: 150)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { recording.toggleRecording() } label: {
                Image(systemName: recording.phase.isRecording ? "stop.fill" : "play.fill")
                    .foregroundStyle(recording.phase.isRecording ? .red : .green)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(recording.phase.isRecording ? "停止录音" : "开始录音")

            Picker("音源", selection: $recording.audioSource) {
                ForEach(AudioSource.allCases) { source in
                    Label(source.title, systemImage: source.symbol).tag(source)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 150)

            Text(providers.selectedProvider?.name ?? "未配置 Provider")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Menu {
                Picker("字幕显示", selection: $contentMode) {
                    ForEach(FloatingSubtitleContentMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(contentMode.title)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.blue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择只显示原文、只显示译文或双语字幕")

            Button { fontSize = max(15, fontSize - 2) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .buttonStyle(.plain)
            Button { fontSize = min(48, fontSize + 2) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .buttonStyle(.plain)

            Menu {
                LabeledContent("背景") {
                    Slider(value: $backgroundOpacity, in: 0.35...0.96)
                        .frame(width: 150)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)

            Button { subtitleWindow.dock() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }
            .buttonStyle(.plain)
            .help("还原到 App 内")

            Button { subtitleWindow.dock() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("关闭独立字幕")
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(height: 48)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .simultaneousGesture(WindowDragGesture())
    }

    private var captionCanvas: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(recentSegments) { segment in
                        VStack(alignment: .leading, spacing: 4) {
                            if contentMode.showsOriginal {
                                Text(segment.original)
                                    .font(.system(size: fontSize, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            if contentMode.showsTranslation {
                                if !segment.translation.isEmpty {
                                    Text(segment.translation)
                                        .font(.system(
                                            size: contentMode == .translation ? fontSize : max(14, fontSize - 3),
                                            weight: contentMode == .translation ? .medium : .regular
                                        ))
                                        .foregroundStyle(Color(red: 0.65, green: 0.86, blue: 1.0))
                                } else {
                                    Label(
                                        segment.isTranslationPending ? "正在翻译…" : "本句暂无译文",
                                        systemImage: segment.isTranslationPending ? "ellipsis" : "exclamationmark.bubble"
                                    )
                                    .font(.system(size: max(13, fontSize - 5)))
                                    .foregroundStyle(.white.opacity(0.58))
                                }
                            }
                        }
                        .id(segment.id)
                    }

                    if !recording.liveTranscript.isEmpty {
                        if contentMode == .translation {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("正在识别，完成本句后显示译文…")
                            }
                            .font(.system(size: max(13, fontSize - 5)))
                            .foregroundStyle(.white.opacity(0.65))
                            .id("floating-live")
                        } else {
                            HStack(alignment: .bottom, spacing: 6) {
                                Text(recording.liveTranscript)
                                    .font(.system(size: fontSize, weight: .semibold))
                                    .foregroundStyle(.white)
                                Capsule().fill(.cyan).frame(width: 3, height: fontSize)
                            }
                            .id("floating-live")
                        }
                    }

                    if recentSegments.isEmpty && recording.liveTranscript.isEmpty {
                        Text("点击 ▶ 开始实时字幕")
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: recording.liveTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("floating-live", anchor: .bottom) }
            }
        }
    }
}
