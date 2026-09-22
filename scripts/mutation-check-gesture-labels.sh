#!/bin/sh
# Prove the new/changed gesture tests can fail, by injecting the exact bugs they
# claim to catch into a scratch copy of the symlinked model.
#
# A test that has never failed has proven nothing. Each mutation below restores
# one of the bugs this pass fixed:
#   M1  buttons named by invented physical anatomy again (the reported leak)
#   M2  a bare arrow heading with no button number ("tôi ko hiểu dùng nút nào")
#   M3  the old Mission Control Global mapping, which the user called useless
#   M4  tilt arms revealed by default on hardware that cannot fire them
#   M5  an interpolated button name built without the shared fragment
#
# Runs against a scratch file only; the real source is untouched, and the count is
# compared before/after so a "GREEN" result cannot be a silently-broken harness.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REAL="$ROOT/XFinder/Core/MouseGestures/GestureModel.swift"
SCRATCH=$(mktemp -d)
cp "$REAL" "$SCRATCH/GestureModel.swift"
REAL_HASH=$(shasum -a 256 "$REAL" | cut -d' ' -f1)

restore() { cp "$SCRATCH/GestureModel.swift" "$REAL"; }

run_tests() {
  (cd "$ROOT/Tests" && swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1)
}

fails() {
  (cd "$ROOT/Tests" && swift test 2>&1 | grep -cE "^Test Case .* failed")
}

echo "=== baseline (no mutation) ==="
restore
BASE=$(fails)
echo "failing test cases: $BASE"
[ "$BASE" -eq 0 ] || { echo "FAIL: baseline is not green"; exit 1; }

mutate() {
  NAME=$1; shift
  restore
  python3 - "$REAL" "$@" <<'EOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, encoding="utf-8").read()
if old not in src:
    print("COULD NOT APPLY MUTATION — the anchor moved", file=sys.stderr)
    sys.exit(2)
open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
EOF
  if [ $? -ne 0 ]; then
    echo "$NAME: HARNESS ERROR (anchor missing) — treat as inconclusive"
    restore
    return
  fi
  N=$(fails)
  if [ "$N" -gt 0 ]; then
    echo "$NAME: RED as expected ($N failing test cases)"
  else
    echo "$NAME: *** STAYED GREEN — the test does not catch this ***"
  fi
}

# M1: bring back the invented anatomy.
mutate "M1 invented physical button names" \
  'default: return "Nút \(n + 1)"' \
  'default: return "Nút hông sau — nút \(n + 1) (Button \(n))"'

# M2: heading without the held button.
mutate "M2 heading omits the held button" \
  'return "\(trigger.numberedName): \(hint)"' \
  'return motion'

# M3: the old Global mapping.
mutate "M3 Global reverts to Mission Control" \
  '.up: key(33, c | s), .down: key(30, c | s), .left: key(33, c), .right: key(30, c),' \
  '.up: key(126, ctrl), .down: key(125, ctrl), .left: key(123, ctrl), .right: key(124, ctrl),'

# M4: tilt arms shown by default.
mutate "M4 tilt revealed by default" \
  'var tiltAvailable = false' \
  'var tiltAvailable = true'

# M5: interpolated name without the shared fragment (the call-site assembly bug).
mutate "M5 button name drops the number offset" \
  'case .mouseButton(let n): return "Nút \(n + 1)"' \
  'case .mouseButton(let n): return "Nút \(n)"'

restore
AFTER_HASH=$(shasum -a 256 "$REAL" | cut -d' ' -f1)
echo
if [ "$REAL_HASH" = "$AFTER_HASH" ]; then
  echo "source restored byte-identical: yes"
else
  echo "source restored byte-identical: NO — restore it from git"
fi
echo "post-restore suite: $(run_tests)"
rm -rf "$SCRATCH"
