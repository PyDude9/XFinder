#!/bin/sh
# Build → sign with the stable "XFinder Dev" identity → install to /Applications.
#
# Why not ad-hoc: TCC binds Accessibility to a code identity. Ad-hoc identity is
# the cdhash, so every rebuild silently loses the grant. Signing with the
# self-signed cert makes the Designated Requirement "identifier + cert subject",
# which survives rebuilds — grant it once and it sticks.
set -e
cd "$(dirname "$0")/.."

SRC=/tmp/xfinder-clean-build/out/XFinder.app
STAGE=/tmp/xf-final/XFinder.app

rm -rf /tmp/xf-final && mkdir -p /tmp/xf-final
ditto --norsrc --noextattr --noacl "$SRC" "$STAGE"
xattr -cr "$STAGE"

# Nested appex FIRST — signing the outer bundle --deep would invalidate it.
APPEX="$STAGE/Contents/PlugIns/XFinderSync.appex"
if [ -d "$APPEX" ]; then
  codesign --force --sign "XFinder Dev" --identifier com.xfinder.app.XFinderSync "$APPEX"
fi
codesign --force --deep --sign "XFinder Dev" --identifier com.xfinder.app "$STAGE"

pkill -x XFinder 2>/dev/null || true
rm -rf /Applications/XFinder.app
ditto --norsrc --noextattr --noacl "$STAGE" /Applications/XFinder.app
xattr -cr /Applications/XFinder.app

codesign --verify --deep --strict /Applications/XFinder.app
echo "--- designated requirement ---"
codesign -d -r- /Applications/XFinder.app 2>&1 | tail -3
echo "--- archs ---"
lipo -archs /Applications/XFinder.app/Contents/MacOS/XFinder.debug.dylib
