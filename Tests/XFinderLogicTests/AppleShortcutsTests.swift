import XCTest
import Foundation
import os

// MARK: - Controlled Fake Runner (never executes real Apple Shortcuts)

private actor FakeAppleShortcutsRunner: AppleShortcutsRunning {
    struct RecordedCall: Equatable, Sendable {
        let arguments: [String]
        let timeout: TimeInterval
        let maxOutputBytes: Int
    }

    enum Action: Sendable {
        case immediate(Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>)
        case suspended
    }

    private(set) var calls: [RecordedCall] = []
    private(set) var cancelledCallIndices: [Int] = []
    private var scriptedActions: [Action] = []
    private var continuations: [Int: CheckedContinuation<Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>, Never>] = [:]
    private var pendingResolutions: [Int: Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>] = [:]
    private var callWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func enqueue(_ actions: Action...) {
        scriptedActions.append(contentsOf: actions)
    }

    func execute(
        arguments: [String],
        timeout: TimeInterval,
        maxOutputBytes: Int
    ) async -> Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError> {
        let index = calls.count
        calls.append(RecordedCall(arguments: arguments, timeout: timeout, maxOutputBytes: maxOutputBytes))
        if let waiter = callWaiters.removeValue(forKey: index) {
            waiter.resume()
        }

        let action: Action = scriptedActions.isEmpty ? .suspended : scriptedActions.removeFirst()
        switch action {
        case .immediate(let result):
            return result
        case .suspended:
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if let preResolved = pendingResolutions.removeValue(forKey: index) {
                        continuation.resume(returning: preResolved)
                    } else {
                        continuations[index] = continuation
                    }
                }
            } onCancel: {
                Task { await self.recordCancellation(at: index) }
            }
        }
    }

    private func recordCancellation(at index: Int) {
        cancelledCallIndices.append(index)
    }

    func waitForCall(at index: Int) async {
        if calls.count > index { return }
        await withCheckedContinuation { continuation in
            if calls.count > index {
                continuation.resume()
            } else {
                callWaiters[index] = continuation
            }
        }
    }

    func resolve(callIndex: Int, with result: Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError>) {
        if let continuation = continuations.removeValue(forKey: callIndex) {
            continuation.resume(returning: result)
        } else {
            pendingResolutions[callIndex] = result
        }
    }
}

// MARK: - Domain & Store Tests (Fake Runner)

final class AppleShortcutsTests: XCTestCase {

    // MARK: Parser & Special Characters

    func testParserPreservesSpacesQuotesShellCharsAndParenthesesInNames() {
        let raw = """
        Backup (Daily) (F8DC56A7-553E-4892-9C67-F16CA7BD2F21)
        Say "Hi" 'Boss' $(rm -rf /) ; echo pwn | cat & $HOME `id` (3D44308A-ADD6-46DA-9D56-ABEB19D31563)
        Tóm tắt bằng ChatGPT (7BCA1522-C13E-4741-AE1A-CB956DAC15CC)
        Plain Name Without UUID
        -LeadingDashName
        """
        let parsed = AppleShortcutsParser.parseListOutput(Data(raw.utf8), truncated: false)
        XCTAssertEqual(parsed.count, 5)

        XCTAssertEqual(parsed[0].name, "Backup (Daily)")
        XCTAssertEqual(parsed[0].identifier, "F8DC56A7-553E-4892-9C67-F16CA7BD2F21")
        XCTAssertEqual(parsed[0].runTarget, "F8DC56A7-553E-4892-9C67-F16CA7BD2F21")

        XCTAssertEqual(parsed[1].name, #"Say "Hi" 'Boss' $(rm -rf /) ; echo pwn | cat & $HOME `id`"#)
        XCTAssertEqual(parsed[1].identifier, "3D44308A-ADD6-46DA-9D56-ABEB19D31563")

        XCTAssertEqual(parsed[2].name, "Tóm tắt bằng ChatGPT")
        XCTAssertEqual(parsed[2].identifier, "7BCA1522-C13E-4741-AE1A-CB956DAC15CC")

        XCTAssertEqual(parsed[3].name, "Plain Name Without UUID")
        XCTAssertNil(parsed[3].identifier)
        XCTAssertEqual(parsed[3].runTarget, "Plain Name Without UUID")

        XCTAssertEqual(parsed[4].name, "-LeadingDashName")
        XCTAssertEqual(AppleShortcutsCommand.runArguments(for: parsed[4]), ["run", "--", "-LeadingDashName"])
    }

    func testParserDropsPartialFinalLineWhenTruncated() {
        let raw = "First (11111111-1111-1111-1111-111111111111)\nSecond (22222222-2222-2222"
        let parsed = AppleShortcutsParser.parseListOutput(Data(raw.utf8), truncated: true)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].name, "First")
    }

    func testSanitizeErrorDetailCapsLargeStderr() {
        let huge = String(repeating: "line error detail\n", count: 200)
        let detail = AppleShortcutsParser.sanitizeErrorDetail(Data(huge.utf8), maxCharacters: 80)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.count, 80)
        XCTAssertTrue(detail?.hasSuffix("…") == true)
    }

    // MARK: Empty, Loading, Running & Open Never Auto-Runs

    @MainActor
    func testOnOpenLoadsListAndNeverAutoRunsShortcuts() async {
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(.suspended)
        let store = AppleShortcutsStore(runner: fake)

        store.onOpen()
        XCTAssertTrue(store.isLoading)
        XCTAssertEqual(store.runState, .idle)

        // Calling onOpen again while loading in the same active session coalesces.
        store.onOpen()
        await fake.waitForCall(at: 0)

        let callsBeforeResolve = await fake.calls
        XCTAssertEqual(callsBeforeResolve.count, 1)
        XCTAssertEqual(callsBeforeResolve[0].arguments, ["list", "--show-identifiers"])

        await fake.resolve(callIndex: 0, with: .success(AppleShortcutsProcessOutput(exitCode: 0, stdout: Data())))
        await yieldUntil { !store.isLoading }

        XCTAssertEqual(store.loadState, .loaded(truncated: false))
        XCTAssertEqual(store.shortcuts, [])
        XCTAssertEqual(store.runState, .idle)

        let callsAfter = await fake.calls
        XCTAssertEqual(callsAfter.count, 1, "Opening the page must never invoke shortcuts run")
    }

    // MARK: Missing CLI & Timeout & Command Error

    @MainActor
    func testMissingCLIOnListAndRun() async {
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(
            .immediate(.failure(.cliUnavailable(path: "/usr/bin/shortcuts"))),
            .immediate(.success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("Demo (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE)\n".utf8)
            ))),
            .immediate(.failure(.cliUnavailable(path: "/usr/bin/shortcuts")))
        )
        let store = AppleShortcutsStore(runner: fake)

        store.onOpen()
        await yieldUntil { store.loadState == .failed(.cliUnavailable) }
        XCTAssertEqual(store.loadState, .failed(.cliUnavailable))

        store.refresh()
        await yieldUntil { store.loadState == .loaded(truncated: false) }
        XCTAssertEqual(store.shortcuts.count, 1)

        store.run(store.shortcuts[0])
        await yieldUntil {
            if case .failed(_, .cliUnavailable) = store.runState { return true }
            return false
        }
        XCTAssertEqual(store.runState, .failed(store.shortcuts[0], .cliUnavailable))
    }

    @MainActor
    func testTimeoutOnListAndRun() async {
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(
            .immediate(.failure(.timedOut(seconds: 10))),
            .immediate(.success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("Slow Job (AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE)\n".utf8)
            ))),
            .immediate(.failure(.timedOut(seconds: 30)))
        )
        let store = AppleShortcutsStore(runner: fake)

        store.onOpen()
        await yieldUntil { store.loadState == .failed(.timedOut) }
        XCTAssertEqual(store.loadState, .failed(.timedOut))

        store.refresh()
        await yieldUntil { store.loadState == .loaded(truncated: false) }

        store.run(store.shortcuts[0])
        await yieldUntil { store.runState == .failed(store.shortcuts[0], .timedOut) }
        XCTAssertEqual(store.runState, .failed(store.shortcuts[0], .timedOut))
    }

    // MARK: Renamed / Deleted Shortcut

    @MainActor
    func testRunUsesStableUUIDAndMapsNotFoundWhenRenamedOrDeleted() async {
        let uuid = "11111111-2222-3333-4444-555555555555"
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(
            .immediate(.success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("Morning Routine (\(uuid))\nLegacy Name Only\n".utf8)
            ))),
            .immediate(.success(AppleShortcutsProcessOutput(exitCode: 0))),
            .immediate(.success(AppleShortcutsProcessOutput(
                exitCode: 1,
                stderr: Data("Error: Couldn't find shortcut \"Legacy Name Only\".\n".utf8)
            )))
        )
        let store = AppleShortcutsStore(runner: fake)

        store.onOpen()
        await yieldUntil { store.shortcuts.count == 2 }

        // 1) UUID-backed shortcut runs by UUID even if renamed later in Shortcuts.app.
        store.run(store.shortcuts[0])
        await yieldUntil { store.runState == .succeeded(store.shortcuts[0]) }
        let calls1 = await fake.calls
        XCTAssertEqual(calls1[1].arguments, ["run", "--", uuid])

        // 2) Name-only (or deleted) shortcut returning not-found maps to .shortcutNotFound.
        store.run(store.shortcuts[1])
        await yieldUntil {
            if case .failed(_, .shortcutNotFound) = store.runState { return true }
            return false
        }
        XCTAssertEqual(
            store.runState,
            .failed(store.shortcuts[1], .shortcutNotFound(name: "Legacy Name Only"))
        )
    }

    // MARK: Consecutive Rapid Clicks (Single-Flight)

    @MainActor
    func testConsecutiveClicksWhileRunningAreIgnored() async {
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(
            .immediate(.success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("First (11111111-1111-1111-1111-111111111111)\nSecond (22222222-2222-2222-2222-222222222222)\n".utf8)
            ))),
            .suspended
        )
        let store = AppleShortcutsStore(runner: fake)

        store.onOpen()
        await yieldUntil { store.shortcuts.count == 2 }

        let first = store.shortcuts[0]
        let second = store.shortcuts[1]

        store.run(first)
        store.run(first)   // duplicate click on same item
        store.run(second)  // click on different item while first is running

        await fake.waitForCall(at: 1)
        let calls = await fake.calls
        XCTAssertEqual(calls.count, 2, "Only 1 list call + 1 run call should be issued")
        XCTAssertEqual(calls[1].arguments, ["run", "--", "11111111-1111-1111-1111-111111111111"])
        XCTAssertEqual(store.runState, .running(first))

        await fake.resolve(callIndex: 1, with: .success(AppleShortcutsProcessOutput(exitCode: 0)))
        await yieldUntil { store.runState == .succeeded(first) }
        XCTAssertEqual(store.runState, .succeeded(first))
    }

    // MARK: Cancel Run & Late Reply Ignored

    @MainActor
    func testCancelRunCancelsTaskAndIgnoresLateSuccessReply() async {
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(
            .immediate(.success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("Long Task (11111111-1111-1111-1111-111111111111)\n".utf8)
            ))),
            .suspended
        )
        let store = AppleShortcutsStore(runner: fake)

        store.onOpen()
        await yieldUntil { store.shortcuts.count == 1 }
        let target = store.shortcuts[0]

        store.run(target)
        await fake.waitForCall(at: 1)
        XCTAssertEqual(store.runState, .running(target))

        store.cancelRun()
        XCTAssertEqual(store.runState, .cancelled(target))

        // Even if the runner resolves .success late after cancel, it must NOT overwrite .cancelled.
        await fake.resolve(callIndex: 1, with: .success(AppleShortcutsProcessOutput(exitCode: 0)))
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(store.runState, .cancelled(target))
    }

    // MARK: Stale Replies After Tab Switch

    @MainActor
    func testStaleListAndRunRepliesAfterTabSwitchAreDropped() async {
        let fake = FakeAppleShortcutsRunner()
        await fake.enqueue(
            .suspended, // call 0: list #1 (will become stale)
            .suspended  // call 1: list #2 after reopen
        )
        let store = AppleShortcutsStore(runner: fake)

        // Open tab -> list #1 starts
        store.onOpen()
        await fake.waitForCall(at: 0)
        XCTAssertTrue(store.isLoading)

        // Switch away to another tab before list #1 returns
        store.onCloseOrTabSwitch()
        XCTAssertFalse(store.isPageActive)
        XCTAssertEqual(store.loadState, .idle)

        // Reopen tab -> list #2 starts
        store.onOpen()
        await fake.waitForCall(at: 1)

        // Resolve list #2 first with fresh data
        await fake.resolve(
            callIndex: 1,
            with: .success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("Fresh Shortcut (22222222-2222-2222-2222-222222222222)\n".utf8)
            ))
        )
        await yieldUntil { store.shortcuts.map(\.name) == ["Fresh Shortcut"] }

        // Now stale list #1 arrives late — must be dropped!
        await fake.resolve(
            callIndex: 0,
            with: .success(AppleShortcutsProcessOutput(
                exitCode: 0,
                stdout: Data("Stale Shortcut (11111111-1111-1111-1111-111111111111)\n".utf8)
            ))
        )
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(store.shortcuts.map(\.name), ["Fresh Shortcut"])

        // Now test stale run reply after tab switch:
        await fake.enqueue(.suspended) // call 2: run
        let fresh = store.shortcuts[0]
        store.run(fresh)
        await fake.waitForCall(at: 2)
        XCTAssertEqual(store.runState, .running(fresh))

        // Switch tab while running
        store.onCloseOrTabSwitch()
        XCTAssertEqual(store.runState, .idle)

        // Late run failure arrives after tab switch — must be dropped!
        await fake.resolve(
            callIndex: 2,
            with: .success(AppleShortcutsProcessOutput(exitCode: 1, stderr: Data("boom".utf8)))
        )
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(store.runState, .idle)
    }

    // MARK: Process Runner Tests (Harmless POSIX Binaries — Never Real Shortcuts)

    func testProcessRunnerReportsMissingCLI() async {
        let runner = AppleShortcutsProcessRunner(executablePath: "/nonexistent/xfinder-missing-shortcuts-cli")
        let result = await runner.execute(arguments: ["list"], timeout: 2, maxOutputBytes: 4096)
        XCTAssertEqual(result, .failure(.cliUnavailable(path: "/nonexistent/xfinder-missing-shortcuts-cli")))
    }

    func testProcessRunnerPassesShellMetacharactersVerbatimWithoutShell() async {
        let runner = AppleShortcutsProcessRunner(executablePath: "/usr/bin/printf")
        let tricky = #"My "Shortcut" 'Name' $(echo PWNED) ; | & `uname` $HOME"#
        let result = await runner.execute(arguments: ["%s", tricky], timeout: 5, maxOutputBytes: 4096)
        switch result {
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            XCTAssertEqual(String(decoding: output.stdout, as: UTF8.self), tricky)
            XCTAssertFalse(output.stdoutTruncated)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testProcessRunnerTerminatesHungProcessOnTimeout() async {
        let runner = AppleShortcutsProcessRunner(executablePath: "/bin/sleep", killGraceInterval: 0.1)
        let start = Date()
        let result = await runner.execute(arguments: ["10"], timeout: 0.15, maxOutputBytes: 1024)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result, .failure(.timedOut(seconds: 0.15)))
        XCTAssertLessThan(elapsed, 3.0, "Hung child must be terminated promptly on timeout")
    }

    func testProcessRunnerTerminatesChildOnTaskCancellation() async {
        let runner = AppleShortcutsProcessRunner(executablePath: "/bin/sleep", killGraceInterval: 0.1)
        let start = Date()
        let task = Task {
            await runner.execute(arguments: ["10"], timeout: 10, maxOutputBytes: 1024)
        }
        try? await Task.sleep(for: .milliseconds(120))
        task.cancel()
        let result = await task.value
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertLessThan(elapsed, 3.0, "Cancelled child must be terminated promptly")
    }

    func testProcessRunnerCapsLargeStdoutAndStderrWithoutDeadlock() async {
        let runner = AppleShortcutsProcessRunner(executablePath: "/usr/bin/python3")
        let script = """
        import sys
        sys.stdout.buffer.write(b'A' * 200000)
        sys.stderr.buffer.write(b'E' * 200000)
        """
        let result = await runner.execute(arguments: ["-c", script], timeout: 10, maxOutputBytes: 2048)
        switch result {
        case .success(let output):
            XCTAssertEqual(output.exitCode, 0)
            XCTAssertEqual(output.stdout.count, 2048)
            XCTAssertEqual(output.stderr.count, 2048)
            XCTAssertTrue(output.stdoutTruncated)
            XCTAssertTrue(output.stderrTruncated)
        case .failure(let error):
            XCTFail("Expected capped success without deadlock, got \(error)")
        }
    }

    // MARK: Helper

    @MainActor
    private func yieldUntil(timeoutSeconds: TimeInterval = 2.0, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
