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
FILES="XFinder/Core/Notch/LiveActivity.swift XFinder/Core/Notch/NotchTask.swift XFinder/Core/Notch/NotchHoverOpen.swift XFinder/Core/Notch/NotchSurfaceMachine.swift XFinder/Core/Notch/NotchSurfaceLayout.swift XFinder/Core/Notch/NotchDragSession.swift XFinder/Core/Notch/NowPlaying.swift XFinder/Views/Detail/DropTrayDetailView.swift XFinder/Core/Calendar/GlanceRules.swift XFinder/Core/Notch/AudioWaveform.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM

FILTER='NotchSurface|NotchDrag|NotchTask|NotchHoverOpen|LiveActivity|NowPlaying|NotchNowPlaying|NotchBehaviour|FeatureKeyDefaults|MeetingAlertRules|AudioWaveform'
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
run "M2 hover peeks with the master hover switch off" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                guard s.hoverToPeek, state.isIdle, now.timeIntervalSince(since) >= s.hoverDwell else { return }'" "'                guard state.isIdle, now.timeIntervalSince(since) >= s.hoverDwell else { return }'"
run "M3 shaken tray with files auto-closes" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if case .expanded = state, anchor == .pointer, itemCount > 0 { return }\n'" "''"
run "M4 pointer away never collapses" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'guard state.isOpen, state != .activity, now.timeIntervalSince(since) >= s.leaveGrace else { return }'" \
  "'guard state.isOpen, state != .activity, now.timeIntervalSince(since) >= s.leaveGrace, Bool(\"false\") == true else { return }'"
run "M5 notchDrop switch ignored" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                guard s.dragIntoNotchOpens else { return }\n'" "''"
run "M6 hover zone always takes the title-bar strip" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'let lip = (itemCount > 0 || nowPlayingActive) ? m.badgeLip : 0'" "'let lip = m.badgeLip'"
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
run "M15 the volume HUD fires on a repeated report" XFinder/Core/Notch/LiveActivity.swift \
  "'        guard changed else { return nil }                                  // CoreAudio reports each change on 2 elements\n'" "''"
run "M16 the countdown reads 0:00 early" XFinder/Core/Notch/LiveActivity.swift \
  "'let t = Int(remaining(at: now).rounded(.up))'" "'let t = Int(remaining(at: now).rounded(.down))'"
run "M17 no badge for a running timer" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            guard itemCount > 0 || timerActive || nowPlayingActive else { return nil }'" "'            guard itemCount > 0 || nowPlayingActive else { return nil }'"
run "M18 a page switch opens a closed surface" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if case .expanded = state { state = .expanded(page) }'" "'                state = .expanded(page)'"
run "M19 hover opens the clipboard whatever the setting says" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if let page = s.hoverOpens.page(for: activity, shown: s.shownPages) {'" "'                if let page = Optional(NotchSurfaceMachine.Page.clipboard) {'"
run "M29 activity ignores a waiting agent" XFinder/Core/Notch/NotchHoverOpen.swift \
  "'            if a.agentNeedsYou, let p = visible(.agents) { return p }\n'" "''"
run "M30 hover opens an EMPTY tray" XFinder/Core/Notch/NotchHoverOpen.swift \
  "'        case .files: return a.itemCount > 0 ? (visible(.files) ?? shown.first) : nil'" "'        case .files: return visible(.files) ?? shown.first'"
run "M20 the playhead keeps moving while paused" XFinder/Core/Notch/NowPlaying.swift \
  "'        let rate = s.playing ? (s.rate ?? 1) : 0'" "'        let rate = s.rate ?? 1'"
run "M21 a crash-looping helper is restarted forever" XFinder/Core/Notch/NowPlaying.swift \
  "'            return attempts > Self.maxAttempts ? .giveUp : .restart(after: Self.delay(forAttempt: attempts))'" "'            return .restart(after: Self.delay(forAttempt: attempts))'"
run "M22 hover peeks an empty tray with nothing playing" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                } else if itemCount > 0 || s.nowPlayingActive {'" "'                } else if true {'"
run "M23 the now-playing peek collapses when the tray empties" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if n == 0, state == .peek, !s.nowPlayingActive { collapse() }'" "'                if n == 0, state == .peek { collapse() }'"
run "M24 the pill ignores its switch" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            guard pillOnPlainScreens else { return nil }\n'" "''"
run "M25 'slow' hover reads as medium" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'            case \"slow\": return 0.5'" "'            case \"slow\": return 0.25'"
run "M26 the plain-screen hover zone ignores the pill" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'            if pillShown, let visible { return pillRect(notch: notch, visible: visible, metrics: m) }\n'" "''"
run "M27 the fixed panel forgets the hub's top fillets (clipboard hub wider than the window)" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'        return CGSize(width: (widths.max() ?? 0) + 2 * m.topFillet, height: notch.height + (drops.max() ?? 0))'" \
  "'        return CGSize(width: (widths.max() ?? 0), height: notch.height + (drops.max() ?? 0))'"
run "M28 the fixed panel is shallower than the deepest hub" XFinder/Core/Notch/NotchSurfaceLayout.swift \
  "'        let drops: [CGFloat] = [m.expandedDrop, m.clipboardExpandedDrop, m.peekDrop, m.activityDrop, m.badgeLip, m.pillHeight]'" \
  "'        let drops: [CGFloat] = [m.clipboardExpandedDrop, m.peekDrop, m.activityDrop, m.badgeLip, m.pillHeight]'"
run "M31 OCR offered with no image held" XFinder/Core/Notch/NotchTask.swift \
  "'            out.append(.removeBackground)\n            out.append(.ocr)\n        }\n        out.append(.airDrop)'" \
  "'            out.append(.removeBackground)\n        }\n        out.append(.ocr)\n        out.append(.airDrop)'"
run "M32 shuffle modes renumbered (0-based, like MPShuffleType)" XFinder/Core/Notch/NowPlaying.swift \
  "'        case off = 1, albums = 2, songs = 3'" "'        case off = 0, albums = 2, songs = 1'"
run "M33 a notice with buttons yields to the hover (they vanish under the pointer)" XFinder/Core/Notch/NotchSurfaceMachine.swift \
  "'                if state == .activity && s.activityHoldsHover { return }   // the pointer came to press a button'" "'                _ = s.activityHoldsHover'"
run "M34 all-day events alert" XFinder/Core/Calendar/GlanceRules.swift \
  "'        for e in events where !e.isAllDay && (includeReminders || !e.isReminder) {'" "'        for e in events where (includeReminders || !e.isReminder) {'"
run "M35 one alert silences every later occurrence of a repeating event" XFinder/Core/Calendar/GlanceRules.swift \
  "'    static func key(_ e: GlanceEvent) -> String { \"\\(e.id)@\\(Int(e.start.timeIntervalSince1970))\" }'" "'    static func key(_ e: GlanceEvent) -> String { e.id }'"
run "M36 an alert scheduled in the past" XFinder/Core/Calendar/GlanceRules.swift \
  "'            let plan = Plan(key: k, fireAt: max(fire, now))'" "'            let plan = Plan(key: k, fireAt: fire)'"
run "M37 an alerted event alerts again" XFinder/Core/Calendar/GlanceRules.swift \
  "'                guard !alerted.contains(k), e.start > now.addingTimeInterval(-lateGrace) else { continue }'" "'                guard e.start > now.addingTimeInterval(-lateGrace) else { continue }'"
run "M38 linear level (ordinary music draws a flat line)" XFinder/Core/Notch/AudioWaveform.swift \
  "'        let db = 20 * log10(rms)\n        return min(1, max(0, (db - floorDB) / -floorDB))'" "'        return min(1, max(0, rms))'"
run "M39 bars fall as fast as they rise" XFinder/Core/Notch/AudioWaveform.swift \
  "'            let k = l > smoothed ? Self.attack : Self.release'" "'            let k = Self.attack'"
run "M40 one silent buffer reads as a denied permission" XFinder/Core/Notch/AudioWaveform.swift \
  "'            return now.timeIntervalSince(first) >= Self.grace'" "'            return true'"
run "M41 no buffers at all reads as denied" XFinder/Core/Notch/AudioWaveform.swift \
  "'            guard let first = firstBuffer, !sawSignal else { return false }'" "'            guard !sawSignal else { return false }; let first = firstBuffer ?? .distantPast'"
run "M8 view default disagrees with its reader" XFinder/Views/Detail/DropTrayDetailView.swift \
  "'@AppStorage(\"dropTray.hoverEnabled\") private var hoverEnabled = true'" "'@AppStorage(\"dropTray.hoverEnabled\") private var hoverEnabled = false'"

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
