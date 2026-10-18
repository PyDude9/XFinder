#!/bin/sh
# cleanup.sh — tear down the snap-memory e2e harness's throw-away app.
#
# Does three things, in order:
#   1. Quits SnapMemTarget.app via the distributed notification it listens
#      for (com.xfinder.e2e.snapmem.quit) — never SIGKILL, so its own
#      quit-notification path is exercised instead of being bypassed.
#   2. Waits briefly for the process to actually exit.
#   3. Unregisters the bundle from LaunchServices with lsregister -u, so a
#      throw-away harness app does not leave a stale "com.xfinder.e2e.snapmem"
#      registration behind (the documented XFinder trap: dead LaunchServices
#      registrations from old build/staging directories accumulate and can
#      block resolution of a real app's identifier later).
#
# Touches nothing belonging to XFinder or the user: only the harness's own
# bundle id and process.

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
BIN_DIR="$SCRIPT_DIR/bin"
TARGET_APP="$SCRIPT_DIR/target/SnapMemTarget.app"
SEND_QUIT="$BIN_DIR/send-quit"
TARGET_LOG="$SCRIPT_DIR/target.log"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "=== snap-memory e2e harness cleanup ==="

if pgrep -f "SnapMemTarget.app/Contents/MacOS/SnapMemTarget" >/dev/null 2>&1; then
    if [ -x "$SEND_QUIT" ]; then
        echo "quitting SnapMemTarget via distributed notification com.xfinder.e2e.snapmem.quit ..."
        "$SEND_QUIT"
    else
        echo "warning: $SEND_QUIT not found/executable; cannot send quit notification" >&2
    fi

    _waited=0
    while pgrep -f "SnapMemTarget.app/Contents/MacOS/SnapMemTarget" >/dev/null 2>&1; do
        sleep 0.25
        _waited=$((_waited + 1))
        if [ "$_waited" -gt 40 ]; then
            echo "warning: SnapMemTarget did not quit within 10s of the notification" >&2
            break
        fi
    done

    if ! pgrep -f "SnapMemTarget.app/Contents/MacOS/SnapMemTarget" >/dev/null 2>&1; then
        echo "ok: SnapMemTarget has quit"
    fi
else
    echo "ok: SnapMemTarget was not running"
fi

if [ -x "$LSREGISTER" ]; then
    if [ -d "$TARGET_APP" ]; then
        echo "unregistering $TARGET_APP from LaunchServices ..."
        "$LSREGISTER" -u "$TARGET_APP"
        echo "ok: lsregister -u issued for $TARGET_APP"
    else
        echo "note: $TARGET_APP does not exist on disk; skipping lsregister -u"
    fi
else
    echo "warning: lsregister not found at the expected path: $LSREGISTER" >&2
fi

# Sanity check: confirm no LaunchServices entry remains for our bundle id.
remaining=$("$LSREGISTER" -dump 2>/dev/null | grep -c "com.xfinder.e2e.snapmem" || true)
echo "LaunchServices entries still mentioning com.xfinder.e2e.snapmem: ${remaining:-unknown}"
if [ "${remaining:-0}" != "0" ]; then
    echo "note: this can include the bundle id string appearing in the dump for other reasons;" >&2
    echo "      if entries persist across multiple cleanup runs, inspect with:" >&2
    echo "      $LSREGISTER -dump | grep -B2 -A10 com.xfinder.e2e.snapmem" >&2
fi

if [ -f "$TARGET_LOG" ]; then
    echo "removing target log: $TARGET_LOG"
    rm -f "$TARGET_LOG"
fi

echo "=== cleanup done ==="
