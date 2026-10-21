#!/bin/sh
# F4 Chụp & chú thích — inject each failure mode of the pure capture/annotation rules; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-capture.XXXXXX)
FILES="XFinder/Core/Capture/CaptureRules.swift XFinder/Core/Capture/Annotation.swift XFinder/Core/Onboarding.swift XFinder/Core/ScreenTextRecognizer.swift XFinder/Core/Image/VisionChild.swift XFinder/Core/Image/ImageRunner.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='CaptureRulesTests|AnnotationTests|CaptureVocabularyL10nTests|OnboardingTests|OCRTextTests|ImageEngineTests'
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
R=XFinder/Core/Capture/CaptureRules.swift
A=XFinder/Core/Capture/Annotation.swift
O=XFinder/Core/Onboarding.swift
run "K1  label puts ⌘ before ⇧ (⌘⇧4 instead of ⇧⌘4)" $R \
  "'        if hasShift { s += \"⇧\" }\\n        if hasCommand { s += \"⌘\" }'" "'        if hasCommand { s += \"⌘\" }\\n        if hasShift { s += \"⇧\" }'"
run "K2  a system clash hides a double assignment" $R \
  "'            return .mode(otherMode)'" "'            _ = otherMode; break'"
run "K3  sound off still plays the shutter" $R \
  "'        if !sound {\\n            args += [\"-x\"]'" "'        if sound {\\n            args += [\"-x\"]'"
run "K4  keep-both is case-sensitive (Ảnh.PNG overwritten by ảnh.png)" $R \
  "'        let lowerExisting = Set(existing.map { \$0.lowercased() })'" "'        let lowerExisting = Set(existing)'"
run "K5  history prunes the NEWEST captures" $R \
  "'            if a.date != b.date { return a.date < b.date }'" "'            if a.date != b.date { return a.date > b.date }'"
run "K6  time spent hovering still counts down" $R \
  "'        let elapsed = effectiveNow.timeIntervalSince(start) - accumulatedPause'" "'        let elapsed = date.timeIntervalSince(start)'"
run "K7  blur draws nothing (the address stays readable)" $A \
  "'            pixelate(region: r.standardized, in: context, base: base)'" "'            _ = r'"
run "K8  counters start at 0" $A \
  "'        return (numbers.max() ?? 0) + 1'" "'        return numbers.max() ?? 0'"
run "K9  pushing an unchanged document adds an undo step" $A \
  "'        guard next != present else { return }'" "'        _ = next == present'"
run "K10 the minimal preset may need a permission again" $O \
  "'!\$0.idle.isBackgroundActive && \$0.permissions.isEmpty }'" "'!\$0.idle.isBackgroundActive }'"
run "K11 the countdown also delays a shot the person is still selecting" $R \
  "'        if countdown > 0, !args.contains(\"-i\") {'" "'        if countdown > 0 {'"
run "K12 shadow off strips the shadow flag from every mode (screencapture rejects -o outside window shots)" $R \
  "'        if mode == .window, !windowShadow {'" "'        if !windowShadow {'"
T=XFinder/Core/ScreenTextRecognizer.swift
V=XFinder/Core/Image/VisionChild.swift
I=XFinder/Core/Image/ImageRunner.swift
run "K13 the Vision child's answer swaps x and y" $T \
  "'x: Double(\$0.box.minX), y: Double(\$0.box.minY)'" "'x: Double(\$0.box.minY), y: Double(\$0.box.minX)'"
run "K14 a typo after --vision silently runs the accurate OCR" $V \
  "'        return Job(rawValue: args[i + 1])'" "'        return Job(rawValue: args[i + 1]) ?? .ocrAccurate'"
run "K15 bytes that are not an image read as an image with no text" $T \
  "'        guard let image = VisionChild.decode(imageData) else { return nil }'" "'        guard let image = VisionChild.decode(imageData) else { return [] }'"
run "K16 a crashed child's empty answer is taken as no text (no fallback)" $T \
  "'        guard let wire = try? JSONDecoder().decode([Line].self, from: data) else { return nil }'" "'        guard let wire = try? JSONDecoder().decode([Line].self, from: data) else { return [] }'"
run "K17 the fast level is sent to the child as the accurate job" $T \
  "'        var job: VisionChild.Job { self == .fast ? .ocrFast : .ocrAccurate }'" "'        var job: VisionChild.Job { .ocrAccurate }'"
run "K18 two of the child's answers share an exit status" $V \
  "'        static let noSubject: Int32 = 3'" "'        static let noSubject: Int32 = 2'"
run "K19 a plain image is cut out as an empty picture instead of \"no subject\"" $I \
  "'        guard let obs = request.results?.first, !obs.allInstances.isEmpty else {\n            return .failure(.noSubject(name))'" "'        guard let obs = request.results?.first, !obs.allInstances.isEmpty else {\n            return .success(Data())'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
