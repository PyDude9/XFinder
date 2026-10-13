import Foundation
import os

/// P5b — the live half of OpenCode sessions (rules and measurements: `OpenCodeRules`). ONE reader of
/// `agents.opencode`, under `agents.enabled` and the notch master (applied by `AgentSessionMonitor`).
///
/// Cost model, every piece demand-driven:
/// * kernel file sources on OpenCode's database folder, `opencode.db` and `opencode.db-wal` — no polling;
/// * a write to the database (a turn streaming, a tool call) is the cue: one refresh at most every 2 s while
///   writes continue, plus one trailing refresh 2.5 s after the last write (the permission request that a tool
///   call triggers is created in memory right after its write);
/// * a refresh is 2–4 runs of the person's own `opencode api` (~0.04 s CPU each) on a background task;
/// * a 30 s safety refresh exists only while a listed session is not ended (a request answered from the terminal
///   is noticed even if nothing else is written).
/// Off, no OpenCode installed, or nothing written ⇒ nothing runs.
@MainActor
final class OpenCodeMonitor {
    static let shared = OpenCodeMonitor()

    private(set) var sessions: [AgentSession] = []
    var onChange: (() -> Void)?

    enum State: Equatable { case off, binaryMissing, ready, failed(String) }
    private(set) var state: State = .off
    private(set) var binaryPath: String?
    private(set) var lastRefreshAt: Date?

    // MARK: - Settings (the one reader)

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "agents.opencode") as? Bool ?? false }

    // MARK: - Paths

    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    /// OpenCode's data folder (`$XDG_DATA_HOME/opencode`, default ~/.local/share/opencode). An app started from the
    /// Dock never sees a shell's XDG variables, so the default is what is watched.
    static let dataDir = URL(fileURLWithPath: home).appendingPathComponent(".local/share/opencode", isDirectory: true)

    static func findBinary() -> String? {
        OpenCodeRules.binaryCandidates(home: home).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Lifecycle

    private var running = false
    private var sources: [DispatchSourceFileSystemObject] = []
    private var inFlight = false
    private var again = false
    private var lastRun = Date.distantPast
    private var throttleWork: DispatchWorkItem?
    private var trailingWork: DispatchWorkItem?
    private var safetyTimer: Timer?
    private var answered: Set<String> = []
    private var firstSeen: [String: Date] = [:]
    private var lastSnapshot: Snapshot?

    func applySettings(underMaster master: Bool) {
        if master && isEnabled { start() } else { stop() }
    }

    private func start() {
        guard !running else { return }
        running = true
        binaryPath = Self.findBinary()
        guard binaryPath != nil else {
            state = .binaryMissing
            publish([])
            return
        }
        state = .ready
        watch()
        refresh()
    }

    private func stop() {
        guard running else { return }
        running = false
        for s in sources + fileSources { s.cancel() }
        sources = []; fileSources = []
        throttleWork?.cancel(); throttleWork = nil
        trailingWork?.cancel(); trailingWork = nil
        safetyTimer?.invalidate(); safetyTimer = nil
        answered = []; firstSeen = [:]; lastSnapshot = nil
        state = .off
        publish([])
    }

    // MARK: - Watching

    private func watch() {
        for s in sources { s.cancel() }
        sources = []
        let dir = Self.dataDir
        // The folder: the WAL file is deleted and recreated at checkpoints, which re-attaches the file sources.
        attach(dir.path, mask: [.write]) { [weak self] in self?.reattachFiles(); self?.cue() }
        reattachFiles()
    }

    private var fileSources: [DispatchSourceFileSystemObject] = []

    private func reattachFiles() {
        guard running else { return }
        for s in fileSources { s.cancel() }
        fileSources = []
        for name in ["opencode.db", "opencode.db-wal"] {
            let path = Self.dataDir.appendingPathComponent(name).path
            if let src = makeSource(path, mask: [.write, .extend, .delete, .rename], handler: { [weak self] in self?.cue() }) {
                fileSources.append(src)
            }
        }
    }

    private func attach(_ path: String, mask: DispatchSource.FileSystemEvent, handler: @escaping @MainActor () -> Void) {
        if let src = makeSource(path, mask: mask, handler: handler) { sources.append(src) }
    }

    private func makeSource(_ path: String, mask: DispatchSource.FileSystemEvent,
                            handler: @escaping @MainActor () -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        src.setEventHandler { MainActor.assumeIsolated { handler() } }   // queue: .main — a documented contract
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }

    /// A write happened: refresh now if the last one was ≥ 2 s ago (else once that window ends), and again 2.5 s
    /// after the last write.
    private func cue() {
        guard running else { return }
        trailingWork?.cancel()
        let trailing = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        trailingWork = trailing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: trailing)
        let wait = 2 - Date().timeIntervalSince(lastRun)
        if wait <= 0 { refresh(); return }
        guard throttleWork == nil else { return }
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.throttleWork = nil; self?.refresh() }
        }
        throttleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: w)
    }

    // MARK: - Refresh

    struct Snapshot: Sendable {
        var info: [OpenCodeRules.SessionInfo] = []
        var active: Set<String> = []
        var pending: [OpenCodeRules.PendingRequest] = []
        var clientOpen = false
        var error: String?
    }

    func refresh() {
        guard running, let bin = binaryPath else { return }
        if inFlight { again = true; return }
        inFlight = true
        lastRun = Date()
        Task.detached(priority: .utility) {
            let snap = Self.fetch(binary: bin)
            await MainActor.run { OpenCodeMonitor.shared.apply(snap) }
        }
    }

    private func apply(_ snap: Snapshot) {
        inFlight = false
        guard running else { return }
        lastRefreshAt = Date()
        if let err = snap.error {
            state = .failed(err)
        } else {
            state = .ready
            lastSnapshot = snap
            let now = Date()
            for p in snap.pending where firstSeen[p.id] == nil { firstSeen[p.id] = now }
            let live = Set(snap.pending.map(\.id))
            firstSeen = firstSeen.filter { live.contains($0.key) }
            answered = answered.intersection(live)          // an answered request that is gone needs no memory
            rebuild()
        }
        if again { again = false; cue() }
    }

    private func rebuild() {
        guard let snap = lastSnapshot else { return }
        let rows = OpenCodeRules.sessions(info: snap.info, active: snap.active, pending: snap.pending,
                                          clientOpen: snap.clientOpen, now: Date(), answered: answered, firstSeen: firstSeen)
        publish(rows)
        syncSafetyTimer()
    }

    private func publish(_ rows: [AgentSession]) {
        guard rows != sessions else { return }
        sessions = rows
        onChange?()
    }

    private func syncSafetyTimer() {
        let live = sessions.contains { $0.status != .ended }
        if live, safetyTimer == nil {
            let t = Timer(timeInterval: 30, repeats: true) { _ in Task { @MainActor in OpenCodeMonitor.shared.refresh() } }
            RunLoop.main.add(t, forMode: .common)
            safetyTimer = t
        } else if !live, let t = safetyTimer {
            t.invalidate(); safetyTimer = nil
        }
    }

    /// Off the main thread: the person's own `opencode api` calls, in order.
    nonisolated static func fetch(binary: String) -> Snapshot {
        var snap = Snapshot()
        let active = run(binary, OpenCodeRules.activeArguments())
        guard active.status == 0, let ids = OpenCodeRules.parseActive(active.out) else {
            snap.error = Self.errorLine(active)
            return snap
        }
        snap.active = ids
        let list = run(binary, OpenCodeRules.listArguments(limit: 12))
        snap.info = (list.status == 0 ? OpenCodeRules.parseSessions(list.out) : nil) ?? []
        // A request belongs to a session mid-turn; a session that moved in the last 2 minutes is asked too, in case
        // `session.active` and the request disagree for an instant. At most 5 sessions are asked.
        let now = Date()
        let recent = snap.info.filter { $0.parentID == nil && now.timeIntervalSince($0.updated) < 120 }.map(\.id)
        let ask = Array(NSOrderedSet(array: Array(ids) + recent).array.compactMap { $0 as? String }.prefix(5))
        for sid in ask {
            guard let args = OpenCodeRules.permissionListArguments(sessionID: sid) else { continue }
            let r = run(binary, args)
            if r.status == 0, let reqs = OpenCodeRules.parsePermissions(r.out) { snap.pending.append(contentsOf: reqs) }
        }
        let ps = run("/bin/ps", ["-axo", "command="])
        snap.clientOpen = OpenCodeRules.clientRunning(psCommands: String(decoding: ps.out, as: UTF8.self))
        return snap
    }

    nonisolated private static func errorLine(_ r: RunResult) -> String {
        let text = String(decoding: r.err.isEmpty ? r.out : r.err, as: UTF8.self)
        let first = text.split(separator: "\n").first.map(String.init) ?? "exit \(r.status)"
        return String(first.prefix(160))
    }

    // MARK: - Answering

    /// Answer a pending request from the notch. The row flips at once; a failed reply puts it back and says why.
    @discardableResult
    func answer(_ p: AgentSession.PendingPermission, of session: AgentSession, allow: Bool) -> Bool {
        guard let bin = binaryPath,
              let args = OpenCodeRules.replyArguments(sessionID: session.id, requestID: p.requestID, allow: allow) else { return false }
        answered.insert(p.requestID)
        rebuild()
        let requestID = p.requestID
        Task.detached(priority: .userInitiated) {
            let r = Self.run(bin, args)
            await MainActor.run {
                let me = OpenCodeMonitor.shared
                if r.status != 0 {
                    me.answered.remove(requestID)
                    me.state = .failed(Self.errorLine(r))
                    me.rebuild()
                }
                me.cue()
            }
        }
        return true
    }

    // MARK: - Process

    struct RunResult: Sendable { var status: Int32; var out: Data; var err: Data }

    /// Runs a command with an 8 s ceiling; both pipes are drained before waiting (a full pipe would block the child).
    nonisolated static func run(_ path: String, _ args: [String]) -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return RunResult(status: -1, out: Data(), err: Data("\(error)".utf8)) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: killer)
        let errBox = OSAllocatedUnfairLock(initialState: Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            let d = err.fileHandleForReading.readDataToEndOfFile()
            errBox.withLock { $0 = d }
            group.leave()
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        killer.cancel()
        return RunResult(status: p.terminationStatus, out: outData, err: errBox.withLock { $0 })
    }
}
