import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var recording: RecordingStore
    @State private var inspectorVisible = false
    @State private var showsSettings = false

    var body: some View {
        Group {
            if showsSettings {
                SettingsView(onBack: { showsSettings = false })
                    .transition(.opacity)
            } else {
                workspace
                    .transition(.opacity)
            }
        }
        .background(AppTheme.root)
        .onAppear { recording.bootstrap() }
        .animation(.easeInOut(duration: 0.18), value: showsSettings)
    }

    private var workspace: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1_240
            VStack(spacing: 0) {
                AppChromeView(
                    inspectorVisible: $inspectorVisible,
                    onOpenSettings: { showsSettings = true }
                )
                Rectangle().fill(AppTheme.hairline).frame(height: 1)

                ZStack(alignment: .trailing) {
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: compact ? 220 : 250)

                        Rectangle().fill(AppTheme.hairline).frame(width: 1)

                        WorkspaceView()
                            .frame(minWidth: 0, maxWidth: .infinity)

                        if inspectorVisible && !compact {
                            Rectangle().fill(AppTheme.hairline).frame(width: 1)
                            InspectorView()
                                .frame(width: 300)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }

                    if inspectorVisible && compact {
                        InspectorView()
                            .frame(width: min(340, geometry.size.width * 0.42))
                            .background(.regularMaterial)
                            .shadow(color: .black.opacity(0.5), radius: 18, x: -8)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                Rectangle().fill(AppTheme.hairline).frame(height: 1)
                StatusBarView()
            }
            .animation(.easeInOut(duration: 0.18), value: inspectorVisible)
            .animation(.easeInOut(duration: 0.18), value: compact)
        }
    }
}

private struct WorkspaceView: View {
    var body: some View {
        VStack(spacing: 0) {
            ControlRailView()
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
            WaveformTimelineView()
                .frame(height: 118)
            Rectangle().fill(AppTheme.hairline).frame(height: 1)
            TranscriptView()
        }
        .background(AppTheme.canvas)
    }
}
