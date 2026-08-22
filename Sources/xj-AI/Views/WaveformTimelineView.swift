import SwiftUI

struct WaveformTimelineView: View {
    @EnvironmentObject private var recording: RecordingStore

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                Canvas { context, size in
                    let levels = recording.audioLevels
                    let step = size.width / CGFloat(max(levels.count, 1))
                    for (index, value) in levels.enumerated() {
                        let barHeight = max(3, size.height * 0.72 * value)
                        let x = CGFloat(index) * step + step * 0.5
                        let rect = CGRect(x: x, y: (size.height - barHeight) / 2, width: max(1, step * 0.34), height: barHeight)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(AppTheme.live.opacity(recording.phase.isRecording ? 0.95 : 0.72)))
                    }
                }
            }
            .frame(height: 56)
            .accessibilityLabel("实时音频波形")

            HStack {
                Text("00:00")
                Spacer()
                Text(TimeFormatters.clock(max(recording.elapsed * 0.25, 30)))
                Spacer()
                Text(TimeFormatters.clock(max(recording.elapsed * 0.5, 60)))
                Spacer()
                Text(TimeFormatters.clock(max(recording.elapsed, 90)))
            }
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(AppTheme.canvas)
    }
}
