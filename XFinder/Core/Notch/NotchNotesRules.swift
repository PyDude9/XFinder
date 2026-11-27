import Foundation

/// XF-ISLAND-NOTES — Pure Foundation rules for Dynamic Island Notes.
/// Kept free of AppKit/SwiftUI so `Tests/XFinderLogicTests` verifies filtering,
/// Vietnamese diacritic/case-insensitive search, pinned priority, long-text excerpts,
/// selection reconciliation after external archive/delete/edit, and keyboard navigation.
public struct NotchNoteSnapshot: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let title: String?
    public let content: String
    public let updatedAt: Date
    public let isPinned: Bool
    public let isArchived: Bool

    public init(
        id: UUID,
        title: String?,
        content: String,
        updatedAt: Date,
        isPinned: Bool,
        isArchived: Bool
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isArchived = isArchived
    }
}

public enum NotchNotesEmptyState: Equatable, Sendable {
    case hasResults
    case noActiveNotes
    case noSearchMatches
}

public enum NotchNotesRules {
    public static let defaultTitleLimit = 72
    public static let defaultExcerptLimit = 140

    /// Normalizes text for Vietnamese-aware case- and diacritic-insensitive matching.
    /// Foundation's `.diacriticInsensitive` does not decompose U+0110/U+0111 (`Đ`/`đ`),
    /// so we fold them explicitly to `d` before applying Foundation folding.
    public static func normalizedSearchText(_ raw: String) -> String {
        let vietnameseFolded = raw
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
        return vietnameseFolded
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "vi_VN"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns active (non-archived) notes matching `query`, sorted with pinned notes first
    /// and newest `updatedAt` first within each group (stable tie-break by UUID).
    public static func visibleNotes(
        from notes: [NotchNoteSnapshot],
        query: String
    ) -> [NotchNoteSnapshot] {
        let needle = normalizedSearchText(query)
        let tokens = needle.split(whereSeparator: \.isWhitespace).map(String.init)

        return notes
            .filter { note in
                guard !note.isArchived else { return false }
                guard !tokens.isEmpty else { return true }
                let titleFolded = normalizedSearchText(note.title ?? "")
                let contentFolded = normalizedSearchText(note.content)
                let haystack = titleFolded.isEmpty ? contentFolded : "\(titleFolded) \(contentFolded)"
                return tokens.allSatisfy { haystack.contains($0) }
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Classifies the current UI empty state so empty library vs no-match search show distinct messages.
    public static func emptyState(
        allNotes: [NotchNoteSnapshot],
        visibleNotes: [NotchNoteSnapshot],
        query: String
    ) -> NotchNotesEmptyState {
        if !visibleNotes.isEmpty { return .hasResults }
        let hasActive = allNotes.contains { !$0.isArchived }
        if !hasActive { return .noActiveNotes }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .noActiveNotes : .noSearchMatches
    }

    /// Reconciles the currently selected note ID when notes change (archive, delete, editor update, or filter change).
    /// Keeps `currentSelection` if it is still visible; otherwise selects the first visible note (or `nil` if empty).
    public static func reconciledSelection(
        currentSelection: UUID?,
        visibleNotes: [NotchNoteSnapshot]
    ) -> UUID? {
        guard !visibleNotes.isEmpty else { return nil }
        if let currentSelection, visibleNotes.contains(where: { $0.id == currentSelection }) {
            return currentSelection
        }
        return visibleNotes.first?.id
    }

    /// Moves keyboard selection by `delta` (+1 = down, -1 = up), clamping at list boundaries.
    /// If nothing is selected yet, down selects the first item and up selects the last item.
    public static func moveSelection(
        currentSelection: UUID?,
        delta: Int,
        visibleNotes: [NotchNoteSnapshot]
    ) -> UUID? {
        guard !visibleNotes.isEmpty else { return nil }
        guard delta != 0 else {
            return reconciledSelection(currentSelection: currentSelection, visibleNotes: visibleNotes)
        }
        guard let currentSelection,
              let currentIndex = visibleNotes.firstIndex(where: { $0.id == currentSelection }) else {
            return delta > 0 ? visibleNotes.first?.id : visibleNotes.last?.id
        }
        let target = max(0, min(visibleNotes.count - 1, currentIndex + delta))
        return visibleNotes[target].id
    }

    /// Extracts a single-line display title for a note, collapsing whitespace and truncating long text cleanly.
    /// Returns `nil` when both title and content are empty/whitespace (caller displays localized fallback).
    public static func displayTitle(
        for note: NotchNoteSnapshot,
        maxLength: Int = defaultTitleLimit
    ) -> String? {
        let explicit = collapseSingleLine(note.title ?? "")
        if !explicit.isEmpty {
            return truncated(explicit, limit: maxLength)
        }
        let firstLine = note.content
            .split(whereSeparator: \.isNewline)
            .map { collapseSingleLine(String($0)) }
            .first(where: { !$0.isEmpty }) ?? ""
        guard !firstLine.isEmpty else { return nil }
        return truncated(firstLine, limit: maxLength)
    }

    /// Extracts a compact single-line preview excerpt from the note body without repeating an implicit first-line title.
    public static func previewExcerpt(
        for note: NotchNoteSnapshot,
        maxLength: Int = defaultExcerptLimit
    ) -> String {
        let lines = note.content
            .split(whereSeparator: \.isNewline)
            .map { collapseSingleLine(String($0)) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        let hasExplicitTitle = !collapseSingleLine(note.title ?? "").isEmpty
        let bodyLines: ArraySlice<String> = hasExplicitTitle ? lines[...] : lines.dropFirst()
        let joined = bodyLines.joined(separator: " · ")
        guard !joined.isEmpty else { return "" }
        return truncated(joined, limit: maxLength)
    }

    // MARK: - Helpers

    private static func collapseSingleLine(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .joined(separator: " ")
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard limit > 1, text.count > limit else { return text }
        let prefix = text.prefix(limit - 1).trimmingCharacters(in: .whitespaces)
        return "\(prefix)…"
    }
}
