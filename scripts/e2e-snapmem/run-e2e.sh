#!/bin/sh
# run-e2e.sh — snap-memory e2e harness driver.
#
# usage:
#   sh run-e2e.sh --phase a
#   sh run-e2e.sh --phase b
#
# WHAT THIS SCRIPT DOES NOT DO (by design, per the harness brief):
#   - does not run git
#   - does not run xcodebuild on the XFinder project
#   - does not run any XFinder install script
#   - does not run `open xfinder://...`
#   - does not run `defaults write com.xfinder.app ...`
#   - does not touch the running XFinder app's windows directly
#   - does not launch anything except its OWN throw-away SnapMemTarget.app
#
# WHAT IT DOES:
#   - checks preconditions (screen unlocked, XFinder running, user idle >= 20s)
#   - phase a (checks A and C):
#       A: with the integrator having arranged a leftHalf SnapMemory rule
#          for com.xfinder.e2e.snapmem inside XFinder, opens the target app,
#          polls the INDEPENDENT read-frame (CGWindowList) measurement every
#          0.25s for up to 6s, and PASSes when the window's bounds equal the
#          left half of the main display's visible frame within 6pt.
#       C: positive control for the measurement itself — compares the
#          target's OWN self-reported frame (its FRAME log line, converted
#          from AppKit bottom-left space to CG top-left space) against
#          read-frame's independent CGWindowList reading, and requires them
#          to agree within 2pt. If A passes but C fails, the result of A is
#          not trustworthy.
#   - phase b (negative control, check B):
#       with the integrator having REMOVED the rule, relaunches the target
#       and confirms after 4s that the window is still at its launch
#       position (x=300 y=300 w=600 h=400 in AppKit space) within 6pt — a
#       negative that is informative (the window genuinely never moved)
#       rather than one that would pass vacuously.
#
# Exit code: 0 if every check PASSed, 1 if any FAILed or was INVALID.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
BIN_DIR="$SCRIPT_DIR/bin"
TARGET_APP="$SCRIPT_DIR/target/SnapMemTarget.app"
BUNDLE_ID="com.xfinder.e2e.snapmem"
TARGET_LOG="$SCRIPT_DIR/target.log"

READ_FRAME="$BIN_DIR/read-frame"
DISPLAYS="$BIN_DIR/displays"
SEND_QUIT="$BIN_DIR/send-quit"
FLIP_RECT="$BIN_DIR/flip-rect"

PASS_COUNT=0
FAIL_COUNT=0
INVALID_COUNT=0
TOTAL_COUNT=0

phase=""

while [ $# -gt 0 ]; do
    case "$1" in
        --phase)
            phase="$2"
            shift 2
            ;;
        --phase=*)
            phase="${1#--phase=}"
            shift
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [ "$phase" != "a" ] && [ "$phase" != "b" ]; then
    echo "usage: sh run-e2e.sh --phase a|b" >&2
    exit 2
fi

for tool in "$READ_FRAME" "$DISPLAYS" "$SEND_QUIT" "$FLIP_RECT" "$TARGET_APP/Contents/MacOS/SnapMemTarget"; do
    if [ ! -x "$tool" ]; then
        echo "ABORT: missing or non-executable: $tool" >&2
        echo "Build the harness first (displays, read-frame, send-quit, flip-rect, SnapMemTarget.app)." >&2
        exit 1
    fi
done

record_result() {
    # record_result <label> <PASS|FAIL|INVALID> <detail...>
    _label="$1"
    _status="$2"
    shift 2
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    case "$_status" in
        PASS) PASS_COUNT=$((PASS_COUNT + 1)) ;;
        FAIL) FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
        INVALID) INVALID_COUNT=$((INVALID_COUNT + 1)) ;;
    esac
    echo "$_status [$_label] $*"
}

echo "=== snap-memory e2e harness — phase $phase ==="
echo

#############################################
# Preconditions
#############################################

echo "--- preconditions ---"

# 1. Screen must not be locked. A locked screen makes window-server / AX
#    measurements meaningless. Read the actual boolean via plistlib against
#    ioreg's plist output, rather than grepping for the key's mere presence
#    (the key can be present with value false).
locked_value=$(/usr/bin/python3 -I -c '
import plistlib, subprocess, sys
try:
    data = subprocess.check_output(["ioreg", "-n", "Root", "-d1", "-a"])
    plist = plistlib.loads(data)
    print(bool(plist.get("CGSSessionScreenIsLocked", False)))
except Exception as e:
    print("ERROR", file=sys.stderr)
    print(e, file=sys.stderr)
    print("UNKNOWN")
')
if [ "$locked_value" = "UNKNOWN" ]; then
    echo "ABORT: could not determine screen lock state." >&2
    exit 1
fi
if [ "$locked_value" = "True" ]; then
    echo "ABORT: screen is locked (CGSSessionScreenIsLocked=true). Refusing to run." >&2
    exit 1
fi
echo "ok: screen not locked"

# 2. XFinder must be running.
if ! pgrep -x XFinder >/dev/null 2>&1; then
    echo "ABORT: XFinder is not running (pgrep -x XFinder found nothing)." >&2
    exit 1
fi
xfinder_pid=$(pgrep -x XFinder | head -1)
echo "ok: XFinder is running (pid $xfinder_pid)"

# 3. HID idle time must be >= 20s.
idle_seconds=$(ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
if [ -z "$idle_seconds" ]; then
    echo "ABORT: could not read HIDIdleTime from ioreg." >&2
    exit 1
fi
if [ "$idle_seconds" -lt 20 ]; then
    echo "ABORT: user is active (HID idle ${idle_seconds}s < 20s). Refusing to run." >&2
    exit 1
fi
echo "ok: HID idle ${idle_seconds}s (>= 20s)"
echo

#############################################
# Display geometry (needed for phase a's expected rect)
#############################################

echo "--- display geometry ---"
displays_json=$("$DISPLAYS")
echo "$displays_json"

main_rect=$(echo "$displays_json" | /usr/bin/python3 -I -c '
import json, sys
displays = json.load(sys.stdin)
for d in displays:
    if d.get("isMain"):
        vf = d["visibleFrame"]
        print(vf["x"], vf["y"], vf["width"], vf["height"])
        sys.exit(0)
sys.exit("no main display found")
')
if [ -z "$main_rect" ]; then
    echo "ABORT: could not determine main display visibleFrame." >&2
    exit 1
fi

main_x=$(echo "$main_rect" | awk '{print $1}')
main_y=$(echo "$main_rect" | awk '{print $2}')
main_w=$(echo "$main_rect" | awk '{print $3}')
main_h=$(echo "$main_rect" | awk '{print $4}')
echo "main display visibleFrame (CG top-left space, points): x=$main_x y=$main_y w=$main_w h=$main_h"

# Expected rect for a "leftHalf" snap, in CG top-left space (the same space
# read-frame's kCGWindowBounds reports in).
# The engine reserves the Stage Manager strip (SnapLayout.stageInset: off => 0; on => clamp(snapzones.stageInset ?? 68, 48, 140)),
# because macOS does not shrink visibleFrame for it. The first live runs expected x=0 w=864 and read x=48 w=840 as a FAIL —
# the window was exactly where the engine's rule puts it. Compute the expectation with the same rule, read from the same keys.
sm_on=$(defaults read com.apple.WindowManager GloballyEnabled 2>/dev/null || echo 0)
reserve=$(defaults read com.xfinder.app snapzones.reserveStage 2>/dev/null || echo 1)
custom=$(defaults read com.xfinder.app snapzones.stageInset 2>/dev/null || echo 68)
inset=$(/usr/bin/python3 -I -c "
sm, rs, c = '$sm_on', '$reserve', '$custom'
on = sm.strip() in ('1', 'true', 'YES')
res = rs.strip() not in ('0', 'false', 'NO')
print(0 if not (on and res) else min(max(float(c), 48), 140))")
echo "stage manager on=$sm_on reserve=$reserve custom=$custom => inset=$inset (engine rule SnapLayout.stageInset)"
expected_x=$(/usr/bin/python3 -I -c "print($main_x + $inset)")
expected_y=$main_y
expected_w=$(/usr/bin/python3 -I -c "print(($main_w - $inset)/2)")
expected_h=$main_h
echo "expected leftHalf rect (CG top-left space): x=$expected_x y=$expected_y w=$expected_w h=$expected_h"
echo

TOLERANCE=6

rects_close() {
    # rects_close <ax> <ay> <aw> <ah> <bx> <by> <bw> <bh> <tol> -> "yes"/"no"
    /usr/bin/python3 -I -c "
ax,ay,aw,ah,bx,by,bw,bh,tol = $1,$2,$3,$4,$5,$6,$7,$8,$9
ok = (abs(ax-bx) <= tol and abs(ay-by) <= tol and abs(aw-bw) <= tol and abs(ah-bh) <= tol)
print('yes' if ok else 'no')
"
}

#############################################
# Launch / quit / poll helpers
#############################################

launch_target() {
    echo "opening $TARGET_APP ..."
    open "$TARGET_APP"
}

quit_target_if_running() {
    if pgrep -f "SnapMemTarget.app/Contents/MacOS/SnapMemTarget" >/dev/null 2>&1; then
        echo "quitting SnapMemTarget via distributed notification ..."
        "$SEND_QUIT"
        _waited=0
        while pgrep -f "SnapMemTarget.app/Contents/MacOS/SnapMemTarget" >/dev/null 2>&1; do
            sleep 0.25
            _waited=$((_waited + 1))
            if [ "$_waited" -gt 20 ]; then
                echo "warning: SnapMemTarget did not quit within 5s" >&2
                break
            fi
        done
    fi
}

poll_until_nonempty() {
    # poll_until_nonempty <max_polls_at_0.25s> -> prints last JSON array line
    _max="$1"
    _i=0
    _last="[]"
    while [ "$_i" -lt "$_max" ]; do
        _last=$("$READ_FRAME" "$BUNDLE_ID")
        _count=$(echo "$_last" | /usr/bin/python3 -I -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null)
        if [ "${_count:-0}" -gt 0 ] 2>/dev/null; then
            echo "$_last"
            return 0
        fi
        sleep 0.25
        _i=$((_i + 1))
    done
    echo "$_last"
    return 0
}

# Phase a used to judge the FIRST frame the window server reported after launch (~0.2-0.5 s) — before XFinder's replay
# (first window seen + 0.5 s) could land, so a working feature read as FAIL. Poll until the window matches the expected rect
# (or the time runs out) and print the time series; the caller then re-reads after a pause to prove it STAYED.
poll_until_matches() {
    _max="$1"; _i=0; _last="[]"
    while [ "$_i" -lt "$_max" ]; do
        _last=$("$READ_FRAME" "$BUNDLE_ID")
        _r=$(extract_first_rect "$_last")
        if [ -n "$_r" ]; then
            echo "  t=$((_i * 250))ms rect: $_r" >&2
            _x=$(echo "$_r" | awk '{print $1}'); _y=$(echo "$_r" | awk '{print $2}'); _w=$(echo "$_r" | awk '{print $3}'); _h=$(echo "$_r" | awk '{print $4}')
            if [ "$(rects_close "$_x" "$_y" "$_w" "$_h" "$expected_x" "$expected_y" "$expected_w" "$expected_h" "$TOLERANCE")" = "yes" ]; then
                echo "$_last"; return 0
            fi
        fi
        sleep 0.25
        _i=$((_i + 1))
    done
    echo "$_last"
    return 0
}

extract_first_rect() {
    # extract_first_rect <json_array> -> "x y w h" of the first entry, or empty
    echo "$1" | /usr/bin/python3 -I -c "
import json, sys
d = json.load(sys.stdin)
if not d:
    sys.exit(0)
e = d[0]
print(e['x'], e['y'], e['width'], e['height'])
" 2>/dev/null
}

last_log_rect() {
    # last_log_rect -> "x y w h" (AppKit space) from the LAST "FRAME" or
    # "INIT" line in the target's log file, or empty if none found.
    if [ ! -f "$TARGET_LOG" ]; then
        return 0
    fi
    awk '/^(FRAME|INIT) /{line=$0} END{print line}' "$TARGET_LOG" \
        | sed -E 's/^(FRAME|INIT) //'
}

#############################################
# Phase A — positive check (A) + measurement cross-check (C)
#############################################

if [ "$phase" = "a" ]; then
    echo "--- phase a: positive check ---"
    echo
    echo "WAIT: integrator action required."
    echo "  Arrange a SnapMemory rule inside XFinder for bundle id"
    echo "    $BUNDLE_ID"
    echo "  with layout = leftHalf on the MAIN display (uuid from the"
    echo "  'display geometry' block printed above). See write-rule.py for"
    echo "  the JSON shape; how that JSON actually reaches XFinder's running"
    echo "  SnapMemory.Store is the integrator's call, not this script's."
    echo
    echo "  Make sure SnapMemTarget.app (bundle id $BUNDLE_ID) is NOT already"
    echo "  running before you continue (phase a will 'open' it fresh)."
    echo
    printf "Press Enter once the rule is in place and XFinder is ready: "
    read -r _ans

    quit_target_if_running
    rm -f "$TARGET_LOG"

    echo
    echo "launching target for phase a ..."
    launch_target

    echo "polling read-frame for up to 6s (0.25s interval) until the window matches the expected rect ..."
    frame_json=$(poll_until_matches 24)
    echo "read-frame result: $frame_json"
    echo "stability: re-reading after 3s (the move must STAY, an app re-asserting its own frame would show here) ..."
    sleep 3
    frame_json=$(poll_until_nonempty 4)
    echo "read-frame result after 3s: $frame_json"

    rect=$(extract_first_rect "$frame_json")
    if [ -z "$rect" ]; then
        record_result "A-positive-snap" INVALID "read-frame never reported an on-screen layer-0 window for $BUNDLE_ID within 6s — cannot judge the snap"
    else
        actual_x=$(echo "$rect" | awk '{print $1}')
        actual_y=$(echo "$rect" | awk '{print $2}')
        actual_w=$(echo "$rect" | awk '{print $3}')
        actual_h=$(echo "$rect" | awk '{print $4}')
        echo "actual rect (CG top-left space, via read-frame/CGWindowList): x=$actual_x y=$actual_y w=$actual_w h=$actual_h"
        echo "expected rect (CG top-left space): x=$expected_x y=$expected_y w=$expected_w h=$expected_h"
        close=$(rects_close "$actual_x" "$actual_y" "$actual_w" "$actual_h" "$expected_x" "$expected_y" "$expected_w" "$expected_h" "$TOLERANCE")
        if [ "$close" = "yes" ]; then
            record_result "A-positive-snap" PASS "window landed on leftHalf within ${TOLERANCE}pt (actual: x=$actual_x y=$actual_y w=$actual_w h=$actual_h; expected: x=$expected_x y=$expected_y w=$expected_w h=$expected_h)"
        else
            record_result "A-positive-snap" FAIL "window did NOT land on leftHalf within ${TOLERANCE}pt (actual: x=$actual_x y=$actual_y w=$actual_w h=$actual_h; expected: x=$expected_x y=$expected_y w=$expected_w h=$expected_h)"
        fi
    fi
    echo

    #############################################
    # Check C — measurement cross-check: the target's OWN self-reported
    # frame (from its log file, NSWindow.frame / AppKit bottom-left space,
    # converted here to CG top-left space via flip-rect) must agree with
    # read-frame's independent CGWindowList measurement within 2pt. This is
    # the positive control for the measurement apparatus itself: if these
    # two disagree, neither check A nor check B can be trusted, whatever
    # they report.
    #############################################

    echo "--- check C: measurement cross-check (target's own report vs read-frame) ---"
    log_rect=$(last_log_rect)
    if [ -z "$log_rect" ]; then
        record_result "C-measurement-agree" INVALID "target.log has no FRAME/INIT line to compare against ($TARGET_LOG)"
    elif [ -z "$rect" ]; then
        record_result "C-measurement-agree" INVALID "read-frame had no reading to compare against the target's own log"
    else
        log_x=$(echo "$log_rect" | awk '{print $1}')
        log_y=$(echo "$log_rect" | awk '{print $2}')
        log_w=$(echo "$log_rect" | awk '{print $3}')
        log_h=$(echo "$log_rect" | awk '{print $4}')
        flipped=$("$FLIP_RECT" "$log_x" "$log_y" "$log_w" "$log_h")
        flip_x=$(echo "$flipped" | awk '{print $1}')
        flip_y=$(echo "$flipped" | awk '{print $2}')
        flip_w=$(echo "$flipped" | awk '{print $3}')
        flip_h=$(echo "$flipped" | awk '{print $4}')
        echo "target's own report (AppKit space): x=$log_x y=$log_y w=$log_w h=$log_h"
        echo "target's own report (converted to CG top-left space): x=$flip_x y=$flip_y w=$flip_w h=$flip_h"
        echo "read-frame's independent report (CG top-left space): x=$actual_x y=$actual_y w=$actual_w h=$actual_h"
        agree=$(rects_close "$flip_x" "$flip_y" "$flip_w" "$flip_h" "$actual_x" "$actual_y" "$actual_w" "$actual_h" 2)
        if [ "$agree" = "yes" ]; then
            record_result "C-measurement-agree" PASS "target's self-report and read-frame's independent CGWindowList measurement agree within 2pt"
        else
            record_result "C-measurement-agree" FAIL "target's self-report and read-frame's independent measurement DISAGREE by more than 2pt — do not trust check A's result from this run"
        fi
    fi
    echo
fi

#############################################
# Phase B — negative control
#############################################

if [ "$phase" = "b" ]; then
    echo "--- phase b: negative control ---"
    echo
    echo "WAIT: integrator action required."
    echo "  REMOVE the SnapMemory rule inside XFinder for bundle id"
    echo "    $BUNDLE_ID"
    echo "  (however your build exposes removing a rule — this script does"
    echo "  not know or touch that mechanism)."
    echo
    printf "Press Enter once the rule has been removed: "
    read -r _ans

    quit_target_if_running
    rm -f "$TARGET_LOG"

    echo
    echo "launching target for phase b ..."
    launch_target

    # Baseline = the frame MEASURED right after launch (CGWindowList, includes the title bar). The first run compared
    # against a computed CONTENT rect and read the 32-pt title bar as "the window moved" — a harness bug, not XFinder.
    sleep 0.7
    base_json=$("$READ_FRAME" "$BUNDLE_ID")
    base_rect=$(extract_first_rect "$base_json")
    echo "baseline frame 0.7s after launch: $base_rect"
    echo "waiting 4s, then reading the window's frame again ..."
    sleep 4
    frame_json=$("$READ_FRAME" "$BUNDLE_ID")
    echo "read-frame result: $frame_json"

    rect=$(extract_first_rect "$frame_json")
    launch_x=$(echo "$base_rect" | awk '{print $1}')
    launch_y=$(echo "$base_rect" | awk '{print $2}')
    launch_w=$(echo "$base_rect" | awk '{print $3}')
    launch_h=$(echo "$base_rect" | awk '{print $4}')
    echo "expected (unmoved) = baseline (CG top-left space): x=$launch_x y=$launch_y w=$launch_w h=$launch_h"
    [ -z "$base_rect" ] && rect=""

    if [ -z "$rect" ]; then
        record_result "B-negative-control" INVALID "read-frame never reported an on-screen layer-0 window for $BUNDLE_ID after 4s — cannot judge the negative control"
    else
        actual_x=$(echo "$rect" | awk '{print $1}')
        actual_y=$(echo "$rect" | awk '{print $2}')
        actual_w=$(echo "$rect" | awk '{print $3}')
        actual_h=$(echo "$rect" | awk '{print $4}')
        echo "actual rect (CG top-left space): x=$actual_x y=$actual_y w=$actual_w h=$actual_h"
        unmoved=$(rects_close "$actual_x" "$actual_y" "$actual_w" "$actual_h" "$launch_x" "$launch_y" "$launch_w" "$launch_h" "$TOLERANCE")
        if [ "$unmoved" = "yes" ]; then
            record_result "B-negative-control" PASS "window stayed at its launch position within ${TOLERANCE}pt — no rule means no move, as expected (actual: x=$actual_x y=$actual_y w=$actual_w h=$actual_h)"
        else
            record_result "B-negative-control" FAIL "window MOVED even though no rule should apply (actual: x=$actual_x y=$actual_y w=$actual_w h=$actual_h; expected unmoved: x=$launch_x y=$launch_y w=$launch_w h=$launch_h) — either a stale rule is still applying, or XFinder is moving windows it should not"
        fi
    fi
    echo
fi

#############################################
# Summary
#############################################

echo "=== summary (phase $phase) ==="
echo "PASS: $PASS_COUNT   FAIL: $FAIL_COUNT   INVALID: $INVALID_COUNT   TOTAL: $TOTAL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ] || [ "$INVALID_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
