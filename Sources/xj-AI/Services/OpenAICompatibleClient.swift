import Foundation

struct OpenAICompatibleClient {
    enum ClientError: LocalizedError {
        case invalidBaseURL
        case missingAPIKey
        case invalidResponse
        case server(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: "Base URL 无效。请填写包含 http:// 或 https:// 的完整地址。"
            case .missingAPIKey: "这个 Provider 需要 API Key。"
            case .invalidResponse: "服务返回了无法解析的响应。"
            case .server(let message): "服务错误：\(message)"
            case .emptyResult: "模型没有返回文本。"
            }
        }
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    func models(provider: AIProviderConfiguration, apiKey: String) async throws -> [String] {
        try requireKeyIfNeeded(provider, apiKey: apiKey)
        let request = try request(provider: provider, apiKey: apiKey, path: "models")
        let data = try await send(request)
        return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id).sorted()
    }

    func translate(
        text: String,
        targetLanguage: String,
        promptTemplate: String,
        provider: AIProviderConfiguration,
        model: String,
        apiKey: String
    ) async throws -> String {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return "" }
        try requireKeyIfNeeded(provider, apiKey: apiKey)
        guard !model.isEmpty else { throw ClientError.server("请先选择模型") }

        let prompt = promptTemplate
            .replacingOccurrences(of: "{{targetLang}}", with: targetLanguage)
            .replacingOccurrences(of: "{{text}}", with: cleanText)
        var request = try request(provider: provider, apiKey: apiKey, path: "chat/completions")
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are a precise realtime subtitle translator."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.15,
            "stream": false
        ])
        let data = try await send(request)
        let result = try JSONDecoder().decode(ChatResponse.self, from: data)
            .choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !result.isEmpty else { throw ClientError.emptyResult }
        return result
    }

    private func requireKeyIfNeeded(_ provider: AIProviderConfiguration, apiKey: String) throws {
        if !provider.kind.apiKeyOptional && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ClientError.missingAPIKey
        }
    }

    private func request(provider: AIProviderConfiguration, apiKey: String, path: String) throws -> URLRequest {
        let raw = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw), components.scheme != nil, components.host != nil else {
            throw ClientError.invalidBaseURL
        }
        var basePath = components.path
        if !basePath.hasSuffix("/") { basePath += "/" }
        components.path = basePath + path
        guard let url = components.url else { throw ClientError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let error = json?["error"]
                let message: String
                if let value = error as? String {
                    message = value
                } else if let dictionary = error as? [String: Any], let value = dictionary["message"] as? String {
                    message = value
                } else {
                    message = "HTTP \(http.statusCode)"
                }
                throw ClientError.server(message)
            }
            return data
        } catch let error as ClientError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                throw ClientError.server("无法连接模型服务，请确认 Base URL、网络和服务状态")
            default:
                throw ClientError.server(error.localizedDescription)
            }
        }
    }
}
