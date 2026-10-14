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
FILES="XFinder/Core/Diagnostics/DiagnosticsRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM

FILTER='DiagnosticsRules'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} END {print (f==""?"NORESULT":f)}'
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

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
