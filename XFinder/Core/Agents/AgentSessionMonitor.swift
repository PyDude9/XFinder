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
    // P5c — notices at the notch (each the ONE reader of its key).
    var notifyPermission: Bool { UserDefaults.standard.object(forKey: "agents.notify.permission") as? Bool ?? true }
    var notifyFinished: Bool { UserDefaults.standard.object(forKey: "agents.notify.finished") as? Bool ?? true }
    var notifySound: Bool { UserDefaults.standard.object(forKey: "agents.notify.sound") as? Bool ?? false }
    /// P8: no notice and no sound for a session whose terminal / app is frontmost (OneNotch does the same).
    /// P10 — the ONE readers of the list's order and of whether ended sessions stay listed.
    var sortModeRaw: String { UserDefaults.standard.string(forKey: "agents.sortMode") ?? "priority" }
    var keepFinished: Bool { UserDefaults.standard.object(forKey: "agents.keepFinished") as? Bool ?? true }
    var notifyQuietWhenFront: Bool { UserDefaults.standard.object(forKey: "agents.notify.quietWhenFront") as? Bool ?? true }

    // MARK: - Paths

    /// `~/Library/Application Support/XFinder/Agents/<agent>` — the hook writes `events/` there and waits in `decisions/`.
    static func supportDir(for agent: AgentKind) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("XFinder/Agents/\(agent.rawValue)", isDirectory: true)
    }
    /// Claude's folder (the statusLine cache lives here too — `ClaudeStatusLine.supportDir(home:)`).
    static let supportDir: URL = supportDir(for: .claude)
    func eventsDir(for agent: AgentKind) -> URL { Self.supportDir(for: agent).appendingPathComponent("events", isDirectory: true) }
    func decisionsDir(for agent: AgentKind) -> URL { Self.supportDir(for: agent).appendingPathComponent("decisions", isDirectory: true) }
    /// Where the hook script is copied. Claude keeps its pre-P5 file name, so a hook installed by 1.3.0 still matches.
    func hookURL(for agent: AgentKind) -> URL {
        Self.supportDir(for: agent).appendingPathComponent(agent == .claude ? "bin/xfinder-claude-hook.zsh" : "bin/xfinder-agent-hook.zsh")
    }
    var hookURL: URL { hookURL(for: .claude) }
    static let claudeSettingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    /// Codex's user-level hook file (learn.chatgpt.com/docs/hooks). `CODEX_HOME` would move it, but an app launched
    /// from the Dock never sees a shell's environment — ~/.codex is what Codex uses unless told otherwise.
    static let codexHooksURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    static func hookFileURL(for agent: AgentKind) -> URL { agent == .codex ? codexHooksURL : claudeSettingsURL }

    /// The agents whose hook logs are tailed.
    static let hookAgents: [AgentKind] = AgentKind.allCases.filter(\.usesHookScript)

    // MARK: - Lifecycle

    private var running = false
    private var tails: [AgentKind: EventTail] = [:]
    private var answered: Set<String> = []
    private var reloadWork: DispatchWorkItem?
    private var livenessTimer: Timer?
    /// When each agent's hook last wrote a line — the only proof that a hook really runs (Codex skips a hook until
    /// the person trusts it in `/hooks`, and nothing else tells XFinder whether they did).
    private(set) var lastEventAt: [AgentKind: Date] = [:]

    /// Under the notch master switch: a notch that is off has no page to show sessions on. OpenCode (P5b) rides
    /// the same switches plus its own.
    func applySettings(underMaster master: Bool = true) {
        if !refreshedScripts { refreshedScripts = true; refreshInstalledScripts() }
        if master && isEnabled { start() } else { stop() }
        OpenCodeMonitor.shared.onChange = { [weak self] in self?.rebuild() }
        WindowlessSessionManager.shared.onChange = { [weak self] in self?.rebuild() }
        OpenCodeMonitor.shared.applySettings(underMaster: master && isEnabled)
    }

    private var refreshedScripts = false

    /// P10 — the list's order or the keep-finished switch changed on the settings page.
    func listSettingsChanged() { rebuild() }

    /// An installed copy of our own scripts follows the app. The hook gained fields after people had installed it (P5c: the
    /// session-id check; P6: where a reply can be typed) and nothing re-copied it, so the agent kept running the old file
    /// until someone pressed "Cài hook" again. Only a copy that EXISTS is replaced — installing stays a button — and only
    /// our own file in Application Support: the agents' settings files are not touched. The write is atomic, so a hook
    /// that is running right now keeps reading the file it opened.
    private func refreshInstalledScripts() {
        let fm = FileManager.default
        let hookSource = Bundle.main.url(forResource: "xfinder-agent-hook", withExtension: "zsh")
        var pairs: [(dest: URL, source: URL?)] = Self.hookAgents.map { (hookURL(for: $0), hookSource) }
        pairs.append((statusLineScriptURL, Bundle.main.url(forResource: "xfinder-claude-statusline", withExtension: "sh")))
        for (dest, source) in pairs {
            guard let source, fm.fileExists(atPath: dest.path),
                  let fresh = try? Data(contentsOf: source), let old = try? Data(contentsOf: dest), fresh != old else { continue }
            try? fresh.write(to: dest, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dest.path)
        }
    }

    private func start() {
        guard !running else { return }
        running = true
        answered = []
        for agent in Self.hookAgents {
            ensureDirectories(for: agent)
            let tail = EventTail(agent: agent, eventsDir: eventsDir(for: agent))
            tail.onChange = { [weak self] in self?.scheduleReload() }
            tails[agent] = tail
            tail.reload(full: true)
            tail.watch()
        }
        rebuild()
    }

    private func stop() {
        guard running else { return }
        running = false
        for tail in tails.values { tail.cancel() }
        tails = [:]
        livenessTimer?.invalidate(); livenessTimer = nil
        reloadWork?.cancel(); reloadWork = nil
        answered = []; lastEventAt = [:]
        notifyBaseline = nil
        if !sessions.isEmpty { sessions = []; onChange?() }
    }

    private func ensureDirectories(for agent: AgentKind) {
        let fm = FileManager.default
        for dir in [Self.supportDir(for: agent), eventsDir(for: agent), decisionsDir(for: agent), hookURL(for: agent).deletingLastPathComponent()] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }

    /// Coalesce bursts (a tool call writes Pre + Post within milliseconds) into one rebuild.
    private func scheduleReload() {
        reloadWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                for tail in self.tails.values { tail.reload(full: false) }
                self.rebuild()
            }
        }
        reloadWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: w)
    }

    private func rebuild() {
        let now = Date()
        var all: [AgentEvents.Event] = []
        for (agent, tail) in tails {
            all.append(contentsOf: tail.events)
            if let last = tail.events.last?.receivedAt { lastEventAt[agent] = last }
        }
        let hooked = running ? AgentSessionRules.sessions(from: all, now: now, answered: answered, isAlive: Self.isAlive) : []
        // P7a: XFinder's own windowless sessions — merged over the hook rows for the same id (the hook alone knows a
        // pending permission request), added as rows of their own when no hook line exists (hook not installed).
        let hosted = running ? WindowlessRules.merged(hookSessions: hooked, records: WindowlessSessionManager.shared.orderedRecords) : []
        let new = AgentSessionRules.ordered(hosted + OpenCodeMonitor.shared.sessions, mode: AgentSessionRules.SortMode.parse(sortModeRaw),
                                           keepFinished: keepFinished)
        if new != sessions {
            notify(old: notifyBaseline, new: new)
            sessions = new
            onChange?()
        }
        notifyBaseline = running ? sessions : nil
        AgentTalkSender.shared.sessionsChanged(sessions)        // P6: held replies go out when their session is free
        syncLivenessTimer()
    }

    // MARK: - Notices (P5c)

    /// The sessions the last notice decision was made against; nil until the first rebuild after starting, so a
    /// launch (or turning the feature on) announces nothing.
    private var notifyBaseline: [AgentSession]?

    private func notify(old: [AgentSession]?, new: [AgentSession]) {
        // OpenCode's rows arrive with its first refresh, after the hook baseline: rows from that FIRST snapshot are a
        // baseline too (counting snapshots, not rebuilds — an empty first snapshot triggers no rebuild).
        let openCodeLive = OpenCodeMonitor.shared.snapshotGeneration > 1
        let events = AgentNotify.events(old: old, new: new,
                                        settings: .init(permission: notifyPermission, finished: notifyFinished))
            .filter { e in
                switch e {
                case .needsApproval(let s, _), .finished(let s): return s.agent != .opencode || openCodeLive
                }
            }
        // P8: the person is already looking at that session's terminal or app — nothing pops, nothing sounds.
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let heard = notifyQuietWhenFront ? events.filter { !AgentNotify.isWatched(AgentNotify.session(of: $0), frontmostBundleID: front) } : events
        guard !heard.isEmpty else { return }
        for e in heard { NotchSurfaceController.shared.presentAgentNotice(AgentNotify.item(for: e)) }
        if notifySound { NSSound(named: NSSound.Name(heard.contains { if case .needsApproval = $0 { return true }; return false } ? "Glass" : "Pop"))?.play() }
    }

    // MARK: - Recent sessions (P5c)

    /// Terminal sessions that are no longer live, newest first. Scanned when the notch Agents page opens and when the
    /// settings page asks — never on a timer.
    private(set) var recent: [AgentRecent.Entry] = []
    private var recentScanning = false
    private var recentWaiters: [@MainActor () -> Void] = []
    private var agentsPageOpen = false

    func setAgentsPageOpen(_ open: Bool) {
        defer { agentsPageOpen = open }
        if open && !agentsPageOpen { refreshRecent() }
    }

    func refreshRecent(completion: (@MainActor () -> Void)? = nil) {
        if let completion { recentWaiters.append(completion) }
        guard !recentScanning else { return }
        recentScanning = true
        let openCode = OpenCodeMonitor.shared.recentEntries
        Task.detached(priority: .utility) {
            let scanned = Self.scanRecent(now: Date())
            await MainActor.run {
                let me = AgentSessionMonitor.shared
                me.recentScanning = false
                let wm = WindowlessSessionManager.shared
                let live = Set(me.sessions.map(\.listID) + wm.liveRecords.map { "\(AgentKind.claude.rawValue):\($0.sessionID)" })
                // P7a: windowless sessions XFinder hosted (their transcripts say sdk-cli, which the scan skips).
                let hosted = wm.historyEntries(maxAge: 14 * 86_400)
                let merged = AgentRecent.merged(scanned + openCode + hosted, live: live, limit: 8)
                if merged != me.recent { me.recent = merged; me.onChange?() }
                let waiters = me.recentWaiters
                me.recentWaiters = []
                for w in waiters { w() }
            }
        }
    }

    /// Off the main thread: the newest files of each agent, only their heads (measured limits in `AgentRecent`).
    nonisolated static func scanRecent(now: Date) -> [AgentRecent.Entry] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let maxAge: TimeInterval = 14 * 86_400
        var out: [AgentRecent.Entry] = []

        var claudeFiles: [(URL, Date)] = []
        let projects = home.appendingPathComponent(".claude/projects")
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where f.pathExtension == "jsonl" {
                guard let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      now.timeIntervalSince(m) < maxAge else { continue }
                claudeFiles.append((f, m))
            }
        }
        for (f, m) in claudeFiles.sorted(by: { $0.1 > $1.1 }).prefix(40) {
            guard let h = try? FileHandle(forReadingFrom: f) else { continue }
            let head = (try? h.read(upToCount: AgentRecent.claudeHeadBytes)) ?? Data()
            try? h.close()
            if let e = AgentRecent.claudeEntry(head: head, fileStem: f.deletingPathExtension().lastPathComponent, modified: m) {
                out.append(e)
            }
        }

        var codexFiles: [(URL, Date)] = []
        if let e = fm.enumerator(at: home.appendingPathComponent(".codex/sessions"), includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let f as URL in e where f.pathExtension == "jsonl" {
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if now.timeIntervalSince(m) < maxAge { codexFiles.append((f, m)) }
            }
        }
        for (f, m) in codexFiles.sorted(by: { $0.1 > $1.1 }).prefix(40) {
            guard let h = try? FileHandle(forReadingFrom: f) else { continue }
            let head = (try? h.read(upToCount: 1_048_576)) ?? Data()      // session_meta carries the base instructions
            try? h.close()
            guard let nl = head.firstIndex(of: UInt8(ascii: "\n")) else { continue }
            if let e = AgentRecent.codexEntry(firstLine: String(decoding: head[..<nl], as: UTF8.self), modified: m) {
                out.append(e)
            }
        }
        return out
    }

    /// A 20 s re-evaluation while any listed session is not ended: an agent that quit without a SessionEnd
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
    /// content to the agent and exits. `answered` makes the row flip at once instead of waiting for the next event.
    @discardableResult
    func answer(_ p: AgentSession.PendingPermission, of session: AgentSession, allow: Bool) -> Bool {
        if session.agent == .opencode { return OpenCodeMonitor.shared.answer(p, of: session, allow: allow) }
        // P11: a windowless Codex session's approval waits on XFinder's own pipe to `codex app-server`.
        if session.agent == .codex, session.hostedByXFinder,
           WindowlessSessionManager.shared.records[session.id]?.pendingApproval?.rawID == p.requestID {
            WindowlessSessionManager.shared.answerApproval(sessionID: session.id, requestID: p.requestID, allow: allow)
            return true
        }
        guard session.agent.usesHookScript,
              let name = AgentDecision.fileName(sessionID: session.id, requestID: p.requestID) else { return false }
        let url = decisionsDir(for: session.agent).appendingPathComponent(name)
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

    func hookStatus(for agent: AgentKind = .claude) -> HookStatus {
        guard agent.usesHookScript, FileManager.default.fileExists(atPath: hookURL(for: agent).path) else { return .notInstalled }
        switch readHookFile(for: agent) {
        case .failure: return .settingsUnreadable
        case .success(let s):
            switch AgentHookInstaller.status(of: s, hookPath: hookURL(for: agent).path, agent: agent) {
            case .installed: return .installed
            case .partial(let m): return .partial(missing: m)
            case .notInstalled: return .notInstalled
            }
        }
    }

    func otherPermissionHookCount(for agent: AgentKind) -> Int {
        guard case .success(let s) = readHookFile(for: agent) else { return 0 }
        return AgentHookInstaller.otherPermissionHooks(in: s, hookPath: hookURL(for: agent).path)
    }

    /// Is any agent's hook installed? (The notch's empty state points to the settings page when none is.)
    var anyHookInstalled: Bool { Self.hookAgents.contains { hookStatus(for: $0) == .installed } }

    enum HookError: Error { case bundleResourceMissing, settingsUnreadable }

    /// Copy the bundled script into Application Support (so an app update or move never breaks the path the agent
    /// holds), then merge XFinder's entries into the agent's hook file — after writing a dated backup of the file
    /// beside it. Other tools' hooks are untouched.
    func installHook(for agent: AgentKind = .claude) throws {
        guard agent.usesHookScript else { return }
        ensureDirectories(for: agent)
        guard let src = Bundle.main.url(forResource: "xfinder-agent-hook", withExtension: "zsh") else { throw HookError.bundleResourceMissing }
        let fm = FileManager.default
        let hook = hookURL(for: agent)
        let data = try Data(contentsOf: src)
        try data.write(to: hook, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: hook.path)
        let settings: [String: Any]
        switch readHookFile(for: agent) {
        case .success(let s): settings = s
        case .failure: throw HookError.settingsUnreadable
        }
        try backupHookFile(for: agent)
        try writeHookFile(AgentHookInstaller.merged(settings, hookPath: hook.path, agent: agent), for: agent)
    }

    func removeHook(for agent: AgentKind = .claude) throws {
        guard agent.usesHookScript else { return }
        guard case .success(let settings) = readHookFile(for: agent) else { throw HookError.settingsUnreadable }
        try backupHookFile(for: agent)
        try writeHookFile(AgentHookInstaller.removed(settings, hookPath: hookURL(for: agent).path), for: agent)
        try? FileManager.default.removeItem(at: hookURL(for: agent))
    }

    private func readHookFile(for agent: AgentKind) -> Result<[String: Any], Error> {
        let url = Self.hookFileURL(for: agent)
        guard FileManager.default.fileExists(atPath: url.path) else { return .success([:]) }
        do {
            let data = try Data(contentsOf: url)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(HookError.settingsUnreadable)
            }
            return .success(obj)
        } catch { return .failure(error) }
    }

    private func readClaudeSettings() -> Result<[String: Any], Error> { readHookFile(for: .claude) }

    private func backupHookFile(for agent: AgentKind) throws {
        let url = Self.hookFileURL(for: agent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).xfinder-backup-\(f.string(from: Date()))")
        try FileManager.default.copyItem(at: url, to: backup)
    }

    private func backupClaudeSettings() throws { try backupHookFile(for: .claude) }

    private func writeHookFile(_ settings: [String: Any], for agent: AgentKind) throws {
        let url = Self.hookFileURL(for: agent)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try AgentHookInstaller.data(for: settings).write(to: url, options: .atomic)
    }

    private func writeClaudeSettings(_ settings: [String: Any]) throws { try writeHookFile(settings, for: .claude) }

    // MARK: - Claude Code statusLine (rate-limit cache) install (on request only)

    /// Paths for the statusLine script + cache, under the SAME support folder as the hook
    /// (`AgentSessionMonitor.supportDir` == `ClaudeStatusLine.supportDir(home:)` — both resolve to
    /// `~/Library/Application Support/XFinder/Agents/claude`).
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    var statusLineScriptURL: URL { ClaudeStatusLine.scriptURL(home: Self.home) }
    var statusLineCacheURL: URL { ClaudeStatusLine.cacheURL(home: Self.home) }
    var statusLinePreviousCommandURL: URL { ClaudeStatusLine.previousCommandURL(home: Self.home) }
    var statusLinePreviousJSONURL: URL { ClaudeStatusLine.previousJSONURL(home: Self.home) }

    enum StatusLineState: Equatable { case notInstalled, installed, replaced, settingsUnreadable }

    enum StatusLineError: Error {
        case bundleResourceMissing
        case settingsUnreadable
        /// Removal was asked for, but `statusLine` currently points at something other than XFinder's script —
        /// another tool's installer (or XFinder's own chain, saved by that tool) may lead back to us, so blindly
        /// overwriting it could break that chain. Nothing is changed; the caller tells the person why.
        case pointsAtAnotherCommand
        /// The saved previous value exists but cannot be read back (P2 review: it used to be treated as "nothing was
        /// there before" and the key was deleted). Nothing is changed; the dated settings.json backups still hold it.
        case previousUnreadable
    }

    func statusLineState() -> StatusLineState {
        switch readClaudeSettings() {
        case .failure: return .settingsUnreadable
        case .success(let settings):
            let previousSaved = FileManager.default.fileExists(atPath: statusLinePreviousJSONURL.path)
            switch ClaudeStatusLine.status(of: settings, scriptPath: statusLineScriptURL.path, previousSaved: previousSaved) {
            case .notInstalled: return .notInstalled
            case .installed: return .installed
            case .replaced: return .replaced
            }
        }
    }

    /// Copy the bundled statusLine script into Application Support, then point `~/.claude/settings.json` at it —
    /// chaining to whatever statusLine was there before (saved to disk so removal can restore it verbatim).
    func installStatusLine() throws {
        ensureDirectories(for: .claude)
        guard let src = Bundle.main.url(forResource: "xfinder-claude-statusline", withExtension: "sh") else {
            throw StatusLineError.bundleResourceMissing
        }
        let fm = FileManager.default
        let scriptURL = statusLineScriptURL
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try Data(contentsOf: src)
        try data.write(to: scriptURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let settings: [String: Any]
        switch readClaudeSettings() {
        case .success(let s): settings = s
        case .failure: throw StatusLineError.settingsUnreadable
        }
        try backupClaudeSettings()

        let install = ClaudeStatusLine.installing(settings, scriptPath: scriptURL.path)

        // Only write the saved-previous files when this install actually captured a previous value (i.e. we were
        // not already installed) — leaving an existing save alone if we were already ours.
        if let previous = install.previous {
            let json = try ClaudeStatusLine.encodePrevious(previous)
            try json.write(to: statusLinePreviousJSONURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: statusLinePreviousJSONURL.path)

            let cmdURL = statusLinePreviousCommandURL
            if let previousCommand = install.previousCommand {
                try previousCommand.write(to: cmdURL, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cmdURL.path)
            } else {
                try? fm.removeItem(at: cmdURL)
            }
        }

        try writeClaudeSettings(install.settings)
    }

    /// Undo the install: only when `statusLine` currently points at XFinder's script. Restores the saved
    /// previous value verbatim (or deletes the key when there was none), then deletes the script and the saved
    /// previous-value files and the rate-limit cache.
    func removeStatusLine() throws {
        let settings: [String: Any]
        switch readClaudeSettings() {
        case .success(let s): settings = s
        case .failure: throw StatusLineError.settingsUnreadable
        }
        guard ClaudeStatusLine.isOurs(settings["statusLine"], scriptPath: statusLineScriptURL.path) else {
            throw StatusLineError.pointsAtAnotherCommand
        }

        // No save ⇒ there was no statusLine before us ⇒ the key is deleted. A save that cannot be read ⇒ refuse.
        var previous: Any?
        if FileManager.default.fileExists(atPath: statusLinePreviousJSONURL.path) {
            guard let data = try? Data(contentsOf: statusLinePreviousJSONURL),
                  let value = ClaudeStatusLine.decodePrevious(data) else { throw StatusLineError.previousUnreadable }
            previous = value
        }

        try backupClaudeSettings()
        try writeClaudeSettings(ClaudeStatusLine.removing(settings, scriptPath: statusLineScriptURL.path, previous: previous))

        let fm = FileManager.default
        try? fm.removeItem(at: statusLineScriptURL)
        try? fm.removeItem(at: statusLinePreviousJSONURL)
        try? fm.removeItem(at: statusLinePreviousCommandURL)
        try? fm.removeItem(at: statusLineCacheURL)
    }
}

/// One agent's events folder, tailed: a directory source (a new day file appears) plus a source on today's file
/// (appends do not change the directory, so a directory watch alone would miss every event after the first).
/// Reads only complete lines, from the last offset, of today's and yesterday's files (a session straddling
/// midnight keeps its history). Kernel-side sources, no polling.
@MainActor
private final class EventTail {
    let agent: AgentKind
    let eventsDir: URL
    var onChange: (() -> Void)?
    private(set) var events: [AgentEvents.Event] = []
    private var offsets: [String: UInt64] = [:]
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var watchedFile: URL?

    init(agent: AgentKind, eventsDir: URL) {
        self.agent = agent
        self.eventsDir = eventsDir
    }

    func watch() {
        dirSource?.cancel()
        let fd = open(eventsDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {       // queue: .main ⇒ the main thread; a documented contract, not a guess
                self?.watchTodayFile()
                self?.onChange?()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        dirSource = src
        watchTodayFile()
    }

    func cancel() {
        dirSource?.cancel(); dirSource = nil
        fileSource?.cancel(); fileSource = nil; watchedFile = nil
        offsets = [:]; events = []
    }

    /// (Re)attach the file watch to today's file when it appears or the day rolls over.
    private func watchTodayFile() {
        let today = eventsDir.appendingPathComponent(AgentEvents.eventsFileName(for: Date()))
        guard today != watchedFile || fileSource == nil else { return }
        fileSource?.cancel(); fileSource = nil; watchedFile = nil
        let fd = open(today.path, O_EVTONLY)
        guard fd >= 0 else { return }                       // not written yet; the directory watch retries
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.onChange?() } }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileSource = src
        watchedFile = today
    }

    func reload(full: Bool) {
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
            if !consumed.isEmpty {
                // The folder decides the agent: a line written by a pre-P5 Claude hook carries no `agent` field.
                let parsed = AgentEvents.parse(jsonl: String(decoding: consumed, as: UTF8.self)).map { e -> AgentEvents.Event in
                    var e = e; e.agent = agent; return e
                }
                events.append(contentsOf: parsed)
            }
        }
        if events.count > 20_000 { events.removeFirst(events.count - 20_000) }
    }
}
