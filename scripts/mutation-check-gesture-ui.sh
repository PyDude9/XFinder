#!/bin/sh
# Mutation check: inject each bug a new test claims to catch, confirm the test
# goes RED, then restore the file byte-identical.
#
# A test that has never failed has proven nothing. Comments must use `#`.
set -e
cd "$(dirname "$0")/.."

SRC=XFinder/Core/MouseGestures/GestureUIDisplay.swift
BAK=/tmp/GestureUIDisplay.swift.bak
cp "$SRC" "$BAK"
restore_src() { cp "$BAK" "$SRC"; }
trap restore_src EXIT

total() {
  swift test --package-path Tests 2>&1 | grep -oE 'Executed [0-9]+ tests' | tail -1 | grep -oE '[0-9]+'
}

check() {
  desc="$1"
  printf '%s\n' "$desc"
  out="$(swift test --package-path Tests 2>&1 | grep -cE 'error: -\[XFinderLogicTests' || true)"
  if [ "$out" -gt 0 ]; then
    echo "  RED as expected ($out assertion(s) failed)"
  else
    echo "  !! STILL GREEN — this test cannot fail, it proves nothing"
  fi
  cp "$BAK" "$SRC"
}

# Bug 1: arrow click becomes a one-way radio instead of a toggle.
sed -i '' 's|current == clicked ? nil : clicked|clicked|' "$SRC"
check "BUG 1: click no longer toggles (radio behaviour)"

# Bug 2: switching app keeps the old arm highlighted (stale detail panel).
sed -i '' 's|static func afterProfileChange() -> GestureDirection? { nil }|static func afterProfileChange() -> GestureDirection? { .up }|' "$SRC"
check "BUG 2: profile change retains the stale selection"

# Bug 3: horizontal-scroll option removed from the tilt arms.
sed -i '' 's|^        isTilt(direction)$|        false|' "$SRC"
check "BUG 3: horizontal-scroll option removed from tilt arms"

# Bug 4: tie the scroll option to the wrong arm family (it must still be OFF
# for up/down/left/right even when the tilt check itself works).
sed -i '' 's|^        isTilt(direction)$|        !isTilt(direction)|' "$SRC"
check "BUG 4: horizontal-scroll offered on the drag arms instead"

# Bug 5: a drag arm loses the mouse-button it names, so the heading degrades to
# the bare motion word ("kéo xuống") — the exact wording the user rejected.
MODEL=XFinder/Core/MouseGestures/GestureModel.swift
# Backup OUTSIDE the repo: a `.bak` sitting next to Swift sources can be picked
# up by a stray build/glob and an interrupted run must not be able to strand it.
MODEL_BAK=/tmp/GestureModel.swift.bak
cp "$MODEL" "$MODEL_BAK"

# Restore on ANY exit, including `set -e` aborting mid-mutation.
restore_model() { cp "$MODEL_BAK" "$MODEL"; }
trap restore_model EXIT

python3 - "$MODEL" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
old = r'return "\(trigger.numberedName): \(hint)"'
assert old in s, "mutation target not found — fix the script, not the assertion"
open(p, 'w', encoding='utf-8').write(s.replace(old, 'return hint'))
PYEOF
printf '%s\n' "BUG 5: a direction heading drops the held mouse button"
out="$(swift test --package-path Tests 2>&1 | grep -cE 'error: -\[XFinderLogicTests' || true)"
if [ "$out" -gt 0 ]; then
  echo "  RED as expected ($out assertion(s) failed)"
else
  echo "  !! STILL GREEN — this test cannot fail, it proves nothing"
fi
restore_model

echo "--- restoring ---"
cp "$BAK" "$SRC"
diff -q "$BAK" "$SRC" && echo "restored byte-identical"
diff -q "$MODEL_BAK" "$MODEL" && echo "model restored byte-identical"
echo "--- final ---"
echo "Executed $(total) tests"
