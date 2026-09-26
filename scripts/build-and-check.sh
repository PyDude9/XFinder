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
# Files added in the "one map" pass: `GestureMap.swift` is the resolver the page AND
# the engine read, and the three view files are the Mac-Mouse-Fix-style UI. Every one
# needs four pbxproj entries, and a missing `PBXFileReference` excludes a file from the
# compilation *silently* — which is why this checks by name instead of trusting the
# build's exit code.
GESTURE_FILES="GestureModel.swift GestureEngine.swift GestureController.swift GestureUIDisplay.swift
MouseGesturesDetailView.swift MouseDiagramView.swift GestureDetailPanel.swift
L10n.swift L10nStore.swift DeviceCapability.swift DeviceCapabilityTypes.swift
DeviceCapabilityModel.swift GestureLabelStructure.swift GestureMap.swift
GestureArmView.swift GestureActionPicker.swift GestureActivityPanel.swift
GestureButtonList.swift
SpaceBinding.swift
ConnectedDeviceBattery.swift BatteryProvider.swift MacPowerSourceProvider.swift
MagicBatteryReader.swift BluetoothBatteryReader.swift BatteryStore.swift
BatteryViews.swift PermissionManager.swift
PreviewItem.swift ScreenCaptureProvider.swift SpecialProviders.swift
WindowPreviewStore.swift PreviewOverlayWindow.swift LiquidGlassView.swift
WindowPreviewComponents.swift LiquidGlassTokens.swift DockLayerController.swift
VoiceProtocols.swift AudioCapture.swift VoiceHotkeyManager.swift
AppleSpeechProvider.swift WhisperKitProvider.swift OllamaCorrectionProvider.swift
TypingSink.swift VoiceGhostOverlay.swift VoiceManager.swift VoiceDetailView.swift
MenuBarEngine.swift MenuBarEngineFactory.swift LegacyLengthEngine.swift
NativeVisibilityEngine.swift NativeVisibilityBridge.swift AccessibilityMenuBarInventory.swift"
for f in $GESTURE_FILES; do
  if grep -q "$f" "$LIST"; then echo "  OK   $f"; else echo "  MISS $f"; fi
done

# A resource is not compiled, so it never appears in the SwiftFileList: check the
# built bundle directly. A missing translation store makes the whole app run in
# Vietnamese with a single stderr line, and no compile check would notice.
echo "--- bundled resources ---"
for r in L10n.strings.json L10n.allowlist.json; do
  if [ -f "$OUT/out/XFinder.app/Contents/Resources/$r" ]; then
    echo "  OK   $r ($(wc -c < "$OUT/out/XFinder.app/Contents/Resources/$r") bytes)"
  else
    echo "  MISS $r"
  fi
done

echo "--- archs ---"
lipo -archs "$OUT/out/XFinder.app/Contents/MacOS/XFinder"

echo "--- code sign with XFinder Dev ---"
if security find-identity -p codesigning -v | grep -q "XFinder Dev"; then
  codesign --force --deep --sign "XFinder Dev" "$OUT/out/XFinder.app" 2>/dev/null || codesign --force --deep --sign - "$OUT/out/XFinder.app"
  echo "signed with XFinder Dev or ad-hoc"
else
  codesign --force --deep --sign - "$OUT/out/XFinder.app"
  echo "signed ad-hoc"
fi

echo "--- deploy to /Applications and launch ---"
pkill -9 XFinder 2>/dev/null || true
sleep 1
rm -rf /Applications/XFinder.app
ditto "$OUT/out/XFinder.app" /Applications/XFinder.app
xattr -cr /Applications/XFinder.app
if security find-identity -p codesigning -v | grep -q "XFinder Dev"; then
  codesign --force --deep --sign "XFinder Dev" /Applications/XFinder.app 2>/dev/null || codesign --force --deep --sign - /Applications/XFinder.app
fi
open /Applications/XFinder.app
echo "app launched from /Applications/XFinder.app"
