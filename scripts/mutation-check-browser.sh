#!/bin/sh
# XF-T28 — inject the file browser engines' known failure modes one at a time; every one must turn the suite RED.
# A mutation that stays GREEN is a finding (the test does not guard what it claims to, or the mutant is equivalent).
#
# The mutants live in scripts/mutation-browser.json ({id, name, file, anchor, replacement}) instead of inline shell
# literals: 126 anchors full of quotes, backslashes and `$` were the escaping trap CLAUDE.md rule 21 warns about.
#
# Rules this script follows (CLAUDE.md §3.1 rule 5):
#   * every target is in FILES; an anchor that does not occur EXACTLY once aborts the run (exit 2) — a mutation that
#     cannot be injected is a broken gate, and a broken gate reads like a passing one;
#   * sources are restored byte-identical by `cp` from a backup (EXIT trap), INT/TERM end the run;
#   * a crashed suite (a trap) counts as RED — it noticed the mutant — and is reported as such; so does a hung one
#     (each run is capped at RUN_TIMEOUT seconds and killed with its whole process group);
#   * the restored tree must be green (exit 1 otherwise).
# Options: ONLY=<id prefix> runs a subset; FROM=<id> resumes there; DRY=1 only checks that every anchor occurs exactly
# once (seconds); RUN_TIMEOUT=<s> caps one test run (default 600).
# Run it detached and poll the log: `nohup sh scripts/mutation-check-browser.sh > <scratch>/m.log 2>&1 &`
set -u
cd "$(dirname "$0")/.."
MUTANTS=scripts/mutation-browser.json
BK=$(mktemp -d /tmp/xf-mut-browser.XXXXXX)
FILES="XFinder/Core/Browser/PaneTree.swift XFinder/Core/Browser/PaneHistory.swift XFinder/Core/Browser/BrowserPath.swift XFinder/Core/Browser/DirectoryEntry.swift XFinder/Core/Browser/SearchQuery.swift XFinder/Core/Browser/FileOperationRules.swift XFinder/Core/Browser/BrowserCommands.swift XFinder/Core/Browser/CloudBadge.swift XFinder/Core/Browser/ShelfModel.swift XFinder/Core/Browser/BrowserWorkspace.swift XFinder/Core/Browser/SidebarLayout.swift XFinder/Core/Browser/FileInfoRules.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
trap 'exit 143' INT TERM

FILTER='PaneTreeTests|PaneHistoryTests|BrowserPathTests|DirectoryEntryTests|SearchQueryTests|FileOperationRulesTests|BrowserCommandsTests|CloudBadgeTests|ShelfModelTests|BrowserWorkspaceTests|BrowserVocabularyL10nTests|SidebarLayoutTests|FileInfoRulesTests'
# One test run may take at most RUN_TIMEOUT seconds. A mutant that loops forever (BrowserPath-11, 2026-10-24: 42 min at
# 100 % CPU before it was noticed) is killed WITH its process group — killing only swift-test left orphaned xctest
# processes burning a core each for 90 minutes — and reported as HANG, which counts as RED: the suite never passes.
RUN_TIMEOUT=${RUN_TIMEOUT:-600}
timed() {
  # Kill the WHOLE descendant tree, found through `pgrep -P`: swift-test starts xctest in its own process group, so a
  # process-group kill left the hung xctest alive (measured 2026-10-24: orphan at 100 % CPU after the first fix).
  perl -e '$t = shift; $pid = fork; if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
           sub tree { my @all = ($_[0]); my @q = ($_[0]);
                      while (@q) { my $p = shift @q; my @c = split /\s+/, `pgrep -P $p`; @c = grep { /^\d+$/ } @c; push @all, @c; push @q, @c }
                      return @all }
           $SIG{ALRM} = sub { my @p = tree($pid); kill "TERM", @p; sleep 3; kill "KILL", @p; print "HARNESS-TIMEOUT\n"; exit 124 };
           alarm $t; waitpid($pid, 0); exit($? >> 8)' "$RUN_TIMEOUT" "$@"
}
fails() {
  timed swift test --package-path Tests --filter "$FILTER" 2>&1 \
    | awk '/Executed [0-9]+ tests, with [0-9]+ failure/ {for(i=1;i<=NF;i++) if($i=="with") f=$(i+1)}
           /[Ff]atal error|[Ee]xited with (unexpected )?signal/ {crash=1}
           /HARNESS-TIMEOUT/ {hang=1}
           END {print (hang ? "HANG" : (crash ? "CRASH" : (f==""?"NORESULT":f)))}'
}

# Every target must be in FILES, every anchor must occur exactly once.
python3 - "$MUTANTS" "$FILES" <<'PY' || { echo "HARNESS ERROR: bad mutant list"; exit 2; }
import json, sys
mutants, files = json.load(open(sys.argv[1])), set(sys.argv[2].split())
bad = 0
for m in mutants:
    if m["file"] not in files: print("NOT IN FILES:", m["id"], m["file"]); bad += 1; continue
    n = open(m["file"]).read().count(m["anchor"])
    if n != 1: print(f"ANCHOR x{n}:", m["id"], m["name"]); bad += 1
print(f"{len(mutants)} mutants, {bad} bad anchors")
sys.exit(1 if bad else 0)
PY
[ "${DRY:-0}" = "1" ] && { echo "DRY: anchors ok"; exit 0; }

base=$(fails); echo "baseline failures: $base"
[ "$base" = "0" ] || { echo "FAIL: baseline is not green"; exit 1; }

# FROM=<id> resumes at that mutant (a run cut short by a broken mutant need not start over).
IDS=$(python3 -c "
import json
ms = [m['id'] for m in json.load(open('$MUTANTS')) if m['id'].startswith('${ONLY:-}')]
start = ms.index('${FROM:-}') if '${FROM:-}' in ms else 0
print('\n'.join(ms[start:]))")
red=0; total=0
for id in $IDS; do
  total=$((total+1))
  name=$(python3 - "$MUTANTS" "$id" <<'PY'
import json, sys
m = next(m for m in json.load(open(sys.argv[1])) if m["id"] == sys.argv[2])
s = open(m["file"]).read()
if s.count(m["anchor"]) != 1: sys.exit(1)
open(m["file"], "w").write(s.replace(m["anchor"], m["replacement"], 1))
print(m["name"])
PY
) || { echo "HARNESS ERROR: anchor not found for $id"; exit 2; }
  n=$(fails); restore
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $id produced no test result (mutant did not compile?)"; exit 2; fi
  if [ "$n" = "HANG" ]; then red=$((red+1)); echo "RED   $id $name (the suite hung — killed after ${RUN_TIMEOUT}s)"
  elif [ "$n" = "CRASH" ]; then red=$((red+1)); echo "RED   $id $name (the suite crashed)"
  elif [ "$n" != "0" ]; then red=$((red+1)); echo "RED   $id $name ($n failing)"
  else echo "GREEN $id $name (0) <-- the tests do not guard this"; fi
done
restore
for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED"
[ "$after" = "0" ] && [ "$red" = "$total" ] || exit 1
