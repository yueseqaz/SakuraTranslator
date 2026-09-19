import Foundation

enum TranslationError: LocalizedError {
    case missingAPIKey(Provider)
    case invalidURL
    case httpError(Int, String)
    case emptyResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p):
            return "请先在设置中填写 \(p.displayName) 的 API Key"
        case .invalidURL:
            return "接口地址无效"
        case .httpError(let code, let message):
            if code == 401 { return "API Key 无效或已过期（401）" }
            if code == 429 { return "请求过于频繁，请稍后再试（429）" }
            let msg = message.isEmpty ? "" : "：\(message)"
            return "请求失败（\(code)）\(msg)"
        case .emptyResponse:
            return "模型没有返回内容"
        case .network(let msg):
            return "网络错误：\(msg)"
        }
    }
}

final class TranslationService {
    static let shared = TranslationService()
    private init() {}

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    func translate(
        text: String,
        language: LanguageTarget,
        tone: TranslationTone = .standard,
        provider: Provider,
        apiKey: String,
        model: String,
        baseURL: String,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> TranslationResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw TranslationError.missingAPIKey(provider)
        }

        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw TranslationError.emptyResponse
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = resolvedModel.isEmpty ? provider.defaultModel : resolvedModel
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = provider.defaultBaseURL }
        while base.hasSuffix("/") { base.removeLast() }

        let urlString = base + "/chat/completions"
        guard let url = URL(string: urlString) else {
            throw TranslationError.invalidURL
        }

        let systemPrompt = """
        You are a professional translation engine.
        \(language.instruction)
        Tone: \(tone.promptDirective)
        Rules:
        - Output ONLY the translation text.
        - Never add explanations, notes, or quotation marks unless they are part of the source.
        - Preserve code blocks, URLs, product names, and intentional formatting when appropriate.
        - Keep the tone natural and idiomatic in the target language.
        """

        let payload = ChatCompletionRequest(
            model: modelID,
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: cleaned)
            ],
            stream: true,
            temperature: 0.2,
            stream_options: StreamOptions(include_usage: true)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)

        var resultText = ""
        var usage: TokenUsage?

        do {
            (resultText, usage) = try await streamOnce(
                request: request,
                onDelta: onDelta
            )
        } catch let error as TranslationError {
            // Some gateways reject stream_options — retry once without it.
            if case .httpError(let code, let message) = error,
               code == 400,
               message.lowercased().contains("stream_options")
                || message.lowercased().contains("unknown")
                || message.lowercased().contains("unrecognized") {
                var fallback = URLRequest(url: url)
                fallback.httpMethod = "POST"
                fallback.setValue("application/json", forHTTPHeaderField: "Content-Type")
                fallback.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                fallback.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let fallbackPayload = ChatCompletionRequest(
                    model: modelID,
                    messages: [
                        ChatMessage(role: "system", content: systemPrompt),
                        ChatMessage(role: "user", content: cleaned)
                    ],
                    stream: true,
                    temperature: 0.2,
                    stream_options: nil
                )
                fallback.httpBody = try JSONEncoder().encode(fallbackPayload)
                (resultText, usage) = try await streamOnce(
                    request: fallback,
                    onDelta: onDelta
                )
            } else {
                throw error
            }
        }

        let result = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.emptyResponse }

        let finalUsage = usage ?? TokenEstimate.estimate(source: cleaned, result: result)
        return TranslationResult(text: result, usage: finalUsage)
    }

    private func streamOnce(
        request: URLRequest,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> (String, TokenUsage?) {
        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.network("无效响应")
        }

        if http.statusCode != 200 {
            var body = ""
            for try await line in bytes.lines {
                body += line
                if body.count > 800 { break }
            }
            let message = Self.extractErrorMessage(from: body) ?? String(body.prefix(400))
            throw TranslationError.httpError(http.statusCode, message)
        }

        var collected = ""
        var usage: TokenUsage?

        for try await line in bytes.lines {
            if let parsed = Self.parseSSELine(line) {
                if let piece = parsed.content {
                    collected += piece
                    onDelta(piece)
                }
                if let u = parsed.usage {
                    usage = u
                }
            }
        }

        return (collected, usage)
    }

    private struct SSEChunk {
        var content: String?
        var usage: TokenUsage?
    }

    private static func parseSSELine(_ raw: String) -> SSEChunk? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("data:") else { return nil }
        var payload = line.dropFirst("data:".count)
        if payload.hasPrefix(" ") { payload = payload.dropFirst() }
        let dataPart = String(payload)
        if dataPart == "[DONE]" { return nil }
        guard let data = dataPart.data(using: .utf8) else { return nil }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let err = obj["error"] as? [String: Any], err["message"] != nil {
            return nil
        }

        var chunk = SSEChunk()

        if let usageObj = obj["usage"] as? [String: Any], !usageObj.isEmpty {
            let prompt = intValue(usageObj["prompt_tokens"])
            let completion = intValue(usageObj["completion_tokens"])
            let total = intValue(usageObj["total_tokens"]) > 0
                ? intValue(usageObj["total_tokens"])
                : prompt + completion
            if total > 0 || prompt > 0 || completion > 0 {
                chunk.usage = TokenUsage(
                    promptTokens: prompt,
                    completionTokens: completion,
                    totalTokens: total
                )
            }
        }

        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first {
            if let delta = first["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                chunk.content = content
            } else if let message = first["message"] as? [String: Any],
                      let content = message["content"] as? String {
                chunk.content = content
            }
        }

        if chunk.content == nil && chunk.usage == nil {
            return nil
        }
        return chunk
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private static func extractErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let err = obj["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        if let msg = obj["message"] as? String {
            return msg
        }
        return nil
    }
}
