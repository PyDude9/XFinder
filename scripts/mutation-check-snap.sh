#!/bin/sh
# Inject the snap geometry's known failure modes one at a time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to).
#
# Rules this script follows (CLAUDE.md, mutation section):
#   * every mutation names its target file and ABORTS the run if its anchor is missing — a mutation
#     that cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by an EXIT trap even if the run is interrupted;
#   * the last step ASSERTS the restored tree is green (prints the failure count, exits 1 if not 0).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-snap.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-snap.XXXXXX)
FILES="XFinder/Core/Snap/SnapLayout.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM

FILTER='SnapLayout|FeatureContract'
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

run "S1 the notch row ignores its switch" XFinder/Core/Snap/SnapLayout.swift \
  "'        if rowEnabled {\n'" "'        if true {\n'"
run "S2 the right third is one third wide (gap at the right edge)" XFinder/Core/Snap/SnapLayout.swift \
  "'            case .rightThird:     return CGRect(x: x + t2, y: y, width: w - t2, height: h)'" \
  "'            case .rightThird:     return CGRect(x: x + t2, y: y, width: t1, height: h)'"
run "S3 the row region counts before the row is showing" XFinder/Core/Snap/SnapLayout.swift \
  "'(rowVisible && row.insetBy(dx: -8, dy: -8).contains(point))'" "'row.insetBy(dx: -8, dy: -8).contains(point)'"
run "S4 bottom/top swapped in top-left space" XFinder/Core/Snap/SnapLayout.swift \
  "'            case .bottomLeft:     return CGRect(x: x, y: y + h / 2, width: w / 2, height: h / 2)'" \
  "'            case .bottomLeft:     return CGRect(x: x, y: y, width: w / 2, height: h / 2)'"

run "S8 the four-corner tile reads the quadrant upside down" XFinder/Core/Snap/SnapLayout.swift \
  "'            let top = point.y >= tile.midY'" "'            let top = point.y < tile.midY'"
run "S9 the four-corner tile is gone from the row" XFinder/Core/Snap/SnapLayout.swift \
  "'    static let rowItems: [RowItem] = [.single(.leftHalf), .single(.rightHalf), .quarters,'" \
  "'    static let rowItems: [RowItem] = [.single(.leftHalf), .single(.rightHalf),'"
run "S5 a press with no window under it is still a candidate" XFinder/Core/Snap/SnapLayout.swift \
  "'            verdict = windowOrigin == nil ? .notWindowMove : .pending'" "'            verdict = .pending'"
run "S6 a text selection (pointer travels, window still) becomes a window drag" XFinder/Core/Snap/SnapLayout.swift \
  "'                verdict = .notWindowMove\n'" "'                verdict = .windowMove\n'"
run "S7 the verdict can change after it was decided" XFinder/Core/Snap/SnapLayout.swift \
  "'            guard verdict == .pending, let start = windowOrigin else { return verdict }'" \
  "'            guard let start = windowOrigin else { return verdict }'"

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
