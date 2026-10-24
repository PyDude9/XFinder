#!/bin/sh
# Inject the local diagnostics' privacy and correctness failure modes one at a time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to).
#
# Rules this script follows (CLAUDE.md, mutation section):
#   * every mutation names its target file and ABORTS the run if its anchor is missing — a mutation
#     that cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by an EXIT trap even if the run is interrupted;
#   * the last step ASSERTS the restored tree is green (prints the failure count, exits 1 if not 0).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-diagnostics.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-diag.XXXXXX)
FILES="XFinder/Core/Diagnostics/DiagnosticsRules.swift XFinder/Core/Diagnostics/AnalyticsRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM

FILTER='DiagnosticsRules|AnalyticsRules'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
}

# mutate <file> <python-literal-old> <python-literal-new>
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
run() {   # run <name> <file> <old> <new>
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  # No "Executed … with N failures" line means the mutant did not compile or the runner died.
  # That proves nothing about the tests — it is a broken mutation, never a pass.
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}

run "G1 a path is accepted as a log code" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'            (c >= \"a\" && c <= \"z\") || (c >= \"A\" && c <= \"Z\") || (c >= \"0\" && c <= \"9\") || c == \".\" || c == \"_\" || c == \"-\"'" \
  "'            (c >= \"a\" && c <= \"z\") || (c >= \"A\" && c <= \"Z\") || (c >= \"0\" && c <= \"9\") || c == \".\" || c == \"_\" || c == \"-\" || c == \"/\" || c == \" \"'"
run "G2 another user's home folder is not redacted" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'        s = replace(#\"/Users/[^/\\\\s\"\'<>:]+\"#, in: s, with: \"/Users/…\")\n'" "''"
run "G3 e-mail addresses survive redaction" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'        s = replace(#\"[A-Za-z0-9._%+\\\\-]+@[A-Za-z0-9.\\\\-]+\\\\.[A-Za-z]{2,}\"#, in: s, with: \"<email>\")\n'" "''"
run "G4 the faulting frame keeps the full source path" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'                line += \"  (\" + (file as NSString).lastPathComponent'" "'                line += \"  (\" + file'"
run "G5 an image path is used instead of its name" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'(images[imageIndex][\"name\"] as? String ?? \"?\")'" "'(images[imageIndex][\"path\"] as? String ?? \"?\")'"
run "G6 a quit from an earlier run vouches for the last one" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'        return !events[lastLaunch...].contains { \$0.area == \"app\" && \$0.code == \"quit\" }'" \
  "'        return !events.contains { \$0.area == \"app\" && \$0.code == \"quit\" }'"
run "G7 reports of other apps are read" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'        guard name == processName else { return nil }'" "'        guard name != nil else { return nil }'"
run "G8 the issue link carries the permissions and feature list" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'                                 permissions: [], featuresOn: [])).prefix(3).joined(separator: \"\\\\n\"))'" \
  "'                                 permissions: system.permissions, featuresOn: system.featuresOn)).joined(separator: \"\\\\n\"))'"
run "G9 the event ring is not trimmed" XFinder/Core/Diagnostics/DiagnosticsRules.swift \
  "'        events.count > maxEvents ? Array(events.suffix(maxEvents)) : events'" "'        events'"

run "N1 a path becomes a token again" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'                || \". _-,:+()\".unicodeScalars.contains(c)'" "'                || \". _-,:+()/\".unicodeScalars.contains(c)'"
run "N2 events from before the last report are counted again" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'        let fresh = i.events.filter { e in i.since.map { e.time > \$0 } ?? true }'" "'        let fresh = i.events'"
run "N3 a refusal is ignored" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'        if s.optedOut { return .wait(.optedOut) }'" "'        if false { return .wait(.optedOut) }'"
run "N4 the first send skips the grace day" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'        if sinceNotice >= 0, sinceNotice < noticeGrace { return .wait(.grace) }'" "''"
run "N5 a newer schema does not show the notice again" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'        guard let shown = s.noticeShownAt, (s.noticeSchema ?? 0) >= schemaVersion else {'" \
  "'        guard let shown = s.noticeShownAt else {'"
run "N6 a crash frame keeps its source location" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'        if let paren = s.range(of: \"  (\") { s = String(s[..<paren.lowerBound]) }      // \"  (File.swift:42)\"'" "''"
run "N7 the App ID is sent as the client user (a stable id)" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'            [\"appID\": receiver.appID, \"clientUser\": clientUser,'" "'            [\"appID\": receiver.appID, \"clientUser\": receiver.appID,'"
run "N8 a failed send retries on every activation" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'            if sinceAttempt >= 0, sinceAttempt < retryInterval { return .wait(.notDue) }'" "''"
run "N9 the namespace accepts a slash" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'              ns.unicodeScalars.allSatisfy({ (\$0 >= \"a\" && \$0 <= \"z\") || (\$0 >= \"0\" && \$0 <= \"9\") || \$0 == \"-\" || \$0 == \".\" }),'" \
  "'              ns.unicodeScalars.allSatisfy({ _ in true }),'"
run "N10 a namespace of dots climbs out of /v2/namespace/" XFinder/Core/Diagnostics/AnalyticsRules.swift \
  "'              !ns.hasPrefix(\".\"), !ns.contains(\"..\")'" "'              true'"

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
