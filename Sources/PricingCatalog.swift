import Foundation

/// Local cost estimates in CNY (¥ / 1M tokens).
/// Custom providers are intentionally unpriced.
enum PricingCatalog {

    struct ModelPricing {
        /// CNY per 1M input tokens
        let inputPerMTok: Double
        /// CNY per 1M output tokens
        let outputPerMTok: Double
        let displayModel: String
        let sourceNote: String

        func cost(inputTokens: Int, outputTokens: Int) -> Double {
            (Double(inputTokens) / 1_000_000.0) * inputPerMTok
                + (Double(outputTokens) / 1_000_000.0) * outputPerMTok
        }
    }

    /// USD→CNY reference rate used to convert DeepSeek / MiMo list prices.
    static let cnyPerUSD: Double = 7.25

    static func pricing(provider: Provider, model: String) -> ModelPricing? {
        switch provider {
        case .custom:
            return nil
        case .deepseek:
            return deepseekPricing(model: model)
        case .mimo:
            return mimoPricing(model: model)
        case .glm:
            return glmPricing(model: model)
        }
    }

    /// DeepSeek official USD list → CNY (cache-miss off-peak; peak ≈ ×2).
    private static func deepseekPricing(model: String) -> ModelPricing {
        let m = model.lowercased()
        if m.contains("pro") {
            return ModelPricing(
                inputPerMTok: 0.66 * cnyPerUSD,
                outputPerMTok: 1.98 * cnyPerUSD,
                displayModel: "deepseek-v4-pro",
                sourceNote: "DeepSeek 官网折算人民币 · 谷时·未命中缓存"
            )
        }
        return ModelPricing(
            inputPerMTok: 0.15 * cnyPerUSD,
            outputPerMTok: 0.60 * cnyPerUSD,
            displayModel: "deepseek-flash",
            sourceNote: "DeepSeek 官网折算人民币 · 谷时·未命中缓存"
        )
    }

    /// MiMo OpenRouter USD reference → CNY.
    private static func mimoPricing(model: String) -> ModelPricing {
        let m = model.lowercased()
        if m.contains("pro") {
            return ModelPricing(
                inputPerMTok: 0.435 * cnyPerUSD,
                outputPerMTok: 0.87 * cnyPerUSD,
                displayModel: "mimo-v2.5-pro",
                sourceNote: "MiMo 参考价折算人民币 · 以控制台为准"
            )
        }
        return ModelPricing(
            inputPerMTok: 0.14 * cnyPerUSD,
            outputPerMTok: 0.28 * cnyPerUSD,
            displayModel: "mimo-v2.5",
            sourceNote: "MiMo 参考价折算人民币 · 以控制台为准"
        )
    }

    /// Zhipu official CNY list prices.
    private static func glmPricing(model: String) -> ModelPricing {
        let m = model.lowercased()

        if m.contains("glm-4-flash") || m.contains("glm-4.7-flash") || m.contains("glm-z1-flash") {
            return ModelPricing(
                inputPerMTok: 0,
                outputPerMTok: 0,
                displayModel: model,
                sourceNote: "智谱官方 · 部分 Flash 免费"
            )
        }
        if m.contains("flashx") && m.contains("5.3") {
            return ModelPricing(
                inputPerMTok: 2,
                outputPerMTok: 7,
                displayModel: "glm-5.3-flashx",
                sourceNote: "智谱官方 API 定价"
            )
        }
        if m.contains("flash") {
            return ModelPricing(
                inputPerMTok: 0.8,
                outputPerMTok: 2.8,
                displayModel: "glm-5.3-flash",
                sourceNote: "智谱官方 API 定价"
            )
        }
        if m.contains("glm-5.1") {
            return ModelPricing(
                inputPerMTok: 6,
                outputPerMTok: 24,
                displayModel: "glm-5.1",
                sourceNote: "智谱官方 · 输入 <32K"
            )
        }
        return ModelPricing(
            inputPerMTok: 8,
            outputPerMTok: 28,
            displayModel: "glm-5.3",
            sourceNote: "智谱官方 API 定价"
        )
    }

    static func formatMoney(_ value: Double) -> String {
        if value <= 0 { return "¥0" }
        if value < 0.01 { return String(format: "¥%.4f", value) }
        if value < 1 { return String(format: "¥%.3f", value) }
        return String(format: "¥%.2f", value)
    }
}

struct CostAggregate {
    var cny: Double = 0
    var pricedCount: Int = 0
    var unpricedCount: Int = 0

    var isEmpty: Bool { cny <= 0 && pricedCount == 0 }

    var combinedLabel: String {
        if pricedCount == 0 && unpricedCount > 0 { return "—" }
        return PricingCatalog.formatMoney(cny)
    }
}

extension UsageStore {
    func cost(for list: [UsageRecord]) -> CostAggregate {
        var agg = CostAggregate()
        for rec in list {
            guard let pricing = PricingCatalog.pricing(provider: rec.provider, model: rec.model) else {
                agg.unpricedCount += 1
                continue
            }
            agg.cny += pricing.cost(inputTokens: rec.promptTokens, outputTokens: rec.completionTokens)
            agg.pricedCount += 1
        }
        return agg
    }

    func recordCost(_ rec: UsageRecord) -> String? {
        guard let pricing = PricingCatalog.pricing(provider: rec.provider, model: rec.model) else {
            return nil
        }
        return PricingCatalog.formatMoney(
            pricing.cost(inputTokens: rec.promptTokens, outputTokens: rec.completionTokens)
        )
    }
}
