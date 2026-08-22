import AVFoundation
import Foundation
import XCTest
@testable import xj_AI

final class SpeechRecognitionConfigurationTests: XCTestCase {
    func testAudioConversionProducesMono16KSamples() throws {
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        ))
        let converter = SpeechPCMConverter()
        var converted: [Float] = []
        for bufferIndex in 0..<48 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_000))
            buffer.frameLength = 1_000
            for channel in 0..<2 {
                let samples = try XCTUnwrap(buffer.floatChannelData?[channel])
                for index in 0..<1_000 {
                    samples[index] = sin(Float(bufferIndex * 1_000 + index) * 0.02) * 0.1
                }
            }
            converted.append(contentsOf: try converter.convert(buffer))
        }

        XCTAssertEqual(converted.count, 16_000, accuracy: 64)
        XCTAssertTrue(converted.contains(where: { abs($0) > 0.01 }))
    }

    func testWAVEncodingHasPCMHeaderAndExpectedLength() {
        let data = SpeechAudioUtilities.wavData(from: Array(repeating: 0.25, count: 16_000))

        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(String(data: data[36..<40], encoding: .ascii), "data")
        XCTAssertEqual(data.count, 44 + 16_000 * 2)
    }

    func testOpenAIEndpointResolution() {
        let client = LANTranscriptionClient(
            protocolKind: .openAI,
            baseURL: "http://192.168.1.20:8000/v1",
            model: "whisper-1",
            apiKey: ""
        )

        XCTAssertEqual(
            client.resolvedEndpointURL?.absoluteString,
            "http://192.168.1.20:8000/v1/audio/transcriptions"
        )
    }

    func testWhisperCppEndpointResolution() {
        let client = LANTranscriptionClient(
            protocolKind: .whisperCpp,
            baseURL: "http://192.168.1.20:8080",
            model: "",
            apiKey: ""
        )

        XCTAssertEqual(
            client.resolvedEndpointURL?.absoluteString,
            "http://192.168.1.20:8080/inference"
        )
    }

    func testLocalModelCatalogUsesUniqueOfficialFiles() {
        let models = LocalSpeechModel.catalog

        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        XCTAssertEqual(Set(models.map(\.fileName)).count, models.count)
        XCTAssertTrue(models.allSatisfy { $0.downloadURL.host == "huggingface.co" })
        XCTAssertTrue(models.allSatisfy { $0.fileName.hasPrefix("ggml-") && $0.fileName.hasSuffix(".bin") })
    }

    func testBundledWhisperHelperTranscribesKnownSampleWhenFixtureIsAvailable() async throws {
        let modelURL = URL(fileURLWithPath: "/private/tmp/ggml-tiny-q5_1.bin")
        let sampleURL = URL(fileURLWithPath: "/opt/homebrew/Cellar/whisper-cpp/1.9.1/share/whisper-cpp/jfk.wav")
        guard FileManager.default.fileExists(atPath: modelURL.path),
              FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Local Whisper integration fixture is not installed.")
        }

        let samples = try samples(from: sampleURL)

        let text = try await LocalWhisperTranscriber().transcribe(
            samples: samples,
            modelURL: modelURL,
            language: "en-US"
        )

        XCTAssertTrue(text.lowercased().contains("country"), "Unexpected transcript: \(text)")
    }

    func testLANWhisperCppClientWhenTestServerIsAvailable() async throws {
        guard let baseURL = ProcessInfo.processInfo.environment["XJ_AI_TEST_LAN_URL"] else {
            throw XCTSkip("No LAN ASR test server configured.")
        }
        let sampleURL = URL(fileURLWithPath: "/opt/homebrew/Cellar/whisper-cpp/1.9.1/share/whisper-cpp/jfk.wav")
        guard FileManager.default.fileExists(atPath: sampleURL.path) else {
            throw XCTSkip("Whisper test audio is not installed.")
        }

        let text = try await LANTranscriptionClient(
            protocolKind: .whisperCpp,
            baseURL: baseURL,
            model: "",
            apiKey: ""
        ).transcribe(samples: try samples(from: sampleURL), language: "en-US")

        XCTAssertTrue(text.lowercased().contains("country"), "Unexpected transcript: \(text)")
    }

    private func samples(from audioURL: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ))
        try audioFile.read(into: buffer)
        return try SpeechPCMConverter().convert(buffer)
    }
}
