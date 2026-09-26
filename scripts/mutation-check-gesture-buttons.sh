#!/bin/sh
# Prove the PATCH v9.1 tests can fail, by injecting the exact bugs they claim to catch.
#
# A test that has never failed has proven nothing. Each mutation below restores one of
# the defects this pass fixed, or one of the mistakes the new code is most likely to
# acquire:
#
#   M1  the HID usage → `CGEvent` button-number conversion loses its `- 1`, so every
#       chip on the page is labelled one button too high
#   M2  `role(forEventButton:)` checks "reserved" **before** the stored assignment, so a
#       configuration that points the hold trigger at right click reports "click only"
#       while the engine is consuming that button
#   M3  the "missing button" prompt fires on every press instead of only on a press the
#       descriptor never declared — i.e. it becomes noise on every mouse
#   M4  the compact chip label re-derives the number itself instead of going through
#       `displayNumber(forButtonNumber:)`, the one place that offset is defined
#   M5  `MouseButtonRole.labelKey` returns a rendered Vietnamese sentence instead of a
#       store key — the leak shape that reached the English UI four times, and which no
#       literal sweep can see because the call site is `L10n.t(variable)`
#
# ── PATCH v10 mutations (M6–M11) ─────────────────────────────────────────────────────
#   M6  the vendor-page scan loses its usage-range guard, so the 1753 `0xFFFFFFFF`
#       sentinel elements on the Apple Internal Trackpad count as buttons
#   M7  `diagramStyle` always returns `.archetype`, so a one-button mouse is drawn with six
#       chips it does not have
#   M8  `MouseControlSlot.positionKey` returns a sentence instead of a store key
#   M9  the raw element dump stops listing the vendor page, so the evidence cannot be read
#   M10 the "missing hardware buttons" prompt fires without evidence
#   M11 the tilt switch reveals the arms but never enables them (the shipped bug)
#
# ── PATCH v10.1 mutations (M12–M13) ──────────────────────────────────────────────────
#   M12 the silhouette loses its thumb rest and becomes symmetric again — a pill, which is
#       the Magic Mouse shape the figure was reported as showing
#   M13 `isDeclared` collapses to "always true", so a chip the descriptor never declared is
#       drawn as a live control: the claim the press-to-record path exists to disprove
#
# ── House rules this script obeys (AGENTS.md) ────────────────────────────────────────
#   * every `mutate` names its target file and **aborts** when its anchor is missing,
#     rather than printing "inconclusive" and carrying on: a mutation that cannot be
#     applied is a broken gate, and a broken gate reads exactly like a passing one
#   * the pre-mutation copies are kept in a scratch dir and restored byte-identically,
#     with the hashes verified at the end
#   * **run this in the background** (`nohup sh scripts/… > /tmp/log 2>&1 &`) and poll
#     the log. A tool timeout that kills this script between `mutate` and `restore`
#     leaves the mutated source on disk, and it has gone into a shipped build once.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CAP="$ROOT/XFinder/Core/MouseGestures/DeviceCapabilityModel.swift"
LABEL_SRC="$ROOT/XFinder/Core/MouseGestures/GestureLabelStructure.swift"
# PATCH v10 added the vendor-page scan and the raw element dump, both of which live in the
# Foundation-only types file. It is in the mutation set for the same reason the other two
# are: a gate whose target cannot be mutated is a gate that cannot be proven to work.
TYPES_SRC="$ROOT/XFinder/Core/MouseGestures/DeviceCapabilityTypes.swift"
# v10 also fixed the tilt switch, which revealed the arms without enabling them. The contract
# for what that one switch writes is `TiltArmsVisibility`, in the pure UI-logic file.
UI_SRC="$ROOT/XFinder/Core/MouseGestures/GestureUIDisplay.swift"
SCRATCH=$(mktemp -d)
cp "$CAP" "$SCRATCH/DeviceCapabilityModel.swift"
cp "$LABEL_SRC" "$SCRATCH/GestureLabelStructure.swift"
cp "$TYPES_SRC" "$SCRATCH/DeviceCapabilityTypes.swift"
cp "$UI_SRC" "$SCRATCH/GestureUIDisplay.swift"
CAP_HASH=$(shasum -a 256 "$CAP" | cut -d' ' -f1)
LABEL_HASH=$(shasum -a 256 "$LABEL_SRC" | cut -d' ' -f1)
TYPES_HASH=$(shasum -a 256 "$TYPES_SRC" | cut -d' ' -f1)
UI_HASH=$(shasum -a 256 "$UI_SRC" | cut -d' ' -f1)

restore() {
  cp "$SCRATCH/DeviceCapabilityModel.swift" "$CAP"
  cp "$SCRATCH/GestureLabelStructure.swift" "$LABEL_SRC"
  cp "$SCRATCH/DeviceCapabilityTypes.swift" "$TYPES_SRC"
  cp "$SCRATCH/GestureUIDisplay.swift" "$UI_SRC"
}

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

# M1: usage 3 lands on event button 3 instead of 2, so every chip is off by one.
mutate "M1 usage→event conversion loses the offset" "$CAP" \
  '            .map { $0 - 1 }' \
  '            .map { $0 }'

# M2: "reserved" wins over the stored assignment, so the row contradicts the engine.
mutate "M2 reserved outranks the stored assignment" "$CAP" \
  '        if context.trigger.buttonNumber == button {
            if let assigned = GestureConfigStore.action(in: context.buttonActions, forEventButton: button),
               assigned.isAssigned, context.holdButtonSingleClickEnabled {
                return .holdTriggerWithAction(assigned)
            }
            return .holdTrigger
        }
        if context.scrollButtonEnabled, context.scrollButton == button { return .scrollButton }
        if button == 0 || button == 1 { return .reserved }' \
  '        if button == 0 || button == 1 { return .reserved }
        if context.trigger.buttonNumber == button {
            if let assigned = GestureConfigStore.action(in: context.buttonActions, forEventButton: button),
               assigned.isAssigned, context.holdButtonSingleClickEnabled {
                return .holdTriggerWithAction(assigned)
            }
            return .holdTrigger
        }
        if context.scrollButtonEnabled, context.scrollButton == button { return .scrollButton }'

# M3: the missing-button prompt becomes unconditional noise.
mutate "M3 missing-button prompt fires on every press" "$CAP" \
  '        return declared.contains(observed) ? nil : observed' \
  '        return observed'

# M4: the compact label re-derives the number, duplicating the offset that was wrong once.
mutate "M4 compact label re-derives the number" "$LABEL_SRC" \
  '        return ButtonLabel(key: numberedPrefixKey,
                           appendNumber: displayNumber(forButtonNumber: n))' \
  '        return ButtonLabel(key: numberedPrefixKey,
                           appendNumber: n)'

# M5: a role key becomes a rendered sentence, which the English UI would show in Vietnamese
# because the call site is L10n.t(variable) and no sweep can see it.
mutate "M5 role label emits a sentence instead of a key" "$CAP" \
  '        case .holdTrigger: return "Nút giữ"' \
  '        case .holdTrigger: return "Nút giữ để chạy cử chỉ"'

# ── PATCH v10 ─────────────────────────────────────────────────────────────────────────
# M6: the vendor scan loses its usage-range guard, so the 0xFFFFFFFF sentinel on the Apple
# Internal Trackpad counts as a button — 1753 of them, one numbered -1. This is the "873
# input-button elements" bug in its v10 form.
mutate "M6 vendor scan admits the 0xFFFFFFFF sentinel usage" "$TYPES_SRC" \
  '            && (1...vendorUsageMax).contains(el.usage) {' \
  '            && el.usage != -2 {'

# M7: the figure stops following the device, so a one-button Magic Mouse is drawn with six
# chips it does not have.
mutate "M7 figure always draws the six-position archetype" "$CAP" \
  '        return device.physical.buttons.count >= 3 ? .archetype : .generic' \
  '        return .archetype'

# M8: a position caption becomes a sentence. `MouseDiagramView` renders
# `L10n.t(slot.positionKey)`, so this shows verbatim in the English UI and no literal sweep
# can see it — the leak shape that reached this page four times.
mutate "M8 position caption emits a sentence instead of a key" "$CAP" \
  '        case .middle: return "Con lăn"' \
  '        case .middle: return "Con lăn xuống để bấm"'

# M9: the raw dump stops listing the vendor page, so the evidence behind "there are extra
# vendor controls" can no longer be checked.
mutate "M9 raw dump hides the vendor page" "$TYPES_SRC" \
  '            $0.usagePage == usagePageButton || $0.usagePage >= usagePageVendorDefined' \
  '            $0.usagePage == usagePageButton'

# M10: the "missing hardware buttons" prompt fires without evidence, i.e. on every mouse
# that simply has fewer buttons.
mutate "M10 under-report prompt fires without evidence" "$CAP" \
  '        return declared.count < MouseControlSlot.archetypeSlots.count && vendorControlCount > 0' \
  '        return declared.count < MouseControlSlot.archetypeSlots.count'

# M11: the tilt switch reveals the arms but leaves the engine switched off — the shipped bug,
# where an action assigned to a tilt direction could never fire.
mutate "M11 tilt switch reveals arms without enabling them" "$UI_SRC" \
  '        (available: reveal, enabled: reveal)' \
  '        (available: reveal, enabled: false)'

# ── PATCH v10.1 ───────────────────────────────────────────────────────────────────────
# M12: the outline goes back to being symmetric, i.e. a pill. The thumb rest — the left
# extreme sitting lower than the right one — is the only property that makes the figure read
# as a multi-button mouse, and the user's report was that the page showed a Magic Mouse.
mutate "M12 silhouette loses its thumb rest and becomes a pill" "$UI_SRC" \
  'Point(x: 0.000, y: 0.640),   // widest on the LEFT — lower half (thumb rest)' \
  'Point(x: 0.000, y: 0.280),   // widest on the LEFT — lower half (thumb rest)'

# M13: every control counts as declared, so a chip the descriptor never declared is drawn as
# a live control. That is the exact claim the Record path exists to disprove, and it is the
# rule that keeps the figure from asserting hardware nobody measured.
mutate "M13 undeclared chips are drawn as live controls" "$CAP" \
  '        switch self {
        case .notDeclared, .unknown: return false
        default: return true
        }' \
  '        return true'

restore
AFTER_HASH=$(shasum -a 256 "$CAP" | cut -d' ' -f1)
LABEL_AFTER=$(shasum -a 256 "$LABEL_SRC" | cut -d' ' -f1)
TYPES_AFTER=$(shasum -a 256 "$TYPES_SRC" | cut -d' ' -f1)
UI_AFTER=$(shasum -a 256 "$UI_SRC" | cut -d' ' -f1)
echo
if [ "$CAP_HASH" = "$AFTER_HASH" ] && [ "$LABEL_HASH" = "$LABEL_AFTER" ] \
   && [ "$TYPES_HASH" = "$TYPES_AFTER" ] && [ "$UI_HASH" = "$UI_AFTER" ]; then
  echo "source restored byte-identical: yes"
else
  echo "source restored byte-identical: NO — restore it from git"
fi
echo "post-restore suite: $(run_tests)"
rm -rf "$SCRATCH"
