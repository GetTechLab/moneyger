import Foundation
import Combine

enum AIProviderType: String, CaseIterable, Identifiable {
    case gemini = "Gemini"
    case claude = "Claude"
    case openai = "OpenAI"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var keychainKey: String {
        switch self {
        case .gemini: return KeychainKeys.geminiAPIKey
        case .claude: return KeychainKeys.claudeAPIKey
        case .openai: return KeychainKeys.openAIAPIKey
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedProvider: AIProviderType {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedAIProvider")
            updateActiveProvider()
        }
    }

    @Published var geminiKey: String = "" {
        didSet { _ = KeychainService.save(key: KeychainKeys.geminiAPIKey, value: geminiKey) }
    }
    @Published var claudeKey: String = "" {
        didSet { _ = KeychainService.save(key: KeychainKeys.claudeAPIKey, value: claudeKey) }
    }
    @Published var openAIKey: String = "" {
        didSet { _ = KeychainService.save(key: KeychainKeys.openAIAPIKey, value: openAIKey) }
    }

    @Published private(set) var activeProvider: any AIProvider = GeminiProvider()

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedAIProvider") ?? ""
        self.selectedProvider = AIProviderType(rawValue: saved) ?? .gemini
        loadKeys()
        updateActiveProvider()
    }

    private func loadKeys() {
        geminiKey = KeychainService.load(key: KeychainKeys.geminiAPIKey) ?? ""
        claudeKey = KeychainService.load(key: KeychainKeys.claudeAPIKey) ?? ""
        openAIKey = KeychainService.load(key: KeychainKeys.openAIAPIKey) ?? ""
    }

    private func updateActiveProvider() {
        switch selectedProvider {
        case .gemini: activeProvider = GeminiProvider()
        case .claude: activeProvider = ClaudeProvider()
        case .openai: activeProvider = OpenAIProvider()
        }
    }

    var isActiveProviderConfigured: Bool {
        activeProvider.isConfigured
    }
}
