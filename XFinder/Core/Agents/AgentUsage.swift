import Foundation

/// §3b #37 — "how much of my AI allowance have I used?", from what the agents themselves write on this Mac.
///
/// Measured 2026-10-13 before writing a line:
/// * **Codex** writes its own rate limits into `~/.codex/sessions/**/*.jsonl` — a `rate_limits` object with `primary`
///   (`window_minutes` 300) and `secondary` (10 080 = a week), each with `used_percent` and `resets_at` (epoch s),
///   plus `plan_type`. 71 such records in 34 session files here. Many events carry `primary: null` — skip those.
/// * **Claude Code** writes NO allowance figure locally — only per-message token `usage` in
///   `~/.claude/projects/*/*.jsonl`. A percentage would need the login token from the Keychain and Anthropic's servers;
///   XFinder does not touch either, so for Claude it shows token counts and says they are not a percentage.
/// * The same assistant message is written as SEVERAL lines (one per content block) with the same usage: 5 882 lines
///   but 2 256 messages in a week here — summing lines would report 2.6× the real tokens. Lines are de-duplicated by
///   `message.id` + `requestId`, keeping the largest output count (a streamed message's last line).
enum AgentUsage {

    // MARK: Claude Code — tokens from transcripts

    struct ClaudeLine: Equatable {
        let key: String
        let time: Date
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheCreate: Int
    }

    /// One transcript line → a usage record, or nil (not an assistant message, no id, no timestamp, no usage).
    static func parseClaudeLine(_ line: String) -> ClaudeLine? {
        guard line.contains("\"usage\""), line.contains("\"assistant\""),
              let data = line.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              d["type"] as? String == "assistant",
              let msg = d["message"] as? [String: Any], let id = msg["id"] as? String,
              let usage = msg["usage"] as? [String: Any],
              let ts = d["timestamp"] as? String, let time = parseISO(ts) else { return nil }
        let rid = d["requestId"] as? String ?? ""
        func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
        return ClaudeLine(key: "\(id)|\(rid)", time: time, input: n("input_tokens"), output: n("output_tokens"),
                          cacheRead: n("cache_read_input_tokens"), cacheCreate: n("cache_creation_input_tokens"))
    }

    struct Totals: Equatable {
        var messages = 0
        var output = 0
        /// Fresh input: prompt tokens plus cache WRITES. Cache reads are not counted — they dwarf everything (652 M in
        /// five hours here) and say nothing about how much was asked.
        var input = 0
    }

    /// De-duplicate by message, then sum the ones at or after `since`.
    static func totals(_ lines: [ClaudeLine], since: Date) -> Totals {
        var best: [String: ClaudeLine] = [:]
        for l in lines {
            if let cur = best[l.key], cur.output >= l.output { continue }
            best[l.key] = l
        }
        var t = Totals()
        for l in best.values where l.time >= since {
            t.messages += 1
            t.output += l.output
            t.input += l.input + l.cacheCreate
        }
        return t
    }

    // MARK: Codex — its own rate limits

    struct CodexWindow: Equatable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Date
    }

    struct CodexLimits: Equatable {
        let observedAt: Date
        let primary: CodexWindow?
        let secondary: CodexWindow?
        let plan: String?
    }

    /// One session line → limits, only when it carries a real `primary` or `secondary` window.
    static func parseCodexLine(_ line: String) -> CodexLimits? {
        guard line.contains("rate_limits"), let data = line.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = findRateLimits(d) else { return nil }
        let p = window(rl["primary"]), s = window(rl["secondary"])
        guard p != nil || s != nil else { return nil }
        let at = (d["timestamp"] as? String).flatMap(parseISO) ?? .distantPast
        return CodexLimits(observedAt: at, primary: p, secondary: s, plan: rl["plan_type"] as? String)
    }

    /// The newest record wins.
    static func latest(_ records: [CodexLimits]) -> CodexLimits? { records.max { $0.observedAt < $1.observedAt } }

    /// A window whose reset time has passed says nothing about now: the next Codex message will report the new figure.
    static func isCurrent(_ w: CodexWindow, now: Date) -> Bool { w.resetsAt > now }

    // MARK: Codex — token usage (for a "Hôm nay" / 7-day total, the same job Claude's `Totals` does)

    /// One `token_count` event's CUMULATIVE totals for its session (`payload.info.total_token_usage`), at a point in time.
    struct CodexTokenPoint: Equatable {
        let time: Date
        /// Fresh input, matching Claude's `Totals.input` sense: "prompt + cache writes, cache READS not counted".
        /// Measured 2026-10-13 across 137 `token_count` events in the 8 newest session files on this Mac:
        /// `cached_input_tokens <= input_tokens` held in every one (it is a SUBSET of `input_tokens`, not an addition),
        /// so the fresh share is `input_tokens - cached_input_tokens`. `cache_write_input_tokens` was 0 in all 274
        /// events sampled — never observed non-zero here — but the field exists in the schema, and nothing in the
        /// 137-event sample proves it is already folded into `input_tokens` the way a cache WRITE normally would be
        /// billed as fresh input elsewhere; so it is added on top, the same shape as Claude's `input + cache_creation`.
        /// If it is ever observed non-zero and double-counted, that is a future measurement, not a guess made now.
        let input: Int
        let output: Int
    }

    /// Cheap pre-check (avoid parsing JSON for every line) + the real parse. `time` comes from the EVENT's own
    /// top-level `timestamp`, not the file's mtime — a session file is written to over its whole lifetime.
    static func parseCodexTokens(_ line: String) -> CodexTokenPoint? {
        guard line.contains("\"token_count\""), let data = line.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = d["timestamp"] as? String, let time = parseISO(ts),
              let payload = d["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else { return nil }
        func n(_ k: String) -> Int { (total[k] as? NSNumber)?.intValue ?? 0 }
        let fresh = max(0, n("input_tokens") - n("cached_input_tokens")) + n("cache_write_input_tokens")
        return CodexTokenPoint(time: time, input: fresh, output: n("output_tokens"))
    }

    /// Per session, the cumulative figure is a running total — so the amount used SINCE `since` is the last point
    /// at/after `since` MINUS the last point strictly before it (0 if the session has no such earlier point, i.e. it
    /// started inside the window). Summed across sessions. Because each point already holds the session's full
    /// cumulative total, re-reading the same event twice (the measured duplicate-event case) changes nothing: the
    /// "last point at/after since" is still the same point, so a repeat cannot inflate the difference.
    static func codexWindowTotals(_ sessions: [[CodexTokenPoint]], since: Date) -> Totals {
        var t = Totals()
        for points in sessions {
            let sorted = points.sorted { $0.time < $1.time }
            guard let lastAtOrAfter = sorted.last(where: { $0.time >= since }) else { continue }
            let baseline = sorted.last(where: { $0.time < since })
            let messages = sorted.filter { $0.time >= since }.count
            t.messages += messages
            t.input += max(0, lastAtOrAfter.input - (baseline?.input ?? 0))
            t.output += max(0, lastAtOrAfter.output - (baseline?.output ?? 0))
        }
        return t
    }

    // MARK: Formatting (glyph-free numbers; the view adds the words)

    /// 1 536 991 → "1.5M", 3 447 → "3.4K", 812 → "812". Decimal separator per caller.
    static func compact(_ n: Int, decimalComma: Bool) -> String {
        func one(_ v: Double, _ suffix: String) -> String {
            let s = String(format: "%.1f", v)
            let trimmed = s.hasSuffix(".0") ? String(s.dropLast(2)) : s
            return (decimalComma ? trimmed.replacingOccurrences(of: ".", with: ",") : trimmed) + suffix
        }
        switch n {
        case 1_000_000_000...: return one(Double(n) / 1e9, "B")
        case 1_000_000...: return one(Double(n) / 1e6, "M")
        case 1_000...: return one(Double(n) / 1e3, "K")
        default: return "\(max(0, n))"
        }
    }

    // MARK: helpers

    private static func window(_ any: Any?) -> CodexWindow? {
        guard let w = any as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue,
              let mins = (w["window_minutes"] as? NSNumber)?.intValue,
              let reset = (w["resets_at"] as? NSNumber)?.doubleValue else { return nil }
        return CodexWindow(usedPercent: min(100, max(0, used)), windowMinutes: mins, resetsAt: Date(timeIntervalSince1970: reset))
    }

    private static func findRateLimits(_ o: Any) -> [String: Any]? {
        if let d = o as? [String: Any] {
            if let r = d["rate_limits"] as? [String: Any] { return r }
            for v in d.values { if let r = findRateLimits(v) { return r } }
        } else if let a = o as? [Any] {
            for v in a { if let r = findRateLimits(v) { return r } }
        }
        return nil
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
