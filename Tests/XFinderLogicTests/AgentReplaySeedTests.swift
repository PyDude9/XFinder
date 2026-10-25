import XCTest

/// 2026-10-25 — a tail keeps only its newest events and folds the rest into a `ReplaySeed` (20 000 kept events held
/// ~25 MB). The list must not change: replaying a suffix on the folded prefix equals replaying everything, at every cut.
final class AgentReplaySeedTests: XCTestCase {
    typealias E = AgentEvents.Event
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    func event(_ name: E.Name, _ sid: String, at s: Double, pid: Int32? = nil, agent: AgentKind = .claude,
               tool: String? = nil, request: String? = nil, notification: String? = nil, error: String? = nil) -> E {
        E(agent: agent, receivedAt: t0.addingTimeInterval(s), name: name, rawName: name.rawValue, sessionID: sid,
          requestID: request, cwd: "/p/\(sid)", transcriptPath: nil, toolName: tool, toolInputSummary: nil,
          notificationType: notification, errorType: error, message: nil, prompt: name == .userPromptSubmit ? "p\(Int(s))" : nil,
          agentPID: pid, terminal: AgentEvents.Terminal())
    }

    /// A deterministic stream over five sessions (two agents, live / dead / missing processes) using every event kind
    /// the replay branches on, one second apart.
    func stream(seed: UInt64, count: Int) -> [E] {
        var x = seed &* 6364136223846793005 &+ 1442695040888963407
        func next(_ n: Int) -> Int { x = x &* 6364136223846793005 &+ 1442695040888963407; return Int((x >> 33) % UInt64(n)) }
        let sessions: [(String, Int32?, AgentKind)] = [("a", 10, .claude), ("b", 11, .claude), ("c", nil, .claude),
                                                       ("a", 20, .codex), ("d", 12, .claude)]
        var out: [E] = []
        for i in 0..<count {
            let (sid, pid, agent) = sessions[next(sessions.count)]
            let t = Double(i) * (next(4) == 0 ? 1_200 : 1)          // some long gaps so staleness and pruning happen
            let at = (out.last.map { $0.receivedAt.timeIntervalSince(t0) } ?? 0) + t + 1
            switch next(12) {
            case 0: out.append(event(.sessionStart, sid, at: at, pid: pid, agent: agent))
            case 1: out.append(event(.userPromptSubmit, sid, at: at, pid: pid, agent: agent))
            case 2: out.append(event(.preToolUse, sid, at: at, pid: pid, agent: agent, tool: next(3) == 0 ? "AskUserQuestion" : "Bash"))
            case 3: out.append(event(.postToolUse, sid, at: at, pid: pid, agent: agent, tool: "Bash"))
            case 4: out.append(event(.permissionRequest, sid, at: at, pid: pid, agent: agent, tool: "Bash", request: "r\(next(4))"))
            case 5: out.append(event(.notification, sid, at: at, pid: pid, agent: agent,
                                     notification: ["idle_prompt", "permission_prompt", "quota_auto_resume_fired"][next(3)]))
            case 6: out.append(event(.stop, sid, at: at, pid: pid, agent: agent))
            case 7: out.append(event(.stopFailure, sid, at: at, pid: pid, agent: agent, error: next(2) == 0 ? "rate_limit" : "overloaded"))
            case 8: out.append(event(.sessionEnd, sid, at: at, pid: pid, agent: agent))
            case 9: out.append(event(.permissionDenied, sid, at: at, pid: pid, agent: agent))
            case 10: out.append(event(.interrupt, sid, at: at, pid: pid, agent: agent))
            default: out.append(event(.subagentStop, sid, at: at, pid: pid, agent: agent))
            }
        }
        return out
    }

    let alive: (Int32) -> Bool = { $0 != 11 }

    func testFoldingAnyPrefixGivesTheSameListAsReplayingEverything() {
        var cuts = 0
        for s in 0..<12 {
            let all = stream(seed: UInt64(s), count: 90)
            let now = all.last!.receivedAt.addingTimeInterval(30)
            for answered in [Set<String>(), ["r1", "r3"]] {
                let full = AgentSessionRules.sessions(from: all, now: now, answered: answered, isAlive: alive)
                XCTAssertFalse(full.isEmpty, "precondition: the stream must leave sessions to compare")
                for k in 0...all.count {
                    var seed = AgentSessionRules.ReplaySeed()
                    AgentSessionRules.fold(Array(all[..<k]), into: &seed)
                    let split = AgentSessionRules.sessions(from: Array(all[k...]), seed: seed, now: now, answered: answered, isAlive: alive)
                    XCTAssertEqual(split, full, "stream \(s) cut at \(k)")
                    cuts += 1
                }
            }
        }
        XCTAssertEqual(cuts, 12 * 2 * 91)
    }

    func testPruningDropsOnlySessionsTheListWouldHideAnyway() {
        var dropped = 0
        for s in 0..<12 {
            let all = stream(seed: UInt64(100 + s), count: 120)
            let now = all.last!.receivedAt.addingTimeInterval(30)
            for k in stride(from: 0, through: all.count, by: 7) {
                var seed = AgentSessionRules.ReplaySeed()
                AgentSessionRules.fold(Array(all[..<k]), into: &seed)
                let window = Array(all[k...])
                let pruned = AgentSessionRules.pruned(seed, now: now, keep: Set(window.map(AgentSessionRules.sessionKey)), isAlive: alive)
                dropped += seed.order.count - pruned.order.count
                XCTAssertEqual(AgentSessionRules.sessions(from: window, seed: pruned, now: now, isAlive: alive),
                               AgentSessionRules.sessions(from: window, seed: seed, now: now, isAlive: alive), "stream \(s) cut at \(k)")
            }
        }
        XCTAssertGreaterThan(dropped, 0, "precondition: the streams must give pruning something to drop")
    }

    func testPruneRules() {
        var seed = AgentSessionRules.ReplaySeed()
        AgentSessionRules.fold([event(.sessionEnd, "ended", at: 0, pid: 10), event(.stop, "dead", at: 0, pid: 11),
                                event(.stop, "silent", at: 0), event(.stop, "live", at: 0, pid: 10),
                                event(.sessionEnd, "inWindow", at: 0, pid: 10), event(.sessionEnd, "recent", at: 3_000, pid: 10)],
                               into: &seed)
        let now = t0.addingTimeInterval(3_700)                 // > keepEndedFor after t0, < after 3 000 s
        let kept = AgentSessionRules.pruned(seed, now: now, keep: ["claude:inWindow"], isAlive: alive).order
        XCTAssertEqual(kept, ["claude:live", "claude:inWindow", "claude:recent"])
    }

    func testARequestAnsweredAfterItWasFoldedNoLongerWaits() {
        var seed = AgentSessionRules.ReplaySeed()
        AgentSessionRules.fold([event(.permissionRequest, "a", at: 0, pid: 10, tool: "Bash", request: "r9")], into: &seed)
        let now = t0.addingTimeInterval(5)
        let waiting = AgentSessionRules.sessions(from: [], seed: seed, now: now, isAlive: alive)
        guard case .waitingForPermission(let p)? = waiting.first?.status else { return XCTFail("folded request must wait") }
        XCTAssertEqual(p.requestID, "r9")
        let answered = AgentSessionRules.sessions(from: [], seed: seed, now: now, answered: ["r9"], isAlive: alive)
        XCTAssertEqual(answered.first?.status, .running(tool: "Bash"))
    }

    func testTwoAgentsWithTheSameSessionIDStayTwoSessions() {
        var seed = AgentSessionRules.ReplaySeed()
        AgentSessionRules.fold([event(.stop, "a", at: 0, pid: 10), event(.stop, "a", at: 1, pid: 20, agent: .codex)], into: &seed)
        XCTAssertEqual(seed.order, ["claude:a", "codex:a"])
    }
}
