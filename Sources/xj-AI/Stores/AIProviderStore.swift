import Foundation

@MainActor
final class AIProviderStore: ObservableObject {
    private enum Keys {
        static let providers = "aiProviders.v2"
        static let selectedProviderID = "selectedAIProviderID"
        static let selectedModel = "selectedAIModel"
        static let targetLanguage = "translationTargetLanguage"
        static let translationPrompt = "translationPrompt"
        static let liveTranslation = "liveTranslationEnabled"
    }

    @Published var providers: [AIProviderConfiguration] {
        didSet { persistProviders() }
    }
    @Published var selectedProviderID: UUID? {
        didSet { UserDefaults.standard.set(selectedProviderID?.uuidString, forKey: Keys.selectedProviderID) }
    }
    @Published var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: Keys.selectedModel) }
    }
    @Published var targetLanguage: String {
        didSet { UserDefaults.standard.set(targetLanguage, forKey: Keys.targetLanguage) }
    }
    @Published var promptTemplate: String {
        didSet { UserDefaults.standard.set(promptTemplate, forKey: Keys.translationPrompt) }
    }
    @Published var liveTranslationEnabled: Bool {
        didSet { UserDefaults.standard.set(liveTranslationEnabled, forKey: Keys.liveTranslation) }
    }
    @Published private(set) var connectionState: ConnectionState = .idle

    enum ConnectionState: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)

        var title: String {
            switch self {
            case .idle: "尚未检测"
            case .testing: "正在连接…"
            case .success(let message), .failure(let message): message
            }
        }
    }

    private let client = OpenAICompatibleClient()
    private let keychain = KeychainStore()

    init() {
        let defaults = UserDefaults.standard
        var loadedProviders: [AIProviderConfiguration]
        if let data = defaults.data(forKey: Keys.providers),
           let decoded = try? JSONDecoder().decode([AIProviderConfiguration].self, from: data),
           !decoded.isEmpty {
            loadedProviders = decoded
        } else {
            loadedProviders = [AIProviderConfiguration.preset(.ollama)]
        }
        for index in loadedProviders.indices where loadedProviders[index].modelIDs.isEmpty {
            let defaults = loadedProviders[index].kind.defaultModels
            if !defaults.isEmpty { loadedProviders[index].modelIDs = defaults }
        }
        providers = loadedProviders
        selectedProviderID = defaults.string(forKey: Keys.selectedProviderID).flatMap(UUID.init(uuidString:)) ?? loadedProviders.first?.id
        selectedModelID = defaults.string(forKey: Keys.selectedModel) ?? loadedProviders.first?.modelIDs.first ?? ""
        targetLanguage = defaults.string(forKey: Keys.targetLanguage) ?? "简体中文"
        promptTemplate = defaults.string(forKey: Keys.translationPrompt) ?? "Translate the following text into {{targetLang}}. Output only the translation, nothing else:\n{{text}}"
        liveTranslationEnabled = defaults.object(forKey: Keys.liveTranslation) as? Bool ?? true
        normalizeSelection()
    }

    var selectedProvider: AIProviderConfiguration? {
        providers.first(where: { $0.id == selectedProviderID })
    }

    var enabledProviders: [AIProviderConfiguration] { providers.filter(\.isEnabled) }

    func addProvider(_ kind: AIProviderKind) {
        let provider = AIProviderConfiguration.preset(kind)
        providers.append(provider)
        selectedProviderID = provider.id
        selectedModelID = provider.modelIDs.first ?? ""
        connectionState = .idle
    }

    func deleteProvider(_ id: UUID) {
        keychain.remove(account: id.uuidString)
        providers.removeAll { $0.id == id }
        normalizeSelection()
        connectionState = .idle
    }

    func apiKey(for id: UUID) -> String { keychain.value(for: id.uuidString) }

    func setAPIKey(_ value: String, for id: UUID) {
        keychain.set(value, for: id.uuidString)
        connectionState = .idle
    }

    func selectProvider(_ id: UUID?) {
        selectedProviderID = id
        if let provider = selectedProvider, !provider.modelIDs.contains(selectedModelID) {
            selectedModelID = provider.modelIDs.first ?? ""
        }
        connectionState = .idle
    }

    func addModel(_ model: String, to providerID: UUID) {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        if !providers[index].modelIDs.contains(value) { providers[index].modelIDs.append(value) }
        selectedModelID = value
    }

    func removeModel(_ model: String, from providerID: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == providerID }) else { return }
        providers[index].modelIDs.removeAll { $0 == model }
        if selectedProviderID == providerID && selectedModelID == model {
            selectedModelID = providers[index].modelIDs.first ?? ""
        }
    }

    func refreshModels(for providerID: UUID? = nil) async {
        guard let provider = provider(for: providerID) else { return }
        connectionState = .testing
        do {
            let models = try await client.models(provider: provider, apiKey: apiKey(for: provider.id))
            guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
            providers[index].modelIDs = models
            if selectedProviderID == provider.id && !models.contains(selectedModelID) {
                selectedModelID = models.first ?? ""
            }
            connectionState = .success("连接成功，发现 \(models.count) 个模型")
        } catch {
            connectionState = .failure(error.localizedDescription)
        }
    }

    func testTranslation() async {
        do {
            _ = try await translate("Hello, welcome to xj-AI.")
            connectionState = .success("测试翻译成功")
        } catch {
            connectionState = .failure(error.localizedDescription)
        }
    }

    func translate(_ text: String) async throws -> String {
        guard liveTranslationEnabled else { return text }
        guard let provider = selectedProvider, provider.isEnabled else {
            throw OpenAICompatibleClient.ClientError.server("请在设置中选择并启用 Provider")
        }
        return try await client.translate(
            text: text,
            targetLanguage: targetLanguage,
            promptTemplate: promptTemplate,
            provider: provider,
            model: selectedModelID,
            apiKey: apiKey(for: provider.id)
        )
    }

    private func provider(for id: UUID?) -> AIProviderConfiguration? {
        let resolved = id ?? selectedProviderID
        return providers.first(where: { $0.id == resolved })
    }

    private func normalizeSelection() {
        if !providers.contains(where: { $0.id == selectedProviderID }) { selectedProviderID = providers.first?.id }
        if let provider = selectedProvider, !provider.modelIDs.contains(selectedModelID) {
            selectedModelID = provider.modelIDs.first ?? ""
        }
    }

    private func persistProviders() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: Keys.providers)
        }
    }
}
