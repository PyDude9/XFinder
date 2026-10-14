import XCTest

/// P6 — replying to an agent session from the notch: which route, whether now, what exactly is typed.
final class AgentTalkTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ status: AgentSession.Status, agent: AgentKind = .claude, id: String = "019a-11",
                         terminal: AgentEvents.Terminal = .init(), pid: Int32? = 4242) -> AgentSession {
        AgentSession(id: id, agent: agent, cwd: "/w/app", transcriptPath: nil, startedAt: t0, updatedAt: t0, status: status,
                     lastTool: nil, lastPrompt: nil, agentPID: pid, terminal: terminal, eventCount: 1)
    }
    private let kittyTerm = AgentEvents.Terminal(bundleID: "net.kovidgoyal.kitty", tty: "/dev/ttys004",
                                                 kittyWindowID: "7", kittyListenOn: "unix:/tmp/kitty-13413")
    private let tmuxTerm = AgentEvents.Terminal(bundleID: "net.kovidgoyal.kitty", tty: "/dev/ttys009", tmuxPane: "%3",
                                                kittyWindowID: "7", kittyListenOn: "unix:/tmp/kitty-13413",
                                                tmuxEnv: "/private/tmp/tmux-502/default,812,0")

    // MARK: Route

    func testRoutesPreferTheAgentsOwnAPIThenTmuxThenKittyThenCopy() {
        XCTAssertEqual(AgentTalk.route(for: session(.waitingForInput, agent: .opencode, id: "ses_A1")), .opencode(sessionID: "ses_A1"))
        XCTAssertEqual(AgentTalk.route(for: session(.waitingForInput, terminal: tmuxTerm)),
                       .tmux(socket: "/private/tmp/tmux-502/default", pane: "%3"),
                       "tmux inside kitty: kitty's window holds the whole tmux client, so tmux addresses the pane")
        XCTAssertEqual(AgentTalk.route(for: session(.waitingForInput, terminal: kittyTerm)),
                       .kitty(socket: "unix:/tmp/kitty-13413", windowID: 7))
        let terminalApp = AgentEvents.Terminal(bundleID: "com.apple.Terminal", tty: "/dev/ttys001")
        XCTAssertEqual(AgentTalk.route(for: session(.waitingForInput, terminal: terminalApp)), .copyAndActivate(bundleID: "com.apple.Terminal"))
        XCTAssertEqual(AgentTalk.route(for: session(.waitingForInput)), .copyAndActivate(bundleID: nil))
    }

    func testOnlyAUnixKittySocketAndAnAbsoluteTmuxSocketAreAccepted() {
        XCTAssertNil(AgentTalk.kittySocket(listenOn: "tcp:localhost:12488"), "never type into a terminal reached over the network")
        XCTAssertNil(AgentTalk.kittySocket(listenOn: "unix:relative/sock"))
        XCTAssertNil(AgentTalk.kittySocket(listenOn: "unix:/tmp/../etc/x"))
        XCTAssertEqual(AgentTalk.kittySocket(listenOn: "unix:/tmp/kitty-1"), "unix:/tmp/kitty-1")
        XCTAssertNil(AgentTalk.tmuxSocket(fromTMUX: "relative,1,0"))
        XCTAssertNil(AgentTalk.tmuxSocket(fromTMUX: nil))
        XCTAssertFalse(AgentTalk.isTmuxPane("%"))
        XCTAssertFalse(AgentTalk.isTmuxPane("%1;rm"))
        XCTAssertTrue(AgentTalk.isTmuxPane("%12"))
        var bad = kittyTerm; bad.kittyListenOn = "tcp:localhost:1"
        XCTAssertEqual(AgentTalk.route(for: session(.waitingForInput, terminal: bad)), .copyAndActivate(bundleID: "net.kovidgoyal.kitty"))
    }

    // MARK: Decision

    func testNothingIsTypedWhileADialogOrQuestionIsOnScreen() {
        let route = AgentTalk.route(for: session(.waitingForInput, terminal: kittyTerm))
        var s = session(.waitingForInput, terminal: kittyTerm)
        XCTAssertEqual(AgentTalk.decision(for: s, route: route), .sendNow)
        s.dialogOnScreen = true
        guard case .copyInstead = AgentTalk.decision(for: s, route: route) else { return XCTFail("a dialog on screen: copy, never type") }
        s.dialogOnScreen = false; s.questionPending = true
        guard case .copyInstead = AgentTalk.decision(for: s, route: route) else { return XCTFail("a pending question: copy, never type") }
        let perm = session(.waitingForPermission(.init(requestID: "r", toolName: "Bash", summary: nil, since: t0)), terminal: kittyTerm)
        guard case .blocked = AgentTalk.decision(for: perm, route: route) else { return XCTFail("a permission request must block") }
        guard case .blocked = AgentTalk.decision(for: session(.ended, terminal: kittyTerm), route: route) else { return XCTFail("ended") }
    }

    /// The button must say what pressing it does: a kitty session with a dialog on screen gets "copy", not "send to kitty".
    func testTheSendButtonSaysCopyWhenTheTextWillBeCopied() {
        var s = session(.waitingForInput, terminal: kittyTerm)
        XCTAssertEqual(AgentTalk.sendLabelKey(for: s), "Gửi vào kitty")
        s.dialogOnScreen = true
        XCTAssertEqual(AgentTalk.sendLabelKey(for: s), "Chép và mở terminal")
        var noApp = AgentEvents.Terminal(tty: "/dev/ttys004", kittyWindowID: "7", kittyListenOn: "unix:/tmp/kitty-13413")
        noApp.bundleID = nil
        var q = session(.waitingForInput, terminal: noApp); q.questionPending = true
        XCTAssertEqual(AgentTalk.sendLabelKey(for: q), "Chép tin nhắn", "no terminal app to bring forward")
        let perm = session(.waitingForPermission(.init(requestID: "r", toolName: "Bash", summary: nil, since: t0)), terminal: kittyTerm)
        guard case .blocked = AgentTalk.decision(for: perm, route: AgentTalk.route(for: perm)) else {
            return XCTFail("a permission request stays blocked — the card answers it")
        }
    }

    func testAWorkingSessionQueuesTypingButNotTheAPIOrTheCopy() {
        let running = session(.running(tool: "Bash"), terminal: kittyTerm)
        XCTAssertEqual(AgentTalk.decision(for: running, route: AgentTalk.route(for: running)), .queue)
        let oc = session(.running(tool: nil), agent: .opencode, id: "ses_X")
        XCTAssertEqual(AgentTalk.decision(for: oc, route: AgentTalk.route(for: oc)), .sendNow, "OpenCode queues it itself")
        XCTAssertEqual(AgentTalk.decision(for: session(.running(tool: nil)), route: .copyAndActivate(bundleID: nil)), .sendNow)
    }

    func testAHeldMessageWaitsForTheSessionToBeFreeAndDiesWithIt() {
        let route = AgentTalk.Route.kitty(socket: "unix:/tmp/k", windowID: 7)
        XCTAssertNil(AgentTalk.shouldDeliverQueued(to: session(.running(tool: nil), terminal: kittyTerm), route: route))
        var q = session(.waitingForInput, terminal: kittyTerm); q.questionPending = true
        XCTAssertNil(AgentTalk.shouldDeliverQueued(to: q, route: route), "a question on screen: keep holding")
        XCTAssertEqual(AgentTalk.shouldDeliverQueued(to: session(.waitingForInput, terminal: kittyTerm), route: route), true)
        XCTAssertEqual(AgentTalk.shouldDeliverQueued(to: session(.ended, terminal: kittyTerm), route: route), false)
    }

    // MARK: Session state the decision relies on

    private func line(_ payload: String, at t: String) -> String {
        #"{"received_at":"\#(t)","request_id":"r-\#(UUID().uuidString)","agent":"claude","env":{"ppid":0},"payload":\#(payload)}"#
    }

    func testRulesTrackADialogAndAQuestionOnScreen() {
        func rows(_ payloads: [String]) -> AgentSession? {
            let events = payloads.enumerated().compactMap { i, p in AgentEvents.parse(line: line(p, at: "2026-10-14T05:00:0\(i)Z")) }
            return AgentSessionRules.sessions(from: events, now: Date(timeIntervalSince1970: 1_791_939_700), isAlive: { _ in true }).first
        }
        let dialog = rows([#"{"hook_event_name":"Stop","session_id":"a"}"#,
                           #"{"hook_event_name":"Notification","session_id":"a","notification_type":"permission_prompt"}"#])
        XCTAssertEqual(dialog?.dialogOnScreen, true)
        XCTAssertEqual(rows([#"{"hook_event_name":"Notification","session_id":"a","notification_type":"elicitation_dialog"}"#])?.dialogOnScreen, true)
        let answered = rows([#"{"hook_event_name":"Notification","session_id":"a","notification_type":"permission_prompt"}"#,
                             #"{"hook_event_name":"PreToolUse","session_id":"a","tool_name":"Bash"}"#])
        XCTAssertEqual(answered?.dialogOnScreen, false, "a tool starting means the dialog was answered")
        let asking = rows([#"{"hook_event_name":"PreToolUse","session_id":"a","tool_name":"AskUserQuestion"}"#,
                           #"{"hook_event_name":"Notification","session_id":"a","notification_type":"idle_prompt"}"#])
        XCTAssertEqual(asking?.questionPending, true, "idle while a question waits is still a question")
        XCTAssertEqual(asking?.status, .waitingForInput)
        let done = rows([#"{"hook_event_name":"PreToolUse","session_id":"a","tool_name":"AskUserQuestion"}"#,
                         #"{"hook_event_name":"PostToolUse","session_id":"a","tool_name":"AskUserQuestion"}"#])
        XCTAssertEqual(done?.questionPending, false)
    }

    func testTheHookRecordsWhereAReplyCanBeTyped() throws {
        let l = #"{"received_at":"2026-10-14T05:00:00Z","request_id":"r","agent":"claude","env":{"ppid":42,"tty":"/dev/ttys004","kitty_window":"7","kitty_listen_on":"unix:/tmp/kitty-13413","tmux":"/private/tmp/tmux-502/default,812,0","tmux_pane":"%3"},"payload":{"hook_event_name":"Stop","session_id":"a"}}"#
        let e = try XCTUnwrap(AgentEvents.parse(line: l))
        XCTAssertEqual(e.terminal.kittyWindowID, "7")
        XCTAssertEqual(e.terminal.kittyListenOn, "unix:/tmp/kitty-13413")
        XCTAssertEqual(e.terminal.tmuxEnv, "/private/tmp/tmux-502/default,812,0")
        XCTAssertEqual(e.terminal.tty, "/dev/ttys004")
    }

    // MARK: Text

    func testTextIsOneCleanLineWithEveryControlCharacterRemoved() {
        XCTAssertEqual(AgentTalk.clean("  fix the\nlogin\r\nbug\tnow  "), "fix the login bug now", "line breaks would press Enter early")
        XCTAssertEqual(AgentTalk.clean("ok\u{1B}]0;PWNED\u{07}done"), "ok]0;PWNEDdone", "an ESC sequence must not reach the terminal live")
        XCTAssertEqual(AgentTalk.clean("a\u{7F}b\u{9B}c\u{08}d"), "abcd", "DEL, C1 CSI and backspace are dropped")
        XCTAssertEqual(AgentTalk.clean("Sửa lỗi đăng nhập 🙂"), "Sửa lỗi đăng nhập 🙂")
        XCTAssertNil(AgentTalk.clean(" \n\t\u{1B} "), "nothing left ⇒ nothing to send")
        XCTAssertEqual(AgentTalk.clean(String(repeating: "x", count: 5000))?.count, AgentTalk.maxLength)
        XCTAssertEqual(AgentTalk.clean("line\u{2028}sep\u{85}nel"), "line sep nel")
    }

    // MARK: Commands

    func testCommandsAreArgumentArraysAndTextNeverRidesAnEscapeInterpretingArgument() throws {
        // Text never rides an argument: Process decomposes non-ASCII arguments to NFD (measured).
        XCTAssertEqual(AgentTalk.tmuxLoadArguments(socket: "/s", buffer: "b").last, "-", "the text comes on stdin")
        XCTAssertEqual(AgentTalk.tmuxPasteArguments(socket: "/s", pane: "%3", buffer: "b"),
                       ["-S", "/s", "paste-buffer", "-d", "-p", "-b", "b", "-t", "%3"])
        XCTAssertNotEqual(AgentTalk.tmuxBufferName(UUID()), AgentTalk.tmuxBufferName(UUID()), "one buffer per send")
        XCTAssertEqual(AgentTalk.tmuxEnterArguments(socket: "/s", pane: "%3").last, "Enter")
        XCTAssertEqual(AgentTalk.tmuxCheckArguments(socket: "/s", pane: "%3").last, "#{pane_tty}")
        let k = AgentTalk.kittyTypeArguments(socket: "unix:/tmp/k", windowID: 7)
        XCTAssertEqual(k.last, "--stdin", "the argument form of send-text interprets Python escapes")
        XCTAssertTrue(k.contains("id:7"))
        XCTAssertEqual(AgentTalk.kittyEnterBytes, "\r")
        let viet = try XCTUnwrap(AgentTalk.opencodePromptArguments(sessionID: "ses_A1", text: "Sửa 🙂", queue: false))
        XCTAssertTrue(viet.last!.unicodeScalars.allSatisfy(\.isASCII), "an argument with non-ASCII would reach the CLI decomposed")
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(viet.last!.utf8)) as? [String: String])
        XCTAssertEqual(decoded["text"]?.unicodeScalars.map(\.value), "Sửa 🙂".unicodeScalars.map(\.value), "NFC scalars come back exactly")
        let oc = try XCTUnwrap(AgentTalk.opencodePromptArguments(sessionID: "ses_A1", text: #"say "hi""#, queue: true))
        XCTAssertEqual(Array(oc.prefix(4)), ["api", "session.prompt", "--param", "sessionID=ses_A1"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(oc.last!.utf8)) as? [String: String])
        XCTAssertEqual(body, ["text": #"say "hi""#, "delivery": "queue"])
        let now = try XCTUnwrap(AgentTalk.opencodePromptArguments(sessionID: "ses_A1", text: "x", queue: false))
        XCTAssertEqual(try XCTUnwrap(JSONSerialization.jsonObject(with: Data(now.last!.utf8)) as? [String: String]), ["text": "x"])
        XCTAssertNil(AgentTalk.opencodePromptArguments(sessionID: "ses_A1 --server x", text: "x", queue: false))
    }

    // MARK: Target checks

    func testTmuxTypesOnlyIntoThePaneThatStillHasTheAgentsTTY() {
        XCTAssertTrue(AgentTalk.tmuxTargetMatches(paneTTY: "/dev/ttys009\n", recordedTTY: "/dev/ttys009"))
        XCTAssertFalse(AgentTalk.tmuxTargetMatches(paneTTY: "/dev/ttys010\n", recordedTTY: "/dev/ttys009"), "a reused pane id")
        XCTAssertFalse(AgentTalk.tmuxTargetMatches(paneTTY: "/dev/ttys009", recordedTTY: nil), "no recorded tty ⇒ never type")
    }

    func testKittyTypesOnlyIntoTheWindowWhoseForegroundIsTheAgent() {
        let ls = #"[{"id":1,"tabs":[{"id":2,"windows":[{"id":7,"env":{"SECRET":"x"},"foreground_processes":[{"pid":4242,"cmdline":["claude"]}]},{"id":8,"foreground_processes":[{"pid":99}]}]}]}]"#
        let data = Data(ls.utf8)
        XCTAssertTrue(AgentTalk.kittyTargetMatches(lsJSON: data, windowID: 7, agentPID: 4242))
        XCTAssertFalse(AgentTalk.kittyTargetMatches(lsJSON: data, windowID: 7, agentPID: 5555), "the window now runs something else")
        XCTAssertFalse(AgentTalk.kittyTargetMatches(lsJSON: data, windowID: 9, agentPID: 4242), "the window is gone")
        XCTAssertFalse(AgentTalk.kittyTargetMatches(lsJSON: data, windowID: 7, agentPID: nil), "no agent pid ⇒ never type")
        XCTAssertFalse(AgentTalk.kittyTargetMatches(lsJSON: Data("nope".utf8), windowID: 7, agentPID: 4242))
    }

    // MARK: Words

    /// The sender is AppKit (outside the package): read its source and require every `Status(key: "…")` literal — and the
    /// ternary arms that build one — to be in `AgentTalk.statusKeys`, so a new outcome line cannot leak Vietnamese.
    func testEverySenderOutcomeLineIsListed() throws {
        let src = try String(contentsOf: L10nFixture.repoRoot().appendingPathComponent("XFinder/Core/Agents/AgentTalkSender.swift"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"(?:Status\(key: |\? |: )"([^"]+)""#)
        let found = regex.matches(in: src, range: NSRange(src.startIndex..., in: src)).compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: src) else { return nil }
            let s = String(src[r])
            return s.unicodeScalars.contains { $0.value > 0x7F } ? s : nil     // Vietnamese / typographic ⇒ a key
        }
        XCTAssertGreaterThanOrEqual(Set(found).count, 20, "the parse found almost nothing — the pattern rotted")
        for key in Set(found) { XCTAssertTrue(AgentTalk.statusKeys.contains(key), "\(key) is said by the sender but not listed") }
    }

    func testEveryKeyHandedToL10nThroughAVariableIsTranslated() throws {
        let entries = try XCTUnwrap(try L10nFixture.raw()["entries"] as? [String: [String: Any]])
        let keys = AgentTalk.reasonKeys + AgentTalk.labelKeys + AgentTalk.statusKeys
        XCTAssertGreaterThanOrEqual(keys.count, 30)
        for key in keys {
            XCTAssertFalse((entries[key]?["en"] as? String ?? "").isEmpty, "\(key) reaches the screen through a variable")
        }
        for route in [AgentTalk.Route.kitty(socket: "unix:/s", windowID: 1), .tmux(socket: "/s", pane: "%1"),
                      .opencode(sessionID: "ses_A"), .copyAndActivate(bundleID: nil), .copyAndActivate(bundleID: "x")] {
            XCTAssertTrue(AgentTalk.labelKeys.contains(AgentTalk.routeLabelKey(route)))
        }
    }
}
