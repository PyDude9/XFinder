import Foundation

/// §3b #37 — the live half of the usage strip on the notch Agents page. Reads only what the agents write on this Mac
/// (`AgentUsage` explains what each file holds and why Claude Code gets tokens, not a percentage). Nothing runs unless
/// the Agents page is on screen: a scan when it appears, then one every 60 s while it stays, off the main actor; each scan reads only
/// what the files gained since the last (`UsageLogReader`).
@MainActor
@Observable
final class AgentUsageMonitor {
    static let shared = AgentUsageMonitor()
    private init() {}

    struct Snapshot: Equatable, Sendable {
        var claude5h = AgentUsage.Totals()
        var claude7d = AgentUsage.Totals()
        var claudeToday = AgentUsage.Totals()
        var claudeQuota: ClaudeStatusLine.Quota?
        var statusLineInstalled = false
        var codex: AgentUsage.CodexLimits?
        var codexToday = AgentUsage.Totals()
        var codex7d = AgentUsage.Totals()
        var scannedAt: Date?
    }

    private(set) var snapshot = Snapshot()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var scanning = false

    /// The Agents page came on screen / went away.
    func setPageOpen(_ open: Bool) {
        if open {
            guard timer == nil else { return }
            refresh()
            let t = Timer(timeInterval: 60, repeats: true) { _ in Task { @MainActor in AgentUsageMonitor.shared.refresh() } }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate(); timer = nil
        }
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        let now = Date()
        Task.detached(priority: .utility) {
            let snap = await UsageLogReader.shared.scan(now: now)
            await MainActor.run {
                let s = AgentUsageMonitor.shared
                s.scanning = false
                if snap != s.snapshot { s.snapshot = snap }
            }
        }
    }
}

/// The usage scan, keeping what it has already read: per file, where it stopped and what it parsed. A scan reads only the
/// bytes appended since the previous one, 4 MB at a time, and turns only lines carrying the marker into Strings.
actor UsageLogReader {
    static let shared = UsageLogReader()

    private struct ClaudeFile { var tail = AgentUsage.LogTail(); var lines: [AgentUsage.ClaudeLine] = [] }
    private struct CodexFile { var tail = AgentUsage.LogTail(); var limits: AgentUsage.CodexLimits?; var points: [AgentUsage.CodexTokenPoint] = [] }
    private var claude: [URL: ClaudeFile] = [:]
    private var codex: [URL: CodexFile] = [:]
    private static let chunk = 4 << 20

    /// New complete lines of `url` since `tail`, read in chunks; nil when the file cannot be opened.
    private static func newLines(_ url: URL, tail: inout AgentUsage.LogTail) -> [Data]? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) } ?? 0
        if AgentUsage.mustRestart(tail, fileSize: size) { tail = AgentUsage.LogTail() }
        guard size > tail.offset else { return [] }
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        do { try h.seek(toOffset: tail.offset) } catch { return nil }
        var out: [Data] = []
        while let data = try? h.read(upToCount: chunk), !data.isEmpty {
            out += AgentUsage.lines(in: data, tail: &tail)
        }
        return out
    }

    private static func recent(_ urls: [URL], now: Date) -> [URL] {
        urls.filter { f in
            f.pathExtension == "jsonl"
                && (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    .map { now.timeIntervalSince($0) < 7 * 86_400 } == true
        }
    }

    func scan(now: Date) -> AgentUsageMonitor.Snapshot {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let weekAgo = now.addingTimeInterval(-7 * 86_400)

        let projects = home.appendingPathComponent(".claude/projects")
        var claudeFiles: [URL] = []
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            claudeFiles += Self.recent((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [], now: now)
        }
        claude = claude.filter { claudeFiles.contains($0.key) }        // files that left the week are forgotten
        var lines: [AgentUsage.ClaudeLine] = []
        for f in claudeFiles {
            var entry = claude[f] ?? ClaudeFile()
            for l in Self.newLines(f, tail: &entry.tail) ?? [] where AgentUsage.contains(l, "\"usage\"") {
                if let u = AgentUsage.parseClaudeLine(String(decoding: l, as: UTF8.self)) { entry.lines.append(u) }
            }
            entry.lines.removeAll { $0.time < weekAgo }
            claude[f] = entry
            lines += entry.lines
        }
        var snap = AgentUsageMonitor.Snapshot(claude5h: AgentUsage.totals(lines, since: now.addingTimeInterval(-5 * 3600)),
                                              claude7d: AgentUsage.totals(lines, since: weekAgo),
                                              claudeToday: AgentUsage.totals(lines, since: Calendar.current.startOfDay(for: now)),
                                              codex: nil, scannedAt: now)

        // Codex: every session file modified within 7 days, for the newest rate-limit window and the token totals.
        var codexFiles: [URL] = []
        if let e = fm.enumerator(at: home.appendingPathComponent(".codex/sessions"), includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let f as URL in e { codexFiles.append(f) }
        }
        codexFiles = Self.recent(codexFiles, now: now)
        codex = codex.filter { codexFiles.contains($0.key) }
        var limits: [AgentUsage.CodexLimits] = []
        var sessions: [[AgentUsage.CodexTokenPoint]] = []
        for f in codexFiles {
            var entry = codex[f] ?? CodexFile()
            for l in Self.newLines(f, tail: &entry.tail) ?? [] {
                if AgentUsage.contains(l, "rate_limits"), let r = AgentUsage.parseCodexLine(String(decoding: l, as: UTF8.self)) {
                    entry.limits = AgentUsage.latest([entry.limits, r].compactMap { $0 })
                }
                if AgentUsage.contains(l, "\"token_count\""), let p = AgentUsage.parseCodexTokens(String(decoding: l, as: UTF8.self)) {
                    entry.points.append(p)
                }
            }
            codex[f] = entry
            if let lim = entry.limits { limits.append(lim) }
            if !entry.points.isEmpty { sessions.append(entry.points) }
        }
        snap.codex = AgentUsage.latest(limits)
        snap.codexToday = AgentUsage.codexWindowTotals(sessions, since: Calendar.current.startOfDay(for: now))
        snap.codex7d = AgentUsage.codexWindowTotals(sessions, since: weekAgo)

        // Claude's statusLine cache: whatever the shell script last wrote, captured when the file was written.
        let cacheURL = ClaudeStatusLine.cacheURL(home: home)
        if let data = try? Data(contentsOf: cacheURL),
           let capturedAt = (try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
            snap.claudeQuota = ClaudeStatusLine.parseQuota(data, capturedAt: capturedAt)
        }

        // settings.json's statusLine: read ONLY that one value, never the rest of the file (it can hold env vars).
        let settingsURL = home.appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: settingsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            snap.statusLineInstalled = ClaudeStatusLine.isOurs(obj["statusLine"], scriptPath: ClaudeStatusLine.scriptURL(home: home).path)
        }
        return snap
    }
}
