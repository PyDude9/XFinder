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

# Nested appex FIRST — `--deep` on the outer bundle would re-sign it with the
# OUTER identifier, collapsing com.xfinder.app.XFinderSync into com.xfinder.app.
# Two bundles sharing one identifier breaks LaunchServices/pluginkit registration
# and makes the appex crash on launch inside ImageIO's bundle-info lookup.
# So: sign every nested item explicitly, then the outer bundle WITHOUT --deep.
APPEX="$STAGE/Contents/PlugIns/XFinderSync.appex"
if [ -d "$APPEX" ]; then
  # Re-sign from our OWN entitlements file, never by letting codesign infer them.
  # The target builds with ENABLE_APP_SANDBOX=YES, so the appex is sandboxed at
  # build time; a plain `codesign --force` here DROPS those entitlements, and pkd
  # then refuses the plug-in ("Final plugin count: 5", no XFinder entry), which is
  # why the Finder menu never appeared. Keeping sandbox + user-selected-read-only
  # matters because the appex reads the Finder selection.
  ENT=/tmp/xf-appex.entitlements
  cat > "$ENT" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.files.user-selected.read-only</key><true/>
  <key>com.apple.security.get-task-allow</key><true/>
</dict>
</plist>
PLIST
  codesign --force --sign "XFinder Dev" --identifier com.xfinder.app.XFinderSync \
    --entitlements "$ENT" "$APPEX"
  APPEX_ID=$(codesign -dv --verbose=2 "$APPEX/Contents/MacOS/XFinderSync" 2>&1 | sed -n 's/^Identifier=//p')
  echo "--- appex identifier: $APPEX_ID ---"
  if [ "$APPEX_ID" != "com.xfinder.app.XFinderSync" ]; then
    echo "FATAL: nested appex lost its own identifier (got '$APPEX_ID')"; exit 1
  fi
  if ! codesign -d --entitlements - "$APPEX" 2>&1 | grep -q app-sandbox; then
    echo "FATAL: appex lost its sandbox entitlement; pkd will refuse the plug-in"; exit 1
  fi
  echo "--- appex sandbox entitlement: present ---"
fi
# B6: the Now Playing helper dylib (loaded into /usr/bin/perl) is nested code too — sign it
# explicitly, same reason as the appex, and refuse to ship a build that lost it: the Run Script
# phase that builds it is hand-authored in the pbxproj and would fail silently otherwise.
HELPER="$STAGE/Contents/Helpers/XFinderNowPlaying.dylib"
if [ -f "$HELPER" ]; then
  codesign --force --sign "XFinder Dev" --identifier com.xfinder.app.nowplaying-adapter "$HELPER"
  echo "--- now-playing helper signed: $(codesign -dv --verbose=2 "$HELPER" 2>&1 | sed -n 's/^Identifier=//p') ---"
else
  echo "FATAL: now-playing helper missing from the build ($HELPER) — the 'Build Now Playing helper' phase did not run"; exit 1
fi
codesign --force --sign "XFinder Dev" --identifier com.xfinder.app "$STAGE"

pkill -x XFinder 2>/dev/null || true
rm -rf /Applications/XFinder.app
ditto --norsrc --noextattr --noacl "$STAGE" /Applications/XFinder.app
xattr -cr /Applications/XFinder.app

# LaunchServices/pluginkit key off a plugin identifier, and every intermediate build
# directory (staging, /tmp, DerivedData everywhere) registers its own copy of the
# same identifier. With several live registrations the extension does not resolve
# and pluginkit prints nothing. Deregister the build/staging copies and register
# ONLY the installed bundle, so there is exactly one authority for the identifier.
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -u "$SRC"           >/dev/null 2>&1 || true
"$LSR" -u "$STAGE"         >/dev/null 2>&1 || true
"$LSR" -f /Applications/XFinder.app 2>/dev/null || true
# Deregistering the staging copy also removes the only live plug-in record, so
# re-add the installed appex explicitly. Without this, pluginkit lists nothing
# and Finder never offers the menu.
pluginkit -a /Applications/XFinder.app/Contents/PlugIns/XFinderSync.appex >/dev/null 2>&1 || true

codesign --verify --strict --verbose=1 /Applications/XFinder.app

# --deep on verify only checks the OUTER bundle, which is how the collapsed
# appex identifier stayed invisible. Verify each nested binary by name too.
echo "--- nested signature check ---"
PLUGINS=/Applications/XFinder.app/Contents/PlugIns
for appex in "$PLUGINS"/*.appex; do
  [ -d "$appex" ] || continue
  codesign --verify --strict "$appex"
  printf '  %s -> ' "$(basename "$appex")"
  codesign -dv --verbose=2 "$appex" 2>&1 | sed -n 's/^Identifier=//p'
done

echo "--- appex registered with pluginkit ---"
pluginkit -m -p com.apple.FinderSync -v 2>/dev/null | grep -i xfinder \
  || echo "  NOT registered (Finder right-click will not list XFinder; needs an enabled Finder extension)"

# The `!` prefix means registered-but-not-enabled; the user enables it in
# System Settings ▸ Login Items & Extensions ▸ Finder, which no app can do for
# them. Report the measured state instead of promising it works.
echo "--- appex registrations still naming a non-installed path (should be empty) ---"
"$LSR" -dump 2>/dev/null | awk '
  /^path:/ { p=$0 }
  /plugin Identifiers: *com\.xfinder\.app\.XFinderSync/ { print p }
' | sort -u | grep -v "/Applications/XFinder.app" || true

echo "--- designated requirement ---"
codesign -d -r- /Applications/XFinder.app 2>&1 | tail -3
echo "--- archs ---"
lipo -archs /Applications/XFinder.app/Contents/MacOS/XFinder.debug.dylib

echo "--- launch app ---"
pkill -9 XFinder 2>/dev/null || true
sleep 1
open /Applications/XFinder.app
echo "app launched from /Applications/XFinder.app"
