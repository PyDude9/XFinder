import XCTest

/// P5b — OpenCode through its own CLI. The JSON below has the shapes measured from OpenCode 2.0.27's API (an isolated
/// `opencode serve`, 2026-10-14); ids are the real format (`ses_…`, `per_…`).
final class OpenCodeRulesTests: XCTestCase {

    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testActiveSessionsAreTheKeysOfData() {
        XCTAssertEqual(OpenCodeRules.parseActive(data(#"{"data":{"ses_ec88f3234ffeMrBmRsjr0FKmNM":{"type":"running"},"x y":{}}}"#)),
                       ["ses_ec88f3234ffeMrBmRsjr0FKmNM"])
        XCTAssertEqual(OpenCodeRules.parseActive(data(#"{"data":{}}"#)), [])
        XCTAssertNil(OpenCodeRules.parseActive(data(#"{"_tag":"UnauthorizedError","message":"Authentication required"}"#)),
                     "a 401 body is not 'no sessions'")
    }

    func testSessionListTimesAreMillisecondsAndChildrenKeepTheirParent() throws {
        let json = #"""
        {"data":[
          {"id":"ses_a1","title":"Fix login","time":{"created":1791931463845,"updated":1791931472084},"location":{"directory":"/w/app"},"outcome":"succeeded"},
          {"id":"ses_b2","parentID":"ses_a1","title":"","time":{"created":1791931463845,"updated":1791931463845},"location":{"directory":"/w/app"}},
          {"id":"bogus","time":{"created":1}}
        ],"cursor":{}}
        """#
        let list = try XCTUnwrap(OpenCodeRules.parseSessions(data(json)))
        XCTAssertEqual(list.map(\.id), ["ses_a1", "ses_b2"], "an id that is not ses_… is dropped")
        XCTAssertEqual(list[0].created.timeIntervalSince1970, 1_791_931_463.845, accuracy: 0.001)
        XCTAssertEqual(list[0].title, "Fix login")
        XCTAssertEqual(list[0].directory, "/w/app")
        XCTAssertNil(list[1].title, "an empty title is no title")
        XCTAssertEqual(list[1].parentID, "ses_a1")
    }

    func testPendingRequestsCarryTheCommand() throws {
        let json = #"{"data":[{"id":"per_1377136ad001M5QsL2gPMdRrI2","sessionID":"ses_ec88f3234ffeMrBmRsjr0FKmNM","action":"shell","resources":["echo xfinder-probe"],"metadata":{"command":"echo xfinder-probe"}},{"id":"nope","sessionID":"ses_x","action":"shell","resources":[]}]}"#
        let reqs = try XCTUnwrap(OpenCodeRules.parsePermissions(data(json)))
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].action, "shell")
        XCTAssertEqual(reqs[0].command, "echo xfinder-probe")
    }

    func testReplyIsOnceOrRejectNeverAlwaysAndRefusesForeignIds() throws {
        let allow = try XCTUnwrap(OpenCodeRules.replyArguments(sessionID: "ses_A1", requestID: "per_B2", allow: true))
        XCTAssertEqual(allow, ["api", "session.permission.reply", "--param", "sessionID=ses_A1", "--param", "requestID=per_B2",
                               "-d", #"{"decision":"once"}"#])
        let deny = try XCTUnwrap(OpenCodeRules.replyArguments(sessionID: "ses_A1", requestID: "per_B2", allow: false))
        XCTAssertEqual(deny.last, #"{"decision":"reject"}"#)
        XCTAssertFalse((allow + deny).joined().contains("always"), "always would save a rule in the person's config")
        XCTAssertNil(OpenCodeRules.replyArguments(sessionID: "ses_A1 --server http://evil", requestID: "per_B2", allow: true))
        XCTAssertNil(OpenCodeRules.replyArguments(sessionID: "ses_A1", requestID: "per_", allow: true))
        XCTAssertNil(OpenCodeRules.permissionListArguments(sessionID: "../ses"))
        XCTAssertEqual(OpenCodeRules.listArguments(limit: 500).last, "limit=50")
    }

    func testSessionStatusesFromTheAPIsView() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func info(_ id: String, updatedAgo: TimeInterval, parent: String? = nil, title: String? = nil) -> OpenCodeRules.SessionInfo {
            .init(id: id, title: title, directory: "/w/\(id)", parentID: parent, created: now.addingTimeInterval(-3600),
                  updated: now.addingTimeInterval(-updatedAgo), outcome: nil)
        }
        let infos = [info("ses_perm", updatedAgo: 5, title: "Refactor"), info("ses_run", updatedAgo: 1), info("ses_idle", updatedAgo: 60),
                     info("ses_old", updatedAgo: 7200), info("ses_child", updatedAgo: 1, parent: "ses_run"), info("ses_gone", updatedAgo: 1800)]
        let pending = [OpenCodeRules.PendingRequest(id: "per_1", sessionID: "ses_perm", action: "shell", resources: ["rm -rf build"],
                                                    command: "rm -rf build", message: nil)]
        let seen = ["per_1": now.addingTimeInterval(-12)]
        let rows = OpenCodeRules.sessions(info: infos, active: ["ses_run", "ses_perm"], pending: pending, clientOpen: true,
                                          now: now, answered: [], firstSeen: seen)
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(byID["ses_perm"]?.status, .waitingForPermission(.init(requestID: "per_1", toolName: "shell",
                                                                             summary: "rm -rf build", since: seen["per_1"]!)))
        XCTAssertEqual(byID["ses_perm"]?.displayName, "Refactor", "OpenCode's title names the row")
        XCTAssertEqual(byID["ses_run"]?.status, .running(tool: nil))
        XCTAssertEqual(byID["ses_idle"]?.status, .waitingForInput, "idle, recent, a client open ⇒ the person's turn")
        XCTAssertEqual(byID["ses_gone"]?.status, .ended, "idle past the stale window ⇒ ended")
        XCTAssertNil(byID["ses_old"], "ended more than an hour ago ⇒ not listed")
        XCTAssertNil(byID["ses_child"], "a subagent session is not a row of its own")
        XCTAssertTrue(rows.allSatisfy { $0.agent == .opencode })

        let noClient = OpenCodeRules.sessions(info: infos, active: [], pending: [], clientOpen: false, now: now, answered: [], firstSeen: [:])
        XCTAssertEqual(noClient.first { $0.id == "ses_idle" }?.status, .ended, "no terminal client ⇒ nobody has the prompt")

        let answered = OpenCodeRules.sessions(info: infos, active: ["ses_perm"], pending: pending, clientOpen: true,
                                              now: now, answered: ["per_1"], firstSeen: seen)
        XCTAssertEqual(answered.first { $0.id == "ses_perm" }?.status, .running(tool: nil), "answered here ⇒ the card goes at once")
    }

    func testOnlyATerminalClientCountsNotTheService() {
        XCTAssertFalse(OpenCodeRules.clientRunning(psCommands: "/Users/me/.opencode/bin/opencode serve --service\n/sbin/launchd"))
        XCTAssertTrue(OpenCodeRules.clientRunning(psCommands: "/Users/me/.opencode/bin/opencode serve --service\nopencode"))
        XCTAssertTrue(OpenCodeRules.clientRunning(psCommands: "/opt/homebrew/bin/opencode /Users/me/project"))
        XCTAssertFalse(OpenCodeRules.clientRunning(psCommands: "/usr/bin/vim notes-about-opencode\nless opencode.log"))
    }
}
