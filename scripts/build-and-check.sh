#!/bin/sh
# Clean Debug build to /tmp (never to ./build or Desktop: codesign fails on
# "resource fork, Finder information" detritus there), then prove the new files
# were actually compiled. "BUILD SUCCEEDED" alone is not evidence: a source file
# missing a PBXFileReference is silently excluded and the build still succeeds.
set -e
ROOT=/Users/wolong/github/XFinder
OUT=/tmp/xfinder-clean-build

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT"

xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Debug \
  -derivedDataPath "$OUT/dd" \
  CONFIGURATION_BUILD_DIR="$OUT/out" \
  build > "$OUT/build.log" 2>&1 || { tail -40 "$OUT/build.log"; exit 1; }

echo "--- build result ---"
grep -c "error:" "$OUT/build.log" || true
grep -m1 "BUILD SUCCEEDED" "$OUT/build.log" || echo "NO SUCCESS LINE"

echo "--- compile log by name (gesture module) ---"
LIST=$(ls "$OUT/dd/Build/Intermediates.noindex/XFinder.build/Debug/XFinder.build/Objects-normal/arm64/XFinder.SwiftFileList" 2>/dev/null || true)
if [ -z "$LIST" ]; then
  LIST=$(find "$OUT/dd" -name "XFinder.SwiftFileList" -print -quit)
fi
echo "list: $LIST"
for f in GestureModel.swift GestureEngine.swift GestureController.swift GestureUIDisplay.swift MouseGesturesDetailView.swift L10n.swift L10nStore.swift; do
  if grep -q "$f" "$LIST"; then echo "  OK   $f"; else echo "  MISS $f"; fi
done

echo "--- archs ---"
lipo -archs "$OUT/out/XFinder.app/Contents/MacOS/XFinder"
