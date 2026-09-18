import Foundation

enum Provider: String, CaseIterable, Identifiable {
    case deepseek
    case mimo
    case glm
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .mimo: return "小米 MiMo"
        case .glm: return "智谱 GLM"
        case .custom: return "自定义"
        }
    }

    var shortName: String {
        switch self {
        case .deepseek: return "DeepSeek"
        case .mimo: return "MiMo"
        case .glm: return "GLM"
        case .custom: return "Custom"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .deepseek: return "https://api.deepseek.com"
        case .mimo: return "https://api.xiaomimimo.com/v1"
        case .glm: return "https://open.bigmodel.cn/api/paas/v4"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .deepseek: return "deepseek-flash"
        case .mimo: return "mimo-v2.5"
        case .glm: return "glm-5.3-flash"
        case .custom: return ""
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .deepseek:
            return ["deepseek-flash", "deepseek-v4-pro"]
        case .mimo:
            return ["mimo-v2.5", "mimo-v2.5-pro", "mimo-x-pro"]
        case .glm:
            return ["glm-5.3-flash", "glm-5.3", "glm-5.2", "glm-4-flash"]
        case .custom:
            return []
        }
    }

    var keyHint: String {
        switch self {
        case .deepseek:
            return "platform.deepseek.com/api_keys"
        case .mimo:
            return "platform.xiaomimimo.com 控制台"
        case .glm:
            return "bigmodel.cn/usercenter/proj-mgmt/apikeys"
        case .custom:
            return "任意 OpenAI 兼容接口"
        }
    }

    var baseURLPlaceholder: String {
        switch self {
        case .custom:
            return "https://api.example.com/v1"
        default:
            return defaultBaseURL
        }
    }

    var isCustom: Bool { self == .custom }
}

enum LanguageTarget: String, CaseIterable, Identifiable {
    case autoToChinese = "auto_zh"
    case autoToEnglish = "auto_en"
    case autoToJapanese = "auto_ja"
    case autoToKorean = "auto_ko"
    case chineseToEnglish = "zh_en"
    case englishToChinese = "en_zh"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .autoToChinese: return "自动 → 中文"
        case .autoToEnglish: return "自动 → English"
        case .autoToJapanese: return "自动 → 日本語"
        case .autoToKorean: return "自动 → 한국어"
        case .chineseToEnglish: return "中文 → English"
        case .englishToChinese: return "English → 中文"
        }
    }

    var shortLabel: String {
        switch self {
        case .autoToChinese: return "→中文"
        case .autoToEnglish: return "→EN"
        case .autoToJapanese: return "→JA"
        case .autoToKorean: return "→KO"
        case .chineseToEnglish: return "中→EN"
        case .englishToChinese: return "EN→中"
        }
    }

    var instruction: String {
        switch self {
        case .autoToChinese:
            return "Translate the user text into natural, fluent Simplified Chinese. Detect the source language automatically."
        case .autoToEnglish:
            return "Translate the user text into natural, fluent English. Detect the source language automatically."
        case .autoToJapanese:
            return "Translate the user text into natural Japanese. Detect the source language automatically."
        case .autoToKorean:
            return "Translate the user text into natural Korean. Detect the source language automatically."
        case .chineseToEnglish:
            return "Translate the Chinese user text into natural English."
        case .englishToChinese:
            return "Translate the English user text into natural Simplified Chinese."
        }
    }

    var swapped: LanguageTarget? {
        switch self {
        case .chineseToEnglish: return .englishToChinese
        case .englishToChinese: return .chineseToEnglish
        default: return nil
        }
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct StreamOptions: Encodable {
    let include_usage: Bool
}

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double?
    let stream_options: StreamOptions?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stream_options
    }
}

struct TokenUsage: Codable, Equatable {
    var promptTokens: Int
    var completionTokens: Int
    var totalTokens: Int

    static let zero = TokenUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)

    var isEmpty: Bool { totalTokens <= 0 && promptTokens <= 0 && completionTokens <= 0 }
}

struct TranslationResult {
    let text: String
    let usage: TokenUsage?
}

struct UsageRecord: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let providerRaw: String
    let model: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    var provider: Provider {
        Provider(rawValue: providerRaw) ?? .deepseek
    }
}

enum MainTab: String, CaseIterable {
    case translate
    case history
    case usage
    case settings

    var label: String {
        switch self {
        case .translate: return "翻译"
        case .history: return "历史"
        case .usage: return "用量"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .translate: return "character.bubble"
        case .history: return "clock"
        case .usage: return "chart.bar"
        case .settings: return "gearshape"
        }
    }
}

struct TranslationHistoryItem: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let source: String
    let result: String
    let providerRaw: String
    let model: String
    let languageRaw: String

    var provider: Provider {
        Provider(rawValue: providerRaw) ?? .deepseek
    }

    var language: LanguageTarget {
        LanguageTarget(rawValue: languageRaw) ?? .autoToChinese
    }
}
