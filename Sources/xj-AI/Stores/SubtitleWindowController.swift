import AppKit
import SwiftUI

@MainActor
final class SubtitleWindowController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isDetached = false

    private let sessionStore: SessionStore
    private let recordingStore: RecordingStore
    private let providerStore: AIProviderStore
    private var panel: NSPanel?

    init(
        sessionStore: SessionStore,
        recordingStore: RecordingStore,
        providerStore: AIProviderStore
    ) {
        self.sessionStore = sessionStore
        self.recordingStore = recordingStore
        self.providerStore = providerStore
    }

    func toggle() {
        isDetached ? dock() : show()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        isDetached = true
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dock() {
        panel?.orderOut(nil)
        isDetached = false
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { window in
            window !== panel && window.canBecomeKey && !window.title.contains("设置")
        })?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        isDetached = false
    }

    private func makePanel() -> NSPanel {
        let rootView = FloatingSubtitleView()
            .environmentObject(sessionStore)
            .environmentObject(recordingStore)
            .environmentObject(providerStore)
            .environmentObject(self)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 260),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("xj-AI-floating-subtitles")
        panel.title = "xj-AI 实时字幕"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.minSize = NSSize(width: 520, height: 150)
        panel.maxSize = NSSize(width: 1_800, height: 1_000)
        panel.contentView = NSHostingView(rootView: rootView)
        panel.delegate = self
        panel.setFrameAutosaveName("xj-AI.floatingSubtitleWindow")
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()
        return panel
    }
}
