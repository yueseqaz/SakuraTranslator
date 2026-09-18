import Foundation

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    /// Keep only the most recent N translations.
    static let maxCount = 10

    @Published private(set) var items: [TranslationHistoryItem] = []

    private let defaults = UserDefaults.standard
    private let key = "history.items.v1"

    private init() { load() }

    func append(
        source: String,
        result: String,
        provider: Provider,
        model: String,
        language: LanguageTarget
    ) {
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let res = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !src.isEmpty, !res.isEmpty else { return }

        // Skip exact duplicate consecutive entries
        if let first = items.first, first.source == src, first.result == res {
            return
        }

        let item = TranslationHistoryItem(
            id: UUID().uuidString,
            timestamp: Date(),
            source: String(src.prefix(2000)),
            result: String(res.prefix(4000)),
            providerRaw: provider.rawValue,
            model: model,
            languageRaw: language.rawValue
        )
        items.insert(item, at: 0)
        if items.count > Self.maxCount {
            items = Array(items.prefix(Self.maxCount))
        }
        persist()
    }

    func clearAll() {
        items = []
        defaults.removeObject(forKey: key)
        objectWillChange.send()
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([TranslationHistoryItem].self, from: data) else {
            items = []
            return
        }
        items = Array(list.prefix(Self.maxCount))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}
