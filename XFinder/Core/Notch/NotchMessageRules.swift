import Foundation
import Observation

/// Pure rules, validation, and ephemeral state model for Dynamic Island local messages.
///
/// Privacy & lifecycle contract:
/// - Purely ephemeral in-memory state: messages do not survive app termination.
/// - Never reads the system Clipboard and never sends data over the network.
/// - Coordinator wires `onShowNotice` and `onDismissNotice` into `LiveActivity` so queued or
///   currently displayed notices are cancelled by their exact `UUID` on Stop, tab disable,
///   rapid replacement, or app shutdown.
enum NotchMessageRules {

    // MARK: - Limits & Presets

    /// Maximum grapheme clusters (`String.count`) allowed in a single Island message.
    static let maxCharacters: Int = 140

    /// Minimum and maximum display duration (seconds) for a local Island notice.
    static let minDurationSeconds: TimeInterval = 2
    static let maxDurationSeconds: TimeInterval = 60
    static let defaultDurationSeconds: TimeInterval = 5

    /// Quick duration presets offered in the page UI (seconds).
    static let durationPresets: [TimeInterval] = [3, 5, 10, 15, 30]

    // MARK: - Types

    enum PresentationMode: Equatable, Sendable {
        case animated
        case staticOnly
    }

    enum ShowBlockReason: Equatable, Sendable {
        case emptyText
        case tooLong(count: Int, limit: Int)
        case invalidDuration
    }

    /// Coordinator callback payload handed to `LiveActivity`.
    struct NoticePayload: Equatable, Identifiable, Sendable {
        let id: UUID
        let text: String
        let duration: TimeInterval
        let reduceMotion: Bool
        let createdAt: Date
    }

    // MARK: - Pure Validation & Normalization

    /// Collapses multiline/tab whitespace into single spaces and strips ASCII/Unicode control
    /// characters while preserving all valid Unicode grapheme clusters (Vietnamese, emoji, CJK).
    static func normalizeText(_ raw: String) -> String {
        let flattened = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        var cleanedScalars = String.UnicodeScalarView()
        cleanedScalars.reserveCapacity(flattened.unicodeScalars.count)
        for scalar in flattened.unicodeScalars {
            // Strip only Unicode General Category Cc (C0/C1 control characters), preserving Cf format
            // scalars such as U+200D (ZWJ) needed by multi-person emoji sequences.
            if scalar.properties.generalCategory == .control {
                continue
            }
            cleanedScalars.append(scalar)
        }

        return String(cleanedScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func isValidDuration(_ seconds: TimeInterval) -> Bool {
        seconds.isFinite && seconds >= minDurationSeconds && seconds <= maxDurationSeconds
    }

    static func clampedDuration(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return defaultDurationSeconds }
        return min(maxDurationSeconds, max(minDurationSeconds, seconds))
    }

    static func presentationMode(reduceMotion: Bool) -> PresentationMode {
        reduceMotion ? .staticOnly : .animated
    }

    /// Returns `nil` when `(draft, duration)` is valid to show, or the exact block reason.
    static func showBlockReason(
        draft: String,
        duration: TimeInterval,
        maxCharacters: Int = maxCharacters
    ) -> ShowBlockReason? {
        guard isValidDuration(duration) else {
            return .invalidDuration
        }

        let normalized = normalizeText(draft)
        if normalized.isEmpty {
            return .emptyText
        }

        let count = normalized.count
        if count > maxCharacters {
            return .tooLong(count: count, limit: maxCharacters)
        }

        return nil
    }

    /// Builds a validated `NoticePayload`, or returns `nil` if text or duration is invalid.
    static func makePayload(
        id: UUID = UUID(),
        draft: String,
        duration: TimeInterval,
        reduceMotion: Bool,
        now: Date = Date(),
        maxCharacters: Int = maxCharacters
    ) -> NoticePayload? {
        guard showBlockReason(draft: draft, duration: duration, maxCharacters: maxCharacters) == nil else {
            return nil
        }
        return NoticePayload(
            id: id,
            text: normalizeText(draft),
            duration: duration,
            reduceMotion: reduceMotion,
            createdAt: now
        )
    }
}

/// Ephemeral in-memory state model for Dynamic Island local messages.
///
/// Coordinator wiring:
/// - Set `onShowNotice` to push the payload onto `LiveActivity` tagged with `payload.id`.
/// - Set `onDismissNotice` to cancel any queued or currently displayed `LiveActivity` item with that `UUID`.
/// - Call `notifyDismissed(id:)` when `LiveActivity` finishes displaying or dismisses that notice.
/// - Call `handleTabDisabled()` when the Message tab is turned OFF in Settings.
/// - Call `shutdown()` on `applicationWillTerminate`.
@MainActor
@Observable
final class NotchMessageModel {

    static let shared = NotchMessageModel()

    // MARK: - Coordinator Callbacks

    /// Invoked when the user triggers "Show in Island" with a validated payload.
    var onShowNotice: ((NotchMessageRules.NoticePayload) -> Void)?

    /// Invoked to cancel a queued or currently displayed notice by its exact `UUID`.
    var onDismissNotice: ((UUID) -> Void)?

    // MARK: - Observable State

    var draft: String = ""
    var durationSeconds: TimeInterval = NotchMessageRules.defaultDurationSeconds
    var isInputFocused: Bool = false
    private(set) var focusInputRequest: UInt64 = 0
    private(set) var activeNotice: NotchMessageRules.NoticePayload?

    // MARK: - Computed Properties

    var normalizedPreviewText: String {
        NotchMessageRules.normalizeText(draft)
    }

    var previewCharacterCount: Int {
        normalizedPreviewText.count
    }

    var showBlockReason: NotchMessageRules.ShowBlockReason? {
        NotchMessageRules.showBlockReason(
            draft: draft,
            duration: durationSeconds,
            maxCharacters: maxCharacters
        )
    }

    var canShow: Bool { showBlockReason == nil }
    var isShowing: Bool { activeNotice != nil }
    var isComposing: Bool { isInputFocused || !draft.isEmpty }

    // MARK: - Configuration & Dependencies

    let maxCharacters: Int
    private let idProvider: () -> UUID
    private let nowProvider: () -> Date

    init(
        maxCharacters: Int = NotchMessageRules.maxCharacters,
        idProvider: @escaping () -> UUID = { UUID() },
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.maxCharacters = max(1, maxCharacters)
        self.idProvider = idProvider
        self.nowProvider = nowProvider
    }

    // MARK: - User Actions

    func selectDuration(_ seconds: TimeInterval) {
        guard NotchMessageRules.isValidDuration(seconds) else { return }
        durationSeconds = seconds
    }

    func requestInputFocus() {
        focusInputRequest &+= 1
    }

    /// Validates and dispatches the current draft to the coordinator's local notice slot.
    /// If a previous notice is still queued/displayed, cancels it by ID before showing the new one.
    @discardableResult
    func showInIsland(reduceMotion: Bool = false) -> NotchMessageRules.NoticePayload? {
        guard let payload = NotchMessageRules.makePayload(
            id: idProvider(),
            draft: draft,
            duration: durationSeconds,
            reduceMotion: reduceMotion,
            now: nowProvider(),
            maxCharacters: maxCharacters
        ) else {
            return nil
        }

        if let previous = activeNotice {
            activeNotice = nil
            onDismissNotice?(previous.id)
        }

        activeNotice = payload
        onShowNotice?(payload)
        return payload
    }

    /// Cancels the active/queued Island notice by its exact `UUID`.
    func stopActiveNotice() {
        guard let current = activeNotice else { return }
        activeNotice = nil
        onDismissNotice?(current.id)
    }

    // MARK: - Coordinator Lifecycle Hooks

    /// Called by coordinator when `LiveActivity` finishes or dismisses a notice.
    /// Ignores stale IDs so an earlier dismissed notice cannot clear a newer active notice.
    func notifyDismissed(id: UUID) {
        guard activeNotice?.id == id else { return }
        activeNotice = nil
    }

    /// Called by coordinator when the Message tab is turned OFF in Settings.
    func handleTabDisabled() {
        stopActiveNotice()
        isInputFocused = false
    }

    /// Called by coordinator on app termination; clears ephemeral draft and cancels active notice.
    func shutdown() {
        stopActiveNotice()
        draft = ""
        isInputFocused = false
    }
}
