#!/bin/sh
# XF-T21 — Chia sẻ nhanh / Kết nối từ xa rules and catalog rows: every mutation must turn ConnectRulesTests RED.
# Sources are restored from a byte copy (trap EXIT); a missing anchor or a mutant that does not compile aborts (exit 2).
# Not mutable here: "the switch goes off but the server keeps running" lives in QuickShareController (NWListener, needs the app);
# it is covered by T-T21-1 by hand.
set -u
cd "$(dirname "$0")/.." || exit 2
FILES="XFinder/Core/ConnectRules.swift XFinder/Core/FeatureCatalog.swift"
BK=$(mktemp -d /tmp/xf-mut-connect.XXXXXX)
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM

fails() {
  swift test --package-path Tests --filter ConnectRulesTests 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} END {print (f==""?"NORESULT":f)}'
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

run "C1 a non-GET request is served" XFinder/Core/ConnectRules.swift \
  'guard parts.count >= 2, parts[0] == "GET" else' 'guard parts.count >= 2 else'
run "C2 any path is a token (no hex check)" XFinder/Core/ConnectRules.swift \
  'return token.allSatisfy({ $0.isHexDigit }) ? token : ""' 'return token'
run "C3 a quote in the file name stays in the header fallback" XFinder/Core/ConnectRules.swift \
  's.value >= 0x20 && s != "\"" && s != "\\"' 's.value >= 0x20 && s != "\\"'
run "C4 CR/LF in the file name stays in the header fallback" XFinder/Core/ConnectRules.swift \
  '(s.isASCII && s.value >= 0x20 &&' '(s.isASCII &&'
run "C5 a link with no port" XFinder/Core/ConnectRules.swift \
  'guard let address, port != 0, !token.isEmpty else' 'guard let address, !token.isEmpty else'
run "C6 ssh destination can be read as an option (no --)" XFinder/Core/ConnectRules.swift \
  'return args + ["--", "\(user)@\(host)", "echo ok"]' 'return args + ["\(user)@\(host)", "echo ok"]'
run "C7 scp files can be read as options (no --)" XFinder/Core/ConnectRules.swift \
  'return args + ["--"] + files +' 'return args + files +'
run "C8 a timeout gets no explanation" XFinder/Core/ConnectRules.swift \
  'if lower.contains("timed out") {' 'if lower.contains("timed out!") {'
run "C10 the index page does not escape < in a file name" XFinder/Core/ConnectRules.swift \
  'case "<": out += "&lt;"' 'case "<": out += "<"'
run "C11 the index page links by (escaped) name instead of token" XFinder/Core/ConnectRules.swift \
  'rows += "<li><a href=\"/\(e.token)\" download>' 'rows += "<li><a href=\"/\(htmlEscape(e.name))\" download>'
run "C9 the LAN server is labelled nothing-at-rest (Yên tĩnh would leave it on)" XFinder/Core/FeatureCatalog.swift \
  'defaultOn: true, permissions: [], idle: .timerWhileActive),' 'defaultOn: true, permissions: [], idle: .nothingAtRest),'

restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
