import AVFoundation
import Foundation

final class MicrophoneCaptureService {
    enum CaptureError: LocalizedError {
        case permissionDenied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "未获得麦克风权限。"
            case .unavailable: "无法启动麦克风。"
            }
        }
    }

    private var engine: AVAudioEngine?
    private var writer: AudioFileWriter?

    static func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func start(
        recordTo url: URL,
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping (Double) -> Void
    ) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw CaptureError.permissionDenied
        }

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.unavailable }

        writer = AudioFileWriter(url: url)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            onBuffer(buffer)
            self?.writer?.write(buffer)
            onLevel(AudioFileWriter.level(from: buffer))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        writer?.finish()
        writer = nil
    }
}
