#!/bin/sh
# Mutation check: inject each bug a new test claims to catch, confirm the test
# goes RED, then restore the file byte-identical.
#
# A test that has never failed has proven nothing. Comments must use `#`.
#
# ── REWRITTEN 2026-09-22 ────────────────────────────────────────────────────
# The previous version was GREEN on bugs 3 and 4 and then aborted with
# "mutation target not found" on bug 5. That is the rotting-script failure
# recorded in AGENTS.md: the `sed` targets (`isTilt(direction)` in
# GestureUIDisplay.swift, `\(trigger.numberedName): \(hint)` in GestureModel.swift)
# stopped existing when the heading vocabulary moved to semantic keys. A green
# suite over a no-op mutation proves nothing, so every target below is re-derived
# from the current source and the script now FAILS LOUDLY if a target is gone.
#
# The bugs are also re-chosen to match where the logic actually lives now:
#   * the arrow-click state machine — GestureUIDisplay.swift (unchanged)
#   * tilt classification          — GestureModel.swift (`GestureTriggerKind`)
#   * the heading vocabulary       — GestureModel.swift (titleKey/motionHintKey)
#   * capability-derived arms      — DeviceCapabilityModel.swift
set -e
cd "$(dirname "$0")/.."

SRC=XFinder/Core/MouseGestures/GestureUIDisplay.swift
MODEL=XFinder/Core/MouseGestures/GestureModel.swift
CAP=XFinder/Core/MouseGestures/DeviceCapabilityModel.swift
SRC_BAK=/tmp/GestureUIDisplay.swift.bak
MODEL_BAK=/tmp/GestureModel.swift.bak
CAP_BAK=/tmp/DeviceCapabilityModel.swift.bak

# Backups live OUTSIDE the repo: a `.bak` next to Swift sources can be picked up
# by a stray build glob.
cp "$SRC" "$SRC_BAK"
cp "$MODEL" "$MODEL_BAK"
cp "$CAP" "$CAP_BAK"

restore_all() {
  cp "$SRC_BAK" "$SRC"
  cp "$MODEL_BAK" "$MODEL"
  cp "$CAP_BAK" "$CAP"
}
# Restore on ANY exit, including `set -e` aborting mid-mutation, so an interrupted
# run can never strand a mutated source in the tree.
trap restore_all EXIT

# Run tests from Tests/ — from the repo root `swift test` reports 0 tests, which
# would make every mutation look green.
failures() {
  (cd Tests && swift test 2>&1) | grep -cE 'error: -\[XFinderLogicTests' || true
}

total() {
  (cd Tests && swift test 2>&1) | grep -oE 'Executed [0-9]+ tests' | tail -1 | grep -oE '[0-9]+'
}

check() {
  printf '%s\n' "$1"
  n="$(failures)"
  if [ "$n" -gt 0 ]; then
    echo "  RED as expected ($n assertion(s) failed)"
  else
    echo "  !! STILL GREEN — this test cannot fail, it proves nothing"
    exit 1
  fi
  restore_all
}

# Fail loudly rather than silently no-op'ing when a target has been refactored away.
mutate() {
  python3 - "$1" "$2" "$3" <<'PYEOF'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path, encoding='utf-8').read()
if old not in s:
    raise SystemExit("mutation target not found in %s — fix the script, not the assertion\n  target: %r" % (path, old))
open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PYEOF
}

# ── Bug 1: arrow click becomes a one-way radio instead of a toggle ──────────
mutate "$SRC" 'current == clicked ? nil : clicked' 'clicked'
check "BUG 1: click no longer toggles (radio behaviour)"

# ── Bug 2: switching app keeps the old arm highlighted ──────────────────────
mutate "$SRC" \
  'static func afterProfileChange() -> GestureDirection? { nil }' \
  'static func afterProfileChange() -> GestureDirection? { .up }'
check "BUG 2: profile change retains the stale selection"

# ── Bug 3: tilt is no longer recognised, so the scroll option disappears ────
# Target is the model's classifier — the single spelling both the engine and the
# diagram read (the old script pointed at a helper that no longer exists).
mutate "$MODEL" \
  '        direction == .tiltLeft || direction == .tiltRight' \
  '        false'
check "BUG 3: tilt stops being recognised (scroll option vanishes from tilt arms)"

# ── Bug 4: tilt classification inverted, so the drag arms offer pass-through ─
mutate "$MODEL" \
  '        direction == .tiltLeft || direction == .tiltRight' \
  '        !(direction == .tiltLeft || direction == .tiltRight)'
check "BUG 4: horizontal-scroll offered on the drag arms instead"

# ── Bug 5 (L1, the shipped regression): the per-arm caption carries the button
# number again, which is what made every arm read as "Button 3". ─────────────
mutate "$MODEL" \
  '        case .up:        return "Kéo lên"' \
  '        case .up:        return "Nút 3: kéo lên"'
check "BUG 5: an arm caption carries the held button number again (L1)"

# ── Bug 6 (L2): a heading key loses its translation, so the English page falls
# back to Vietnamese — the leak reported four times. Also proves the new
# store-key test can fail. ───────────────────────────────────────────────────
python3 - XFinder/Resources/L10n.strings.json <<'PYEOF'
import json, sys
p = sys.argv[1]
doc = json.loads(open(p, encoding='utf-8').read())
if 'Kéo sang trái' not in doc['entries']:
    raise SystemExit("mutation target 'Kéo sang trái' not found in the store — fix the script")
del doc['entries']['Kéo sang trái']
open(p, 'w', encoding='utf-8').write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
PYEOF
printf '%s\n' "BUG 6: a heading key loses its English translation (L2)"
n="$(failures)"
if [ "$n" -gt 0 ]; then
  echo "  RED as expected ($n assertion(s) failed)"
else
  echo "  !! STILL GREEN — this test cannot fail, it proves nothing"
  exit 1
fi
python3 scripts/add-gesture-l10n-entries.py > /dev/null

# ── Bug 7 (R3/D2): an unattributable descriptor's *absence* is treated as
# evidence, which greys out a working mouse and claims its hardware lacks a
# button it has. ────────────────────────────────────────────────────────────
mutate "$CAP" \
  '            if device.confidence != .verified { return .unknownUntilDetected }' \
  '            if false { return .unknownUntilDetected }'
check "BUG 7: a missing capability on an unattributable device is called unsupported"

echo "--- restoring ---"
restore_all
diff -q "$SRC_BAK" "$SRC" && echo "restored byte-identical: GestureUIDisplay.swift"
diff -q "$MODEL_BAK" "$MODEL" && echo "restored byte-identical: GestureModel.swift"
diff -q "$CAP_BAK" "$CAP" && echo "restored byte-identical: DeviceCapabilityModel.swift"

echo "--- final ---"
echo "Executed $(total) tests"
