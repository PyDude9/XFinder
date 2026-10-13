import Foundation

/// P2 — install rules for Claude Code's `statusLine` setting, and the parser for the rate-limit cache the
/// installed script writes. Pure (Foundation only); `AgentSessionMonitor` is the live half that reads/writes
/// `~/.claude/settings.json` and the cache file on disk.
///
/// Claude Code's `statusLine` setting is ONE object, not a list (unlike `hooks`, which is keyed by event and can
/// hold several tools' entries side by side) — so installing XFinder's script must CHAIN to whatever was there
/// before, and removing it must put that exact object back. `AgentHookInstaller.command(forHookAt:)` is the
/// model for quoting a path for `/bin/sh -c`; `command(forScriptAt:)` here does the same thing for the same reason
/// (a space or a quote in the home folder must survive).
enum ClaudeStatusLine {

    // MARK: - Paths (identical to AgentSessionMonitor.supportDir: `home/Library/Application Support/XFinder/Agents/claude`)

    static func supportDir(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/XFinder/Agents/claude", isDirectory: true)
    }

    static func scriptURL(home: URL) -> URL {
        supportDir(home: home).appendingPathComponent("bin/xfinder-claude-statusline.sh")
    }

    static func cacheURL(home: URL) -> URL {
        supportDir(home: home).appendingPathComponent("rate-limits.json")
    }

    /// The command string of whatever statusLine was installed before XFinder's — what the script chains to.
    static func previousCommandURL(home: URL) -> URL {
        supportDir(home: home).appendingPathComponent("statusline-before")
    }

    /// The whole previous `statusLine` object (so removal can restore it verbatim, keys and all).
    static func previousJSONURL(home: URL) -> URL {
        supportDir(home: home).appendingPathComponent("statusline-before.json")
    }

    // MARK: - Quoting

    /// Single-quoted like `AgentHookInstaller.command(forHookAt:)`, so a space or an embedded quote in the path
    /// survives being run by `/bin/sh -c "$command"`.
    static func command(forScriptAt path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Recognising our own entry

    /// `statusLine` is a dictionary (Claude Code's documented shape is `{"type":"command","command":"...",…}`).
    /// Anything else (absent, a string, a number) is "not ours".
    static func isOurs(_ statusLine: Any?, scriptPath: String) -> Bool {
        guard let dict = statusLine as? [String: Any], let command = dict["command"] as? String else { return false }
        return command.contains(scriptPath)
    }

    enum Status: Equatable {
        case notInstalled
        case installed
        /// We installed once (a previous-settings save exists) but `settings.json` now points somewhere else —
        /// another tool's installer, or the person's own edit, replaced it.
        case replaced
    }

    static func status(of settings: [String: Any], scriptPath: String, previousSaved: Bool) -> Status {
        if isOurs(settings["statusLine"], scriptPath: scriptPath) { return .installed }
        return previousSaved ? .replaced : .notInstalled
    }

    // MARK: - Install

    /// `previous` is the statusLine value that was there before, WHATEVER its JSON type (P2 review: a hand-edited
    /// string or array used to be dropped by an `as? [String: Any]` cast and was then gone for good — "Gỡ" deleted the
    /// key instead of restoring it). nil = there was no statusLine key at all.
    struct Install: Equatable {
        var settings: [String: Any]
        var previous: Any?
        var previousCommand: String?

        static func == (lhs: Install, rhs: Install) -> Bool {
            NSDictionary(dictionary: lhs.settings).isEqual(to: rhs.settings)
                && jsonEqual(lhs.previous, rhs.previous)
                && lhs.previousCommand == rhs.previousCommand
        }
    }

    /// Two JSON values (nil-able) compared the way Foundation compares property lists.
    static func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return NSArray(array: [x]).isEqual(to: [y])
        default: return false
        }
    }

    // MARK: - The saved previous value on disk

    /// The file holds `{"statusLine": <the previous value>}`: always a JSON object, so a previous value of any JSON type
    /// (object, string, number, array, null) survives the round trip.
    static func encodePrevious(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["statusLine": value], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The saved value, or nil when the file is not a readable save (truncated, hand-edited, another format) — the
    /// caller must then REFUSE to remove rather than delete the key, or the previous setting would be lost silently.
    static func decodePrevious(_ data: Data) -> Any? {
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any],
              obj.count == 1, let value = obj["statusLine"] else { return nil }
        return value
    }

    /// What installing over `settings` produces. Three cases:
    /// - no `statusLine` present → previous = nil, previousCommand = nil, new value is our bare command object.
    /// - another tool's `statusLine` → previous = that object VERBATIM; previousCommand = its "command" string,
    ///   UNLESS that command already points back at us (a previous install's chain) — chaining into ourselves
    ///   would recurse, so previousCommand is nil in that case (the script's own `XFINDER_STATUSLINE_ACTIVE`
    ///   guard is the second line of defence, but the installer should not even write that chain). The new
    ///   object keeps every OTHER key of the previous object (padding, refreshInterval, hideVimModeIndicator…)
    ///   so the visible status line's own look is unaffected — only "type" and "command" are replaced.
    /// - our own `statusLine` already installed → settings unchanged, previous = nil, previousCommand = nil
    ///   (the caller must not overwrite whatever it already saved at the FIRST install).
    static func installing(_ settings: [String: Any], scriptPath: String) -> Install {
        var out = settings
        let raw = settings["statusLine"]
        let existing = raw as? [String: Any]

        if let existing, isOurs(existing, scriptPath: scriptPath) {
            // Already ours: leave settings (and the caller's saved previous files) untouched.
            return Install(settings: settings, previous: nil, previousCommand: nil)
        }

        var newValue: [String: Any] = existing ?? [:]
        newValue["type"] = "command"
        newValue["command"] = command(forScriptAt: scriptPath)
        out["statusLine"] = newValue

        // A previous value that is not an object (hand-edited string, array, null…) is saved VERBATIM so removal can put
        // it back; there is nothing to chain to, because Claude Code only runs {"type": "command"} objects.
        guard let raw else { return Install(settings: out, previous: nil, previousCommand: nil) }
        guard let existing else { return Install(settings: out, previous: raw, previousCommand: nil) }

        var previousCommand: String?
        if existing["type"] as? String == "command", let c = existing["command"] as? String, !c.contains(scriptPath) {
            previousCommand = c
        }
        return Install(settings: out, previous: existing, previousCommand: previousCommand)
    }

    // MARK: - Remove

    /// `settings` with XFinder's `statusLine` undone:
    /// - currently ours + `previous` given → restored verbatim.
    /// - currently ours + `previous` nil → the `statusLine` key is deleted (there was nothing before us).
    /// - NOT currently ours → unchanged (another tool owns the slot now; overwriting it would discard that
    ///   tool's own chain, which may lead back to us).
    static func removing(_ settings: [String: Any], scriptPath: String, previous: Any?) -> [String: Any] {
        guard isOurs(settings["statusLine"], scriptPath: scriptPath) else { return settings }
        var out = settings
        if let previous {
            out["statusLine"] = previous
        } else {
            out.removeValue(forKey: "statusLine")
        }
        return out
    }

    // MARK: - The rate-limit cache the script writes

    struct Window: Equatable, Sendable {
        var usedPercent: Double
        var resetsAt: Date?
    }

    struct Quota: Equatable, Sendable {
        var fiveHour: Window?
        var sevenDay: Window?
        var capturedAt: Date
    }

    /// `data` is the bare `rate_limits` object Claude Code hands the status line, e.g.
    /// `{"five_hour":{"used_percentage":37.5,"resets_at":1792000000},"seven_day":{"used_percentage":12}}`.
    /// `resets_at` is Unix epoch SECONDS; `used_percentage` may arrive as an Int or a Double. A window with no
    /// `used_percentage` is absent (not a 0 %). nil is returned for anything that is not a JSON object, or an
    /// object with neither window.
    static func parseQuota(_ data: Data, capturedAt: Date) -> Quota? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let five = window(obj["five_hour"])
        let seven = window(obj["seven_day"])
        guard five != nil || seven != nil else { return nil }
        return Quota(fiveHour: five, sevenDay: seven, capturedAt: capturedAt)
    }

    private static func window(_ raw: Any?) -> Window? {
        guard let dict = raw as? [String: Any], let pct = (dict["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        var resetsAt: Date?
        if let secs = (dict["resets_at"] as? NSNumber)?.doubleValue {
            resetsAt = Date(timeIntervalSince1970: secs)
        }
        return Window(usedPercent: pct, resetsAt: resetsAt)
    }

    /// Claude Code itself drops a window once its reset time has passed; a stale figure must not be shown as
    /// current. No `resetsAt` (older cache shape, or the field was absent) is read as still current.
    static func isCurrent(_ w: Window, now: Date) -> Bool {
        guard let resetsAt = w.resetsAt else { return true }
        return resetsAt > now
    }
}
