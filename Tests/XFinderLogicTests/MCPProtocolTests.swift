import XCTest
import Foundation

/// D: the Clipboard MCP server's protocol, with fixtures instead of a pipe and a database.
final class MCPProtocolTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func rec(_ text: String, type: ContentType = .text, app: String = "Ghi chú", bundle: String = "com.apple.Notes",
             minutesAgo: Double = 0, id: UUID = UUID(), ocr: String? = nil) -> ClipboardRecord {
        ClipboardRecord(id: id, type: type, timestamp: t0.addingTimeInterval(-minutesAgo * 60), sourceBundleID: bundle,
                        sourceAppName: app, textSnippet: text, thumbnailPath: nil, payloadPath: nil, ocrText: ocr, pinboardID: nil, metadata: [:])
    }

    func ctx(enabled: Bool = true, _ records: [ClipboardRecord], full: [UUID: String] = [:]) -> MCP.Context {
        MCP.Context(enabled: enabled, appVersion: "1.2.3", records: { records }, fullText: { full[$0.id] ?? $0.textSnippet })
    }

    func json(_ s: String?) -> [String: Any] {
        guard let s, let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }

    func toolText(_ s: String?) -> String {
        let r = json(s)["result"] as? [String: Any]
        let content = r?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }

    // MARK: Handshake and envelopes

    func testInitializeAnswersWithVersionToolsCapabilityAndServerInfo() {
        let out = json(MCP.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#, context: ctx([])))
        let result = out["result"] as? [String: Any]
        XCTAssertEqual(out["id"] as? Int, 1)
        XCTAssertEqual(result?["protocolVersion"] as? String, MCP.protocolVersion)
        XCTAssertNotNil((result?["capabilities"] as? [String: Any])?["tools"])
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "xfinder-clipboard")
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["version"] as? String, "1.2.3")
    }

    func testNotificationsGetNoReplyAndUnknownMethodsGetMinus32601() {
        XCTAssertNil(MCP.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, context: ctx([])))
        XCTAssertNil(MCP.handle(line: "   ", context: ctx([])), "blank lines are ignored")
        let out = json(MCP.handle(line: #"{"jsonrpc":"2.0","id":"a","method":"resources/list"}"#, context: ctx([])))
        XCTAssertEqual((out["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual(out["id"] as? String, "a", "the id comes back whatever its type")
    }

    func testParseErrorHasNullIdAndCodeMinus32700() {
        let out = json(MCP.handle(line: "{not json", context: ctx([])))
        XCTAssertTrue(out["id"] is NSNull)
        XCTAssertEqual((out["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testToolsListDescribesThreeToolsWithSchemas() {
        let out = json(MCP.handle(line: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#, context: ctx([])))
        let tools = (out["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        XCTAssertEqual(tools.map { $0["name"] as? String }, ["clipboard_list_recent", "clipboard_search", "clipboard_get"])
        for t in tools { XCTAssertNotNil(t["inputSchema"], "\(t["name"] ?? "") has no schema") }
    }

    // MARK: The fences

    func testWhenDisabledEveryToolCallIsAnErrorButHandshakeStillWorks() {
        let c = ctx(enabled: false, [rec("secret-ish")])
        let call = json(MCP.handle(line: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"clipboard_list_recent","arguments":{}}}"#, context: c))
        XCTAssertEqual((call["error"] as? [String: Any])?["code"] as? Int, -32000)
        XCTAssertTrue(((call["error"] as? [String: Any])?["message"] as? String ?? "").contains("turned off"))
        let list = json(MCP.handle(line: #"{"jsonrpc":"2.0","id":4,"method":"tools/list"}"#, context: c))
        XCTAssertNotNil(list["result"], "listing tools is harmless; only calls are fenced")
    }

    func testPasswordManagerRecordsNeverAppearInAnyTool() {
        let pw = rec("hunter2", app: "1Password", bundle: "com.1password.1password7")
        let ok = rec("hello world")
        let c = ctx([pw, ok], full: [pw.id: "hunter2"])
        XCTAssertFalse(toolText(MCP.handle(line: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"clipboard_list_recent","arguments":{}}}"#, context: c)).contains("hunter2"))
        XCTAssertFalse(toolText(MCP.handle(line: #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"clipboard_search","arguments":{"query":"hunter"}}}"#, context: c)).contains("hunter2"))
        let get = json(MCP.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"clipboard_get\",\"arguments\":{\"id\":\"\(pw.id.uuidString)\"}}}", context: c))
        let r = get["result"] as? [String: Any]
        XCTAssertEqual(r?["isError"] as? Bool, true, "a hidden record reads as missing, not as forbidden")
        XCTAssertEqual(MCP.visible([pw, ok]).map(\.id), [ok.id])
    }

    // MARK: Search, recent, get

    func testSearchMatchesSnippetOCRTitleAndAppCaseInsensitivelyNewestFirst() {
        let a = rec("Bảng màu Hokusai", minutesAgo: 10)
        let b = rec("x", minutesAgo: 5, ocr: "hokusai wave")
        let c = rec("y", app: "Hokusai Viewer", minutesAgo: 1)
        let d = rec("unrelated", minutesAgo: 0)
        let hits = MCP.search([a, b, c, d], query: "HOKUSAI", type: nil, limit: 10)
        XCTAssertEqual(hits.map(\.id), [c.id, b.id, a.id], "newest first, every field searched")
        XCTAssertEqual(MCP.search([a, b, c, d], query: "hokusai", type: .code, limit: 10).count, 0, "type filter applies")
        XCTAssertEqual(MCP.search([a, b, c, d], query: "   ", type: nil, limit: 10).count, 0, "an empty query matches nothing")
        XCTAssertEqual(MCP.search([a, b, c, d], query: "hokusai", type: nil, limit: 2).count, 2, "limit")
    }

    func testRecentIsNewestFirstAndLimitsClamp() {
        let recs = (0..<150).map { rec("item \($0)", minutesAgo: Double($0)) }
        XCTAssertEqual(MCP.recent(recs, type: nil, limit: MCP.clampLimit(500)).count, MCP.maxLimit, "clamped to 100")
        XCTAssertEqual(MCP.clampLimit(nil), MCP.defaultLimit)
        XCTAssertEqual(MCP.clampLimit(0), 1)
        XCTAssertEqual(MCP.clampLimit("7"), 7)
        XCTAssertEqual(MCP.clampLimit(3.0), 3)
        XCTAssertEqual(MCP.recent(recs, type: nil, limit: 3).map(\.textSnippet), ["item 0", "item 1", "item 2"])
    }

    func testGetReturnsTheFullTextNotTheSnippet() {
        let r = rec("a 200-char preview…")
        let c = ctx([r], full: [r.id: "the whole 5 000-character clip"])
        let out = MCP.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"clipboard_get\",\"arguments\":{\"id\":\"\(r.id.uuidString)\"}}}", context: c)
        XCTAssertEqual(toolText(out), "the whole 5 000-character clip")
        let bad = json(MCP.handle(line: #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"clipboard_get","arguments":{"id":"nope"}}}"#, context: c))
        XCTAssertEqual((bad["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testSummaryLineIsOneLineWithIdTypeAndTruncatedSnippet() {
        let r = rec(String(repeating: "x", count: 300) + "\nline two", type: .code)
        let line = MCP.summaryLine(r)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.hasPrefix(r.id.uuidString + " · code · "))
        XCTAssertTrue(line.hasSuffix("…"), "snippets over 200 characters are cut, the full text is one clipboard_get away")
    }

    func testEncodeIsOneLineWithSortedKeys() {
        let s = MCP.encode(["b": 1, "a": ["z": 1, "y": 2]])
        XCTAssertEqual(s, #"{"a":{"y":2,"z":1},"b":1}"#)
    }
}
