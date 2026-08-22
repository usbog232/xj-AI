import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var recording: RecordingStore
    @EnvironmentObject private var subtitleWindow: SubtitleWindowController

    var body: some View {
        Group {
            if subtitleWindow.isDetached {
                detachedPlaceholder
            } else {
                transcriptContent
            }
        }
        .background(AppTheme.canvas)
    }

    private var transcriptContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let session = sessions.selectedSession, !session.segments.isEmpty {
                        ForEach(session.segments) { segment in
                            TranscriptRow(segment: segment)
                                .id(segment.id)
                        }
                    } else if recording.liveTranscript.isEmpty {
                        EmptyTranscriptView()
                    }

                    if !recording.liveTranscript.isEmpty {
                        LiveTranscriptRow(text: recording.liveTranscript, elapsed: recording.elapsed)
                            .id("live")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .onChange(of: recording.liveTranscript) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("live", anchor: .bottom) }
            }
        }
    }

    private var detachedPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "pip")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(AppTheme.live)
            Text("实时字幕已在独立窗口显示")
                .font(.headline)
            Text("独立窗口可以移动、缩放并置于其他应用之上。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("还原到 App 内") { subtitleWindow.dock() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(TimeFormatters.clock(segment.startTime))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.muted)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 7) {
                Text(segment.original)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                if segment.isTranslationPending {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在本地翻译…")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                } else if !segment.translation.isEmpty {
                    Text(segment.translation)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color(red: 0.69, green: 0.76, blue: 0.82))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
        }
    }
}

private struct LiveTranscriptRow: View {
    let text: String
    let elapsed: TimeInterval

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(TimeFormatters.clock(elapsed))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(AppTheme.live)
                .frame(width: 72, alignment: .leading)

            HStack(alignment: .bottom, spacing: 6) {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                Capsule()
                    .fill(AppTheme.live)
                    .frame(width: 2, height: 20)
                    .opacity(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
    }
}

private struct EmptyTranscriptView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.live)
            Text("准备开始实时翻译")
                .font(.system(size: 18, weight: .semibold))
            Text("选择音频来源和语言后开始录音。原文、译文、音频和时间轴会保存在本机。")
                .font(.system(size: 13))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
    }
}
