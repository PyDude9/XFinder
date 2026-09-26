import Foundation

/// WhisperKitProvider is a stub for Phase 2 implementation.
/// Will leverage argmaxinc/WhisperKit with large-v3-turbo CoreML model resident in 36GB RAM.
public final class WhisperKitProvider: @unchecked Sendable, SttProvider {
    public let id: String = "whisper-kit"

    public init() {}

    public func isAvailable() async -> Bool {
        return false // Stub: Phase 2
    }

    public func warmup() async {}

    public func start(
        language: String,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (SttError) -> Void
    ) async {
        onError(.modelNotReady)
    }

    public func stop() async -> String? {
        return nil
    }

    public func cancel() {}
}
