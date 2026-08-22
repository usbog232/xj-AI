import Foundation

struct LANTranscriptionClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidURL
        case invalidResponse
        case requestFailed(Int, String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "局域网识别地址无效，请填写包含 http:// 或 https:// 的完整地址。"
            case .invalidResponse: "局域网识别服务返回了无法解析的结果。"
            case .requestFailed(let status, let detail):
                "局域网识别请求失败（HTTP \(status)）\(detail.isEmpty ? "" : "：\(detail)")"
            }
        }
    }

    let protocolKind: LANRecognitionProtocol
    let baseURL: String
    let model: String
    let apiKey: String

    func transcribe(samples: [Float], language: String) async throws -> String {
        guard let resolvedEndpointURL else { throw ClientError.invalidURL }
        let boundary = "xj-ai-boundary-\(UUID().uuidString)"
        var request = URLRequest(url: resolvedEndpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var fields: [(String, String)] = [("response_format", "json")]
        switch protocolKind {
        case .openAI:
            fields.append(("model", model.isEmpty ? "whisper-1" : model))
        case .whisperCpp:
            fields.append(("temperature", "0.0"))
        }
        let languageCode = SpeechAudioUtilities.whisperLanguage(from: language)
        if languageCode != "auto" { fields.append(("language", languageCode)) }
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: fields,
            fileData: SpeechAudioUtilities.wavData(from: samples)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8)
                .map { String($0.prefix(240)) } ?? ""
            throw ClientError.requestFailed(http.statusCode, detail)
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = object["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw ClientError.invalidResponse
    }

    var resolvedEndpointURL: URL? {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme != nil,
              components.host != nil else { return nil }
        var path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch protocolKind {
        case .openAI:
            if !path.hasSuffix("audio/transcriptions") {
                path = path.hasSuffix("v1") ? "\(path)/audio/transcriptions" : "\(path.isEmpty ? "" : "\(path)/")v1/audio/transcriptions"
            }
        case .whisperCpp:
            if !path.hasSuffix("inference") {
                path = path.isEmpty ? "inference" : "\(path)/inference"
            }
        }
        components.path = "/\(path)"
        return components.url
    }

    private func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileData: Data
    ) -> Data {
        var body = Data()
        for (name, value) in fields {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"xj-ai-chunk.wav\"\r\n")
        body.appendUTF8("Content-Type: audio/wav\r\n\r\n")
        body.append(fileData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(contentsOf: string.utf8)
    }
}
