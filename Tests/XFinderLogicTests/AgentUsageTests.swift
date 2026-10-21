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

    // MARK: Codex token totals — shaped exactly like `payload.info.total_token_usage` (measured 2026-10-13)

    func codexTokenCount(ts: String, input: Int, cached: Int, cacheWrite: Int = 0, output: Int, reasoning: Int = 0) -> String {
        let total = input + output
        return """
        {"timestamp":"\(ts)","ordinal":1,"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":\(cacheWrite),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)},"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":\(cacheWrite),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(total)},"model_context_window":380000},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":null,"secondary":null,"credits":null,"individual_limit":null,"spend_control_reached":null,"plan_type":null,"rate_limit_reached_type":null}}}
        """
    }

    func testParseCodexTokensReadsTheMeasuredShape() throws {
        // Measured 2026-10-13: cached_input_tokens is a SUBSET of input_tokens, not additional — fresh input is the
        // difference, matching Claude's "prompt + cache writes, cache reads not counted" sense.
        let line = codexTokenCount(ts: "2026-09-23T09:33:09.422Z", input: 19035, cached: 3968, output: 132)
        let p = try XCTUnwrap(U.parseCodexTokens(line))
        XCTAssertEqual(p.input, 19035 - 3968)
        XCTAssertEqual(p.output, 132)
        let expectedTime = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-23T09:33:09Z"))
        XCTAssertEqual(p.time.timeIntervalSince1970, expectedTime.timeIntervalSince1970, accuracy: 1)
    }

    func testParseCodexTokensIgnoresNonTokenCountLines() {
        XCTAssertNil(U.parseCodexTokens(#"{"timestamp":"2026-09-23T09:33:09Z","payload":{"type":"task_started"}}"#))
        XCTAssertNil(U.parseCodexTokens("not json at all"))
        XCTAssertNil(U.parseCodexTokens(#"{"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1}}}}"#), "no timestamp")
    }

    func testCodexWindowTotalsIsImmuneToRepeatedEvents() throws {
        // Exact duplicate consecutive events were measured on this Mac (2 of 137). The cumulative-difference
        // approach reads the same "last point at/after since" both times, so a repeat changes nothing.
        let session = [
            codexTokenCount(ts: "2026-10-13T08:00:00Z", input: 1000, cached: 0, output: 100),
            codexTokenCount(ts: "2026-10-13T09:00:00Z", input: 2000, cached: 500, output: 300),
            codexTokenCount(ts: "2026-10-13T09:00:00Z", input: 2000, cached: 500, output: 300), // exact repeat
        ].compactMap(U.parseCodexTokens)
        XCTAssertEqual(session.count, 3)
        let since = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T08:30:00Z"))
        let t = U.codexWindowTotals([session], since: since)
        // baseline = the point before `since` (input 1000), last-at-or-after = the later point (input 1500 fresh)
        XCTAssertEqual(t.input, (2000 - 500) - 1000)
        XCTAssertEqual(t.output, 300 - 100)
        XCTAssertEqual(t.messages, 2, "both points at/after `since`, repeat included — messages counts points, not de-duplicated")
    }

    func testCodexWindowTotalsSubtractsBaselineWhenSessionStartedBeforeTheWindow() throws {
        let session = [
            codexTokenCount(ts: "2026-10-13T06:00:00Z", input: 500, cached: 0, output: 50), // before the window
            codexTokenCount(ts: "2026-10-13T08:00:00Z", input: 900, cached: 100, output: 120),
        ].compactMap(U.parseCodexTokens)
        let since = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T07:00:00Z"))
        let t = U.codexWindowTotals([session], since: since)
        XCTAssertEqual(t.input, (900 - 100) - 500, "only the usage SINCE the window start, not the whole session")
        XCTAssertEqual(t.output, 120 - 50)
        XCTAssertEqual(t.messages, 1)
    }

    func testCodexWindowTotalsIsZeroForASessionEntirelyBeforeTheWindow() throws {
        let session = [
            codexTokenCount(ts: "2026-10-13T01:00:00Z", input: 500, cached: 0, output: 50),
            codexTokenCount(ts: "2026-10-13T02:00:00Z", input: 900, cached: 100, output: 120),
        ].compactMap(U.parseCodexTokens)
        let since = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-13T08:00:00Z"))
        let t = U.codexWindowTotals([session], since: since)
        XCTAssertEqual(t.input, 0)
        XCTAssertEqual(t.output, 0)
        XCTAssertEqual(t.messages, 0, "no points at/after `since`, so this session contributes nothing")
    }

    func testCodexWindowTotalsSumsAcrossSessions() throws {
        let since = Date(timeIntervalSince1970: 1_000_000)
        let sessionA = [AgentUsage.CodexTokenPoint(time: since.addingTimeInterval(-100), input: 10, output: 5),
                        AgentUsage.CodexTokenPoint(time: since.addingTimeInterval(100), input: 60, output: 25)]
        let sessionB = [AgentUsage.CodexTokenPoint(time: since.addingTimeInterval(50), input: 200, output: 40)]
        let t = U.codexWindowTotals([sessionA, sessionB], since: since)
        XCTAssertEqual(t.input, (60 - 10) + 200, "session B has no point before `since`, so its baseline is 0")
        XCTAssertEqual(t.output, (25 - 5) + 40)
        XCTAssertEqual(t.messages, 2, "one point at/after `since` per session")
    }

    // MARK: Reading only what was appended (2026-10-21)

    func testLinesAreSplitAcrossChunksAndTheUnfinishedEndWaits() {
        var tail = AgentUsage.LogTail()
        XCTAssertEqual(AgentUsage.lines(in: Data("a\nbb\ncc".utf8), tail: &tail).map { String(decoding: $0, as: UTF8.self) }, ["a", "bb"])
        XCTAssertEqual(tail.pending, Data("cc".utf8), "the line still being written waits for its newline")
        XCTAssertEqual(AgentUsage.lines(in: Data("c\n\nd".utf8), tail: &tail).map { String(decoding: $0, as: UTF8.self) }, ["ccc"])
        XCTAssertEqual(tail.offset, 11, "offset counts every byte read, so the next scan seeks past them")
        XCTAssertEqual(tail.pending, Data("d".utf8))
    }

    func testAShrunkFileIsReadAgainFromTheStart() {
        let tail = AgentUsage.LogTail(offset: 500, pending: Data())
        XCTAssertTrue(AgentUsage.mustRestart(tail, fileSize: 100))
        XCTAssertFalse(AgentUsage.mustRestart(tail, fileSize: 500))
        XCTAssertFalse(AgentUsage.mustRestart(tail, fileSize: 900))
    }

    func testTheMarkerIsFoundInBytes() {
        XCTAssertTrue(AgentUsage.contains(Data("{\"usage\":{}}".utf8), "\"usage\""))
        XCTAssertFalse(AgentUsage.contains(Data("{\"type\":\"user\"}".utf8), "\"usage\""))
    }
}
