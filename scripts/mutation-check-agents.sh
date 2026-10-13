#!/bin/sh
# N3 — inject the agent-session rules' known failure modes one at a time; every one must turn the suite RED.
# Same harness rules as mutation-check-notch.sh: a missing anchor ABORTS (a mutation that cannot be injected is a
# broken gate), sources are restored byte-identical by an EXIT trap, the last step asserts the tree is green.
# Run detached and poll the log: `nohup sh scripts/mutation-check-agents.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-agents.XXXXXX)
FILES="XFinder/Core/Agents/AgentEvents.swift XFinder/Core/Agents/AgentHookInstaller.swift XFinder/Core/Agents/AgentUsage.swift XFinder/Core/Agents/ClaudeStatusLine.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM

FILTER='AgentSession|AgentUsage|ClaudeStatusLine|FeatureContract|FeatureCatalog'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} END {print (f==""?"NORESULT":f)}'
}

mutate() {
  python3 - "$1" "$2" "$3" <<'PY' || { echo "HARNESS ERROR: anchor not found in $1"; exit 2; }
import sys, ast
path, old, new = sys.argv[1], ast.literal_eval(sys.argv[2]), ast.literal_eval(sys.argv[3])
s = open(path).read()
if s.count(old) != 1: sys.exit(1)
open(path, "w").write(s.replace(old, new, 1))
PY
}

base=$(fails); echo "baseline failures: $base"
[ "$base" = "0" ] || { echo "FAIL: baseline is not green"; exit 1; }

red=0; total=0
run() {
  # A target outside FILES is never restored (P1, the notch script's M40). Refuse it.
  case " $FILES " in *" $2 "*) ;; *) echo "HARNESS ERROR: $2 is not in FILES (it would never be restored)"; exit 2;; esac
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}

run "A1 a dead claude process does not end the session" XFinder/Core/Agents/AgentEvents.swift \
  "'                if let pid = s.agentPID, !isAlive(pid) { s.status = .ended }'" \
  "'                if let pid = s.agentPID, !isAlive(pid), Bool(\"false\") == true { s.status = .ended }'"
run "A2 an answered permission request keeps waiting" XFinder/Core/Agents/AgentEvents.swift \
  "'                if answered.contains(rid) { s.status = .running(tool: e.toolName) }\n                else {'" "'                do {'"
run "A3 a tool starting leaves the permission card up" XFinder/Core/Agents/AgentEvents.swift \
  "'                s.status = .running(tool: e.toolName)\n            case .postToolUse, .postToolUseFailure:'" \
  "'                if case .waitingForPermission = s.status {} else { s.status = .running(tool: e.toolName) }\n            case .postToolUse, .postToolUseFailure:'"
run "A4 display order forgets that permissions come first" XFinder/Core/Agents/AgentEvents.swift \
  "'            case .waitingForPermission: return 0\n            case .waitingForInput: return 1'" \
  "'            case .waitingForPermission: return 1\n            case .waitingForInput: return 1'"
run "A5 a silent pid-less session never goes stale" XFinder/Core/Agents/AgentEvents.swift \
  "'                else if s.agentPID == nil, now.timeIntervalSince(s.updatedAt) > staleAfter { s.status = .ended }\n'" "''"
run "A6 removing the hook also removes other tools' entries" XFinder/Core/Agents/AgentHookInstaller.swift \
  "'                let inner = (e[\"hooks\"] as? [[String: Any]] ?? []).filter { !isOurs(\$0, hookPath: hookPath) }'" \
  "'                let inner: [[String: Any]] = []'"
run "A7 merge appends a second copy on every run" XFinder/Core/Agents/AgentHookInstaller.swift \
  "'            if !contains(list, hookPath: hookPath) {'" "'            do {'"
run "A8 the decision JSON drifts from the documented shape" XFinder/Core/Agents/AgentHookInstaller.swift \
  "'        let decision: [String: Any] = [\"behavior\": allow ? \"allow\" : \"deny\"]'" \
  "'        let decision: [String: Any] = [\"permissionDecision\": allow ? \"allow\" : \"deny\"]'"
run "A9 a line without a session id still becomes an event" XFinder/Core/Agents/AgentEvents.swift \
  "'        guard !sessionID.isEmpty else { return nil }\n'" "''"
run "A10 PermissionRequest timeout shrinks to the default (the hook would be killed while waiting)" XFinder/Core/Agents/AgentHookInstaller.swift \
  "'        (\"PermissionRequest\", 3600), (\"PermissionDenied\", 10),'" "'        (\"PermissionRequest\", 10), (\"PermissionDenied\", 10),'"

U=XFinder/Core/Agents/AgentUsage.swift
run "A11 repeated lines of one message are summed (2.6x the real tokens)" $U \
  "'            if let cur = best[l.key], cur.output >= l.output { continue }'" "'            if false, let cur = best[l.key], cur.output >= l.output { continue }; best[UUID().uuidString] = l; continue'"
run "A12 cache reads counted as input" $U \
  "'            t.input += l.input + l.cacheCreate'" "'            t.input += l.input + l.cacheCreate + l.cacheRead'"
run "A13 a Codex event with null windows becomes a 0 % record" $U \
  "'        guard p != nil || s != nil else { return nil }'" "'        _ = 0'"
run "A14 a window past its reset still reads as current" $U \
  "'    static func isCurrent(_ w: CodexWindow, now: Date) -> Bool { w.resetsAt > now }'" "'    static func isCurrent(_ w: CodexWindow, now: Date) -> Bool { true }'"
# P2 — ClaudeStatusLine.swift (install rules + rate-limit cache parser). Numbered from A16: A12-A14 belong to AgentUsage.swift.
CSL=XFinder/Core/Agents/ClaudeStatusLine.swift
run "A16 previousCommand allowed to point back at us" $CSL \
  "'        if let existing, isOurs(existing, scriptPath: scriptPath) {'" \
  "'        if false, let existing, isOurs(existing, scriptPath: scriptPath) {'"
run "A17 removing() deletes the key even when not ours" $CSL \
  "'        guard isOurs(settings[\"statusLine\"], scriptPath: scriptPath) else { return settings }\n'" \
  "'        _ = isOurs(settings[\"statusLine\"], scriptPath: scriptPath)\n'"
run "A18 isCurrent ignores resetsAt" $CSL \
  "'        guard let resetsAt = w.resetsAt else { return true }\n        return resetsAt > now\n'" \
  "'        _ = w.resetsAt\n        return true\n'"
run "A19 installing() drops padding/refreshInterval" $CSL \
  "'        var newValue: [String: Any] = existing ?? [:]\n'" \
  "'        var newValue: [String: Any] = [:]\n'"
run "A20 a bare object is taken as a save (a hand-edited or foreign file would be restored as if it were ours)" $CSL \
  "'              obj.count == 1, let value = obj[\"statusLine\"] else { return nil }'" \
  "'              let value = obj[\"statusLine\"] ?? (obj as Any?) else { return nil }'"
run "A21 a non-object previous statusLine is dropped (Gỡ would delete it)" $CSL \
  "'        guard let existing else { return Install(settings: out, previous: raw, previousCommand: nil) }'" \
  "'        guard let existing else { return Install(settings: out, previous: nil, previousCommand: nil) }'"

# The restore check and the post-restore suite run come AFTER every mutation (they used to sit before A11, so the
# later mutations ran unchecked — found while adding A20/A21).
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
