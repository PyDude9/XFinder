import Foundation

/// F2 — "Remove app X cleanly: the app and what it left in my Library — see every item first, all of it to the Trash."
/// Pure: which names in `~/Library` belong to an app, what is selected by default, what is refused, how an error reads.
///
/// Matching was checked against what six installed apps actually left (2026-10-13, names only): Keka, WireGuard, Hush,
/// Pause, Sentinel, Fluor — exact bundle id (`Preferences/<bid>.plist`, `Containers/<bid>`), helpers and extensions
/// (`Containers/<bid>.network-extension`), group containers (`<TEAM>.group.<bid>`, `group.<bid>`), and one folder
/// named after the app (`Application Support/Sentinel`). No match collided with another installed app.
///
/// What an app without special permissions can move (measured with a probe app launched by LaunchServices, so TCC
/// judged the probe and not the terminal): an app bundle in /Applications or ~/Applications — including a Developer ID,
/// hardened-runtime one — and folders in Application Support / Caches: yes. Another app's sandbox container: NO,
/// `NSCocoaErrorDomain 513`, with both `FileManager.trashItem` and `NSWorkspace.recycle`. (The same move from the
/// terminal SUCCEEDED — a probe run from a shell measures the shell's permissions, not the app's.)
enum Uninstall {

    enum Location: String, CaseIterable, Equatable {
        case applicationSupport = "Application Support"
        case caches = "Caches"
        case preferences = "Preferences"
        case byHostPreferences = "Preferences/ByHost"
        case containers = "Containers"
        case groupContainers = "Group Containers"
        case applicationScripts = "Application Scripts"
        case savedState = "Saved Application State"
        case httpStorages = "HTTPStorages"
        case webKit = "WebKit"
        case cookies = "Cookies"
        case logs = "Logs"
        case launchAgents = "LaunchAgents"

        /// macOS guards these against other apps. Containers: measured (513). Group containers and application scripts
        /// belong to the same sandbox machinery; the page says "may be" for them and lets the attempt report the truth.
        var isProtected: Bool { self == .containers || self == .groupContainers || self == .applicationScripts }

        /// Measured to fail EVERY time for an app without special permissions (513). The page does not offer a checkbox
        /// that cannot work — it offers "Show in Finder" instead. The other protected kinds stay tickable (unticked by
        /// default) because their refusal was not measured; the attempt reports the truth per item.
        var alwaysRefused: Bool { self == .containers }
    }

    enum Match: String, Equatable {
        case exact, helper, group, name, launchAgent
    }

    struct Candidate: Equatable {
        let location: Location
        let fileName: String
        let match: Match

        /// A folder named after the app is a guess (another app may use the same word); a protected location cannot
        /// be moved by XFinder anyway — both start unticked.
        var selectedByDefault: Bool { match != .name && !location.isProtected }
    }

    struct AppInfo: Equatable {
        let path: String
        let bundleID: String
        let name: String
    }

    enum Refusal: Equatable {
        case notAnApp, apple, system, itself, running
    }

    /// Why this app must not be uninstalled here (nil ⇒ it may be). A running app is refused until it quits: moving
    /// its files away under it loses whatever it writes next.
    static func refusal(_ app: AppInfo, ownBundleID: String, running: Set<String>) -> Refusal? {
        if app.bundleID.isEmpty || !app.path.hasSuffix(".app") { return .notAnApp }
        if app.bundleID.hasPrefix("com.apple.") { return .apple }
        if app.path.hasPrefix("/System/") { return .system }
        if app.bundleID == ownBundleID { return .itself }
        if running.contains(app.bundleID) { return .running }
        return nil
    }

    /// `com.foo.App.plist` → `com.foo.App`; `com.foo.App.savedState` → `com.foo.App`.
    static func baseName(_ fileName: String) -> String {
        for ext in [".plist", ".savedState", ".binarycookies"] where fileName.hasSuffix(ext) && fileName.count > ext.count {
            return String(fileName.dropLast(ext.count))
        }
        return fileName
    }

    static func match(fileName: String, in location: Location, app: AppInfo) -> Match? {
        let bid = app.bundleID
        guard !bid.isEmpty else { return nil }
        let base = baseName(fileName)
        if base == bid { return location == .launchAgents ? .launchAgent : .exact }
        if base.hasPrefix(bid + ".") {
            switch location {
            case .launchAgents: return .launchAgent
            case .byHostPreferences: return .exact          // <bid>.<host UUID>.plist
            default: return .helper
            }
        }
        if location == .groupContainers, base.hasSuffix("." + bid) { return .group }
        if [.applicationSupport, .caches, .logs].contains(location), app.name.count >= 3,
           base.caseInsensitiveCompare(app.name) == .orderedSame { return .name }
        return nil
    }

    /// A name that belongs to ANOTHER installed app whose id extends this one (`com.google.Chrome.canary` when removing
    /// `com.google.Chrome`) is never offered.
    static func claimedByOther(_ fileName: String, bundleID: String, installed: [String]) -> Bool {
        let base = baseName(fileName)
        return installed.contains { other in
            other != bundleID && other.hasPrefix(bundleID + ".") && (base == other || base.hasPrefix(other + "."))
        }
    }

    /// Every leftover, in `Location.allCases` order, then by name. `listing` returns the names in one Library folder.
    static func plan(app: AppInfo, listing: (Location) -> [String], installed: [String]) -> [Candidate] {
        Location.allCases.flatMap { loc in
            listing(loc).sorted().compactMap { name -> Candidate? in
                guard let m = match(fileName: name, in: loc, app: app),
                      !claimedByOther(name, bundleID: app.bundleID, installed: installed) else { return nil }
                return Candidate(location: loc, fileName: name, match: m)
            }
        }
    }

    // MARK: Outcome of one move

    enum ItemOutcome: Equatable {
        case trashed
        /// macOS refused (513 / EPERM / EACCES): the page offers "Show in Finder" so the user can drag it.
        case protected
        case missing
        case failed(String)
    }

    static func outcome(domain: String, code: Int, message: String) -> ItemOutcome {
        if domain == NSCocoaErrorDomain && (code == NSFileWriteNoPermissionError || code == NSFileReadNoPermissionError) { return .protected }
        if domain == NSPOSIXErrorDomain && (code == Int(EPERM) || code == Int(EACCES)) { return .protected }
        if domain == NSCocoaErrorDomain && (code == NSFileNoSuchFileError || code == NSFileReadNoSuchFileError) { return .missing }
        return .failed(message)
    }
}
