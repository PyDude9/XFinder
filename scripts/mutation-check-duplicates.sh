#!/bin/sh
# XF-MFGAP-02 — duplicate verification/authorization mutants; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-duplicates.XXXXXX)
FILES="XFinder/Core/Duplicates/DuplicateRules.swift XFinder/Core/Duplicates/DuplicateScanEngine.swift XFinder/Core/Duplicates/DuplicateTrash.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='DuplicateRulesTests'
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
run_multi() {
  name=$1; shift; total=$((total+1))
  while [ "$#" -ge 3 ]; do mutate "$1" "$2" "$3" || exit 2; shift 3; done
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $name produced no result"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $name ($n failing)"
  else echo "GREEN $name (0) <-- unguarded"; fi
}
run_multi 'D1 forced equal hash still needs bytes' XFinder/Core/Duplicates/DuplicateScanEngine.swift ''"'"'return try equalBytes(move.file, move.keeper, cancelled: cancelled)'"'"'' ''"'"'return true'"'"''
run_multi 'D2 changed fingerprint rejected' XFinder/Core/Duplicates/DuplicateRules.swift ''"'"'-> Bool { a == b }'"'"'' ''"'"'-> Bool { true }'"'"''
run_multi 'D3 selected keeper protections bypassed' XFinder/Core/Duplicates/DuplicateTrash.swift ''"'"'let authorized = selected.contains(move.file.id) && !selected.contains(move.keeper.id)'"'"'' ''"'"'let authorized = selected.contains(move.file.id)'"'"'' XFinder/Core/Duplicates/DuplicateTrash.swift ''"'"'hasKeeper: !selected.contains(move.keeper.id)'"'"'' ''"'"'hasKeeper: true'"'"''
run_multi 'D4 empty selection yields enabled plan' XFinder/Core/Duplicates/DuplicateRules.swift ''"'"'guard complete, !selected.isEmpty else { return nil }'"'"'' ''"'"'guard complete else { return nil }'"'"'' XFinder/Core/Duplicates/DuplicateRules.swift ''"'"'return moves.isEmpty ? nil : moves'"'"'' ''"'"'return moves'"'"''
run_multi 'D5 cancellation ignored across move boundaries' XFinder/Core/Duplicates/DuplicateTrash.swift ''"'"'\n            if cancelled() { outcome.cancelled = true; break }'"'"'' ''"'"'\n            if false { outcome.cancelled = true; break }'"'"'' XFinder/Core/Duplicates/DuplicateTrash.swift ''"'"'selected: authorized, cancelled: cancelled(), fingerprintsMatch: true'"'"'' ''"'"'selected: authorized, cancelled: false, fingerprintsMatch: true'"'"'' XFinder/Core/Duplicates/DuplicateTrash.swift ''"'"'DuplicateScanEngine.verify(move, cancelled: cancelled)'"'"'' ''"'"'DuplicateScanEngine.verify(move, cancelled: { false })'"'"'' XFinder/Core/Duplicates/DuplicateTrash.swift ''"'"'selected: authorized, cancelled: cancelled(), fingerprintsMatch: unchanged'"'"'' ''"'"'selected: authorized, cancelled: false, fingerprintsMatch: unchanged'"'"''
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
