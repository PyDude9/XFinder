import Foundation

/// §3b #37 — the live half of the usage strip on the notch Agents page. Reads only what the agents write on this Mac
/// (`AgentUsage` explains what each file holds and why Claude Code gets tokens, not a percentage). Nothing runs unless
/// the Agents page is on screen: a scan when it appears, then one every 60 s while it stays (measured: 171 MB of a
/// week's transcripts in ~0.3 s), off the main actor.
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
            let snap = Self.scan(now: now)
            await MainActor.run {
                let s = AgentUsageMonitor.shared
                s.scanning = false
                if snap != s.snapshot { s.snapshot = snap }
            }
        }
    }

    nonisolated static func scan(now: Date) -> Snapshot {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var lines: [AgentUsage.ClaudeLine] = []
        let projects = home.appendingPathComponent(".claude/projects")
        for dir in (try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for f in files where f.pathExtension == "jsonl" {
                guard let m = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      now.timeIntervalSince(m) < 7 * 86_400,
                      let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
                for l in text.split(separator: "\n") where l.contains("\"usage\"") {
                    if let u = AgentUsage.parseClaudeLine(String(l)) { lines.append(u) }
                }
            }
        }
        var snap = Snapshot(claude5h: AgentUsage.totals(lines, since: now.addingTimeInterval(-5 * 3600)),
                            claude7d: AgentUsage.totals(lines, since: now.addingTimeInterval(-7 * 86_400)),
                            claudeToday: AgentUsage.totals(lines, since: Calendar.current.startOfDay(for: now)),
                            codex: nil, scannedAt: now)

        // Codex: every session file modified within 7 days, both for the newest rate-limit window AND for the
        // token totals (today / 7 d). Newest-first so the limits search can stop at the first real window.
        var codexFiles: [(URL, Date)] = []
        if let e = fm.enumerator(at: home.appendingPathComponent(".codex/sessions"),
                                 includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let f as URL in e where f.pathExtension == "jsonl" {
                let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                guard now.timeIntervalSince(m) < 7 * 86_400 else { continue }
                codexFiles.append((f, m))
            }
        }
        codexFiles.sort { $0.1 > $1.1 }
        var codexSessions: [[AgentUsage.CodexTokenPoint]] = []
        for (f, _) in codexFiles {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            if snap.codex == nil {
                let recs = text.split(separator: "\n").filter { $0.contains("rate_limits") }.compactMap { AgentUsage.parseCodexLine(String($0)) }
                if let latest = AgentUsage.latest(recs) { snap.codex = latest }
            }
            let points = text.split(separator: "\n").compactMap { AgentUsage.parseCodexTokens(String($0)) }
            if !points.isEmpty { codexSessions.append(points) }
        }
        snap.codexToday = AgentUsage.codexWindowTotals(codexSessions, since: Calendar.current.startOfDay(for: now))
        snap.codex7d = AgentUsage.codexWindowTotals(codexSessions, since: now.addingTimeInterval(-7 * 86_400))

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
