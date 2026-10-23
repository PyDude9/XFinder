#!/bin/sh
# D0 — inject the notch clipboard page's failure modes one at a time; every one must turn the suite RED.
# Same contract as mutation-check-switcher.sh: a missing anchor or a mutant with no test result ABORTS (exit 2),
# sources are restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-notchclip.XXXXXX)
FILES="XFinder/Core/Clipboard/NotchClipboardRules.swift XFinder/Core/Notch/NotchSurfaceLayout.swift XFinder/Core/ClipboardShelfController.swift XFinder/Core/ColorFormat.swift XFinder/Core/Notch/NotchPages.swift XFinder/Core/MCP/MCPProtocol.swift XFinder/Core/Clipboard/CodeHighlighter.swift XFinder/Core/Clipboard/ClipExport.swift XFinder/Core/Clipboard/ClipboardLibraryRules.swift XFinder/Core/Clipboard/BoardLock.swift XFinder/Core/Clipboard/LinkPreviewRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='NotchClipboardRules|LinkPreviewRules|NotchSurfaceLayout|FeatureKeyDefaults|ColorFormat|NotchPages|MCPProtocol|CodeHighlighter|ClipExport|ClipboardLibraryRules|BoardLock'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /Fatal error|Exited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
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
  # A target outside FILES is never restored (P1, the notch script's M40). Refuse it.
  case " $FILES " in *" $2 "*) ;; *) echo "HARNESS ERROR: $2 is not in FILES (it would never be restored)"; exit 2;; esac
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
  "'            case .clipboard, .agents: return wideDrop'" "'            case .clipboard, .agents: return narrowDrop'"
run "D9 the clipboard page is as narrow as the tray (the card row cannot fit)" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            Self.isWide(page) ? wideWidth : narrowWidth'" "'            narrowWidth'"
run "D10 every image fills the tile (the 2.8:1 screenshot is a zoomed centre crop again)" $R \
  "'        return (r > tolerance || r < 1 / tolerance) ? .fit : .fill'" "'        return .fill'"
run "D11 hsl() hue does not wrap (hsl(390…) is not hsl(30…))" XFinder/Core/ColorFormat.swift \
  "'        return wrapped < 0 ? wrapped + 360 : wrapped'" "'        return v'"
run "D12 the footer ignores the recording pause" $R \
  "'        if paused { return .paused }'" "'        if false { return .paused }'"
run "D13 a page listed twice is shown twice" XFinder/Core/Notch/NotchPages.swift \
  "'            if let p = Page(rawValue: t), !out.contains(p) { out.append(p) }'" "'            if let p = Page(rawValue: t) { out.append(p) }'"
run "D14 a request for a hidden page opens the hidden page" XFinder/Core/Notch/NotchPages.swift \
  "'        shown.contains(page) ? page : (shown.first ?? defaultOrder[0])'" "'        page'"
run "D15 a swipe keeps firing for the whole gesture" XFinder/Core/Notch/NotchPages.swift \
  "'            if total <= -Self.threshold { fired = true; return 1 }'" "'            if total <= -Self.threshold { return 1 }'"
run "D16 the flares eat the content (hub width does not grow by them)" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            return CGSize(width: max(m.expandedWidth(for: page), notch.width) + 2 * m.topFillet,'" "'            return CGSize(width: max(m.expandedWidth(for: page), notch.width),'"
run "D17 MCP returns password-manager records" XFinder/Core/MCP/MCPProtocol.swift \
  "'            return !excludedBundleFragments.contains { bid.contains(\$0) }'" "'            return true'"
run "D18 MCP answers tool calls while switched off" XFinder/Core/MCP/MCPProtocol.swift \
  "'            guard context.enabled else {'" "'            guard false else {'"
run "D19 MCP limit is not clamped" XFinder/Core/MCP/MCPProtocol.swift \
  "'        return min(max(n, 1), maxLimit)'" "'        return n'"
run "D20 highlighter cap excludes exactly 4000 chars" XFinder/Core/Clipboard/CodeHighlighter.swift \
  "'        guard text.count <= maxLength else {'" "'        guard text.count < maxLength else {'"
run "D21 export still ships password-manager records" XFinder/Core/Clipboard/ClipExport.swift \
  "'excludedBundleIDs.contains(bundleID) {\\n                skipped += 1\\n                continue'" "'excludedBundleIDs.contains(bundleID) {\\n                skipped += 1'"
run "D21b export still ships locked rows" XFinder/Core/Clipboard/ClipExport.swift \
  "'            if record.isLocked {\\n                skipped += 1\\n                continue'" "'            if record.isLocked {\\n                skipped += 1'"
run "D22 import re-adds records the app already has" XFinder/Core/Clipboard/ClipExport.swift \
  "'            if existingIDs.contains(entry.id) {'" "'            if false {'"
L=XFinder/Core/Clipboard/ClipboardLibraryRules.swift
run "D23 library: the Pinned scope shows everything" $L \
  "'            return records.filter(\\.isPinned)'" "'            return records'"
run "D24 library: 'week' is wider than 7×24 h" $L \
  "'            return now.timeIntervalSince(date) <= 7 * 24 * 3600'" "'            return now.timeIntervalSince(date) <= 8 * 24 * 3600'"
run "D25 library: app facets sorted by name before count" $L \
  "'                if lhs.count != rhs.count { return lhs.count > rhs.count }'" "'                if false { return lhs.count > rhs.count }'"
run "D26 library: visibleCount is not clamped to the total" $L \
  "'        min(total, max(1, pagesShown) * pageSize)'" "'        max(1, pagesShown) * pageSize'"
K=XFinder/Core/Clipboard/BoardLock.swift
run "D27 lock: the fence lets locked rows through (MCP/export)" $K \
  "'        records.filter { !\$0.isLocked }'" "'        records'"
run "D28 lock: a content key (url) stays on the locked row" $K \
  "'    static let keptMetadataKeys: Set<String> = [\"isPinned\", \"usageCount\", \"isSaved\"]'" "'    static let keptMetadataKeys: Set<String> = [\"isPinned\", \"usageCount\", \"isSaved\", \"url\"]'"
run "D29 lock: open() ignores the blob version byte" $K \
  "'        guard blob.first == blobVersion else { throw Error.badBlob }'" "'        _ = blobVersion'"
run "D31 lock: restorePlain honours a planted ../ file name" $K \
  "'        guard let name, !name.isEmpty, !name.contains(\"/\"), name != \".\", name != \"..\", !name.hasPrefix(\"~\") else { return fallback }'" "'        guard let name, !name.isEmpty else { return fallback }'"
run "D30 MCP lists locked rows" XFinder/Core/MCP/MCPProtocol.swift \
  "'            guard !r.isLocked else { return false }'" "'            _ = r.isLocked'"
run "D8 the hotkey-surface reader defaults to the shelf (view says notch)" XFinder/Core/ClipboardShelfController.swift \
  "'UserDefaults.standard.string(forKey: \"clipboard.hotkeySurface\") ?? \"notch\"'" "'UserDefaults.standard.string(forKey: \"clipboard.hotkeySurface\") ?? \"shelf\"'"
run "D32 a private host is eligible for a link preview" XFinder/Core/Clipboard/LinkPreviewRules.swift \
  "'            if a == 10 || a == 127 || a == 0 || (a == 169 && b == 254) || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168) { return false }\n'" "''"
run "D33 the deck taps when it first appears or when a filter replaces the list" $R \
  "'        return ids.contains(old) && ids.contains(new)'" "'        return true'"
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails); echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
