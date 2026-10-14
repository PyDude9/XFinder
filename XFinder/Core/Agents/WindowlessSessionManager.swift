import AppKit
import Foundation
import os

/// P7a — the live half of "Phiên không cửa sổ" (rules + measurements: `WindowlessRules`). Runs Claude Code as XFinder's
/// own child in streaming-input mode, with no terminal: a turn the person sends goes to its stdin as one JSON line, the
/// stream on its stdout updates the record the notch shows. Nothing polls — the pipes deliver.
///
/// Lifetime: the child lives while XFinder does. Stopping (or quitting XFinder) interrupts the turn and closes stdin; the
/// conversation stays in Claude Code's own store and can be reopened windowless, or with `claude --resume` in a terminal.
/// Each process is its own session id; XFinder keeps only an in-memory record (the last ~40 messages) for the notch.
@MainActor @Observable
final class WindowlessSessionManager {
    static let shared = WindowlessSessionManager()
    @ObservationIgnored private let log = Logger(subsystem: "com.xfinder.app", category: "Windowless")

    enum StartError: Error, Equatable {
        case noClaude, badFolder, badSessionID, alreadyRunning, openElsewhere, launchFailed(String)
        /// A store key for the page.
        var key: String {
            switch self {
            case .noClaude: return "Không tìm thấy lệnh claude."
            case .badFolder: return "Thư mục không còn."
            case .openElsewhere: return "Phiên này đang mở ở nơi khác — đóng nó trước rồi mở lại."
            case .badSessionID, .alreadyRunning, .launchFailed: return "Không chạy được claude."
            }
        }
        var detail: String? { if case .launchFailed(let s) = self { return s }; return nil }
    }

    private(set) var records: [String: WindowlessRules.Record] = [:]      // session id → record
    /// Display order: newest first.
    var orderedRecords: [WindowlessRules.Record] { records.values.sorted { $0.startedAt > $1.startedAt } }
    var liveRecords: [WindowlessRules.Record] { orderedRecords.filter { !$0.isEnded } }
    @ObservationIgnored var onChange: (() -> Void)?

    /// P7b — what the crew relay needs to hear: a member's turn ended (with its result text), or its process ended. A
    /// slot of its own, so the monitor's `onChange` is never displaced (design review).
    enum Signal: Sendable { case turnEnded(sessionID: String, result: String?), processEnded(sessionID: String) }
    @ObservationIgnored var crewObserver: ((Signal) -> Void)?

    /// P7b — the one gate every writer goes through (a P6 reply and a crew delivery can race for one stdin): a session that
    /// is mid-turn refuses, so two user turns never land without a result between them.
    enum SendResult: Equatable, Sendable { case sent, busy, gone }

    private struct Child {
        var process: Process
        var stdin: FileHandle
        var stdout: Pipe
        var stderr: Pipe
        var generation: Int
        var buffer = Data()
        var lastStderr: String?
    }
    @ObservationIgnored private var children: [String: Child] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var loginEnvironment: [String: String]??   // nil = not resolved yet; .some(nil) = failed
    private static let maxLineBytes = 8 * 1024 * 1024

    // MARK: - Environment + binary

    /// The person's login environment, resolved once per run (`zsh -i -l -c 'env -0'`, 8 s cap). Off the main thread.
    func resolveEnvironment() async -> [String: String]? {
        if let cached = loginEnvironment { return cached }
        let shell = Self.loginShell()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let env = await Task.detached(priority: .userInitiated) { () -> [String: String]? in
            Self.runShellEnv(shell: shell, home: home)
        }.value
        loginEnvironment = .some(env)
        log.info("login environment resolved: \(env == nil ? "failed" : "\(env!.count) variables")")
        return env
    }

    nonisolated private static func loginShell() -> String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell {
            let s = String(cString: sh)
            if s.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        return "/bin/zsh"
    }

    /// Runs `<shell> -i -l -c '/usr/bin/env -0'` with a minimal environment (so the answer is the login environment, not
    /// XFinder's own), stdin from /dev/null, at most 8 s. Falls back to `-l` alone once.
    ///
    /// Never waits for the pipe to CLOSE (review): a startup file that backgrounds a job (ssh-agent, a version manager's
    /// hook) leaves a grandchild holding the write end, so `readDataToEndOfFile` blocked for that job's whole life —
    /// reproduced with `( sleep 15 & ); exit 0` against a 2 s cap. The output is collected as it arrives and taken when
    /// the shell itself exits (or is killed at 8 s); `env -0` has written everything by then.
    nonisolated static func runShellEnv(shell: String, home: String) -> [String: String]? {
        let user = NSUserName()
        for flags in [["-i", "-l"], ["-l"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell)
            p.arguments = flags + ["-c", "/usr/bin/env -0"]
            p.environment = ["HOME": home, "USER": user, "LOGNAME": user, "SHELL": shell,
                             "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": NSTemporaryDirectory()]
            let out = Pipe()
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            let collected = OSAllocatedUnfairLock(initialState: Data())
            out.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if d.isEmpty { h.readabilityHandler = nil; return }
                collected.withLock { $0.append(d) }
            }
            let exited = DispatchSemaphore(value: 0)
            p.terminationHandler = { _ in exited.signal() }
            do { try p.run() } catch { out.fileHandleForReading.readabilityHandler = nil; continue }
            if exited.wait(timeout: .now() + 8) == .timedOut {
                p.terminate()
                _ = exited.wait(timeout: .now() + 1)
            }
            Thread.sleep(forTimeInterval: 0.15)              // the last chunk the shell wrote before exiting
            out.fileHandleForReading.readabilityHandler = nil
            let env = WindowlessRules.parseEnvironment(collected.withLock { $0 })
            if !p.isRunning, p.terminationStatus == 0, env["PATH"] != nil { return env }
        }
        return nil
    }

    /// Test seam for the e2e harness (a stand-in `claude` that answers without a model). Never set by the app.
    @ObservationIgnored var claudePathOverride: String?

    private func claudePath(env: [String: String]) -> String? {
        if let o = claudePathOverride { return o }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return WindowlessRules.claudeCandidates(path: env["PATH"], home: home)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Whether a windowless session can start at all (claude found). Resolves the environment on first use.
    func claudeAvailable() async -> Bool {
        let login = await resolveEnvironment()
        let env = WindowlessRules.childEnvironment(login: login, fallback: ProcessInfo.processInfo.environment,
                                                   home: FileManager.default.homeDirectoryForCurrentUser.path)
        return claudePath(env: env) != nil
    }

    // MARK: - Start / resume

    /// A new windowless session in `folder`; `firstMessage` (optional) is sent as its first turn. Returns the session id.
    @discardableResult
    func startClaude(folder: URL, firstMessage: String?, extraArguments: [String] = [], extraEnvironment: [String: String] = [:],
                     pathPrepend: String? = nil) async throws -> String {
        let id = UUID().uuidString.lowercased()
        try await launch(sessionID: id, folder: folder, resume: false, extraArguments: extraArguments,
                         extraEnvironment: extraEnvironment, pathPrepend: pathPrepend)
        if let text = firstMessage.flatMap(WindowlessRules.cleanMessage) { _ = deliver(text, to: id) }
        return id
    }

    /// Reopen a stored Claude Code conversation windowless (Phiên gần đây). `folder` is where it ran.
    /// `liveSessions`: the hook rows the caller knows (`AgentSessionMonitor.shared.sessions`), passed in so this file stays
    /// free of the monitor.
    func resumeClaude(sessionID: String, folder: URL, liveSessions: [AgentSession]) async throws {
        let sid = sessionID.lowercased()
        // Review: the recent list can be stale — the same conversation may be open in a terminal again, and two writers on
        // one transcript interleave. A live hook row, or a `claude` process whose arguments name the id, refuses it.
        let hookLive = liveSessions.contains {
            $0.agent == .claude && $0.id.lowercased() == sid && $0.status != .ended && !$0.hostedByXFinder
        }
        let processLive = await Task.detached(priority: .userInitiated) { Self.processArgumentsMention(sid) }.value
        guard !hookLive, !processLive else { throw StartError.openElsewhere }
        try await launch(sessionID: sid, folder: folder, resume: true)
    }

    /// Is a `claude` process running with this session id among its arguments (`--resume <id>` / `--session-id <id>`)?
    /// A session picked from the in-terminal picker has no id in its arguments — only a hook row reveals that one.
    nonisolated static func processArgumentsMention(_ sessionID: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "args="]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").contains { line in
            line.lowercased().contains(sessionID) && line.contains("claude")
        }
    }

    private func launch(sessionID: String, folder: URL, resume: Bool, extraArguments: [String] = [],
                        extraEnvironment: [String: String] = [:], pathPrepend: String? = nil) async throws {
        guard children[sessionID] == nil else { throw StartError.alreadyRunning }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { throw StartError.badFolder }
        guard let base = WindowlessRules.claudeArguments(sessionID: sessionID, resume: resume) else { throw StartError.badSessionID }
        let args = base + extraArguments
        let login = await resolveEnvironment()
        try Task.checkCancellation()                       // the person backed out while the environment resolved
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = WindowlessRules.childEnvironment(login: login, fallback: ProcessInfo.processInfo.environment, home: home)
        guard let claude = claudePath(env: env) else { throw StartError.noClaude }
        guard children[sessionID] == nil else { throw StartError.alreadyRunning }   // the await above can interleave
        for (k, v) in extraEnvironment { env[k] = v }
        if let pathPrepend { env["PATH"] = pathPrepend + ":" + (env["PATH"] ?? "/usr/bin:/bin") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: claude)
        p.arguments = args
        p.currentDirectoryURL = folder
        p.environment = env
        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors
        generation += 1
        let gen = generation
        let sid = sessionID
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil          // EOF: clear here or GCD spins (see NowPlayingMonitor)
                return
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consume(data, sessionID: sid, gen: gen) } }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let text = String(decoding: data.suffix(2_000), as: UTF8.self)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.noteStderr(text, sessionID: sid, gen: gen) } }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.ended(sessionID: sid, gen: gen, code: code) } }
        }
        // The child can exit between `isRunning` and a write (a stop, a crash): without F_SETNOSIGPIPE that write raises
        // SIGPIPE and kills XFinder (measured, exit 141). With it, the write throws and `send` reports failure.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try p.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            throw StartError.launchFailed(error.localizedDescription)
        }
        children[sessionID] = Child(process: p, stdin: input.fileHandleForWriting, stdout: output, stderr: errors, generation: gen)
        let now = Date()
        var record = records[sessionID] ?? WindowlessRules.Record(sessionID: sessionID, cwd: folder.path, startedAt: now, updatedAt: now)
        record.phase = .idle
        record.pid = p.processIdentifier
        record.cwd = folder.path
        record.lastError = nil
        record.updatedAt = now
        records[sessionID] = record
        rememberFolder(folder.path)
        log.info("windowless claude started pid=\(p.processIdentifier) resume=\(resume)")
        onChange?()
    }

    // MARK: - Send / stop

    /// One turn to a hosted session (P6 replies). false when it could not go now — busy or gone.
    func send(_ text: String, to sessionID: String) -> Bool { deliver(text, to: sessionID) == .sent }

    /// The gate: writes a turn only to a live session that is free (no message yet, or its last turn ended).
    func deliver(_ text: String, to sessionID: String) -> SendResult {
        let sid = sessionID.lowercased()
        guard let child = children[sid], child.process.isRunning, let record = records[sid], !record.isEnded else { return .gone }
        switch record.phase {
        case .idle, .waiting: break
        case .working, .ended: return .busy
        }
        guard let clean = WindowlessRules.cleanMessage(text), let line = WindowlessRules.userTurnLine(clean) else { return .busy }
        do {
            try child.stdin.write(contentsOf: line)
        } catch {
            log.error("stdin write failed: \(error.localizedDescription)")
            return .gone
        }
        records[sid]?.sent(clean, at: Date())
        onChange?()
        return .sent
    }

    /// End the current turn cleanly (SIGINT — Claude Code records the turn as interrupted instead of losing it).
    func interrupt(_ sessionID: String) {
        guard let child = children[sessionID.lowercased()], child.process.isRunning else { return }
        child.process.interrupt()
    }

    /// Stop the session: interrupt the turn, close stdin (the process ends), SIGTERM after 3 s if it is still there.
    func stop(_ sessionID: String) {
        let sid = sessionID.lowercased()
        guard let child = children[sid] else { return }
        if child.process.isRunning { child.process.interrupt() }
        try? child.stdin.close()
        let gen = child.generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated {
                if let c = self?.children[sid], c.generation == gen, c.process.isRunning { c.process.terminate() }
            }
        }
    }

    /// Drop an ended record from the list.
    func forget(_ sessionID: String) {
        let sid = sessionID.lowercased()
        guard children[sid] == nil else { return }
        records.removeValue(forKey: sid)
        onChange?()
    }

    /// XFinder is quitting: every child gets the clean stop. Synchronous part only (the processes finish on their own).
    func stopAll() {
        for (_, child) in children {
            if child.process.isRunning { child.process.interrupt() }
            try? child.stdin.close()
        }
    }

    // MARK: - Stream

    private func consume(_ data: Data, sessionID: String, gen: Int) {
        guard var child = children[sessionID], child.generation == gen else { return }
        child.buffer.append(data)
        if child.buffer.count > Self.maxLineBytes, !child.buffer.contains(0x0A) {
            log.error("dropping a \(child.buffer.count)-byte line with no newline")
            child.buffer.removeAll(keepingCapacity: false)
        }
        var events: [WindowlessRules.StreamEvent] = []
        while let nl = child.buffer.firstIndex(of: 0x0A) {
            let lineData = child.buffer[child.buffer.startIndex..<nl]
            child.buffer.removeSubrange(child.buffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .utf8) else { continue }
            let e = WindowlessRules.parse(line: line)
            if e != .ignored { events.append(e) }
        }
        children[sessionID] = child
        guard !events.isEmpty, var record = records[sessionID] else { return }
        let now = Date()
        for e in events { record.apply(e, at: now) }
        records[sessionID] = record
        onChange?()
        // After the record says "waiting", so a relay that writes at once finds the session free.
        for e in events { if case .result(_, let text, _) = e { crewObserver?(.turnEnded(sessionID: sessionID, result: text)) } }
    }

    private func noteStderr(_ text: String, sessionID: String, gen: Int) {
        guard var child = children[sessionID], child.generation == gen else { return }
        child.lastStderr = text.split(separator: "\n").last.map(String.init)
        children[sessionID] = child
    }

    private func ended(sessionID: String, gen: Int, code: Int32) {
        guard let child = children[sessionID], child.generation == gen else { return }
        child.stdout.fileHandleForReading.readabilityHandler = nil
        child.stderr.fileHandleForReading.readabilityHandler = nil
        children.removeValue(forKey: sessionID)
        if var record = records[sessionID] {
            // A launch that dies before saying anything (sign-in needed, bad flag) leaves its stderr as the reason.
            if code != 0, record.turns == 0 || record.lastError == nil, let err = child.lastStderr, !err.isEmpty {
                record.lastError = err
                record.append(.note, err, at: Date())
            }
            record.exited(code: code, at: Date())
            record.pid = nil
            records[sessionID] = record
            rememberEnded(record)
        }
        log.info("windowless claude ended code=\(code)")
        onChange?()
        crewObserver?(.processEnded(sessionID: sessionID))
    }

    // MARK: - Folders

    /// The folders a new session was last started in, newest first (at most 8). Read and written only here.
    static let foldersKey = "agents.windowless.folders"
    var recentFolders: [String] { UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? [] }

    func rememberFolder(_ path: String) {
        var list = recentFolders.filter { $0 != path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(8)), forKey: Self.foldersKey)
    }

    /// What the notch composer offers: remembered folders first, then `extra` (live and recent sessions' folders);
    /// existing folders only, no duplicates, at most 8.
    func folderChoices(extra: [String]) -> [String] {
        var seen = Set<String>()
        return (recentFolders + extra).filter { p in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue && seen.insert(p).inserted
        }.prefix(8).map { $0 }
    }

    // MARK: - History (Phiên gần đây)

    /// Ended windowless sessions that took at least one turn: id, folder, time — what "Phiên gần đây" needs to reopen
    /// them. Kept here because the transcript head of a `-p` session says `entrypoint: "sdk-cli"` (measured: 6 of the
    /// newest 100 transcripts here), and the recent scan lists only `cli` — `sdk-cli` also covers other tools' headless
    /// runs, so XFinder lists only the sessions it hosted itself. At most 20; no message is stored.
    static let historyKey = "agents.windowless.history"

    func historyEntries(maxAge: TimeInterval, now: Date = Date()) -> [AgentRecent.Entry] {
        let raw = UserDefaults.standard.array(forKey: Self.historyKey) as? [[String: Any]] ?? []
        return raw.compactMap { d -> AgentRecent.Entry? in
            guard let id = d["id"] as? String, UUID(uuidString: id) != nil, let cwd = d["cwd"] as? String,
                  let t = d["updated"] as? Double else { return nil }
            let updated = Date(timeIntervalSince1970: t)
            guard now.timeIntervalSince(updated) < maxAge else { return nil }
            return AgentRecent.Entry(agent: .claude, sessionID: id, cwd: cwd, updated: updated, title: nil)
        }
    }

    private func rememberEnded(_ r: WindowlessRules.Record) {
        guard r.turns > 0 else { return }            // nothing was said: nothing to reopen
        var raw = (UserDefaults.standard.array(forKey: Self.historyKey) as? [[String: Any]] ?? [])
            .filter { ($0["id"] as? String) != r.sessionID }
        raw.insert(["id": r.sessionID, "cwd": r.cwd, "updated": r.updatedAt.timeIntervalSince1970], at: 0)
        UserDefaults.standard.set(Array(raw.prefix(20)), forKey: Self.historyKey)
    }

    // MARK: - Rows

    var sessions: [AgentSession] { orderedRecords.map(WindowlessRules.session(for:)) }
}
