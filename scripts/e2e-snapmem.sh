#!/bin/sh
# SNAPMEM (XF-T20) live end-to-end on the INSTALLED XFinder: seed one leftHalf rule for a throw-away AppKit app, relaunch
# XFinder so it loads the rule, open the app, and measure with the window server (CGWindowList) that its window lands where
# the engine puts it; then switch the feature off and prove the window does NOT move (negative control). Exit 0 only when
# every check passed.
#
# Lessons this script exists to keep (2026-10-18, four false FAILs before the first honest PASS):
#   * phase a used to judge the FIRST frame after launch (~0.3 s) — before XFinder's replay (first window seen + 0.5 s) could
#     land. run-e2e.sh now polls until the expected frame appears and re-reads 3 s later to prove it stayed;
#   * the expected rect must apply the engine's own Stage Manager rule (SnapLayout.stageInset: off => 0, on =>
#     clamp(snapzones.stageInset ?? 68, 48, 140)) — macOS does not shrink visibleFrame for the strip;
#   * the owner's snapzones.remember is restored EXACTLY (the scratch version deleted it even when the owner had set it).
#
# Side effects, all undone at exit: two defaults keys of com.xfinder.app; XFinder is quit and reopened once (to load the
# seeded store) and brought forward once (to apply the switch-off); the throw-away app is unregistered from LaunchServices.
# It never moves any window but its own throw-away one, never installs anything, and refuses to run when the screen is
# locked, when the owner touched the keyboard or mouse in the last 20 s, or when XFinder is not running (never relaunch an
# app the owner closed).
set -u
cd "$(dirname "$0")/.."
ROOT=$(pwd)
D=com.xfinder.app
log() { echo "[snapmem-e2e $(date +%H:%M:%S)] $*"; }

locked=$(ioreg -n Root -d1 -a | /usr/bin/python3 -I -c 'import plistlib,sys; print(bool(plistlib.loads(sys.stdin.buffer.read()).get("CGSSessionScreenIsLocked", False)))' 2>/dev/null || echo UNKNOWN)
idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')
[ "$locked" = "False" ] || { log "REFUSED: screen locked or lock state unknown ($locked)"; exit 2; }
[ "${idle:-0}" -ge "${XF_E2E_MIN_IDLE:-20}" ] || { log "REFUSED: the owner is active (HID idle ${idle}s)"; exit 2; }
pgrep -x XFinder >/dev/null || { log "REFUSED: XFinder is not running — never relaunch an app the owner closed"; exit 2; }
defaults read $D snapzones.memory.v1 >/dev/null 2>&1 && { log "REFUSED: the owner already has remembered layouts — not overwriting them"; exit 2; }

# The owner's switch, restored exactly at exit (absent stays absent).
orig_remember=$(defaults read $D snapzones.remember 2>/dev/null || echo ABSENT)
B=${XF_E2E_DIR:-$(mktemp -d /tmp/xf-snapmem-e2e.XXXXXX)}
restore() {
  [ -x "$B/cleanup.sh" ] && /bin/sh "$B/cleanup.sh" >/dev/null 2>&1
  defaults delete $D snapzones.memory.v1 2>/dev/null
  case "$orig_remember" in
    ABSENT) defaults delete $D snapzones.remember 2>/dev/null ;;
    1|true|YES) defaults write $D snapzones.remember -bool true ;;
    *) defaults write $D snapzones.remember -bool false ;;
  esac
  log "restored: snapzones.remember=$(defaults read $D snapzones.remember 2>/dev/null || echo absent) (was $orig_remember), memory store removed"
}
trap 'restore' EXIT
trap 'exit 143' INT TERM

# ---- build the helpers and the throw-away app (nothing is written into the repo)
E=scripts/e2e-snapmem
mkdir -p "$B/bin" "$B/target/SnapMemTarget.app/Contents/MacOS"
for t in displays flip-rect read-frame send-quit; do
  swiftc -O -o "$B/bin/$t" "$E/src/$t.swift" 2>&1 | grep -E "error:" && { log "compile failed: $t"; exit 1; }
done
swiftc -O -o "$B/target/SnapMemTarget.app/Contents/MacOS/SnapMemTarget" "$E/target/main.swift" 2>&1 | grep -E "error:" && { log "compile failed: target"; exit 1; }
cp "$E/target/Info.plist" "$B/target/SnapMemTarget.app/Contents/Info.plist"
codesign -s - --force "$B/target/SnapMemTarget.app" >/dev/null 2>&1
cp "$E/run-e2e.sh" "$E/cleanup.sh" "$E/write-rule.py" "$B/"
log "built in $B"

# ---- seed: a leftHalf rule for the target on the set of displays attached now
"$B/bin/displays" > "$B/displays.json"
/usr/bin/python3 -I - "$B/displays.json" "$B/write-rule.py" "$B/rule.json" <<'EOF'
import json, subprocess, sys
displays = json.load(open(sys.argv[1]))
displays.sort(key=lambda d: (not d["isBuiltin"], d["uuid"]))     # the order SnapMemory.Arrangement uses
args = ["python3", sys.argv[2], "--out", sys.argv[3], "--bundle-id", "com.xfinder.e2e.snapmem", "--app-name", "SnapMem Target",
        "--display-uuid", ",".join(d["uuid"] for d in displays),
        "--display-name", ",".join(d["name"] for d in displays),
        "--pixel-width", ",".join(str(d["pixelWidth"]) for d in displays),
        "--pixel-height", ",".join(str(d["pixelHeight"]) for d in displays),
        "--is-builtin", ",".join("true" if d["isBuiltin"] else "false" for d in displays),
        "--primary-index", str([i for i, d in enumerate(displays) if d.get("isMain")][0]),
        "--layout-kind", "snap", "--layout-target", "leftHalf"]
r = subprocess.run(args, capture_output=True, text=True)
if r.returncode != 0: sys.exit(r.stderr)
EOF
[ -s "$B/rule.json" ] || { log "could not write the rule"; exit 1; }
defaults write $D snapzones.memory.v1 -data "$(xxd -p "$B/rule.json" | tr -d '\n')"
defaults write $D snapzones.remember -bool true
log "seeded a leftHalf rule for com.xfinder.e2e.snapmem; installed dylib md5 $(md5 -q /Applications/XFinder.app/Contents/MacOS/XFinder.debug.dylib 2>/dev/null || echo ?)"

# The store is read in init, so XFinder is reopened once.
osascript -e 'quit app "XFinder"' >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do pgrep -x XFinder >/dev/null || break; sleep 0.5; done
pgrep -x XFinder >/dev/null && { log "XFinder did not quit; aborting"; exit 1; }
open -a XFinder
sleep 15

rc=0
log "=== phase a (rule present, feature on) ==="
echo | /bin/sh "$B/run-e2e.sh" --phase a > "$B/phase-a.log" 2>&1 || rc=1
grep -E "^(PASS|FAIL|INVALID|ABORT)|stage manager|expected|actual" "$B/phase-a.log"
/usr/bin/log show --last 2m --predicate 'subsystem == "com.xfinder.app" AND category == "SnapMemory"' --style compact 2>/dev/null | grep -v "^Timestamp" | tail -4

# Let the controller's 2 s re-check happen before the switch goes off.
sleep 4
log "=== phase b (feature off — applied when XFinder becomes active) ==="
defaults write $D snapzones.remember -bool false
open -b $D; sleep 2
echo | /bin/sh "$B/run-e2e.sh" --phase b > "$B/phase-b.log" 2>&1 || rc=1
grep -E "^(PASS|FAIL|INVALID|ABORT)|expected|actual" "$B/phase-b.log"

[ "$rc" = "0" ] && log "RESULT: every check passed" || log "RESULT: a check failed or was invalid — logs in $B"
exit $rc
