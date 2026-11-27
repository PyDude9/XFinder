import Foundation
import Observation

/// Pure rules, validation, limits, and state model for the Dynamic Island on-device chat page.
///
/// Privacy & isolation contract:
/// - Offline on-device only; never uses network, external tools, Clipboard, or Voice settings.
/// - Conversation history stays strictly in memory for the current XFinder session and survives tab switches.
/// - Never invokes the language model until the user explicitly submits a prompt.
enum NotchLocalChatRules {

    // MARK: - Limits & Instructions

    /// Maximum character count allowed for a single user prompt.
    static let maxPromptCharacters: Int = 2_000

    /// Maximum combined character count retained in the in-memory conversation context.
    static let maxContextCharacters: Int = 12_000

    /// Maximum message count (user + assistant turns) in one conversation.
    static let maxMessages: Int = 40

    /// Default system instructions for the page's dedicated `LanguageModelSession`.
    static let defaultInstructions =
        "You are a concise, helpful on-device assistant inside XFinder. Answer directly and briefly."

    // MARK: - Domain Types

    enum UnavailableReason: Equatable, Sendable {
        case unsupportedOS
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case sdkUnavailable
        case unknown
    }

    enum Availability: Equatable, Sendable {
        case unchecked
        case available
        case unavailable(UnavailableReason)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }

        var unavailableReason: UnavailableReason? {
            if case .unavailable(let reason) = self { return reason }
            return nil
        }
    }

    enum SendBlockReason: Equatable, Sendable {
        case availabilityUnchecked
        case unavailable(UnavailableReason)
        case generating
        case emptyPrompt
        case promptTooLong(count: Int, limit: Int)
        case contextLimitReached
    }

    enum ChatError: Error, Equatable, Sendable {
        case unavailable(UnavailableReason)
        case refused
        case guardrailViolation
        case contextWindowExceeded
        case assetsUnavailable
        case concurrentRequest
        case emptyResponse
        case cancelled
        case generationFailed(String)
    }

    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    struct Message: Identifiable, Equatable, Sendable {
        let id: UUID
        let role: Role
        let text: String
        let createdAt: Date

        init(id: UUID = UUID(), role: Role, text: String, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.text = text
            self.createdAt = createdAt
        }
    }

    // MARK: - Pure Validation Helpers

    static func normalizePrompt(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func totalContextCharacters(messages: [Message]) -> Int {
        messages.reduce(0) { $0 + $1.text.count }
    }

    /// Evaluates whether a prompt can be sent right now, returning `nil` when allowed or the
    /// exact reason why sending is blocked.
    static func sendBlockReason(
        draft: String,
        availability: Availability,
        isGenerating: Bool,
        isContextWindowFull: Bool,
        messages: [Message],
        maxPromptCharacters: Int = maxPromptCharacters,
        maxContextCharacters: Int = maxContextCharacters,
        maxMessages: Int = maxMessages
    ) -> SendBlockReason? {
        switch availability {
        case .unchecked:
            return .availabilityUnchecked
        case .unavailable(let reason):
            return .unavailable(reason)
        case .available:
            break
        }

        if isGenerating {
            return .generating
        }

        if isContextWindowFull || messages.count >= maxMessages {
            return .contextLimitReached
        }

        let trimmed = normalizePrompt(draft)
        if trimmed.isEmpty {
            return .emptyPrompt
        }

        if trimmed.count > maxPromptCharacters {
            return .promptTooLong(count: trimmed.count, limit: maxPromptCharacters)
        }

        let projectedContext = totalContextCharacters(messages: messages) + trimmed.count
        if projectedContext > maxContextCharacters {
            return .contextLimitReached
        }

        return nil
    }
}

/// Engine abstraction so `NotchLocalChatModel` can be tested with a deterministic fake without
/// ever invoking `FoundationModels` on the owner's desktop.
@MainActor
protocol LocalChatEngine: AnyObject {
    func checkAvailability() -> NotchLocalChatRules.Availability
    func respond(to prompt: String, instructions: String) async throws -> String
    func resetSession()
}

/// Session-scoped in-memory view model for Dynamic Island on-device chat.
///
/// Lifecycle guarantees:
/// - Does NOT check availability or create a `LanguageModelSession` in `init()`.
/// - `checkAvailability()` / `retryAvailability()` only inspect availability; they never invoke the model.
/// - `messages` remain in memory across tab switches; `resetConversation()` wipes history and resets the session.
/// - Every request is tagged with `(sessionEpoch, requestID)` so late responses/errors after Stop,
///   New Conversation, tab disable, or shutdown are strictly discarded.
@MainActor
@Observable
final class NotchLocalChatModel {

    static let shared = NotchLocalChatModel(engine: FoundationModelsChatAdapter())

    // MARK: - Configuration

    let maxPromptCharacters: Int
    let maxContextCharacters: Int
    let maxMessages: Int
    let instructions: String

    // MARK: - Observable State

    var draft: String = ""
    var isInputFocused: Bool = false
    private(set) var focusInputRequest: UInt64 = 0

    private(set) var availability: NotchLocalChatRules.Availability = .unchecked
    private(set) var messages: [NotchLocalChatRules.Message] = []
    private(set) var isGenerating: Bool = false
    private(set) var isContextWindowFull: Bool = false
    private(set) var lastError: NotchLocalChatRules.ChatError?

    var contextCharacters: Int {
        NotchLocalChatRules.totalContextCharacters(messages: messages)
    }

    var trimmedDraftLength: Int {
        NotchLocalChatRules.normalizePrompt(draft).count
    }

    var sendBlockReason: NotchLocalChatRules.SendBlockReason? {
        NotchLocalChatRules.sendBlockReason(
            draft: draft,
            availability: availability,
            isGenerating: isGenerating,
            isContextWindowFull: isContextWindowFull,
            messages: messages,
            maxPromptCharacters: maxPromptCharacters,
            maxContextCharacters: maxContextCharacters,
            maxMessages: maxMessages
        )
    }

    var canSend: Bool { sendBlockReason == nil }
    var hasConversation: Bool { !messages.isEmpty }
    var isComposing: Bool { isInputFocused || !draft.isEmpty }

    // MARK: - Internal State

    private let engine: LocalChatEngine
    private let nowProvider: () -> Date
    private var activeTask: Task<Void, Never>?
    private var sessionEpoch: UInt64 = 0
    private var requestCounter: UInt64 = 0

    // MARK: - Init

    init(
        engine: LocalChatEngine,
        maxPromptCharacters: Int = NotchLocalChatRules.maxPromptCharacters,
        maxContextCharacters: Int = NotchLocalChatRules.maxContextCharacters,
        maxMessages: Int = NotchLocalChatRules.maxMessages,
        instructions: String = NotchLocalChatRules.defaultInstructions,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.engine = engine
        self.maxPromptCharacters = max(1, maxPromptCharacters)
        self.maxContextCharacters = max(1, maxContextCharacters)
        self.maxMessages = max(2, maxMessages)
        self.instructions = instructions
        self.nowProvider = nowProvider
    }

    // MARK: - Availability & Focus

    /// Inspects on-device FoundationModels availability without invoking any model generation.
    /// Safe to call on page appear and on explicit retry.
    func checkAvailability() {
        let result = engine.checkAvailability()
        availability = result
        if result.isAvailable {
            if case .unavailable = lastError {
                lastError = nil
            }
        }
    }

    /// Explicit retry button action for unavailable states.
    func retryAvailability() {
        lastError = nil
        checkAvailability()
    }

    func requestInputFocus() {
        focusInputRequest &+= 1
    }

    // MARK: - Send, Stop, Reset

    /// Sends the current `draft` if valid. Rejects rapid/concurrent sends, empty prompts,
    /// over-limit prompts, full context, and unavailable states.
    @discardableResult
    func sendPrompt() -> Bool {
        if case .unchecked = availability {
            checkAvailability()
        }
        guard sendBlockReason == nil else { return false }

        let prompt = NotchLocalChatRules.normalizePrompt(draft)
        draft = ""
        lastError = nil

        let userMessage = NotchLocalChatRules.Message(
            role: .user,
            text: prompt,
            createdAt: nowProvider()
        )
        messages.append(userMessage)
        isGenerating = true

        requestCounter &+= 1
        let capturedEpoch = sessionEpoch
        let capturedRequest = requestCounter
        let capturedInstructions = instructions

        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let rawReply = try await self.engine.respond(to: prompt, instructions: capturedInstructions)
                guard self.sessionEpoch == capturedEpoch,
                      self.requestCounter == capturedRequest,
                      !Task.isCancelled else {
                    return
                }
                let trimmedReply = rawReply.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isGenerating = false
                self.activeTask = nil
                if trimmedReply.isEmpty {
                    self.lastError = .emptyResponse
                } else {
                    self.messages.append(
                        NotchLocalChatRules.Message(
                            role: .assistant,
                            text: trimmedReply,
                            createdAt: self.nowProvider()
                        )
                    )
                }
            } catch let chatError as NotchLocalChatRules.ChatError {
                guard self.sessionEpoch == capturedEpoch,
                      self.requestCounter == capturedRequest else {
                    return
                }
                self.isGenerating = false
                self.activeTask = nil
                self.handleError(chatError)
            } catch is CancellationError {
                guard self.sessionEpoch == capturedEpoch,
                      self.requestCounter == capturedRequest else {
                    return
                }
                self.isGenerating = false
                self.activeTask = nil
            } catch {
                guard self.sessionEpoch == capturedEpoch,
                      self.requestCounter == capturedRequest else {
                    return
                }
                self.isGenerating = false
                self.activeTask = nil
                self.lastError = .generationFailed(error.localizedDescription)
            }
        }

        return true
    }

    /// Cancels an in-flight generation immediately and ignores any late reply from it.
    func stopGeneration() {
        guard isGenerating || activeTask != nil else { return }
        requestCounter &+= 1
        activeTask?.cancel()
        activeTask = nil
        isGenerating = false
    }

    /// Starts a brand-new conversation: cancels in-flight generation, bumps epoch so late replies
    /// cannot bleed into the fresh session, wipes in-memory messages, and resets the adapter session.
    func resetConversation() {
        sessionEpoch &+= 1
        requestCounter &+= 1
        activeTask?.cancel()
        activeTask = nil
        isGenerating = false
        isContextWindowFull = false
        lastError = nil
        messages.removeAll()
        engine.resetSession()
    }

    // MARK: - Coordinator Lifecycle Hooks

    /// Called by the coordinator when the Local Chat tab is toggled OFF in Settings.
    /// Cancels any active generation and drops late replies without touching other app state.
    func handleTabDisabled() {
        stopGeneration()
        isInputFocused = false
    }

    /// Called by the coordinator on application termination.
    func shutdown() {
        sessionEpoch &+= 1
        requestCounter &+= 1
        activeTask?.cancel()
        activeTask = nil
        isGenerating = false
        isInputFocused = false
        engine.resetSession()
    }

    // MARK: - Error Handling

    private func handleError(_ error: NotchLocalChatRules.ChatError) {
        switch error {
        case .cancelled:
            break
        case .contextWindowExceeded:
            isContextWindowFull = true
            lastError = .contextWindowExceeded
        case .unavailable(let reason):
            availability = .unavailable(reason)
            lastError = .unavailable(reason)
        case .assetsUnavailable:
            availability = .unavailable(.modelNotReady)
            lastError = .assetsUnavailable
        case .refused, .guardrailViolation, .concurrentRequest, .emptyResponse, .generationFailed:
            lastError = error
        }
    }
}
