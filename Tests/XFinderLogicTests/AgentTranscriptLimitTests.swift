import XCTest
import Foundation

/// The Claude desktop app runs no StopFailure hook when a turn is refused at the usage limit (measured 2026-10-14), so the
/// row is corrected from the transcript. These tests use lines shaped exactly like the measured one.
final class AgentTranscriptLimitTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_791_985_288)       // 2026-10-14T13:41:28Z, the prompt

    private func line(_ d: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: d), encoding: .utf8)!
    }

    private func refusal(at ts: String = "2026-10-14T13:41:29.145Z", sidechain: Bool = false, status: String = "rejected") -> String {
        line(["type": "assistant", "isSidechain": sidechain, "isApiErrorMessage": true, "error": "rate_limit",
              "apiErrorStatus": 429, "apiError": "usage_limit_reached", "timestamp": ts,
              "quotaLimits": ["status": status, "resetsAt": 1_791_987_600, "rateLimitType": "five_hour"]])
    }

    private func answer(at ts: String) -> String {
        line(["type": "assistant", "isSidechain": false, "timestamp": ts, "message": ["role": "assistant"]])
    }

    private func session(updatedAt: Date, status: AgentSession.Status = .running(tool: nil),
                         agent: AgentKind = .claude) -> AgentSession {
        AgentSession(id: "ec69d774", agent: agent, cwd: "/tmp", transcriptPath: "/Users/x/.claude/projects/p/ec69d774.jsonl",
                     startedAt: t0.addingTimeInterval(-600), updatedAt: updatedAt, status: status,
                     lastTool: nil, lastPrompt: nil, agentPID: 1, terminal: AgentEvents.Terminal(), eventCount: 3)
    }

    func testTheMeasuredRefusalLineIsRead() throws {
        let tail = "{\"torn line\n" + answer(at: "2026-10-14T13:40:00Z") + "\n" + refusal() + "\n"
        let limit = try XCTUnwrap(AgentSessionRules.transcriptLimit(tail: tail))
        XCTAssertEqual(limit.since.timeIntervalSince1970, 1_791_985_289.145, accuracy: 0.01)
        XCTAssertEqual(limit.resetsAt, Date(timeIntervalSince1970: 1_791_987_600), "resetsAt is epoch seconds — 21:20 ICT")
    }

    func testARealAnswerAfterTheRefusalLiftsIt() {
        let tail = refusal() + "\n" + answer(at: "2026-10-14T14:20:05Z") + "\n"
        XCTAssertNil(AgentSessionRules.transcriptLimit(tail: tail), "Claude continued after the reset: no longer stopped")
    }

    /// Review finding: a later, different API error must not leave an old refusal on screen.
    func testALaterDifferentErrorEndsTheRefusal() {
        let overloaded = line(["type": "assistant", "isSidechain": false, "isApiErrorMessage": true, "error": "overloaded",
                               "timestamp": "2026-10-14T13:50:00Z"])
        XCTAssertNil(AgentSessionRules.transcriptLimit(tail: refusal() + "\n" + overloaded))
        XCTAssertNil(AgentSessionRules.transcriptLimit(tail: refusal() + "\n" + refusal(at: "2026-10-14T13:50:00Z", status: "allowed_warning")))
    }

    /// Review finding: a symlink inside ~/.claude/projects must not point the read at another file.
    func testASymlinkOutOfProjectsIsNotRead() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("xf-home-\(UUID().uuidString)")
        let projects = home.appendingPathComponent(".claude/projects/p")
        try fm.createDirectory(at: projects, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let outside = home.appendingPathComponent("secret.jsonl")
        try Data().write(to: outside)
        let link = projects.appendingPathComponent("evil.jsonl")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let inside = projects.appendingPathComponent("real.jsonl")
        try Data().write(to: inside)
        var s = session(updatedAt: t0)
        s.transcriptPath = inside.path
        XCTAssertTrue(AgentSessionRules.shouldReadTranscript(s, now: t0.addingTimeInterval(10), home: home.path),
                      "positive control: a real transcript under projects is read")
        s.transcriptPath = link.path
        XCTAssertFalse(AgentSessionRules.shouldReadTranscript(s, now: t0.addingTimeInterval(10), home: home.path))
    }

    func testSidechainsOtherErrorsAndWarningsDoNotDecide() {
        XCTAssertNil(AgentSessionRules.transcriptLimit(tail: refusal(sidechain: true)), "a subagent's refusal is its own")
        XCTAssertNil(AgentSessionRules.transcriptLimit(tail: refusal(status: "allowed_warning")), "a warning is not a refusal")
        let other = line(["type": "assistant", "isApiErrorMessage": true, "error": "server_error",
                          "timestamp": "2026-10-14T13:41:29Z"])
        XCTAssertNil(AgentSessionRules.transcriptLimit(tail: other))
        // A later sidechain answer must not lift a main-thread refusal either.
        let tail = refusal() + "\n" + line(["type": "assistant", "isSidechain": true, "timestamp": "2026-10-14T13:45:00Z"])
        XCTAssertNotNil(AgentSessionRules.transcriptLimit(tail: tail))
    }

    func testARefusedRunningSessionBecomesALimitStop() throws {
        let limit = AgentSessionRules.transcriptLimit(tail: refusal())
        let s = AgentSessionRules.applyingTranscriptLimit(session(updatedAt: t0), limit)
        XCTAssertEqual(s.status, .waitingForInput)
        XCTAssertTrue(s.isLimitStopped)
        XCTAssertEqual(s.limitStop?.reason, "rate_limit")
    }

    func testAHookEventAfterTheRefusalLeavesTheRowAlone() {
        let limit = AgentSessionRules.transcriptLimit(tail: refusal())
        let later = session(updatedAt: t0.addingTimeInterval(120))          // a tool ran two minutes later
        XCTAssertEqual(AgentSessionRules.applyingTranscriptLimit(later, limit), later)
        let waiting = session(updatedAt: t0, status: .waitingForInput)
        XCTAssertEqual(AgentSessionRules.applyingTranscriptLimit(waiting, limit), waiting, "only a running row is corrected")
        let codex = session(updatedAt: t0, agent: .codex)
        XCTAssertEqual(AgentSessionRules.applyingTranscriptLimit(codex, limit), codex, "a Claude transcript decides Claude rows")
    }

    /// The other agent's fix matched "hit your session limit" in the PROMPT text — so pasting a message that quotes it
    /// (exactly what happened at 22:32) flagged a working session as stopped. A prompt is never evidence.
    func testAPromptQuotingTheLimitTextIsNotALimitStop() throws {
        let raw = """
        {"received_at":"2026-10-14T15:32:21Z","agent":"claude","env":{},"payload":{"session_id":"ec69d774","hook_event_name":"UserPromptSubmit","prompt":"<failures>Agent failed: You've hit your session limit · resets 9:20pm</failures>"}}
        """
        let events = AgentEvents.parse(jsonl: raw + "\n")
        XCTAssertEqual(events.count, 1, "the fixture must parse, or this test proves nothing")
        let sessions = AgentSessionRules.sessions(from: events, now: t0.addingTimeInterval(7000), answered: [], isAlive: { _ in true })
        XCTAssertEqual(sessions.first?.status, .running(tool: nil))
        XCTAssertNil(sessions.first?.limitStop)
    }

    func testOnlyTranscriptsUnderClaudeProjectsAreRead() {
        let now = t0.addingTimeInterval(10)
        var s = session(updatedAt: t0)
        s.transcriptPath = "/Users/x/.claude/projects/p/ec69d774.jsonl"
        XCTAssertTrue(AgentSessionRules.shouldReadTranscript(s, now: now, home: "/Users/x"))
        s.transcriptPath = "/Users/x/.claude/projects/../../.ssh/id_rsa.jsonl"
        XCTAssertFalse(AgentSessionRules.shouldReadTranscript(s, now: now, home: "/Users/x"), "no climbing out of projects")
        s.transcriptPath = "/etc/passwd"
        XCTAssertFalse(AgentSessionRules.shouldReadTranscript(s, now: now, home: "/Users/x"))
        s.transcriptPath = "/Users/x/.claude/projects/p/ec69d774.jsonl"
        XCTAssertFalse(AgentSessionRules.shouldReadTranscript(s, now: t0.addingTimeInterval(1), home: "/Users/x"),
                       "an active turn (an event a second ago) is not read")
    }
}
