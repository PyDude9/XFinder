#!/bin/sh
# XF-T35 Phân tích thư mục — inject each failure mode of StorageScanRules; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-storage.XXXXXX)
FILES="XFinder/Core/Storage/StorageScanRules.swift XFinder/Core/Storage/StorageTreeRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='StorageScan|StorageTree'
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
S=XFinder/Core/Storage/StorageScanRules.swift
run "S1  ties sorted by path descending" $S \
  "'        return lhs.relativePath.utf8.lexicographicallyPrecedes(rhs.relativePath.utf8)'" "'        return rhs.relativePath.utf8.lexicographicallyPrecedes(lhs.relativePath.utf8)'"
run "S2  smallest file first" $S \
  "'        if lhs.logicalSize != rhs.logicalSize { return lhs.logicalSize > rhs.logicalSize }'" "'        if lhs.logicalSize != rhs.logicalSize { return lhs.logicalSize < rhs.logicalSize }'"
run "S3  top list grows past the limit" $S \
  "'        if files.count > limit { files.removeLast() }'" "'        _ = limit'"
run "S4  overflow wraps instead of saturating" $S \
  "'            logicalBytes = Int64.max\n            didOverflow = true'" "'            logicalBytes = sum\n            didOverflow = true'"
run "S5  overflow not reported" $S \
  "'            logicalBytes = Int64.max\n            didOverflow = true'" "'            logicalBytes = Int64.max'"
run "S6  skipped entries still say complete" $S \
  "'        if requestedStatus == .completed, skippedCount > 0 || didOverflow {'" "'        if requestedStatus == .completed, didOverflow {'"
run "S7  negative size reduces the total" $S \
  "'        guard file.logicalSize >= 0 else {'" "'        guard file.logicalSize >= Int64.min else {'"
run "S8  second hard link counted again" $S \
  "'        if let hardLink, !seenHardLinks.insert(hardLink).inserted {'" "'        if let hardLink, !seenHardLinks.insert(hardLink).inserted, false {'"
run "S9  limit 0 keeps old entries" $S \
  "'            files.removeAll(keepingCapacity: true)\n            return'" "'            return'"
T=XFinder/Core/Storage/StorageTreeRules.swift
run "T1 top file limit" $T "'static let fileLimit = 20'" "'static let fileLimit = 19'"
run "T2 cap ignored" $T "'guard nodes.count + 2 <= limit else {'" "'guard true else {'"
run "T3 tree overflow wraps" $T "'return overflow ? Int64.max : value'" "'return value'"
run "T4 aggregate count lost" $T "'nodes[id].fileCount += node.fileCount'" "'nodes[id].fileCount += 0'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
