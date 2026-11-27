import Foundation
import os

/// Off-main-thread `Process` runner for macOS `/usr/bin/shortcuts`.
///
/// Guarantees:
/// - Invokes `executablePath` directly via `Process.executableURL` + `Process.arguments` (NO shell).
/// - Never blocks the UI thread (`Task.detached` + background pipe readers).
/// - Drains stdout and stderr concurrently BEFORE `waitUntilExit()` with a hard byte cap,
///   continuing to drain excess bytes to EOF so large output never deadlocks a full kernel pipe
///   or exhausts memory.
/// - Closes the cancellation/timeout race window via an `OSAllocatedUnfairLock` state machine:
///   if cancel or timeout fires before `pid` is published, the launching thread observes it
///   immediately after `try process.run()` and terminates the child (`SIGTERM`, then `SIGKILL`
///   after `killGraceInterval` if the child does not exit).
/// - Cancellation limitation: terminating `/usr/bin/shortcuts` stops the CLI client and frees
///   XFinder, but actions already handed off over XPC to `Shortcuts` / `BackgroundShortcutRunner`
///   may continue or finish in the background daemon.
struct AppleShortcutsProcessRunner: AppleShortcutsRunning {
    let executablePath: String
    let killGraceInterval: TimeInterval

    private static let readChunkSize = 16 * 1024

    init(
        executablePath: String = AppleShortcutsCommand.defaultExecutablePath,
        killGraceInterval: TimeInterval = 0.3
    ) {
        self.executablePath = executablePath
        self.killGraceInterval = max(0.05, killGraceInterval)
    }

    private struct ControlState: Sendable {
        var pid: pid_t = 0
        var cancelled: Bool = false
        var timedOut: Bool = false
        var exited: Bool = false
    }

    private struct StreamCapture: Sendable {
        var data: Data = Data()
        var truncated: Bool = false
    }

    func execute(
        arguments: [String],
        timeout: TimeInterval,
        maxOutputBytes: Int
    ) async -> Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError> {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            return .failure(.cliUnavailable(path: executablePath))
        }
        if Task.isCancelled {
            return .failure(.cancelled)
        }

        let control = OSAllocatedUnfairLock<ControlState>(initialState: ControlState())
        let executable = executablePath
        let grace = killGraceInterval
        let effectiveTimeout = max(0.05, timeout)
        let effectiveCap = max(0, maxOutputBytes)

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Self.executeBlocking(
                        executable: executable,
                        arguments: arguments,
                        timeout: effectiveTimeout,
                        maxOutputBytes: effectiveCap,
                        grace: grace,
                        control: control
                    )
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            let targetPID = control.withLock { state -> pid_t in
                state.cancelled = true
                return state.exited ? 0 : state.pid
            }
            if targetPID > 0 {
                let queue = DispatchQueue(label: "com.xfinder.shortcuts.cancel", qos: .userInitiated)
                Self.terminateProcess(pid: targetPID, control: control, grace: grace, queue: queue)
            }
        }
    }

    private static func executeBlocking(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        maxOutputBytes: Int,
        grace: TimeInterval,
        control: OSAllocatedUnfairLock<ControlState>
    ) -> Result<AppleShortcutsProcessOutput, AppleShortcutsRunnerError> {
        if control.withLock({ $0.cancelled }) {
            return .failure(.cancelled)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            try? stdoutPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForWriting.close()
            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain && (nsError.code == Int(ENOENT) || nsError.code == Int(EACCES)) {
                return .failure(.cliUnavailable(path: executable))
            }
            return .failure(.launchFailed(detail: error.localizedDescription))
        }

        // Close parent-side write ends immediately so EOF is observed cleanly when child exits.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let childPID = process.processIdentifier
        let shouldTerminateNow = control.withLock { state -> Bool in
            state.pid = childPID
            return state.cancelled || state.timedOut
        }

        let watchdogQueue = DispatchQueue(label: "com.xfinder.shortcuts.watchdog", qos: .utility)
        let watchdog = DispatchSource.makeTimerSource(queue: watchdogQueue)
        watchdog.schedule(deadline: .now() + timeout)
        watchdog.setEventHandler {
            let targetPID = control.withLock { state -> pid_t in
                guard !state.exited else { return 0 }
                state.timedOut = true
                return state.pid
            }
            if targetPID > 0 {
                Self.terminateProcess(pid: targetPID, control: control, grace: grace, queue: watchdogQueue)
            }
        }
        watchdog.resume()

        if shouldTerminateNow {
            control.withLock { $0.cancelled = true }
            Self.terminateProcess(pid: childPID, control: control, grace: grace, queue: watchdogQueue)
        }

        let stdoutBox = OSAllocatedUnfairLock<StreamCapture>(initialState: StreamCapture())
        let stderrBox = OSAllocatedUnfairLock<StreamCapture>(initialState: StreamCapture())
        let readGroup = DispatchGroup()
        let readQueue = DispatchQueue.global(qos: .userInitiated)

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        readGroup.enter()
        readQueue.async {
            let capture = Self.readBounded(from: stdoutHandle, maxBytes: maxOutputBytes)
            stdoutBox.withLock { $0 = capture }
            readGroup.leave()
        }

        readGroup.enter()
        readQueue.async {
            let capture = Self.readBounded(from: stderrHandle, maxBytes: maxOutputBytes)
            stderrBox.withLock { $0 = capture }
            readGroup.leave()
        }

        // Drain both pipes before waiting for exit so a chatty child cannot deadlock on pipe buffers.
        readGroup.wait()
        process.waitUntilExit()

        watchdog.cancel()
        let finalState = control.withLock { state -> ControlState in
            state.exited = true
            return state
        }

        if finalState.timedOut {
            return .failure(.timedOut(seconds: timeout))
        }
        if finalState.cancelled {
            return .failure(.cancelled)
        }

        let out = stdoutBox.withLock { $0 }
        let err = stderrBox.withLock { $0 }
        return .success(
            AppleShortcutsProcessOutput(
                exitCode: process.terminationStatus,
                stdout: out.data,
                stderr: err.data,
                stdoutTruncated: out.truncated,
                stderrTruncated: err.truncated
            )
        )
    }

    private static func terminateProcess(
        pid: pid_t,
        control: OSAllocatedUnfairLock<ControlState>,
        grace: TimeInterval,
        queue: DispatchQueue
    ) {
        _ = kill(pid, SIGTERM)
        queue.asyncAfter(deadline: .now() + grace) {
            let stillRunning = control.withLock { !$0.exited && $0.pid == pid }
            if stillRunning {
                _ = kill(pid, SIGKILL)
            }
        }
    }

    /// Reads up to `maxBytes` into memory, then continues draining and discarding until EOF so
    /// the child process never stalls on a full pipe.
    private static func readBounded(from handle: FileHandle, maxBytes: Int) -> StreamCapture {
        defer { try? handle.close() }
        var data = Data()
        var truncated = false

        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: readChunkSize)
            } catch {
                break
            }
            guard let chunk, !chunk.isEmpty else {
                break
            }
            if data.count < maxBytes {
                let remaining = maxBytes - data.count
                if chunk.count <= remaining {
                    data.append(chunk)
                } else {
                    data.append(chunk.prefix(remaining))
                    truncated = true
                }
            } else {
                truncated = true
            }
        }

        return StreamCapture(data: data, truncated: truncated)
    }
}
