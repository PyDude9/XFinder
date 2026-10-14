import Foundation

/// P5 (2026-10-14) — which coding agent a session belongs to. Pure (symlinked into the test package).
///
/// Claude Code and Codex both run a command hook per event, with the SAME stdin fields (`session_id`, `cwd`,
/// `hook_event_name`, `tool_name`, `tool_input`…) and the SAME PermissionRequest output
/// (`hookSpecificOutput.decision.behavior`) — measured against both tools' docs — so one hook script serves both,
/// told which agent it runs for by its first argument. OpenCode has no command hooks; it is read through its own
/// CLI (`opencode api …`, see `OpenCodeBridge`).
enum AgentKind: String, CaseIterable, Codable, Sendable {
    case claude, codex, opencode

    /// Product names — identical in both languages (allowlisted), so callers show them unwrapped.
    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    /// How the agent is recognised at a glance — a coloured tile with a glyph, the way OneNotch and Notch Crew show it
    /// (measured 2026-10-14: OneNotch keys each provider to its own symbol + tint, Claude (0.85, 0.47, 0.26); Notch Crew
    /// shows an orange tile for Claude and a white tile with a square-in-square for OpenCode). XFinder draws its own tile
    /// from SF Symbols — no logo artwork is copied from either app.
    struct Brand: Equatable, Sendable {
        var glyph: String           // SF Symbol name (checked to exist by a test)
        var tile: (Double, Double, Double)
        var glyphIsDark: Bool        // dark glyph on a light tile
        static func == (a: Brand, b: Brand) -> Bool {
            a.glyph == b.glyph && a.tile == b.tile && a.glyphIsDark == b.glyphIsDark
        }
    }

    var brand: Brand {
        switch self {
        case .claude: return Brand(glyph: "asterisk", tile: (0.85, 0.47, 0.26), glyphIsDark: false)
        case .codex: return Brand(glyph: "hexagon", tile: (0.93, 0.93, 0.94), glyphIsDark: true)
        case .opencode: return Brand(glyph: "square.inset.filled", tile: (0.93, 0.93, 0.94), glyphIsDark: true)
        }
    }

    /// Agents that run XFinder's hook script (the others are read some other way).
    var usesHookScript: Bool { self != .opencode }

    /// The executable names the hook walks up its parent chain looking for. The agent process — not the shell it
    /// may have used to start the hook — is what liveness is measured on (a `sh -c` exits with the hook).
    var processNames: Set<String> {
        switch self {
        case .claude: return ["claude"]
        case .codex: return ["codex"]
        case .opencode: return ["opencode"]
        }
    }

    /// The shell command that reopens a session where it ran: `cd '<dir>' && claude --resume '<id>'`. Single-quoted
    /// so a space or a quote in a folder name survives a paste into any POSIX shell. Flags measured from each CLI's
    /// `--help` on 2026-10-14: `claude --resume <id>`, `codex resume <id>`, `opencode --session <id>`.
    func resumeCommand(sessionID: String, cwd: String?) -> String {
        let id = Self.shellQuoted(sessionID)
        let run: String
        switch self {
        case .claude: run = "claude --resume \(id)"
        case .codex: run = "codex resume \(id)"
        case .opencode: run = "opencode --session \(id)"
        }
        guard let cwd, !cwd.isEmpty else { return run }
        return "cd \(Self.shellQuoted(cwd)) && \(run)"
    }

    static func shellQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
