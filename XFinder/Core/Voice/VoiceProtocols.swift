import Foundation

public enum SttError: Error, Equatable, Sendable {
    case permissionDenied
    case silentStream
    case noSpeech
    case modelNotReady
    case systemError(String)
}

public protocol SttProvider: Sendable {
    var id: String { get }
    func isAvailable() async -> Bool
    func warmup() async
    func start(
        language: String,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (SttError) -> Void
    ) async
    func stop() async -> String?
    func cancel()
}

public protocol TypingSinkProtocol: Sendable {
    func snapshot() -> String
    func applyPartial(_ text: String)
    func commit(_ text: String)
    func rollback()
}

/// Rewrites a finished transcription into the text that will be inserted.
///
/// Every tier in the settings page — on-device Apple Intelligence, a local Ollama daemon,
/// or a bring-your-own-key HTTP endpoint — conforms to this one protocol. The orchestrator
/// therefore never branches on *which* provider is configured; it branches on the mode, and
/// asks the provider for text. That is what keeps "the provider failed" a single code path
/// instead of one per vendor.
public protocol TranscriptRefiner: Sendable {
    /// Stable identifier, used in logs and in the "test connection" result.
    var id: String { get }
    /// Whether the provider is usable right now. On-device returns false when Apple
    /// Intelligence is switched off; HTTP providers return false without a key.
    func isAvailable() async -> Bool
    /// Rewrite. Throws `RefinerError` so the UI can say *why* rather than showing nothing.
    func refine(_ request: RefineRequest) async throws -> String
}
