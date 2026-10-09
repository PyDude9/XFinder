import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The fully on-device tier, backed by Apple's Foundation Models framework.
///
/// This is the tier the brief called "Apple Intelligence (on-device)": free, offline, and
/// nothing leaves the machine. It is only present on macOS 26 and later, and only when the
/// user has turned Apple Intelligence on, so the whole type is guarded and reports *why* it
/// is unavailable rather than pretending.
///
/// A note on the framework's availability and the deployment target: the app builds against
/// the macOS 27 SDK but targets macOS 14. `FoundationModels` is auto-weak-linked in that
/// configuration (verified with `otool -L` — the load command is marked `weak`), so importing
/// it is safe: on an older system the symbols simply resolve to null and this tier reports
/// itself unavailable, instead of the app failing to launch.
///
/// What is *not* claimed here: `NSWritingToolsCoordinator` cannot be driven programmatically
/// to rewrite text destined for another application, so the system Writing Tools UI is not
/// the mechanism. Foundation Models is, because it is a plain generate-text API.
public final class AppleOnDeviceRefiner: TranscriptRefiner, @unchecked Sendable {
    public let id = "apple-on-device"

    public init() {}

    // MARK: - Reasons, as L10n keys
    //
    // Every reason is a Vietnamese literal that is also a key in `L10n.strings.json`, and the
    // call site resolves it with `L10n.t`. They are named constants rather than inline literals
    // so that `knownReasonKeys` can list them: a string handed to the UI through
    // `L10n.t(variable)` is invisible to the literal sweep, so the only way to guarantee none
    // of them silently renders Vietnamese in an English UI is to enumerate the vocabulary.
    static let reasonTooOldOS = "Máy này chạy macOS cũ hơn 26, chưa có Apple Intelligence."
    static let reasonRequiresMacOS26 = "macOS 26 trở lên mới có Apple Intelligence."
    static let reasonDeviceNotEligible = "Máy này không nằm trong danh sách hỗ trợ Apple Intelligence."
    static let reasonNotEnabled = "Apple Intelligence chưa được bật trong Cài đặt hệ thống."
    static let reasonModelNotReady = "Mô hình trên máy chưa tải xong. Thử lại sau ít phút."
    static let reasonUnavailable = "Apple Intelligence không khả dụng trên máy này."
    static let reasonNoSDK = "Bản SDK này không có FoundationModels."

    /// Every key this file can hand to the UI, in one list. `VoiceRefinerTests` resolves each
    /// against the shipped store, which is the gate the literal sweeps cannot provide.
    public static let knownReasonKeys: [String] = [
        reasonTooOldOS,
        reasonRequiresMacOS26,
        reasonDeviceNotEligible,
        reasonNotEnabled,
        reasonModelNotReady,
        reasonUnavailable,
        reasonNoSDK,
    ]

    /// Why the tier cannot be used, or `nil` when it can. Rendered (through `L10n`) on the
    /// settings page so the user knows whether to enable Apple Intelligence or to pick a
    /// different tier.
    public func unavailableReason() -> String? {
        guard #available(macOS 26.0, *) else {
            return Self.reasonTooOldOS
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return Self.reasonDeviceNotEligible
            case .appleIntelligenceNotEnabled:
                return Self.reasonNotEnabled
            case .modelNotReady:
                return Self.reasonModelNotReady
            @unknown default:
                return Self.reasonUnavailable
            }
        }
        #else
        return Self.reasonNoSDK
        #endif
    }

    public func isAvailable() async -> Bool {
        unavailableReason() == nil
    }

    public func refine(_ request: RefineRequest) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw RefinerError.unavailable(Self.reasonRequiresMacOS26)
        }
        #if canImport(FoundationModels)
        if let reason = unavailableReason() {
            throw RefinerError.unavailable(reason)
        }

        let system = request.messages.first(where: { $0.role == .system })?.content ?? ""
        let user = request.messages.filter { $0.role == .user }.map(\.content).joined(separator: "\n\n")

        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: system)
            let response = try await session.respond(to: user)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw RefinerError.badResponse }
            return text
        } catch let error as RefinerError {
            throw error
        } catch is CancellationError {
            throw RefinerError.cancelled
        } catch {
            throw RefinerError.transport(error.localizedDescription)
        }
        #else
        throw RefinerError.unavailable(Self.reasonNoSDK)
        #endif
    }
}
