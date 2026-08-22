import Foundation

struct LocalWhisperTranscriber: Sendable {
    enum TranscriptionError: LocalizedError {
        case helperMissing
        case modelMissing
        case processFailed(String)

        var errorDescription: String? {
            switch self {
            case .helperMissing:
                "xj-AI 的本地 Whisper 识别组件缺失，请重新构建或安装 App。"
            case .modelMissing:
                "尚未下载所选本地语音模型，请先在“设置 → 本地模型”中下载。"
            case .processFailed(let detail):
                detail.isEmpty ? "本地 Whisper 识别失败。" : "本地 Whisper 识别失败：\(detail)"
            }
        }
    }

    static var helperURL: URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "Tools/whisper-cli"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appending(path: "Resources/Tools/whisper-cli"),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ].compactMap { $0 }
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    func transcribe(samples: [Float], modelURL: URL, language: String) async throws -> String {
        guard !samples.isEmpty else { return "" }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelMissing
        }
        guard let helperURL = Self.helperURL else { throw TranscriptionError.helperMissing }

        let wavURL = FileManager.default.temporaryDirectory
            .appending(path: "xj-AI-whisper-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        try SpeechAudioUtilities.wavData(from: samples).write(to: wavURL, options: .atomic)

        let languageCode = SpeechAudioUtilities.whisperLanguage(from: language)
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = helperURL
        process.arguments = [
            "-m", modelURL.path,
            "-f", wavURL.path,
            "-l", languageCode,
            "--no-gpu",
            "--no-timestamps",
            "--no-prints",
            "--suppress-nst",
            "-t", String(min(8, max(2, ProcessInfo.processInfo.processorCount / 2)))
        ]
        process.standardOutput = stdout
        process.standardError = stderr

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if status != 0 {
            let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TranscriptionError.processFailed(String(detail.suffix(240)))
        }
        return output
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
