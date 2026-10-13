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
  build > "$OUT/build.log" 2>&1 || {
    # P3: the tail alone ends with "The following build commands failed" — the `error:` lines sit far above it and a
    # failed build printed no cause at all. Print them first.
    echo "--- compiler errors ---"; grep -E "error:" "$OUT/build.log" | sort -u | head -40
    tail -20 "$OUT/build.log"; exit 1; }

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
AppleSpeechProvider.swift TypingSink.swift VoiceManager.swift VoiceDetailView.swift
DictationMode.swift VoiceTrigger.swift RefinePrompt.swift RefinerTypes.swift
VoiceSettingsKeys.swift VoiceRefiner.swift VoiceTextDiff.swift VoiceKeychain.swift
VoiceScreenContext.swift VoiceHUD.swift VoiceDiffPanel.swift VoiceAudioCue.swift
AppleOnDeviceRefiner.swift HTTPRefiner.swift OllamaRefiner.swift
MenuBarEngine.swift MenuBarEngineFactory.swift LegacyLengthEngine.swift
NativeVisibilityEngine.swift NativeVisibilityBridge.swift AccessibilityMenuBarInventory.swift
SettingsShell.swift NotchInterfaceDetailView.swift MediaDetailView.swift AIAgentsDetailView.swift
CalendarSettingsDetailView.swift LiveActivitiesDetailView.swift ShortcutsDetailView.swift ShortcutCatalog.swift
DropTrayDetailView.swift SidebarDestination.swift
AgentKind.swift AgentEvents.swift AgentHookInstaller.swift AgentSessionMonitor.swift NotchAgentsPage.swift
OpenCodeRules.swift OpenCodeMonitor.swift"
MISSING=0
for f in $GESTURE_FILES; do
  if grep -q "/$f" "$LIST"; then echo "  OK   $f"; else echo "  MISS $f"; MISSING=$((MISSING + 1)); fi
done

# A resource is not compiled, so it never appears in the SwiftFileList: check the
# built bundle directly. A missing translation store makes the whole app run in
# Vietnamese with a single stderr line, and no compile check would notice.
echo "--- bundled resources ---"
for r in L10n.strings.json L10n.allowlist.json xfinder-agent-hook.zsh xfinder-claude-statusline.sh; do
  if [ -f "$OUT/out/XFinder.app/Contents/Resources/$r" ]; then
    echo "  OK   $r ($(wc -c < "$OUT/out/XFinder.app/Contents/Resources/$r") bytes)"
  else
    echo "  MISS $r"; MISSING=$((MISSING + 1))
  fi
done

# B6: the Now Playing helper is produced by a Run Script phase, not a Sources entry, so the
# SwiftFileList cannot show it either — check the bundle.
echo "--- now-playing helper ---"
H="$OUT/out/XFinder.app/Contents/Helpers/XFinderNowPlaying.dylib"
if [ -f "$H" ]; then echo "  OK   XFinderNowPlaying.dylib ($(lipo -archs "$H"))"; else echo "  MISS XFinderNowPlaying.dylib"; MISSING=$((MISSING + 1)); fi

echo "--- archs ---"
lipo -archs "$OUT/out/XFinder.app/Contents/MacOS/XFinder"

# P3: a MISS used to be printed and the script still exited 0 — a gate that only prints reads as a pass.
if [ "$MISSING" -ne 0 ]; then echo "FAIL: $MISSING file(s) missing from the compile list or the bundle"; exit 1; fi

# This script BUILDS and CHECKS. It does not sign or install, on purpose (2026-10-10):
# it used to `pkill -9 XFinder`, replace /Applications/XFinder.app and re-sign it with
# `codesign --deep` — killing the user's running app on every build, and the deep re-sign
# DROPPED the Finder Sync extension's sandbox entitlement, so pkd refused the extension
# and XFinder's Finder menu vanished (measured: entitlement count 0, no pluginkit entry).
# CLAUDE.md had already recorded that exact trap for the install script.
echo "--- not installed ---"
echo "build output: $OUT/out/XFinder.app"
echo "to install and launch (signs the extension correctly): sh scripts/install-mouse-rebuild.sh"
