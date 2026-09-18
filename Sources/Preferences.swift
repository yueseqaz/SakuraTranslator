import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    private enum Keys {
        static let provider = "provider"
        static let language = "languageTarget"
        static let autoTranslate = "autoTranslate"
        static let autoCopy = "autoCopyResult"
    }

    @Published var provider: Provider {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    @Published var languageTarget: LanguageTarget {
        didSet { defaults.set(languageTarget.rawValue, forKey: Keys.language) }
    }

    @Published var autoTranslate: Bool {
        didSet { defaults.set(autoTranslate, forKey: Keys.autoTranslate) }
    }

    @Published var autoCopyResult: Bool {
        didSet { defaults.set(autoCopyResult, forKey: Keys.autoCopy) }
    }

    @Published var apiKeys: [Provider: String] = [:]
    @Published var models: [Provider: String] = [:]
    @Published var baseURLs: [Provider: String] = [:]

    init() {
        let rawProvider = defaults.string(forKey: Keys.provider) ?? Provider.deepseek.rawValue
        provider = Provider(rawValue: rawProvider) ?? .deepseek

        let rawLang = defaults.string(forKey: Keys.language) ?? LanguageTarget.autoToChinese.rawValue
        languageTarget = LanguageTarget(rawValue: rawLang) ?? .autoToChinese

        autoTranslate = defaults.object(forKey: Keys.autoTranslate) as? Bool ?? false
        autoCopyResult = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true

        for p in Provider.allCases {
            apiKeys[p] = defaults.string(forKey: keyName(p)) ?? ""
            let storedModel = defaults.string(forKey: modelNameKey(p))
            if p.isCustom {
                models[p] = storedModel ?? ""
                baseURLs[p] = defaults.string(forKey: baseNameKey(p)) ?? ""
            } else {
                models[p] = (storedModel?.isEmpty == false) ? storedModel! : p.defaultModel
                let storedBase = defaults.string(forKey: baseNameKey(p))
                baseURLs[p] = (storedBase?.isEmpty == false) ? storedBase! : p.defaultBaseURL
            }
        }
    }

    private func keyName(_ p: Provider) -> String {
        "apiKey.\(p.rawValue)"
    }

    private func modelNameKey(_ p: Provider) -> String {
        "model.\(p.rawValue)"
    }

    private func baseNameKey(_ p: Provider) -> String {
        "baseURL.\(p.rawValue)"
    }

    func apiKey(for provider: Provider) -> String {
        apiKeys[provider] ?? ""
    }

    func model(for provider: Provider) -> String {
        let value = (models[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isCustom { return value }
        return value.isEmpty ? provider.defaultModel : value
    }

    func baseURL(for provider: Provider) -> String {
        let value = (baseURLs[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isCustom { return value }
        return value.isEmpty ? provider.defaultBaseURL : value
    }

    func setAPIKey(_ key: String, for provider: Provider) {
        apiKeys[provider] = key
        defaults.set(key, forKey: keyName(provider))
    }

    func setModel(_ model: String, for provider: Provider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isCustom {
            models[provider] = trimmed
            defaults.set(trimmed, forKey: modelNameKey(provider))
            return
        }
        let value = trimmed.isEmpty ? provider.defaultModel : trimmed
        models[provider] = value
        defaults.set(value, forKey: modelNameKey(provider))
    }

    func setBaseURL(_ url: String, for provider: Provider) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isCustom {
            baseURLs[provider] = trimmed
            defaults.set(trimmed, forKey: baseNameKey(provider))
            return
        }
        let value = trimmed.isEmpty ? provider.defaultBaseURL : trimmed
        baseURLs[provider] = value
        defaults.set(value, forKey: baseNameKey(provider))
    }

    var currentHasKey: Bool {
        !apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ready to call chat/completions
    var currentIsReady: Bool {
        guard currentHasKey else { return false }
        let model = model(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseURL(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.isCustom {
            return !model.isEmpty && !base.isEmpty
        }
        return !model.isEmpty
    }
}
