import Foundation

/// A chat-style message handed to a language model.
public struct RefineMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case system, user }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// Everything a refiner needs to turn a transcription into inserted text.
public struct RefineRequest: Equatable, Sendable {
    public let text: String
    public let messages: [RefineMessage]
    /// Free-form context (frontmost app, window title, selection) already folded into the
    /// prompt by `RefinePrompt`; carried separately so a provider can log what it sent.
    public let contextSummary: String?

    public init(text: String, messages: [RefineMessage], contextSummary: String? = nil) {
        self.text = text
        self.messages = messages
        self.contextSummary = contextSummary
    }
}

public enum RefinerError: Error, Equatable, Sendable {
    case notConfigured
    case missingKey
    case unavailable(String)
    case http(Int, String)
    case badResponse
    case transport(String)
    case cancelled

    /// A sentence key for the UI. Vietnamese literal = L10n key, resolved by the view.
    ///
    /// Deliberately free of interpolation. A key built with a runtime value (`"Máy chủ trả lỗi \(code)"`)
    /// can never match a store entry, so `L10n.t` would silently fall back to Vietnamese while the
    /// build stayed green — the exact failure CLAUDE.md Part 0 §8 records. The status code is not
    /// lost: it is carried by `detail`, which the settings page shows on the line below.
    public var messageKey: String {
        switch self {
        case .notConfigured: return "Chưa chọn nhà cung cấp AI"
        case .missingKey: return "Chưa có khoá API"
        case .unavailable: return "Nhà cung cấp không sẵn sàng"
        case .http: return "Máy chủ trả lỗi"
        case .badResponse: return "Không đọc được câu trả lời"
        case .transport: return "Không kết nối được"
        case .cancelled: return "Đã hủy"
        }
    }

    /// Detail line for the settings page. The HTTP body is the provider's own text, which
    /// is the single most useful thing to show when a key is wrong — it says why.
    public var detail: String? {
        switch self {
        case .http(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "HTTP \(code)" }
            return "HTTP \(code): \(String(trimmed.prefix(300)))"
        case .unavailable(let why), .transport(let why):
            return why
        default:
            return nil
        }
    }
}

/// Which vendor an OpenAI-format-compatible endpoint belongs to.
///
/// Only three request *shapes* exist in the wild for the services we support: OpenAI's
/// `chat/completions`, Anthropic's `messages`, and Gemini's `generateContent`. Ollama has
/// its own `/api/chat`. Modelling the shape separately from the vendor is what keeps the
/// encoder honest — adding a vendor means picking a shape, not writing new JSON.
public enum APIRequestShape: String, Sendable {
    case openAICompatible
    case anthropic
    case gemini
}

public enum APIProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case openai
    case groq
    case anthropic
    case gemini
    case openrouter
    case deepseek
    case custom

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        case .deepseek: return "DeepSeek"
        case .custom: return "Địa chỉ riêng (OpenAI format)"
        }
    }

    public var shape: APIRequestShape {
        switch self {
        case .openai, .groq, .openrouter, .deepseek, .custom: return .openAICompatible
        case .anthropic: return .anthropic
        case .gemini: return .gemini
        }
    }

    /// Base URL without a trailing slash. The request builders append the path.
    public var defaultBaseURL: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .custom: return ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .anthropic: return "claude-3-5-haiku-latest"
        case .gemini: return "gemini-2.0-flash"
        case .openrouter: return "openai/gpt-4o-mini"
        case .deepseek: return "deepseek-chat"
        case .custom: return ""
        }
    }

    /// A short menu of known-good model names, so the user does not have to memorise them.
    /// The field stays free-text: these lists go stale faster than the app ships.
    public var suggestedModels: [String] {
        switch self {
        case .openai: return ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"]
        case .groq: return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "openai/gpt-oss-20b"]
        case .anthropic: return ["claude-3-5-haiku-latest", "claude-3-5-sonnet-latest", "claude-sonnet-4-5"]
        case .gemini: return ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"]
        case .openrouter: return ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "google/gemini-2.0-flash-001"]
        case .deepseek: return ["deepseek-chat", "deepseek-reasoner"]
        case .custom: return []
        }
    }

    /// Keychain account name for this provider's key. Never the key itself.
    public var keychainAccount: String { "voice.apikey.\(rawValue)" }

    /// Where the user goes to create a key. Shown as a link, never auto-opened.
    public var consoleURL: String {
        switch self {
        case .openai: return "https://platform.openai.com/api-keys"
        case .groq: return "https://console.groq.com/keys"
        case .anthropic: return "https://console.anthropic.com/settings/keys"
        case .gemini: return "https://aistudio.google.com/app/apikey"
        case .openrouter: return "https://openrouter.ai/keys"
        case .deepseek: return "https://platform.deepseek.com/api_keys"
        case .custom: return ""
        }
    }

    /// Gemini takes the key as a query parameter, so a "key" is still required — this
    /// exists so the UI can label the field correctly per provider.
    public var keyFieldLabelKey: String { "Khoá API" }
}

// MARK: - Request building (pure)

public enum RefinerRequestBuilder {

    /// Build a `URLRequest` for one provider. Pure: takes everything it needs, touches no
    /// global state, so the encoders can be asserted byte-for-byte in the test package.
    public static func request(
        kind: APIProviderKind,
        baseURL: String,
        model: String,
        apiKey: String,
        messages: [RefineMessage],
        timeout: TimeInterval = 30
    ) -> URLRequest? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseResolved = base.isEmpty ? kind.defaultBaseURL : base
        guard !baseResolved.isEmpty, !model.isEmpty else { return nil }

        var urlString: String
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: [String: Any]

        switch kind.shape {
        case .openAICompatible:
            urlString = baseResolved.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
            headers["Authorization"] = "Bearer \(apiKey)"
            body = [
                "model": model,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                "temperature": 0.2,
                "stream": false,
            ]

        case .anthropic:
            urlString = baseResolved.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1/messages"
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
            let system = messages.first(where: { $0.role == .system })?.content
            let userMessages = messages.filter { $0.role == .user }
            body = [
                "model": model,
                "max_tokens": 2048,
                "messages": userMessages.map { ["role": $0.role.rawValue, "content": $0.content] },
            ]
            if let system { body["system"] = system }

        case .gemini:
            // The model is part of the path and the key is a query parameter.
            let trimmed = baseResolved.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            urlString = "\(trimmed)/models/\(model):generateContent?key=\(apiKey)"
            let system = messages.first(where: { $0.role == .system })?.content
            let userText = messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")
            body = [
                "contents": [["parts": [["text": userText]]]],
            ]
            if let system { body["systemInstruction"] = ["parts": [["text": system]]] }
        }

        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }

    /// Ollama runs locally and needs no key. Its `/api/chat` shape is its own.
    public static func ollamaRequest(
        baseURL: String,
        model: String,
        messages: [RefineMessage],
        timeout: TimeInterval = 120
    ) -> URLRequest? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = base.isEmpty ? "http://localhost:11434" : base
        guard !model.isEmpty,
              let url = URL(string: resolved.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "stream": false,
            "options": ["temperature": 0.2],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        return request
    }
}

// MARK: - Response parsing (pure)

public enum RefinerResponseParser {

    /// Pull the assistant text out of a provider response.
    ///
    /// Returns `nil` rather than an empty string when the shape is not recognised, so a
    /// provider change surfaces as `.badResponse` instead of silently inserting nothing.
    public static func text(kind: APIProviderKind, from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        // A provider error delivered with HTTP 200 is still an error.
        if let error = root["error"] as? [String: Any], error["message"] is String {
            return nil
        }

        let text: String?
        switch kind.shape {
        case .openAICompatible:
            let choices = root["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            text = message?["content"] as? String

        case .anthropic:
            let content = root["content"] as? [[String: Any]]
            let parts = content?.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            text = parts?.joined()

        case .gemini:
            let candidates = root["candidates"] as? [[String: Any]]
            let parts = (candidates?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]
            let texts = parts?.compactMap { $0["text"] as? String }
            text = texts?.joined()
        }

        guard let resolved = text?.trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty else {
            return nil
        }
        return resolved
    }

    /// Ollama's `/api/chat` returns `{"message":{"content":"…"}}`.
    public static func ollamaText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `GET /api/tags` → `{"models":[{"name":"qwen2.5:7b"}]}`.
    public static func ollamaModelNames(from data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// The provider's own error text, for the settings page.
    public static func errorMessage(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any] {
            if let message = error["message"] as? String { return message }
            if let status = error["status"] as? String { return status }
        }
        if let error = root["error"] as? String { return error }
        if let message = root["message"] as? String { return message }
        return nil
    }
}
