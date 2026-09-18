import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    static let shared = UsageStore()

    @Published private(set) var records: [UsageRecord] = []

    private let defaults = UserDefaults.standard
    private let key = "usage.records.v1"
    private let maxRecords = 500

    private init() {
        load()
    }

    func record(
        provider: Provider,
        model: String,
        usage: TokenUsage
    ) {
        guard !usage.isEmpty else { return }
        let item = UsageRecord(
            id: UUID().uuidString,
            timestamp: Date(),
            providerRaw: provider.rawValue,
            model: model,
            promptTokens: max(0, usage.promptTokens),
            completionTokens: max(0, usage.completionTokens),
            totalTokens: max(0, usage.totalTokens)
        )
        records.insert(item, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        persist()
        objectWillChange.send()
    }

    func clearAll() {
        records = []
        defaults.removeObject(forKey: key)
        objectWillChange.send()
    }

    // MARK: - Aggregates

    private var calendar: Calendar { .current }

    private func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    var todayRecords: [UsageRecord] {
        let today = startOfDay(Date())
        return records.filter { $0.timestamp >= today }
    }

    var last30DaysRecords: [UsageRecord] {
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return records.filter { $0.timestamp >= cutoff }
    }

    func totals(_ list: [UsageRecord]) -> (prompt: Int, completion: Int, total: Int, count: Int) {
        var p = 0, c = 0, t = 0
        for r in list {
            p += r.promptTokens
            c += r.completionTokens
            t += r.totalTokens
        }
        return (p, c, t, list.count)
    }

    struct ProviderBucket: Identifiable {
        let id: String
        let provider: Provider
        let prompt: Int
        let completion: Int
        let total: Int
        let count: Int
        let costLabel: String?
        let pricingNote: String?
    }

    var providerBuckets: [ProviderBucket] {
        let list = last30DaysRecords
        var map: [String: (p: Int, c: Int, t: Int, n: Int, model: String)] = [:]
        for r in list {
            var v = map[r.providerRaw] ?? (0, 0, 0, 0, r.model)
            v.p += r.promptTokens
            v.c += r.completionTokens
            v.t += r.totalTokens
            v.n += 1
            // keep latest model name for pricing hint
            v.model = r.model
            map[r.providerRaw] = v
        }
        return Provider.allCases.compactMap { p in
            guard let v = map[p.rawValue], v.t > 0 || v.n > 0 else { return nil }
            let pricing = PricingCatalog.pricing(provider: p, model: v.model)
            let costLabel: String?
            let note: String?
            if let pricing {
                let cost = pricing.cost(inputTokens: v.p, outputTokens: v.c)
                costLabel = PricingCatalog.formatMoney(cost)
                note = pricing.sourceNote
            } else if p.isCustom {
                costLabel = nil
                note = "自定义引擎不计成本"
            } else {
                costLabel = nil
                note = "无定价档"
            }
            return ProviderBucket(
                id: p.rawValue,
                provider: p,
                prompt: v.p,
                completion: v.c,
                total: v.t,
                count: v.n,
                costLabel: costLabel,
                pricingNote: note
            )
        }
        .sorted { $0.total > $1.total }
    }

    var recentRecords: [UsageRecord] {
        Array(records.prefix(24))
    }

    // MARK: - Helpers

    static func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.2fM", Double(n) / 1_000_000)
        }
        if n >= 10_000 {
            return String(format: "%.1fK", Double(n) / 1_000)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else {
            records = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let list = try? decoder.decode([UsageRecord].self, from: data) {
            records = list
        } else {
            records = []
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(records) {
            defaults.set(data, forKey: key)
        }
    }
}

enum TokenEstimate {
    /// Rough fallback when the provider does not return usage on the stream.
    static func estimate(source: String, result: String) -> TokenUsage {
        func tokens(of s: String) -> Int {
            guard !s.isEmpty else { return 0 }
            var cjk = 0
            var other = 0
            for ch in s.unicodeScalars {
                if (0x4E00...0x9FFF).contains(ch.value)
                    || (0x3040...0x30FF).contains(ch.value)
                    || (0xAC00...0xD7AF).contains(ch.value) {
                    cjk += 1
                } else if !ch.properties.isWhitespace {
                    other += 1
                }
            }
            // CJK ≈ 1 token/char; Latin ≈ 4 chars/token; system prompt overhead ~80
            return cjk + Int(ceil(Double(other) / 4.0))
        }
        let prompt = tokens(of: source) + 80
        let completion = tokens(of: result)
        return TokenUsage(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: prompt + completion
        )
    }
}
