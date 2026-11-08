#!/bin/sh
# XF-VOICE-PERMISSIONS — inject each permission-handling failure mode; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-voice.XXXXXX)
FILES="XFinder/Core/Voice/VoicePermissionRules.swift XFinder/Core/Voice/VoiceManager.swift XFinder/Core/FeatureHub.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM
FILTER='VoicePermissionRules|PermissionCallbackIsolation'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
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
if [ "${DRY:-}" = 1 ]; then
  echo "DRY: checking every anchor occurs exactly once (no test run)"
else
  base=$(fails); echo "baseline failures: $base"
  [ "$base" = "0" ] || { echo "FAIL: baseline is not green"; exit 1; }
fi
red=0; total=0
run() {
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  if [ "${DRY:-}" = 1 ]; then restore; echo "ANCHOR $1"; return; fi
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $1 ($n failing)"
  else echo "GREEN $1 (0) <-- the tests do not guard this"; fi
}
V=XFinder/Core/Voice/VoicePermissionRules.swift
run "V1  a refused Speech Recognition is ignored (dictation starts / mic is prompted)" $V \
  "'        if let refused = statuses.first(where: { \$0.status.isRefused }) {'" "'        if let refused = statuses.first(where: { \$0.status.isRefused && \$0.kind == .microphone }) {'"
run "V2  speech is named first when both are refused" $V \
  "'        if let refused = statuses.first(where: { \$0.status.isRefused }) {'" "'        if let refused = statuses.last(where: { \$0.status.isRefused }) {'"
run "V3  restricted is reported as plain denied" $V \
  "'            return .blocked(refused.kind, restricted: refused.status == .restricted)'" "'            return .blocked(refused.kind, restricted: false)'"
run "V4  restricted counts as askable (old re-ask bug)" $V \
  "'    var isRefused: Bool { self == .denied || self == .restricted }'" "'    var isRefused: Bool { self == .denied }'"
run "V5  only the first undecided permission is asked" $V \
  "'        return undecided.isEmpty ? .start : .ask(undecided)'" "'        return undecided.isEmpty ? .start : .ask([undecided[0]])'"
run "V6  a refused row offers Request again (button that does nothing)" $V \
  "'        case .denied: return \"Mở Cài đặt hệ thống\"'" "'        case .denied: return \"Yêu cầu\"'"
run "V7  a restricted row offers a button" $V \
  "'        case .authorized, .restricted: return nil'" "'        case .authorized: return nil\n        case .restricted: return \"Mở Cài đặt hệ thống\"'"
run "V8  the Speech line says Micro (copy-paste)" $V \
  "'        case (.speechRecognition, false): return \"Nhận dạng giọng nói đang bị từ chối cho XFinder\"'" "'        case (.speechRecognition, false): return \"Micro đang bị từ chối cho XFinder\"'"
run "V9  the vocabulary list drops the row buttons" $V \
  "'            if let action = rowActionKey(status) { keys.append(action) }'" "'            _ = rowActionKey(status)'"
M=XFinder/Core/Voice/VoiceManager.swift
H=XFinder/Core/FeatureHub.swift
run "V10 the speech callback in VoiceManager loses @Sendable (Swift 6 trap off-main)" $M \
  "'                    SFSpeechRecognizer.requestAuthorization { @Sendable status in'" "'                    SFSpeechRecognizer.requestAuthorization { status in'"
run "V11 the speech callback in FeatureHub loses @Sendable (the un-annotated SDK block)" $H \
  "'                SFSpeechRecognizer.requestAuthorization { @Sendable _ in'" "'                SFSpeechRecognizer.requestAuthorization { _ in'"
echo "RESULT: $red/$total mutations RED"
restore
[ "${DRY:-}" = 1 ] && { echo "DRY: $total anchors OK"; exit 0; }
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
