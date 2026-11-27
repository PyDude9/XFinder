import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device `FoundationModels` adapter for Dynamic Island local chat.
///
/// Compatibility & weak-linkage contract:
/// - App deployment target is macOS 14.0 while building against the macOS 26+/27 SDK.
/// - `FoundationModels` is auto-weak-linked (`LC_LOAD_WEAK_DYLIB`); verify after Xcode build with:
///   `otool -L XFinder.app/Contents/MacOS/XFinder | grep FoundationModels`
///   (must show `(weak)` or `LC_LOAD_WEAK_DYLIB` via `otool -l`).
/// - Availability probing mirrors `AppleOnDeviceRefiner` with distinct reasons for OS version,
///   device eligibility, Apple Intelligence toggle, and model readiness.
/// - Creates its own isolated `LanguageModelSession` with zero external tools, zero network access,
///   and zero coupling to Voice or Clipboard.
@MainActor
final class FoundationModelsChatAdapter: LocalChatEngine {

    /// Stored type-erased so the class compiles cleanly under `MACOSX_DEPLOYMENT_TARGET = 14.0`.
    private var sessionStorage: AnyObject?

    init() {}

    func checkAvailability() -> NotchLocalChatRules.Availability {
        guard #available(macOS 26.0, *) else {
            return .unavailable(.unsupportedOS)
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.unknown)
            }
        }
        #else
        return .unavailable(.sdkUnavailable)
        #endif
    }

    func respond(to prompt: String, instructions: String) async throws -> String {
        guard #available(macOS 26.0, *) else {
            throw NotchLocalChatRules.ChatError.unavailable(.unsupportedOS)
        }
        #if canImport(FoundationModels)
        if let unavailable = checkAvailability().unavailableReason {
            throw NotchLocalChatRules.ChatError.unavailable(unavailable)
        }
        return try await respondMacOS26(to: prompt, instructions: instructions)
        #else
        throw NotchLocalChatRules.ChatError.unavailable(.sdkUnavailable)
        #endif
    }

    func resetSession() {
        sessionStorage = nil
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func respondMacOS26(to prompt: String, instructions: String) async throws -> String {
        let session: LanguageModelSession
        if let existing = sessionStorage as? LanguageModelSession {
            session = existing
        } else {
            let created = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: instructions
            )
            sessionStorage = created
            session = created
        }

        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw NotchLocalChatRules.ChatError.emptyResponse
            }
            return text
        } catch let error as NotchLocalChatRules.ChatError {
            throw error
        } catch is CancellationError {
            throw NotchLocalChatRules.ChatError.cancelled
        } catch let genError as LanguageModelSession.GenerationError {
            throw Self.mapGenerationError(genError)
        } catch {
            throw NotchLocalChatRules.ChatError.generationFailed(error.localizedDescription)
        }
    }

    @available(macOS 26.0, *)
    private static func mapGenerationError(
        _ error: LanguageModelSession.GenerationError
    ) -> NotchLocalChatRules.ChatError {
        switch error {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        case .guardrailViolation:
            return .guardrailViolation
        case .refusal:
            return .refusalMapped
        case .assetsUnavailable:
            return .assetsUnavailable
        case .concurrentRequests:
            return .concurrentRequest
        default:
            return .generationFailed(error.localizedDescription)
        }
    }
    #endif
}

private extension NotchLocalChatRules.ChatError {
    static var refusalMapped: NotchLocalChatRules.ChatError { .refused }
}
