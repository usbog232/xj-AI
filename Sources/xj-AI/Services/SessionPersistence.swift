import AppKit
import Foundation

final class SessionPersistence {
    enum PersistenceError: LocalizedError {
        case sessionMissing
        case cannotCreateDirectory
        case cannotCreateExport
        case audioMissing
        case mp3EncoderUnavailable
        case audioConversionFailed

        var errorDescription: String? {
            switch self {
            case .sessionMissing: "没有可导出的会话。"
            case .cannotCreateDirectory: "无法创建记录目录。"
            case .cannotCreateExport: "无法创建会话导出目录。"
            case .audioMissing: "选中的记录没有可下载的本地音频。"
            case .mp3EncoderUnavailable: "没有找到 FFmpeg，无法生成 MP3。请先安装 FFmpeg，或改选 WAV。"
            case .audioConversionFailed: "音频格式转换失败。"
            }
        }
    }

    private let fileManager = FileManager.default
    private let recordsDirectoryOverride: URL?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(recordsDirectory: URL? = nil) {
        recordsDirectoryOverride = recordsDirectory
    }

    var recordsDirectory: URL {
        if let recordsDirectoryOverride { return recordsDirectoryOverride }
        if let saved = UserDefaults.standard.string(forKey: AppPreferences.recordsDirectoryKey), !saved.isEmpty {
            return URL(fileURLWithPath: saved, isDirectory: true)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appending(path: "xj-AI/Records", directoryHint: .isDirectory)
    }

    func setRecordsDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: AppPreferences.recordsDirectoryKey)
    }

    func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(at: recordsDirectory, withIntermediateDirectories: true)
        } catch {
            throw PersistenceError.cannotCreateDirectory
        }
    }

    func loadSessions() -> [SessionRecord] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordsDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(SessionRecord.self, from: $0) }
            .filter { $0.duration > 0 || !$0.segments.isEmpty || $0.audioFileName != nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ session: SessionRecord) throws {
        try prepareDirectory()
        let data = try encoder.encode(session)
        try data.write(to: jsonURL(for: session), options: .atomic)
    }

    func delete(_ session: SessionRecord) throws {
        var candidates = [jsonURL(for: session)]
        if let audio = session.audioFileName {
            candidates.append(recordsDirectory.appending(path: URL(fileURLWithPath: audio).lastPathComponent))
        }
        candidates.append(recordsDirectory.appending(path: "\(session.id.uuidString).caf"))

        let shortID = String(session.id.uuidString.prefix(8))
        if let files = try? fileManager.contentsOfDirectory(
            at: recordsDirectory,
            includingPropertiesForKeys: nil
        ) {
            candidates.append(contentsOf: files.filter { url in
                ExportFormat.allCases.map(\.rawValue).contains(url.pathExtension.lowercased())
                    && url.deletingPathExtension().lastPathComponent.hasSuffix("-\(shortID)")
            })
        }

        for url in Set(candidates) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    @discardableResult
    func download(
        _ sessions: [SessionRecord],
        options: SessionDownloadOptions,
        to destination: URL
    ) async throws -> (directory: URL, exportedCount: Int, skippedCount: Int) {
        guard !sessions.isEmpty else { throw PersistenceError.sessionMissing }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let root = uniqueDirectory(
            destination.appending(path: "xj-AI-Export-\(formatter.string(from: Date()))", directoryHint: .isDirectory)
        )
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            throw PersistenceError.cannotCreateExport
        }

        var exportedCount = 0
        for session in sessions {
            let base = safeFileName(session.title) + "-" + session.id.uuidString.prefix(8)
            switch options.kind {
            case .subtitles:
                let text = exportText(
                    for: session,
                    format: options.subtitleFormat,
                    content: options.subtitleContent
                )
                try text.write(
                    to: root.appending(path: "\(base).\(options.subtitleFormat.rawValue)"),
                    atomically: true,
                    encoding: .utf8
                )
                exportedCount += 1
            case .audio:
                guard let source = audioURL(for: session) else { continue }
                let output = root.appending(path: "\(base).\(options.audioFormat.rawValue)")
                try await convertAudio(from: source, to: output, format: options.audioFormat)
                exportedCount += 1
            }
        }

        if exportedCount == 0 {
            try? fileManager.removeItem(at: root)
            throw PersistenceError.audioMissing
        }
        return (root, exportedCount, sessions.count - exportedCount)
    }

    func audioURL(sessionID: UUID) throws -> URL {
        try prepareDirectory()
        return recordsDirectory.appending(path: "\(sessionID.uuidString).caf")
    }

    @discardableResult
    func export(_ session: SessionRecord, format: ExportFormat) throws -> URL {
        try prepareDirectory()
        let base = safeFileName(session.title) + "-" + session.id.uuidString.prefix(8)
        let url = recordsDirectory.appending(path: "\(base).\(format.rawValue)")
        let text = exportText(for: session, format: format, content: .bilingual)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func openRecordsDirectory() throws {
        try prepareDirectory()
        NSWorkspace.shared.open(recordsDirectory)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportText(
        for session: SessionRecord,
        format: ExportFormat,
        content: SubtitleDownloadContent
    ) -> String {
        func caption(for segment: TranscriptSegment) -> String {
            switch content {
            case .original:
                segment.original
            case .translation:
                segment.translation
            case .bilingual:
                [segment.original, segment.translation]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
        }

        let text: String
        switch format {
        case .txt:
            text = session.segments.map { segment in
                "[\(TimeFormatters.clock(segment.startTime))]\n\(caption(for: segment))"
            }.joined(separator: "\n\n")
        case .srt:
            text = session.segments.enumerated().map { index, segment in
                "\(index + 1)\n\(TimeFormatters.subtitle(segment.startTime)) --> \(TimeFormatters.subtitle(segment.endTime))\n\(caption(for: segment))"
            }.joined(separator: "\n\n") + "\n"
        case .vtt:
            text = "WEBVTT\n\n" + session.segments.map { segment in
                "\(TimeFormatters.subtitle(segment.startTime, separator: ".")) --> \(TimeFormatters.subtitle(segment.endTime, separator: "."))\n\(caption(for: segment))"
            }.joined(separator: "\n\n") + "\n"
        }
        return text
    }

    private func jsonURL(for session: SessionRecord) -> URL {
        recordsDirectory.appending(path: "\(session.id.uuidString).json")
    }

    private func audioURL(for session: SessionRecord) -> URL? {
        let candidates = [
            session.audioFileName.map { recordsDirectory.appending(path: URL(fileURLWithPath: $0).lastPathComponent) },
            recordsDirectory.appending(path: "\(session.id.uuidString).caf")
        ].compactMap { $0 }
        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func convertAudio(
        from source: URL,
        to destination: URL,
        format: AudioDownloadFormat
    ) async throws {
        switch format {
        case .wav:
            try await runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/afconvert"),
                arguments: ["-f", "WAVE", "-d", "LEI16", source.path, destination.path]
            )
        case .mp3:
            guard let ffmpeg = ffmpegURL() else { throw PersistenceError.mp3EncoderUnavailable }
            try await runProcess(
                executable: ffmpeg,
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-y",
                    "-i", source.path,
                    "-vn", "-codec:a", "libmp3lame", "-b:a", "128k",
                    destination.path
                ]
            )
        }
    }

    private func ffmpegURL() -> URL? {
        let candidates = [
            Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
            URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
            URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        ].compactMap { $0 }
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    private func runProcess(executable: URL, arguments: [String]) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let status = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else { throw PersistenceError.audioConversionFailed }
    }

    private func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "xj-AI-session" : cleaned
    }

    private func uniqueDirectory(_ proposed: URL) -> URL {
        guard fileManager.fileExists(atPath: proposed.path) else { return proposed }
        var counter = 2
        while true {
            let candidate = proposed.deletingLastPathComponent()
                .appending(path: "\(proposed.lastPathComponent)-\(counter)", directoryHint: .isDirectory)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }
}
