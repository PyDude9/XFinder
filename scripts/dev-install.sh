#!/bin/zsh
# XFinder dev install — keeps macOS permissions across rebuilds.
#
# THE PROBLEM
# macOS grants Accessibility / Screen Recording to a *code identity*, not to a
# path. With the default ad-hoc signature that identity is the cdhash, which
# changes on every build. Measured:
#
#     prog1 cdhash = 2c616111f66f026531b71db2d8f7ca33d381a4ee
#     prog2 cdhash = 368f37901b6551d0992150c65f956f302a3086ef
#
# ...for two binaries signed with the SAME identifier. So every rebuild looks
# like a brand-new app and the grants are forgotten. SIP is enabled, so writing
# TCC.db directly is not possible, and `tccutil` can only *reset*, never grant.
#
# THE FIX
# Sign with a self-signed certificate. The designated requirement then becomes
# "identifier + certificate subject", which is stable across rebuilds, so the
# permission sticks. Run to a fixed install path so the app is always the same
# bundle to the system.
#
# ONE-TIME SETUP (needs the GUI — a cert cannot be created non-interactively):
#   1. Open Keychain Access
#   2. Menu: Keychain Access ▸ Certificate Assistant ▸ Create a Certificate…
#   3. Name: XFinder Dev
#      Identity Type: Self Signed Root
#      Certificate Type: Code Signing        ← must be this
#      Tick "Let me override defaults", then accept the rest.
#   4. Re-run this script.
#
# Then grant Accessibility + Screen Recording ONCE and they survive every build.

set -euo pipefail

CERT_NAME="XFinder Dev"
APP_NAME="XFinder.app"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build"
SRC="$BUILD_DIR/$APP_NAME"
DEST="/Applications/$APP_NAME"

echo "▸ Building (Debug)…"
cd "$(dirname "$0")/.."
xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Debug build \
  2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | grep -v "DVTPlugIn\|CoreSimulator" || true

if [[ ! -d "$SRC" ]]; then
  echo "✗ Build output not found at $SRC" >&2
  exit 1
fi

# Quit the running copy so the bundle can be replaced and relaunched cleanly.
if pgrep -x XFinder >/dev/null; then
  echo "▸ Quitting running XFinder…"
  pkill -x XFinder || true
  sleep 1
fi

if security find-certificate -c "$CERT_NAME" >/dev/null 2>&1; then
  echo "▸ Signing with '$CERT_NAME' (stable identity — permissions persist)…"
  # --force replaces the ad-hoc signature Xcode just applied.
  # --deep covers any future embedded helpers/extensions.
  codesign --force --deep --sign "$CERT_NAME" \
           --identifier com.xfinder.app \
           --options runtime "$SRC" 2>/dev/null \
    || codesign --force --deep --sign "$CERT_NAME" \
                --identifier com.xfinder.app "$SRC"
  STABLE=1
else
  echo "⚠ Certificate '$CERT_NAME' not found — falling back to ad-hoc."
  echo "  Permissions WILL reset on each rebuild until you create it."
  echo "  See the ONE-TIME SETUP comment at the top of this script."
  STABLE=0
fi

echo "▸ Installing to $DEST…"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "▸ Launching…"
open "$DEST"

echo
if [[ "$STABLE" == "1" ]]; then
  echo "✓ Installed with a stable signature."
  echo "  Grant Accessibility + Screen Recording once; later builds keep them."
  echo "  (If macOS still asks again, remove the old XFinder entry in"
  echo "   System Settings ▸ Privacy & Security first — it holds the old identity.)"
else
  echo "✓ Installed (ad-hoc). Create the certificate to stop re-granting."
fi
