import Foundation

/// Pure value representation of an XFinder Quicklink for filtering, URL validation, and testing without AppKit.
/// At runtime, `NotchLinksPage` maps directly from `Quicklinks.shared.links` (no separate store).
struct NotchLinkEntry: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let keyword: String
    let title: String
    let url: String

    init(id: UUID = UUID(), keyword: String, title: String, url: String) {
        self.id = id
        self.keyword = keyword
        self.title = title
        self.url = url
    }
}

/// Pure filtering, HTTP/HTTPS URL validation, open-result classification, and display rules
/// for the Dynamic Island Quicklinks page (`XF-ISLAND-LINKS`).
enum NotchLinksRules {

    enum OpenResult: Equatable, Sendable {
        case opened(URL)
        case invalidURL
        case launchFailed(URL)
    }

    enum DisplayState: Equatable, Sendable {
        /// The Quicklinks list itself has no items.
        case emptyCatalog
        /// Quicklinks exist, but none match the active filter query.
        case noMatches
        /// One or more Quicklinks to render.
        case results([NotchLinkEntry])
    }

    // MARK: - Text Normalization

    /// Lowercases, folds Vietnamese `đ`/`Đ` to `d`, strips diacritics, and collapses whitespace.
    static func normalize(_ raw: String) -> String {
        let lower = raw.lowercased()
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ð", with: "d")
        let folded = lower.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Strict HTTP/HTTPS URL Validation

    /// Returns a validated `URL` if and only if `raw` is a well-formed `http` or `https` URL with a non-empty host
    /// and no embedded whitespace or control characters. Rejects `javascript:`, `file:`, `data:`, `mailto:`, `xfinder:`,
    /// schemeless strings, and hostless URLs.
    static func validatedWebURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        guard trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }

        guard let components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        // Reject hosts made solely of dots (e.g. "https://." or "https://..")
        guard host.contains(where: { $0 != "." }) else { return nil }

        return components.url
    }

    // MARK: - Filtering & Display State

    /// Filters `links` by title, keyword, or URL using multi-token AND matching.
    /// Empty/whitespace queries return `links` in their original order.
    static func filter(_ links: [NotchLinkEntry], query: String) -> [NotchLinkEntry] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return links }
        let tokens = normalizedQuery.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return links }

        var scored: [(rank: Int, index: Int, entry: NotchLinkEntry)] = []
        for (index, entry) in links.enumerated() {
            let normKeyword = normalize(entry.keyword)
            let normTitle = normalize(entry.title)
            let normURL = normalize(entry.url)
            let rawLowerURL = entry.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let haystack = "\(normKeyword) \(normTitle) \(normURL) \(rawLowerURL)"
            let allTokensMatch = tokens.allSatisfy { token in
                haystack.contains(token)
            }
            guard allTokensMatch else { continue }

            let rank: Int
            if normKeyword == normalizedQuery {
                rank = 0
            } else if normKeyword.hasPrefix(normalizedQuery) {
                rank = 1
            } else if normTitle.hasPrefix(normalizedQuery) {
                rank = 2
            } else if normTitle.contains(normalizedQuery) || normKeyword.contains(normalizedQuery) {
                rank = 3
            } else {
                rank = 4
            }
            scored.append((rank, index, entry))
        }

        return scored
            .sorted { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.index < b.index
            }
            .map(\.entry)
    }

    /// Computes whether the page should render the empty-catalog state, no-matches state, or filtered rows.
    static func displayState(links: [NotchLinkEntry], query: String) -> DisplayState {
        guard !links.isEmpty else { return .emptyCatalog }
        let matched = filter(links, query: query)
        return matched.isEmpty ? .noMatches : .results(matched)
    }

    // MARK: - Display Formatting (Long Titles / URLs)

    /// Returns a trimmed display title, falling back to a compact URL string if the title is blank.
    static func displayTitle(_ rawTitle: String, fallbackURL: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return displayURL(fallbackURL)
    }

    /// Compact single-line display form of a URL (drops `http://`/`https://` prefix and lone trailing `/`).
    static func displayURL(_ rawURL: String) -> String {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var shown = trimmed
        if shown.lowercased().hasPrefix("https://") {
            shown = String(shown.dropFirst("https://".count))
        } else if shown.lowercased().hasPrefix("http://") {
            shown = String(shown.dropFirst("http://".count))
        }
        if shown.hasSuffix("/") && shown.count > 1 {
            shown.removeLast()
        }
        return shown
    }

    // MARK: - User Actions (Open & Copy)

    /// Validates that `entry.url` is HTTP/HTTPS before invoking `opener`.
    /// Never calls `opener` for invalid or non-HTTP(S) URLs.
    static func open(_ entry: NotchLinkEntry, using opener: (URL) -> Bool) -> OpenResult {
        guard let url = validatedWebURL(entry.url) else {
            return .invalidURL
        }
        return opener(url) ? .opened(url) : .launchFailed(url)
    }

    /// Copies the trimmed address string via `copier` (write-only; never reads the clipboard).
    static func copyAddress(_ entry: NotchLinkEntry, using copier: (String) -> Bool) -> Bool {
        let trimmed = entry.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return copier(trimmed)
    }
}
