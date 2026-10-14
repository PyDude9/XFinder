#!/bin/sh
# Inject the clipboard modules' known failure modes one at a time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to).
#
# Rules this script follows (CLAUDE.md, mutation section):
#   * every mutation names its target file and ABORTS the run if its anchor is missing — a mutation
#     that cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by an EXIT trap even if the run is interrupted;
#   * the last step ASSERTS the restored tree is green (prints the failure count, exits 1 if not 0).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-clipboard.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-clipboard.XXXXXX)
FILES="XFinder/Core/Clipboard/ClipboardFilterToken.swift XFinder/Core/Clipboard/ClipboardTransform.swift XFinder/Core/Clipboard/PasteQueue.swift XFinder/Core/Clipboard/ClipboardText.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM

FILTER='ClipboardFilterToken|ClipboardTransform|PasteQueue|ClipboardText'
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

run "C1 an unknown @token is dropped instead of filtering by app" XFinder/Core/Clipboard/ClipboardFilterToken.swift \
  "'                out.app = token                           // the last app token wins'" "'                break'"
run "C2 the queue pastes a ⌘-clicked card twice" XFinder/Core/Clipboard/PasteQueue.swift \
  "'        guard !items.contains(item) else { return }\n'" "''"
run "C3 CRLF counts as two line breaks" XFinder/Core/Clipboard/ClipboardTransform.swift \
  "'var l = text.replacingOccurrences(of: \"\\\\r\\\\n\", with: \"\\\\n\").components(separatedBy: .newlines)'" "'var l = text.components(separatedBy: .newlines)'"
run "C4 unpadded Base64 is rejected" XFinder/Core/Clipboard/ClipboardTransform.swift \
  "'            s += String(repeating: \"=\", count: pad)\n'" "''"
run "C5 a no-op transform pretends it changed something" XFinder/Core/Clipboard/ClipboardTransform.swift \
  "'        return out == text ? .failure(.noChange) : .success(out)'" "'        return .success(out)'"
run "C6 the drained stack stays active (the next ⌘V would paste nothing)" XFinder/Core/Clipboard/PasteQueue.swift \
  "'        if items.isEmpty { active = false }\n        return next'" "'        return next'"
run "C7 the measured bug: only clips above 4 096 characters get a payload" XFinder/Core/Clipboard/ClipboardText.swift \
  "'static func needsPayload(_ text: String) -> Bool { text.count > previewLength }'" "'static func needsPayload(_ text: String) -> Bool { text.count > 4096 }'"
run "C8 pasting reads the 200-character preview instead of the payload" XFinder/Core/Clipboard/ClipboardText.swift \
  "'        if let p = payloadPath, !p.isEmpty, let full = read(p), !full.isEmpty { return full }\n'" "''"

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
