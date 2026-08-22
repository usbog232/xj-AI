import AVFoundation
import CoreMedia
import Foundation

struct ChunkRecognitionResult: Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

final class ChunkedSpeechRecognitionService {
    enum ServiceError: LocalizedError {
        case notConfigured

        var errorDescription: String? { "语音识别引擎尚未配置。" }
    }

    private let conversionQueue = DispatchQueue(label: "net.xj-ai.speech-conversion", qos: .userInitiated)
    private let conversionGroup = DispatchGroup()
    private let pcmConverter = SpeechPCMConverter()
    private var pipeline: ChunkPipeline?

    func start(
        configuration: ChunkRecognitionConfiguration,
        onResult: @escaping @Sendable (ChunkRecognitionResult) async -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        guard configuration.engine != .apple else { throw ServiceError.notConfigured }
        if configuration.engine == .localWhisper, configuration.localModelURL == nil {
            throw LocalWhisperTranscriber.TranscriptionError.modelMissing
        }
        pipeline = ChunkPipeline(
            configuration: configuration,
            onResult: onResult,
            onError: onError
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let pipeline, let ownedBuffer = SpeechAudioUtilities.copy(buffer) else { return }
        conversionGroup.enter()
        conversionQueue.async {
            do {
                let samples = try self.pcmConverter.convert(ownedBuffer)
                Task {
                    await pipeline.append(samples)
                    self.conversionGroup.leave()
                }
            } catch {
                Task {
                    await pipeline.report(error)
                    self.conversionGroup.leave()
                }
            }
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard let pipeline, let ownedBuffer = AudioFileWriter.pcmBuffer(from: sampleBuffer) else { return }
        conversionGroup.enter()
        conversionQueue.async {
            do {
                let samples = try self.pcmConverter.convert(ownedBuffer)
                Task {
                    await pipeline.append(samples)
                    self.conversionGroup.leave()
                }
            } catch {
                Task {
                    await pipeline.report(error)
                    self.conversionGroup.leave()
                }
            }
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            conversionGroup.notify(queue: conversionQueue) {
                continuation.resume()
            }
        }
        await pipeline?.finish()
        pipeline = nil
    }

    func stop() async {
        await pipeline?.cancel()
        pipeline = nil
    }
}

private actor ChunkPipeline {
    private let configuration: ChunkRecognitionConfiguration
    private let onResult: @Sendable (ChunkRecognitionResult) async -> Void
    private let onError: @Sendable (Error) -> Void
    private let chunkSampleCount: Int
    private var samples: [Float] = []
    private var processedSamples = 0
    private var pendingTask: Task<Void, Never>?
    private var isCancelled = false

    init(
        configuration: ChunkRecognitionConfiguration,
        onResult: @escaping @Sendable (ChunkRecognitionResult) async -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) {
        self.configuration = configuration
        self.onResult = onResult
        self.onError = onError
        chunkSampleCount = max(16_000, Int(configuration.chunkDuration * 16_000))
    }

    func append(_ newSamples: [Float]) {
        guard !isCancelled else { return }
        samples.append(contentsOf: newSamples)
        while samples.count >= chunkSampleCount {
            let chunk = Array(samples.prefix(chunkSampleCount))
            samples.removeFirst(chunkSampleCount)
            enqueue(chunk)
        }
    }

    func finish() async {
        if samples.count >= 8_000 {
            let remainder = samples
            samples.removeAll(keepingCapacity: false)
            enqueue(remainder)
        }
        let finalTask = pendingTask
        await finalTask?.value
    }

    func cancel() {
        isCancelled = true
        samples.removeAll(keepingCapacity: false)
        pendingTask?.cancel()
        pendingTask = nil
    }

    func report(_ error: Error) {
        onError(error)
    }

    private func enqueue(_ chunk: [Float]) {
        let previous = pendingTask
        let start = TimeInterval(processedSamples) / 16_000
        processedSamples += chunk.count
        let end = TimeInterval(processedSamples) / 16_000
        let configuration = configuration
        let onResult = onResult
        let onError = onError

        pendingTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            do {
                let text: String
                switch configuration.engine {
                case .apple:
                    return
                case .localWhisper:
                    guard let modelURL = configuration.localModelURL else {
                        throw LocalWhisperTranscriber.TranscriptionError.modelMissing
                    }
                    text = try await LocalWhisperTranscriber().transcribe(
                        samples: chunk,
                        modelURL: modelURL,
                        language: configuration.language
                    )
                case .lan:
                    text = try await LANTranscriptionClient(
                        protocolKind: configuration.lanProtocol,
                        baseURL: configuration.lanBaseURL,
                        model: configuration.lanModel,
                        apiKey: configuration.lanAPIKey
                    ).transcribe(samples: chunk, language: configuration.language)
                }
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    await onResult(ChunkRecognitionResult(text: cleaned, startTime: start, endTime: end))
                }
            } catch {
                onError(error)
            }
        }
    }
}
