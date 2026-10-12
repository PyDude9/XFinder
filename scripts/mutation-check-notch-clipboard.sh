#!/bin/sh
# D0 — inject the notch clipboard page's failure modes one at a time; every one must turn the suite RED.
# Same contract as mutation-check-switcher.sh: a missing anchor or a mutant with no test result ABORTS (exit 2),
# sources are restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-notchclip.XXXXXX)
FILES="XFinder/Core/Clipboard/NotchClipboardRules.swift XFinder/Core/Notch/NotchSurfaceLayout.swift XFinder/Core/ClipboardShelfController.swift XFinder/Core/ColorFormat.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM
FILTER='NotchClipboardRules|NotchSurfaceLayout|FeatureKeyDefaults|ColorFormat'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} END {print (f==""?"NORESULT":f)}'
}
mutate() {
  python3 - "$1" "$2" "$3" <<'PY' || { echo "HARNESS ERROR: anchor not found in $1"; exit 2; }
import sys, ast
path, old, new = sys.argv[1], ast.literal_eval(sys.argv[2]), ast.literal_eval(sys.argv[3])
s = open(path).read()
if s.count(old) != 1: sys.exit(1)
open(path, "w").write(s.replace(old, new, 1))
PY
}
base=$(fails); echo "baseline failures: $base"
[ "$base" = "0" ] || { echo "FAIL: baseline is not green"; exit 1; }
red=0; total=0
run() {
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}
R=XFinder/Core/Clipboard/NotchClipboardRules.swift
run "D1 ⌘⇧V with the notch surface off opens nothing (no shelf fallback)" $R \
  "'        preferred == .notch && notchSurfaceEnabled ? .notch : .shelf'" "'        preferred'"
run "D2 ⌘4 lands on the first board whatever the digit" $R \
  "'            let i = slot - 3'" "'            let i = 0'"
run "D3 → wraps from the last card to the first" $R \
  "'        case .right: return min(count - 1, i + 1)'" "'        case .right: return (i + 1) % count'"
run "D4 ↓ on the bottom row jumps to the last card" $R \
  "'        case .down:  return i + cols < count ? i + cols : i'" "'        case .down:  return min(count - 1, i + cols)'"
run "D5 a type with no record still gets a (dead) chip" $R \
  "'            guard let n = counts[t], n > 0 else { return nil }'" "'            let n = counts[t] ?? 0'"
run "D6 the Accessibility warning shows even with auto-paste off" $R \
  "'        if autoPaste && !accessibilityTrusted { return .accessibilityMissing }'" "'        if !accessibilityTrusted { return .accessibilityMissing }'"
run "D7 the clipboard page is as short as the tray" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            page == .clipboard ? clipboardExpandedDrop : expandedDrop'" "'            expandedDrop'"
run "D9 the clipboard page is as narrow as the tray (four cards cannot fit)" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            page == .clipboard ? clipboardExpandedWidth : expandedWidth'" "'            expandedWidth'"
run "D10 every image fills the tile (the 2.8:1 screenshot is a zoomed centre crop again)" $R \
  "'        return (r > tolerance || r < 1 / tolerance) ? .fit : .fill'" "'        return .fill'"
run "D11 hsl() hue does not wrap (hsl(390…) is not hsl(30…))" XFinder/Core/ColorFormat.swift \
  "'        return wrapped < 0 ? wrapped + 360 : wrapped'" "'        return v'"
run "D12 the footer ignores the recording pause" $R \
  "'        if paused { return .paused }'" "'        if false { return .paused }'"
run "D8 the hotkey-surface reader defaults to the shelf (view says notch)" XFinder/Core/ClipboardShelfController.swift \
  "'UserDefaults.standard.string(forKey: \"clipboard.hotkeySurface\") ?? \"notch\"'" "'UserDefaults.standard.string(forKey: \"clipboard.hotkeySurface\") ?? \"shelf\"'"
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails); echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
