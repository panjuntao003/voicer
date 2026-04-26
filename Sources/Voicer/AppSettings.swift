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
        get { defaults.string(forKey: Key.llmBaseURL.rawValue) ?? "https://api.openai.com" }
        set { defaults.set(newValue, forKey: Key.llmBaseURL.rawValue) }
    }

    var llmAPIKey: String {
        get { defaults.string(forKey: Key.llmAPIKey.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmAPIKey.rawValue) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Key.llmModel.rawValue) ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Key.llmModel.rawValue) }
    }
}
