#!/bin/sh
# XF-T25 Cuộn chuột mượt — inject each failure mode of the pure rules; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-smooth.XXXXXX)
FILES="XFinder/Core/SmoothScroll/SmoothScrollRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM
FILTER='SmoothScrollRulesTests'
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
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}
F=XFinder/Core/SmoothScroll/SmoothScrollRules.swift
run "S1  trackpad inertia (momentum phase) is smoothed as a wheel" $F \
  "'e.scrollPhase != 0 || e.momentumPhase != 0 ? .gesture : .wheel'" "'e.scrollPhase != 0 ? .gesture : .wheel'"
run "S2  isContinuous decides the device (the Razer reads as a trackpad)" $F \
  "'e.scrollPhase != 0 || e.momentumPhase != 0 ? .gesture : .wheel'" "'e.isContinuous ? .gesture : .wheel'"
run "S3  our own posted events are smoothed again (feedback loop)" $F \
  "'guard settings.enabled, e.userData != tag, e.userData != gestureTag,'" "'guard settings.enabled, e.userData != gestureTag,'"
run "S4  the gesture engine's scroll is smoothed twice" $F \
  "'guard settings.enabled, e.userData != tag, e.userData != gestureTag,'" "'guard settings.enabled, e.userData != tag,'"
run "S5  ⌘/⌥/⌃-wheel is smoothed (zoom breaks)" $F \
  "'!e.commandOptionOrControl,'" "'true,'"
run "S6  reverse is ignored" $F \
  "'(s.reverse ? -1 : 1)'" "'(1)'"
run "S7  speed is ignored" $F \
  "'let factor = Double(s.speed) / 100'" "'let factor = 1.0'"
run "S8  a pixel wheel is read as lines" $F \
  "'let dy = e.isContinuous ? Double(e.pointY) : Double(e.lineY) * pixelsPerLine'" "'let dy = Double(e.lineY) * pixelsPerLine'"
run "S9  turning around glides on against the hand" $F \
  "'remaining = 0; carry = 0 }'" "'_ = 0 }'"
run "S10 the glide ends short of its distance (rounding dropped)" $F \
  "'if remaining == 0 { whole += carry.rounded(); carry = 0 }'" "'if remaining == 0 { carry = 0 }'"
run "S11 the last half pixel creeps forever (never idle)" $F \
  "'if abs(remaining - move) < 0.5 { move = remaining }'" "'_ = move'"
run "S12 an out-of-range speed is trusted" $F \
  "'s.speed = min(max(speed, SmoothScrollRules.speedRange.lowerBound), SmoothScrollRules.speedRange.upperBound)'" "'s.speed = max(speed, SmoothScrollRules.speedRange.lowerBound)'"
run "S13 the time constant ignores the chosen smoothness scale" $F \
  "'let tau = Double(smoothnessMs) / 1000 / 3'" "'let tau = Double(smoothnessMs) / 1000'"
run "S14 another smoother is never noticed" $F \
  "'bundleIDs.lazy.compactMap { conflictingBundleIDs[\$0] }.first'" "'nil as String?'"
echo "RESULT: $red/$total mutations RED"
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
