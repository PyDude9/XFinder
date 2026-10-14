import Foundation

/// P6 (2026-10-14) — "Nhắn phiên": reply to an agent session from the notch. Pure (symlinked into the test package):
/// which way a message can travel, whether it may go now, and the exact command arguments.
///
/// Measured before a line was written (isolated processes only — never the person's own windows):
/// * **kitty 0.49.2** — `kitty @ --to <socket> send-text --match id:<window> --stdin` delivers the bytes exactly (the
///   argument form interprets Python escapes, so it is never used for text); `send-text '\r'` is Enter; targeting by window
///   id works while the window is unfocused or the instance hidden; no macOS permission is involved. A process inside a
///   kitty window sees `KITTY_WINDOW_ID`, `KITTY_LISTEN_ON`, `KITTY_PID`. `send-text` reports no error when nothing was
///   delivered, so the target is checked with `kitty @ ls --match id:<window>` first.
/// * **tmux 3.8** — `send-keys -t %N -l <text>` passes UTF-8 through untouched (a two-character `\n` stays two characters);
///   `send-keys Enter` sends CR. A pane sees `TMUX=<socket>,<pid>,<session>` and `TMUX_PANE=%N`. Pane ids are reused after
///   a pane dies, so the pane's tty is compared with the one the hook recorded before typing.
/// * **OpenCode 2.0.27** — `opencode api session.prompt --param sessionID=… -d '{"text":…,"delivery":"queue"}'` (flat body,
///   `delivery` ∈ steer | queue); a queued prompt waits in the session's inbox until the turn ends.
/// * **`Foundation.Process` decomposes non-ASCII arguments to NFD** (measured: "Sửa" passed as an argument reaches the child
///   as `53 75 cc 9b cc 89 61`; through stdin it stays `53 e1 bb ad 61`). So text never travels as an argument: tmux gets it
///   through `load-buffer -` (stdin) + `paste-buffer`, kitty through `send-text --stdin`, OpenCode as ASCII-only JSON
///   (`\uXXXX`), which no conversion can touch.
/// * **Neither `-l` nor `--stdin` filters control characters**: an ESC sequence in the text reaches the terminal live (it can
///   retitle it or move the cursor), so every message is cleaned here first, and folded to ONE line (a newline would press
///   Enter early in a TUI's input box).
/// * **Claude Code's messaging socket (`CLAUDE_CODE_MESSAGING_SOCKET`) is not used**: a message through it arrives as
///   "Message from @<another session>", which the receiving Claude is told to treat as a peer, not as the person — the wrong
///   meaning for "I reply to my session" — and its message-line format is not published.
/// * Terminal.app (`do script` — Automation-gated), iTerm2, WezTerm, Ghostty and Codex's `codex queue` were NOT measured, so
///   they get the honest fallback: the message is copied and the terminal brought forward.
enum AgentTalk {

    // MARK: - Route

    enum Route: Equatable, Sendable {
        /// kitty remote control: the listen socket and the window id the hook recorded.
        case kitty(socket: String, windowID: Int)
        /// tmux: the server socket (first field of `$TMUX`) and the pane id.
        case tmux(socket: String, pane: String)
        /// OpenCode's own API through the person's `opencode` binary.
        case opencode(sessionID: String)
        /// No measured way to type into this terminal: copy the text, bring the app forward (nil ⇒ nothing to bring forward).
        case copyAndActivate(bundleID: String?)
        /// P7a — XFinder hosts the session's process: the text goes to its stdin as a stream-json user turn.
        case windowless(sessionID: String)

        /// Typing into a terminal is blocked while a dialog or question is on screen; an API message is not typing.
        var typesIntoTerminal: Bool {
            switch self {
            case .kitty, .tmux: return true
            case .opencode, .copyAndActivate, .windowless: return false
            }
        }
    }

    /// The best measured route for a session. kitty and tmux need what the hook recorded; tmux wins over kitty because a
    /// tmux pane inside a kitty window is addressed by tmux (kitty's window holds the whole tmux client).
    static func route(for session: AgentSession) -> Route {
        if session.hostedByXFinder { return .windowless(sessionID: session.id) }
        // A windowless session XFinder no longer hosts (it restarted, the pipe is gone): nothing to type into, and its
        // recorded bundle id would be XFinder's own — copy only.
        if session.terminal.windowless { return .copyAndActivate(bundleID: nil) }
        if session.agent == .opencode, OpenCodeRules.isSessionID(session.id) { return .opencode(sessionID: session.id) }
        let t = session.terminal
        if let pane = t.tmuxPane, isTmuxPane(pane), let sock = tmuxSocket(fromTMUX: t.tmuxEnv) {
            return .tmux(socket: sock, pane: pane)
        }
        if let id = t.kittyWindowID.flatMap(Int.init), id > 0, let sock = kittySocket(listenOn: t.kittyListenOn) {
            return .kitty(socket: sock, windowID: id)
        }
        return .copyAndActivate(bundleID: t.bundleID)
    }

    /// `$TMUX` is `<socket path>,<server pid>,<session id>` (measured). nil unless the first field is an absolute path.
    static func tmuxSocket(fromTMUX tmux: String?) -> String? {
        guard let first = tmux?.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init),
              first.hasPrefix("/"), !first.contains("..") else { return nil }
        return first
    }

    static func isTmuxPane(_ s: String) -> Bool {
        s.hasPrefix("%") && s.count > 1 && s.count <= 12 && s.dropFirst().allSatisfy(\.isNumber)
    }

    /// `KITTY_LISTEN_ON` is `unix:<path>` for a socket (measured). Only a unix socket is accepted — a `tcp:` listener would
    /// let XFinder type into a terminal reached over the network.
    static func kittySocket(listenOn: String?) -> String? {
        guard let l = listenOn, l.hasPrefix("unix:") else { return nil }
        let path = String(l.dropFirst("unix:".count))
        guard path.hasPrefix("/") || path.hasPrefix("@"), !path.contains("..") else { return nil }
        return l
    }

    // MARK: - May it go now?

    enum Decision: Equatable, Sendable {
        case sendNow
        /// The session is working: XFinder keeps the message and sends it when the session is waiting for the person.
        case queue
        /// Not now, and not later on its own: the reason is a store key.
        case blocked(reasonKey: String)
        /// A dialog or a multiple-choice question is on the terminal, so nothing may be TYPED (a keystroke would answer
        /// it — Enter on Claude's permission dialog is its highlighted default, "Yes"). The text is copied and the
        /// terminal brought forward instead, so the person answers the dialog and pastes. Not a dead end: the review
        /// found `dialogOnScreen` can outlive a dialog the person dismissed with Esc (Stop does not run on a user
        /// interrupt), and a bare refusal would then block every reply until they typed in the terminal.
        case copyInstead(reasonKey: String)
    }

    static func decision(for session: AgentSession, route: Route) -> Decision {
        switch session.status {
        case .ended:
            return .blocked(reasonKey: "Phiên đã kết thúc.")
        case .waitingForPermission:
            // A keystroke would answer the dialog; an API message is not a keystroke but still must not race the approval.
            return .blocked(reasonKey: "Phiên đang chờ bạn duyệt quyền — dùng Cho phép / Từ chối.")
        case .running:
            if case .opencode = route { return .sendNow }        // OpenCode queues it itself (delivery: queue)
            if case .windowless = route { return .queue }        // XFinder holds it until the turn's result line
            if case .copyAndActivate = route { return .sendNow } // the person pastes it themselves
            return .queue
        case .waitingForInput:
            if route.typesIntoTerminal, session.dialogOnScreen {
                return .copyInstead(reasonKey: "Trên terminal đang có một hộp thoại — trả lời nó ở terminal trước.")
            }
            if route.typesIntoTerminal, session.questionPending {
                return .copyInstead(reasonKey: "Agent đang hỏi bạn một câu có lựa chọn — trả lời ở terminal.")
            }
            return .sendNow
        }
    }

    /// A message held while the session worked: deliver it now? Only once the session waits for the person again, with no
    /// dialog or question on screen. `nil` = keep holding; a reason key = drop it and say why.
    static func shouldDeliverQueued(to session: AgentSession, route: Route) -> Bool? {
        switch decision(for: session, route: route) {
        case .sendNow: return true
        case .queue, .copyInstead: return nil       // a dialog/question on screen: keep holding, never type into it
        case .blocked:
            // Ended ⇒ the held message is dropped (the caller says so); a dialog/question ⇒ keep holding.
            return session.status == .ended ? false : nil
        }
    }

    // MARK: - Text

    static let maxLength = 4_000

    /// One clean line: every control character (C0, DEL, C1 — ESC included) removed, line breaks and tabs folded to one
    /// space, runs of spaces collapsed, trimmed, cut at `maxLength`. Empty ⇒ nil (nothing to send).
    static func clean(_ text: String) -> String? {
        var out = ""
        out.reserveCapacity(min(text.count, maxLength))
        var lastWasSpace = false
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isBreak = v == 0x0A || v == 0x0D || v == 0x09 || v == 0x2028 || v == 0x2029 || v == 0x85
            if isBreak || v == 0x20 {
                if !lastWasSpace && !out.isEmpty { out.append(" ") }
                lastWasSpace = true
                continue
            }
            if v < 0x20 || v == 0x7F || (0x80...0x9F).contains(v) { continue }
            out.unicodeScalars.append(scalar)
            lastWasSpace = false
        }
        while out.hasSuffix(" ") { out.removeLast() }
        if out.count > maxLength { out = String(out.prefix(maxLength)) }
        return out.isEmpty ? nil : out
    }

    // MARK: - Commands (argument arrays — no shell anywhere)

    static func tmuxCheckArguments(socket: String, pane: String) -> [String] {
        ["-S", socket, "display-message", "-p", "-t", pane, "#{pane_tty}"]
    }
    /// The text arrives on stdin (`-`): an argument would be decomposed to NFD by `Process`.
    static func tmuxLoadArguments(socket: String, buffer: String) -> [String] {
        ["-S", socket, "load-buffer", "-b", buffer, "-"]
    }
    /// `-d` deletes the buffer afterwards; `-p` brackets the paste only if the program asked for bracketed paste.
    static func tmuxPasteArguments(socket: String, pane: String, buffer: String) -> [String] {
        ["-S", socket, "paste-buffer", "-d", "-p", "-b", buffer, "-t", pane]
    }
    /// A buffer name of our own per send, so two sends never paste each other's text.
    static func tmuxBufferName(_ uuid: UUID) -> String { "xfinder-reply-" + uuid.uuidString.lowercased() }
    static func tmuxEnterArguments(socket: String, pane: String) -> [String] {
        ["-S", socket, "send-keys", "-t", pane, "Enter"]
    }

    static func kittyCheckArguments(socket: String, windowID: Int) -> [String] {
        ["@", "--to", socket, "ls", "--match", "id:\(windowID)"]
    }
    /// The text goes through stdin (`--stdin`): the argument form would interpret escapes.
    static func kittyTypeArguments(socket: String, windowID: Int) -> [String] {
        ["@", "--to", socket, "send-text", "--match", "id:\(windowID)", "--stdin"]
    }
    static func kittyEnterArguments(socket: String, windowID: Int) -> [String] {
        ["@", "--to", socket, "send-text", "--match", "id:\(windowID)", "--stdin"]
    }
    static let kittyEnterBytes = "\r"

    static func opencodePromptArguments(sessionID: String, text: String, queue: Bool) -> [String]? {
        guard OpenCodeRules.isSessionID(sessionID) else { return nil }
        let body = queue ? #"{"delivery":"queue","text":"# + asciiJSONString(text) + "}"
                         : #"{"text":"# + asciiJSONString(text) + "}"
        return ["api", "session.prompt", "--param", "sessionID=\(sessionID)", "-d", body]
    }

    /// A JSON string literal (with its quotes) whose every character is ASCII: `"`, `\` and controls escaped, everything
    /// above 0x7E written as `\uXXXX` UTF-16 units. A JSON parser turns it back into exactly the original scalars, and
    /// `Process` has nothing left to decompose.
    static func asciiJSONString(_ s: String) -> String {
        var out = "\""
        for unit in s.utf16 {
            switch unit {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x20...0x7E: out.unicodeScalars.append(Unicode.Scalar(UInt8(unit)))
            default: out += String(format: "\\u%04x", unit)
            }
        }
        return out + "\""
    }

    // MARK: - Target checks (is the pane / window still the session's?)

    /// tmux `#{pane_tty}` must be the tty the hook recorded for the agent — a reused pane id points at someone else.
    static func tmuxTargetMatches(paneTTY output: String, recordedTTY: String?) -> Bool {
        guard let recorded = recordedTTY, !recorded.isEmpty else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == recorded
    }

    /// `kitty @ ls --match id:N` JSON: the window must exist and one of its foreground processes must be the agent (or a
    /// descendant the hook could not see — then the window's own pid tree is not trusted and the check fails).
    /// Only `id` and `foreground_processes[].pid` are read; the window's environment, which `ls` also prints, is ignored.
    static func kittyTargetMatches(lsJSON data: Data, windowID: Int, agentPID: Int32?) -> Bool {
        guard let agentPID, agentPID > 1,
              let osWindows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return false }
        for os in osWindows {
            for tab in os["tabs"] as? [[String: Any]] ?? [] {
                for w in tab["windows"] as? [[String: Any]] ?? [] {
                    guard (w["id"] as? Int) == windowID else { continue }
                    let fg = (w["foreground_processes"] as? [[String: Any]] ?? []).compactMap { $0["pid"] as? Int }
                    return fg.contains(Int(agentPID))
                }
            }
        }
        return false
    }

    // MARK: - Words for the page

    /// What the send button says for a route (a store key).
    static func routeLabelKey(_ route: Route) -> String {
        switch route {
        case .kitty: return "Gửi vào kitty"
        case .tmux: return "Gửi vào tmux"
        case .opencode: return "Gửi qua OpenCode"
        case .copyAndActivate(let bid): return bid == nil ? "Chép tin nhắn" : "Chép và mở terminal"
        case .windowless: return "Gửi tin"
        }
    }

    /// What the send button says for a session: the route's word, unless the text will be copied instead of typed —
    /// then the button must say so (a "Gửi vào kitty" button that copies would promise what it does not do).
    static func sendLabelKey(for session: AgentSession) -> String {
        let route = self.route(for: session)
        if case .copyInstead = decision(for: session, route: route) {
            return routeLabelKey(.copyAndActivate(bundleID: session.terminal.bundleID))
        }
        return routeLabelKey(route)
    }

    /// Every key this file can hand to `L10n.t` through a variable — the test resolves them all against the store.
    static let reasonKeys: [String] = [
        "Phiên đã kết thúc.",
        "Phiên đang chờ bạn duyệt quyền — dùng Cho phép / Từ chối.",
        "Trên terminal đang có một hộp thoại — trả lời nó ở terminal trước.",
        "Agent đang hỏi bạn một câu có lựa chọn — trả lời ở terminal.",
    ]
    static let labelKeys: [String] = ["Gửi vào kitty", "Gửi vào tmux", "Gửi qua OpenCode", "Chép tin nhắn", "Chép và mở terminal", "Gửi tin"]
    /// Every outcome line `AgentTalkSender` can show (it lives in an AppKit file the test package cannot compile, so the
    /// list is here and a test reads the sender's source to prove nothing it says is missing from it).
    static let statusKeys: [String] = [
        "Cửa sổ kitty của phiên không còn chạy agent — không gõ vào đâu cả.",
        "Không tìm thấy lệnh kitty.",
        "Không tìm thấy lệnh opencode.",
        "Không tìm thấy lệnh tmux.",
        "OpenCode không nhận tin.",
        "OpenCode đã xếp tin vào hàng đợi của phiên.",
        "Phiên đã kết thúc — tin đang chờ chưa được gửi.",
        "Sẽ gửi khi phiên rảnh.",
        "kitty không cho điều khiển từ xa (cần allow_remote_control và listen_on trong kitty.conf).",
        "kitty không nhận chữ.",
        "kitty không nhận phím Enter.",
        "tmux không nhận chữ.",
        "tmux không nhận phím Enter.",
        "Ô tmux của phiên không còn — không gõ vào đâu cả.",
        "Đang gửi…",
        "Đã chép — dán (⌘V) vào terminal rồi bấm Enter.",
        "Đã chép — mở terminal của phiên, dán (⌘V) rồi bấm Enter.",
        "Đã gửi qua OpenCode.",
        "Đã gửi vào kitty.",
        "Đã gửi vào tmux.",
        "Đã huỷ tin đang chờ.",
        "Đã thay tin đang chờ — sẽ gửi khi phiên rảnh.",
        "Đã chép — trả lời hộp thoại ở terminal trước, rồi dán (⌘V) và bấm Enter.",
        "Cửa sổ kitty thôi chạy agent trước khi bấm Enter — chữ có thể còn ở dòng nhập, chưa gửi.",
        "Ô tmux đã đổi trước khi bấm Enter — chữ có thể còn ở dòng nhập, chưa gửi.",
        "Đã gửi tin.",
        "Phiên không cửa sổ đã dừng — tin chưa được gửi.",
    ]
}
