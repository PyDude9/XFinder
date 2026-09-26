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
