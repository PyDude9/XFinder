import Foundation

/// N3 (2026-10-13) — AI agent sessions on the notch, built from the mechanism MEASURED on OneNotch 2.0.5
/// (`docs/ONENOTCH_EVIDENCE_2026-10-13.md` §7): Claude Code runs a hook command for every event of a session;
/// the hook appends ONE JSON line per event to a file XFinder owns; XFinder tails those files. Nothing here
/// touches a private API or needs a permission — it is files written by a shell script Claude Code launches.
///
/// This file is pure (Foundation only, symlinked into the test package): the line format, the parser and the
/// rules that turn a stream of events into "what is each session doing right now". `AgentSessionMonitor`
/// (AppKit) does the file watching, liveness checks and the notch page.
enum AgentEvents {

    /// What the hook writes per line: `{"received_at", "request_id", "agent", "env": {...}, "payload": <the agent's
    /// hook input>}`. `payload.tool_response` is dropped by the hook (an image Read carries the base64 of the
    /// image — 650 KB measured on OneNotch's log); a payload over 256 KB is replaced by a stub with
    /// `xfinder_dropped: true` so one event can never push a day's log past what the reader keeps in memory.
    struct Event: Equatable {
        enum Name: String, Equatable {
            case sessionStart = "SessionStart", sessionEnd = "SessionEnd", userPromptSubmit = "UserPromptSubmit"
            case preToolUse = "PreToolUse", postToolUse = "PostToolUse", postToolUseFailure = "PostToolUseFailure"
            case notification = "Notification"
            case stop = "Stop", subagentStop = "SubagentStop", preCompact = "PreCompact", postCompact = "PostCompact"
            case permissionRequest = "PermissionRequest", permissionDenied = "PermissionDenied"
            case messageDisplay = "MessageDisplay", stopFailure = "StopFailure"
            /// Codex only (P5): the person interrupted a running turn — it is their turn again.
            case interrupt = "Interrupt"
            case subagentStart = "SubagentStart"
            case other = "?"
        }
        /// Which agent's hook wrote the line (P5). Lines written before P5 carry no `agent` field: they are Claude's.
        var agent: AgentKind = .claude
        var receivedAt: Date
        var name: Name
        /// The raw `hook_event_name`, kept so an event this build does not know still shows its name.
        var rawName: String
        var sessionID: String
        var requestID: String?
        var cwd: String?
        var transcriptPath: String?
        var toolName: String?
        /// A one-line summary of `tool_input` (command / file path / pattern) for the permission card.
        var toolInputSummary: String?
        var notificationType: String?
        var message: String?
        var prompt: String?
        /// The `claude` process that ran the hook (the hook's parent) — what liveness is measured on.
        var agentPID: Int32?
        var terminal: Terminal
        var dropped: Bool = false
    }

    /// Where the session lives, so "Mở terminal" can bring the right app forward. All optional: a hook run
    /// from a non-terminal host (the desktop app, an IDE) has none of it.
    struct Terminal: Equatable {
        var bundleID: String?
        var termProgram: String?
        var tty: String?
        var itermSession: String?
        var tmuxPane: String?
        var weztermPane: String?
        var termSession: String?
        var entrypoint: String?
    }

    // MARK: - Parsing

    static let maxPayloadBytes = 262_144

    /// One JSONL line → an event, or nil for a blank / unparseable / payload-less line. Unknown fields are
    /// ignored; an unknown `hook_event_name` becomes `.other` with `rawName` kept.
    static func parse(line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return nil }
        let rawName = payload["hook_event_name"] as? String ?? ""
        let sessionID = payload["session_id"] as? String ?? ""
        // P5 review: the id becomes part of a decision FILE NAME — `../` would point outside the decisions folder.
        guard isSafeSessionID(sessionID) else { return nil }
        let env = obj["env"] as? [String: Any] ?? [:]
        let received = (obj["received_at"] as? String).flatMap(Self.iso.date(from:)) ?? Date(timeIntervalSince1970: 0)
        var e = Event(receivedAt: received, name: Event.Name(rawValue: rawName) ?? .other, rawName: rawName, sessionID: sessionID,
                      terminal: Terminal())
        e.requestID = obj["request_id"] as? String
        if let a = obj["agent"] as? String { e.agent = AgentKind(rawValue: a) ?? .claude }
        e.cwd = payload["cwd"] as? String
        e.transcriptPath = payload["transcript_path"] as? String
        e.toolName = payload["tool_name"] as? String
        e.toolInputSummary = (payload["tool_input"] as? [String: Any]).flatMap(summary(ofToolInput:))
        e.notificationType = payload["notification_type"] as? String
        e.message = payload["message"] as? String
        e.prompt = payload["prompt"] as? String
        e.dropped = (payload["xfinder_dropped"] as? Bool) ?? false
        if let p = env["ppid"] as? Int, p > 0 { e.agentPID = Int32(p) }
        e.terminal = Terminal(bundleID: nonEmpty(env["bundle_id"]), termProgram: nonEmpty(env["term_program"]),
                              tty: nonEmpty(env["tty"]), itermSession: nonEmpty(env["iterm_session"]),
                              tmuxPane: nonEmpty(env["tmux_pane"]), weztermPane: nonEmpty(env["wezterm_pane"]),
                              termSession: nonEmpty(env["term_session"]), entrypoint: nonEmpty(env["entrypoint"]))
        return e
    }

    /// A session id that may become part of a file name: letters, digits, `-`, `_`; 1…128 characters. Claude Code and
    /// Codex hand out UUIDs; anything else is not a session this app will write a decision for.
    static func isSafeSessionID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 128 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func parse(jsonl: String) -> [Event] {
        jsonl.split(separator: "\n", omittingEmptySubsequences: true).compactMap { parse(line: String($0)) }
    }

    /// The one field of a tool's input a person needs to judge a permission request, on one line, cut at 160.
    static func summary(ofToolInput input: [String: Any]) -> String? {
        for key in ["command", "file_path", "path", "pattern", "url", "query", "prompt", "description"] {
            if let s = input[key] as? String, !s.isEmpty {
                let one = s.replacingOccurrences(of: "\n", with: " ⏎ ")
                return one.count > 160 ? String(one.prefix(160)) + "…" : one
            }
        }
        return nil
    }

    private static func nonEmpty(_ v: Any?) -> String? {
        guard let s = v as? String, !s.isEmpty else { return nil }
        return s
    }

    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()

    /// The day file a hook line lands in (UTC, like the hook's `date -u`).
    static func eventsFileName(for date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return "events-\(f.string(from: date)).jsonl"
    }
}

/// One agent session (Claude Code, Codex, OpenCode) as the notch shows it.
struct AgentSession: Equatable, Identifiable {
    enum Status: Equatable {
        /// Between a prompt and the next Stop: thinking, or running the named tool.
        case running(tool: String?)
        /// Stopped after an answer, or a `Notification` said it is idle: the person's turn.
        case waitingForInput
        /// A `PermissionRequest` nobody has answered yet — the hook is blocking on XFinder's decision file.
        case waitingForPermission(PendingPermission)
        /// `SessionEnd`, or the `claude` process is gone.
        case ended
    }

    struct PendingPermission: Equatable {
        var requestID: String
        var toolName: String
        var summary: String?
        var since: Date
    }

    /// The agent's own session id (what a decision file and a resume command are named after).
    var id: String
    var agent: AgentKind = .claude
    /// Unique across agents — two tools could in principle hand out the same id; a list keys on this.
    var listID: String { "\(agent.rawValue):\(id)" }
    var cwd: String?
    var transcriptPath: String?
    var startedAt: Date
    var updatedAt: Date
    var status: Status
    var lastTool: String?
    var lastPrompt: String?
    var agentPID: Int32?
    var terminal: AgentEvents.Terminal
    var eventCount: Int
    /// A conversation title when the agent has one (OpenCode does; Claude Code and Codex hooks carry none).
    var title: String? = nil
    /// `true` once something asked for the person: the badge and the live activity count these.
    var needsYou: Bool {
        switch status { case .waitingForInput, .waitingForPermission: return true; default: return false }
    }
    /// What to call it: the agent's own title when it has one, else the folder's name (Claude Code and Codex hooks
    /// carry no session title).
    var displayName: String {
        if let title, !title.isEmpty { return title }
        guard let cwd, !cwd.isEmpty else { return String(id.prefix(8)) }
        return (cwd as NSString).lastPathComponent
    }
}

/// The rules: a stream of events → sessions in display order. Pure, so the state machine is tested
/// without a file or a process.
enum AgentSessionRules {
    /// A session with no event for this long and no known live process is treated as ended.
    static let staleAfter: TimeInterval = 15 * 60
    /// Ended sessions older than this are not listed at all.
    static let keepEndedFor: TimeInterval = 60 * 60

    static func sessions(from events: [AgentEvents.Event], now: Date,
                         answered: Set<String> = [],
                         isAlive: (Int32) -> Bool) -> [AgentSession] {
        var byID: [String: AgentSession] = [:]
        var order: [String] = []
        for e in events.sorted(by: { $0.receivedAt < $1.receivedAt }) {
            let key = "\(e.agent.rawValue):\(e.sessionID)"      // P5: one session per (agent, id)
            var s = byID[key] ?? {
                order.append(key)
                return AgentSession(id: e.sessionID, agent: e.agent, cwd: e.cwd, transcriptPath: e.transcriptPath,
                                    startedAt: e.receivedAt, updatedAt: e.receivedAt, status: .running(tool: nil),
                                    lastTool: nil, lastPrompt: nil, agentPID: e.agentPID, terminal: e.terminal, eventCount: 0)
            }()
            s.eventCount += 1
            s.updatedAt = max(s.updatedAt, e.receivedAt)
            if let c = e.cwd { s.cwd = c }
            if let t = e.transcriptPath { s.transcriptPath = t }
            if let p = e.agentPID { s.agentPID = p }
            if e.terminal != AgentEvents.Terminal() { s.terminal = e.terminal }
            switch e.name {
            case .sessionStart:
                s.status = .running(tool: nil)
            case .userPromptSubmit:
                s.lastPrompt = e.prompt
                s.status = .running(tool: nil)
            case .preToolUse:
                s.lastTool = e.toolName
                // A tool starting means the request before it (if any) was answered, in the terminal or by us.
                s.status = .running(tool: e.toolName)
            case .postToolUse, .postToolUseFailure:
                s.status = .running(tool: nil)
            case .permissionRequest:
                let rid = e.requestID ?? ""
                if answered.contains(rid) { s.status = .running(tool: e.toolName) }
                else {
                    s.status = .waitingForPermission(.init(requestID: rid, toolName: e.toolName ?? "?",
                                                           summary: e.toolInputSummary, since: e.receivedAt))
                }
            case .permissionDenied:
                s.status = .running(tool: nil)
            case .notification:
                switch e.notificationType {
                case "idle_prompt"?: s.status = .waitingForInput
                case "permission_prompt"?:
                    // Claude Code's own prompt is on screen; only a PermissionRequest hook can answer it from here.
                    if case .waitingForPermission = s.status {} else { s.status = .waitingForInput }
                default: break
                }
            case .stop, .interrupt:
                s.status = .waitingForInput
            case .sessionEnd:
                s.status = .ended
            case .subagentStart, .subagentStop, .preCompact, .postCompact, .messageDisplay, .stopFailure, .other:
                break
            }
            byID[key] = s
        }
        // Liveness and staleness, after the replay: a dead process ends the session whatever the log says.
        var out: [AgentSession] = []
        for id in order {
            guard var s = byID[id] else { continue }
            if s.status != .ended {
                if let pid = s.agentPID, !isAlive(pid) { s.status = .ended }
                else if s.agentPID == nil, now.timeIntervalSince(s.updatedAt) > staleAfter { s.status = .ended }
            }
            if s.status == .ended, now.timeIntervalSince(s.updatedAt) > keepEndedFor { continue }
            out.append(s)
        }
        return out.sorted(by: displayOrder)
    }

    /// Permission requests first (oldest first — the one that has waited longest), then sessions waiting for
    /// input, then running ones (most recent activity first), ended last.
    static func displayOrder(_ a: AgentSession, _ b: AgentSession) -> Bool {
        func rank(_ s: AgentSession) -> Int {
            switch s.status {
            case .waitingForPermission: return 0
            case .waitingForInput: return 1
            case .running: return 2
            case .ended: return 3
            }
        }
        let ra = rank(a), rb = rank(b)
        if ra != rb { return ra < rb }
        if case .waitingForPermission(let pa) = a.status, case .waitingForPermission(let pb) = b.status { return pa.since < pb.since }
        return a.updatedAt > b.updatedAt
    }

    /// The store key for a status line (the view wraps it in `L10n.t`).
    static func statusKey(_ s: AgentSession.Status) -> String {
        switch s {
        case .running(let tool): return tool == nil ? "Đang suy nghĩ" : "Đang chạy "
        case .waitingForInput: return "Đang chờ bạn"
        case .waitingForPermission: return "Chờ bạn duyệt"
        case .ended: return "Đã kết thúc"
        }
    }
}
