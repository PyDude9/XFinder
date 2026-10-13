import XCTest

/// P5c — notices at the notch and "Phiên gần đây".
final class AgentNotifyRecentTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, _ status: AgentSession.Status, agent: AgentKind = .claude, cwd: String = "/w/app") -> AgentSession {
        AgentSession(id: id, agent: agent, cwd: cwd, transcriptPath: nil, startedAt: t0, updatedAt: t0, status: status,
                     lastTool: nil, lastPrompt: nil, agentPID: nil, terminal: AgentEvents.Terminal(), eventCount: 1)
    }
    private func perm(_ rid: String) -> AgentSession.PendingPermission {
        .init(requestID: rid, toolName: "Bash", summary: "make", since: t0)
    }
    private let on = AgentNotify.Settings(permission: true, finished: true)

    // MARK: Notices

    func testTheFirstSnapshotIsABaselineNotNews() {
        XCTAssertEqual(AgentNotify.events(old: nil, new: [session("a", .waitingForPermission(perm("r1")))], settings: on), [],
                       "launching XFinder must not announce sessions that were already waiting")
    }

    func testANewRequestIsAnnouncedOnceAndANewerOneAgain() {
        let waiting = session("a", .waitingForPermission(perm("r1")))
        let first = AgentNotify.events(old: [session("a", .running(tool: "Bash"))], new: [waiting], settings: on)
        XCTAssertEqual(first, [.needsApproval(waiting, perm("r1"))])
        XCTAssertEqual(AgentNotify.events(old: [waiting], new: [waiting], settings: on), [], "the same request is not re-announced")
        let next = session("a", .waitingForPermission(perm("r2")))
        XCTAssertEqual(AgentNotify.events(old: [waiting], new: [next], settings: on).count, 1, "a different request is news")
        XCTAssertEqual(AgentNotify.events(old: [], new: [waiting], settings: on).count, 1, "a session that appears already waiting is news")
    }

    func testOnlyARunningSessionThatStopsIsFinished() {
        let idle = session("a", .waitingForInput)
        XCTAssertEqual(AgentNotify.events(old: [session("a", .running(tool: nil))], new: [idle], settings: on), [.finished(idle)])
        XCTAssertEqual(AgentNotify.events(old: [session("a", .waitingForPermission(perm("r")))], new: [idle], settings: on), [],
                       "answering a request is not 'your turn'")
        XCTAssertEqual(AgentNotify.events(old: [], new: [idle], settings: on), [], "appearing idle is not a finished turn")
        XCTAssertEqual(AgentNotify.events(old: [session("a", .running(tool: nil))], new: [session("a", .ended)], settings: on), [])
    }

    func testEachSwitchSilencesOnlyItsOwnNotice() {
        let old = [session("a", .running(tool: nil)), session("b", .running(tool: nil))]
        let new = [session("a", .waitingForPermission(perm("r"))), session("b", .waitingForInput)]
        XCTAssertEqual(AgentNotify.events(old: old, new: new, settings: .init(permission: false, finished: true)).count, 1)
        XCTAssertEqual(AgentNotify.events(old: old, new: new, settings: .init(permission: true, finished: false)).count, 1)
        XCTAssertEqual(AgentNotify.events(old: old, new: new, settings: .init(permission: false, finished: false)), [])
    }

    func testTheSameIdUnderAnotherAgentIsAnotherSession() {
        let old = [session("same", .running(tool: nil), agent: .claude)]
        let new = [session("same", .waitingForInput, agent: .codex)]
        XCTAssertEqual(AgentNotify.events(old: old, new: new, settings: on), [], "a Codex session never inherits a Claude session's state")
    }

    func testNoticesNameTheAgentAndOpenTheAgentsPage() throws {
        let item = AgentNotify.item(for: .needsApproval(session("a", .waitingForPermission(perm("r")), agent: .codex), perm("r")))
        XCTAssertEqual(item.kind, .agent)
        XCTAssertEqual(item.titleKey, "Cần bạn duyệt")
        XCTAssertEqual(item.detail, "Codex · app · Bash")
        XCTAssertEqual(item.buttons, [.openAgents])
        let entries = try XCTUnwrap(try L10nFixture.raw()["entries"] as? [String: [String: Any]])
        for key in ["Cần bạn duyệt", "Tới lượt bạn"] {
            let en = entries[key]?["en"] as? String ?? ""
            XCTAssertFalse(en.isEmpty, "\(key) must be translated in the store — it reaches the screen through a variable")
        }
    }

    // MARK: Recent sessions

    func testClaudeTranscriptHeadsYieldOnlyTerminalSessions() {
        let filler = String(repeating: #"{"type":"agent-setting","x":"\#(String(repeating: "y", count: 400))"}"# + "\n", count: 50)
        let cli = filler + #"{"type":"attachment","cwd":"\/Users\/me\/My \"Proj\"","sessionId":"5b0c-11","entrypoint":"cli"}"# + "\n"
        let e = AgentRecent.claudeEntry(head: Data(cli.utf8), fileStem: "5b0c-11", modified: t0)
        XCTAssertEqual(e?.cwd, #"/Users/me/My "Proj""#, "the value is JSON-unescaped")
        XCTAssertEqual(e?.sessionID, "5b0c-11")
        XCTAssertEqual(e?.agent, .claude)
        let desktop = #"{"cwd":"/w","sessionId":"x1","entrypoint":"claude-desktop"}"#
        XCTAssertNil(AgentRecent.claudeEntry(head: Data(desktop.utf8), fileStem: "x1", modified: t0), "desktop-app sessions are not listed")
        let cut = #"{"cwd":"/w/unterminat"#
        XCTAssertNil(AgentRecent.claudeEntry(head: Data(("{\"entrypoint\":\"cli\"," + cut).utf8), fileStem: "x", modified: t0),
                     "a value cut by the head limit is not guessed")
        let evil = #"{"cwd":"/w","sessionId":"x; rm -rf ~","entrypoint":"cli"}"#
        XCTAssertNil(AgentRecent.claudeEntry(head: Data(evil.utf8), fileStem: "x", modified: t0), "an id that is not shell-safe is dropped")
    }

    func testCodexSessionMetaYieldsOnlyTerminalSessions() {
        let tui = #"{"timestamp":"2026-09-23T10:00:00Z","type":"session_meta","payload":{"id":"019a-ab","cwd":"/w/api","originator":"codex-tui","source":"cli","base_instructions":{"text":"…"}}}"#
        XCTAssertEqual(AgentRecent.codexEntry(firstLine: tui, modified: t0)?.sessionID, "019a-ab")
        let desktop = #"{"type":"session_meta","payload":{"id":"019a-cd","cwd":"/w","originator":"Codex Desktop","source":"vscode"}}"#
        XCTAssertNil(AgentRecent.codexEntry(firstLine: desktop, modified: t0))
        XCTAssertNil(AgentRecent.codexEntry(firstLine: #"{"type":"event_msg","payload":{}}"#, modified: t0))
    }

    func testMergedIsNewestFirstWithoutLiveSessionsOrDuplicates() {
        func e(_ id: String, _ ago: TimeInterval, _ a: AgentKind = .claude) -> AgentRecent.Entry {
            .init(agent: a, sessionID: id, cwd: "/w/\(id)", updated: t0.addingTimeInterval(-ago), title: nil)
        }
        let all = [e("old", 900), e("live", 10), e("new", 60), e("new", 60), e("oc", 30, .opencode)]
        let m = AgentRecent.merged(all, live: ["claude:live"], limit: 3)
        XCTAssertEqual(m.map(\.id), ["opencode:oc", "claude:new", "claude:old"])
        XCTAssertEqual(AgentRecent.merged(all, live: [], limit: 2).count, 2)
        XCTAssertEqual(m[1].resumeCommand, "cd '/w/new' && claude --resume 'new'")
    }
}
