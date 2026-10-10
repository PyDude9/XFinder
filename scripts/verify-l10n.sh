#!/bin/sh
# Full acceptance run for the language work.
#
# Prints a measured result for every claim, because "it compiles" has never been
# evidence for anything in this project — a file missing from the pbxproj builds
# fine and renders nothing, and a missing translation builds fine and renders
# Vietnamese in an English UI.
set -e
cd "$(dirname "$0")/.."

echo "=== 1. Store is internally consistent (structure, scope, coverage) ==="
python3 scripts/check-l10n-coverage.py

echo
echo "=== 2. Every wrapped literal in the app resolves to a translation ==="
python3 scripts/audit-l10n-literals.py 2>&1 | sed -n '1,3p'

echo
echo "=== 2b. No Vietnamese left outside \\( ) in an interpolated string (leak shape #7) ==="
python3 scripts/audit-l10n-interpolations.py

echo
echo "=== 3. Reachability audit: Vietnamese-returning declarations in Core/ ==="
python3 scripts/audit-l10n-reachability.py 2>&1 | tail -3

echo
echo "=== 4. Tests ==="
# From Tests/. From the repo root `swift test` reports "0 tests", which the old
# version of this script did — and a green count over zero tests reads exactly
# like protection.
(cd Tests && swift test 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -1)

echo
echo "=== 5. Build, so the bundle below describes THIS tree ==="
# The script used to read /tmp/xfinder-l10n-build without rebuilding it, so it kept
# reporting a bundle from an earlier run — measured: it printed a 119475-byte store
# while the source on disk was 127776 bytes. Reading a stale artefact is how a green
# result stops describing the tree in front of you.
OUT=/tmp/xfinder-l10n-build
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Debug \
  -derivedDataPath "$OUT/dd" CONFIGURATION_BUILD_DIR="$OUT/out" build \
  > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log"; exit 1; }
grep -m1 "BUILD SUCCEEDED" "$OUT/build.log" || { echo "FAIL: no success line"; exit 1; }

ls -la "$OUT/out/XFinder.app/Contents/Resources/L10n.strings.json"
# The built store must match the source, byte for byte. A size comparison catches
# the whole class of "built an older revision and reported on it".
SRC="XFinder/Resources/L10n.strings.json"
if cmp -s "$SRC" "$OUT/out/XFinder.app/Contents/Resources/L10n.strings.json"; then
  echo "built store matches source: yes"
else
  echo "FAIL: the bundled store differs from $SRC"
  exit 1
fi

echo
echo "=== 6. New sources present in the compile log by name ==="
grep -E "L10nStore|L10n\.swift|GestureLabelStructure|DeviceCapability" \
  /tmp/xfinder-l10n-build/dd/Build/Intermediates.noindex/XFinder.build/Debug/XFinder.build/Objects-normal/arm64/XFinder.SwiftFileList

echo
echo "=== 7. Removed dictionaries are gone from the compile log ==="
if grep -qE "L10nDB|L10nStrings" \
  /tmp/xfinder-l10n-build/dd/Build/Intermediates.noindex/XFinder.build/Debug/XFinder.build/Objects-normal/arm64/XFinder.SwiftFileList; then
  echo "FAIL: a deleted dictionary is still being compiled"
  exit 1
else
  echo "absent — the four-store split is gone"
fi

echo
echo "=== 8. Installed binary: arch + signature + Event Tap ==="
lipo -archs /Applications/XFinder.app/Contents/MacOS/XFinder.debug.dylib
codesign -d -r- /Applications/XFinder.app 2>&1 | grep designated
python3 - <<'PYEOF'
import plistlib, pathlib
d = plistlib.loads((pathlib.Path.home()/'Library/Preferences/com.xfinder.app.plist').read_bytes())
print("AppLanguage:", d.get('AppLanguage'))
print("lastTapState:", d.get('mouseGestures.lastTapState'))
PYEOF

echo
echo "=== 9. English store contains no Vietnamese-only render fallbacks ==="
python3 - <<'PYEOF'
import json
from pathlib import Path
store = json.loads(Path("XFinder/Resources/L10n.strings.json").read_text(encoding="utf-8"))["entries"]
import re
VI = re.compile(r"[À-ỹĐđ]")
allow = set(json.loads(Path("XFinder/Resources/L10n.allowlist.json").read_text(encoding="utf-8"))["sameByDesign"])
leaks = [vi for vi, e in store.items() if VI.search(e["en"]) and e["en"] not in allow]
print(f"English values still containing Vietnamese characters: {len(leaks)}")
for l in leaks[:10]:
    print("   ", repr(l), "->", repr(store[l]["en"]))
PYEOF
