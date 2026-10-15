# XFinder — agents read this first

Native macOS 14+ utility (Swift 6, SwiftUI + AppKit, arm64 only). Claude Code is the main agent; other agents (OpenCode,
Zed, Antigravity, Cursor, Codex) work from a task board while Claude is out of quota.

1. **Rules and commands:** `docs/AGENT_QUICKSTART.md` (short, current). Read it before doing anything.
2. **What you may work on:** the Notion view **Queue — Ready** (claim handshake, Runs, roles: `docs/AGENT_NOTION.md`).
   **The exact procedure, rubric and forbidden files:** `docs/AGENT_TASKS.md`. One task per session, on your own
   branch `agent/<tool>-<ID>`. The spec is always a file in `docs/specs/` — never a Notion page.
3. **Log what you did and what you could not verify:** your Run in Notion (`docs/AGENT_NOTION.md` §4). Only when you
   cannot reach Notion: `docs/AGENT_WORKLOG.md` (newest first).
4. Long project history (2026-10-13 snapshot, ~150 KB): `docs/PROJECT_NOTES_2026-10-13.md`. Do not load it whole —
   grep it by section title when the quickstart sends you there.

Non-negotiable, even if a task seems to need it:

- Never `git push`, never commit on `main`, never `git add -A`/`-u` — stage explicit paths. The tree holds untracked files
  of the owner's (`assets_info.json`, `strings/`, `.agents/`, …) that must not be committed.
- Scratch files go to `/tmp/…`, never the repo root.
- Never launch `XFinder.app/Contents/MacOS/XFinder` from a shell; use `open -a XFinder`. A `xfinder://` URL launches the app.
- Every user-facing string goes through `L10n.t("…")` with an entry in `XFinder/Resources/L10n.strings.json`.
- Report build, tests and live behaviour separately; say what you did not verify.
