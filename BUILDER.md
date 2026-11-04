# XFinder — BUILDER rules (read this, not the whole CLAUDE.md)

You are a **Builder**. You are a Builder in every Orca worktree. Only the session whose repo root is
`/Users/wolong/github/XFinder` (main checkout) or `/Users/wolong/github/XFinder-claude` is the **Boss**.
Check: `git rev-parse --show-toplevel`. If it is anything else, every "install / push / merge" rule you
read anywhere (CLAUDE.md §1 "Xong thì cài rồi push luôn", §5) is NOT for you.

## Your job, exactly
1. **One task, one session, one worktree, one branch.** Branch = `agent/<tool>-<TASK-ID>`
   (e.g. `agent/opencode-XF-T34`). `<tool>` = the tool actually running you (claude, codex, opencode,
   antigravity, gemini, cursor, zed). If the branch name is wrong, STOP and tell the owner.
2. **No spec, no code.** The spec is a file in `docs/specs/`. Read it; do not edit it.
3. Stay inside the files the spec names. Forbidden files: `docs/AGENT_TASKS.md` §2 (Info.plist,
   entitlements, install/release scripts, `~/.claude`/`~/.codex` writers, DatabaseService schema,
   Diagnostics, file-deleting engines, changing a UserDefaults default).
4. Before coding, write the failure cases (`docs/AGENT_QUICKSTART.md` rule 11) in your report.

## Build and check (your own output dir — never the shared /tmp/xfinder-clean-build)
```sh
export XF_ROOT="$(git rev-parse --show-toplevel)"
export XF_OUT="/tmp/xf-$(basename "$XF_ROOT")"
sh scripts/gate-all.sh            # must end with: GATE: green
```
Mutation harness only if the spec names it: detached, one at a time, no edits while it runs.

## Never (each one has happened)
- **Never install** (`install-mouse-rebuild.sh`), never launch or relaunch XFinder, never send
  keys/clicks to the owner's apps. Installing on the owner's machine is the Boss's job, after review.
- Never `git push`, merge, rebase, amend, commit on `main`, or `git add -A`/`-u`. Stage explicit paths.
- Never put scratch files in the repo root (`a.c`, `prog1`, probes…) — use `/tmp/xf-<you>/`.
- Never start timers/sleep loops to "check later". Wait for the command to finish, then report.
- Never start a second task in this session. Research tasks do not run in a build worktree.

## Report (paste at the end, and in your Notion Run / docs/AGENT_WORKLOG.md)
```
TASK: <ID>   BRANCH: <branch>   COMMITS: <hash list>
BUILD: <last line>   TESTS: <n tests / n failures>   GATE: <green|RED + line>
MUTATION: <n/n RED | not run>   LIVE: NOT VERIFIED (Builder does not install)
FILES CHANGED: <paths>
NOT VERIFIED: <list>
QUESTIONS (Q-*): <list or none>
```
CLAUDE.md §7 "live state" in a worktree is a stale copy — trust `git log` and the spec, not §7.
