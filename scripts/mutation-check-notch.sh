#!/bin/sh
# Inject the Notch surface's known failure modes one at a time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to).
#
# Rules this script follows (CLAUDE.md, mutation section):
#   * every mutation names its target file and ABORTS the run if its anchor is missing — a mutation
#     that cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by an EXIT trap even if the run is interrupted;
#   * the last step ASSERTS the restored tree is green (prints the failure count, exits 1 if not 0).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-notch.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-notch.XXXXXX)
FILES="XFinder/Core/Notch/LiveActivity.swift XFinder/Core/Notch/NotchTask.swift XFinder/Core/Notch/NotchSurfaceMachine.swift XFinder/Core/Notch/NotchSurfaceLayout.swift XFinder/Core/Notch/NotchDragSession.swift XFinder/Views/Detail/DropTrayDetailView.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM

FILTER='NotchSurface|NotchDrag|NotchTask|LiveActivity|FeatureKeyDefaults'
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
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  # No "Executed … with N failures" line means the mutant did not compile or the runner died.
  # That proves nothing about the tests — it is a broken mutation, never a pass.
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}

run "M1 drag pasteboard: trust stale types" XFinder/Core/Notch/NotchDragSession.swift \
  "'        guard changeCount() != changeCountAtPress else { return false }   // no new drag session yet\n'" "''"
run "M2 hover reveals an empty tray" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'guard s.hoverToPeek, itemCount > 0, state.isIdle,'" "'guard s.hoverToPeek, state.isIdle,'"
run "M3 shaken tray with files auto-closes" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if case .expanded = state, anchor == .pointer, itemCount > 0 { return }\n'" "''"
run "M4 pointer away never collapses" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'guard state.isOpen, state != .activity, now.timeIntervalSince(since) >= s.leaveGrace else { return }'" \
  "'guard state.isOpen, state != .activity, now.timeIntervalSince(since) >= s.leaveGrace, Bool(\"false\") == true else { return }'"
run "M5 notchDrop switch ignored" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                guard s.dragIntoNotchOpens else { return }\n'" "''"
run "M6 hover zone always takes the title-bar strip" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'let lip = itemCount > 0 ? m.badgeLip : 0'" "'let lip = m.badgeLip'"
run "M7 a drag at the notch yanks the pointer tray" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if case .expanded = state, anchor == .pointer { return }\n'" "''"
run "M9 pasteboard read on every drag event (throttle removed)" XFinder/Core/Notch/NotchDragSession.swift \
  "'        if let lastCheck, now.timeIntervalSince(lastCheck) < Self.recheckInterval { return false }\n'" "''"
run "M10 a step after Cancel still counts" XFinder/Core/Notch/NotchTask.swift \
  "'    mutating func stepSucceeded(output: URL?) {\n        guard isRunning else { return }\n'" "'    mutating func stepSucceeded(output: URL?) {\n'"
run "M11 the hub collapses mid-job" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if taskRunning { return }\n'" "''"
run "M12 same-kind notices stack instead of replacing" XFinder/Core/Notch/LiveActivity.swift \
  "'            if current?.kind == item.kind { current = item; return true }\n'" "''"
run "M13 a notice interrupts the open hub" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if state.isIdle { state = .activity; anchor = .notch }'" "'                state = .activity; anchor = .notch'"
run "M14 low battery repeats every percent" XFinder/Core/Notch/LiveActivity.swift \
  "'            } else if n <= lowBattery && o > lowBattery {'" "'            } else if n <= lowBattery {'"
run "M8 view default disagrees with its reader" XFinder/Views/Detail/DropTrayDetailView.swift \
  "'@AppStorage(\"dropTray.hoverEnabled\") private var hoverEnabled = true'" "'@AppStorage(\"dropTray.hoverEnabled\") private var hoverEnabled = false'"

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
