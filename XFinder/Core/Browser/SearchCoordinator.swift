import Foundation

/// XF-T30 W5a — one search, three sources (filename index, Spotlight, content index) merged by path, streamed back as
/// they arrive (FileOctopus "Filename, path and fuzzy search, and Spotlight results"). Contract
/// docs/specs/XF-T30-w5a-contract.md §3. W5a builder (S5): implement.
@MainActor
final class SearchCoordinator {
    static let shared = SearchCoordinator()

    enum Source: String, Sendable { case name, spotlight, content }

    struct Result: Equatable, Sendable {
        let path: String
        let sources: Set<Source>
        let tier: MatchTier?
        let snippet: String?
    }

    final class Handle {
        fileprivate(set) var cancelled = false
        func cancel() { cancelled = true }
    }

    /// `folders`: the scope's folders (empty = This Mac). `onUpdate` gets the whole merged list each time a source adds to
    /// it; `onFinish(truncated)` once all sources are done.
    @discardableResult
    func search(_ parsed: ParsedSearch, folders: [URL], limit: Int,
                onUpdate: @escaping @MainActor ([Result]) -> Void,
                onFinish: @escaping @MainActor (Bool) -> Void) -> Handle {
        let h = Handle()
        onFinish(false)
        return h
    }
}
