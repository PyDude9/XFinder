import XCTest
import AppKit
import Foundation

/// N3 — the pure half of AI agent sessions on the notch: the hook's line format, the session rules and the
/// settings.json merge. Fixtures mirror what the hook script writes (measured in the scratchpad harness).
final class AgentSessionTests: XCTestCase {
    typealias E = AgentEvents.Event
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    let sid = "11111111-2222-3333-4444-555555555555"

    func line(_ name: String, at seconds: Double = 0, sid: String? = nil, extra: String = "", env: String = #""ppid":4242,"tty":"/dev/ttys003","term_program":"iTerm.app","bundle_id":"com.googlecode.iterm2""#, requestID: String = "r1") -> String {
        let ts = AgentEvents.iso.string(from: t0.addingTimeInterval(seconds))
        return #"{"received_at":"\#(ts)","request_id":"\#(requestID)","env":{\#(env)},"payload":{"hook_event_name":"\#(name)","session_id":"\#(sid ?? self.sid)","cwd":"/Users/me/Projects/XFinder","transcript_path":"/t.jsonl"\#(extra)}}"#
    }

    // MARK: Parsing

    func testParsesTheHookLineIntoAnEvent() {
        let e = AgentEvents.parse(line: line("PreToolUse", at: 3, extra: #","tool_name":"Bash","tool_input":{"command":"git push\norigin"}"#))
        XCTAssertEqual(e?.name, .preToolUse)
        XCTAssertEqual(e?.sessionID, sid)
        XCTAssertEqual(e?.toolName, "Bash")
        XCTAssertEqual(e?.toolInputSummary, "git push ⏎ origin")
        XCTAssertEqual(e?.agentPID, 4242)
        XCTAssertEqual(e?.terminal.bundleID, "com.googlecode.iterm2")
        XCTAssertEqual(e?.terminal.tty, "/dev/ttys003")
        XCTAssertEqual(e?.receivedAt, t0.addingTimeInterval(3))
        XCTAssertEqual(e?.cwd, "/Users/me/Projects/XFinder")
    }

    func testUnknownEventNamesSurviveAndBadLinesAreSkipped() {
        let e = AgentEvents.parse(line: line("SomethingNew"))
        XCTAssertEqual(e?.name, .other); XCTAssertEqual(e?.rawName, "SomethingNew")
        XCTAssertNil(AgentEvents.parse(line: "{not json"))
        XCTAssertNil(AgentEvents.parse(line: #"{"received_at":"x","payload":{"hook_event_name":"Stop"}}"#), "no session id ⇒ no event")
        XCTAssertNil(AgentEvents.parse(line: "   "))
        XCTAssertEqual(AgentEvents.parse(jsonl: line("Stop") + "\n\n" + "garbage\n" + line("Stop", at: 1)).count, 2)
    }

    /// 2026-10-25: the launch read parses bytes per line (memchr) — blank lines, CRLF, a missing final newline and a
    /// slice that does not start at index 0 (a mapped file read from an offset) all behave like the String path.
    func testByteParserMatchesTheLineParser() {
        let text = "\n" + line("Stop") + "\r\n  \n" + line("Notification", at: 2) + "\n" + line("Stop", at: 4)
        let fromBytes = AgentEvents.parse(jsonl: Data(text.utf8))
        let fromLines = text.split(separator: "\n").compactMap { AgentEvents.parse(line: String($0)) }
        XCTAssertEqual(fromBytes, fromLines)
        XCTAssertEqual(fromBytes.map(\.receivedAt), [0, 2, 4].map { t0.addingTimeInterval($0) })
        let padded = Data(("garbage-prefix\n" + text).utf8)
        let slice = padded[padded.index(padded.startIndex, offsetBy: 15)...]
        XCTAssertEqual(AgentEvents.parse(jsonl: slice), fromBytes, "a slice keeps its own indices")
    }

    func testTimestampFastPathAgreesWithTheFormatter() {
        for s in ["2026-10-25T03:32:17Z", "2024-02-29T23:59:59Z", "2000-02-29T00:00:00Z", "1970-01-01T00:00:00Z",
                  "2100-03-01T12:00:00Z", "1969-12-31T23:59:59Z"] {
            XCTAssertEqual(AgentEvents.timestamp(s), AgentEvents.iso.date(from: s), s)
        }
        // Out-of-range fields ⇒ the formatter decides, whatever it decides (measured: it rolls 02-30 over to 03-02).
        for s in ["2026-02-30T00:00:00Z", "2100-02-29T00:00:00Z", "2026-10-25T24:00:00Z", "2026-1x-25T03:32:17Z"] {
            XCTAssertEqual(AgentEvents.timestamp(s), AgentEvents.iso.date(from: s), s)
        }
        XCTAssertEqual(AgentEvents.timestamp("2026-10-25T10:32:17+07:00"), AgentEvents.timestamp("2026-10-25T03:32:17Z"),
                       "an offset goes through the formatter")
    }

    func testEventsFileNameMatchesTheUTCFormatter() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        // Every 7 h 13 min across 1969…2101 (crosses every month end, leap days, the epoch and negative days), plus the
        // exact second before and after a UTC midnight.
        var t = Date(timeIntervalSince1970: -40_000_000)
        while t.timeIntervalSince1970 < 4_150_000_000 {
            XCTAssertEqual(AgentEvents.eventsFileName(for: t), "events-\(f.string(from: t)).jsonl", "\(t)")
            t = t.addingTimeInterval(7 * 3_600 + 13 * 60)
        }
        for s in [1_761_436_799.0, 1_761_436_800.0, 1_761_436_800.9, -1.0, 0.0] {
            let d = Date(timeIntervalSince1970: s)
            XCTAssertEqual(AgentEvents.eventsFileName(for: d), "events-\(f.string(from: d)).jsonl", "\(s)")
        }
        for days in [-1, 0, 1, 19_000, 59, 60, 11_016] {
            let (y, m, d) = AgentEvents.civilFromDays(days)
            XCTAssertEqual(AgentEvents.daysFromCivil(year: y, month: m, day: d), days, "round trip \(days)")
        }
    }

    func testSessionIDsAreAsciiWordCharactersOnly() {
        XCTAssertTrue(AgentEvents.isSafeSessionID(sid))
        XCTAssertTrue(AgentEvents.isSafeSessionID("abc_DEF-09"))
        for bad in ["", "../x", "a b", "ạ", "١٢٣", "ｆｕｌｌ", "a/b", "a.b", String(repeating: "a", count: 129)] {
            XCTAssertFalse(AgentEvents.isSafeSessionID(bad), bad)
        }
    }

    func testToolInputSummaryPrefersTheOneFieldAPersonNeedsAndCutsLongOnes() {
        XCTAssertEqual(AgentEvents.summary(ofToolInput: ["file_path": "/a/b.swift", "content": "…"]), "/a/b.swift")
        XCTAssertEqual(AgentEvents.summary(ofToolInput: ["command": String(repeating: "x", count: 200)])?.count, 161)
        XCTAssertNil(AgentEvents.summary(ofToolInput: ["other": 1]))
    }

    func testEventsFileNameIsTheUTCDayLikeTheHooksDateU() {
        // 2025-10-09T06:13:20Z
        XCTAssertEqual(AgentEvents.eventsFileName(for: t0), "events-2025-10-09.jsonl")
    }

    // MARK: Session rules

    func sessions(_ lines: [String], now seconds: Double = 60, alive: Set<Int32> = [4242], answered: Set<String> = []) -> [AgentSession] {
        AgentSessionRules.sessions(from: AgentEvents.parse(jsonl: lines.joined(separator: "\n")),
                                   now: t0.addingTimeInterval(seconds), answered: answered, isAlive: { alive.contains($0) })
    }

    func testAToolStartsRunningAndStopMeansYourTurn() {
        var s = sessions([line("SessionStart"), line("UserPromptSubmit", at: 1, extra: #","prompt":"fix the bug""#),
                          line("PreToolUse", at: 2, extra: #","tool_name":"Read""#)])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].status, .running(tool: "Read"))
        XCTAssertEqual(s[0].lastPrompt, "fix the bug")
        XCTAssertEqual(s[0].displayName, "XFinder")
        s = sessions([line("SessionStart"), line("PreToolUse", at: 2, extra: #","tool_name":"Read""#), line("PostToolUse", at: 3, extra: #","tool_name":"Read""#)])
        XCTAssertEqual(s[0].status, .running(tool: nil), "between tools it is thinking")
        s = sessions([line("SessionStart"), line("PreToolUse", at: 2, extra: #","tool_name":"Bash""#), line("PostToolUseFailure", at: 3, extra: #","tool_name":"Bash""#)])
        XCTAssertEqual(s[0].status, .running(tool: nil), "a failed tool is over too")
        s = sessions([line("SessionStart"), line("Stop", at: 5)])
        XCTAssertEqual(s[0].status, .waitingForInput)
        XCTAssertTrue(s[0].needsYou)
    }

    func testAPermissionRequestWaitsUntilAnsweredOrAToolRuns() {
        let req = line("PermissionRequest", at: 4, extra: #","tool_name":"Bash","tool_input":{"command":"git push"}"#, requestID: "req-9")
        var s = sessions([line("SessionStart"), req])
        guard case .waitingForPermission(let p) = s[0].status else { return XCTFail("\(s[0].status)") }
        XCTAssertEqual(p.requestID, "req-9"); XCTAssertEqual(p.toolName, "Bash"); XCTAssertEqual(p.summary, "git push")
        XCTAssertEqual(p.since, t0.addingTimeInterval(4))
        // answered from the notch (the decision file was written) ⇒ no longer waiting, even before the next event
        s = sessions([line("SessionStart"), req], answered: ["req-9"])
        XCTAssertEqual(s[0].status, .running(tool: "Bash"))
        // answered in the terminal ⇒ the tool simply starts
        s = sessions([line("SessionStart"), req, line("PreToolUse", at: 6, extra: #","tool_name":"Bash""#)])
        XCTAssertEqual(s[0].status, .running(tool: "Bash"))
        // denied in the terminal
        s = sessions([line("SessionStart"), req, line("PermissionDenied", at: 6, extra: #","tool_name":"Bash""#)])
        XCTAssertEqual(s[0].status, .running(tool: nil))
    }

    func testADeadProcessEndsTheSessionWhateverTheLogSays() {
        let s = sessions([line("SessionStart"), line("PreToolUse", at: 2, extra: #","tool_name":"Bash""#)], alive: [])
        XCTAssertEqual(s[0].status, .ended)
    }

    func testWithoutAPidASilentSessionGoesStaleAndOldEndedSessionsDropOut() {
        let noPid = #""tty":"","term_program":"""#
        var s = sessions([line("SessionStart", env: noPid), line("PreToolUse", at: 2, extra: #","tool_name":"Bash""#, env: noPid)], now: 10 * 60)
        XCTAssertEqual(s[0].status, .running(tool: "Bash"), "10 min of silence is not stale yet")
        s = sessions([line("SessionStart", env: noPid), line("PreToolUse", at: 2, extra: #","tool_name":"Bash""#, env: noPid)], now: 16 * 60)
        XCTAssertEqual(s[0].status, .ended)
        s = sessions([line("SessionStart"), line("SessionEnd", at: 5)], now: 30 * 60)
        XCTAssertEqual(s.count, 1, "an ended session stays listed for an hour")
        s = sessions([line("SessionStart"), line("SessionEnd", at: 5)], now: 61 * 60)
        XCTAssertEqual(s.count, 0)
    }

    func testDisplayOrderPutsPermissionsFirstThenWaitingThenRunningThenEnded() {
        let a = "aaaaaaaa-0000-0000-0000-000000000001", b = "bbbbbbbb-0000-0000-0000-000000000002"
        let c = "cccccccc-0000-0000-0000-000000000003", d = "dddddddd-0000-0000-0000-000000000004"
        let s = sessions([
            line("SessionStart", at: 0, sid: a), line("PreToolUse", at: 50, sid: a, extra: #","tool_name":"Bash""#),      // running, most recent
            line("SessionStart", at: 1, sid: b), line("Stop", at: 60, sid: b),                                            // waiting for input — MORE recent than the permission, so rank, not time, must put c first
            line("SessionStart", at: 2, sid: c), line("PermissionRequest", at: 20, sid: c, extra: #","tool_name":"Write""#, requestID: "rc"),
            line("SessionStart", at: 3, sid: d), line("SessionEnd", at: 30, sid: d),
        ])
        XCTAssertEqual(s.map(\.id), [c, b, a, d])
        XCTAssertEqual(s.filter(\.needsYou).count, 2)
    }

    func testNotificationTypesMapToWaiting() {
        var s = sessions([line("SessionStart"), line("Notification", at: 2, extra: #","notification_type":"idle_prompt","message":"waiting""#)])
        XCTAssertEqual(s[0].status, .waitingForInput)
        s = sessions([line("SessionStart"), line("Notification", at: 2, extra: #","notification_type":"permission_prompt""#)])
        XCTAssertEqual(s[0].status, .waitingForInput, "Claude Code's own prompt is up; only a PermissionRequest hook can be answered from here")
    }

    /// The status keys come from a model function (`L10n.t(variable)` at the call site), which no literal
    /// sweep can see — so the vocabulary is resolved against the shipped store here.
    func testEveryStatusKeyIsInTheStore() throws {
        let store = try L10nFixture.load()
        let keys = [AgentSessionRules.statusKey(.running(tool: nil)), AgentSessionRules.statusKey(.running(tool: "Bash")),
                    AgentSessionRules.statusKey(.waitingForInput), AgentSessionRules.statusKey(.ended),
                    AgentSessionRules.statusKey(.waitingForPermission(.init(requestID: "r", toolName: "Bash", summary: nil, since: t0)))]
        XCTAssertEqual(Set(keys).count, 5, "five distinct keys, or the loop proves less than it claims")
        for k in keys {
            guard let entry = store.entries[k] else { XCTFail("\(k.debugDescription) is not in L10n.strings.json"); continue }
            XCTAssertFalse(entry.en.isEmpty); XCTAssertNotEqual(entry.en, k)
        }
    }

    // MARK: settings.json merge

    let hookPath = "/Users/me/Library/Application Support/XFinder/Agents/bin/xfinder-claude-hook.zsh"

    func testMergeAppendsOurEntryOncePerEventAndKeepsOtherTools() {
        let other: [String: Any] = ["matcher": "*", "hooks": [["type": "command", "command": "'/x/OneNotchClaudeHook'", "timeout": 45]]]
        let settings: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [other]]]
        let merged = AgentHookInstaller.merged(settings, hookPath: hookPath)
        let hooks = merged["hooks"] as! [String: Any]
        XCTAssertEqual(merged["model"] as? String, "opus")
        XCTAssertEqual((hooks["PreToolUse"] as! [[String: Any]]).count, 2, "the other tool's entry is kept, ours appended")
        XCTAssertEqual(Set(hooks.keys), Set(AgentHookInstaller.events.map(\.name)))
        let perm = (hooks["PermissionRequest"] as! [[String: Any]]).first!["hooks"] as! [[String: Any]]
        XCTAssertEqual(perm.first?["timeout"] as? Int, 3600)
        XCTAssertEqual(perm.first?["command"] as? String, "'\(hookPath)'")
        XCTAssertEqual(perm.first?["statusMessage"] as? String, AgentHookInstaller.marker)
        // idempotent
        let twice = AgentHookInstaller.merged(merged, hookPath: hookPath)
        XCTAssertEqual(((twice["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]).count, 2)
        XCTAssertEqual(AgentHookInstaller.status(of: twice, hookPath: hookPath), .installed)
    }

    func testRemoveTakesOnlyOurEntriesAndCleansEmptyContainers() {
        let other: [String: Any] = ["matcher": "*", "hooks": [["type": "command", "command": "'/x/OneNotchClaudeHook'", "timeout": 45]]]
        let merged = AgentHookInstaller.merged(["hooks": ["PreToolUse": [other]]], hookPath: hookPath)
        let removed = AgentHookInstaller.removed(merged, hookPath: hookPath)
        // `as?` on purpose: a mutation that drops EVERY entry leaves no "hooks" at all, and a force-cast would trap
        // the whole run instead of failing this test (CLAUDE.md: never force-unwrap what the mutation removes).
        let hooks = removed["hooks"] as? [String: Any] ?? [:]
        XCTAssertEqual(Array(hooks.keys), ["PreToolUse"], "events that held only our entry disappear; the other tool's survives")
        XCTAssertEqual((hooks["PreToolUse"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(AgentHookInstaller.status(of: removed, hookPath: hookPath), .notInstalled)
        let empty = AgentHookInstaller.removed(AgentHookInstaller.merged([:], hookPath: hookPath), hookPath: hookPath)
        XCTAssertNil(empty["hooks"], "an empty hooks object is dropped")
    }

    func testPartialInstallIsReportedWithTheMissingEvents() {
        var merged = AgentHookInstaller.merged([:], hookPath: hookPath)
        var hooks = merged["hooks"] as! [String: Any]
        hooks.removeValue(forKey: "PermissionRequest"); merged["hooks"] = hooks
        XCTAssertEqual(AgentHookInstaller.status(of: merged, hookPath: hookPath), .partial(missing: ["PermissionRequest"]))
    }

    func testCommandQuotingSurvivesSpacesAndQuotes() {
        XCTAssertEqual(AgentHookInstaller.command(forHookAt: "/a b/c'd"), "'/a b/c'\\''d'")
    }

    func testDecisionPayloadIsClaudeCodesPermissionRequestShape() {
        let allow = AgentDecision.payload(allow: true)
        XCTAssertEqual(allow, #"{"hookSpecificOutput":{"decision":{"behavior":"allow"},"hookEventName":"PermissionRequest"}}"#)
        let deny = AgentDecision.payload(allow: false)
        XCTAssertEqual(deny, #"{"hookSpecificOutput":{"decision":{"behavior":"deny"},"hookEventName":"PermissionRequest"}}"#,
                       "the documented shape: behavior only — exit code 2 is ignored for PermissionRequest, so this JSON is the only control")
        XCTAssertEqual(AgentDecision.fileName(sessionID: "s", requestID: "r"), "s-r.json")
    }

    /// Owner report 2026-10-14: OpenCode running in kitty, nothing on the notch — both switches were off and the page
    /// only talked about a hook OpenCode does not use. An empty page must name the real reason.
    func testAnEmptyAgentsPageNamesWhyItIsEmpty() throws {
        typealias R = AgentSessionRules
        XCTAssertEqual(R.emptyReasonKey(enabled: false, hookInstalled: true, openCodeOn: true, openCodeMissing: false),
                       R.emptyReasonKeys[0], "the master switch off is said first, whatever else is set")
        XCTAssertEqual(R.emptyReasonKey(enabled: true, hookInstalled: false, openCodeOn: true, openCodeMissing: true), R.emptyReasonKeys[1])
        XCTAssertEqual(R.emptyReasonKey(enabled: true, hookInstalled: false, openCodeOn: false, openCodeMissing: false), R.emptyReasonKeys[2])
        XCTAssertNil(R.emptyReasonKey(enabled: true, hookInstalled: false, openCodeOn: true, openCodeMissing: false),
                     "OpenCode needs no hook: with it on, an empty page is just an empty page")
        XCTAssertNil(R.emptyReasonKey(enabled: true, hookInstalled: true, openCodeOn: false, openCodeMissing: false))
        let store = try L10nFixture.load()
        for k in R.emptyReasonKeys { XCTAssertFalse((store.entries[k]?.en ?? "").isEmpty, k) }
    }

    // MARK: P8 — presentation (OneNotch / Notch Crew)

    private func session(_ id: String, _ agent: AgentKind, _ status: AgentSession.Status, at t: TimeInterval,
                         question: Bool = false) -> AgentSession {
        let at = Date(timeIntervalSince1970: t)
        var s = AgentSession(id: id, agent: agent, cwd: "/tmp/\(id)", transcriptPath: nil, startedAt: at, updatedAt: at, status: status,
                             lastTool: nil, lastPrompt: nil, agentPID: nil, terminal: AgentEvents.Terminal(), eventCount: 1)
        s.questionPending = question
        return s
    }

    func testActivityTellsAFinishedTurnFromSomethingThatMustBeAnswered() {
        typealias R = AgentSessionRules
        XCTAssertEqual(R.activity(of: session("a", .claude, .running(tool: nil), at: 0)), .thinking)
        XCTAssertEqual(R.activity(of: session("a", .claude, .running(tool: "Bash"), at: 0)), .working)
        XCTAssertEqual(R.activity(of: session("a", .claude, .running(tool: "AskUserQuestion"), at: 0, question: true)), .waiting,
                       "a question arrives as a running tool, but the person must act")
        XCTAssertEqual(R.activity(of: session("a", .claude, .waitingForInput, at: 0)), .yourTurn,
                       "a finished turn is not an orange alert")
        let p = AgentSession.PendingPermission(requestID: "r", toolName: "Bash", summary: nil, since: Date())
        XCTAssertEqual(R.activity(of: session("a", .claude, .waitingForPermission(p), at: 0)), .waiting)
        XCTAssertEqual(R.activity(of: session("a", .claude, .ended, at: 0)), .ended)
    }

    func testTheWingShowsTheMostUrgentAgentFirstAndCountsEveryLiveSession() throws {
        typealias R = AgentSessionRules
        XCTAssertNil(R.wingSummary([session("x", .claude, .ended, at: 9)]), "nothing live ⇒ no wing")
        let p = AgentSession.PendingPermission(requestID: "r", toolName: "Bash", summary: nil, since: Date())
        let all = [session("a", .claude, .running(tool: "Bash"), at: 30),
                   session("b", .opencode, .waitingForPermission(p), at: 10),
                   session("c", .claude, .waitingForInput, at: 50),
                   session("d", .codex, .ended, at: 60)]
        let w = try XCTUnwrap(R.wingSummary(all))
        XCTAssertEqual(w.activity, .waiting, "the most urgent activity wins")
        XCTAssertEqual(w.agents, [.opencode, .claude], "most urgent agent first, each agent once, ended ones left out")
        XCTAssertEqual(w.live, 3)
        XCTAssertEqual(w.waiting, 1)
        let three = [session("a", .claude, .running(tool: nil), at: 1), session("b", .codex, .running(tool: nil), at: 2),
                     session("c", .opencode, .running(tool: nil), at: 3)]
        XCTAssertEqual(try XCTUnwrap(R.wingSummary(three)).agents.count, 2, "at most two tiles are drawn")
        XCTAssertEqual(try XCTUnwrap(R.wingSummary(three)).agents.first, .opencode, "ties go to the most recent")
        let store = try L10nFixture.load()
        for k in R.wingLabelKeys { XCTAssertFalse((store.entries[k]?.en ?? "").isEmpty, k) }
        XCTAssertEqual(Set(Activity.allCasesForTest.map(R.wingLabelKey)), Set(R.wingLabelKeys))
    }

    func testEveryAgentHasAGlyphThatExistsAndItsOwnTile() {
        for kind in AgentKind.allCases {
            XCTAssertNotNil(NSImage(systemSymbolName: kind.brand.glyph, accessibilityDescription: nil), kind.brand.glyph)
        }
        XCTAssertEqual(Set(AgentKind.allCases.map(\.brand.glyph)).count, AgentKind.allCases.count, "no two agents share a glyph")
    }
}


extension AgentSessionTests {
    /// Owner's screenshot 2026-10-14: a finished turn showed "Waiting for you" and was counted as waiting in the header
    /// while the wing showed a green "your turn" check; and a Claude desktop session offered "Copy and open terminal".
    func testAFinishedTurnIsYourTurnAndADesktopSessionIsAnApp() {
        let done = session("a", .claude, .waitingForInput, at: 0)
        XCTAssertEqual(AgentSessionRules.rowStatusKey(done), "Tới lượt bạn")
        XCTAssertEqual(AgentSessionRules.rowStatusKey(session("b", .claude, .running(tool: "AskUserQuestion"), at: 0, question: true)), "Đang chờ bạn")
        var desktop = session("c", .claude, .waitingForInput, at: 0)
        desktop.terminal.entrypoint = "claude-desktop"
        desktop.terminal.bundleID = "com.anthropic.claudefordesktop"
        XCTAssertTrue(AgentTalk.runsInApp(desktop))
        XCTAssertEqual(AgentTalk.sendLabelKey(for: desktop), "Chép và mở app", "an app is not called a terminal")
        var kitty = session("d", .claude, .waitingForInput, at: 0)
        kitty.terminal.bundleID = "com.apple.Terminal"
        XCTAssertFalse(AgentTalk.runsInApp(kitty))
        XCTAssertEqual(AgentTalk.sendLabelKey(for: kitty), "Chép và mở terminal")
    }
}

extension AgentSessionTests {
    /// P10 — OneNotch's "Sort sessions by" and "Keep finished sessions visible".
    func testTheListFollowsTheChosenOrderAndCanHideEndedSessions() {
        var a = session("a", .claude, .running(tool: nil), at: 100); a.startedAt = Date(timeIntervalSince1970: 10)
        var b = session("b", .codex, .waitingForInput, at: 50); b.startedAt = Date(timeIntervalSince1970: 30)
        var c = session("c", .opencode, .ended, at: 200); c.startedAt = Date(timeIntervalSince1970: 20)
        let all = [a, b, c]
        typealias R = AgentSessionRules
        XCTAssertEqual(R.ordered(all, mode: .priority, keepFinished: true).map(\.id), ["b", "a", "c"], "your turn before running before ended")
        XCTAssertEqual(R.ordered(all, mode: .recency, keepFinished: true).map(\.id), ["c", "a", "b"])
        XCTAssertEqual(R.ordered(all, mode: .newest, keepFinished: true).map(\.id), ["b", "c", "a"])
        XCTAssertEqual(R.ordered(all, mode: .recency, keepFinished: false).map(\.id), ["a", "b"], "ended sessions left out")
        XCTAssertEqual(R.SortMode.parse("bogus"), .priority, "an unknown stored value falls back to the default")
        XCTAssertEqual(R.SortMode.parse(nil), .priority)
    }
}

private typealias Activity = AgentSessionRules.Activity
private extension AgentSessionRules.Activity {
    static let allCasesForTest: [AgentSessionRules.Activity] = [.ended, .yourTurn, .thinking, .working, .waiting]
}
