import XCTest

/// P7a — windowless Claude Code sessions: the launch, the stream, the record and how it merges with hook rows.
final class WindowlessRulesTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let sid = "11111111-2222-4333-8444-555555555555"

    // MARK: Launch

    func testTheLaunchFixesTheSessionIdAndRefusesAnythingButAUUID() {
        XCTAssertEqual(WindowlessRules.claudeArguments(sessionID: sid, resume: false),
                       ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--session-id", sid])
        XCTAssertEqual(WindowlessRules.claudeArguments(sessionID: sid, resume: true)?.suffix(2), ["--resume", sid])
        XCTAssertNil(WindowlessRules.claudeArguments(sessionID: "--dangerously-skip-permissions", resume: true),
                     "the id becomes a process argument: only a UUID may")
        XCTAssertNil(WindowlessRules.claudeArguments(sessionID: "abc", resume: false))
    }

    func testAUserTurnIsOneJSONLineWithTheTextUntouched() throws {
        let text = "Sửa lỗi \"đăng nhập\"\nrồi chạy test 🙂"
        let data = try XCTUnwrap(WindowlessRules.userTurnLine(text))
        XCTAssertEqual(data.last, 0x0A, "one line, newline-terminated")
        XCTAssertEqual(data.dropLast().filter { $0 == 0x0A }.count, 0, "the text's own newline is escaped inside the JSON")
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any])
        XCTAssertEqual(obj["type"] as? String, "user")
        XCTAssertTrue(obj["parent_tool_use_id"] is NSNull)
        let msg = try XCTUnwrap(obj["message"] as? [String: Any])
        XCTAssertEqual(msg["role"] as? String, "user")
        XCTAssertEqual((msg["content"] as? String)?.unicodeScalars.map(\.value), text.unicodeScalars.map(\.value))
    }

    func testAMessageKeepsItsLinesButLosesControlCharacters() {
        XCTAssertEqual(WindowlessRules.cleanMessage("  one\ntwo\u{1B}[31m\u{07}  "), "one\ntwo[31m")
        XCTAssertNil(WindowlessRules.cleanMessage(" \n\u{1B} "))
        XCTAssertEqual(WindowlessRules.cleanMessage(String(repeating: "x", count: 30_000))?.count, WindowlessRules.maxLength)
    }

    func testTheLoginEnvironmentParsesAndDropsNoise() {
        var raw = Data("Last login: today\nPATH=/opt/homebrew/bin:/usr/bin".utf8)   // a startup file printed something
        raw.append(0)
        raw.append(contentsOf: Array("HOME=/Users/me".utf8)); raw.append(0)
        raw.append(contentsOf: Array("EMPTY=".utf8)); raw.append(0)
        raw.append(contentsOf: Array("NOEQUALS".utf8)); raw.append(0)
        raw.append(contentsOf: Array("WEIRD NAME=x".utf8)); raw.append(0)
        let env = WindowlessRules.parseEnvironment(raw)
        XCTAssertNil(env["PATH"], "a name containing the noise's newline is not a variable")
        XCTAssertEqual(env["HOME"], "/Users/me")
        XCTAssertEqual(env["EMPTY"], "")
        XCTAssertNil(env["NOEQUALS"]); XCTAssertNil(env["WEIRD NAME"])
    }

    func testTheChildEnvironmentCarriesTheMarkerAndNotAnotherClaudeOrTerminal() {
        let login = ["PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/me", "CLAUDECODE": "1", "TMUX": "/tmp/x,1,0",
                     "__CFBundleIdentifier": "com.xfinder.app", "CLAUDE_CODE_MESSAGING_TOKEN": "t"]
        let env = WindowlessRules.childEnvironment(login: login, fallback: [:], home: "/Users/me")
        XCTAssertEqual(env[WindowlessRules.markerVariable], "1")
        for k in ["CLAUDECODE", "TMUX", "__CFBundleIdentifier", "CLAUDE_CODE_MESSAGING_TOKEN"] { XCTAssertNil(env[k], k) }
        XCTAssertEqual(env["PATH"], "/opt/homebrew/bin:/usr/bin", "the login PATH is used as is")
        let fallback = WindowlessRules.childEnvironment(login: nil, fallback: ["PATH": "/usr/bin:/bin"], home: "/Users/me")
        XCTAssertEqual(fallback["PATH"], "/opt/homebrew/bin:/usr/local/bin:/Users/me/.local/bin:/usr/bin:/bin",
                       "launchd's PATH would miss Homebrew and ~/.local/bin")
        XCTAssertEqual(WindowlessRules.claudeCandidates(path: "/a:/b", home: "/h").prefix(3), ["/a/claude", "/b/claude", "/h/.local/bin/claude"])
    }

    // MARK: Stream

    func testTheStreamLinesThatMatterAndTheOnesThatDoNot() {
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"system","subtype":"ui_invalidate","event":"ui.render","session_id":"x"}"#), .ignored,
                       "measured: an undocumented line type — ignored, never an error")
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"system","subtype":"init","session_id":"s","model":"claude-x"}"#),
                       .initialized(sessionID: "s", model: "claude-x"))
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"text","text":"Done."}]}}"#),
                       .assistantText("Done."))
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"assistant","parent_tool_use_id":null,"message":{"content":[{"type":"tool_use","name":"Bash","input":{}}]}}"#),
                       .toolUse("Bash"))
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"assistant","parent_tool_use_id":"toolu_1","message":{"content":[{"type":"text","text":"sub-agent"}]}}"#),
                       .ignored, "a sub-agent's chatter is not the session's answer")
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"user","message":{"content":[{"type":"tool_result","content":"secret output"}]}}"#), .ignored)
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"result","subtype":"success","is_error":false,"result":"ok","total_cost_usd":0.12}"#),
                       .result(isError: false, text: "ok", costUSD: 0.12))
        XCTAssertEqual(WindowlessRules.parse(line: #"{"type":"result","subtype":"error_max_turns","result":"x"}"#),
                       .result(isError: true, text: "x", costUSD: nil))
        XCTAssertEqual(WindowlessRules.parse(line: "Last login: today"), .ignored)
    }

    // MARK: Record

    func testARecordFollowsATurnFromSendToResultToExit() {
        var r = WindowlessRules.Record(sessionID: sid, cwd: "/w/app", startedAt: t0, updatedAt: t0)
        XCTAssertEqual(r.phase, .idle)
        r.sent("fix it", at: t0)
        XCTAssertEqual(r.phase, .working(tool: nil))
        r.apply(.toolUse("Edit"), at: t0)
        XCTAssertEqual(r.phase, .working(tool: "Edit"))
        r.apply(.assistantText("Fixed."), at: t0)
        r.apply(.assistantText("Fixed."), at: t0)
        XCTAssertEqual(r.transcript.filter { $0.role == .agent }.count, 1, "a repeated answer is one entry")
        r.apply(.result(isError: false, text: "Fixed.", costUSD: 0.05), at: t0)
        XCTAssertEqual(r.phase, .waiting)
        XCTAssertEqual(r.costUSD, 0.05)
        XCTAssertEqual(r.lastAgentText, "Fixed.")
        r.exited(code: 0, at: t0)
        XCTAssertTrue(r.isEnded)
        r.sent("too late", at: t0)
        XCTAssertNotEqual(r.lastPersonText, "too late", "an ended session takes no turn")
        r.apply(.assistantText("late"), at: t0)
        XCTAssertNotEqual(r.lastAgentText, "late")
    }

    func testTheTranscriptIsCappedAndAnErrorBecomesANote() {
        var r = WindowlessRules.Record(sessionID: sid, cwd: "/w", startedAt: t0, updatedAt: t0)
        for i in 0..<60 { r.sent("m\(i)", at: t0) }
        XCTAssertEqual(r.transcript.count, WindowlessRules.transcriptCap)
        XCTAssertEqual(r.transcript.last?.text, "m59")
        r.apply(.assistantText(String(repeating: "y", count: 9_000)), at: t0)
        XCTAssertEqual(r.lastAgentText?.count, WindowlessRules.entryCap + 1, "long text is cut, with an ellipsis")
        r.apply(.result(isError: true, text: "API error", costUSD: nil), at: t0)
        XCTAssertEqual(r.transcript.last?.role, .note)
        XCTAssertEqual(r.lastError, "API error")
    }

    // MARK: Rows + merge

    func testARecordBecomesAHostedRowAndARepliesGoToItsStdin() {
        var r = WindowlessRules.Record(sessionID: sid, cwd: "/w/app", startedAt: t0, updatedAt: t0)
        r.sent("go", at: t0); r.apply(.toolUse("Bash"), at: t0)
        let row = WindowlessRules.session(for: r)
        XCTAssertTrue(row.hostedByXFinder)
        XCTAssertTrue(row.terminal.windowless)
        XCTAssertEqual(row.status, .running(tool: "Bash"))
        XCTAssertEqual(row.listID, "claude:\(sid)")
        XCTAssertEqual(AgentTalk.route(for: row), .windowless(sessionID: sid))
        XCTAssertEqual(AgentTalk.decision(for: row, route: .windowless(sessionID: sid)), .queue, "mid-turn: hold until the result line")
        r.apply(.result(isError: false, text: nil, costUSD: nil), at: t0)
        let waiting = WindowlessRules.session(for: r)
        XCTAssertEqual(AgentTalk.decision(for: waiting, route: AgentTalk.route(for: waiting)), .sendNow)
        XCTAssertEqual(AgentTalk.sendLabelKey(for: waiting), "Gửi tin")
    }

    func testAHookRowForAHostedSessionKeepsItsPermissionButGainsTheStdinRoute() {
        var r = WindowlessRules.Record(sessionID: sid, cwd: "/w/app", startedAt: t0, updatedAt: t0)
        r.sent("go", at: t0)
        var hook = WindowlessRules.session(for: r)
        hook.hostedByXFinder = false
        hook.status = .waitingForPermission(.init(requestID: "r1", toolName: "Bash", summary: "rm x", since: t0))
        let merged = WindowlessRules.merged(hookSessions: [hook], records: [r])
        XCTAssertEqual(merged.count, 1, "one session, one row")
        XCTAssertTrue(merged[0].hostedByXFinder)
        guard case .waitingForPermission(let p) = merged[0].status else { return XCTFail("only the hook knows a permission request is pending") }
        XCTAssertEqual(p.requestID, "r1")
        guard case .blocked = AgentTalk.decision(for: merged[0], route: AgentTalk.route(for: merged[0])) else {
            return XCTFail("a permission request blocks a reply — the card answers it")
        }
        r.exited(code: 0, at: t0)
        let after = WindowlessRules.merged(hookSessions: [hook], records: [r])
        XCTAssertFalse(after[0].hostedByXFinder, "no process, no stdin")
        XCTAssertEqual(after[0].status, .ended)
    }

    func testAWindowlessRowXFinderNoLongerHostsIsCopyOnly() {
        var t = AgentEvents.Terminal(bundleID: "com.xfinder.app")
        t.windowless = true
        let s = AgentSession(id: sid, agent: .claude, cwd: "/w", transcriptPath: nil, startedAt: t0, updatedAt: t0,
                             status: .waitingForInput, lastTool: nil, lastPrompt: nil, agentPID: 42, terminal: t, eventCount: 1)
        XCTAssertEqual(AgentTalk.route(for: s), .copyAndActivate(bundleID: nil), "never bring XFinder itself forward as 'the terminal'")
    }

    func testTheHookRecordsTheWindowlessMarker() throws {
        let line = #"{"received_at":"2026-10-14T05:00:00Z","request_id":"r","agent":"claude","env":{"ppid":42,"windowless":"1"},"payload":{"hook_event_name":"Stop","session_id":"a"}}"#
        XCTAssertTrue(try XCTUnwrap(AgentEvents.parse(line: line)).terminal.windowless)
        let plain = #"{"received_at":"2026-10-14T05:00:00Z","request_id":"r","agent":"claude","env":{"ppid":42,"windowless":""},"payload":{"hook_event_name":"Stop","session_id":"a"}}"#
        XCTAssertFalse(try XCTUnwrap(AgentEvents.parse(line: plain)).terminal.windowless)
    }

    func testEveryKeyHandedToL10nThroughAVariableIsTranslated() throws {
        let keys = WindowlessRules.phaseKeys + WindowlessRules.errorKeys
        XCTAssertGreaterThan(keys.count, 6)
        for p: WindowlessRules.Phase in [.idle, .working(tool: nil), .waiting, .ended(code: 0)] {
            XCTAssertTrue(WindowlessRules.phaseKeys.contains(WindowlessRules.phaseKey(p)))
        }
        let entries = try XCTUnwrap(try L10nFixture.raw()["entries"] as? [String: [String: Any]])
        for k in keys { XCTAssertFalse((entries[k]?["en"] as? String ?? "").isEmpty, "missing from the store: \(k)") }
    }
}
