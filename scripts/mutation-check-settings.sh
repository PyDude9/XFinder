#!/bin/sh
# P3 (2026-10-13): inject the settings shell's known failure modes — sidebar IA and the shortcut catalog — one at a
# time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to).
#
# Rules this script follows (CLAUDE.md, mutation section):
#   * every mutation names its target file and ABORTS the run if its anchor is missing — a mutation
#     that cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by an EXIT trap even if the run is interrupted;
#   * the last step ASSERTS the restored tree is green (prints the failure count, exits 1 if not 0).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-settings.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-settings.XXXXXX)
FILES="XFinder/Models/SidebarDestination.swift XFinder/Core/Shortcuts/ShortcutCatalog.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM

FILTER='SidebarDestination|ShortcutCatalog|WhatsNew'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} END {print (f==""?"NORESULT":f)}'
}

# mutate <file> <python-literal-old> <python-literal-new>
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
run() {   # run <name> <file> <old> <new>
  # A target outside FILES is never restored — P1 found M40's mutant still on disk after a run. Refuse it.
  case " $FILES " in *" $2 "*) ;; *) echo "HARNESS ERROR: $2 is not in FILES (it would never be restored)"; exit 2;; esac
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  # No "Executed … with N failures" line means the mutant did not compile or the runner died.
  # That proves nothing about the tests — it is a broken mutation, never a pass.
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}

run "S1 a page is dropped from every group (unreachable)" XFinder/Models/SidebarDestination.swift \
  "'(\"CHUNG\", [.dashboard, .features, .shortcuts, .system,'" "'(\"CHUNG\", [.dashboard, .features, .system,'"
run "S2 two pages share an icon again (smartSelect = aiSearch)" XFinder/Models/SidebarDestination.swift \
  "'        case .smartSelect: return \"character.cursor.ibeam\"'" "'        case .smartSelect: return \"wand.and.stars\"'"
run "S3 a notch page leaves the NOTCH group" XFinder/Models/SidebarDestination.swift \
  "'.aiAgents, .calendar, .liveActivities]),'" "'.aiAgents, .calendar]),\n            (\"TẠM\", [.liveActivities]),'"
run "S4 the tray page promises the notch settings again" XFinder/Models/SidebarDestination.swift \
  "'        case .dropTray: return \"Khay thả\"'" "'        case .dropTray: return \"Notch & Khay thả\"'"
run "S5 an icon that is not an SF Symbol (renders as nothing)" XFinder/Models/SidebarDestination.swift \
  "'        case .liveActivities: return \"dot.radiowaves.left.and.right\"'" "'        case .liveActivities: return \"sparkles.magnifyingglass\"'"
run "C1 a shortcut clashes with itself" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'where otherID != owner && otherChord == chord && isActive(otherID) {'" "'where otherChord == chord && isActive(otherID) {'"
run "C2 a switched-off owner still counts as a clash" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'where otherID != owner && otherChord == chord && isActive(otherID) {'" "'where otherID != owner && otherChord == chord {'"
run "C3 the palette's command bit read from the option bit" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'            if raw & (1 << 20) != 0 { m.insert(.command) }'" "'            if raw & (1 << 19) != 0 { m.insert(.command) }'"
run "C4 the catalog drifts from the snap engine's key code" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'chord: Chord(keyCode: 2, modifiers: [.control, .option]), scope: .global,'" "'chord: Chord(keyCode: 3, modifiers: [.control, .option]), scope: .global,'"
run "C5 a gate default disagrees with its reader" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'gateKey: \"quitProtection.enabled\", gateDefault: false),'" "'gateKey: \"quitProtection.enabled\", gateDefault: true),'"
run "C7 the catalog drifts from the clipboard tap's key code" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'chord: Chord(keyCode: 9, modifiers: [.command, .shift]), // V'" "'chord: Chord(keyCode: 11, modifiers: [.command, .shift]), // V'"
run "C8 the catalog drifts from the notes monitor's letter" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'chord: Chord(keyCode: 45, modifiers: [.command, .option]), // N'" "'chord: Chord(keyCode: 46, modifiers: [.command, .option]), // N'"
run "C9 the catalog drifts from QuitHold's key" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'chord: Chord(keyCode: 12, modifiers: [.command]), // Q'" "'chord: Chord(keyCode: 13, modifiers: [.command]), // Q'"
run "C6 Find Next shown as a macOS-reserved chord, not a convention" XFinder/Core/Shortcuts/ShortcutCatalog.swift \
  "'isConventionOnly: true))'" "'isConventionOnly: false))'"
run "C10 a tab is its own sidebar row again (the merge undone)" XFinder/Models/SidebarDestination.swift \
  "'    var hostRow: SidebarDestination { self == .antiSleep ? .features : (tabGroup?.first ?? self) }'" \
  "'    var hostRow: SidebarDestination { self }'"

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
