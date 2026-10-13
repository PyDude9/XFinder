#!/bin/sh
# Build a Release (arm64) XFinder.app, sign it with the self-signed "XFinder Dev" identity,
# verify it, and zip it with a checksum into dist/.  Does NOT publish anything.
#
# Self-signed means Gatekeeper WILL warn on a downloaded copy (no Developer ID, not notarized);
# the release notes say how to open it. Usage:  sh scripts/make-release.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" XFinder/Info.plist)
OUT=/tmp/xfinder-release
APP="$OUT/out/XFinder.app"
STAGE="$OUT/stage/XFinder.app"
DIST="$ROOT/dist"

security find-certificate -c "XFinder Dev" >/dev/null 2>&1 || { echo "FATAL: no 'XFinder Dev' certificate in the keychain"; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT/stage" "$DIST"
xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Release \
  -derivedDataPath "$OUT/dd" CONFIGURATION_BUILD_DIR="$OUT/out" build > "$OUT/build.log" 2>&1 || true
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$OUT/build.log" | head -5
grep -q "BUILD SUCCEEDED" "$OUT/build.log" || { echo "FATAL: Release build failed (log: $OUT/build.log)"; exit 1; }
[ -d "$APP" ] || { echo "FATAL: build produced no app"; exit 1; }

ditto --norsrc --noextattr --noacl "$APP" "$STAGE"
xattr -cr "$STAGE"

# Nested appex FIRST, from its own entitlements (see install-mouse-rebuild.sh for why), no --deep.
APPEX="$STAGE/Contents/PlugIns/XFinderSync.appex"
if [ -d "$APPEX" ]; then
  ENT="$OUT/appex.entitlements"
  cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
</dict>
</plist>
PLIST
  codesign --force --sign "XFinder Dev" --identifier com.xfinder.app.XFinderSync --entitlements "$ENT" "$APPEX"
  codesign -d --entitlements - "$APPEX" 2>&1 | grep -q app-sandbox || { echo "FATAL: appex lost its sandbox entitlement"; exit 1; }
fi
# B6: the Now Playing helper is nested code loaded by /usr/bin/perl — sign it like install-mouse-rebuild.sh does, and
# refuse to ship without it (the page would promise a feature whose helper is missing).
HELPER="$STAGE/Contents/Helpers/XFinderNowPlaying.dylib"
[ -f "$HELPER" ] || { echo "FATAL: Now Playing helper missing from the bundle"; exit 1; }
codesign --force --sign "XFinder Dev" "$HELPER"
codesign --force --sign "XFinder Dev" --identifier com.xfinder.app "$STAGE"
codesign --verify --deep --strict "$STAGE"

# Facts the release must satisfy — fail loudly rather than ship the wrong thing.
ARCHS=$(lipo -archs "$STAGE/Contents/MacOS/XFinder")
[ "$ARCHS" = "arm64" ] || { echo "FATAL: archs are '$ARCHS', expected arm64"; exit 1; }
APPVER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$STAGE/Contents/Info.plist")
[ "$APPVER" = "$VERSION" ] || { echo "FATAL: bundle version '$APPVER' != '$VERSION'"; exit 1; }
[ ! -e "$STAGE/Contents/MacOS/XFinder.debug.dylib" ] || { echo "FATAL: a debug dylib is in the release"; exit 1; }
APPEX_ID=$(codesign -dv --verbose=2 "$APPEX/Contents/MacOS/XFinderSync" 2>&1 | sed -n 's/^Identifier=//p')
[ "$APPEX_ID" = "com.xfinder.app.XFinderSync" ] || { echo "FATAL: appex identifier '$APPEX_ID'"; exit 1; }
for r in L10n.strings.json L10n.allowlist.json xfinder-claude-hook.zsh xfinder-claude-statusline.sh; do
  find "$STAGE/Contents/Resources" -name "$r" | grep -q . || { echo "FATAL: $r missing from the bundle"; exit 1; }
done

ZIP="$DIST/XFinder-$VERSION-arm64.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$STAGE" "$ZIP"
( cd "$DIST" && shasum -a 256 "XFinder-$VERSION-arm64.zip" > "XFinder-$VERSION-arm64.zip.sha256" )
echo "built: $ZIP ($(du -h "$ZIP" | cut -f1))"
cat "$ZIP.sha256"
