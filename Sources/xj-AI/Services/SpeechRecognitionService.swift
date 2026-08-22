import AVFoundation
import CoreMedia
import Foundation
import Speech

struct RecognizedSpeechSegment: Equatable {
    let substring: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let substringRange: NSRange

    var endTime: TimeInterval { timestamp + duration }
}

struct SpeechRecognitionUpdate: Equatable {
    let formattedText: String
    let segments: [RecognizedSpeechSegment]
    let isFinal: Bool
}

final class SpeechRecognitionService {
    enum RecognitionError: LocalizedError {
        case permissionDenied
        case recognizerUnavailable
        case onDeviceUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "未获得语音识别权限，请在系统设置的“隐私与安全性”中允许 xj-AI。"
            case .recognizerUnavailable:
                "当前语言的语音识别器暂时不可用。"
            case .onDeviceUnavailable(let locale):
                "\(locale) 尚未安装可用的 Apple 本地语音模型。请在系统设置中添加对应语言后重试。"
            }
        }
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func start(
        localeIdentifier: String,
        onText: @escaping (SpeechRecognitionUpdate) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        stop()

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw RecognitionError.permissionDenied
        }

        let locale = Locale(identifier: localeIdentifier)
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            throw RecognitionError.recognizerUnavailable
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw RecognitionError.onDeviceUnavailable(locale.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .dictation
        request.addsPunctuation = true

        self.recognizer = recognizer
        self.request = request
        self.task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let transcription = result.bestTranscription
                let segments = transcription.segments.map { segment in
                    RecognizedSpeechSegment(
                        substring: segment.substring,
                        timestamp: segment.timestamp,
                        duration: segment.duration,
                        substringRange: segment.substringRange
                    )
                }
                onText(SpeechRecognitionUpdate(
                    formattedText: transcription.formattedString,
                    segments: segments,
                    isFinal: result.isFinal
                ))
            }
            if let error { onError(error) }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        request?.appendAudioSampleBuffer(sampleBuffer)
    }

    func finishAudio() {
        request?.endAudio()
    }

    func stop() {
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }
}
