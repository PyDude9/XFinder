import Foundation

/// OllamaCorrectionProvider is a stub for Phase 3 implementation.
/// Will query local Ollama http://localhost:11434/api/generate with qwen2.5:14b to correct grammar and spelling.
public final class OllamaCorrectionProvider: @unchecked Sendable {
    public let endpoint: URL

    public init(endpoint: URL = URL(string: "http://localhost:11434/api/generate")!) {
        self.endpoint = endpoint
    }

    public func isAvailable() async -> Bool {
        return false // Stub: Phase 3
    }

    public func correct(text: String, language: String) async -> String {
        return text // Passthrough for now
    }
}
