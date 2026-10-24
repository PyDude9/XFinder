#!/bin/sh
# XF-T24 — side-notes layout and backup rules: every mutation must turn SideNotesT24Tests RED.
# Sources are restored from a byte copy (trap EXIT); a missing anchor or a mutant that does not compile aborts (exit 2).
# T1 stayed GREEN on the first run — the test compared an identity — and the panel-contains-the-pills assertion exists because of it.
set -u
cd "$(dirname "$0")/.." || exit 2
FILES="XFinder/Core/EdgeNotesLayout.swift XFinder/Core/NoteBackup.swift"
BK=$(mktemp -d /tmp/xf-mut-side-notes.XXXXXX)
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM

fails() {
  swift test --package-path Tests --filter SideNotesT24Tests 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
}
base=$(fails); echo "baseline failures: $base"
[ "$base" = "0" ] || { echo "FAIL: baseline is not green"; exit 1; }

red=0; total=0
run() {  # label file old new
  total=$((total + 1))
  python3 - "$2" "$3" "$4" <<'PY' || { echo "HARNESS ERROR: anchor not found for $1"; exit 2; }
import sys
p, o, n = sys.argv[1:4]
s = open(p).read()
if s.count(o) != 1: sys.exit(1)
open(p, "w").write(s.replace(o, n))
PY
  n=$(fails); restore
  [ "$n" = "NORESULT" ] && { echo "HARNESS ERROR: $1 produced no test result"; exit 2; }
  if [ "$n" != "0" ]; then red=$((red + 1)); echo "RED   $1 ($n failing)"; else echo "GREEN $1 <-- the tests do not guard this"; fi
}

run "T1 the panel top follows the card only (top pills cut off)" XFinder/Core/EdgeNotesLayout.swift \
  "let top = max(stack.maxY + slack, cardTop + slack)" "let top = cardTop + slack"
run "T2 the card is not lifted off the screen bottom" XFinder/Core/EdgeNotesLayout.swift \
  "if cardTop - cardHeight < floor { cardTop = floor + cardHeight }" "if false { cardTop = floor + cardHeight }"
run "T3 the height ignores the cap" XFinder/Core/EdgeNotesLayout.swift \
  "return (min(max(want, minCardHeight), cap), want > cap)" "return (max(want, minCardHeight), want > cap)"
run "T4 retention also prunes files that are not backups" XFinder/Core/NoteBackup.swift \
  'day(ofFile: n).map { !kept.contains($0) } ?? false' 'day(ofFile: n).map { !kept.contains($0) } ?? true'
run "T5 backups named by UTC, not the person's day" XFinder/Core/NoteBackup.swift \
  "cal.timeZone = timeZone" 'cal.timeZone = TimeZone(identifier: "UTC")!'

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
