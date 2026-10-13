import Foundation

/// P5c (2026-10-14) — "Phiên gần đây": terminal sessions that are no longer live, to reopen where they ran. Pure
/// (symlinked into the test package): what is read from the head of each agent's own session file.
///
/// Measured on this Mac before writing it:
/// * Claude Code transcripts (`~/.claude/projects/<dir>/<session>.jsonl`): `cwd`, `sessionId` and `entrypoint` sit
///   together on an early line, always within the first ~250 KB (60 files sampled); `entrypoint` is `cli` for a
///   terminal session and `claude-desktop` for the desktop app (55 of the 60 newest). Only `cli` is listed — the job is
///   reopening a terminal session.
/// * Codex session files (`~/.codex/sessions/YYYY/MM/DD/rollout-…jsonl`): the first line is `session_meta` with
///   `payload.id`, `payload.cwd`, `payload.originator` (`codex-tui` for the terminal; `Codex Desktop` and
///   `codex_work_desktop` for the apps) and `payload.source` (`cli` / `vscode`).
/// Only those identifiers and the folder are taken; no message is read out of the files.
enum AgentRecent {

    struct Entry: Equatable, Identifiable, Sendable {
        var agent: AgentKind
        var sessionID: String
        var cwd: String?
        var updated: Date
        var title: String?
        var id: String { "\(agent.rawValue):\(sessionID)" }
        var displayName: String {
            if let title, !title.isEmpty { return title }
            guard let cwd, !cwd.isEmpty else { return String(sessionID.prefix(8)) }
            return (cwd as NSString).lastPathComponent
        }
        var resumeCommand: String { agent.resumeCommand(sessionID: sessionID, cwd: cwd) }
    }

    /// How much of a Claude transcript is read to find its identifiers (measured: within ~250 KB on every file).
    static let claudeHeadBytes = 320_000

    /// A Claude transcript's head → an entry, or nil unless it is an interactive TERMINAL session.
    static func claudeEntry(head: Data, fileStem: String, modified: Date) -> Entry? {
        let text = String(decoding: head, as: UTF8.self)
        guard let entry = field("entrypoint", in: text), entry == "cli",
              let cwd = field("cwd", in: text) else { return nil }
        let sid = field("sessionId", in: text) ?? fileStem
        guard isSafeID(sid) else { return nil }
        return Entry(agent: .claude, sessionID: sid, cwd: cwd, updated: modified, title: nil)
    }

    /// A Codex session file's first line → an entry, or nil unless the terminal client wrote it.
    static func codexEntry(firstLine: String, modified: Date) -> Entry? {
        guard let data = firstLine.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              obj["type"] as? String == "session_meta",
              let p = obj["payload"] as? [String: Any] else { return nil }
        let terminal = (p["originator"] as? String) == "codex-tui" || (p["source"] as? String) == "cli"
        guard terminal, let sid = (p["id"] as? String) ?? (p["session_id"] as? String), isSafeID(sid) else { return nil }
        return Entry(agent: .codex, sessionID: sid, cwd: p["cwd"] as? String, updated: modified, title: nil)
    }

    /// Newest first, live sessions left out (they are already on the list above), at most `limit`.
    static func merged(_ entries: [Entry], live: Set<String>, limit: Int) -> [Entry] {
        var seen = Set<String>()
        return entries.sorted { $0.updated > $1.updated }
            .filter { !live.contains($0.id) && seen.insert($0.id).inserted }
            .prefix(limit).map { $0 }
    }

    /// The first `"key":"value"` in raw JSONL text, JSON-unescaped. Used on transcript heads instead of parsing whole
    /// lines: the line that carries `cwd` can sit behind 200 KB of other lines.
    static func field(_ key: String, in text: String) -> String? {
        guard let r = text.range(of: "\"\(key)\":\"") else { return nil }
        var i = r.upperBound
        var raw = ""
        var escaped = false
        while i < text.endIndex {
            let ch = text[i]
            if escaped { raw.append("\\"); raw.append(ch); escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" { break }
            else { raw.append(ch) }
            i = text.index(after: i)
        }
        guard i < text.endIndex else { return nil }                       // unterminated ⇒ cut mid-value
        guard let data = "\"\(raw)\"".data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String else { return nil }
        return value
    }

    /// A session id that can go into a shell command: UUID-ish or OpenCode's `ses_…`.
    static func isSafeID(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 80 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
