import Foundation

/// P12.1 (2026-10-14) — "an agent stopped at its usage limit: which other agent can take the work?" Pure (symlinked into
/// the test package). Two questions only, answered from what XFinder already reads, never from a guess:
///
/// * **Did this turn stop at a limit?** Claude Code's `StopFailure` hook (it runs INSTEAD of `Stop` when a turn ends on an
///   API error) carries `error: "rate_limit"`; Codex's app-server ends the turn `failed` with
///   `codexErrorInfo: "usageLimitExceeded"`. A retried 429 (`system/api_retry`) never reaches either — the turn went on.
///   Codex's separate `rateLimitExceeded` is NOT treated as a stop (Q-P12-2): the schema keeps the two apart.
/// * **How much room does each agent have?** Claude's % comes only from XFinder's statusLine cache, Codex's from its own
///   session logs; a window past its reset says nothing; OpenCode has no figure at all. So each agent is `available`,
///   `exhausted` or `unknown` — and the figures are never compared ACROSS agents (a Claude 5-hour % and a Codex weekly %
///   are different windows), only used to rule an agent out or to prefer one whose room is known.
enum AgentQuotaRules {

    enum Headroom: Equatable, Sendable {
        /// Every current window is below 100 %; `usedPercent` is the fullest one.
        case available(usedPercent: Double)
        /// A current window is at 100 %.
        case exhausted
        /// No figure, or none still current.
        case unknown
    }

    /// The `StopFailure` error type that means "this turn stopped at a usage limit".
    static func isLimitStop(claudeError: String?) -> Bool { claudeError == "rate_limit" }

    /// The Codex `codexErrorInfo` value that means the same.
    static func isLimitStop(codexCode: String?) -> Bool { codexCode == "usageLimitExceeded" }

    /// A usage snapshot older than this is not trusted to rule an agent in or out: it only refreshes while the Agents
    /// page is open, and a figure from an hour ago may be at 100 % by now.
    static let freshFor: TimeInterval = 10 * 60

    static func classify(_ used: [Double]) -> Headroom {
        guard let fullest = used.max() else { return .unknown }
        return fullest >= 100 ? .exhausted : .available(usedPercent: fullest)
    }

    /// Claude: only from the statusLine cache (`rate_limits` appears only for Pro/Max, after a reply, in a terminal session).
    static func claude(statusLineInstalled: Bool, quota: ClaudeStatusLine.Quota?, scannedAt: Date?, now: Date) -> Headroom {
        guard statusLineInstalled, let quota, let scannedAt, now.timeIntervalSince(scannedAt) <= freshFor else { return .unknown }
        let windows = [quota.fiveHour, quota.sevenDay].compactMap { $0 }.filter { ClaudeStatusLine.isCurrent($0, now: now) }
        return classify(windows.map(\.usedPercent))
    }

    /// Codex: its own `rate_limits` from the session logs.
    static func codex(_ limits: AgentUsage.CodexLimits?, scannedAt: Date?, now: Date) -> Headroom {
        guard let limits, let scannedAt, now.timeIntervalSince(scannedAt) <= freshFor else { return .unknown }
        let windows = [limits.primary, limits.secondary].compactMap { $0 }.filter { AgentUsage.isCurrent($0, now: now) }
        return classify(windows.map(\.usedPercent))
    }

    /// The agent the handoff preview opens on: never the one that stopped, never one known to be exhausted, never one not
    /// installed; one with known room before one whose room is unknown; otherwise `AgentKind` order. nil ⇒ nothing to
    /// suggest (the notice then just opens the Agents page). The person still sees the preview and presses Send.
    static func suggestTarget(stopped: AgentKind, headroom: [AgentKind: Headroom], available: Set<AgentKind>) -> AgentKind? {
        let candidates = AgentKind.allCases.filter { $0 != stopped && available.contains($0) && headroom[$0] != .exhausted }
        if let known = candidates.first(where: { if case .available = headroom[$0] { return true }; return false }) { return known }
        return candidates.first
    }
}
