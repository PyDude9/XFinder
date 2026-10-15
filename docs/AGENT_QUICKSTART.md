# XFinder — quickstart for any coding agent (Zed, OpenCode, Antigravity, Cursor, Codex…)

Read this first. **If the owner sent you here to do a task, the task list, the "small task" rubric, the forbidden files
and the exact procedure are in `docs/AGENT_TASKS.md` — follow that file.** This one is short on purpose; the full
history lives in `CLAUDE.md` (local, git-ignored, ~460 KB — grep it by section title, never load it whole) and in
`AGENTS.md` (a tracked snapshot from 2026-10-13, older than this file).

## What it is

A native macOS 14+ utility (Swift 6, SwiftUI + AppKit, **arm64 only**): a notch surface (clipboard, file tray, Now
Playing, AI-agent sessions, calendar, timer), a settings window with a sidebar, a clipboard manager, window snapping,
mouse gestures, local diagnostics. Vietnamese is the source language of every UI string.

## Commands (run from the repo root, absolute paths are safest)

| Purpose | Command | Notes |
|:--|:--|:--|
| Build + check | `sh scripts/build-and-check.sh` | builds to `/tmp/xfinder-clean-build/out`, checks named files really compiled, bundled resources, arm64. **Does not install.** |
| Unit tests | `swift test --package-path /Users/wolong/github/XFinder/Tests` | ~1190 tests, ~7 s. A Swift package that symlinks pure source files — a new pure file needs its symlink in `Tests/XFinderLogicTests/` |
| Install | `sh scripts/install-mouse-rebuild.sh` | installs the LAST build-and-check output, signs, relaunches XFinder. Run build-and-check first; compare the installed dylib hash with the build |
| L10n gates | `python3 scripts/check-l10n-coverage.py` · `check-l10n-duplicates.py` · `audit-l10n-literals.py` · `audit-l10n-interpolations.py` · `check-sidebar-groups-l10n.py` · `verify-l10n-runtime.py` | every one must print `TOTAL 0` |
| UI tokens | `python3 scripts/audit-ui-tokens.py` | `TOTAL 0` |
| Mutation harnesses | `scripts/mutation-check-*.sh` (18) | inject known bugs; every mutation must go RED. Run detached (`nohup sh … > log 2>&1 &`), **one at a time**, and never edit a source file while one runs (it restores from a backup taken at its start) |

## Hard rules (each one is a bug that shipped once)

1. **Honesty.** Never show a number, control or sentence that is not true. A feature that cannot work gets an
   explainer, not a dead switch. Claiming "no API exists" needs a probe, not a guess.
2. **Every user-facing string goes through `L10n.t("…")`** (Vietnamese literal as the key) with an entry in
   `XFinder/Resources/L10n.strings.json`. Add entries with an ADD-ONLY script like `scripts/add-analytics-l10n-entries.py`
   (refuses to rewrite an existing key). A string joined to a runtime value is `scope: "fragment"` and keeps its edge
   space; never put `\(value)` inside `L10n.t(…)` — split it: `"\(L10n.t("Đã nén "))\(n)\(L10n.t(" mục"))"`.
3. **One key, one control; defaults agree with their reader.** Before adding a switch, grep its UserDefaults key. The
   engine reads it once as `UserDefaults.standard.object(forKey: "k") as? Bool ?? x`; the view's `@AppStorage` default
   must equal `x` (`FeatureKeyDefaultsTests` enforces it — add a row there).
4. **`project.pbxproj` is hand-written: four entries per new file** (PBXBuildFile, PBXFileReference, group child,
   Sources phase). Lint with `plutil -lint XFinder.xcodeproj/project.pbxproj`. A missing entry silently drops the file.
5. **Swift 6 strict concurrency.** No `@unchecked Sendable`. A callback from AppKit/IOKit/CoreBluetooth may arrive off
   the main thread: hop with `runOnMainActor`/`Task { @MainActor … }`, never `MainActor.assumeIsolated` unless the
   thread is documented.
6. **No polling timers.** Idle CPU must stay ~0 %. Event-driven (monitors, notifications, DispatchSource); a timer only
   while a visible thing needs it. Every `addGlobalMonitorForEvents` needs a paired `addLocalMonitorForEvents`.
7. **Bring another app forward from a panel with `NSWorkspace.openApplication`, never `activate(options:)`** (ignored
   since macOS 14 when XFinder is not active).
8. **Write tests that can fail.** For pure logic: a test, then inject the bug (or run the harness) and watch it go red.
9. **Measure before claiming.** "It compiles" proves nothing about behaviour. Report build / tests / live behaviour
   separately, and say what was not verified.

## Shell traps on this Mac

- `ls`, `find`, `log` are aliases/functions: use `/bin/ls`, `/usr/bin/find`, `/usr/bin/log`.
- A `cd` inside a zsh `a && b` chain can die silently on a zoxide hook: use `/bin/sh -c 'cd … && …'` or absolute paths.
- zsh: write `${VAR}:x`, never `$VAR:x` (`:c`, `:q`… are modifiers).
- **Never launch `XFinder.app/Contents/MacOS/XFinder` directly from a shell** — TCC attributes its permission requests
  to the shell and can kill it. Launch with `open -a XFinder` (or `open -g`); pages: `open "xfinder://settings?page=<rawValue>"`.
  A custom URL scheme LAUNCHES the app — check `pgrep -x XFinder` first if the owner quit it.
- `defaults import` merges; it does not replace a domain.
- Scratch files go to `/tmp/…` or a scratchpad, **never the repo root**.

## Git

- Work on a branch: `git switch -c agent/<tool>-<topic>`. Stage **explicit paths** (`git add path/a path/b`), never
  `git add -A`/`git add -u` — the tree holds untracked files of the owner's that must not be committed
  (`assets_info.json`, `binary_strings.txt`, `strings/`, `.agents/`, `docs/*_2026-10.md` …).
- One topic per commit; the message states what was measured and what was not.
- **Do not push and do not commit on `main` unless the owner asks.** Do not commit someone else's uncommitted work.
- Leave a short note of what you did and what you could not verify in `docs/AGENT_WORKLOG.md` (append, newest first).

## Where things are

`XFinder/Core/` engines (pure rules are separate files with tests: `*Rules.swift`), `XFinder/Views/` SwiftUI,
`XFinder/Models/SidebarDestination.swift` the sidebar, `XFinder/Core/Notch/` the notch, `XFinder/Core/Agents/` agent
sessions (hooks, OpenCode, windowless, crew, handoff), `XFinder/Core/Diagnostics/` local log + anonymous analytics,
`Tests/XFinderLogicTests/` tests, `scripts/` gates, `docs/PENDING_TESTS_AND_DECISIONS.md` open questions (Q-…) and hand
tests (T-…).
