import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var recording: RecordingStore

    var body: some View {
        HStack(spacing: 12) {
            Label(
                recording.recognitionStatusTitle,
                systemImage: recording.recognitionStatusIsReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(recording.recognitionStatusIsReady ? AppTheme.success : AppTheme.warning)

            Text(recording.statusMessage)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)

            Spacer()

            Label(TimeFormatters.clock(recording.elapsed), systemImage: "clock")
                .foregroundStyle(AppTheme.muted)

            Spacer()

            Label(recording.autoSave ? "已自动保存" : "自动保存已关闭", systemImage: recording.autoSave ? "checkmark.icloud" : "icloud.slash")
                .foregroundStyle(AppTheme.muted)
        }
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 18)
        .frame(height: 40)
        .background(.ultraThinMaterial)
    }
}
