import XCTest

/// P5a — Codex beside Claude Code: one hook script, events tagged by agent, Codex's hook file merged without moving
/// anyone else's entries.
final class AgentCodexTests: XCTestCase {

    private func line(_ agent: String?, _ payload: String, at t: String = "2026-10-14T05:00:00Z") -> String {
        let a = agent.map { #","agent":"\#($0)""# } ?? ""
        return #"{"received_at":"\#(t)","request_id":"r-\#(UUID().uuidString)"\#(a),"env":{"ppid":0},"payload":\#(payload)}"#
    }

    // MARK: Parsing and sessions

    func testALineWithoutAnAgentIsClaudesAndCodexLinesSayCodex() throws {
        let old = try XCTUnwrap(AgentEvents.parse(line: line(nil, #"{"hook_event_name":"Stop","session_id":"a"}"#)))
        XCTAssertEqual(old.agent, .claude, "a pre-P5 Claude hook writes no agent field")
        let codex = try XCTUnwrap(AgentEvents.parse(line: line("codex", #"{"hook_event_name":"Stop","session_id":"a"}"#)))
        XCTAssertEqual(codex.agent, .codex)
        let unknown = try XCTUnwrap(AgentEvents.parse(line: line("cursor", #"{"hook_event_name":"Stop","session_id":"a"}"#)))
        XCTAssertEqual(unknown.agent, .claude, "an agent this build does not know falls back, it does not drop the line")
    }

    func testTheSameIdUnderTwoAgentsIsTwoSessions() {
        let events = [
            line("claude", #"{"hook_event_name":"UserPromptSubmit","session_id":"same","cwd":"/a"}"#),
            line("codex", #"{"hook_event_name":"Stop","session_id":"same","cwd":"/b"}"#, at: "2026-10-14T05:00:01Z"),
        ].compactMap(AgentEvents.parse(line:))
        let s = AgentSessionRules.sessions(from: events, now: Date(timeIntervalSince1970: 1_791_939_700), isAlive: { _ in true })
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(Set(s.map(\.agent)), [.claude, .codex])
        XCTAssertEqual(Set(s.map(\.listID)).count, 2, "a list must key on agent + id")
    }

    func testCodexInterruptMeansItIsYourTurn() {
        let events = [
            line("codex", #"{"hook_event_name":"PreToolUse","session_id":"c","tool_name":"Bash","tool_input":{"command":"make"}}"#),
            line("codex", #"{"hook_event_name":"Interrupt","session_id":"c","turn_id":"t"}"#, at: "2026-10-14T05:00:01Z"),
        ].compactMap(AgentEvents.parse(line:))
        let s = AgentSessionRules.sessions(from: events, now: Date(timeIntervalSince1970: 1_791_939_700), isAlive: { _ in true })
        XCTAssertEqual(s.first?.status, .waitingForInput)
    }

    // MARK: Installer

    func testCodexSubscribesToItsDocumentedEventsWithinItsTimeoutLimits() {
        let ev = Dictionary(uniqueKeysWithValues: AgentHookInstaller.events(for: .codex).map { ($0.name, $0.timeout) })
        XCTAssertEqual(Set(ev.keys), ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                      "PermissionRequest", "Stop", "Interrupt"])
        XCTAssertNil(ev["Notification"], "Codex has no Notification event")
        XCTAssertLessThanOrEqual(ev["SessionEnd"] ?? 99, 3, "Codex caps SessionEnd at 3 s")
        XCTAssertLessThanOrEqual(ev["Interrupt"] ?? 99, 3, "Codex caps Interrupt at 3 s")
        XCTAssertEqual(ev["PermissionRequest"], 3600, "the hook waits up to 3500 s for the notch")
        XCTAssertTrue(AgentHookInstaller.events(for: .opencode).isEmpty)
    }

    func testCodexMergeAppendsAfterOtherToolsSoTheirTrustedPositionsHold() throws {
        let hookPath = "/Users/me/Library/Application Support/XFinder/Agents/codex/bin/xfinder-agent-hook.zsh"
        let other: [String: Any] = ["hooks": [
            "PermissionRequest": [["hooks": [["type": "command", "command": "/opt/other/hook codex 86400", "timeout": 86410]]]],
            "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "bash validate.sh"]]]],
        ]]
        let merged = AgentHookInstaller.merged(other, hookPath: hookPath, agent: .codex)
        let hooks = try XCTUnwrap(merged["hooks"] as? [String: Any])
        let perm = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(perm.count, 2)
        let first = try XCTUnwrap((perm[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        XCTAssertEqual(first, "/opt/other/hook codex 86400", "the other tool keeps position 0 (Codex trust is per position)")
        let ours = try XCTUnwrap((perm[1]["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(ours["command"] as? String, "'\(hookPath)' codex")
        XCTAssertEqual(ours["timeout"] as? Int, 3600)
        let pre = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(pre.first?["matcher"] as? String, "Bash")
        XCTAssertEqual(AgentHookInstaller.status(of: merged, hookPath: hookPath, agent: .codex), .installed)
        // Running install twice adds nothing.
        let again = AgentHookInstaller.merged(merged, hookPath: hookPath, agent: .codex)
        XCTAssertEqual((again["hooks"] as? [String: Any])?["PermissionRequest"].map { ($0 as? [Any])?.count }, 2)
        // Removing ours leaves the other tool's entries exactly.
        let removed = AgentHookInstaller.removed(merged, hookPath: hookPath)
        XCTAssertEqual(((removed["hooks"] as? [String: Any])?["PermissionRequest"] as? [Any])?.count, 1)
        XCTAssertEqual(AgentHookInstaller.status(of: removed, hookPath: hookPath, agent: .codex), .notInstalled)
    }

    func testOtherToolsApprovalHooksAreCountedButOursIsNot() {
        let hookPath = "/x/xfinder-agent-hook.zsh"
        var s: [String: Any] = ["hooks": [
            "PermissionRequest": [
                ["hooks": [["type": "command", "command": "/opt/onenotch/hook", "timeout": 3600]]],
                ["hooks": [["type": "command", "command": "/opt/crew/hook claude 86400"],
                           ["type": "prompt", "prompt": "not a command"]]],
            ],
            "Stop": [["hooks": [["type": "command", "command": "/opt/other/stop"]]]],
        ]]
        XCTAssertEqual(AgentHookInstaller.otherPermissionHooks(in: s, hookPath: hookPath), 2,
                       "two command handlers on PermissionRequest; the prompt handler and the Stop hook do not count")
        s = AgentHookInstaller.merged(s, hookPath: hookPath, agent: .codex)
        XCTAssertEqual(AgentHookInstaller.otherPermissionHooks(in: s, hookPath: hookPath), 2, "XFinder's own entry is not 'another tool'")
        XCTAssertEqual(AgentHookInstaller.otherPermissionHooks(in: [:], hookPath: hookPath), 0)
    }

    func testClaudesCommandIsUnchangedSoAHookInstalledBeforeP5StillMatches() {
        let p = "/Users/me/Library/Application Support/XFinder/Agents/claude/bin/xfinder-claude-hook.zsh"
        XCTAssertEqual(AgentHookInstaller.command(forHookAt: p), "'\(p)'")
        XCTAssertEqual(AgentHookInstaller.command(forHookAt: p, agent: .claude), "'\(p)'")
        let preP5 = AgentHookInstaller.merged([:], hookPath: p)          // what 1.3.0 wrote
        XCTAssertEqual(AgentHookInstaller.status(of: preP5, hookPath: p, agent: .claude), .installed)
    }

    // MARK: Resume command

    func testResumeCommandsQuoteTheFolderAndTheId() {
        XCTAssertEqual(AgentKind.claude.resumeCommand(sessionID: "abc", cwd: "/Users/me/My Project"),
                       "cd '/Users/me/My Project' && claude --resume 'abc'")
        XCTAssertEqual(AgentKind.codex.resumeCommand(sessionID: "019a-uuid", cwd: nil), "codex resume '019a-uuid'")
        XCTAssertEqual(AgentKind.opencode.resumeCommand(sessionID: "ses_x", cwd: "/tmp/it's"),
                       "cd '/tmp/it'\\''s' && opencode --session 'ses_x'")
    }

    // MARK: The shipped script

    private var scriptURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/Agents/xfinder-agent-hook.zsh")
    }

    private func runHook(_ args: [String], stdin: String, dir: URL, extraEnv: [String: String] = [:],
                         isolateCodexHost: Bool = false) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var env = isolateCodexHost
            ? ["PATH": "/usr/bin:/bin", "HOME": dir.path,
               "CODEX_HOME": dir.appendingPathComponent("codex-home").path,
               "CODEX_SESSION_ID": "fixture-session", "CODEX_THREAD_ID": "fixture-thread"]
            : ProcessInfo.processInfo.environment
        env["XFINDER_AGENT_DIR"] = dir.path
        for (k, v) in extraEnv { env[k] = v }
        if isolateCodexHost {
            // The real shell's parent chain is controlled by the test runner (and can contain Codex itself).
            // Give the shipped hook a deterministic `ps` view so this assertion tests its Codex handling, not
            // whichever GUI app happened to launch `swift test`.
            let ps = dir.appendingPathComponent("fixture-ps")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try """
            #!/bin/sh
            case "$*" in
              *"-o ppid=,tty=,comm="*) printf '1 ?? /usr/bin/fixture-runner\\n' ;;
              *"-o tty="*) printf '??\\n' ;;
            esac
            """.write(to: ps, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ps.path)
            let isolatedScript = dir.appendingPathComponent("xfinder-agent-hook.zsh")
            let source = try String(contentsOf: scriptURL, encoding: .utf8)
            try source.replacingOccurrences(of: "/bin/ps", with: ps.path)
                .write(to: isolatedScript, atomically: true, encoding: .utf8)
            p.arguments = [isolatedScript.path] + args
        } else {
            p.arguments = [scriptURL.path] + args
        }
        p.environment = env
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "the hook must never exit non-zero (exit 2 blocks the agent)")
    }

    func testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/jq") else { throw XCTSkip("no /usr/bin/jq on this Mac") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xf-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try runHook(["codex"], stdin: #"{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"THE ANSWER"}"#, dir: tmp, isolateCodexHost: true)
        try runHook(["codex"], stdin: #"{"hook_event_name":"PostToolUse","session_id":"s1","tool_name":"Bash","tool_response":"OUTPUT"}"#, dir: tmp, isolateCodexHost: true)
        let files = try FileManager.default.contentsOfDirectory(at: tmp.appendingPathComponent("events"), includingPropertiesForKeys: nil)
        let text = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        let events = AgentEvents.parse(jsonl: text)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.agent == .codex })
        XCTAssertFalse(text.contains("THE ANSWER"), "Codex's Stop carries the model's answer; XFinder promises not to keep it")
        XCTAssertFalse(text.contains("OUTPUT"), "tool_response is dropped")
        XCTAssertTrue(events.allSatisfy { $0.agentPID == nil }, "no ancestor named codex ⇒ no pid, never the shell's")
    }

    /// P6 review: a control character in an env value (a newline in $TMUX) split the event across two lines and both
    /// halves were dropped. The hook now strips control characters from every env value.
    func testAControlCharacterInAnEnvValueDoesNotSplitTheEvent() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xf-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try runHook([], stdin: #"{"hook_event_name":"Stop","session_id":"s9"}"#, dir: tmp,
                    extraEnv: ["TMUX": "/tmp/tmux-502/default,1,0\nEVIL", "KITTY_LISTEN_ON": "unix:/tmp/k\u{1B}]0;x\u{07}"])
        let files = try FileManager.default.contentsOfDirectory(at: tmp.appendingPathComponent("events"), includingPropertiesForKeys: nil)
        let text = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertEqual(text.split(separator: "\n").count, 1, "one event, one line")
        let events = AgentEvents.parse(jsonl: text)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.terminal.tmuxEnv, "/tmp/tmux-502/default,1,0EVIL")
        XCTAssertEqual(events.first?.terminal.kittyListenOn, "unix:/tmp/k]0;x")
    }

    // MARK: Ids that could escape the decisions folder (P5 review)

    func testIdsThatCouldEscapeTheDecisionsFolderAreRefused() {
        let evil = line("codex", #"{"hook_event_name":"PermissionRequest","session_id":"../../Library/LaunchAgents/x","tool_name":"Bash"}"#)
        XCTAssertNil(AgentEvents.parse(line: evil), "an id with a path in it is not a session")
        XCTAssertNil(AgentDecision.fileName(sessionID: "../x", requestID: "r1"))
        XCTAssertNil(AgentDecision.fileName(sessionID: "s1", requestID: "a/b"))
        XCTAssertNil(AgentDecision.fileName(sessionID: String(repeating: "a", count: 129), requestID: "r1"))
        XCTAssertEqual(AgentDecision.fileName(sessionID: "019a-5b0c_x", requestID: "ee48-71b5"), "019a-5b0c_x-ee48-71b5.json")
    }

    /// Starts the shipped hook as if XFinder were running (`XFINDER_ASSUME_RUNNING`), returns whether it exited by
    /// itself within `seconds` (a hook that waits for a decision is killed and reports false).
    private func hookExitsOnItsOwn(sid: String, within seconds: TimeInterval) throws -> Bool {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xf-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [scriptURL.path, "codex"]
        var env = ProcessInfo.processInfo.environment
        env["XFINDER_AGENT_DIR"] = tmp.path
        env["XFINDER_ASSUME_RUNNING"] = "1"
        p.environment = env
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        input.fileHandleForWriting.write(Data(#"{"hook_event_name":"PermissionRequest","session_id":"\#(sid)","tool_name":"Bash"}"#.utf8))
        try input.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(seconds)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        let exited = !p.isRunning
        if !exited { p.terminate(); p.waitUntilExit() }
        return exited
    }

    func testTheHookNeverWaitsOnAnUnsafeSessionIdButDoesOnASafeOne() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/jq") else { throw XCTSkip("no /usr/bin/jq on this Mac") }
        XCTAssertFalse(try hookExitsOnItsOwn(sid: "safe-id-1", within: 1),
                       "positive control: a safe id waits for the notch's decision (else this test proves nothing)")
        XCTAssertTrue(try hookExitsOnItsOwn(sid: "../escape", within: 3),
                      "an id with a path in it must not be waited on — its decision file would live outside the folder")
    }

    func testTheShippedHookIgnoresAnAgentItDoesNotKnow() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("xf-hook-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try runHook(["evil;touch /tmp/x"], stdin: #"{"hook_event_name":"Stop","session_id":"s"}"#, dir: tmp)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "an unknown agent name writes nothing at all")
    }
}
