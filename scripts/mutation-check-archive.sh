#!/bin/sh
# Inject the archive engine's known failure modes one at a time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to).
#
# Rules this script follows (CLAUDE.md, mutation section):
#   * every mutation names its target file and ABORTS the run if its anchor is missing — a mutation
#     that cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by an EXIT trap even if the run is interrupted;
#   * the last step ASSERTS the restored tree is green (prints the failure count, exits 1 if not 0).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-archive.sh > /tmp/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-archive.XXXXXX)
FILES="XFinder/Core/Archive/ArchiveEngine.swift XFinder/Core/Archive/ArchiveRunner.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM

FILTER='ArchiveEngine|ArchiveRunner'
fails() {
  swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)} /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1} END {print (crash ? "CRASH" : (f==""?"NORESULT":f))}'
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

run "A1 two sources go to ditto again" XFinder/Core/Archive/ArchiveEngine.swift \
  "'        !(format == .zip && sourceCount == 1 && level == defaultLevel && !hasPassword)'" \
  "'        !(format == .zip && level == defaultLevel && !hasPassword)'"
run "A2 same-name sources collide" XFinder/Core/Archive/ArchiveEngine.swift \
  "'            while used.contains(candidate.lowercased()) { candidate = numbered(base, n); n += 1 }\n'" "''"
run "A3 password back in argv" XFinder/Core/Archive/ArchiveEngine.swift \
  "r'arguments: [\"-r\", \"-\\(lvl)\", \"-q\", output.path] + names,'" \
  "r'arguments: [\"-r\", \"-\\(lvl)\", \"-q\"] + (hasPassword ? [\"-P\", password ?? \"\"] : []) + [output.path] + names,'"
run "A4 ask decides for the user" XFinder/Core/Archive/ArchiveEngine.swift \
  "'        case .ask: return .needsDecision(existing: base)'" "'        case .ask: return .write(base)'"
run "A5 no up-front missing-source check" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        guard missing.isEmpty else { return .failure(.missingSource(missing)) }\n'" "''"
run "A6 placements reuse a name within one batch" XFinder/Core/Archive/ArchiveEngine.swift \
  "'            if case .write(let url) = d { reserved.insert(url.lastPathComponent.lowercased()) }\n'" "''"
run "A7 tar stores the staging symlinks" XFinder/Core/Archive/ArchiveEngine.swift \
  "'arguments: [\"-czhf\", output.path] + names,'" "'arguments: [\"-czf\", output.path] + names,'"

run "A8 escaping links inside an archive are accepted" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        guard escaping.isEmpty else { try? fm.removeItem(at: dir); return .failure(.unsafeLinks(escaping.sorted())) }\n'" "''"

# A9: a link walk that cannot see "._" names (as every FileManager listing is for regular ._ files — F1). bsdtar
# creates "._x" symlinks from a foreign tar, so the guard must still see them.
run "A9 the link check is blind to links named ._…" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            while let rel = walker.nextObject() as? String {\n'" "'            while let rel = walker.nextObject() as? String {\n                if (rel as NSString).lastPathComponent.hasPrefix(\"._\") { continue }\n'"
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
