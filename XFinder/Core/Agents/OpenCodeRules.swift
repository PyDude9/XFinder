import Foundation

/// P5b (2026-10-14) — OpenCode sessions on the notch. Pure (symlinked into the test package).
///
/// Measured on this Mac (OpenCode v2.0.27) before a line was written:
/// * Its plugin loader REJECTS the v1 plugin shape — `"Plugin must export a default definition with an id and an
///   effect or setup function"`, logged for Notch Crew's `notch.js` — so a plugin is not a dependable way in.
/// * A background service (`opencode serve --service`) answers an HTTP API that needs a password XFinder must not
///   read (`401` without it). OpenCode's own CLI carries it: `opencode api <operationId> --param k=v -d <json>` —
///   so XFinder runs the person's own `opencode` binary and never touches a credential.
/// * `opencode api event.subscribe` buffers the whole SSE response (0 bytes in 8 s, even with events flowing), so
///   there is no push channel through the CLI. A PENDING permission request lives in memory only — the database
///   and its WAL do not change when one is created — but the tool call that triggers it is written just before,
///   so a write to the database is the cue to ask (debounced; a trailing check catches the request that lands
///   right after the write burst).
/// * The full answer loop was run against an isolated `opencode serve` (scratch XDG dirs, its own port):
///   `permission.asked` → `opencode api session.permission.reply --param sessionID=… --param requestID=…
///   -d '{"decision":"once"}'` → `permission.replied`, and the request list is empty afterwards. On v2 the shell
///   permission action is `shell` (not `bash`), and a request created without an agent evaluates to `deny`.
/// * One CLI call costs ~0.05 s wall / 0.04 s CPU and ~99 MB transient RSS — fine on a write cue, not as a timer.
enum OpenCodeRules {

    struct SessionInfo: Equatable, Sendable {
        var id: String
        var title: String?
        var directory: String?
        var parentID: String?
        var created: Date
        var updated: Date
        /// `succeeded` / `failed` once the session's last turn has an outcome.
        var outcome: String?
    }

    struct PendingRequest: Equatable, Sendable {
        var id: String
        var sessionID: String
        var action: String
        var resources: [String]
        var command: String?
        var message: String?
    }

    // MARK: - Parsing the API's JSON (each returns nil for anything that is not the documented shape)

    /// `session.active` → `{"data": {"ses_…": {"type": "running"}}}`. Sessions absent from it are inactive.
    static func parseActive(_ data: Data) -> Set<String>? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let map = obj["data"] as? [String: Any] else { return nil }
        return Set(map.keys.filter(isSessionID))
    }

    /// `session.list` → `{"data": [Session.Info], "cursor": {...}}`. Times are epoch MILLISECONDS.
    static func parseSessions(_ data: Data) -> [SessionInfo]? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return nil }
        return list.compactMap { s in
            guard let id = s["id"] as? String, isSessionID(id) else { return nil }
            let time = s["time"] as? [String: Any] ?? [:]
            let created = date(ms: time["created"]) ?? Date(timeIntervalSince1970: 0)
            let updated = date(ms: time["updated"]) ?? created
            let title = (s["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let dir = (s["location"] as? [String: Any])?["directory"] as? String
            return SessionInfo(id: id, title: title, directory: dir, parentID: s["parentID"] as? String,
                               created: created, updated: updated, outcome: s["outcome"] as? String)
        }
    }

    /// `session.permission.list` / `permission.request.list` → `{"data": [Permission.Request]}`.
    static func parsePermissions(_ data: Data) -> [PendingRequest]? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return nil }
        return list.compactMap { r in
            guard let id = r["id"] as? String, isRequestID(id),
                  let sid = r["sessionID"] as? String, isSessionID(sid) else { return nil }
            let meta = r["metadata"] as? [String: Any] ?? [:]
            return PendingRequest(id: id, sessionID: sid, action: r["action"] as? String ?? "?",
                                  resources: r["resources"] as? [String] ?? [], command: meta["command"] as? String,
                                  message: r["message"] as? String)
        }
    }

    private static func date(ms: Any?) -> Date? {
        if let n = ms as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000) }
        return nil
    }

    // MARK: - IDs (a value that goes into a process argument is validated first)

    static func isSessionID(_ s: String) -> Bool { matches(s, prefix: "ses_") }
    static func isRequestID(_ s: String) -> Bool { matches(s, prefix: "per_") }

    private static func matches(_ s: String, prefix: String) -> Bool {
        guard s.hasPrefix(prefix), s.count > prefix.count, s.count <= 80 else { return false }
        return s.dropFirst(prefix.count).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    // MARK: - CLI arguments

    static func activeArguments() -> [String] { ["api", "session.active"] }
    /// Top-level sessions only: a child (`parentID`) is a subagent of a session that is already listed.
    static func listArguments(limit: Int) -> [String] { ["api", "session.list", "--param", "limit=\(max(1, min(limit, 50)))"] }
    static func permissionListArguments(sessionID: String) -> [String]? {
        guard isSessionID(sessionID) else { return nil }
        return ["api", "session.permission.list", "--param", "sessionID=\(sessionID)"]
    }
    /// "Cho phép" answers `once` — never `always`, which would save a rule in the person's OpenCode config.
    static func replyArguments(sessionID: String, requestID: String, allow: Bool) -> [String]? {
        guard isSessionID(sessionID), isRequestID(requestID) else { return nil }
        let body = allow ? #"{"decision":"once"}"# : #"{"decision":"reject"}"#
        return ["api", "session.permission.reply", "--param", "sessionID=\(sessionID)", "--param", "requestID=\(requestID)", "-d", body]
    }

    /// Where `opencode` is usually installed (its own installer puts it in ~/.opencode/bin). First executable wins.
    static func binaryCandidates(home: String) -> [String] {
        ["\(home)/.opencode/bin/opencode", "/opt/homebrew/bin/opencode", "/usr/local/bin/opencode",
         "\(home)/.local/bin/opencode", "\(home)/.bun/bin/opencode"]
    }

    // MARK: - Sessions

    /// The API's view → the notch's rows.
    /// * a pending request ⇒ waiting for permission (the oldest one, since `firstSeen`);
    /// * listed by `session.active` ⇒ running;
    /// * otherwise, while an OpenCode terminal client is open and the session moved in the last `staleAfter`,
    ///   it is the person's turn; else ended. (No API says "the person has the prompt" — an idle session with a
    ///   client open is the closest true statement.)
    /// Ended sessions older than `AgentSessionRules.keepEndedFor` and subagent (child) sessions are not listed.
    static func sessions(info: [SessionInfo], active: Set<String>, pending: [PendingRequest], clientOpen: Bool,
                         now: Date, answered: Set<String>, firstSeen: [String: Date]) -> [AgentSession] {
        var out: [AgentSession] = []
        for s in info where s.parentID == nil {
            let waiting = pending.filter { $0.sessionID == s.id && !answered.contains($0.id) }
                .sorted { (firstSeen[$0.id] ?? now) < (firstSeen[$1.id] ?? now) }
            let status: AgentSession.Status
            if let p = waiting.first {
                status = .waitingForPermission(.init(requestID: p.id, toolName: p.action,
                                                     summary: p.command ?? p.resources.first ?? p.message,
                                                     since: firstSeen[p.id] ?? now))
            } else if active.contains(s.id) {
                status = .running(tool: nil)
            } else if clientOpen, now.timeIntervalSince(s.updated) <= AgentSessionRules.staleAfter {
                status = .waitingForInput
            } else {
                status = .ended
            }
            if status == .ended, now.timeIntervalSince(s.updated) > AgentSessionRules.keepEndedFor { continue }
            var row = AgentSession(id: s.id, agent: .opencode, cwd: s.directory, transcriptPath: nil, startedAt: s.created,
                                   updatedAt: s.updated, status: status, lastTool: nil, lastPrompt: nil, agentPID: nil,
                                   terminal: AgentEvents.Terminal(), eventCount: 0)
            row.title = s.title
            out.append(row)
        }
        return out
    }

    /// Is any OpenCode TERMINAL client running? `ps -axo command=` lines → true when one runs `opencode` without
    /// `serve` (the background service is always up once installed, and proves nothing about a session).
    static func clientRunning(psCommands: String) -> Bool {
        psCommands.split(separator: "\n").contains { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let exe = parts.first, (String(exe) as NSString).lastPathComponent == "opencode" else { return false }
            return !parts.dropFirst().contains("serve")
        }
    }
}
