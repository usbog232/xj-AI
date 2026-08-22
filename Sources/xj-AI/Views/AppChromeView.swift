import SwiftUI

struct AppChromeView: View {
    @EnvironmentObject private var recording: RecordingStore
    @EnvironmentObject private var providers: AIProviderStore
    @EnvironmentObject private var speech: SpeechRecognitionStore
    @EnvironmentObject private var subtitleWindow: SubtitleWindowController
    @Binding var inspectorVisible: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.live.opacity(0.15))
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.live)
                }
                .frame(width: 28, height: 28)

                Text("xj-AI")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 218, alignment: .leading)

            Text("实时翻译")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(recording.phase.isRecording ? AppTheme.recording : AppTheme.success)
                    .frame(width: 7, height: 7)
                Text(privacyStatus)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            Button {
                inspectorVisible.toggle()
            } label: {
                Image(systemName: inspectorVisible ? "sidebar.right" : "sidebar.trailing")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(inspectorVisible ? "隐藏会话设置" : "显示会话设置")

            Button { subtitleWindow.toggle() } label: {
                Image(systemName: subtitleWindow.isDetached ? "rectangle.inset.filled" : "pip.enter")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help(subtitleWindow.isDetached ? "还原字幕到 App (⇧⌘F)" : "弹出实时字幕 (⇧⌘F)")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("设置 (⌘,)")
        }
        .padding(.leading, 80)
        .padding(.trailing, 18)
        .frame(height: 54)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var privacyStatus: String {
        if speech.selectedEngine == .lan {
            return recording.phase.isRecording ? "正在发送音频到局域网 ASR" : "局域网语音识别 · 音频离开本机"
        }
        guard let kind = providers.selectedProvider?.kind else { return "未配置翻译 Provider" }
        switch kind {
        case .ollama, .llamaCpp, .custom:
            return recording.phase.isRecording ? "正在录制 · 本地/局域网翻译" : "本地/局域网 Provider"
        case .openAI, .deepSeek:
            return recording.phase.isRecording ? "正在录制 · 仅文字发送云端翻译" : "云端翻译 · 音频仍在本机"
        }
    }
}

struct WindowDragGesture: Gesture {
    var body: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { _ in
                if let event = NSApp.currentEvent {
                    NSApp.keyWindow?.performDrag(with: event)
                }
            }
    }
}
