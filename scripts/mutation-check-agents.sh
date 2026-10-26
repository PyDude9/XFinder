#!/bin/sh
# N3 — inject the agent-session rules' known failure modes one at a time; every one must turn the suite RED.
# Same harness rules as mutation-check-notch.sh: a missing anchor ABORTS (a mutation that cannot be injected is a
# broken gate), sources are restored byte-identical by an EXIT trap, the last step asserts the tree is green.
# Run detached and poll the log: `nohup sh scripts/mutation-check-agents.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-agents.XXXXXX)
FILES="XFinder/Core/Agents/AgentEvents.swift XFinder/Core/Agents/AgentHookInstaller.swift XFinder/Core/Agents/AgentUsage.swift XFinder/Core/Agents/ClaudeStatusLine.swift XFinder/Core/Agents/AgentKind.swift XFinder/Resources/Agents/xfinder-agent-hook.zsh XFinder/Core/Agents/OpenCodeRules.swift XFinder/Core/Agents/AgentNotify.swift XFinder/Core/Agents/AgentRecent.swift XFinder/Core/Agents/AgentTalk.swift XFinder/Core/Agents/WindowlessRules.swift XFinder/Core/Agents/AgentTalkSender.swift XFinder/Core/Agents/CrewRules.swift XFinder/Core/Agents/CrewGate.swift XFinder/Core/Agents/CrewGit.swift XFinder/Resources/Agents/xfinder-crew.zsh XFinder/Core/Agents/AgentQuotaRules.swift XFinder/Core/Agents/CodexAppServer.swift XFinder/Core/Agents/AgentHandoff.swift XFinder/Core/Notch/LiveActivity.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM

FILTER='CrewGate|AgentTranscriptLimit|LiveActivity|AgentQuota|CodexAppServer|AgentHandoff|Crew|Windowless|ChildStdin|AgentTalk|AgentSession|AgentReplaySeed|AgentCodex|OpenCodeRules|AgentNotifyRecent|AgentUsage|ClaudeStatusLine|FeatureContract|FeatureCatalog'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
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

DRY_BAD=0
if [ -n "${DRY:-}" ]; then base=0; else base=$(fails); fi; echo "baseline failures: $base"
[ "$base" = "0" ] || { echo "FAIL: baseline is not green"; exit 1; }

red=0; total=0
run() {
  # ONLY=H runs just the mutations whose label starts with H (a fast pass while writing new ones); the full run is the gate.
  if [ -n "${ONLY:-}" ]; then case "$1" in "$ONLY"*) ;; *) return 0;; esac; fi
  # DRY=1 only checks that every anchor still exists exactly once (seconds, not an hour): run it after editing any target.
  if [ -n "${DRY:-}" ]; then
    python3 - "$2" "$3" <<'PY' && echo "ok      $1" || { echo "MISSING $1"; DRY_BAD=1; }
import sys, ast
s = open(sys.argv[1]).read(); old = ast.literal_eval(sys.argv[2])
sys.exit(0 if s.count(old) == 1 else 1)
PY
    return 0
  fi
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
  "'            if case .waitingForPermission(let p) = s.status, answered.contains(p.requestID) {'" "'            if case .waitingForPermission(let p) = s.status, false, answered.contains(p.requestID) {'"
run "A3 a tool starting leaves the permission card up" XFinder/Core/Agents/AgentEvents.swift \
  "'            s.status = .running(tool: e.toolName)\n        case .postToolUse, .postToolUseFailure:'" \
  "'            if case .waitingForPermission = s.status {} else { s.status = .running(tool: e.toolName) }\n        case .postToolUse, .postToolUseFailure:'"
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
run "U1 the unfinished last line is thrown away (a message being written is lost)" $U \
  "'        tail.pending = Data(buffer[start...])'" "'        tail.pending = Data()'"
run "U2 the read position never moves (every scan re-reads the whole file)" $U \
  "'        tail.offset += UInt64(chunk.count)'" "'        _ = chunk.count'"
run "U3 a truncated file is never read again" $U \
  "'    static func mustRestart(_ tail: LogTail, fileSize: UInt64) -> Bool { fileSize < tail.offset }'" "'    static func mustRestart(_ tail: LogTail, fileSize: UInt64) -> Bool { false }'"
E=XFinder/Core/Agents/AgentEvents.swift
run "U4 a day-old event log is already deleted (the week is ignored)" $E \
  "'let cutoff = eventsFileName(for: now.addingTimeInterval(-Double(keepDays) * 86_400))'" "'let cutoff = eventsFileName(for: now)'"
run "U5 a file that is not an events day file is deleted" $E \
  "'name.count == cutoff.count && name.hasPrefix(\"events-\")'" "'name.hasPrefix(\"events-\")'"
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
  "r'    static func sessionKey(_ e: AgentEvents.Event) -> String { \"\\(e.agent.rawValue):\\(e.sessionID)\" }'" "'    static func sessionKey(_ e: AgentEvents.Event) -> String { e.sessionID }'"
run "A25 Codex SessionEnd timeout above its 3 s cap" $H \
  "'        (\"SessionStart\", 10), (\"SessionEnd\", 3), (\"UserPromptSubmit\", 10),'" "'        (\"SessionStart\", 10), (\"SessionEnd\", 10), (\"UserPromptSubmit\", 10),'"
run "A26 the hook keeps Codex's answer text in the log" $Z \
  "'del(.tool_response, .last_assistant_message)'" "'del(.tool_response)'"
run "A27 the parser ignores the line's agent" $E \
  "'        if let a = obj[\"agent\"] as? String { e.agent = AgentKind(rawValue: a) ?? .claude }'" "'        _ = obj[\"agent\"]'"
run "A28 a Codex interrupt reads as still running" $E \
  "'        case .stop, .interrupt:\n            s.status = .waitingForInput'" "'        case .stop, .interrupt:\n            s.status = e.name == .interrupt ? .running(tool: nil) : .waitingForInput'"
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
  "'            s.questionPending = e.toolName == AgentSessionRules.questionTool'" "'            s.questionPending = false'"
run "A64 a dialog stays on screen after the person answered it" $E \
  "'             .permissionDenied, .sessionStart, .stopFailure:\n            s.dialogOnScreen = false'" "'             .permissionDenied, .sessionStart, .stopFailure:\n            break'"
run "A65 an elicitation dialog is not seen" $E \
  "'            case \"permission_prompt\"?, \"elicitation_dialog\"?:'" "'            case \"permission_prompt\"?:'"

# P6 review
run "A66 a newline in an env value splits the event (both halves dropped)" $Z \
  "'LC_ALL=C tr -d \x27\\\\001-\\\\037\\\\177\x27 | '" "''"
run "A67 the send button says send while the text will be copied" $T \
  "'        if case .copyInstead = decision(for: session, route: route) {'" "'        if false, case .copyInstead = decision(for: session, route: route) {'"

# P7a — windowless sessions + the SIGPIPE guard
W=XFinder/Core/Agents/WindowlessRules.swift
run "A68 a non-UUID session id reaches the claude arguments" $W \
  "'        guard UUID(uuidString: sessionID) != nil else { return nil }'" "'        guard !sessionID.isEmpty else { return nil }'"
run "A69 the child inherits CLAUDECODE (it would think it runs inside another Claude Code)" $W \
  "'        for k in [\"CLAUDECODE\", '" "'        for k in ['"
run "A70 the child does not carry the windowless marker" $W \
  "'        env[markerVariable] = \"1\"'" "'        _ = markerVariable'"
run "A71 a sub-agent's chatter is shown as the session's answer" $W \
  "'            if let parent = obj[\"parent_tool_use_id\"], !(parent is NSNull) { return .ignored }\n'" "''"
run "A72 an ended session still takes a turn" $W \
  "'            guard !isEnded else { return }\n            append(.person, text, at: at)'" "'            append(.person, text, at: at)'"
run "A73 a hook row stays hosted after its process ended (a reply into a dead pipe)" $W \
  "'                out[i].hostedByXFinder = !r.isEnded'" "'                out[i].hostedByXFinder = true'"
run "A74 the in-memory transcript grows without a cap" $W \
  "'            if transcript.count > WindowlessRules.transcriptCap { transcript.removeFirst(transcript.count - WindowlessRules.transcriptCap) }\n'" "''"
run "A75 a windowless reply is written mid-turn" $T \
  "'            if case .windowless = route { return .queue }'" "'            if case .windowless = route { return .sendNow }'"
run "A76 a hosted session is not routed to its stdin" $T \
  "'        if session.hostedByXFinder { return .windowless(sessionID: session.id) }\n'" "''"
run "A77 env parsing turns startup noise into a variable" $W \
  "'            guard !name.isEmpty, name.allSatisfy({ \$0.isASCII && (\$0.isLetter || \$0.isNumber || \$0 == \"_\") }) else { continue }'" "'            guard !name.isEmpty else { continue }'"
run "A78 the P6 sender writes to a child stdin without F_SETNOSIGPIPE (a dead CLI kills XFinder)" XFinder/Core/Agents/AgentTalkSender.swift \
  "'        _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)'" "'        _ = 0'"

# P7b — crews
K=XFinder/Core/Agents/CrewRules.swift
run "B1 the signature is not checked (any member can pose as another)" $K \
  "'              signature(name: name, to: to, text: raw, token: token) == mac.lowercased(),'" "'              !mac.isEmpty,'"
run "B2 a member can message itself" $K \
  "'        else if to != from, roles.contains(to) { targets = [to] }'" "'        else if roles.contains(to) { targets = [to] }'"
run "B3 two deliveries go to one member at once (the reply-back slot is overwritten)" $K \
  "'                guard free[d.to] == true, inFlight[d.to] == nil, !ended.contains(d.to) else { i += 1; continue }'" "'                guard !ended.contains(d.to) else { i += 1; continue }'"
run "B4 a reply asks for a reply (endless ping-pong)" $K \
  "'queue.append(Delivery(to: asker, text: \"[crew] Reply from \\\\(role): \\\\(text)\", replyTo: nil))'" "'queue.append(Delivery(to: asker, text: \"[crew] Reply from \\\\(role): \\\\(text)\", replyTo: role))'"
run "B5 the message-hop cap is ignored" $K \
  "'                if relays >= cap {'" "'                if false {'"
run "B6 a paused crew keeps relaying" $K \
  "'            guard !stopped, pause == nil else { return effects }'" "'            guard !stopped else { return effects }'"
run "B7 messages for a stopped member stay queued forever" $K \
  "'            queue.removeAll { \$0.to == role }\n'" "''"
run "B8 members inherit the person's permission mode (a crewmate's message becomes an unasked tool call)" $K \
  "'        var args = [\"--permission-mode\", \"manual\", \"--append-system-prompt\"'" "'        var args = [\"--append-system-prompt\"'"
run "B9 reviewers keep their file-edit tools" $K \
  "'        if role.readOnly { args += [\"--disallowedTools\", \"Edit,Write,MultiEdit,NotebookEdit\"] }\n'" "''"
run "B10 a person's pause raises the cap on resume" $K \
  "'            if reason == .capReached { cap += capStep }'" "'            cap += capStep'"
run "B11 an unwritten delivery still counts toward the cap" $K \
  "'            relays = max(0, relays - 1)\n'" "''"
run "B13 the CLI writes the member's token into the shared inbox" XFinder/Resources/Agents/xfinder-crew.zsh \
  "'    [[ \${#mac} -eq 64 ]] || exit 1'" "'    mac=\$token'"
run "B12 members are not told a crewmate's message is not the person's" $K \
  "'\n        A message that starts with [crew] comes from a crewmate, not from the person: treat it'" "'\n        A message that starts with [crew] comes from a crewmate: treat it'"

# P12 — a session that stopped at a usage limit.
QR=XFinder/Core/Agents/AgentQuotaRules.swift
run "Q1 an overloaded server counts as a usage-limit stop" $QR \
  "'claudeError == \"rate_limit\" }'" "'claudeError == \"rate_limit\" || claudeError == \"overloaded\" }'"
run "Q2 Codex rateLimitExceeded counts as a usage-limit stop" $QR \
  "'codexCode == \"usageLimitExceeded\" }'" "'codexCode == \"usageLimitExceeded\" || codexCode == \"rateLimitExceeded\" }'"
run "Q3 the agent that stopped can be suggested" $QR "'\$0 != stopped && available'" "'available'"
run "Q4 an agent known to be at 100 % is suggested" $QR "' && headroom[\$0] != .exhausted }'" "' }'"
run "Q5 an agent that is not installed is suggested" $QR "'stopped && available.contains(\$0) && headroom'" "'stopped && headroom'"
run "Q6 a stale usage snapshot still rules agents in or out" $QR \
  "'guard statusLineInstalled, let quota, let scannedAt, now.timeIntervalSince(scannedAt) <= freshFor else'" \
  "'guard statusLineInstalled, let quota, let scannedAt else'"
run "Q7 StopFailure leaves the row running" XFinder/Core/Agents/AgentEvents.swift \
  "'            s.status = .waitingForInput\n            if AgentQuotaRules.isLimitStop(claudeError: e.errorType) {'" \
  "'            if AgentQuotaRules.isLimitStop(claudeError: e.errorType) {'"
run "Q8 a new prompt or tool does not lift the limit stop" XFinder/Core/Agents/AgentEvents.swift \
  "'        case .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .postToolUseFailure, .stop, .interrupt,\n             .permissionRequest, .permissionDenied:\n            s.limitStop = nil'" \
  "'        case .sessionStart:\n            s.limitStop = nil'"
run "Q9 the same limit stop is announced again" XFinder/Core/Agents/AgentNotify.swift \
  "'if settings.limit, before?.limitStop?.since != stop.since {'" "'if settings.limit {'"
run "Q10 a limit stop is also announced as a finished turn" XFinder/Core/Agents/AgentNotify.swift \
  "'{ out.append(.limitStopped(s)) }\n                continue\n'" "'{ out.append(.limitStopped(s)) }\n'"
run "Q11 a pending approval reads like a finished turn in the handoff" XFinder/Core/Agents/AgentHandoff.swift \
  "'case .waitingForPermission(let p): return .waitingForApproval(tool: p.toolName, summary: p.summary)'" \
  "'case .waitingForPermission: return .finishedTurn'"
run "Q12 an ended source session still says it is open" XFinder/Core/Agents/AgentHandoff.swift \
  "'if state != .ended { s += '" "'if true { s += '"
run "Q13 the pending command is not cut" XFinder/Core/Agents/AgentHandoff.swift \
  "'(summary.count > approvalSummaryCap ? String(summary.prefix(approvalSummaryCap)) + \"…\" : summary)'" "'summary'"
run "Q14 StopFailure is not subscribed" XFinder/Core/Agents/AgentHookInstaller.swift \
  "'        (\"StopFailure\", 10),\n'" "''"
run "Q15 a Codex error code is kept for a completed turn" XFinder/Core/Agents/WindowlessRules.swift \
  "'lastErrorCode = status == \"failed\" ? code : nil'" "'lastErrorCode = code'"
run "Q16 codexErrorInfo is not read" XFinder/Core/Agents/CodexAppServer.swift \
  "'code: errorCode(errObj?[\"codexErrorInfo\"]))'" "'code: nil)'"

run "Q17 a stale limit stop outranks a live status" XFinder/Core/Agents/AgentEvents.swift \
  "'var isLimitStopped: Bool { limitStop != nil && status == .waitingForInput }'" "'var isLimitStopped: Bool { limitStop != nil }'"
run "Q18 a refused Codex turn/start leaves the row working forever" XFinder/Core/Agents/WindowlessRules.swift \
  "'                if case .working = phase, activeTurnID == nil, turns > 0 { phase = .waiting }\n'" "''"
run "Q19 a Codex limit stop takes a new time with every later event" XFinder/Core/Agents/WindowlessRules.swift \
  "'since: r.lastErrorAt ?? r.updatedAt)'" "'since: r.updatedAt)'"
run "Q20 a finished-turn notice wipes a limit stop before it is seen" XFinder/Core/Notch/LiveActivity.swift \
  "'            return rank(a.tint) > rank(b.tint)'" "'            return false'"

run "Q21 a subagent's refusal (sidechain) stops the main session" XFinder/Core/Agents/AgentEvents.swift \
  "'                  (d[\"isSidechain\"] as? Bool) != true else { continue }'" "'                  true else { continue }'"
run "Q22 a real answer (or another error) after the refusal does not lift it" XFinder/Core/Agents/AgentEvents.swift \
  "'            guard refused else { found = nil; continue }'" "'            guard refused else { continue }'"
run "Q23 a refusal older than the last hook event still stops the row" XFinder/Core/Agents/AgentEvents.swift \
  "'              limit.since >= s.updatedAt.addingTimeInterval(-2) else { return s }'" "'              true else { return s }'"
run "Q24 a hook line can point the transcript read at any file" XFinder/Core/Agents/AgentEvents.swift \
  "'        return resolved.hasPrefix(root) && resolved.hasSuffix(\".jsonl\")'" "'        return true'"
run "Q26 a symlink inside projects points the read at another file" XFinder/Core/Agents/AgentEvents.swift \
  "'        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path'" \
  "'        let resolved = URL(fileURLWithPath: path).standardizedFileURL.path'"
run "Q25 a prompt quoting the limit text marks the session stopped (the sniffing fix)" XFinder/Core/Agents/AgentEvents.swift \
  "'            s.lastPrompt = e.prompt\n            s.status = .running(tool: nil)'" \
  "'            s.lastPrompt = e.prompt\n            if e.prompt?.contains(\"hit your session limit\") == true { s.status = .waitingForInput; s.limitStop = AgentSession.LimitStop(reason: \"rate_limit\", since: e.receivedAt) } else { s.status = .running(tool: nil) }'"

# The restore check and the post-restore suite run come AFTER every mutation (they used to sit before A11, so the
# later mutations ran unchecked — found while adding A20/A21).
# XF-T23 v2a (2026-10-18) — CrewV2 gate, envelope, classifier
run "G1 the branch field leaves the MAC (a forgeable branch)" XFinder/Core/Agents/CrewGate.swift \
  "'f(\"task\", e.task), f(\"criteria\", e.criteria), f(\"branch\", e.branch), f(\"verdict\", e.verdict?.rawValue),'" \
  "'f(\"task\", e.task), f(\"criteria\", e.criteria), f(\"branch\", nil), f(\"verdict\", e.verdict?.rawValue),'"
run "G2 one approval is enough to merge" XFinder/Core/Agents/CrewGate.swift \
  "'                if sec == .approved, rev == .approved {'" "'                if sec == .approved || rev == .approved {'"
run "G3 a new done keeps the old verdicts" XFinder/Core/Agents/CrewGate.swift \
  "'                rounds[b, default: 0] += 1\n                branches[b] = .awaitingVerdicts(security: nil, reviewer: nil)'" \
  "'                rounds[b, default: 0] += 1\n                if case .awaitingVerdicts = state(of: b) { return .nowAwaiting(b, round: rounds[b] ?? 1) }\n                branches[b] = .awaitingVerdicts(security: nil, reviewer: nil)'"
run "G4 git -C . push is an ordinary command" XFinder/Core/Agents/CrewGate.swift \
  "'                        if w[i] == \"-C\" || w[i] == \"-c\" { i += 2 } else { i += 1 }'" "'                        i += 1'"

# XF-T23 v2b (2026-10-18) — the PreToolUse guard, branch families, the checklist, the git helper, the signed CLI
run "H1 an edit outside the worktree is allowed" XFinder/Core/Agents/CrewGate.swift \
  "'        if CrewV2.StateChanging.pathInside(root: resolve(root), file: resolve(file)) { return nil }'" \
  "'        if true { return nil }'"
run "H2 a symlink inside the worktree is trusted" XFinder/Core/Agents/CrewGate.swift \
  "'        var resolved = realpath(url.path, &buffer).map { String(cString: \$0) } ?? url.path'" \
  "'        var resolved = url.path'"
run "H3 the guard never asks about a state-changing command" XFinder/Core/Agents/CrewGate.swift \
  "'            if case .stateChanging(let what) = CrewV2.StateChanging.classify(command: command) {'" \
  "'            if case .stateChanging(let what) = CrewV2.StateChanging.classify(command: command), false {'"
run "H4 a taken branch name is reused" XFinder/Core/Agents/CrewGate.swift \
  "'            if (Array(names.values) + [integration]).allSatisfy({ isValidBranch(\$0) && !exists(\$0) }) { return (names, integration) }'" \
  "'            if (Array(names.values) + [integration]).allSatisfy({ isValidBranch(\$0) }) { return (names, integration) }'"
run "H5 the lead may hand a builder a plain message instead of a task" XFinder/Core/Agents/CrewGate.swift \
  "'        from == .lead && to.editsCode && (kind == .question || kind == .status)'" "'        false'"
run "H6 a mergeable branch shows the reviewer as pending" XFinder/Core/Agents/CrewGate.swift \
  "'            return Checklist(done: true, security: .approved, reviewer: .approved, merged: false)\n        case .rejected(let by, _):'" \
  "'            return Checklist(done: true, security: .approved, reviewer: .pending, merged: false)\n        case .rejected(let by, _):'"
run "H7 stopping a crew force-removes a worktree with uncommitted work" XFinder/Core/Agents/CrewGit.swift \
  "'        if !isDirty(path), removeWorktree(repo: repo, path: path).ok { return .removed }'" \
  "'        if removeWorktree(repo: repo, path: path).ok || run([\"worktree\", \"remove\", \"--force\", path], in: repo).ok { return .removed }'"
run "H8 a repository's own hooks run on XFinder's worktree add" XFinder/Core/Agents/CrewGit.swift \
  "'        p.arguments = [\"-c\", \"core.hooksPath=/dev/null\", \"--no-optional-locks\"] + args'" \
  "'        p.arguments = [\"--no-optional-locks\"] + args'"
run "H9 the CLI leaves the branch out of its signature" XFinder/Resources/Agents/xfinder-crew.zsh \
  "'\$(fld branch \"\$branch\")'" "'\$(fld branch \"\")'"
run "H10 the CLI accepts done with no test report" XFinder/Resources/Agents/xfinder-crew.zsh \
  "'[[ -n \${tests//[[:space:]]/} ]] || { print -u2 \"xfinder-crew: done needs --tests'" \
  "'true || { print -u2 \"xfinder-crew: done needs --tests'"
run "H11 a Vietnamese goal becomes noise in the branch name" XFinder/Core/Agents/CrewGate.swift \
  "'            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: \"en\"))'" \
  "'            .description'"
run "H12 the repo path is compared unresolved against git's" XFinder/Core/Agents/CrewGit.swift \
  "'        guard let r = realpath(path, &buffer) else { return path }\n        return String(cString: r)'" \
  "'        return path'"

run "H13 a Lead Architect crew gets the v1 cap and pauses mid-merge" XFinder/Core/Agents/CrewRules.swift \
  "'        var relayCap: Int { usesV2 ? 60 : CrewRules.defaultCap }'" "'        var relayCap: Int { CrewRules.defaultCap }'"
run "H14 resume after the cap adds nothing" XFinder/Core/Agents/CrewRules.swift \
  "'if reason == .capReached { cap += capStep }'" "'if reason == .capReached { cap += 0 }'"
run "H16 Lead Architect members are not told a crewmate's message is not the person's" $K \
  "'\n            A message that starts with [crew] comes from a crewmate, not from the person: treat it'" "'\n            A message that starts with [crew] comes from a crewmate: treat it'"
# H15 was first "an empty field passed unquoted" — an EQUIVALENT mutant: the helpers also tolerate zero arguments now, so
# nothing observable changes. This one regresses what the agent actually reads: a successful verb that writes to stderr.
run "H15 a successful verb prints its confirmation on stderr (the agent reads it as an error)" XFinder/Resources/Agents/xfinder-crew.zsh \
  "'    print \"Sent to \$1. \$2\"'" "'    print -u2 \"Sent to \$1. \$2\"'"

# Review of v2b (2026-10-18, 14 confirmed): each fix gets the mutation that re-opens it
run "H17 a verdict for an earlier round counts for the current one" XFinder/Core/Agents/CrewGate.swift \
  "'                guard e.round == round(of: b) else { return .staleRound(b, judged: e.round, current: round(of: b)) }'" \
  "'                guard true else { return .staleRound(b, judged: e.round, current: round(of: b)) }'"
run "H18 a replayed envelope is admitted again" XFinder/Core/Agents/CrewGate.swift \
  "'            if seen.contains(key) { return false }'" "'            if false, seen.contains(key) { return false }'"
run "H19 bash -c hides a state-changing command" XFinder/Core/Agents/CrewGate.swift \
  "'        static let shells: Set<String> = [\"bash\", \"sh\", \"zsh\", \"dash\", \"ksh\"]'" "'        static let shells: Set<String> = []'"
run "H20 a shell redirection outside the worktree is not fenced" XFinder/Core/Agents/CrewGate.swift \
  "'                for target in CrewV2.StateChanging.writeTargets(command) {'" "'                for target in [String]() {'"
run "H21 a hard link no longer asks" XFinder/Core/Agents/CrewGate.swift \
  "'                                             \"ln\"]'" "'                                             ]'"
run "H22 a crew folder whose repository moved is deleted with its work" XFinder/Core/Agents/CrewGit.swift \
  "'                out.failed = entries.map { \"\\\\(\$0.lastPathComponent): repository not found at \\\\(repo ?? \"?\")\" }\n                return out'" \
  "'                return out'"
run "H23 the CLI scans the whole line for options (free text rewrites a signed field)" XFinder/Resources/Agents/xfinder-crew.zsh \
  "'    break\n  done\n  rest=(\"\$@\")'" "'    shift; continue\n  done\n  rest=(\"\$@\")'"
run "H24 the CLI counts bytes, not characters" XFinder/Resources/Agents/xfinder-crew.zsh \
  "'export LC_ALL=en_US.UTF-8'" "'export LC_ALL=C'"
run "H25 the settings file lets the repository switch hooks off" XFinder/Core/Agents/CrewGate.swift \
  "'\"disableAllHooks\": false]'" "'\"disableAllHooks\": true]'"

# 2026-10-25 — a tail folds what it trims into a ReplaySeed (20 000 kept events held ~25 MB)
run "R1 pruning drops a session whose process is alive" XFinder/Core/Agents/AgentEvents.swift \
  "'            let over = s.status == .ended || s.agentPID.map { !isAlive(\$0) } ?? true'" "'            let over = true'"
run "R2 pruning drops a session that still has events in the kept window" XFinder/Core/Agents/AgentEvents.swift \
  "'            if old && over && !keep.contains(key) { continue }'" "'            if old && over { continue }'"
run "R3 the folded prefix is forgotten" XFinder/Core/Agents/AgentEvents.swift \
  "'        var state = seed'" "'        var state = ReplaySeed()'"

# 2026-10-25 — launch read: bytes per line, arithmetic timestamps (70 MB of hook logs took 4,3 s / 305 MB at launch)
run "R4 the line after the first is lost" XFinder/Core/Agents/AgentEvents.swift \
  "'                offset = end + 1'" "'                offset = raw.count'"
run "R5 a slice is read from index 0 of its base" XFinder/Core/Agents/AgentEvents.swift \
  "'        let origin = data.startIndex'" "'        let origin = 0'"
run "R6 the fast timestamp drops the hour" XFinder/Core/Agents/AgentEvents.swift \
  "'days * 86_400 + h * 3_600 + mi * 60 + sec'" "'days * 86_400 + mi * 60 + sec'"
run "R8 March-based month shift is off by one" XFinder/Core/Agents/AgentEvents.swift \
  "'        let mp = (month + 9) % 12'" "'        let mp = (month + 10) % 12'"
run "R9 a dot passes as a session id character" XFinder/Core/Agents/AgentEvents.swift \
  "'|| b == 0x2D || b == 0x5F'" "'|| b == 0x2D || b == 0x5F || b == 0x2E'"
run "R10 the day file name is off by one day" XFinder/Core/Agents/AgentEvents.swift \
  "'        let d = doy - (153 * mp + 2) / 5 + 1'" "'        let d = doy - (153 * mp + 2) / 5'"
run "R11 January and February stay in the previous civil year" XFinder/Core/Agents/AgentEvents.swift \
  "'        return (m <= 2 ? y + 1 : y, m, d)'" "'        return (y, m, d)'"

[ -n "${DRY:-}" ] && { [ "$DRY_BAD" = "0" ] && echo "DRY: every anchor found exactly once" && exit 0; echo "DRY: anchors missing"; exit 1; }
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
