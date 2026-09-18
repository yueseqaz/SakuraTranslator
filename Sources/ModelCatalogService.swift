import Foundation

enum ModelCatalogError: LocalizedError {
    case missingCredentials
    case missingBaseURL
    case invalidURL
    case httpError(Int, String)
    case emptyList
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "请先填写 API Key"
        case .missingBaseURL:
            return "请先填写 Base URL"
        case .invalidURL:
            return "Base URL 无效"
        case .httpError(let code, let message):
            if code == 401 { return "API Key 无效（401）" }
            if code == 404 { return "未找到 /models 接口（404）" }
            let msg = message.isEmpty ? "" : "：\(message)"
            return "拉取失败（\(code)）\(msg)"
        case .emptyList:
            return "接口未返回任何模型"
        case .parseFailed:
            return "无法解析模型列表，请手动填写模型 ID"
        }
    }
}

/// OpenAI-compatible `GET {base}/models`
final class ModelCatalogService {
    static let shared = ModelCatalogService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        return URLSession(configuration: config)
    }()

    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ModelCatalogError.missingCredentials }

        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { throw ModelCatalogError.missingBaseURL }
        guard URL(string: base) != nil else { throw ModelCatalogError.invalidURL }

        var lastError: Error = ModelCatalogError.invalidURL
        for urlString in Self.candidateEndpoints(base: base) {
            guard let url = URL(string: urlString) else { continue }
            do {
                let list = try await fetch(url: url, apiKey: key)
                if !list.isEmpty { return list }
                lastError = ModelCatalogError.emptyList
            } catch let error as ModelCatalogError {
                if case .httpError(let code, _) = error, code == 404 {
                    lastError = error
                    continue
                }
                // Auth / other hard errors: try next endpoint anyway, keep last error
                lastError = error
                continue
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    /// Try both `{base}/models` and `{base}/v1/models` depending on how base is written.
    private static func candidateEndpoints(base: String) -> [String] {
        var list: [String] = []
        list.append(base + "/models")
        if base.hasSuffix("/v1") {
            // already versioned — also try parent/models in case base included /v1 by mistake
            let parent = String(base.dropLast(3))
            if !parent.isEmpty {
                list.append(parent + "/models")
                list.append(parent + "/v1/models")
            }
        } else {
            list.append(base + "/v1/models")
        }
        return list
    }

    private func fetch(url: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelCatalogError.parseFailed
        }
        if http.statusCode != 200 {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw ModelCatalogError.httpError(http.statusCode, body)
        }
        return try Self.parseModelIDs(from: data)
    }

    private static func parseModelIDs(from data: Data) throws -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelCatalogError.parseFailed
        }

        var rawList: [[String: Any]] = []
        if let arr = obj["data"] as? [[String: Any]] {
            rawList = arr
        } else if let arr = obj["models"] as? [[String: Any]] {
            rawList = arr
        } else if let arr = obj["data"] as? [String] {
            return uniquePreserveOrder(arr.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        } else if let arr = obj["models"] as? [String] {
            return uniquePreserveOrder(arr.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        } else {
            throw ModelCatalogError.parseFailed
        }

        var ids: [String] = []
        for item in rawList {
            var id = ""
            if let s = item["id"] as? String { id = s }
            else if let s = item["name"] as? String { id = s }
            else if let s = item["model"] as? String { id = s }
            id = id.trimmingCharacters(in: .whitespaces)
            if !id.isEmpty { ids.append(id) }
        }
        return uniquePreserveOrder(ids)
    }

    private static func uniquePreserveOrder(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in list where !seen.contains(item) {
            seen.insert(item)
            out.append(item)
        }
        return out
    }
}
