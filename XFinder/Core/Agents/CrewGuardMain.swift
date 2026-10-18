import Foundation

/// XF-T23 Crew v2b — `XFinder --crew-guard`: the app binary as a Claude Code PreToolUse hook command, so the crew guard has
/// exactly one implementation (`CrewGuard.decide`, unit-tested). A crew member's `--settings` file points its PreToolUse hook
/// here for Bash and the file-edit tools; the hook's JSON arrives on stdin, `XFINDER_CREW_ROOT` (the member's own worktree)
/// in the environment, and the answer — "ask" for a state-changing command, "deny" for an edit outside the worktree, or
/// nothing — goes to stdout. Decided in `XFinderApp.init` before any scene or AppKit object exists, like `--mcp`; never returns.
///
/// Fails open on purpose: when this process cannot run, the hook command exits non-zero, which Claude Code treats as a
/// non-blocking error, and the member's normal manual-mode asking stays in force (spec §3.4).
enum CrewGuardMain {
    static func run() -> Never {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let root = ProcessInfo.processInfo.environment["XFINDER_CREW_ROOT"]
        if let decision = CrewGuard.decide(hookStdin: input, root: root, resolve: CrewGuard.realPath) {
            FileHandle.standardOutput.write(Data(CrewGuard.hookOutput(decision).utf8))
        }
        exit(0)
    }
}
