import Foundation

/// P5c (2026-10-14) — "tell me when a session needs me, so I do not have to watch it". Pure (symlinked into the test
/// package): which session transitions are worth a notice at the notch, and what the notice says.
///
/// Two transitions only, each behind its own switch:
/// * a session starts waiting for a permission (a NEW request — the same request is announced once);
/// * a session that was running is now waiting for the person (its turn finished).
/// The first snapshot after the monitor starts is a baseline: launching XFinder announces nothing.
/// Ended sessions, sessions appearing already idle, and tool-to-tool changes inside a turn say nothing.
enum AgentNotify {

    struct Settings: Equatable, Sendable {
        var permission: Bool
        var finished: Bool
    }

    enum Event: Equatable {
        case needsApproval(AgentSession, AgentSession.PendingPermission)
        case finished(AgentSession)
    }

    /// The person is already looking at this session: the app it runs in (kitty, Terminal, the Claude desktop app —
    /// the bundle id the hook recorded) is frontmost. OneNotch stays quiet then ("Skip the popup when you're already
    /// looking at the session", "Stay quiet while the terminal is in front" — measured 2026-10-14). A session with no
    /// recorded app (OpenCode via its API, a windowless one) is never "watched": its notice still comes.
    static func isWatched(_ s: AgentSession, frontmostBundleID: String?) -> Bool {
        guard let mine = s.terminal.bundleID, !mine.isEmpty, let front = frontmostBundleID, !front.isEmpty else { return false }
        return mine.caseInsensitiveCompare(front) == .orderedSame
    }

    static func session(of e: Event) -> AgentSession {
        switch e { case .needsApproval(let s, _), .finished(let s): return s }
    }

    static func events(old: [AgentSession]?, new: [AgentSession], settings: Settings) -> [Event] {
        guard let old else { return [] }
        let prior = Dictionary(old.map { ($0.listID, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [Event] = []
        for s in new {
            let before = prior[s.listID]
            switch s.status {
            case .waitingForPermission(let p):
                guard settings.permission else { continue }
                if case .waitingForPermission(let q)? = before?.status, q.requestID == p.requestID { continue }
                out.append(.needsApproval(s, p))
            case .waitingForInput:
                guard settings.finished, let before, case .running = before.status else { continue }
                out.append(.finished(s))
            case .running, .ended:
                continue
            }
        }
        return out
    }

    /// The notice. Detail = agent · session name [· tool]; the store keys are wrapped by the view.
    static func item(for event: Event) -> LiveActivity.Item {
        switch event {
        case .needsApproval(let s, let p):
            var detail = "\(s.agent.displayName) · \(s.displayName) · \(p.toolName)"
            if detail.count > 90 { detail = String(detail.prefix(90)) + "…" }
            return LiveActivity.Item(kind: .agent, symbol: "hand.raised.fill", titleKey: "Cần bạn duyệt",
                                     detail: detail, tint: .warning, duration: 8, buttons: [.openAgents])
        case .finished(let s):
            return LiveActivity.Item(kind: .agent, symbol: "checkmark.circle.fill", titleKey: "Tới lượt bạn",
                                     detail: "\(s.agent.displayName) · \(s.displayName)", tint: .good, duration: 4,
                                     buttons: [.openAgents])
        }
    }
}
