#!/bin/sh
# N3 — inject the agent-session rules' known failure modes one at a time; every one must turn the suite RED.
# Same harness rules as mutation-check-notch.sh: a missing anchor ABORTS (a mutation that cannot be injected is a
# broken gate), sources are restored byte-identical by an EXIT trap, the last step asserts the tree is green.
# Run detached and poll the log: `nohup sh scripts/mutation-check-agents.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-agents.XXXXXX)
FILES="XFinder/Core/Agents/AgentEvents.swift XFinder/Core/Agents/AgentHookInstaller.swift XFinder/Core/Agents/AgentUsage.swift XFinder/Core/Agents/ClaudeStatusLine.swift XFinder/Core/Agents/AgentKind.swift XFinder/Resources/Agents/xfinder-agent-hook.zsh XFinder/Core/Agents/OpenCodeRules.swift XFinder/Core/Agents/AgentNotify.swift XFinder/Core/Agents/AgentRecent.swift XFinder/Core/Agents/AgentTalk.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM

FILTER='AgentTalk|AgentSession|AgentCodex|OpenCodeRules|AgentNotifyRecent|AgentUsage|ClaudeStatusLine|FeatureContract|FeatureCatalog'
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
  "'        guard isSafeSessionID(sessionID) else { return nil }\n'" "''"
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

# P5a — Codex beside Claude Code (one hook script, events tagged by agent, Codex's hooks.json merged in place).
E=XFinder/Core/Agents/AgentEvents.swift
H=XFinder/Core/Agents/AgentHookInstaller.swift
Z=XFinder/Resources/Agents/xfinder-agent-hook.zsh
run "A22 our entry goes in FRONT of another tool's (Codex trust is per position: theirs would be skipped)" $H \
  "'            hooks[name] = list'" "'            hooks[name] = Array(list.reversed())'"
run "A23 Claude's command gains an argument (a hook installed by 1.3.0 no longer matches)" $H \
  "'        return agent == .claude ? quoted : quoted + \" \" + agent.rawValue'" "'        return quoted + \" \" + agent.rawValue'"
run "A24 sessions keyed by id alone (a Claude and a Codex session with one id merge)" $E \
  "r'            let key = \"\\(e.agent.rawValue):\\(e.sessionID)\"'" "'            let key = e.sessionID'"
run "A25 Codex SessionEnd timeout above its 3 s cap" $H \
  "'        (\"SessionStart\", 10), (\"SessionEnd\", 3), (\"UserPromptSubmit\", 10),'" "'        (\"SessionStart\", 10), (\"SessionEnd\", 10), (\"UserPromptSubmit\", 10),'"
run "A26 the hook keeps Codex's answer text in the log" $Z \
  "'del(.tool_response, .last_assistant_message)'" "'del(.tool_response)'"
run "A27 the parser ignores the line's agent" $E \
  "'        if let a = obj[\"agent\"] as? String { e.agent = AgentKind(rawValue: a) ?? .claude }'" "'        _ = obj[\"agent\"]'"
run "A28 a Codex interrupt reads as still running" $E \
  "'            case .stop, .interrupt:\n                s.status = .waitingForInput'" "'            case .stop, .interrupt:\n                s.status = e.name == .interrupt ? .running(tool: nil) : .waitingForInput'"
run "A29 XFinder's own approval hook counted as another tool's" $H \
  "'.filter { (\$0[\"command\"] as? String) != nil && !isOurs(\$0, hookPath: hookPath) }'" "'.filter { (\$0[\"command\"] as? String) != nil }'"
run "A30 a Codex hook with no codex ancestor records the shell's pid" $Z \
  "'if [ -z \"\$agent_pid\" ] && [ \"\$agent\" = \"claude\" ]; then'" "'if [ -z \"\$agent_pid\" ]; then'"

# P5b — OpenCode through its own CLI.
O=XFinder/Core/Agents/OpenCodeRules.swift
run "A31 Cho phép answers always (a rule would be saved in the person's OpenCode config)" $O \
  "'        let body = allow ? #\"{\"decision\":\"once\"}\"# : #\"{\"decision\":\"reject\"}\"#'" "'        let body = allow ? #\"{\"decision\":\"always\"}\"# : #\"{\"decision\":\"reject\"}\"#'"
run "A32 an id that is not ses_… reaches a process argument" $O \
  "'        guard s.hasPrefix(prefix), s.count > prefix.count, s.count <= 80 else { return false }\n        return s.dropFirst(prefix.count).allSatisfy { \$0.isASCII && (\$0.isLetter || \$0.isNumber) }'" "'        return s.hasPrefix(prefix)'"
run "A33 a subagent (child) session gets a row of its own" $O \
  "'        for s in info where s.parentID == nil {'" "'        for s in info {'"
run "A34 an idle session reads as waiting with no terminal client open" $O \
  "'            } else if clientOpen, now.timeIntervalSince(s.updated) <= AgentSessionRules.staleAfter {'" "'            } else if now.timeIntervalSince(s.updated) <= AgentSessionRules.staleAfter {'"
run "A35 the background service counts as a terminal client" $O \
  "'            return !parts.dropFirst().contains(\"serve\")'" "'            return true'"
run "A36 session times read as seconds (dates in 58 000 AD)" $O \
  "'        if let n = ms as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000) }'" "'        if let n = ms as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }'"
run "A37 an answered OpenCode request keeps its card" $O \
  "'            let waiting = pending.filter { \$0.sessionID == s.id && !answered.contains(\$0.id) }'" "'            let waiting = pending.filter { \$0.sessionID == s.id }'"

# P5c — notices and recent sessions.
N=XFinder/Core/Agents/AgentNotify.swift
RC=XFinder/Core/Agents/AgentRecent.swift
run "A38 launching XFinder announces sessions that were already waiting" $N \
  "'        guard let old else { return [] }'" "'        let old = old ?? []'"
run "A39 the same request is announced on every rebuild" $N \
  "'                if case .waitingForPermission(let q)? = before?.status, q.requestID == p.requestID { continue }'" "'                _ = before'"
run "A40 answering a request reads as a finished turn" $N \
  "'                guard settings.finished, let before, case .running = before.status else { continue }'" "'                guard settings.finished, before != nil else { continue }'"
run "A41 desktop-app Claude sessions listed as terminal sessions" $RC \
  "'        guard let entry = field(\"entrypoint\", in: text), entry == \"cli\",'" "'        guard let entry = field(\"entrypoint\", in: text), !entry.isEmpty,'"
run "A42 Codex desktop sessions listed" $RC \
  "'        guard terminal, let sid'" "'        guard terminal || true, let sid'"
run "A43 live sessions listed again under recent" $RC \
  "'            .filter { !live.contains(\$0.id) && seen.insert(\$0.id).inserted }'" "'            .filter { seen.insert(\$0.id).inserted }'"
run "A44 a value cut by the head limit is guessed" $RC \
  "'        guard i < text.endIndex else { return nil }                       // unterminated ⇒ cut mid-value'" "'        _ = 0'"
run "A45 a session id that is not shell-safe reaches the copied command" $RC \
  "'        !s.isEmpty && s.count <= 80 && s.allSatisfy { \$0.isASCII && (\$0.isLetter || \$0.isNumber || \$0 == \"-\" || \$0 == \"_\") }'" "'        !s.isEmpty'"

# P5 review — a forged session id must never become a path outside the decisions folder.
run "A46 the parser accepts a session id with a path in it" $E \
  "'        guard isSafeSessionID(sessionID) else { return nil }'" "'        guard !sessionID.isEmpty else { return nil }'"
run "A47 the hook waits on (and later cats/rm's) a decision file named by an unsafe id" $Z \
  "'  \x27\x27|*[!A-Za-z0-9_-]*) safe_sid=\"\" ;;'" "'  \x27\x27) safe_sid=\"\" ;;'"

# P6 — "Nhắn phiên": what may be typed into a terminal, when, and into which window.
T=XFinder/Core/Agents/AgentTalk.swift
run "A48 an ESC sequence reaches the terminal live" $T \
  "'            if v < 0x20 || v == 0x7F || (0x80...0x9F).contains(v) { continue }'" \
  "'            if (v < 0x20 && v != 0x1B) || v == 0x7F || (0x80...0x9F).contains(v) { continue }'"
run "A49 a newline in the reply presses Enter early" $T \
  "'            let isBreak = v == 0x0A'" "'            if v == 0x0A { out.unicodeScalars.append(scalar); continue }\n            let isBreak = v == 0x0A'"
run "A50 a reply is typed over a permission request" $T \
  "'        case .waitingForPermission:\n'" "'        case .waitingForPermission:\n            return .sendNow\n'"
run "A51 a reply is typed into a dialog on screen" $T \
  "'            if route.typesIntoTerminal, session.dialogOnScreen {'" "'            if route.typesIntoTerminal, session.dialogOnScreen, Bool(\"false\") == true {'"
run "A52 a reply picks an option of a pending question" $T \
  "'            if route.typesIntoTerminal, session.questionPending {'" "'            if route.typesIntoTerminal, session.questionPending, Bool(\"false\") == true {'"
run "A53 a working session gets typed into at once" $T \
  "'            return .queue\n        case .waitingForInput:'" "'            return .sendNow\n        case .waitingForInput:'"
run "A54 a held message for an ended session waits forever" $T \
  "'            return session.status == .ended ? false : nil'" "'            return nil'"
run "A55 a reused tmux pane id is typed into" $T \
  "'        return output.trimmingCharacters(in: .whitespacesAndNewlines) == recorded'" "'        return true'"
run "A56 a kitty window that now runs something else is typed into" $T \
  "'                    return fg.contains(Int(agentPID))'" "'                    return true'"
run "A57 a kitty tcp listener is accepted (typing over the network)" $T \
  "'        guard let l = listenOn, l.hasPrefix(\"unix:\") else { return nil }'" \
  "'        guard let l = listenOn else { return nil }\n        if l.hasPrefix(\"tcp:\") { return l }'"
run "A58 tmux gets the text as an argument (Process decomposes it to NFD)" $T \
  "'\"load-buffer\", \"-b\", buffer, \"-\"]'" "'\"set-buffer\", \"-b\", buffer]'"
run "A59 kitty gets the text in the escape-interpreting argument form" $T \
  "'    static func kittyTypeArguments(socket: String, windowID: Int) -> [String] {\n        [\"@\", \"--to\", socket, \"send-text\", \"--match\", \"id:\\\\(windowID)\", \"--stdin\"]'" \
  "'    static func kittyTypeArguments(socket: String, windowID: Int) -> [String] {\n        [\"@\", \"--to\", socket, \"send-text\", \"--match\", \"id:\\\\(windowID)\"]'"
run "A60 OpenCode loses delivery: queue (the prompt steers a running turn)" $T \
  "'        let body = queue ? #\"{\"delivery\":\"queue\",\"text\":\"# + asciiJSONString(text) + \"}\"'" \
  "'        let body = queue ? #\"{\"text\":\"# + asciiJSONString(text) + \"}\"'"
run "A61 non-ASCII text reaches the OpenCode argument raw" $T \
  "'            default: out += String(format: \"\\\\\\\\u%04x\", unit)'" "'            default: out.unicodeScalars.append(Unicode.Scalar(unit) ?? \"?\")'"
run "A62 a reply longer than the cap goes through whole" $T \
  "'        if out.count > maxLength { out = String(out.prefix(maxLength)) }\n'" "''"
run "A63 AskUserQuestion never marks a question pending" $E \
  "'                s.questionPending = e.toolName == AgentSessionRules.questionTool'" "'                s.questionPending = false'"
run "A64 a dialog stays on screen after the person answered it" $E \
  "'                 .permissionDenied, .sessionStart:\n                s.dialogOnScreen = false'" "'                 .permissionDenied, .sessionStart:\n                break'"
run "A65 an elicitation dialog is not seen" $E \
  "'                case \"permission_prompt\"?, \"elicitation_dialog\"?:'" "'                case \"permission_prompt\"?:'"

# P6 review
run "A66 a newline in an env value splits the event (both halves dropped)" $Z \
  "'LC_ALL=C tr -d \x27\\\\001-\\\\037\\\\177\x27 | '" "''"
run "A67 the send button says send while the text will be copied" $T \
  "'        if case .copyInstead = decision(for: session, route: route) {'" "'        if false, case .copyInstead = decision(for: session, route: route) {'"

# The restore check and the post-restore suite run come AFTER every mutation (they used to sit before A11, so the
# later mutations ran unchecked — found while adding A20/A21).
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
