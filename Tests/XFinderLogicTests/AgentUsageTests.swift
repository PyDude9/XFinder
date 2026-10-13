import XCTest

/// §3b #37 — lines shaped exactly like the ones measured in ~/.claude/projects and ~/.codex/sessions (2026-10-13).
final class AgentUsageTests: XCTestCase {
    typealias U = AgentUsage

    func claude(_ id: String, req: String = "r1", ts: String, out: Int, input: Int = 2, cr: Int = 100, cc: Int = 50) -> String {
        """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(id)","model":"claude","usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(cc),"cache_read_input_tokens":\(cr),"output_tokens":\(out),"service_tier":"standard"}}}
        """
    }

    func testRepeatedLinesOfOneMessageCountOnce() throws {
        // The measured shape: one message written once per content block, the streamed output growing.
        let lines = [claude("m1", ts: "2026-10-13T09:00:00.000Z", out: 10),
                     claude("m1", ts: "2026-10-13T09:00:01.000Z", out: 969),
                     claude("m1", ts: "2026-10-13T09:00:01.500Z", out: 969),
                     claude("m2", ts: "2026-10-13T09:30:00Z", out: 100)].compactMap(U.parseClaudeLine)
        XCTAssertEqual(lines.count, 4)
        let t = U.totals(lines, since: .distantPast)
        XCTAssertEqual(t.messages, 2, "5 882 lines were 2 256 messages here — never sum lines")
        XCTAssertEqual(t.output, 969 + 100, "the streamed message's LAST (largest) count")
        XCTAssertEqual(t.input, (2 + 50) * 2, "fresh input = prompt + cache writes; cache reads are not counted")
    }

    func testWindowCutsByTime() throws {
        let lines = [claude("old", ts: "2026-10-13T01:00:00Z", out: 500), claude("new", ts: "2026-10-13T08:00:00Z", out: 7)]
            .compactMap(U.parseClaudeLine)
        let since = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T05:00:00Z"))
        XCTAssertEqual(U.totals(lines, since: since).output, 7)
    }

    func testNonAssistantAndBrokenLinesAreIgnored() {
        XCTAssertNil(U.parseClaudeLine(#"{"type":"user","timestamp":"2026-10-13T09:00:00Z","message":{"id":"x","usage":{"output_tokens":5}}}"#))
        XCTAssertNil(U.parseClaudeLine(#"{"type":"assistant","message":{"id":"x","usage":{"output_tokens":5}}}"#), "no timestamp")
        XCTAssertNil(U.parseClaudeLine("not json \"usage\" \"assistant\""))
    }

    func codex(ts: String, primary: String, secondary: String = "null") -> String {
        """
        {"timestamp":"\(ts)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"codex","primary":\(primary),"secondary":\(secondary),"credits":{"has_credits":false},"plan_type":"plus"}}}
        """
    }

    func testCodexReadsItsOwnWindowsAndSkipsNullOnes() throws {
        let p = #"{"used_percent":10.0,"window_minutes":300,"resets_at":1789660056}"#
        let s = #"{"used_percent":25.0,"window_minutes":10080,"resets_at":1790071253}"#
        XCTAssertNil(U.parseCodexLine(codex(ts: "2026-09-23T09:33:58.389Z", primary: "null")), "most events carry primary: null")
        let a = try XCTUnwrap(U.parseCodexLine(codex(ts: "2026-09-17T10:55:31.546Z", primary: p, secondary: s)))
        XCTAssertEqual(a.primary?.usedPercent, 10)
        XCTAssertEqual(a.primary?.windowMinutes, 300)
        XCTAssertEqual(a.secondary?.windowMinutes, 10080)
        XCTAssertEqual(a.plan, "plus")
        let b = try XCTUnwrap(U.parseCodexLine(codex(ts: "2026-09-18T10:00:00Z", primary: #"{"used_percent":40,"window_minutes":300,"resets_at":1789700000}"#)))
        XCTAssertEqual(U.latest([b, a]), b, "the newest record wins whatever the order read")
    }

    func testAWindowPastItsResetIsNotCurrent() {
        let w = U.CodexWindow(usedPercent: 90, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertFalse(U.isCurrent(w, now: Date(timeIntervalSince1970: 2_000)), "after the reset the old 90 % says nothing")
        XCTAssertTrue(U.isCurrent(w, now: Date(timeIntervalSince1970: 500)))
    }

    func testCompactNumbers() {
        XCTAssertEqual(U.compact(1_536_991, decimalComma: false), "1.5M")
        XCTAssertEqual(U.compact(1_536_991, decimalComma: true), "1,5M")
        XCTAssertEqual(U.compact(3_000, decimalComma: false), "3K")
        XCTAssertEqual(U.compact(812, decimalComma: false), "812")
        XCTAssertEqual(U.compact(651_799_843, decimalComma: false), "651.8M")
    }
}
