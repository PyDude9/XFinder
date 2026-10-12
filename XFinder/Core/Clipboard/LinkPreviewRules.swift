import Foundation
import CryptoKit

/// D4b (2026-10-13) — opt-in previews for copied links: title and a small image fetched from the page itself, the way
/// OneNotch's `LinkPreviewStore` does. The fetch is the ONE network action a copy can trigger, so it is off by
/// default and the rules about WHICH links may be fetched live here, pure and tested. `LinkPreviewFetcher`
/// (LinkPresentation) does the network and the disk.
///
/// Measured first (`scratchpad/d4b/lp-probe`): `LPMetadataProvider` from a CLI returns a title for apple.com in 1.1 s,
/// github.com in 1.4 s, example.com in 0.2 s, and fails a dead host in 0.2 s (`LPErrorDomain 2`).
enum LinkPreviewRules {
    static let enabledKey = "clipboard.linkPreviews"
    static let titleKey = "linkTitle"
    static let imageKey = "linkImage"
    static let fetchedKey = "linkFetched"
    /// A preview is refreshed after this long; a failed fetch is retried after `retryAfter`.
    static let staleAfter: TimeInterval = 30 * 86_400
    static let retryAfter: TimeInterval = 86_400
    static let fetchTimeout: TimeInterval = 8
    static let maxImageEdge = 480
    /// When the switch is turned on, how many existing link clips are fetched (newest first).
    static let backfillLimit = 50

    /// Only public http(s) hosts. Never localhost, `.local`, `.internal`, `.invalid`, bare IPs in private ranges,
    /// or a URL carrying credentials — a preview must not be a way to make XFinder knock on a private service.
    static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard url.user == nil, url.password == nil else { return false }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".internal") || host.hasSuffix(".invalid")
            || host.hasSuffix(".localhost") || host == "0.0.0.0" { return false }
        if let ip = ipv4(host) {
            let (a, b) = (ip[0], ip[1])
            if a == 10 || a == 127 || a == 0 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) { return false }
        }
        if host.contains(":") { return false }            // IPv6 literal: not worth the risk surface
        return true
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".").map(String.init)
        guard parts.count == 4 else { return nil }
        let nums = parts.compactMap(Int.init)
        guard nums.count == 4, nums.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return nums
    }

    /// Cache file stem: a SHA-256 of the URL string, so a host name never becomes a file name.
    static func cacheStem(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Does this record need a fetch now? `fetched` is the record's `linkFetched`, `hasTitle` whether a title was stored.
    static func needsFetch(fetched: Date?, hasTitle: Bool, now: Date) -> Bool {
        guard let fetched else { return true }
        return now.timeIntervalSince(fetched) > (hasTitle ? staleAfter : retryAfter)
    }

    /// The metadata patch for a result: a title (or none, on failure) and the cached image path. `fetched` is
    /// always written so a failure is not retried on every render.
    static func metadataPatch(title: String?, imagePath: String?, fetched: Date) -> [String: String] {
        var p: [String: String] = [fetchedKey: iso.string(from: fetched)]
        if let title, !title.isEmpty { p[titleKey] = String(title.prefix(200)) }
        if let imagePath { p[imageKey] = imagePath }
        return p
    }

    static func fetchedDate(from metadata: [String: String]) -> Date? {
        metadata[fetchedKey].flatMap(iso.date(from:))
    }

    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// The URL a link clip points at (`url` metadata first, the preview text second).
    static func url(of metadata: [String: String], preview: String) -> URL? {
        let s = (metadata["url"]?.isEmpty == false ? metadata["url"]! : preview).trimmingCharacters(in: .whitespacesAndNewlines)
        // macOS 27's URL(string:) percent-encodes "not a url at all" into a relative URL — demand a scheme and a host.
        guard let u = URL(string: s), u.scheme != nil, u.host != nil else { return nil }
        return u
    }
}
