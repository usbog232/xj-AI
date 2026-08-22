import AVFoundation
import Foundation
import XCTest
@testable import xj_AI

final class SessionPersistenceTests: XCTestCase {
    func testOriginalSRTDownloadContainsOnlyOriginalText() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var options = SessionDownloadOptions()
        options.subtitleContent = .original
        options.subtitleFormat = .srt
        let result = try await fixture.persistence.download(
            [fixture.session], options: options, to: fixture.destination
        )

        let text = try String(contentsOf: try onlyExportedFile(in: result.directory), encoding: .utf8)
        XCTAssertEqual(result.exportedCount, 1)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertTrue(text.contains("Hello world."))
        XCTAssertFalse(text.contains("你好，世界。"))
        XCTAssertTrue(text.contains("00:00:00,000 --> 00:00:03,000"))
    }

    func testTranslationTXTDownloadContainsOnlyTranslation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var options = SessionDownloadOptions()
        options.subtitleContent = .translation
        options.subtitleFormat = .txt
        let result = try await fixture.persistence.download(
            [fixture.session], options: options, to: fixture.destination
        )

        let text = try String(contentsOf: try onlyExportedFile(in: result.directory), encoding: .utf8)
        XCTAssertFalse(text.contains("Hello world."))
        XCTAssertTrue(text.contains("你好，世界。"))
    }

    func testBilingualVTTDownloadContainsBothLanguages() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var options = SessionDownloadOptions()
        options.subtitleContent = .bilingual
        options.subtitleFormat = .vtt
        let result = try await fixture.persistence.download(
            [fixture.session], options: options, to: fixture.destination
        )

        let file = try onlyExportedFile(in: result.directory)
        XCTAssertEqual(file.pathExtension, "vtt")
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("WEBVTT"))
        XCTAssertTrue(text.contains("Hello world.\n你好，世界。"))
    }

    func testWAVDownloadConvertsRecordedAudio() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var options = SessionDownloadOptions()
        options.kind = .audio
        options.audioFormat = .wav
        let result = try await fixture.persistence.download(
            [fixture.session], options: options, to: fixture.destination
        )

        let file = try onlyExportedFile(in: result.directory)
        XCTAssertEqual(file.pathExtension, "wav")
        XCTAssertEqual(try Data(contentsOf: file).prefix(4), Data("RIFF".utf8))
    }

    func testMP3DownloadConvertsRecordedAudioWhenFFmpegIsAvailable() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")
                || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ffmpeg") else {
            throw XCTSkip("FFmpeg is not installed on this Mac.")
        }
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        var options = SessionDownloadOptions()
        options.kind = .audio
        options.audioFormat = .mp3
        let result = try await fixture.persistence.download(
            [fixture.session], options: options, to: fixture.destination
        )

        let file = try onlyExportedFile(in: result.directory)
        XCTAssertEqual(file.pathExtension, "mp3")
        XCTAssertGreaterThan(try Data(contentsOf: file).count, 100)
    }

    func testDeleteRemovesJSONAudioAndGeneratedSubtitleFiles() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        _ = try fixture.persistence.export(fixture.session, format: .srt)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: fixture.records.path).isEmpty)

        try fixture.persistence.delete(fixture.session)

        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.records.path).isEmpty)
    }

    private func makeFixture() throws -> (
        root: URL,
        records: URL,
        destination: URL,
        persistence: SessionPersistence,
        session: SessionRecord
    ) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "xj-AI-persistence-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let records = root.appending(path: "records", directoryHint: .isDirectory)
        let destination = root.appending(path: "downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let session = SessionRecord(
            title: "测试会话",
            duration: 6,
            source: .systemAudio,
            sourceLanguage: "en-US",
            targetLanguage: "zh-CN",
            translationModel: "test-model",
            segments: [
                TranscriptSegment(
                    startTime: 0,
                    endTime: 3,
                    original: "Hello world.",
                    translation: "你好，世界。",
                    isTranslationPending: false
                )
            ],
            audioFileName: "recording.caf"
        )
        let persistence = SessionPersistence(recordsDirectory: records)
        try persistence.save(session)
        try writeTestAudio(to: records.appending(path: "recording.caf"))
        return (root, records, destination, persistence, session)
    }

    private func writeTestAudio(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3_200))
        buffer.frameLength = 3_200
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = sin(Float(index) * 0.05) * 0.1
            }
        }
        try file.write(from: buffer)
    }

    private func onlyExportedFile(in directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try XCTUnwrap(files.first)
    }
}
