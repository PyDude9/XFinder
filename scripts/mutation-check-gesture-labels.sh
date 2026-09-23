#!/bin/sh
# Prove the new/changed gesture tests can fail, by injecting the exact bugs they
# claim to catch into a scratch copy of the symlinked model.
#
# A test that has never failed has proven nothing. Each mutation below restores
# one of the bugs this pass fixed:
#   M1  buttons named by invented physical anatomy again (the reported leak)
#   M2  a direction heading losing its key vocabulary
#   M3  a Global that is useless in a text editor. The **first** version sent
#       Mission Control as `⌃↑⌃↓` and the user called it "hơi vô dụng" — measured
#       cause: their own mouse already binds Mission Control. The **second** sent the
#       browser "next/previous item" pair (`⌘⇧]`/`⌘⇧[`), which means *nothing* in an
#       editor, i.e. most of their day. The **third** sent `⌃←`/`⌃→` for Spaces, which
#       are unbound on macOS 27 and produced round 7's "recognised but does nothing".
#       The mutation puts the unbound `⌃↑` back: a regression only the exact-keystroke
#       and system-action tests can see.
#       (Re-anchored three times now; each time the script reported HARNESS ERROR rather
#       than a false green, which is the behaviour the AGENTS.md rotting-anchor rule
#       exists to produce.)
#   M4  tilt arms revealed by default on hardware that cannot fire them
#   M5  the button number losing its macOS→user offset (0 must read "Nút 1")
#
# ── RE-ANCHORED 2026-09-22 ──────────────────────────────────────────────────
# M1, M2 and M5 had "anchor moved" (HARNESS ERROR) after the model stopped
# returning display strings. That is the rotting-script failure recorded in
# AGENTS.md: the anchors pointed at `GestureModel.swift` sentences that no longer
# exist. An inconclusive mutation is not a passing one, so each is re-anchored at
# wherever the behaviour actually lives now:
#   * M1/M5 — the numbered button name moved to `L10n.t(_ key: ButtonKey)` in
#             `Core/L10n.swift`, because numbering is a *rendering* concern.
#   * M2    — the heading is now assembled from `titleKey` + `motionHintKey`, so
#             the mutation drops the button half from the composed sentence.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REAL="$ROOT/XFinder/Core/MouseGestures/GestureModel.swift"
LABEL_SRC="$ROOT/XFinder/Core/MouseGestures/GestureLabelStructure.swift"
SCRATCH=$(mktemp -d)
cp "$REAL" "$SCRATCH/GestureModel.swift"
cp "$LABEL_SRC" "$SCRATCH/GestureLabelStructure.swift"
REAL_HASH=$(shasum -a 256 "$REAL" | cut -d' ' -f1)
LABEL_HASH=$(shasum -a 256 "$LABEL_SRC" | cut -d' ' -f1)

restore() { cp "$SCRATCH/GestureModel.swift" "$REAL"; cp "$SCRATCH/GestureLabelStructure.swift" "$LABEL_SRC"; }

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
  TARGET=$1; shift
  restore
  python3 - "$TARGET" "$@" <<'EOF'
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

# M1: bring back the invented anatomy. Anchored in GestureLabelStructure.swift —
# the Foundation-only file the test package can actually compile. The previous
# anchor was in L10n.swift, which imports SwiftUI, so this mutation stayed GREEN
# and the harness reported protection it did not have.
mutate "M1 invented physical button names" "$LABEL_SRC" \
  '        default: return nil' \
  '        default: return "Nút hông sau — nút \(n) (Button \(n - 1))"'

# M2: the heading loses the button half, which is what made the arms unreadable
# ("tôi ko hiểu dùng nút nào của chuột với mũi tên").
mutate "M2 heading omits the held button" "$LABEL_SRC" \
  '                if let named = ButtonLabelStructure.namedKey(forButtonNumber: n) {' \
  '                if false, let named = ButtonLabelStructure.namedKey(forButtonNumber: n) {'

# M3: Global's vertical arms revert to a *useless* mapping. Three versions of this
# row have shipped and each was replaced for a measured reason:
#   1. `⌃↑`/`⌃↓` for Mission Control — the user called it "hơi vô dụng" because their
#      MX Master 3 already binds Mission Control to its thumb button.
#   2. `⌘⇧]`/`⌘⇧[` for the browser "next/previous item" pair — means *nothing* in an
#      editor, i.e. most of their day.
#   3. `⌃←`/`⌃→` for Spaces — **unbound on macOS 27** (ids 79–82 are `enabled` with no
#      `value`), which produced round 7's "recognised but does nothing".
# The mutation re-injects (1) — the Mission Control *keystroke* that this pass replaced
# with a system event. It is the sharpest form of the bug: the row still reads
# "Mission Control" and now sends a key nothing listens for.
# Re-anchored 2026-09-22 (third time) against the system-action declaration. The script
# reports HARNESS ERROR rather than a false green when this anchor moves, which is the
# behaviour the AGENTS.md rotting-anchor rule exists to produce.
mutate "M3 Global reverts to the unbound ⌃↑ keystroke" "$REAL" \
  '                              up: .convention(.missionControl, GestureSystemAction.missionControl),' \
  '                              up: .convention(.missionControl, GestureShortcut(key: GestureKeyCode.upArrow, flags: GestureShortcut.control)),'

# M4: tilt arms shown by default.
mutate "M4 tilt revealed by default" "$REAL" \
  'var tiltAvailable = false' \
  'var tiltAvailable = true'

# M5: the button number loses its macOS→user offset, so macOS button 0 renders as
# "Nút 0" and every number on the page is off by one.
mutate "M5 button name drops the number offset" "$LABEL_SRC" \
  '    static func displayNumber(forButtonNumber n: Int) -> Int { n + 1 }' \
  '    static func displayNumber(forButtonNumber n: Int) -> Int { n }'

restore
AFTER_HASH=$(shasum -a 256 "$REAL" | cut -d' ' -f1)
LABEL_AFTER=$(shasum -a 256 "$LABEL_SRC" | cut -d' ' -f1)
echo
if [ "$REAL_HASH" = "$AFTER_HASH" ] && [ "$LABEL_HASH" = "$LABEL_AFTER" ]; then
  echo "source restored byte-identical: yes"
else
  echo "source restored byte-identical: NO — restore it from git"
fi
echo "post-restore suite: $(run_tests)"
rm -rf "$SCRATCH"
