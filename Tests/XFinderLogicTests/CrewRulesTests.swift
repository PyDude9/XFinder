import XCTest

/// P7b — crews: templates, launch flags, inbox requests and the relay engine.
final class CrewRulesTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func delivered(_ effects: [CrewRules.Effect]) -> [String] {
        effects.compactMap { if case .deliver(let to, _) = $0 { return to }; return nil }
    }
    private func req(_ from: String, _ to: [String], _ text: String = "please review") -> CrewRules.Request {
        CrewRules.Request(from: from, to: to, text: text)
    }

    // MARK: Templates + launch

    func testTemplatesHaveValidRolesALeadAndReadOnlyReviewers() {
        for t in CrewRules.Template.allCases {
            XCTAssertGreaterThanOrEqual(t.roles.count, 2)
            XCTAssertEqual(t.lead, t.roles[0])
            XCTAssertFalse(t.lead.readOnly, "the lead builds")
            XCTAssertTrue(t.roles.dropFirst().allSatisfy(\.readOnly), "reviewers cannot edit files")
            XCTAssertEqual(Set(t.roles.map(\.name)).count, t.roles.count)
            for r in t.roles { XCTAssertTrue(CrewRules.isValidRole(r.name), r.name) }
        }
        XCTAssertFalse(CrewRules.isValidRole("Builder")); XCTAssertFalse(CrewRules.isValidRole("1x"))
        XCTAssertFalse(CrewRules.isValidRole("a b")); XCTAssertFalse(CrewRules.isValidRole("all;rm"))
        XCTAssertTrue(CrewRules.isValidRole("critic-safety"))
    }

    func testMembersAlwaysAskAndReviewersHaveNoEditTools() {
        let t = CrewRules.Template.pipeline
        let builder = CrewRules.launchArguments(for: t.roles[0], in: t)
        let reviewer = CrewRules.launchArguments(for: t.roles[1], in: t)
        XCTAssertEqual(Array(builder.prefix(2)), ["--permission-mode", "manual"],
                       "measured: 2.1.296 has no 'default' mode; 'manual' asks — whatever the person's own default is")
        XCTAssertFalse(builder.contains("--disallowedTools"))
        let i = try? XCTUnwrap(reviewer.firstIndex(of: "--disallowedTools"))
        XCTAssertEqual(i.map { reviewer[$0 + 1] }, "Edit,Write,MultiEdit,NotebookEdit", "one argument, not a variadic list")
        for a in builder + reviewer { XCTAssertFalse(a.contains("bypassPermissions") || a.contains("--allowedTools"), "no approval is ever skipped") }
    }

    func testTheSystemPromptIsASCIIAndTellsTheRulesOfTheCrew() {
        for t in CrewRules.Template.allCases {
            for r in t.roles {
                let p = CrewRules.systemPrompt(for: r, in: t)
                XCTAssertTrue(p.unicodeScalars.allSatisfy(\.isASCII), "an argument: Process decomposes non-ASCII")
                XCTAssertTrue(p.contains("\"\(r.name)\""))
                XCTAssertTrue(p.contains("xfinder-crew send"))
                XCTAssertTrue(p.contains("not from the person") && p.contains("never run a destructive command"),
                              "a crewmate's message is a request to evaluate, not an order (design review)")
                for other in t.roles { XCTAssertTrue(p.contains(other.name)) }
            }
        }
    }

    // MARK: Requests

    func testARequestTakesItsSenderFromItsTokenNeverFromTheFile() throws {
        let tokens = ["tok-b": "builder", "tok-r": "reviewer"]
        let roles = ["builder", "reviewer"]
        func data(_ d: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: d) }
        let r = try XCTUnwrap(CrewRules.parseRequest(data(["token": "tok-b", "from": "reviewer", "to": "reviewer", "text": " look\u{1B}[2J "]),
                                                     tokens: tokens, roles: roles))
        XCTAssertEqual(r.from, "builder", "the forged 'from' is ignored")
        XCTAssertEqual(r.to, ["reviewer"])
        XCTAssertEqual(r.text, "look[2J")
        XCTAssertNil(CrewRules.parseRequest(data(["token": "nope", "to": "reviewer", "text": "x"]), tokens: tokens, roles: roles))
        XCTAssertNil(CrewRules.parseRequest(data(["token": "tok-b", "to": "builder", "text": "x"]), tokens: tokens, roles: roles), "not to oneself")
        XCTAssertNil(CrewRules.parseRequest(data(["token": "tok-b", "to": "stranger", "text": "x"]), tokens: tokens, roles: roles))
        XCTAssertNil(CrewRules.parseRequest(data(["token": "tok-b", "to": "reviewer", "text": "   "]), tokens: tokens, roles: roles))
        XCTAssertNil(CrewRules.parseRequest(Data("not json".utf8), tokens: tokens, roles: roles))
        let all = try XCTUnwrap(CrewRules.parseRequest(data(["token": "tok-r", "to": "all", "text": "hi"]), tokens: tokens, roles: roles))
        XCTAssertEqual(all.to, ["builder"])
        let long = try XCTUnwrap(CrewRules.parseRequest(data(["token": "tok-b", "to": "reviewer", "text": String(repeating: "x", count: 9_000)]),
                                                        tokens: tokens, roles: roles))
        XCTAssertEqual(long.text.count, CrewRules.maxMessage)
    }

    func testThePermissionCardReadsACrewSend() {
        XCTAssertEqual(CrewRules.describeSend(command: #"xfinder-crew send reviewer "Xem giúp hàm parse""#)?.to, "reviewer")
        XCTAssertEqual(CrewRules.describeSend(command: #"xfinder-crew send reviewer "Xem giúp hàm parse""#)?.text, "Xem giúp hàm parse")
        XCTAssertEqual(CrewRules.describeSend(command: "/Users/me/Library/Application Support/XFinder/Agents/crew/bin/xfinder-crew send all 'done'")?.to, nil,
                       "a path with spaces is split — the card falls back to the raw command")
        XCTAssertEqual(CrewRules.describeSend(command: "xfinder-crew send all done for now")?.text, "done for now")
        XCTAssertNil(CrewRules.describeSend(command: "rm -rf / && xfinder-crew send reviewer hi"))
        XCTAssertNil(CrewRules.describeSend(command: "xfinder-crew who"))
        XCTAssertNil(CrewRules.describeSend(command: "xfinder-crew send Reviewer hi"))
    }

    // MARK: Relay

    func testAMessageWaitsForABusyMemberAndOnlyOneIsInFlightPerTarget() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer"], busy: ["builder"])
        XCTAssertEqual(delivered(r.receive(req("reviewer", ["builder"], "q1"), at: t0)), [], "the lead is mid-turn")
        XCTAssertEqual(delivered(r.turnEnded("builder", result: "step 1", at: t0)), ["builder"], "released when its turn ends")
        XCTAssertEqual(delivered(r.receive(req("reviewer", ["builder"], "q2"), at: t0)), [], "one delivery in flight per target")
        XCTAssertEqual(r.queue.count, 1)
    }

    func testAnAnswerGoesBackToTheAskerOnceAndNeverPingPongs() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer"], busy: [])
        XCTAssertEqual(delivered(r.receive(req("builder", ["reviewer"]), at: t0)), ["reviewer"])
        XCTAssertEqual(r.pendingReply["reviewer"], "builder")
        let back = r.turnEnded("reviewer", result: "Found 2 bugs", at: t0)
        guard case .deliver(let to, let text)? = back.first else { return XCTFail("the answer goes back") }
        XCTAssertEqual(to, "builder")
        XCTAssertTrue(text.hasPrefix("[crew] Reply from reviewer: Found 2 bugs"))
        XCTAssertTrue(r.pendingReply.isEmpty, "a reply asks for no reply")
        XCTAssertEqual(delivered(r.turnEnded("builder", result: "fixed", at: t0)), [], "the builder's answer to a reply goes nowhere by itself")
        XCTAssertEqual(r.board.map(\.kind), [.message, .reply])
    }

    func testAllFansOutAndRepliesQueueBehindABusyAsker() {
        var r = CrewRules.Relay(roles: ["builder", "critic-a", "critic-b"], busy: [])
        XCTAssertEqual(Set(delivered(r.receive(req("builder", ["critic-a", "critic-b"]), at: t0))), ["critic-a", "critic-b"])
        XCTAssertEqual(delivered(r.turnEnded("critic-a", result: "A", at: t0)), ["builder"])
        XCTAssertEqual(delivered(r.turnEnded("critic-b", result: "B", at: t0)), [], "the builder is busy with A's reply")
        XCTAssertEqual(delivered(r.turnEnded("builder", result: "ok", at: t0)), ["builder"], "then B's reply")
    }

    func testAStoppedMemberFailsWhatWaitsForItAndForItsAnswer() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer"], busy: ["builder"])
        _ = r.receive(req("reviewer", ["builder"]), at: t0)                 // queued for the busy builder
        _ = r.memberEnded("builder", at: t0)
        XCTAssertTrue(r.queue.isEmpty)
        XCTAssertTrue(r.board.contains { $0.kind == .failed })
        var s = CrewRules.Relay(roles: ["builder", "reviewer"], busy: [])
        _ = s.receive(req("builder", ["reviewer"]), at: t0)                 // in flight, answer owed to the builder
        _ = s.memberEnded("builder", at: t0)
        XCTAssertTrue(s.pendingReply.isEmpty, "nobody left to take the answer")
        XCTAssertEqual(delivered(s.turnEnded("reviewer", result: "x", at: t0)), [])
        XCTAssertEqual(delivered(s.receive(req("reviewer", ["builder"]), at: t0)), [], "a message to an ended member is not queued")
        XCTAssertTrue(s.queue.isEmpty)
    }

    func testPauseHoldsAndResumeReleases() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer"], busy: [])
        r.pauseByPerson(at: t0)
        XCTAssertEqual(delivered(r.receive(req("builder", ["reviewer"]), at: t0)), [])
        XCTAssertEqual(delivered(r.resume(at: t0)), ["reviewer"])
        XCTAssertEqual(r.cap, CrewRules.defaultCap, "a person's pause does not raise the cap")
    }

    func testTheCapPausesTheCrewAndResumeRaisesIt() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer"], busy: [])
        var sent = 0
        for i in 0..<(CrewRules.defaultCap + 3) {
            sent += delivered(r.receive(req("builder", ["reviewer"], "m\(i)"), at: t0)).count
            sent += delivered(r.turnEnded("reviewer", result: nil, at: t0)).filter { $0 == "reviewer" }.count
            _ = r.turnEnded("builder", result: nil, at: t0)
        }
        XCTAssertLessThanOrEqual(r.relays, CrewRules.defaultCap, "never past the cap")
        XCTAssertEqual(r.pause, .capReached)
        XCTAssertTrue(r.board.contains { $0.kind == .capped })
        _ = r.resume(at: t0)
        XCTAssertEqual(r.cap, CrewRules.defaultCap * 2)
        XCTAssertNil(r.pause)
    }

    func testStopEndsEveryLiveMemberAndIgnoresLaterMessages() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer", "critic"], busy: ["builder"])
        _ = r.memberEnded("critic", at: t0)
        _ = r.receive(req("reviewer", ["builder"]), at: t0)
        let effects = r.stop(at: t0)
        XCTAssertEqual(Set(effects), [.stopMember("builder"), .stopMember("reviewer")], "the ended member is not stopped twice")
        XCTAssertTrue(r.queue.isEmpty)
        XCTAssertEqual(r.receive(req("reviewer", ["builder"]), at: t0), [])
        XCTAssertEqual(r.resume(at: t0), [])
    }

    func testABusyWriteIsRetriedAndAGoneMemberEnds() {
        var r = CrewRules.Relay(roles: ["builder", "reviewer"], busy: [])
        XCTAssertEqual(delivered(r.receive(req("builder", ["reviewer"]), at: t0)), ["reviewer"])
        XCTAssertEqual(r.relays, 1)
        XCTAssertEqual(r.deliveryFailed("reviewer", gone: false, at: t0), [])
        XCTAssertEqual(r.relays, 0, "an unwritten delivery does not count")
        XCTAssertEqual(r.queue.first?.to, "reviewer", "back at the front")
        XCTAssertEqual(delivered(r.turnEnded("reviewer", result: nil, at: t0)), ["reviewer"], "tried again once the person's turn ended")
        _ = r.deliveryFailed("reviewer", gone: true, at: t0)
        XCTAssertTrue(r.ended.contains("reviewer"))
    }

    // MARK: Words

    func testEveryKeyHandedToL10nThroughAVariableIsTranslated() throws {
        let entries = try XCTUnwrap(try L10nFixture.raw()["entries"] as? [String: [String: Any]])
        let keys = CrewRules.boardKeys + CrewRules.templateKeys
        XCTAssertGreaterThan(keys.count, 7)
        for k: CrewRules.BoardEntry.Kind in [.message, .reply, .failed, .paused, .resumed, .capped, .stopped] {
            XCTAssertTrue(CrewRules.boardKeys.contains(CrewRules.boardKindKey(k)))
        }
        for k in keys { XCTAssertFalse((entries[k]?["en"] as? String ?? "").isEmpty, "missing from the store: \(k)") }
    }
}
