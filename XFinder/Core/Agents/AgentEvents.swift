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
        /// P12.3 — `StopFailure`'s `error` (rate_limit, overloaded, authentication_failed…).
        var errorType: String?
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
        /// P6 — where a reply can be typed: kitty's window id and listen socket, tmux's whole `$TMUX` value.
        var kittyWindowID: String?
        var kittyListenOn: String?
        var tmuxEnv: String?
        /// P7a — the agent runs as XFinder's own child with no terminal (the hook saw `XFINDER_WINDOWLESS=1`).
        var windowless: Bool = false
    }

    // MARK: - Parsing

    static let maxPayloadBytes = 262_144

    /// One JSONL line → an event, or nil for a blank / unparseable / payload-less line. Unknown fields are
    /// ignored; an unknown `hook_event_name` becomes `.other` with `rawName` kept.
    static func parse(line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return parse(lineData: Data(trimmed.utf8))
    }

    /// The same, straight from the bytes of one line (no `String` round trip). JSONSerialization skips surrounding
    /// whitespace itself.
    static func parse(lineData data: Data) -> Event? {
        guard !data.isEmpty,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return nil }
        let rawName = payload["hook_event_name"] as? String ?? ""
        let sessionID = payload["session_id"] as? String ?? ""
        // P5 review: the id becomes part of a decision FILE NAME — `../` would point outside the decisions folder.
        guard isSafeSessionID(sessionID) else { return nil }
        let env = obj["env"] as? [String: Any] ?? [:]
        let received = (obj["received_at"] as? String).flatMap(Self.timestamp(_:)) ?? Date(timeIntervalSince1970: 0)
        var e = Event(receivedAt: received, name: Event.Name(rawValue: rawName) ?? .other, rawName: rawName, sessionID: sessionID,
                      terminal: Terminal())
        e.requestID = obj["request_id"] as? String
        if let a = obj["agent"] as? String { e.agent = AgentKind(rawValue: a) ?? .claude }
        e.cwd = payload["cwd"] as? String
        e.transcriptPath = payload["transcript_path"] as? String
        e.toolName = payload["tool_name"] as? String
        e.toolInputSummary = (payload["tool_input"] as? [String: Any]).flatMap(summary(ofToolInput:))
        e.notificationType = payload["notification_type"] as? String
        if e.name == .stopFailure { e.errorType = payload["error"] as? String }
        e.message = payload["message"] as? String
        e.prompt = payload["prompt"] as? String
        e.dropped = (payload["xfinder_dropped"] as? Bool) ?? false
        if let p = env["ppid"] as? Int, p > 0 { e.agentPID = Int32(p) }
        e.terminal = Terminal(bundleID: nonEmpty(env["bundle_id"]), termProgram: nonEmpty(env["term_program"]),
                              tty: nonEmpty(env["tty"]), itermSession: nonEmpty(env["iterm_session"]),
                              tmuxPane: nonEmpty(env["tmux_pane"]), weztermPane: nonEmpty(env["wezterm_pane"]),
                              termSession: nonEmpty(env["term_session"]), entrypoint: nonEmpty(env["entrypoint"]),
                              kittyWindowID: nonEmpty(env["kitty_window"]), kittyListenOn: nonEmpty(env["kitty_listen_on"]),
                              tmuxEnv: nonEmpty(env["tmux"]), windowless: env["windowless"] as? String == "1")
        return e
    }

    /// A session id that may become part of a file name: letters, digits, `-`, `_`; 1…128 characters. Claude Code and
    /// Codex hand out UUIDs; anything else is not a session this app will write a decision for.
    static func isSafeSessionID(_ s: String) -> Bool {
        // Bytes, not Characters: every non-ASCII byte fails, so Unicode letters/digits are refused as before.
        !s.isEmpty && s.utf8.count <= 128 && s.utf8.allSatisfy { b in
            (0x30...0x39).contains(b) || (0x41...0x5A).contains(b) || (0x61...0x7A).contains(b) || b == 0x2D || b == 0x5F
        }
    }

    static func parse(jsonl: String) -> [Event] {
        parse(jsonl: Data(jsonl.utf8))
    }

    /// A day file's bytes → events, one line at a time. Each line's Foundation objects are released before the next
    /// (2026-10-25: today + yesterday = 70 MB / 38 632 lines held 305 MB and 4,3 s at launch without the pool and
    /// with `ISO8601DateFormatter` per line; this path measures ~0,6 s / ~50 MB on the same files).
    static func parse(jsonl data: Data) -> [Event] {
        // Line bounds by `memchr` (a byte loop over `Data` was ~18 % of the parse, sampled).
        var bounds: [Range<Int>] = []
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let rest = raw.count - offset
                let end = memchr(base + offset, 0x0A, rest).map { $0 - UnsafeMutableRawPointer(mutating: base) } ?? raw.count
                if end > offset { bounds.append(offset..<end) }
                offset = end + 1
            }
        }
        var events: [Event] = []
        events.reserveCapacity(bounds.count)
        let origin = data.startIndex
        for r in bounds {
            let line = data[(origin + r.lowerBound)..<(origin + r.upperBound)]
            if let e = autoreleasepool(invoking: { parse(lineData: line) }) { events.append(e) }
        }
        return events
    }

    /// `received_at` as the hook writes it (`date -u +%Y-%m-%dT%H:%M:%SZ`, exactly 20 ASCII bytes) by arithmetic —
    /// `ISO8601DateFormatter` costs ~57 µs a line (measured, 26 511 lines = 1,5 s). Anything else (fractional seconds,
    /// an offset, an older writer) falls back to the formatter. A day past the month's end (02-30) needs no check: the
    /// formatter rolls it over and `daysFromCivil` is linear in the day, so both give 03-02 (measured).
    static func timestamp(_ s: String) -> Date? {
        let b = Array(s.utf8)
        guard b.count == 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A, b[19] == 0x5A
        else { return iso.date(from: s) }
        func num(_ from: Int, _ len: Int) -> Int? {
            var v = 0
            for i in from..<(from + len) {
                let d = Int(b[i]) - 48
                guard (0...9).contains(d) else { return nil }
                v = v * 10 + d
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let h = num(11, 2), let mi = num(14, 2),
              let sec = num(17, 2), (1...12).contains(mo), (1...31).contains(d), h < 24, mi < 60,
              sec < 60
        else { return iso.date(from: s) }
        let days = daysFromCivil(year: y, month: mo, day: d)
        return Date(timeIntervalSince1970: TimeInterval(days * 86_400 + h * 3_600 + mi * 60 + sec))
    }

    /// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's `days_from_civil`).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
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

    /// The day file a hook line lands in (UTC, like the hook's `date -u`). Arithmetic, not a `DateFormatter`: this runs
    /// on every coalesced hook event (sampled 2026-10-26: 475 of 935 busy main-thread samples were formatter set-up here).
    static func eventsFileName(for date: Date) -> String {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let days = Int((seconds / 86_400).rounded(.down))
        let (y, m, d) = civilFromDays(days)
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : String(v) }
        return "events-\(y)-\(two(m))-\(two(d)).jsonl"
    }

    /// Proleptic Gregorian date of a day count since 1970-01-01 (Howard Hinnant's `civil_from_days`; the inverse of
    /// `daysFromCivil`).
    static func civilFromDays(_ z: Int) -> (year: Int, month: Int, day: Int) {
        let z = z + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// Day files the hook wrote more than `keepDays` days ago. Nothing ever removed them: measured 2026-10-23, 10 days
    /// of Claude Code events were 62 MB on this Mac (the reference app's changelog reports gigabytes). Only names of the
    /// exact `events-YYYY-MM-DD.jsonl` shape are ever returned; the monitor reads just today and yesterday.
    static let keepDays = 7
    static func expiredEventFiles(_ names: [String], now: Date, keepDays: Int = keepDays) -> [String] {
        let cutoff = eventsFileName(for: now.addingTimeInterval(-Double(keepDays) * 86_400))
        return names.filter { name in
            name.count == cutoff.count && name.hasPrefix("events-") && name.hasSuffix(".jsonl")
                && name.dropFirst(7).prefix(10).allSatisfy({ $0.isNumber || $0 == "-" }) && name < cutoff
        }
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
    /// P6 — a dialog is on the terminal (Claude Code's `permission_prompt` / `elicitation_dialog` notification) and nothing
    /// has happened since: typing a reply would answer it.
    var dialogOnScreen: Bool = false
    /// P6 — the agent asked a multiple-choice question (`AskUserQuestion` started, not finished): typing would pick an option.
    var questionPending: Bool = false
    /// P12 — the last turn stopped at a usage limit (Claude Code `StopFailure` `rate_limit`, Codex `usageLimitExceeded`) and
    /// nothing has happened since. Cleared by the next prompt or tool, or when Claude Code resumes on its own.
    var limitStop: LimitStop? = nil
    struct LimitStop: Equatable {
        /// The agent's own code (`rate_limit`, `usageLimitExceeded`).
        var reason: String
        var since: Date
    }
    /// The stop only means something while the session waits for the person: a permission request, a running tool or an
    /// end outranks it (P12 review — a stale stop hid a live permission request and silenced its notice). Every reader of
    /// `limitStop` (row, notice, handoff note) goes through this.
    var isLimitStopped: Bool { limitStop != nil && status == .waitingForInput }
    /// P7a — XFinder hosts this session's process right now (a windowless session): a reply goes to its stdin. Set only
    /// by the merge with `WindowlessSessionManager`'s live records, never by a hook line.
    var hostedByXFinder: Bool = false
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
    /// What an EMPTY Agents page says, so it never stays silent about why (owner, 2026-10-14: OpenCode was running in
    /// kitty, the notch showed nothing, and the only line on the page talked about a hook OpenCode does not use — the
    /// real reason was that both switches were off). nil ⇒ everything is connected and there simply is no session.
    static func emptyReasonKey(enabled: Bool, hookInstalled: Bool, openCodeOn: Bool, openCodeMissing: Bool) -> String? {
        if !enabled { return "Agent AI đang tắt — bật ở trang Agent AI." }
        if openCodeOn && openCodeMissing { return "Đã bật OpenCode nhưng không tìm thấy lệnh opencode." }
        if !hookInstalled && !openCodeOn {
            return "Chưa nối agent nào — cài hook cho Claude Code / Codex hoặc bật OpenCode ở trang Agent AI."
        }
        return nil
    }
    static let emptyReasonKeys = [
        "Agent AI đang tắt — bật ở trang Agent AI.",
        "Đã bật OpenCode nhưng không tìm thấy lệnh opencode.",
        "Chưa nối agent nào — cài hook cho Claude Code / Codex hoặc bật OpenCode ở trang Agent AI.",
    ]

    // MARK: - Presentation (OneNotch / Notch Crew, measured 2026-10-14)

    /// What a session is doing, in the words the notch shows. OneNotch's pet has the phases idle · thinking · working ·
    /// waiting · done · error; XFinder's events give thinking (running, no tool), working (running a tool), waiting
    /// (a permission or a question), your turn (stopped after an answer) and ended.
    enum Activity: Int, Comparable, Sendable {
        case ended = 0, yourTurn, thinking, working, waiting
        static func < (a: Activity, b: Activity) -> Bool { a.rawValue < b.rawValue }
        /// The activity grid runs for these — something is happening, or someone must act.
        var isBusy: Bool { self == .thinking || self == .working || self == .waiting }
    }

    static func activity(of s: AgentSession) -> Activity {
        if s.isLimitStopped { return .yourTurn }
        switch s.status {
        // AskUserQuestion arrives as a running tool, but it is the person who must act.
        case .running(let tool): return s.questionPending ? .waiting : (tool == nil ? .thinking : .working)
        case .waitingForPermission: return .waiting
        // A question or a dialog on screen needs an answer; a plain finished turn is only "your turn".
        case .waitingForInput: return (s.questionPending || s.dialogOnScreen) ? .waiting : .yourTurn
        case .ended: return .ended
        }
    }

    /// The collapsed wing for every live session at once: ONE indicator showing the most urgent activity (OneNotch folds
    /// many sessions into one pet; Notch Crew names who is "waiting on you"), the agents involved most-urgent first, at
    /// most two drawn, and the counts behind them.
    struct WingSummary: Equatable, Sendable {
        var agents: [AgentKind]
        var activity: Activity
        var live: Int
        var waiting: Int
    }

    static func wingSummary(_ sessions: [AgentSession]) -> WingSummary? {
        let live = sessions.filter { activity(of: $0) != .ended }
        guard !live.isEmpty else { return nil }
        let ranked = live.sorted { a, b in
            let x = activity(of: a), y = activity(of: b)
            return x != y ? x > y : a.updatedAt > b.updatedAt
        }
        var agents: [AgentKind] = []
        for s in ranked where !agents.contains(s.agent) { agents.append(s.agent) }
        return WingSummary(agents: Array(agents.prefix(2)), activity: activity(of: ranked[0]),
                           live: live.count, waiting: live.filter { activity(of: $0) == .waiting }.count)
    }

    /// The wing's spoken label ends with one of these (after the agents' names).
    static func wingLabelKey(_ a: Activity) -> String {
        switch a {
        case .waiting: return " đang chờ bạn"
        case .working, .thinking: return " đang chạy"
        case .yourTurn: return " đã xong — tới lượt bạn"
        case .ended: return " đã dừng"
        }
    }
    static let wingLabelKeys = [" đang chờ bạn", " đang chạy", " đã xong — tới lượt bạn", " đã dừng"]

    /// The row's status word, by activity — "Tới lượt bạn" for a finished turn, "Đang chờ bạn" only when the person
    /// must answer something (the wing already told them apart; the row and the header said "waiting" for both).
    static func rowStatusKey(_ s: AgentSession) -> String {
        if s.isLimitStopped { return "Chạm giới hạn" }
        switch activity(of: s) {
        case .yourTurn: return "Tới lượt bạn"
        case .waiting:
            if case .waitingForPermission = s.status { return statusKey(s.status) }
            return "Đang chờ bạn"
        default: return statusKey(s.status)
        }
    }

    /// The tool name of Claude Code's multiple-choice question.
    static let questionTool = "AskUserQuestion"
    /// A session with no event for this long and no known live process is treated as ended.
    static let staleAfter: TimeInterval = 15 * 60
    /// Ended sessions older than this are not listed at all.
    static let keepEndedFor: TimeInterval = 60 * 60

    /// The replay of events no longer held in memory. A tail keeps only its newest `AgentSessionMonitor` window of
    /// events and folds what it trims off the front into this (measured 2026-10-25: 20 000 kept events held ~25 MB —
    /// a 476-byte `Event` each plus ~5 strings — while the list only ever needed the folded state per session).
    struct ReplaySeed: Equatable {
        var byID: [String: AgentSession] = [:]
        var order: [String] = []
    }

    /// P5: one session per (agent, id).
    static func sessionKey(_ e: AgentEvents.Event) -> String { "\(e.agent.rawValue):\(e.sessionID)" }

    /// Replays `events` (oldest first) on top of `seed`. Which requests XFinder answered is NOT part of the replay —
    /// `sessions(from:seed:…)` applies it at the end, so a request folded before its answer arrived is still caught.
    static func fold(_ events: [AgentEvents.Event], into seed: inout ReplaySeed) {
        for e in events.sorted(by: { $0.receivedAt < $1.receivedAt }) { apply(e, to: &seed) }
    }

    /// The seed without the sessions the list will never show again: ended (or dead, or silent with no process) for
    /// longer than `keepEndedFor`. A session that still has an event in the kept window (`keep`) is never dropped —
    /// the window's events would otherwise start it over with a new `startedAt`.
    static func pruned(_ seed: ReplaySeed, now: Date, keep: Set<String>, isAlive: (Int32) -> Bool) -> ReplaySeed {
        var out = ReplaySeed()
        for key in seed.order {
            guard let s = seed.byID[key] else { continue }
            let old = now.timeIntervalSince(s.updatedAt) > keepEndedFor
            let over = s.status == .ended || s.agentPID.map { !isAlive($0) } ?? true
            if old && over && !keep.contains(key) { continue }
            out.byID[key] = s
            out.order.append(key)
        }
        return out
    }

    static func sessions(from events: [AgentEvents.Event], seed: ReplaySeed = ReplaySeed(), now: Date,
                         answered: Set<String> = [],
                         isAlive: (Int32) -> Bool) -> [AgentSession] {
        var state = seed
        fold(events, into: &state)
        // Liveness and staleness, after the replay: a dead process ends the session whatever the log says.
        var out: [AgentSession] = []
        for id in state.order {
            guard var s = state.byID[id] else { continue }
            // A request XFinder answered: the hook is past it, the tool is about to run.
            if case .waitingForPermission(let p) = s.status, answered.contains(p.requestID) {
                s.status = .running(tool: p.toolName)
            }
            if s.status != .ended {
                if let pid = s.agentPID, !isAlive(pid) { s.status = .ended }
                else if s.agentPID == nil, now.timeIntervalSince(s.updatedAt) > staleAfter { s.status = .ended }
            }
            if s.status == .ended, now.timeIntervalSince(s.updatedAt) > keepEndedFor { continue }
            out.append(s)
        }
        return out.sorted(by: displayOrder)
    }

    private static func apply(_ e: AgentEvents.Event, to state: inout ReplaySeed) {
        let key = sessionKey(e)
        if state.byID[key] == nil { state.order.append(key) }
        var s = state.byID[key] ?? AgentSession(id: e.sessionID, agent: e.agent, cwd: e.cwd, transcriptPath: e.transcriptPath,
                                                startedAt: e.receivedAt, updatedAt: e.receivedAt, status: .running(tool: nil),
                                                lastTool: nil, lastPrompt: nil, agentPID: e.agentPID, terminal: e.terminal,
                                                eventCount: 0)
        s.eventCount += 1
        s.updatedAt = max(s.updatedAt, e.receivedAt)
        if let c = e.cwd { s.cwd = c }
        if let t = e.transcriptPath { s.transcriptPath = t }
        if let p = e.agentPID { s.agentPID = p }
        if e.terminal != AgentEvents.Terminal() { s.terminal = e.terminal }
        // P12: the work went on — a prompt, a tool, a finished turn — so the limit no longer stops it.
        switch e.name {
        case .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .postToolUseFailure, .stop, .interrupt,
             .permissionRequest, .permissionDenied:
            s.limitStop = nil
        default: break
        }
        // P6: anything the person or the agent does next means the dialog / question on screen is gone.
        switch e.name {
        case .userPromptSubmit, .preToolUse, .postToolUse, .postToolUseFailure, .stop, .interrupt, .sessionEnd,
             .permissionDenied, .sessionStart, .stopFailure:
            s.dialogOnScreen = false
        default: break
        }
        switch e.name {
        case .userPromptSubmit, .postToolUse, .postToolUseFailure, .stop, .interrupt, .sessionEnd, .sessionStart, .stopFailure:
            s.questionPending = false
        case .preToolUse:
            s.questionPending = e.toolName == AgentSessionRules.questionTool
        default: break
        }
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
            s.status = .waitingForPermission(.init(requestID: e.requestID ?? "", toolName: e.toolName ?? "?",
                                                   summary: e.toolInputSummary, since: e.receivedAt))
        case .permissionDenied:
            s.status = .running(tool: nil)
        case .notification:
            switch e.notificationType {
            case "idle_prompt"?: s.status = .waitingForInput
            case "permission_prompt"?, "elicitation_dialog"?:
                // Claude Code's own prompt is on screen; only a PermissionRequest hook can answer it from here.
                if case .waitingForPermission = s.status {} else { s.status = .waitingForInput }
                s.dialogOnScreen = true
            // P12: Claude Code's own wait for a usage-limit reset (docs, v2.1.234+). "fired" = it continued the task;
            // "stale" = the reset happened while the Mac slept and it waits for Enter; "disabled" = it gave up waiting.
            case "quota_auto_resume_fired"?:
                s.limitStop = nil
                s.status = .running(tool: nil)
            case "quota_auto_resume_stale"?:
                s.limitStop = nil
            default: break
            }
        case .stop, .interrupt:
            s.status = .waitingForInput
        case .stopFailure:
            // It runs INSTEAD of Stop when a turn ends on an API error (docs) — ignoring it left the row "running"
            // until the 15-minute staleness rule. The turn is over either way; only `rate_limit` is a limit stop.
            s.status = .waitingForInput
            if AgentQuotaRules.isLimitStop(claudeError: e.errorType) {
                s.limitStop = AgentSession.LimitStop(reason: e.errorType ?? "", since: e.receivedAt)
            }
        case .sessionEnd:
            s.status = .ended
        case .subagentStart, .subagentStop, .preCompact, .postCompact, .messageDisplay, .other:
            break
        }
        state.byID[key] = s
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

    /// P10 — OneNotch's "Sort sessions by" (measured: priority "Needs attention first", recency, newestFirst, manual).
    /// Manual (drag to order) is not offered: it needs a stored order per session id that outlives the session.
    enum SortMode: String, CaseIterable, Sendable {
        case priority, recency, newest
        var labelKey: String {
            switch self {
            case .priority: return "Cần chú ý trước"
            case .recency: return "Hoạt động gần nhất"
            case .newest: return "Mở mới nhất"
            }
        }
        static func parse(_ raw: String?) -> SortMode { raw.flatMap(SortMode.init(rawValue:)) ?? .priority }
    }

    /// The list in the chosen order; `keepFinished == false` leaves ended sessions out (OneNotch: "Keep finished sessions
    /// visible in the AI session list").
    static func ordered(_ sessions: [AgentSession], mode: SortMode, keepFinished: Bool) -> [AgentSession] {
        let shown = keepFinished ? sessions : sessions.filter { $0.status != .ended }
        switch mode {
        case .priority: return shown.sorted(by: displayOrder)
        case .recency: return shown.sorted { $0.updatedAt > $1.updatedAt }
        case .newest: return shown.sorted { $0.startedAt > $1.startedAt }
        }
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

// MARK: - A usage limit read from the transcript

extension AgentSessionRules {
    /// A usage-limit refusal found in a Claude Code transcript.
    struct TranscriptLimit: Equatable, Sendable {
        var since: Date
        /// `quotaLimits.resetsAt` (epoch seconds) when the line carries it.
        var resetsAt: Date?
    }

    /// Claude Code writes a usage-limit refusal into its own transcript — an `assistant` line with `isApiErrorMessage`,
    /// `error: "rate_limit"` and `quotaLimits {status: "rejected", resetsAt, rateLimitType}` — but the desktop app runs no
    /// `StopFailure` hook for it. Measured 2026-10-14: the turn died at 13:41:29Z with exactly that line, and the hook log
    /// holds no event after the 13:41:28Z prompt (and no `StopFailure` all day). So the hook alone leaves the row
    /// "running" until the 15-minute staleness rule; this reads the transcript's tail instead.
    ///
    /// The LAST main-thread assistant line decides: a rejected `rate_limit` refusal means stopped at the limit; anything
    /// else after it — a real answer, or a different API error (review: a later `overloaded` must not keep an old
    /// refusal on screen) — means the session's state is no longer that refusal. Sidechain lines (a subagent's own
    /// turns) never decide it. A torn first line of the tail does not parse and is skipped.
    static func transcriptLimit(tail: String) -> TranscriptLimit? {
        var found: TranscriptLimit?
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("assistant"),
                  let d = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  d["type"] as? String == "assistant",
                  (d["isSidechain"] as? Bool) != true else { continue }
            let quota = d["quotaLimits"] as? [String: Any]
            let refused = d["isApiErrorMessage"] as? Bool == true && d["error"] as? String == "rate_limit"
                && (quota?["status"] as? String ?? "rejected") == "rejected"
            guard refused else { found = nil; continue }
            found = TranscriptLimit(since: transcriptDate(d["timestamp"] as? String) ?? .distantPast,
                                    resetsAt: (quota?["resetsAt"] as? Double).map { Date(timeIntervalSince1970: $0) })
        }
        return found
    }

    /// `2026-10-14T13:41:29.145Z`, with or without the fraction.
    static func transcriptDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// A running Claude Code session whose transcript ends in a refusal that came after (or with) its last hook event is
    /// stopped at the limit. A hook event after the refusal means the work went on, so the row is left alone.
    static func applyingTranscriptLimit(_ s: AgentSession, _ limit: TranscriptLimit?) -> AgentSession {
        guard let limit, s.agent == .claude, case .running = s.status,
              limit.since >= s.updatedAt.addingTimeInterval(-2) else { return s }
        var out = s
        out.status = .waitingForInput
        out.limitStop = AgentSession.LimitStop(reason: "rate_limit", since: limit.since)
        return out
    }

    /// Whether the monitor should look at a session's transcript now: a Claude Code session still "running" with no hook
    /// event for `quietFor` seconds (an active turn sends events; a refused one goes silent), and a transcript path that
    /// is a `.jsonl` inside `~/.claude/projects` — a hook line cannot steer the read to any other file. Both sides are
    /// resolved through symlinks first: a link inside `projects` cannot point the read elsewhere, and a `~/.claude` that
    /// is itself a link (dotfiles setups) still matches.
    static func shouldReadTranscript(_ s: AgentSession, now: Date, home: String, quietFor: TimeInterval = 3) -> Bool {
        guard s.agent == .claude, case .running = s.status, let path = s.transcriptPath,
              now.timeIntervalSince(s.updatedAt) >= quietFor else { return false }
        let root = URL(fileURLWithPath: home).appendingPathComponent(".claude/projects")
            .resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return resolved.hasPrefix(root) && resolved.hasSuffix(".jsonl")
    }
}
