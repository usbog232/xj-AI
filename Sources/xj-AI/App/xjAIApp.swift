import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct xjAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var sessionStore: SessionStore
    @StateObject private var providerStore: AIProviderStore
    @StateObject private var speechStore: SpeechRecognitionStore
    @StateObject private var recordingStore: RecordingStore
    @StateObject private var subtitleWindow: SubtitleWindowController

    init() {
        let sessions = SessionStore()
        let providers = AIProviderStore()
        let speech = SpeechRecognitionStore()
        let recording = RecordingStore(
            sessionStore: sessions,
            providerStore: providers,
            speechStore: speech
        )
        _sessionStore = StateObject(wrappedValue: sessions)
        _providerStore = StateObject(wrappedValue: providers)
        _speechStore = StateObject(wrappedValue: speech)
        _recordingStore = StateObject(wrappedValue: recording)
        _subtitleWindow = StateObject(wrappedValue: SubtitleWindowController(
            sessionStore: sessions,
            recordingStore: recording,
            providerStore: providers
        ))
    }

    var body: some Scene {
        WindowGroup("xj-AI", id: "main") {
            ContentView()
                .environmentObject(sessionStore)
                .environmentObject(providerStore)
                .environmentObject(speechStore)
                .environmentObject(recordingStore)
                .environmentObject(subtitleWindow)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1_380, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建实时会话") { recordingStore.newIdleSession() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("录音") {
                Button(recordingStore.phase.isRecording ? "停止录音" : "开始录音") {
                    recordingStore.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(recordingStore.phase == .preparing || recordingStore.phase == .stopping)
            }
            CommandMenu("字幕") {
                Button(subtitleWindow.isDetached ? "还原字幕到 App" : "弹出实时字幕") {
                    subtitleWindow.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(recordingStore)
                .environmentObject(providerStore)
                .environmentObject(speechStore)
                .frame(width: 900, height: 640)
                .preferredColorScheme(.dark)
        }
    }
}
