#!/bin/sh
# XF-T27 Chống ngủ + Lau bàn phím — inject each failure mode of the pure rules; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-systools.XXXXXX)
FILES="XFinder/Core/SystemMonitor/CaffeineRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM
FILTER='CaffeineRulesTests'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /Fatal error|Exited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
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
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}
F=XFinder/Core/SystemMonitor/CaffeineRules.swift
run "C1 a hold that expired while the app was closed is restarted" $F \
  "'        guard left >= 60 else { return .none }'" "'        _ = left'"
run "C2 a timed hold resumes as indefinite" $F \
  "'        return .minutesLeft(Int((left / 60).rounded(.down)))'" "'        return .indefinite'"
run "C3 low battery stops a hold while charging" $F \
  "'        guard onBattery, let percent else { return false }'" "'        guard let percent else { return false }'"
run "C4 the UPS is read as the Mac's battery" $F \
  "'for d in sources where (d[\"Type\"] as? String) == \"InternalBattery\" {'" "'for d in sources {'"
run "C5 another key does not reset the Esc count" $F \
  "'            guard isEscape else { presses = []; return false }'" "'            guard isEscape else { return false }'"
run "C6 slow Esc presses still unlock" $F \
  "'            presses = presses.filter { t - \$0 <= Self.window } + [t]'" "'            presses = presses + [t]'"
run "C7 cleaning minutes are not clamped" $F \
  "'min(max(minutes, cleaningRange.lowerBound), cleaningRange.upperBound)'" "'minutes'"
echo "RESULT: $red/$total mutations RED"
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
