import Foundation

/// XF-T28 (2026-10-24) — pure path arithmetic behind the file browser's breadcrumb bar and its "type a path" field
/// (symlinked into the test package). No I/O: `segments`/`collapse` turn a path string into display pieces, and
/// `resolve`/`completions` turn what the user typed into a normalized path or a list of Tab candidates. The caller
/// (an AppKit-facing controller) owns the actual directory listing and `stat` calls.
///
/// Volumes: a path under "/Volumes/X" starts its breadcrumb at "X" (whose own path is "/Volumes/X") — the user never
/// sees "/" or "Volumes" as clickable segments of another disk's path, matching Finder.
enum BrowserPath {

    struct Segment: Equatable, Sendable {
        let name: String
        let path: String
    }

    /// One slot of a collapsed breadcrumb: either a visible segment at `segments[index]`, or an ellipsis standing in
    /// for the segments at the hidden indices (kept in order so a menu can list them).
    enum Display: Equatable, Sendable {
        case segment(Int)
        case ellipsis(hidden: [Int])
    }

    /// Splits `path` into the chain of (name, path-to-here) the breadcrumb bar shows, root first.
    static func segments(of path: String, rootName: String) -> [Segment] {
        let normalized = normalize(path, base: "/")
        if normalized == "/" {
            return [Segment(name: rootName, path: "/")]
        }
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2, parts[0] == "Volumes" {
            var result = [Segment(name: parts[1], path: "/Volumes/\(parts[1])")]
            var runningPath = "/Volumes/\(parts[1])"
            for part in parts.dropFirst(2) {
                runningPath += "/\(part)"
                result.append(Segment(name: part, path: runningPath))
            }
            return result
        }
        var result = [Segment(name: rootName, path: "/")]
        var runningPath = ""
        for part in parts {
            runningPath += "/\(part)"
            result.append(Segment(name: part, path: runningPath))
        }
        return result
    }

    /// Reduces `count` segment indices (0..<count) to what fits in `maxVisible` slots: the first segment, the last
    /// (maxVisible - 2), and one ellipsis in between standing for everything else. No collapsing needed ⇒ every
    /// index comes back as its own `.segment`.
    static func collapse(count: Int, maxVisible: Int) -> [Display] {
        guard count > 0 else { return [] }
        let visible = max(maxVisible, 3)
        guard count > visible else { return (0..<count).map { .segment($0) } }
        let tailCount = visible - 2
        let tailStart = count - tailCount
        let hidden = Array(1..<tailStart)
        var result: [Display] = [.segment(0), .ellipsis(hidden: hidden)]
        result.append(contentsOf: (tailStart..<count).map { .segment($0) })
        return result
    }

    /// Resolves what the user typed in the path field into an absolute, normalized path: "~" and "~/x" are relative
    /// to `home`, anything else not starting with "/" is relative to `current`, and "." / ".." / "//" are collapsed.
    /// The result never ends in "/" unless it IS the root. An empty field means "stay here".
    static func resolve(typed: String, current: String, home: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return normalize(current, base: "/") }
        if trimmed == "~" {
            return normalize(home, base: "/")
        }
        if trimmed.hasPrefix("~/") {
            return normalize(home + "/" + trimmed.dropFirst(2), base: "/")
        }
        if trimmed.hasPrefix("/") {
            return normalize(trimmed, base: "/")
        }
        return normalize(current + "/" + trimmed, base: "/")
    }

    /// Collapses a possibly-relative path against `base` (itself assumed already absolute), resolving "." and "..",
    /// squashing repeated "/", and dropping a trailing "/" (unless the result is the root).
    private static func normalize(_ path: String, base: String) -> String {
        let full = path.hasPrefix("/") ? path : base + "/" + path
        var stack: [String] = []
        for part in full.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." {
                continue
            } else if part == ".." {
                if !stack.isEmpty { stack.removeLast() }
            } else {
                stack.append(String(part))
            }
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }

    /// Tab-completion candidates for the path field: the children of the typed path's parent whose name starts with
    /// its last component, case- and diacritic-insensitively, in natural (Finder-like) order.
    static func completions(typed: String, children: [String]) -> [String] {
        let lastSlash = typed.lastIndex(of: "/")
        let prefix = lastSlash.map { String(typed[typed.index(after: $0)...]) } ?? typed
        guard !prefix.isEmpty else {
            return children.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        let foldedPrefix = fold(prefix)
        return children
            .filter { fold($0).hasPrefix(foldedPrefix) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Longest prefix shared by every name, matched case-insensitively but returned with the casing of `names[0]`.
    ///
    /// Folds one `Character` at a time (not the whole string) before comparing: folding a full string can change its
    /// length (German "ß" → "ss", the "ﬀ" ligature → "ff"), which would desync a shared `length` index between the
    /// original and folded arrays and let the loop silently "match" past where the names actually diverge (measured
    /// 2026-10-24: `commonPrefix(["straße", "strasse"])` returned the whole first word instead of stopping at "stra").
    static func commonPrefix(_ names: [String]) -> String {
        guard let first = names.first, !first.isEmpty else { return "" }
        guard names.count > 1 else { return first }
        let firstChars = Array(first)
        let others = names.dropFirst().map { Array($0) }
        var length = 0
        outer: while length < firstChars.count {
            let c = fold(String(firstChars[length]))
            for other in others {
                guard length < other.count, fold(String(other[length])) == c else { break outer }
            }
            length += 1
        }
        return String(firstChars.prefix(length))
    }

    /// Case- and diacritic-insensitive fold used for prefix matching, consistent with the rest of the browser's text
    /// matching (see `EntryRules.foldKey`).
    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
