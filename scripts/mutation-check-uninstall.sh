#!/bin/sh
# F2 Gỡ ứng dụng — inject each failure mode; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-uninstall.XXXXXX)
FILES="XFinder/Core/Uninstall/UninstallRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='UninstallRules'
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
U=XFinder/Core/Uninstall/UninstallRules.swift
run "U1  a folder named after the app is pre-selected" $U \
  "'        var selectedByDefault: Bool { match != .name && !location.isProtected }'" "'        var selectedByDefault: Bool { !location.isProtected }'"
run "U2  <bid><more> counts as the app (no dot)" $U \
  "'        if base.hasPrefix(bid + \".\") {'" "'        if base.hasPrefix(bid) {'"
run "U3  another installed app's files are offered" $U \
  "'            other != bundleID && other.hasPrefix(bundleID + \".\") && (base == other || base.hasPrefix(other + \".\"))'" "'            false && other.isEmpty'"
run "U4  Apple's apps can be removed" $U \
  "'        if app.bundleID.hasPrefix(\"com.apple.\") { return .apple }'" "'        if false { return .apple }'"
run "U5  a running app can be removed" $U \
  "'        if running.contains(app.bundleID) { return .running }'" "'        if false { return .running }'"
run "U6  macOS's 513 refusal reads as an unknown failure" $U \
  "'        if domain == NSCocoaErrorDomain && (code == NSFileWriteNoPermissionError || code == NSFileReadNoPermissionError) { return .protected }'" "'        if false { return .protected }'"
run "U7  a group container only has to END in the bid" $U \
  "'        if location == .groupContainers, base.hasSuffix(\".\" + bid) { return .group }'" "'        if location == .groupContainers, base.hasSuffix(bid) { return .group }'"
run "U8  containers offered as tickable (measured: always refused)" $U \
  "'        var alwaysRefused: Bool { self == .containers }'" "'        var alwaysRefused: Bool { false }'"
run "U9  protected locations pre-selected" $U \
  "'        var selectedByDefault: Bool { match != .name && !location.isProtected }'" "'        var selectedByDefault: Bool { match != .name }'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
