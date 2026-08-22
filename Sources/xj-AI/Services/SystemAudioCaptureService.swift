import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: LocalizedError {
        case noDisplay
        case applicationUnavailable
        case screenPermissionDenied

        var errorDescription: String? {
            switch self {
            case .noDisplay: "没有找到可采集的显示器。"
            case .applicationUnavailable: "所选应用已经退出，请重新选择。"
            case .screenPermissionDenied: "需要“屏幕与系统音频录制”权限才能采集系统声音。"
            }
        }
    }

    private let queue = DispatchQueue(label: "net.xj-ai.system-audio", qos: .userInitiated)
    private var stream: SCStream?
    private var writer: AudioFileWriter?
    private var onSample: ((CMSampleBuffer) -> Void)?
    private var onLevel: ((Double) -> Void)?

    static var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func availableApplications() async throws -> [CapturableApplication] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownBundleID = Bundle.main.bundleIdentifier
        return content.applications
            .filter { $0.bundleIdentifier != ownBundleID && !$0.applicationName.isEmpty }
            .map {
                CapturableApplication(
                    id: $0.bundleIdentifier,
                    name: $0.applicationName,
                    processID: $0.processID
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func start(
        applicationBundleID: String?,
        recordTo url: URL,
        onSample: @escaping (CMSampleBuffer) -> Void,
        onLevel: @escaping (Double) -> Void
    ) async throws {
        guard Self.hasScreenCapturePermission || Self.requestScreenCapturePermission() else {
            throw CaptureError.screenPermissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter: SCContentFilter
        if let applicationBundleID {
            guard let application = content.applications.first(where: { $0.bundleIdentifier == applicationBundleID }) else {
                throw CaptureError.applicationUnavailable
            }
            filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
        } else {
            let excluded = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        }

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
        configuration.queueDepth = 3
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1

        self.onSample = onSample
        self.onLevel = onLevel
        self.writer = AudioFileWriter(url: url)

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .audio)
        writer?.finish()
        writer = nil
        self.stream = nil
        onSample = nil
        onLevel = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        onSample?(sampleBuffer)
        writer?.write(sampleBuffer)
        onLevel?(AudioFileWriter.level(from: sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        writer?.finish()
    }
}
