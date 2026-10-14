import Foundation

/// P7a (2026-10-14) — "Phiên không cửa sổ": a Claude Code session XFinder hosts itself, with no terminal window. Pure
/// (symlinked into the test package): the launch arguments, the stream it reads, the record it keeps, and the row the
/// notch shows. The process side is `WindowlessSessionManager`.
///
/// Measured before a line was written (Claude Code 2.1.296, this Mac):
/// * `claude -p --input-format stream-json --output-format stream-json --verbose --session-id <uuid>` with NO input
///   printed exactly one line — `{"type":"system","subtype":"ui_invalidate",…,"session_id":"<the uuid given>"}` — and
///   exited 0; no transcript was written and no model was asked. So XFinder can fix the session id up front, and the
///   stream carries line types the docs do not list: every unknown type is ignored, never an error.
/// * Notch Crew's windowless sessions are the same idea: its binary imports `NSTask` and `kill` and NO pseudo-terminal
///   function (`nm -u`), i.e. the agent's own CLI over plain pipes.
/// * Hooks still fire in `-p` mode unless `--bare` (docs), so a windowless session's permission requests reach the
///   notch card exactly like a terminal session's — when XFinder's hook is installed.
/// * An app launched by launchd has PATH `/usr/bin:/bin:/usr/sbin:/sbin`; the agent's own shell commands would then
///   miss Homebrew. `zsh -i -l -c 'env -0'` resolved the login environment in 0.47 s (28 variables, PATH with
///   /opt/homebrew/bin and ~/.local/bin, nothing printed before the list), so the child runs with that environment.
/// Every turn the person sends is a model turn on their plan; XFinder never sends one on its own here.
enum WindowlessRules {

    // MARK: - Launch

    /// The env var the child carries so XFinder's hook can tell a windowless session from a terminal one.
    static let markerVariable = "XFINDER_WINDOWLESS"

    /// Claude Code's streaming-input mode. `resume == false` fixes a new session's id; `true` reopens a stored one.
    /// nil when the id is not a UUID (it becomes a process argument).
    static func claudeArguments(sessionID: String, resume: Bool) -> [String]? {
        guard UUID(uuidString: sessionID) != nil else { return nil }
        return ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                resume ? "--resume" : "--session-id", sessionID]
    }

    /// One user turn on stdin (JSON, so no conversion can touch the text, and newlines are just text here — there is
    /// no Enter key to press early).
    static func userTurnLine(_ text: String) -> Data? {
        let obj: [String: Any] = ["type": "user", "message": ["role": "user", "content": text], "parent_tool_use_id": NSNull()]
        guard var data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
        data.append(0x0A)
        return data
    }

    /// The message a person may send: trimmed, at most `maxLength` characters, nil when empty. Line breaks are kept —
    /// the stream carries them as text.
    static let maxLength = 20_000
    static func cleanMessage(_ text: String) -> String? {
        var out = String(text.unicodeScalars.filter { s in
            let v = s.value
            return v == 0x0A || v == 0x09 || !(v < 0x20 || v == 0x7F || (0x80...0x9F).contains(v))
        })
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.count > maxLength { out = String(out.prefix(maxLength)) }
        return out.isEmpty ? nil : out
    }

    /// `env -0` output → a dictionary. Anything a startup file printed before the list (no `=`, or a newline inside the
    /// name) is dropped rather than turned into a variable.
    static func parseEnvironment(_ data: Data) -> [String: String] {
        var env: [String: String] = [:]
        for chunk in data.split(separator: 0, omittingEmptySubsequences: true) {
            guard let eq = chunk.firstIndex(of: UInt8(ascii: "=")) else { continue }
            let name = String(decoding: chunk[chunk.startIndex..<eq], as: UTF8.self)
            // Letters, digits and _ only: noise a startup file printed before the list (spaces, colons, a newline) is
            // never a variable name.
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { continue }
            env[name] = String(decoding: chunk[chunk.index(after: eq)...], as: UTF8.self)
        }
        return env
    }

    /// The child's environment: the person's login environment (else XFinder's own, with the usual tool folders added),
    /// plus the marker. Variables that would make the child think it runs inside another Claude Code are removed.
    static func childEnvironment(login: [String: String]?, fallback: [String: String], home: String) -> [String: String] {
        var env = login ?? fallback
        if login == nil {
            let extra = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin"]
            let path = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
            env["PATH"] = (extra.filter { !path.contains($0) } + path).joined(separator: ":")
        }
        for k in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT", "CLAUDE_CODE_MESSAGING_SOCKET",
                  "CLAUDE_CODE_MESSAGING_TOKEN", "__CFBundleIdentifier", "XPC_SERVICE_NAME", "TERM_PROGRAM", "TMUX",
                  "TMUX_PANE", "KITTY_WINDOW_ID", "KITTY_LISTEN_ON", "KITTY_PID", "ITERM_SESSION_ID", "TERM_SESSION_ID"] {
            env.removeValue(forKey: k)
        }
        env[markerVariable] = "1"
        return env
    }

    /// Where `claude` lives: the login PATH first, then the installer's usual places.
    static func claudeCandidates(path: String?, home: String) -> [String] {
        var out = (path ?? "").split(separator: ":").map { String($0) + "/claude" }
        out += [home + "/.local/bin/claude", home + "/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        var seen = Set<String>()
        return out.filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    // MARK: - The stream

    enum StreamEvent: Equatable, Sendable {
        case initialized(sessionID: String?, model: String?)
        case assistantText(String)
        case toolUse(String)
        case result(isError: Bool, text: String?, costUSD: Double?)
        case ignored
    }

    /// One stdout line → an event. Sub-agent messages (`parent_tool_use_id` set) and tool results are not shown.
    static func parse(line: String) -> StreamEvent {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = obj["type"] as? String else { return .ignored }
        switch type {
        case "system":
            guard obj["subtype"] as? String == "init" else { return .ignored }
            return .initialized(sessionID: obj["session_id"] as? String, model: obj["model"] as? String)
        case "assistant":
            if let parent = obj["parent_tool_use_id"], !(parent is NSNull) { return .ignored }
            guard let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] else { return .ignored }
            let texts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !texts.isEmpty { return .assistantText(texts) }
            if let tool = content.first(where: { $0["type"] as? String == "tool_use" })?["name"] as? String { return .toolUse(tool) }
            return .ignored
        case "result":
            return .result(isError: (obj["is_error"] as? Bool) ?? (obj["subtype"] as? String != "success"),
                           text: obj["result"] as? String, costUSD: obj["total_cost_usd"] as? Double)
        default:
            return .ignored
        }
    }

    // MARK: - The record

    struct Entry: Equatable, Sendable, Identifiable {
        enum Role: String, Sendable { case person, agent, note }
        var id: Int
        var role: Role
        var text: String
        var at: Date
    }

    enum Phase: Equatable, Sendable {
        /// Running, no message sent yet.
        case idle
        case working(tool: String?)
        /// The last turn ended; the session waits for the person.
        case waiting
        case ended(code: Int32?)
    }

    static let transcriptCap = 40
    static let entryCap = 4_000

    struct Record: Equatable, Sendable {
        var sessionID: String
        var cwd: String
        var startedAt: Date
        var updatedAt: Date
        var phase: Phase = .idle
        var transcript: [Entry] = []
        var model: String?
        /// Claude Code's own estimate for the process so far (`total_cost_usd`); not a bill.
        var costUSD: Double?
        var turns = 0
        var pid: Int32?
        var lastError: String?
        /// P12.2 (Codex) — the failed turn's `codexErrorInfo`; cleared when the next turn is sent or starts.
        var lastErrorCode: String?
        /// When that failure arrived — the stop's identity (P12 review: `updatedAt` moves on with any later event, and a
        /// stop whose time keeps changing is announced again on every rebuild).
        var lastErrorAt: Date?
        var nextEntryID = 0
        /// P11 — which agent the process is: Claude Code (stream-json) or Codex (`codex app-server` JSON-RPC).
        var agent: AgentKind = .claude
        /// P11 (Codex) — the app-server's thread id once `thread/start` answered; nil while the handshake runs.
        var threadID: String?
        /// P11 (Codex) — the turn in progress, for `turn/interrupt`.
        var activeTurnID: String?
        /// P11 (Codex) — an approval the app-server is waiting on (it arrives on the same pipe, no hook involved).
        var pendingApproval: PendingApproval?

        struct PendingApproval: Equatable, Sendable {
            var rawID: String
            var kind: CodexAppServer.ApprovalKind
            var summary: String?
            var legacy: Bool
            var since: Date
        }

        var isEnded: Bool { if case .ended = phase { return true }; return false }
        var lastAgentText: String? { transcript.last(where: { $0.role == .agent })?.text }
        var lastPersonText: String? { transcript.last(where: { $0.role == .person })?.text }

        mutating func append(_ role: Entry.Role, _ text: String, at: Date) {
            let t = text.count > WindowlessRules.entryCap ? String(text.prefix(WindowlessRules.entryCap)) + "…" : text
            if role == .agent, let last = transcript.last, last.role == .agent, last.text == t { return }
            transcript.append(Entry(id: nextEntryID, role: role, text: t, at: at))
            nextEntryID += 1
            if transcript.count > WindowlessRules.transcriptCap { transcript.removeFirst(transcript.count - WindowlessRules.transcriptCap) }
        }

        /// The person sent a turn.
        mutating func sent(_ text: String, at: Date) {
            guard !isEnded else { return }
            append(.person, text, at: at)
            phase = .working(tool: nil)
            lastErrorCode = nil; lastErrorAt = nil
            turns += 1
            updatedAt = at
        }

        mutating func apply(_ event: StreamEvent, at: Date) {
            guard !isEnded else { return }
            switch event {
            case .initialized(_, let model):
                if let model { self.model = model }
            case .assistantText(let t):
                append(.agent, t, at: at)
                if case .working = phase { phase = .working(tool: nil) }
            case .toolUse(let name):
                phase = .working(tool: name)
            case .result(let isError, let text, let cost):
                if isError { append(.note, text ?? "", at: at); lastError = text }
                if let cost { costUSD = cost }
                phase = .waiting
            case .ignored:
                return
            }
            updatedAt = at
        }

        /// P11 — a Codex app-server event (the handshake events are handled by the manager, which must write replies).
        mutating func applyCodex(_ event: CodexAppServer.Event, at: Date) {
            guard !isEnded else { return }
            switch event {
            case .threadStarted(let tid, let model):
                threadID = tid
                if let model { self.model = model }
            case .turnStarted(let turnID):
                activeTurnID = turnID
                lastErrorCode = nil; lastErrorAt = nil
                phase = .working(tool: nil)
            case .tool(let name):
                phase = .working(tool: name)
            case .agentMessage(let t):
                append(.agent, t, at: at)
                if case .working = phase { phase = .working(tool: nil) }
            case .approval(let raw, let kind, let summary, let legacy):
                pendingApproval = PendingApproval(rawID: raw, kind: kind, summary: summary, legacy: legacy, since: at)
            case .turnCompleted(let status, let error, let code):
                if let error, !error.isEmpty { append(.note, error, at: at); lastError = error }
                else if status == "failed" { lastError = status }
                lastErrorCode = status == "failed" ? code : nil
                lastErrorAt = lastErrorCode == nil ? nil : at
                activeTurnID = nil
                pendingApproval = nil
                phase = .waiting            // `sent` already counted the turn
            case .requestFailed(_, let message):
                append(.note, message, at: at)
                lastError = message
                // P12 review: a `turn/start` the server refused never gets a `turn/completed` — without this the row said
                // "working" forever and `deliver` refused every later message. A refused request while a turn RUNS
                // (an interrupt, say) leaves the turn alone.
                if case .working = phase, activeTurnID == nil, turns > 0 { phase = .waiting }
            case .error(let message):
                lastError = message
            case .initializeOK, .otherRequest, .ignored:
                return
            }
            updatedAt = at
        }

        /// The process ended (any reason). The conversation stays on disk; Claude Code can resume it.
        mutating func exited(code: Int32?, at: Date) {
            guard !isEnded else { return }
            phase = .ended(code: code)
            updatedAt = at
        }
    }

    // MARK: - The row

    /// A record as a notch row. Hook events for the same session id (when XFinder's hook is installed) are merged
    /// over it by the monitor; this is the row when there are none.
    static func session(for r: Record) -> AgentSession {
        var status: AgentSession.Status
        switch r.phase {
        case .idle, .waiting: status = .waitingForInput
        case .working(let tool): status = .running(tool: tool)
        case .ended: status = .ended
        }
        var terminal = AgentEvents.Terminal()
        terminal.windowless = true
        // P11: a Codex approval waits on the pipe — the row shows the same Allow / Deny card as a hook permission.
        if let p = r.pendingApproval, !r.isEnded {
            status = .waitingForPermission(AgentSession.PendingPermission(
                requestID: p.rawID, toolName: p.kind == .command ? "Bash" : "Edit", summary: p.summary, since: p.since))
        }
        var s = AgentSession(id: r.sessionID, agent: r.agent, cwd: r.cwd, transcriptPath: nil, startedAt: r.startedAt,
                             updatedAt: r.updatedAt, status: status, lastTool: { if case .working(let t) = r.phase { return t }; return nil }(),
                             lastPrompt: r.lastPersonText, agentPID: r.pid, terminal: terminal, eventCount: r.turns)
        s.hostedByXFinder = true
        // P12.2: a Codex turn that failed with usageLimitExceeded is a limit stop until the next turn.
        if case .waiting = r.phase, AgentQuotaRules.isLimitStop(codexCode: r.lastErrorCode) {
            s.limitStop = AgentSession.LimitStop(reason: r.lastErrorCode ?? "", since: r.lastErrorAt ?? r.updatedAt)
        }
        return s
    }

    /// Hook rows + XFinder's own records → one list. A hook row for a hosted session keeps its status (it alone knows a
    /// permission request is pending) unless the process has ended, and is marked hosted so a reply goes to its stdin.
    static func merged(hookSessions: [AgentSession], records: [Record]) -> [AgentSession] {
        var out = hookSessions
        for r in records {
            let row = session(for: r)
            if let i = out.firstIndex(where: { $0.listID == row.listID }) {
                out[i].hostedByXFinder = !r.isEnded
                out[i].terminal.windowless = true
                if r.isEnded { out[i].status = .ended }
                if out[i].cwd == nil { out[i].cwd = r.cwd }
                if out[i].limitStop == nil { out[i].limitStop = row.limitStop }
            } else {
                out.append(row)
            }
        }
        return out
    }

    // MARK: - Words for the page (store keys)

    static func phaseKey(_ p: Phase) -> String {
        switch p {
        case .idle: return "Đang chờ tin đầu tiên"
        case .working: return "Đang làm"
        case .waiting: return "Tới lượt bạn"
        case .ended: return "Đã dừng"
        }
    }

    /// Every key this file and `WindowlessSessionManager` hand to `L10n.t` through a variable.
    static let phaseKeys = ["Đang chờ tin đầu tiên", "Đang làm", "Tới lượt bạn", "Đã dừng"]
    static let errorKeys = [
        "Không tìm thấy lệnh claude.",
        "Thư mục không còn.",
        "Không chạy được claude.",
        "Phiên không cửa sổ đã dừng — tin chưa được gửi.",
        "Phiên này đang mở ở nơi khác — đóng nó trước rồi mở lại.",
    ]
}
