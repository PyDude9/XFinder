import Foundation

/// N3 — the pure half of "Cài hook Claude Code": how XFinder's command hook is merged into, found in and removed
/// from `~/.claude/settings.json` without touching anything else in that file. Claude Code's `hooks` value is
/// `{ "<Event>": [ { "matcher": "...", "hooks": [ { "type": "command", "command": "...", "timeout": N } ] } ] }`;
/// several tools may register entries for one event, so XFinder APPENDS its own entry and identifies it later by
/// the hook command's path — never by position, never by clearing the array.
///
/// `AgentSessionMonitor` reads and writes the file (and only when the person presses the button: a hook runs a
/// shell script inside every Claude Code session, so it is installed on request, never on a switch).
enum AgentHookInstaller {
    /// Events XFinder subscribes to. `PermissionRequest` gets the long timeout: the hook blocks until the notch
    /// answers (or XFinder is gone), and Claude Code kills a hook that outlives its timeout.
    static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("SessionEnd", 10), ("UserPromptSubmit", 10),
        ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10), ("Notification", 10),
        ("Stop", 10), ("SubagentStop", 10), ("PreCompact", 10), ("PostCompact", 10),
        ("PermissionRequest", 3600), ("PermissionDenied", 10),
    ]
    static let marker = "Managed by XFinder"

    /// The command Claude Code runs: the script path, single-quoted so a space in the home folder survives.
    static func command(forHookAt path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Is XFinder's hook registered for every event it needs? (Partial = "cần sửa", like OneNotch's "hooks need repair".)
    enum Status: Equatable { case installed, partial(missing: [String]), notInstalled }

    static func status(of settings: [String: Any], hookPath: String) -> Status {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let missing = events.map(\.name).filter { !contains(hooks[$0], hookPath: hookPath) }
        if missing.count == events.count { return .notInstalled }
        return missing.isEmpty ? .installed : .partial(missing: missing)
    }

    /// `settings` with XFinder's entry present once for every event — existing entries (ours or others') are kept.
    static func merged(_ settings: [String: Any], hookPath: String) -> [String: Any] {
        var out = settings
        var hooks = out["hooks"] as? [String: Any] ?? [:]
        for (name, timeout) in events {
            var list = hooks[name] as? [[String: Any]] ?? []
            if !contains(list, hookPath: hookPath) {
                list.append(["matcher": "", "hooks": [["type": "command", "command": command(forHookAt: hookPath),
                                                       "timeout": timeout, "statusMessage": marker]]])
            }
            hooks[name] = list
        }
        out["hooks"] = hooks
        return out
    }

    /// `settings` without any entry whose command points at XFinder's hook; an event left with no entries is
    /// dropped from `hooks`, and an empty `hooks` object is dropped from the settings.
    static func removed(_ settings: [String: Any], hookPath: String) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any] else { return out }
        for (name, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }
            let kept = list.compactMap { entry -> [String: Any]? in
                var e = entry
                let inner = (e["hooks"] as? [[String: Any]] ?? []).filter { !isOurs($0, hookPath: hookPath) }
                if inner.isEmpty { return nil }
                e["hooks"] = inner
                return e
            }
            if kept.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = kept }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    private static func contains(_ value: Any?, hookPath: String) -> Bool {
        guard let list = value as? [[String: Any]] else { return false }
        return list.contains { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).contains { isOurs($0, hookPath: hookPath) }
        }
    }

    private static func isOurs(_ hook: [String: Any], hookPath: String) -> Bool {
        guard let c = hook["command"] as? String else { return false }
        return c.contains(hookPath)
    }

    /// Serialise for writing: pretty, sorted keys, slashes unescaped — stable across runs so a diff of the
    /// file shows only what changed.
    static func data(for settings: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

/// N3 — the decision a `PermissionRequest` hook prints on stdout when the notch answers. Written to
/// `decisions/<session>-<request>.json`; the hook reads, deletes and prints it. The JSON shape is Claude Code's
/// documented PermissionRequest hook output (`hookSpecificOutput.decision.behavior`).
enum AgentDecision {
    static func fileName(sessionID: String, requestID: String) -> String { "\(sessionID)-\(requestID).json" }

    static func payload(allow: Bool) -> String {
        let decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        let obj: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
