#!/bin/sh
# XF-T33 Step 1 — geometry, no-upscale and keep-both regression mutations.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-image.XXXXXX)
FILES="XFinder/Core/Image/ImageTransformRules.swift XFinder/Core/Image/ImageRunner.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM
FILTER='ImageTransformRulesTests|ImageEngineTests'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
}
mutate() {
  python3 - "$1" "$2" "$3" <<'PY' || { echo "HARNESS ERROR: anchor not found in $1"; exit 2; }
import ast, sys
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
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}
R=XFinder/Core/Image/ImageTransformRules.swift
run "orientation 6/8 are not swapped" "$R" \
  "'return (orientation >= 5 ? height : width, orientation >= 5 ? width : height)'" \
  "'return (width, orientation >= 5 ? width : height)'"
run "crop is applied before target scale" "$R" \
  "'desiredScale = Double(width) / Double(cropPixels.width)'" \
  "'desiredScale = Double(width) / Double(upright.width)'"
run "no-upscale default is enforced" "$R" \
  "'let skipped = !allowUpscale && desiredScale > 1 ? SkipReason.wouldUpscale : nil'" \
  "'let skipped: SkipReason? = nil'"
P=XFinder/Core/Image/ImageRunner.swift
run "existing outputs and source are never overwritten" "$P" \
  "'renamex_np(staging.path, candidate.path, UInt32(RENAME_EXCL)) == 0'" \
  "'rename(staging.path, candidate.path) == 0'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
