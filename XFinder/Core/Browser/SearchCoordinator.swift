import Foundation
import UniformTypeIdentifiers

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

    /// Per-source limit handed to each engine — generous enough that the merge step (which applies the caller's real
    /// `limit` after chip filtering) rarely starves a source, without pulling the whole machine through `mdfind`/FTS5
    /// on a broad query. Mirrors the 200-hit cap `BrowserWindowModel.startSearch` already uses for Spotlight alone.
    private static let perSourceLimit = 200

    /// `folders`: the scope's folders (empty = This Mac). `onUpdate` gets the whole merged list each time a source adds to
    /// it; `onFinish(truncated)` once all sources are done.
    @discardableResult
    func search(_ parsed: ParsedSearch, folders: [URL], limit: Int,
                onUpdate: @escaping @MainActor ([Result]) -> Void,
                onFinish: @escaping @MainActor (Bool) -> Void) -> Handle {
        let handle = Handle()
        let now = Date()
        let calendar = Calendar.current
        let roots = BrowserSettings.indexRoots
        let folderPaths = folders.map { $0.standardizedFileURL.path }

        // Q-T30-14: "This Mac" (no scope folders) with zero approved index roots stays Spotlight-only — FileOctopus
        // falls back to the current folder here, XFinder keeps whole-machine Spotlight because it already has it.
        let scopedRoots = Self.rootsInScope(roots, folders: folderPaths)
        let nameIndexRuns = !scopedRoots.isEmpty
        let hasWords = !parsed.terms.isEmpty || !parsed.phrases.isEmpty
        let contentRoots = scopedRoots.filter(\.contents)
        let contentIndexRuns = hasWords && !contentRoots.isEmpty

        var merged: [String: MergedHit] = [:]
        var order: [String] = []
        var finishedSources = 0
        // Every source that will actually run (Spotlight always runs) counts toward "all done"; a source skipped by
        // scope/query gating (no roots in scope, no words for content) never calls back, so it must not be waited on.
        let totalSources = 1 + (nameIndexRuns ? 1 : 0) + (contentIndexRuns ? 1 : 0)
        var anyTruncated = false

        func publish() {
            guard !handle.cancelled else { return }
            let results = order.compactMap { merged[$0]?.toResult() }
            onUpdate(results)
        }

        func finishOne(truncated: Bool) {
            guard !handle.cancelled else { return }
            anyTruncated = anyTruncated || truncated
            finishedSources += 1
            if finishedSources >= totalSources {
                onFinish(anyTruncated)
            }
        }

        func ingest(path: String, source: Source, tier: MatchTier?, snippet: String?) {
            guard !handle.cancelled else { return }
            if var existing = merged[path] {
                existing.sources.insert(source)
                if let tier, existing.tier == nil || tier < existing.tier! { existing.tier = tier }
                if let snippet, existing.snippet == nil { existing.snippet = snippet }
                merged[path] = existing
            } else {
                merged[path] = MergedHit(path: path, sources: [source], tier: tier, snippet: snippet)
                order.append(path)
            }
        }

        // MARK: Spotlight — always runs (also the whole fallback when there are no approved roots at all).
        let expression = SearchQuery.mdfindExpression(parsed, now: now, calendar: calendar)
        let spotlightLimit = Self.perSourceLimit
        Task { [weak self] in
            guard let self else { return }
            let found = await Task.detached(priority: .userInitiated) {
                FileSearchEngine.runMdfind(query: expression, scopes: folders, limit: spotlightLimit)
            }.value
            guard !handle.cancelled else { return }
            await MainActor.run {
                for item in found.items {
                    ingest(path: item.path, source: .spotlight, tier: nil, snippet: nil)
                }
                publish()
                finishOne(truncated: found.truncated)
            }
            _ = self
        }

        // MARK: Filename index — only roots inside the requested scope.
        if nameIndexRuns {
            let rootPaths = scopedRoots.map(\.path)
            let perSourceLimit = Self.perSourceLimit
            Task {
                let hits = await FilenameIndex.shared.search(Self.indexQueryText(parsed), within: rootPaths, limit: perSourceLimit)
                guard !handle.cancelled else { return }
                // `chipsAllow` calls `lstat` — kept off the main actor (rule 15: no main-thread disk I/O), same as
                // `BrowserWindowModel.entry(forPath:)` detaches its own `lstat` loop.
                let allowed = await Task.detached(priority: .userInitiated) {
                    hits.filter { Self.chipsAllow(parsed, path: $0.path, now: now, calendar: calendar) }
                }.value
                guard !handle.cancelled else { return }
                let truncated = hits.count >= perSourceLimit
                for hit in allowed {
                    ingest(path: hit.path, source: .name, tier: hit.tier, snippet: nil)
                }
                publish()
                finishOne(truncated: truncated)
            }
        }

        // MARK: Content index — only when the query has words and at least one in-scope root has Contents on.
        if contentIndexRuns {
            let rootPaths = contentRoots.map(\.path)
            let queryText = Self.indexQueryText(parsed)
            let perSourceLimit = Self.perSourceLimit
            Task {
                let hits = await ContentIndex.shared.search(queryText, within: rootPaths, limit: perSourceLimit)
                guard !handle.cancelled else { return }
                let allowed = await Task.detached(priority: .userInitiated) {
                    hits.filter { Self.chipsAllow(parsed, path: $0.path, now: now, calendar: calendar) }
                }.value
                guard !handle.cancelled else { return }
                let truncated = hits.count >= perSourceLimit
                for hit in allowed {
                    ingest(path: hit.path, source: .content, tier: nil, snippet: hit.snippet)
                }
                publish()
                finishOne(truncated: truncated)
            }
        }

        return handle
    }

    // MARK: - Merge

    private struct MergedHit {
        let path: String
        var sources: Set<Source>
        var tier: MatchTier?
        var snippet: String?
        func toResult() -> Result { Result(path: path, sources: sources, tier: tier, snippet: snippet) }
    }

    // MARK: - Scope

    /// Index roots that fall inside the requested scope folders. Empty `folders` is "This Mac": every approved root
    /// qualifies (Q-T30-14 handles the zero-roots case by simply not running this source at all). A non-empty
    /// `folders` list (`.folder` / `.panes`) only includes a root that is the scope folder itself or nested under it —
    /// a root covering a *larger* area than the scope is intentionally excluded here (a filename-index crawl of
    /// `~/Projects` should not be asked to answer a search scoped to `~/Projects/XFinder/Core` by restricting at
    /// query time only; it is still correct to just skip it and let Spotlight/the folder listing carry that scope).
    fileprivate static func rootsInScope(_ roots: [IndexRoot], folders: [String]) -> [IndexRoot] {
        let approved = roots.filter { !$0.paused }
        guard !folders.isEmpty else { return approved }
        return approved.filter { root in
            folders.contains { folder in
                root.path == folder || folder.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
                    || root.path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
            }
        }
    }

    /// The index engines match on filename text, not an `mdfind` predicate — only the free words/phrases/exclusions
    /// are meaningful to them (chips are metadata Spotlight understands natively but an index hit needs filtered in
    /// afterward, see `chipsAllow`). Matches `BrowserWindowModel.runSearch(parsed:...)`'s own reconstruction of a
    /// text query from chip-free terms.
    fileprivate static func indexQueryText(_ parsed: ParsedSearch) -> String {
        (parsed.terms + parsed.phrases).joined(separator: " ")
    }

    // MARK: - Chip post-filter for index hits (Spotlight already applied every chip as part of its predicate)

    /// Whether `path` still matches every chip in `parsed`, checked with `lstat` since a filename/content-index hit
    /// never went through `mdfind`. `kind`/`modified`/`created`/`size`/`ext:` are checkable this way (`in:` has no
    /// chip of its own yet — `SearchQuery.parseFieldValue` does not recognize the `in` field, so it cannot reach this
    /// function today; nothing to filter on until that lands). `tag:`/`from:`/`content:` chips need Spotlight
    /// metadata (user tags, quarantine where-from, full-text) that a bare `lstat` cannot read, and `SearchQuery`'s
    /// `mdfind`-clause builder for them is private to that file — those three chip kinds are deliberately left
    /// unfiltered here (an index hit that only matches on filename can surface under a `tag:`/`from:`/`content:` chip
    /// it does not actually satisfy; see deviations). `excluded` filename terms ARE checked since they are plain
    /// substring checks on the name, same information the index already matched on.
    /// `nonisolated`: called from `Task.detached` (rule 15, no main-thread `lstat`), touches no actor state.
    fileprivate nonisolated static func chipsAllow(_ parsed: ParsedSearch, path: String, now: Date, calendar: Calendar) -> Bool {
        let name = (path as NSString).lastPathComponent
        if !parsed.excluded.isEmpty {
            let folded = NameMatcher.fold(name)
            for word in parsed.excluded where !NameMatcher.fold(word).isEmpty {
                if containsSubsequenceAsSubstring(haystack: folded, needle: NameMatcher.fold(word)) { return false }
            }
        }
        let checkableFields: Set<SearchChip.Field> = [.kind, .modified, .created, .size, .ext]
        guard parsed.chips.contains(where: { checkableFields.contains($0.field) }) else { return true }
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let isDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        let size = Int64(st.st_size)
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
        let created = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec) + TimeInterval(st.st_birthtimespec.tv_nsec) / 1e9)
        let ext = (name as NSString).pathExtension

        for chip in parsed.chips {
            switch chip.value {
            case .kind(let kind):
                if !matchesKind(kind, ext: ext, isDirectory: isDirectory) { return false }
            case .date(let range):
                guard chip.field == .modified || chip.field == .created else { continue }
                let (start, end) = SearchQuery.interval(of: range, now: now, calendar: calendar)
                let date = chip.field == .created ? created : modified
                if let start, date < start { return false }
                if let end, date >= end { return false }
            case .size(let op, let bytes):
                guard !isDirectory else { return false }
                switch op {
                case .greater: if !(size > bytes) { return false }
                case .less: if !(size < bytes) { return false }
                case .greaterOrEqual: if !(size >= bytes) { return false }
                case .lessOrEqual: if !(size <= bytes) { return false }
                case .equal: if size != bytes { return false }
                }
            case .text(let value):
                guard chip.field == .ext else { continue } // tag: / from: / content: — see doc comment above.
                if ext.lowercased() != value.lowercased() { return false }
            }
        }
        return true
    }

    /// Same screenshot special-case as `SearchQuery.clause(for:)` (`kMDItemIsScreenCapture`, not just "is a PNG") is
    /// not reproducible from a bare `lstat` — a screenshot kind chip on an index-only hit is checked by extension
    /// only (`.png`), which is strictly broader than Spotlight's own clause; documented in deviations.
    private nonisolated static func matchesKind(_ kind: KindFilter, ext: String, isDirectory: Bool) -> Bool {
        if kind == .folders { return isDirectory }
        guard !isDirectory, !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        switch kind {
        case .pdfs: return type.conforms(to: .pdf)
        case .images, .screenshots: return type.conforms(to: .image)
        case .videos: return type.conforms(to: .movie)
        case .audio: return type.conforms(to: .audio)
        case .documents: return type.conforms(to: .content)
        case .spreadsheets: return type.conforms(to: .spreadsheet)
        case .presentations: return type.conforms(to: .presentation)
        case .archives: return type.conforms(to: .archive)
        case .applications: return type.conforms(to: .application)
        case .code: return type.conforms(to: .sourceCode)
        case .text: return type.conforms(to: .text)
        case .folders: return isDirectory
        }
    }

    /// `excluded` filename words use the same "every byte in order" substring rule the fuzzy tier allows elsewhere in
    /// this file's neighbourhood (`NameMatcher`); for an exclusion we only need a true substring, not fuzzy, so this
    /// is a plain byte-subsequence-as-contiguous-run check.
    private nonisolated static func containsSubsequenceAsSubstring(haystack: [UInt8], needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return needle.isEmpty }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<(start + needle.count)]) == needle { return true }
        }
        return false
    }
}
