#!/bin/sh
# F1 Dọn rác thư mục — inject each failure mode; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-cleanup.XXXXXX)
FILES="XFinder/Core/Cleanup/JunkCleanup.swift XFinder/Core/FileWalk.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM
FILTER='JunkCleanup'
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
J=XFinder/Core/Cleanup/JunkCleanup.swift
W=XFinder/Core/FileWalk.swift
run "J1  a ._ name counts without the AppleDouble header" $J \
  "'                if readHeader(url).map(isAppleDouble) ?? false { report.items.append(Item(url: url, kind: kind, bytes: size)) }'" "'                report.items.append(Item(url: url, kind: kind, bytes: size))'"
run "J2  packages are walked into" $J \
  "'            if isDir, name.contains(\".\"), (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {'" "'            if isDir, name.contains(\".\"), false {'"
run "J3  volume system folders are walked into" $J \
  "'            if isDir, systemFolders.contains(name) { return .skip }'" "'            _ = systemFolders'"
run "J4  a __MACOSX holding a real file counts as junk" $J \
  "'        return clean && !walked.truncated ? total : nil'" "'        return total'"
run "J5  symlinks are followed" $W \
  "'fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil)'" "'fts_open(&argv, FTS_LOGICAL | FTS_NOCHDIR | FTS_XDEV, nil)'"
run "J6  no re-check right before the Trash" $J \
  "'            guard stillJunk(item) else { out.changed += 1; continue }'" "'            _ = stillJunk'"
run "J7  names compared case-sensitively (THUMBS.DB missed)" $J \
  "'        switch name.lowercased() {'" "'        switch name {'"
run "J8  the entry limit is ignored" $W \
  "'            if entries > limit { return (entries, true, false) }'" "'            if entries < 0 { return (entries, true, false) }'"
run "J9  FileManager listing (hides every ._ name) instead of fts" $J \
  "'        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else { return report }'" "'        guard rootValues?.isDirectory == true, rootValues?.isSymbolicLink != true else { return report }\n        for n in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where n.hasPrefix(\"._\") { report.items.append(Item(url: root.appendingPathComponent(n), kind: .appleDouble, bytes: 0)) }\n        if true { return report }'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
