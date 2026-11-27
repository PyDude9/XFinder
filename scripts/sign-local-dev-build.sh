#!/bin/sh
# Sign an already built bundle without installing or launching it.
set -eu

APP=${1:?Usage: sign-local-dev-build.sh /path/to/XFinder.app}
IDENTITY="XFinder Dev"
EXTENSION="$APP/Contents/PlugIns/XFinderSync.appex"
HELPER="$APP/Contents/Helpers/XFinderNowPlaying.dylib"

test -d "$APP"
test -f "$HELPER"
if [ -d "$EXTENSION" ]; then
  codesign --force --sign "$IDENTITY" --identifier com.xfinder.app.XFinderSync \
    --preserve-metadata=entitlements "$EXTENSION"
  codesign --verify --strict "$EXTENSION"
fi
codesign --force --sign "$IDENTITY" --identifier com.xfinder.app.nowplaying-adapter "$HELPER"
codesign --force --sign "$IDENTITY" --identifier com.xfinder.app \
  --preserve-metadata=entitlements "$APP"
codesign --verify --deep --strict "$APP"
codesign -d -r- "$APP"
