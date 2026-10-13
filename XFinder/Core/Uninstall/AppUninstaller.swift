import AppKit

/// F2 — the system side of "Gỡ ứng dụng": which apps are installed, what an app left in ~/Library (decided by the
/// pure `Uninstall` rules), how big each item is, and moving the chosen items to the Trash one by one, each with its
/// own outcome. Nothing is ever deleted.
enum AppUninstaller {

    struct InstalledApp: Identifiable, Hashable {
        var id: String { url.path }
        let url: URL
        let name: String
        let bundleID: String
    }

    /// Top level of /Applications, /Applications/Utilities and ~/Applications. Apple's own apps are listed too (the
    /// page explains why they are refused) — hiding them would read as "XFinder cannot find Safari".
    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var out: [InstalledApp] = []
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(name)
                guard let info = info(for: url), seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                out.append(InstalledApp(url: url, name: info.name, bundleID: info.bundleID))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func info(for url: URL) -> Uninstall.AppInfo? {
        guard let b = Bundle(url: url) else { return nil }
        let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return Uninstall.AppInfo(path: url.path, bundleID: b.bundleIdentifier ?? "", name: name)
    }

    static var libraryURL: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library") }

    static func url(of c: Uninstall.Candidate) -> URL {
        libraryURL.appendingPathComponent(c.location.rawValue, isDirectory: true).appendingPathComponent(c.fileName)
    }

    /// Names in one Library folder. FileManager's listing hides regular files named "._…" — none of the names that
    /// belong to an app look like that, so it is fine here (unlike the junk scan, which must use `FileWalk`).
    static func leftovers(for app: Uninstall.AppInfo, installed: [String]) -> [Uninstall.Candidate] {
        Uninstall.plan(app: app, listing: { loc in
            (try? FileManager.default.contentsOfDirectory(atPath: libraryURL.appendingPathComponent(loc.rawValue).path)) ?? []
        }, installed: installed)
    }

    @MainActor static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Asks the app to quit, as its own Quit menu would (it may ask to save documents).
    @MainActor static func requestQuit(bundleID: String) {
        NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }.forEach { $0.terminate() }
    }

    /// One `trashItem` per URL, in order; each URL gets its own outcome.
    static func moveToTrash(_ urls: [URL]) -> [URL: Uninstall.ItemOutcome] {
        var out: [URL: Uninstall.ItemOutcome] = [:]
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                out[url] = .trashed
            } catch {
                let e = error as NSError
                let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError
                let o = Uninstall.outcome(domain: e.domain, code: e.code, message: e.localizedDescription)
                if case .failed = o, let u = underlying {
                    out[url] = Uninstall.outcome(domain: u.domain, code: u.code, message: e.localizedDescription)
                } else {
                    out[url] = o
                }
            }
        }
        return out
    }
}
