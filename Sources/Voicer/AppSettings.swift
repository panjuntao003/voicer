import Foundation

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key: String {
        case language = "voicer.language"
        case llmEnabled = "voicer.llm.enabled"
        case llmBaseURL = "voicer.llm.baseURL"
        case llmAPIKey = "voicer.llm.apiKey"
        case llmModel = "voicer.llm.model"
        case llmProviderName = "voicer.llm.providerName"
        case speechAPIEnabled = "voicer.speech.apiEnabled"
        case speechModel = "voicer.speech.model"
    }

    var language: String {
        get { defaults.string(forKey: Key.language.rawValue) ?? "zh-CN" }
        set { defaults.set(newValue, forKey: Key.language.rawValue) }
    }

    var llmEnabled: Bool {
        get { defaults.bool(forKey: Key.llmEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.llmEnabled.rawValue) }
    }

    var llmBaseURL: String {
        get { defaults.string(forKey: Key.llmBaseURL.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmBaseURL.rawValue) }
    }

    var llmAPIKey: String {
        get { defaults.string(forKey: Key.llmAPIKey.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmAPIKey.rawValue) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Key.llmModel.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmModel.rawValue) }
    }

    var llmProviderName: String {
        get {
            if let stored = defaults.string(forKey: Key.llmProviderName.rawValue), !stored.isEmpty {
                return stored
            }
            // 向后兼容：老用户根据 baseURL 反向匹配
            let url = llmBaseURL
            if let matched = LLMProvider.all.first(where: { $0.baseURL == url && $0.name != "Custom" }) {
                defaults.set(matched.name, forKey: Key.llmProviderName.rawValue)
                return matched.name
            }
            return "Custom"
        }
        set { defaults.set(newValue, forKey: Key.llmProviderName.rawValue) }
    }

    var speechAPIEnabled: Bool {
        get { defaults.bool(forKey: Key.speechAPIEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.speechAPIEnabled.rawValue) }
    }

    var speechModel: String {
        get { defaults.string(forKey: Key.speechModel.rawValue) ?? "whisper-1" }
        set { defaults.set(newValue, forKey: Key.speechModel.rawValue) }
    }
}
