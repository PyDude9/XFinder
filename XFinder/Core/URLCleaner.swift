import Foundation

/// Strips tracking parameters from a single copied link.
///
/// The job: "I copied a link; I do not want to paste `?utm_source=…&fbclid=…` into a chat."
/// Pure Foundation so the rules are pinned by tests rather than trusted.
///
/// Deliberately conservative, because the cost of a wrong rewrite is a broken link:
///
/// * Acts only when the **whole** copy is one `http(s)` link — a sentence that merely contains a
///   URL is never touched, and neither is a URL with surrounding prose.
/// * Removes only parameters on a short, named list. Nothing is guessed from a name that "looks
///   like tracking". Ambiguous names are **host-scoped**: `t=` is a timestamp on YouTube but a
///   tracking token on X, `si=` is a share id on YouTube/Spotify but may be a real field
///   elsewhere. A global `t` rule would break `youtu.be/…?t=90`.
/// * Leaves everything it does not remove byte-for-byte: other parameters keep their order and
///   percent-encoding, the fragment is untouched (`#/route?utm_x` is client-side routing, not a
///   query), and when nothing is removed it returns `nil` so the caller never rewrites.
enum URLCleaner {

    struct Result: Equatable {
        /// The link with tracking parameters removed.
        let cleaned: String
        /// Parameter names removed, in the order they appeared (decoded, lower-cased).
        let removed: [String]
        /// Lower-cased host, for the "last cleaned" status line.
        let host: String
    }

    // MARK: - Rules

    /// Names that are tracking on every site.
    static let globalNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "twclid", "ttclid", "mc_eid", "mc_cid", "igshid", "igsh", "_hsenc", "_hsmi",
        "mkt_tok", "vero_id", "oly_enc_id", "oly_anon_id", "ck_subscriber_id", "_openstat",
    ]

    /// Name prefixes that are tracking on every site (`utm_source`, Matomo `pk_campaign`, …).
    static let globalPrefixes: [String] = ["utm_", "pk_", "mtm_", "hsa_"]

    /// Names that are tracking only on these hosts (a host matches itself and its subdomains).
    static let hostScoped: [(hosts: [String], names: Set<String>)] = [
        (["youtube.com", "youtu.be", "open.spotify.com"], ["si"]),
        (["youtube.com", "youtu.be"], ["feature", "pp"]),
        (["x.com", "twitter.com"], ["s", "t", "ref_src", "ref_url"]),
        (["facebook.com", "instagram.com"], ["mibextid"]),
    ]

    static func isTracking(name: String, host: String) -> Bool {
        let n = name.lowercased()
        if globalNames.contains(n) { return true }
        if globalPrefixes.contains(where: { n.hasPrefix($0) }) { return true }
        for rule in hostScoped where rule.names.contains(n) {
            if rule.hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }
        }
        return false
    }

    // MARK: - Cleaning

    /// `nil` when the input is not a single http(s) link, has no query, or carries nothing on
    /// the list. A non-nil result always differs from the input.
    static func clean(_ input: String) -> Result? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // One token only: any inner whitespace means prose, not a bare link.
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }

        // Fragment first: a `?` after `#` belongs to client-side routing, never to the query.
        let beforeFragment: Substring
        let fragment: Substring
        if let hash = trimmed.firstIndex(of: "#") {
            beforeFragment = trimmed[..<hash]
            fragment = trimmed[hash...]
        } else {
            beforeFragment = trimmed[...]
            fragment = ""
        }

        guard let q = beforeFragment.firstIndex(of: "?") else { return nil }
        let base = beforeFragment[..<q]
        let query = beforeFragment[beforeFragment.index(after: q)...]
        guard let host = host(ofAbsoluteURL: String(base)) else { return nil }

        var kept: [Substring] = []
        var removed: [String] = []
        for part in query.split(separator: "&", omittingEmptySubsequences: true) {
            let rawName = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? part
            let name = String(rawName).removingPercentEncoding ?? String(rawName)
            if isTracking(name: name, host: host) {
                removed.append(name.lowercased())
            } else {
                kept.append(part)
            }
        }
        guard !removed.isEmpty else { return nil }

        let rebuiltQuery = kept.isEmpty ? "" : "?" + kept.joined(separator: "&")
        return Result(cleaned: String(base) + rebuiltQuery + String(fragment), removed: removed, host: host)
    }

    /// Lower-cased host of `scheme://[user@]host[:port]/…`, without Foundation's URL parser
    /// (which rejects some non-ASCII hosts and would make the rule depend on its quirks).
    static func host(ofAbsoluteURL s: String) -> String? {
        guard let schemeEnd = s.range(of: "://") else { return nil }
        var authority = s[schemeEnd.upperBound...]
        if let slash = authority.firstIndex(of: "/") { authority = authority[..<slash] }
        if let at = authority.lastIndex(of: "@") { authority = authority[authority.index(after: at)...] }
        var host = Substring(authority)
        if host.hasPrefix("[") {
            // IPv6 literal: keep through the closing bracket.
            if let close = host.firstIndex(of: "]") { host = host[...close] }
        } else if let colon = host.firstIndex(of: ":") {
            host = host[..<colon]
        }
        let h = host.lowercased()
        return h.isEmpty ? nil : h
    }
}

/// Remembers the `NSPasteboard.changeCount` of writes XFinder made itself.
///
/// Why this exists: the paste engine writes the pasteboard and then sends ⌘V ~150 ms later, and
/// the clipboard monitor treats every `changeCount` bump as a fresh copy. With link cleaning on,
/// the monitor would "clean" the item **while it is being pasted** — rewriting the pasteboard
/// (`clearContents` then `setString`) under the target app's read. The engine records its own
/// write here and the monitor skips cleaning for that count. Ingest is unchanged on purpose:
/// usage counts and de-duplication depend on it.
final class OwnWriteMark: @unchecked Sendable {
    static let shared = OwnWriteMark()
    private let lock = NSLock()
    private var counts: [Int] = []

    /// Remember a count; only the last few matter, so the list never grows.
    func record(_ changeCount: Int) {
        lock.lock(); defer { lock.unlock() }
        counts.append(changeCount)
        if counts.count > 8 { counts.removeFirst(counts.count - 8) }
    }

    func contains(_ changeCount: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return counts.contains(changeCount)
    }

    /// Pasteboard states XFinder created only to READ something (the translate fallback sends ⌘C to
    /// the front app, then puts the user's clipboard back). They are not the user's copies, so
    /// clipboard history must not ingest them. Separate from `counts`: those still ingest.
    private var transient: [Int] = []

    func recordTransient(_ changeCount: Int) {
        lock.lock(); defer { lock.unlock() }
        transient.append(changeCount)
        if transient.count > 8 { transient.removeFirst(transient.count - 8) }
    }

    func isTransient(_ changeCount: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return transient.contains(changeCount)
    }
}
