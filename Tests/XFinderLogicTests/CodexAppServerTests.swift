import XCTest

/// P11 — a windowless Codex session over `codex app-server`: the messages XFinder writes, the reading of what comes
/// back, and how the record turns into a notch row (an approval becomes the usual Allow / Deny card).
final class CodexAppServerTests: XCTestCase {
    typealias C = CodexAppServer

    private func obj(_ line: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] ?? [:]
    }

    func testTheRequestsAreOneLineEachWithTheMeasuredShape() {
        let ini = C.initialize(version: "1.4.0")
        XCTAssertTrue(ini.hasSuffix("\n") && !ini.dropLast().contains("\n"), "one JSON object per line")
        XCTAssertEqual(obj(ini)["method"] as? String, "initialize")
        XCTAssertNil(obj(ini)["jsonrpc"], "codex app-server messages carry no jsonrpc field")
        let start = obj(C.threadStart(cwd: "/w/Dự án"))
        let params = start["params"] as? [String: Any] ?? [:]
        XCTAssertEqual(params["approvalPolicy"] as? String, "on-request", "Codex asks before acting outside the folder")
        XCTAssertEqual(params["sandbox"] as? String, "workspace-write")
        XCTAssertEqual(params["cwd"] as? String, "/w/Dự án")
        let turn = obj(C.turnStart(id: 7, threadID: "t1", text: "dòng 1\ndòng 2"))
        let input = ((turn["params"] as? [String: Any])?["input"] as? [[String: Any]])?.first
        XCTAssertEqual(input?["type"] as? String, "text")
        XCTAssertEqual(input?["text"] as? String, "dòng 1\ndòng 2", "newlines survive inside the JSON string")
        XCTAssertEqual(obj(C.approvalReply(rawID: "12", allow: true, legacy: false))["id"] as? Int, 12, "a numeric id is echoed as a number")
        XCTAssertEqual(obj(C.approvalReply(rawID: "\"ab\"", allow: false, legacy: false))["id"] as? String, "ab", "a string id as a string")
        XCTAssertEqual((obj(C.approvalReply(rawID: "3", allow: false, legacy: false))["result"] as? [String: Any])?["decision"] as? String, "decline")
        XCTAssertEqual((obj(C.approvalReply(rawID: "3", allow: true, legacy: true))["result"] as? [String: Any])?["decision"] as? String, "approved")
        XCTAssertNotNil(obj(C.unsupportedReply(rawID: "9"))["error"], "an unhandled server request gets an error, never silence")
    }

    func testParsingTheStream() {
        XCTAssertEqual(C.parse(line: #"{"id":1,"result":{"codexHome":"/x"}}"#), .initializeOK)
        XCTAssertEqual(C.parse(line: #"{"id":2,"result":{"model":"m","thread":{"id":"th"}}}"#), .threadStarted(threadID: "th", model: "m"))
        XCTAssertEqual(C.parse(line: #"{"id":2,"error":{"message":"not logged in"}}"#), .requestFailed(id: 2, message: "not logged in"))
        XCTAssertEqual(C.parse(line: #"{"method":"turn/started","params":{"threadId":"th","turn":{"id":"tu"}}}"#), .turnStarted(turnID: "tu"))
        XCTAssertEqual(C.parse(line: #"{"method":"item/started","params":{"item":{"type":"commandExecution","command":"ls"}}}"#), .tool("Bash"))
        XCTAssertEqual(C.parse(line: #"{"method":"item/completed","params":{"item":{"type":"agentMessage","text":"Xong"}}}"#), .agentMessage("Xong"))
        XCTAssertEqual(C.parse(line: #"{"method":"item/completed","params":{"item":{"type":"reasoning","text":"x"}}}"#), .ignored, "reasoning is not shown")
        XCTAssertEqual(C.parse(line: #"{"method":"turn/completed","params":{"turn":{"status":"failed","error":{"message":"quota"}}}}"#),
                       .turnCompleted(status: "failed", error: "quota", code: nil))
        XCTAssertEqual(C.parse(line: #"{"id":5,"method":"item/commandExecution/requestApproval","params":{"command":"rm -rf build"}}"#),
                       .approval(rawID: "5", kind: .command, summary: "rm -rf build", legacy: false))
        XCTAssertEqual(C.parse(line: #"{"id":"r1","method":"execCommandApproval","params":{"command":["git","push"]}}"#),
                       .approval(rawID: "\"r1\"", kind: .command, summary: "git push", legacy: true))
        XCTAssertEqual(C.parse(line: #"{"id":6,"method":"item/tool/requestUserInput","params":{}}"#), .otherRequest(rawID: "6"))
        XCTAssertEqual(C.parse(line: "not json"), .ignored)
    }

    func testTheRecordShowsAnApprovalAsThePermissionCardAndClearsItWhenTheTurnEnds() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        var r = WindowlessRules.Record(sessionID: "x", cwd: "/w", startedAt: t, updatedAt: t)
        r.agent = .codex
        r.applyCodex(.threadStarted(threadID: "th", model: "m"), at: t)
        XCTAssertEqual(r.threadID, "th")
        r.sent("làm đi", at: t)
        r.applyCodex(.turnStarted(turnID: "tu"), at: t)
        r.applyCodex(.approval(rawID: "5", kind: .command, summary: "rm -rf build", legacy: false), at: t)
        let row = WindowlessRules.session(for: r)
        XCTAssertEqual(row.agent, .codex)
        guard case .waitingForPermission(let p) = row.status else { return XCTFail("an approval must show as a permission card") }
        XCTAssertEqual(p.requestID, "5")
        XCTAssertEqual(p.toolName, "Bash")
        XCTAssertEqual(p.summary, "rm -rf build")
        r.applyCodex(.agentMessage("Đã xoá"), at: t)
        r.applyCodex(.turnCompleted(status: "completed", error: nil, code: nil), at: t)
        XCTAssertNil(r.pendingApproval)
        XCTAssertNil(r.activeTurnID)
        XCTAssertEqual(r.phase, .waiting)
        XCTAssertEqual(r.turns, 1, "a Codex turn is counted once (sent), not again when it completes")
        XCTAssertEqual(r.lastAgentText, "Đã xoá")
        guard case .waitingForInput = WindowlessRules.session(for: r).status else { return XCTFail("after the turn: your turn") }
    }

    func testCodexIsFoundWhereItsInstallerLinksIt() {
        let c = C.candidates(path: "/opt/homebrew/bin:/usr/bin", home: "/Users/u")
        XCTAssertEqual(c.first, "/opt/homebrew/bin/codex", "PATH first")
        XCTAssertTrue(c.contains("/Users/u/.local/bin/codex"), "the standalone installer's link (measured)")
        XCTAssertEqual(Set(c).count, c.count)
    }
}
