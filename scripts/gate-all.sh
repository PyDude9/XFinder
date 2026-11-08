#!/bin/sh
# One command, one summary — what an agent pastes into docs/AGENT_WORKLOG.md and what Claude re-runs to
# check it. Runs, in order: the build (scripts/build-and-check.sh), the whole test package, and every
# string / UI gate. Prints ONE line per step and exits non-zero if any step failed.
#
# It does NOT run mutation harnesses (they edit sources and must run one at a time, alone) and does NOT
# install anything. Never run it while a mutation harness is running: both use the test package.
#
#   sh scripts/gate-all.sh            # everything (~2 min)
#   sh scripts/gate-all.sh --no-build # tests + gates only, for a docs/tests-only change
set -u
cd "$(dirname "$0")/.." || exit 2
LOG=$(mktemp -d "${TMPDIR:-/tmp}/xfinder-gate.XXXXXX")
fail=0
line() { printf '%-34s %s\n' "$1" "$2"; }

if pgrep -f 'scripts/mutation-check-' >/dev/null 2>&1; then
  echo "A mutation harness is running — wait for it; both use the test package." >&2
  exit 2
fi

if [ "${1:-}" != "--no-build" ]; then
  if sh scripts/build-and-check.sh > "$LOG/build.txt" 2>&1 && ! grep -q '^  MISS' "$LOG/build.txt"; then
    line "build (arm64, compile list)" "OK"
  else
    line "build (arm64, compile list)" "FAILED — see $LOG/build.txt"; fail=1
  fi
fi

swift test --package-path Tests > "$LOG/tests.txt" 2>&1
summary=$(grep -E 'Executed [0-9]+ tests' "$LOG/tests.txt" | tail -1 | sed 's/^[[:space:]]*//')
case "$summary" in
  *"with 0 failures"*|*"skipped and 0 failures"*) line "tests" "$summary" ;;   # XCTSkip adds "N test(s) skipped and"
  "") line "tests" "DID NOT RUN (compile error?) — see $LOG/tests.txt"; fail=1 ;;
  *) line "tests" "$summary"; fail=1 ;;
esac

for g in check-l10n-coverage check-l10n-duplicates audit-l10n-literals check-sidebar-groups-l10n \
         audit-gesture-vocabulary-l10n audit-l10n-interpolations audit-ui-tokens; do
  out=$(python3 "scripts/$g.py" 2>&1 | tail -1)
  case "$out" in
    "TOTAL 0 "*) line "$g" "$out" ;;
    *) line "$g" "${out:-no output}"; fail=1 ;;
  esac
done

# A modified source nobody asked for is a leftover mutant until proven otherwise (CLAUDE.md, gesture rules).
line "modified tracked files" "$(git --no-optional-locks status --short | grep -vc '^??')"

[ "$fail" = 0 ] && echo "GATE: green" || echo "GATE: RED"
exit "$fail"
