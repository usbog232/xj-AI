import Foundation

struct OllamaClient {
    enum ClientError: LocalizedError {
        case invalidHost
        case unavailable
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidHost: "Ollama 地址无效。"
            case .unavailable: "无法连接本机 Ollama，请先启动 Ollama。"
            case .invalidResponse: "Ollama 返回了无法解析的结果。"
            case .server(let message): "Ollama 错误：\(message)"
            }
        }
    }

    struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }
        let models: [Model]
    }

    struct GenerateResponse: Decodable {
        let response: String
    }

    func availableModels(host: String) async throws -> [String] {
        guard let base = normalizedURL(host), let url = URL(string: "api/tags", relativeTo: base) else {
            throw ClientError.invalidHost
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            try validate(response: response, data: data)
            return try JSONDecoder().decode(TagsResponse.self, from: data).models.map(\.name)
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.unavailable
        }
    }

    func translate(
        text: String,
        sourceLanguage: String,
        targetLanguage: String,
        model: String,
        host: String
    ) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        guard let base = normalizedURL(host), let url = URL(string: "api/generate", relativeTo: base) else {
            throw ClientError.invalidHost
        }

        let source = LanguageOption.title(for: sourceLanguage, in: LanguageOption.sourceLanguages)
        let target = LanguageOption.title(for: targetLanguage, in: LanguageOption.targetLanguages)
        let prompt = """
        你是实时字幕翻译器。把下面内容从\(source)翻译为\(target)。
        只输出译文，不解释，不加引号；保留专有名词、数字与语气；口语应自然简洁。

        \(text)
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.15]
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
            let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
            return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.unavailable
        }
    }

    private func normalizedURL(_ host: String) -> URL? {
        let value = host.hasSuffix("/") ? host : host + "/"
        return URL(string: value)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ClientError.server(message ?? "HTTP \(http.statusCode)")
        }
    }
}
