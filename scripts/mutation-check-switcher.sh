#!/bin/sh
# Inject the ⌘-Tab switcher's Phase C failure modes one at a time; every one must turn the suite RED.
# Same contract as mutation-check-notch.sh: a missing anchor or a mutant with no test result ABORTS (exit 2),
# sources are restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-switcher.XXXXXX)
FILES="XFinder/Core/WindowPreview/WindowPreviewStore.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='SwitcherPhaseC|WindowPreviewStore'
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
run "S1 the exclusion list is ignored" XFinder/Core/WindowPreview/WindowPreviewStore.swift \
  "'        !bundleID.isEmpty && excluded.contains(bundleID)'" "'        false'"
run "S2 a window straddling two screens belongs to neither" XFinder/Core/WindowPreview/WindowPreviewStore.swift \
  "'        w.bounds.intersects(screenCG)'" "'        screenCG.contains(w.bounds)'"
run "S3 flipping back lands on the first app, not the one we came from" XFinder/Core/WindowPreview/WindowPreviewStore.swift \
  "'            selectedIndex = Self.clampedSelection(appItems.firstIndex { \$0.bundleID == bundleID } ?? 0, count: appItems.count)'" "'            selectedIndex = 0'"
run "S4 the selection is not clamped after cards disappear" XFinder/Core/WindowPreview/WindowPreviewStore.swift \
  "'        count <= 0 ? 0 : min(max(0, index), count - 1)'" "'        index'"
run "S5 closing a group's representative keeps the dead window on the card" XFinder/Core/WindowPreview/WindowPreviewStore.swift \
  "'            guard item.windowIDs.contains(windowID) else { return item }'" "'            return item'"
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails); echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
