#!/bin/sh
# F3 Thoát khi đóng cửa sổ cuối — inject each failure mode; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-quitonclose.XXXXXX)
FILES="XFinder/Core/QuitOnClose/QuitOnCloseRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='QuitOnCloseRules'
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
Q=XFinder/Core/QuitOnClose/QuitOnCloseRules.swift
run "Q1  quits with one window still open" $Q \
  "'        return n == 0'" "'        return n <= 1'"
run "Q2  an unreadable window list counts as empty" $Q \
  "'        guard watched, stillRunning, let n = windowCount else { return false }   // nil: AX could not read ⇒ do nothing'" "'        guard watched, stillRunning else { return false }; let n = windowCount ?? 0'"
run "Q3  Finder and the system can be quit when listed" $Q \
  "'        guard enabled, let bid = bundleID, !bid.isEmpty, bid != ownBundleID, !neverQuit.contains(bid) else { return false }'" "'        guard enabled, let bid = bundleID, !bid.isEmpty, bid != ownBundleID else { return false }'"
run "Q4  the switch is ignored" $Q \
  "'        guard enabled, let bid = bundleID, !bid.isEmpty, bid != ownBundleID, !neverQuit.contains(bid) else { return false }'" "'        guard let bid = bundleID, !bid.isEmpty, bid != ownBundleID, !neverQuit.contains(bid) else { return false }'"
run "Q5  no grace (⌘W then ⌘N quits in between)" $Q \
  "'    static let grace: TimeInterval = 1.0'" "'    static let grace: TimeInterval = 0'"
run "Q6  XFinder can quit itself when listed" $Q \
  "'        guard enabled, let bid = bundleID, !bid.isEmpty, bid != ownBundleID, !neverQuit.contains(bid) else { return false }'" "'        guard enabled, let bid = bundleID, !bid.isEmpty, !neverQuit.contains(bid) else { return false }'"
run "Q7  an unlisted app is watched" $Q \
  "'        return apps.contains(bid)'" "'        return !bid.isEmpty'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
