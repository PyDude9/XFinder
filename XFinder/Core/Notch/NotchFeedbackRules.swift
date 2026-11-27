import Foundation
import Observation

/// Pure rules, validation, and ephemeral in-memory model for the Dynamic Island Feedback page.
///
/// Privacy & honesty contract:
/// - Draft stays strictly in memory (never written to disk or UserDefaults).
/// - Never automatically reads or attaches logs, diagnostics, system/machine info, or Clipboard.
/// - Opening the GitHub issues page passes ONLY the destination URL (zero query parameters,
///   never auto-submits, never encodes user draft into the URL).
/// - All external side effects (Clipboard copy, opening GitHub, opening XFinder Diagnostics)
///   flow through injectable callbacks so coordinator wires XFinder's existing flows and tests
///   stay 100% isolated.
enum NotchFeedbackRules {

    // MARK: - Constants

    /// Default XFinder repository slug (`owner/repo`), matching `DiagnosticsCenter.issuesRepo`.
    static let defaultIssuesRepo = "PyDude9/XFinder"

    /// Maximum grapheme clusters (`String.count`) allowed in a feedback draft.
    static let maxCharacters: Int = 1_500

    // MARK: - Types

    enum Category: String, CaseIterable, Identifiable, Equatable, Sendable {
        case bug
        case suggestion
        case other

        var id: String { rawValue }
    }

    enum ActionBlockReason: Equatable, Sendable {
        case emptyText
        case tooLong(count: Int, limit: Int)
    }

    enum Status: Equatable, Sendable {
        case idle
        case copied
        case copyFailed
        case openedIssues
        case openBrowserFailed
        case openedDiagnostics
        case openDiagnosticsFailed
    }

    // MARK: - Pure Helpers

    /// Destination-only URL for creating a new GitHub issue. Never carries query parameters,
    /// draft text, logs, or system metadata.
    static func issuesDestinationURL(repo: String = defaultIssuesRepo) -> URL {
        let trimmed = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeRepo = trimmed.isEmpty ? defaultIssuesRepo : trimmed
        return URL(string: "https://github.com/\(safeRepo)/issues/new")
            ?? URL(string: "https://github.com/PyDude9/XFinder/issues/new")!
    }

    /// Normalizes line endings and removes C0/C1 control characters (except `\n` and `\t`) while
    /// preserving Unicode grapheme clusters (Vietnamese diacritics, ZWJ emoji, CJK).
    static func normalizeDraft(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(unified.unicodeScalars.count)
        for scalar in unified.unicodeScalars {
            if scalar == "\n" || scalar == "\t" {
                scalars.append(scalar)
            } else if scalar.properties.generalCategory == .control {
                continue
            } else {
                scalars.append(scalar)
            }
        }

        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func copyBlockReason(
        draft: String,
        maxCharacters: Int = maxCharacters
    ) -> ActionBlockReason? {
        let normalized = normalizeDraft(draft)
        if normalized.isEmpty {
            return .emptyText
        }
        let count = normalized.count
        if count > maxCharacters {
            return .tooLong(count: count, limit: maxCharacters)
        }
        return nil
    }

    /// Builds the plain-text preview containing ONLY the chosen category label and user text.
    /// Never appends logs, diagnostics, or machine details.
    static func formatPreview(categoryLabel: String, draft: String) -> String {
        let normalized = normalizeDraft(draft)
        guard !normalized.isEmpty else { return "" }
        let cleanLabel = categoryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanLabel.isEmpty {
            return normalized
        }
        return "[\(cleanLabel)]\n\(normalized)"
    }
}

/// In-memory view model for Dynamic Island Feedback.
///
/// Coordinator wiring:
/// - `onCopyText`: writes the formatted preview string to `NSPasteboard.general` and returns `true`/`false`.
/// - `onOpenIssuesPage`: opens the destination-only GitHub issues URL via `NSWorkspace.shared.open(_:)`
///   and returns `true`/`false`.
/// - `onOpenDiagnostics`: navigates to XFinder's existing Diagnostics settings page and returns `true`/`false`.
/// - `handleTabDisabled()`: drops focus while preserving any in-progress draft in memory.
/// - `shutdown()`: clears ephemeral in-memory draft on app quit.
@MainActor
@Observable
final class NotchFeedbackModel {

    static let shared = NotchFeedbackModel()

    // MARK: - Coordinator Callbacks

    /// Copies the preview text to the user's clipboard on explicit click. Returns `true` on success.
    var onCopyText: ((String) -> Bool)?

    /// Opens the destination-only GitHub issues page in the user's browser. Returns `true` on success.
    var onOpenIssuesPage: ((URL) -> Bool)?

    /// Opens XFinder's existing Diagnostics view so the user can inspect reports themselves.
    var onOpenDiagnostics: (() -> Bool)?

    // MARK: - Observable State

    var category: NotchFeedbackRules.Category = .bug
    var draft: String = ""
    var isInputFocused: Bool = false
    private(set) var focusInputRequest: UInt64 = 0
    private(set) var status: NotchFeedbackRules.Status = .idle

    // MARK: - Configuration

    let maxCharacters: Int
    let issuesURL: URL

    init(
        maxCharacters: Int = NotchFeedbackRules.maxCharacters,
        issuesRepo: String = NotchFeedbackRules.defaultIssuesRepo
    ) {
        self.maxCharacters = max(1, maxCharacters)
        self.issuesURL = NotchFeedbackRules.issuesDestinationURL(repo: issuesRepo)
    }

    // MARK: - Computed Properties

    var normalizedDraft: String {
        NotchFeedbackRules.normalizeDraft(draft)
    }

    var characterCount: Int {
        normalizedDraft.count
    }

    var copyBlockReason: NotchFeedbackRules.ActionBlockReason? {
        NotchFeedbackRules.copyBlockReason(draft: draft, maxCharacters: maxCharacters)
    }

    var canCopy: Bool { copyBlockReason == nil }
    var isComposing: Bool { isInputFocused || !draft.isEmpty }

    // MARK: - User Actions

    func selectCategory(_ next: NotchFeedbackRules.Category) {
        guard next != category else { return }
        category = next
        if status == .copied || status == .copyFailed {
            status = .idle
        }
    }

    func updateDraft(_ next: String) {
        guard next != draft else { return }
        draft = next
        if status == .copied || status == .copyFailed {
            status = .idle
        }
    }

    func formattedPreview(categoryLabel: String) -> String {
        NotchFeedbackRules.formatPreview(categoryLabel: categoryLabel, draft: draft)
    }

    /// Copies the formatted preview via `onCopyText`. Preserves `draft` on both success and failure.
    @discardableResult
    func copyPreview(categoryLabel: String) -> Bool {
        guard copyBlockReason == nil else { return false }
        let text = formattedPreview(categoryLabel: categoryLabel)
        guard !text.isEmpty else { return false }
        let ok = onCopyText?(text) ?? false
        status = ok ? .copied : .copyFailed
        return ok
    }

    /// Opens the destination-only GitHub issues page via `onOpenIssuesPage`.
    /// Never clears `draft` so the user can still copy it even if the browser fails to open.
    @discardableResult
    func openIssuesPage() -> Bool {
        let ok = onOpenIssuesPage?(issuesURL) ?? false
        status = ok ? .openedIssues : .openBrowserFailed
        return ok
    }

    /// Opens XFinder's existing Diagnostics view via `onOpenDiagnostics`.
    @discardableResult
    func openDiagnostics() -> Bool {
        let ok = onOpenDiagnostics?() ?? false
        status = ok ? .openedDiagnostics : .openDiagnosticsFailed
        return ok
    }

    func requestInputFocus() {
        focusInputRequest &+= 1
    }

    // MARK: - Coordinator Lifecycle Hooks

    /// Called when the Feedback tab is turned OFF in Settings while the user may be typing.
    /// Drops keyboard focus cleanly while preserving the in-memory draft.
    func handleTabDisabled() {
        isInputFocused = false
    }

    /// Called on application termination; clears ephemeral in-memory draft.
    func shutdown() {
        isInputFocused = false
        draft = ""
        status = .idle
    }
}
