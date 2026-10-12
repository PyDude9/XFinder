import AppKit
import Foundation

/// N3 — the live half of AI agent sessions on the notch. ONE reader of `agents.enabled`. While on it watches the
/// folder the hook script writes to (a `DispatchSource` per day file — appends do not change the directory, so a
/// directory watch alone would miss every event after the first), replays the day's lines into `AgentSession`s
/// with the pure rules, checks that each `claude` process is still alive, writes the decision file a blocking
/// `PermissionRequest` hook is waiting for, and installs / removes the hook in `~/.claude/settings.json` — the
/// last two only when the person presses the button, never from a switch.
///
/// Idle cost when on and nothing is happening: two file-system sources (kernel-side, no polling) and a 20 s
/// liveness timer that exists ONLY while a session is listed as alive. Off ⇒ nothing.
@MainActor
final class AgentSessionMonitor {
    static let shared = AgentSessionMonitor()

    private(set) var sessions: [AgentSession] = []
    /// Fires on every change of `sessions` (Observation has no publishers; the controller mirrors into its model).
    var onChange: (() -> Void)?

    // MARK: - Settings (the one reader)

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "agents.enabled") as? Bool ?? false }

    // MARK: - Paths

    static let supportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("XFinder/Agents/claude", isDirectory: true)
    }()
    var eventsDir: URL { Self.supportDir.appendingPathComponent("events", isDirectory: true) }
    var decisionsDir: URL { Self.supportDir.appendingPathComponent("decisions", isDirectory: true) }
    var hookURL: URL { Self.supportDir.appendingPathComponent("bin/xfinder-claude-hook.zsh") }
    static let claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    // MARK: - Lifecycle

    private var running = false
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedFile: URL?
    private var offsets: [String: UInt64] = [:]
    private var events: [AgentEvents.Event] = []
    private var answered: Set<String> = []
    private var reloadWork: DispatchWorkItem?
    private var livenessTimer: Timer?

    /// Under the notch master switch: a notch that is off has no page to show sessions on.
    func applySettings(underMaster master: Bool = true) {
        if master && isEnabled { start() } else { stop() }
    }

    private func start() {
        guard !running else { return }
        running = true
        ensureDirectories()
        offsets = [:]; events = []
        reload(full: true)
        watchDirectory()
        watchTodayFile()
    }

    private func stop() {
        guard running else { return }
        running = false
        dirSource?.cancel(); dirSource = nil
        fileSource?.cancel(); fileSource = nil; watchedFile = nil
        livenessTimer?.invalidate(); livenessTimer = nil
        reloadWork?.cancel(); reloadWork = nil
        offsets = [:]; events = []; answered = []
        if !sessions.isEmpty { sessions = []; onChange?() }
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [Self.supportDir, eventsDir, decisionsDir, hookURL.deletingLastPathComponent()] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    // MARK: - Watching

    private func watchDirectory() {
        dirSource?.cancel()
        let fd = open(eventsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {       // queue: .main ⇒ the main thread; a documented contract, not a guess
                self?.watchTodayFile()
                self?.scheduleReload()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSource = src
    }

    /// (Re)attach the file watch to today's file when it appears or the day rolls over.
    private func watchTodayFile() {
        let today = eventsDir.appendingPathComponent(AgentEvents.eventsFileName(for: Date()))
        guard today != watchedFile || fileSource == nil else { return }
        fileSource?.cancel(); fileSource = nil; watchedFile = nil
        let fd = open(today.path, O_EVTONLY)
        guard fd >= 0 else { return }                       // not written yet; the directory watch retries
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.scheduleReload() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
        watchedFile = today
    }

    /// Coalesce bursts (a tool call writes Pre + Post within milliseconds) into one rebuild.
    private func scheduleReload() {
        reloadWork?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.reload(full: false) } }
        reloadWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: w)
    }

    /// Read what is new in today's and yesterday's files (a session straddling midnight keeps its history).
    private func reload(full: Bool) {
        let now = Date()
        let files = [AgentEvents.eventsFileName(for: now.addingTimeInterval(-86_400)), AgentEvents.eventsFileName(for: now)]
            .map { eventsDir.appendingPathComponent($0) }
        if full { events = []; offsets = [:] }
        for url in files {
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            let start = offsets[url.lastPathComponent] ?? 0
            let size = (try? h.seekToEnd()) ?? 0
            guard size > start else {
                if size < start { offsets[url.lastPathComponent] = 0 }   // truncated / replaced ⇒ re-read next time
                continue
            }
            try? h.seek(toOffset: start)
            guard let data = try? h.readToEnd(), !data.isEmpty else { continue }
            // Only complete lines: the hook may be mid-write; the remainder is read on the next event.
            var consumed = data
            var carry: UInt64 = 0
            if data.last != UInt8(ascii: "\n"), let nl = data.lastIndex(of: UInt8(ascii: "\n")) {
                consumed = data[...nl]; carry = UInt64(data.count - consumed.count)
            } else if data.last != UInt8(ascii: "\n") {
                consumed = Data(); carry = UInt64(data.count)
            }
            offsets[url.lastPathComponent] = size - carry
            if !consumed.isEmpty { events.append(contentsOf: AgentEvents.parse(jsonl: String(decoding: consumed, as: UTF8.self))) }
        }
        if events.count > 20_000 { events.removeFirst(events.count - 20_000) }
        rebuild()
    }

    private func rebuild() {
        let now = Date()
        let new = AgentSessionRules.sessions(from: events, now: now, answered: answered, isAlive: Self.isAlive)
        if new != sessions {
            sessions = new
            onChange?()
        }
        syncLivenessTimer()
    }

    /// A 20 s re-evaluation while any listed session is not ended: a `claude` that quit without a SessionEnd
    /// (⌃C, a crash) is noticed by its pid disappearing. No timer while nothing is alive.
    private func syncLivenessTimer() {
        let anyAlive = sessions.contains { $0.status != .ended }
        if anyAlive, livenessTimer == nil {
            let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }
            RunLoop.main.add(t, forMode: .common)
            livenessTimer = t
        } else if !anyAlive, let t = livenessTimer {
            t.invalidate(); livenessTimer = nil
        }
    }

    nonisolated static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Decisions

    /// Answer the pending permission request of a session: the hook polls for this file (every 0.25 s), prints its
    /// content to Claude Code and exits. `answered` makes the row flip at once instead of waiting for the next event.
    @discardableResult
    func answer(_ p: AgentSession.PendingPermission, of session: AgentSession, allow: Bool) -> Bool {
        let url = decisionsDir.appendingPathComponent(AgentDecision.fileName(sessionID: session.id, requestID: p.requestID))
        let payload = AgentDecision.payload(allow: allow)
        do {
            try payload.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            answered.insert(p.requestID)
            rebuild()
            return true
        } catch {
            return false
        }
    }

    /// Bring the session's terminal forward. Only what the hook recorded can be acted on: the terminal app's
    /// bundle id (iTerm, Terminal, Ghostty, Warp, kitty, WezTerm…). Focusing the exact tab needs each
    /// terminal's own scripting and is not attempted — the row says "mở app", not "mở tab".
    @discardableResult
    func openTerminal(of session: AgentSession) -> Bool {
        guard let bid = session.terminal.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    // MARK: - Hook install (on request only)

    enum HookStatus: Equatable { case installed, partial(missing: [String]), notInstalled, settingsUnreadable }

    func hookStatus() -> HookStatus {
        guard FileManager.default.fileExists(atPath: hookURL.path) else { return .notInstalled }
        switch readClaudeSettings() {
        case .failure: return .settingsUnreadable
        case .success(let s):
            switch AgentHookInstaller.status(of: s, hookPath: hookURL.path) {
            case .installed: return .installed
            case .partial(let m): return .partial(missing: m)
            case .notInstalled: return .notInstalled
            }
        }
    }

    enum HookError: Error { case bundleResourceMissing, settingsUnreadable }

    /// Copy the bundled script into Application Support (so an app update or move never breaks the path Claude
    /// Code holds), then merge XFinder's entries into `~/.claude/settings.json` — after writing a dated backup
    /// of the file beside it. Other tools' hooks are untouched.
    func installHook() throws {
        ensureDirectories()
        guard let src = Bundle.main.url(forResource: "xfinder-claude-hook", withExtension: "zsh") else { throw HookError.bundleResourceMissing }
        let fm = FileManager.default
        let data = try Data(contentsOf: src)
        try data.write(to: hookURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hookURL.path)
        let settings: [String: Any]
        switch readClaudeSettings() {
        case .success(let s): settings = s
        case .failure: throw HookError.settingsUnreadable
        }
        try backupClaudeSettings()
        let merged = AgentHookInstaller.merged(settings, hookPath: hookURL.path)
        try writeClaudeSettings(merged)
    }

    func removeHook() throws {
        guard case .success(let settings) = readClaudeSettings() else { throw HookError.settingsUnreadable }
        try backupClaudeSettings()
        try writeClaudeSettings(AgentHookInstaller.removed(settings, hookPath: hookURL.path))
        try? FileManager.default.removeItem(at: hookURL)
    }

    private func readClaudeSettings() -> Result<[String: Any], Error> {
        let url = Self.claudeSettingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .success([:]) }
        do {
            let data = try Data(contentsOf: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(HookError.settingsUnreadable)
            }
            return .success(obj)
        } catch { return .failure(error) }
    }

    private func backupClaudeSettings() throws {
        let url = Self.claudeSettingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.xfinder-backup-\(f.string(from: Date()))")
        try FileManager.default.copyItem(at: url, to: backup)
    }

    private func writeClaudeSettings(_ settings: [String: Any]) throws {
        let url = Self.claudeSettingsURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AgentHookInstaller.data(for: settings).write(to: url, options: .atomic)
    }
}
