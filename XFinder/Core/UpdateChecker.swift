import Foundation
import AppKit

/// Compares this build against the latest GitHub Release.
///
/// Deliberately minimal: one unauthenticated GET to the public Releases API,
/// only when the user presses the button. No background polling, no telemetry,
/// nothing sent about the user — the request carries no identifying data, which
/// keeps the app's "100% local, zero telemetry" promise intact (checking for a
/// newer version is a user-initiated fetch, not tracking).
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        /// Running the newest published release.
        case upToDate(current: String)
        case updateAvailable(latest: String, current: String, url: URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Owner/repo of the public repository holding the Releases.
    private let owner = "PyDude9"
    private let repo = "XFinder"

    private init() {}

    /// This build's marketing version, e.g. "1.0.0".
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var releasesPageURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)/releases")!
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub rejects API requests without a User-Agent.
        request.setValue("XFinder/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let current = currentVersion
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                // 404 is the normal answer for a repo with no releases yet —
                // report it as "no release", not as a failure the user must act on.
                if code == 404 {
                    state = .upToDate(current: current)
                    return
                }
                guard code == 200 else {
                    state = .failed("GitHub trả về mã \(code)")
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tagName
                if Self.isNewer(latest, than: current),
                   let page = URL(string: release.htmlURL) {
                    state = .updateAvailable(latest: Self.normalize(latest),
                                             current: current,
                                             url: page)
                } else {
                    state = .upToDate(current: current)
                }
            } catch is CancellationError {
                state = .idle
            } catch {
                // Offline is the common case here; say so plainly.
                state = .failed(error.localizedDescription)
            }
        }
    }

    func openReleasesPage(_ url: URL? = nil) {
        NSWorkspace.shared.open(url ?? releasesPageURL)
    }

    // MARK: - Version comparison

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Strips a leading "v" and any pre-release suffix so "v1.2.0" and "1.2.0"
    /// compare equal.
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    /// Numeric, component-wise comparison — NOT a string compare.
    ///
    /// `"1.10.0" > "1.9.0"` is true numerically but false lexicographically,
    /// which would silently stop offering updates after version 9. Missing
    /// components count as zero so "1.2" and "1.2.0" are equal.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(normalize(candidate))
        let b = components(normalize(current))
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        // Drop anything after a pre-release marker: "1.2.0-beta.1" -> "1.2.0".
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        return core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
