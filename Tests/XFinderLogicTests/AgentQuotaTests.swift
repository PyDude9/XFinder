import XCTest

/// P12 — a session that stopped at a usage limit: which signals count, how each agent's room is read, which agent the
/// handoff opens on, the notice (once, never also "finished"), and the handoff note's state line.
final class AgentQuotaTests: XCTestCase {
    typealias Q = AgentQuotaRules
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let sid = "11111111-2222-3333-4444-555555555555"

    private func line(_ name: String, at seconds: Double = 0, extra: String = "") -> String {
        let ts = AgentEvents.iso.string(from: t0.addingTimeInterval(seconds))
        return #"{"received_at":"\#(ts)","request_id":"r","env":{"ppid":4242,"bundle_id":"net.kovidgoyal.kitty"},"payload":{"hook_event_name":"\#(name)","session_id":"\#(sid)","cwd":"/w/app","transcript_path":"/t.jsonl"\#(extra)}}"#
    }

    private func sessions(_ lines: [String]) -> [AgentSession] {
        AgentSessionRules.sessions(from: lines.compactMap(AgentEvents.parse(line:)), now: t0.addingTimeInterval(60), isAlive: { _ in true })
    }

    // MARK: Signals

    func testOnlyTheUsageLimitCodesAreLimitStops() {
        XCTAssertTrue(Q.isLimitStop(claudeError: "rate_limit"))
        for other in ["overloaded", "server_error", "authentication_failed", "unknown", ""] {
            XCTAssertFalse(Q.isLimitStop(claudeError: other), other)
        }
        XCTAssertFalse(Q.isLimitStop(claudeError: nil))
        XCTAssertTrue(Q.isLimitStop(codexCode: "usageLimitExceeded"))
        XCTAssertFalse(Q.isLimitStop(codexCode: "rateLimitExceeded"), "Q-P12-2: the schema keeps the two apart; only the usage limit stops the work")
        XCTAssertFalse(Q.isLimitStop(codexCode: "httpConnectionFailed"))
        XCTAssertFalse(Q.isLimitStop(codexCode: nil))
    }

    func testStopFailureEndsTheTurnAndOnlyARateLimitIsALimitStop() {
        // StopFailure runs INSTEAD of Stop: without handling it the row stayed "running".
        var s = sessions([line("UserPromptSubmit"), line("StopFailure", at: 5, extra: #","error":"rate_limit","error_details":"429""#)])
        XCTAssertEqual(s[0].status, .waitingForInput)
        XCTAssertEqual(s[0].limitStop, AgentSession.LimitStop(reason: "rate_limit", since: t0.addingTimeInterval(5)))
        XCTAssertEqual(AgentSessionRules.rowStatusKey(s[0]), "Chạm giới hạn")
        s = sessions([line("UserPromptSubmit"), line("StopFailure", at: 5, extra: #","error":"overloaded""#)])
        XCTAssertEqual(s[0].status, .waitingForInput, "any API-error end is the end of the turn")
        XCTAssertNil(s[0].limitStop, "an overloaded server is not a usage limit")
        XCTAssertEqual(AgentSessionRules.rowStatusKey(s[0]), "Tới lượt bạn")
    }

    func testTheLimitStopClearsWhenTheWorkGoesOn() {
        let stop = line("StopFailure", at: 5, extra: #","error":"rate_limit""#)
        XCTAssertNil(sessions([line("UserPromptSubmit"), stop, line("UserPromptSubmit", at: 9)])[0].limitStop, "the person typed again")
        XCTAssertNil(sessions([line("UserPromptSubmit"), stop, line("PreToolUse", at: 9, extra: #","tool_name":"Bash""#)])[0].limitStop)
        // Claude Code's own wait for the reset (docs, v2.1.234+).
        let fired = sessions([line("UserPromptSubmit"), stop, line("Notification", at: 9, extra: #","notification_type":"quota_auto_resume_fired""#)])[0]
        XCTAssertNil(fired.limitStop); XCTAssertEqual(fired.status, .running(tool: nil), "it continued the task by itself")
        let stale = sessions([line("UserPromptSubmit"), stop, line("Notification", at: 9, extra: #","notification_type":"quota_auto_resume_stale""#)])[0]
        XCTAssertNil(stale.limitStop); XCTAssertEqual(stale.status, .waitingForInput, "reset passed while asleep: it waits for Enter")
        let gaveUp = sessions([line("UserPromptSubmit"), stop, line("Notification", at: 9, extra: #","notification_type":"quota_auto_resume_disabled""#)])[0]
        XCTAssertNotNil(gaveUp.limitStop, "it stopped waiting — still stopped at the limit")
        // An idle notification after the stop does not lift it.
        XCTAssertNotNil(sessions([line("UserPromptSubmit"), stop, line("Notification", at: 9, extra: #","notification_type":"idle_prompt""#)])[0].limitStop)
    }

    func testCodexCarriesItsErrorCodeIntoALimitStop() {
        XCTAssertEqual(CodexAppServer.parse(line: #"{"method":"turn/completed","params":{"turn":{"status":"failed","error":{"message":"You've hit your usage limit","codexErrorInfo":"usageLimitExceeded"}}}}"#),
                       .turnCompleted(status: "failed", error: "You've hit your usage limit", code: "usageLimitExceeded"))
        XCTAssertEqual(CodexAppServer.parse(line: #"{"method":"turn/completed","params":{"turn":{"status":"failed","error":{"message":"x","codexErrorInfo":{"httpConnectionFailed":{"httpStatusCode":502}}}}}}"#),
                       .turnCompleted(status: "failed", error: "x", code: "httpConnectionFailed"), "a structured variant is named by its key")
        var r = WindowlessRules.Record(sessionID: "x", cwd: "/w", startedAt: t0, updatedAt: t0)
        r.agent = .codex
        r.sent("làm đi", at: t0)
        r.applyCodex(.turnCompleted(status: "failed", error: "limit", code: "usageLimitExceeded"), at: t0.addingTimeInterval(3))
        XCTAssertEqual(WindowlessRules.session(for: r).limitStop, AgentSession.LimitStop(reason: "usageLimitExceeded", since: t0.addingTimeInterval(3)))
        r.sent("thử lại", at: t0.addingTimeInterval(9))
        XCTAssertNil(WindowlessRules.session(for: r).limitStop, "the next turn clears it")
        r.applyCodex(.turnCompleted(status: "failed", error: "slow down", code: "rateLimitExceeded"), at: t0.addingTimeInterval(12))
        XCTAssertNil(WindowlessRules.session(for: r).limitStop, "a rate limit is not a usage-limit stop")
        r.applyCodex(.turnCompleted(status: "completed", error: nil, code: "usageLimitExceeded"), at: t0.addingTimeInterval(15))
        XCTAssertNil(r.lastErrorCode, "a code is kept only for a failed turn")
        // A hook row for the same session keeps the record's stop when it has none of its own.
        var r2 = r; r2.lastErrorCode = "usageLimitExceeded"
        let hook = AgentSession(id: "x", agent: .codex, cwd: "/w", transcriptPath: nil, startedAt: t0, updatedAt: t0,
                                status: .waitingForInput, lastTool: nil, lastPrompt: nil, agentPID: nil,
                                terminal: AgentEvents.Terminal(), eventCount: 1)
        XCTAssertNotNil(WindowlessRules.merged(hookSessions: [hook], records: [r2]).first?.limitStop)
    }

    // MARK: Room per agent

    func testHeadroomIsReadOnlyFromCurrentFreshFigures() {
        let now = t0
        let five = ClaudeStatusLine.Window(usedPercent: 40, resetsAt: now.addingTimeInterval(3600))
        let quota = ClaudeStatusLine.Quota(fiveHour: five, sevenDay: nil, capturedAt: now)
        XCTAssertEqual(Q.claude(statusLineInstalled: true, quota: quota, scannedAt: now, now: now), .available(usedPercent: 40))
        XCTAssertEqual(Q.claude(statusLineInstalled: false, quota: quota, scannedAt: now, now: now), .unknown, "no statusLine ⇒ no figure, never 0 %")
        XCTAssertEqual(Q.claude(statusLineInstalled: true, quota: quota, scannedAt: now.addingTimeInterval(-11 * 60), now: now), .unknown, "a stale snapshot rules nothing in or out")
        let past = ClaudeStatusLine.Quota(fiveHour: .init(usedPercent: 100, resetsAt: now.addingTimeInterval(-1)), sevenDay: nil, capturedAt: now)
        XCTAssertEqual(Q.claude(statusLineInstalled: true, quota: past, scannedAt: now, now: now), .unknown, "a window past its reset says nothing")
        let full = ClaudeStatusLine.Quota(fiveHour: five, sevenDay: .init(usedPercent: 100, resetsAt: now.addingTimeInterval(86_400)), capturedAt: now)
        XCTAssertEqual(Q.claude(statusLineInstalled: true, quota: full, scannedAt: now, now: now), .exhausted, "the FULLEST current window decides")
        let codex = AgentUsage.CodexLimits(observedAt: now,
                                           primary: .init(usedPercent: 99, windowMinutes: 300, resetsAt: now.addingTimeInterval(600)),
                                           secondary: .init(usedPercent: 20, windowMinutes: 10_080, resetsAt: now.addingTimeInterval(86_400)), plan: "plus")
        XCTAssertEqual(Q.codex(codex, scannedAt: now, now: now), .available(usedPercent: 99))
        XCTAssertEqual(Q.codex(nil, scannedAt: now, now: now), .unknown)
        XCTAssertEqual(Q.classify([100]), .exhausted)
        XCTAssertEqual(Q.classify([99.9]), .available(usedPercent: 99.9))
        XCTAssertEqual(Q.classify([]), .unknown)
    }

    func testTheSuggestedAgentIsNeverTheStoppedOneNorAFullOne() {
        let all: Set<AgentKind> = [.claude, .codex, .opencode]
        XCTAssertEqual(Q.suggestTarget(stopped: .claude, headroom: [.claude: .exhausted, .codex: .available(usedPercent: 30), .opencode: .unknown], available: all), .codex)
        XCTAssertEqual(Q.suggestTarget(stopped: .claude, headroom: [.codex: .exhausted, .opencode: .unknown], available: all), .opencode, "a full Codex is skipped")
        XCTAssertEqual(Q.suggestTarget(stopped: .codex, headroom: [.claude: .unknown, .opencode: .unknown], available: all), .claude, "all unknown ⇒ AgentKind order")
        XCTAssertEqual(Q.suggestTarget(stopped: .codex, headroom: [.claude: .unknown, .opencode: .available(usedPercent: 10)], available: all), .opencode,
                       "known room beats unknown room")
        XCTAssertEqual(Q.suggestTarget(stopped: .claude, headroom: [.codex: .available(usedPercent: 1)], available: [.claude, .opencode]), .opencode,
                       "an agent that is not installed is never offered")
        XCTAssertNil(Q.suggestTarget(stopped: .claude, headroom: [:], available: [.claude]), "nothing else installed ⇒ no suggestion")
        for stopped in AgentKind.allCases {
            XCTAssertNotEqual(Q.suggestTarget(stopped: stopped, headroom: [:], available: all), stopped)
        }
    }

    // MARK: The notice

    private func row(_ status: AgentSession.Status, stop: Date? = nil) -> AgentSession {
        var s = AgentSession(id: sid, agent: .claude, cwd: "/w/app", transcriptPath: "/t.jsonl", startedAt: t0, updatedAt: t0,
                             status: status, lastTool: nil, lastPrompt: nil, agentPID: 1, terminal: AgentEvents.Terminal(), eventCount: 3)
        if let stop { s.limitStop = .init(reason: "rate_limit", since: stop) }
        return s
    }

    func testALimitStopIsAnnouncedOnceAndNeverAsFinished() {
        let on = AgentNotify.Settings(permission: true, finished: true, limit: true)
        let running = row(.running(tool: nil))
        let stopped = row(.waitingForInput, stop: t0)
        XCTAssertEqual(AgentNotify.events(old: [running], new: [stopped], settings: on), [.limitStopped(stopped)], "not ALSO 'your turn'")
        XCTAssertEqual(AgentNotify.events(old: [stopped], new: [stopped], settings: on), [], "the same stop is not announced twice")
        let again = row(.waitingForInput, stop: t0.addingTimeInterval(600))
        XCTAssertEqual(AgentNotify.events(old: [stopped], new: [again], settings: on), [.limitStopped(again)], "a later stop is news")
        let off = AgentNotify.Settings(permission: true, finished: true, limit: false)
        XCTAssertEqual(AgentNotify.events(old: [running], new: [stopped], settings: off), [], "switch off ⇒ silent, and still not 'finished'")
        XCTAssertEqual(AgentNotify.events(old: nil, new: [stopped], settings: on), [], "the first snapshot is a baseline")
    }

    func testTheNoticeOpensTheHandoffOnlyWhenThereIsATarget() throws {
        let s = row(.waitingForInput, stop: t0)
        let item = AgentNotify.item(for: .limitStopped(s), suggestedTarget: .codex)
        XCTAssertEqual(item.buttons, [.handOff(listID: s.listID, target: .codex)])
        XCTAssertEqual(item.tint, .bad)
        XCTAssertEqual(AgentNotify.item(for: .limitStopped(s)).buttons, [.openAgents], "no target ⇒ open the Agents page")
        let store = try L10nFixture.load()
        for key in [item.titleKey, "Chạm giới hạn", "Chuyển sang ", "Khi một phiên dừng vì chạm giới hạn sử dụng"] {
            guard let e = store.entries[key] else { XCTFail("\(key.debugDescription) is not in L10n.strings.json"); continue }
            XCTAssertFalse(e.en.isEmpty); XCTAssertNotEqual(e.en, key)
        }
    }

    // MARK: The handoff note

    func testTheHandoffNoteSaysWhatTheSessionWasDoing() {
        XCTAssertEqual(AgentHandoff.sourceState(of: row(.running(tool: "Bash"))), .working)
        XCTAssertEqual(AgentHandoff.sourceState(of: row(.waitingForInput)), .finishedTurn)
        var q = row(.waitingForInput); q.questionPending = true
        XCTAssertEqual(AgentHandoff.sourceState(of: q), .waitingForAnswer)
        let p = AgentSession.PendingPermission(requestID: "r", toolName: "Bash", summary: String(repeating: "x", count: 400), since: t0)
        XCTAssertEqual(AgentHandoff.sourceState(of: row(.waitingForPermission(p))), .waitingForApproval(tool: "Bash", summary: p.summary))
        XCTAssertEqual(AgentHandoff.sourceState(of: row(.waitingForInput, stop: t0)), .limitStop)
        XCTAssertEqual(AgentHandoff.sourceState(of: row(.ended, stop: t0)), .ended, "an ended session is ended, whatever stopped it")

        func msg(_ st: AgentHandoff.SourceState, path: String? = nil) -> String {
            AgentHandoff.compose(source: .claude, folder: "/w/app", turns: [], files: [], git: nil, state: st, transcriptPath: path, english: true)
        }
        XCTAssertNotEqual(msg(.finishedTurn), msg(.waitingForApproval(tool: "Bash", summary: nil)),
                          "a finished turn and a pending approval used to read the same")
        let approval = msg(.waitingForApproval(tool: "Bash", summary: p.summary))
        XCTAssertTrue(approval.contains("waiting for my approval: Bash — " + String(repeating: "x", count: AgentHandoff.approvalSummaryCap) + "…"))
        XCTAssertFalse(approval.contains(String(repeating: "x", count: AgentHandoff.approvalSummaryCap + 1)), "cut at the cap")
        XCTAssertTrue(msg(.limitStop).contains("stopped at a usage limit"))
        XCTAssertTrue(msg(.working).contains("leave the files below alone"), "an open source session: hands off its files")
        XCTAssertFalse(msg(.ended).contains("leave the files below alone"))
        XCTAssertTrue(msg(.finishedTurn, path: "/Users/me/.claude/x.jsonl").contains("## Full log (do not open it unless I ask)\n/Users/me/.claude/x.jsonl"))
        XCTAssertFalse(msg(.finishedTurn).contains("Full log"), "no path ⇒ no section")
        let vi = AgentHandoff.compose(source: .claude, folder: nil, turns: [], files: [], git: nil, state: .limitStop, english: false)
        XCTAssertTrue(vi.contains("chạm giới hạn sử dụng"))
    }

    // MARK: Review fixes

    func testAPermissionRequestAfterALimitStopIsShownAndAnnounced() {
        // P12 review: the stale stop hid the request ("Chạm giới hạn") and silenced its notice — the hook then blocks
        // Claude Code for up to an hour with nobody told.
        let s = sessions([line("UserPromptSubmit"), line("StopFailure", at: 5, extra: #","error":"rate_limit""#),
                          line("PermissionRequest", at: 9, extra: #","tool_name":"Bash","tool_input":{"command":"ls"}"#)])[0]
        guard case .waitingForPermission = s.status else { return XCTFail("the request must show") }
        XCTAssertNil(s.limitStop)
        XCTAssertEqual(AgentSessionRules.rowStatusKey(s), "Chờ bạn duyệt")
        var stale = row(.running(tool: "Bash"), stop: t0)
        XCTAssertFalse(stale.isLimitStopped, "a stop only counts while the session waits for the person")
        stale.status = .waitingForPermission(.init(requestID: "r9", toolName: "Bash", summary: nil, since: t0))
        XCTAssertEqual(AgentSessionRules.rowStatusKey(stale), "Chờ bạn duyệt")
        XCTAssertNotEqual(AgentHandoff.sourceState(of: stale), .limitStop)
        let events = AgentNotify.events(old: [row(.waitingForInput, stop: t0)], new: [stale],
                                        settings: .init(permission: true, finished: true, limit: true))
        XCTAssertEqual(events.count, 1)
        if case .needsApproval? = events.first {} else { XCTFail("the approval notice must come") }
    }

    func testARefusedCodexTurnStartEndsTheTurnAndTheStopKeepsItsTime() {
        var r = WindowlessRules.Record(sessionID: "x", cwd: "/w", startedAt: t0, updatedAt: t0)
        r.agent = .codex
        r.sent("làm đi", at: t0)
        r.applyCodex(.requestFailed(id: 3, message: "turn/start refused"), at: t0.addingTimeInterval(1))
        XCTAssertEqual(r.phase, .waiting, "no turn/completed will ever come for a refused turn/start")
        r.sent("lần nữa", at: t0.addingTimeInterval(2))
        r.applyCodex(.turnStarted(turnID: "tu"), at: t0.addingTimeInterval(3))
        r.applyCodex(.requestFailed(id: 9, message: "interrupt refused"), at: t0.addingTimeInterval(4))
        XCTAssertEqual(r.phase, .working(tool: nil), "a refused request while a turn RUNS leaves the turn alone")
        r.applyCodex(.turnCompleted(status: "failed", error: "limit", code: "usageLimitExceeded"), at: t0.addingTimeInterval(5))
        let first = WindowlessRules.session(for: r).limitStop
        r.applyCodex(.error("late notice"), at: t0.addingTimeInterval(30))
        XCTAssertEqual(WindowlessRules.session(for: r).limitStop, first, "a later event must not give the same stop a new time")
        XCTAssertEqual(first?.since, t0.addingTimeInterval(5))
    }

    func testAnUrgentAgentNoticeIsNotReplacedByALesserOne() {
        let s = row(.waitingForInput, stop: t0)
        let limit = AgentNotify.item(for: .limitStopped(s), suggestedTarget: .codex)
        let done = AgentNotify.item(for: .finished(row(.waitingForInput)))
        var q = LiveActivity.Queue()
        q.push(limit); q.push(done)
        XCTAssertEqual(q.current, limit, "a finished turn must not wipe a limit stop before it is seen")
        XCTAssertEqual(q.advance(), done, "it waits its turn instead")
        var q2 = LiveActivity.Queue()
        q2.push(done); q2.push(limit)
        XCTAssertEqual(q2.current, limit, "the urgent one replaces the lesser one")
    }

    // MARK: The hook subscription

    func testStopFailureIsSubscribedLastForClaudeOnly() {
        XCTAssertEqual(AgentHookInstaller.events.last?.name, "StopFailure", "appended at the end — existing positions never move")
        XCTAssertEqual(AgentHookInstaller.events.filter { $0.name == "StopFailure" }.count, 1)
    }
}
