#!/bin/sh
# XF-T23 Crew v2b — end-to-end on REAL processes: a temporary git repository, a stand-in `claude` (fake-claude.py) for every
# role, and the PRODUCTION CrewManager / CrewRules / CrewGate / CrewGit / WindowlessSessionManager and the shipped
# xfinder-crew.zsh compiled together. It proves what the unit tests cannot: worktrees and branches per builder, per-member
# environment and --settings, the signed envelopes through the Approved -> merge gate, refusals, and a stop that never
# deletes uncommitted work. No model is called. Exit 0 only when every check passed.
#
# It uses the real ~/Library/Application Support/XFinder/Agents/crew (the manager's fixed root), and CrewManager removes
# stale crew folders at start — so it refuses to run while XFinder is open with crew folders present.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
CREWS="$HOME/Library/Application Support/XFinder/Agents/crew"
if pgrep -x XFinder >/dev/null 2>&1 && ls "$CREWS" 2>/dev/null | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-'; then
  echo "REFUSED: XFinder is running and has crew folders; quit it (or stop its crews) first." >&2; exit 2
fi
W=${XF_E2E_DIR:-$(mktemp -d /tmp/xf-crew-e2e.XXXXXX)}
mkdir -p "$W"
cp scripts/e2e-crew-v2/fake-claude.py "$W/fake-claude.py"; chmod +x "$W/fake-claude.py"
A=XFinder/Core/Agents
swiftc -O -o "$W/e2e" scripts/e2e-crew-v2/main.swift scripts/e2e-crew-v2/L10nStub.swift \
  $A/CrewManager.swift $A/CrewRules.swift $A/CrewGate.swift $A/CrewGit.swift \
  $A/WindowlessRules.swift $A/WindowlessSessionManager.swift $A/AgentEvents.swift $A/AgentKind.swift \
  $A/AgentRecent.swift $A/AgentUsage.swift $A/ClaudeStatusLine.swift $A/AgentQuotaRules.swift $A/CodexAppServer.swift 2>&1 \
  | grep -E "error:" && { echo "compile failed" >&2; exit 1; } || true
rm -rf "$W/repo" "$W/fake.log"
# XF_GUARD_BIN=<built XFinder binary> makes every builder run the real PreToolUse guard from its --settings (3 more checks).
"$W/e2e" "$W" "$ROOT/XFinder/Resources/Agents/xfinder-crew.zsh"
