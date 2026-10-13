#!/bin/sh
# Smart Selection (E1–E3) + the shared secret-app list — inject each failure mode; every one must turn the suite RED.
# Contract of the other mutation scripts: a missing anchor or a mutant with no test result ABORTS (exit 2), sources are
# restored byte-identical by an EXIT trap, the last step asserts the restored tree is green.
set -u
cd "$(dirname "$0")/.."
BK=$(mktemp -d /tmp/xf-mut-smartselect.XXXXXX)
FILES="XFinder/Core/SmartSelect/SmartSelectionRules.swift XFinder/Core/SmartSelect/UnitConversion.swift XFinder/Core/SmartSelect/TimeZoneConversion.swift XFinder/Core/SmartSelect/CurrencyConversion.swift XFinder/Core/SecretApps.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT INT TERM
FILTER='SmartSelectionRules|UnitConversion|TimeZoneConversion|CurrencyConversion|MCPProtocol'
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
R=XFinder/Core/SmartSelect/SmartSelectionRules.swift
U=XFinder/Core/SmartSelect/UnitConversion.swift
T=XFinder/Core/SmartSelect/TimeZoneConversion.swift
run "E1  an unspaced minus/slash counts as arithmetic (dates and phone numbers become sums)" $R \
  "'        let spaced = t.range(of: #\"\\\\s[-/]\\\\s\"#, options: .regularExpression) != nil'" "'        let spaced = t.contains(\"-\") || t.contains(\"/\")'"
run "E2  a keyboard selection shows the badge (no mouse-up needed)" $R \
  "'                  abs(up.time - change) <= mouseUpWindow else { return [] }'" "'                  true else { return [] }'"
run "E3  the badge shows before the selection settles" $R \
  "'                  t - change >= settleDelay - 0.001,'" "'                  true,'"
run "E4  the degenerate AX rect (0,H,0x0) is trusted as an anchor" $R \
  "'        if let r = axBounds, r.width > 0, r.height > 0, r.minY < primaryScreenHeight {'" "'        if let r = axBounds {'"
run "E5  password managers get the badge" $R \
  "'        return !SecretApps.matches(bid, frontAppName)'" "'        return true'"
run "E6  the event title keeps the date words" $R \
  "'        var s = selection.replacingOccurrences(of: matched, with: \" \")'" "'        var s = selection'"
run "E7  every date is timed (noon events instead of all-day)" $R \
  "'        return patterns.contains { s.range(of: \$0, options: .regularExpression) != nil }'" "'        return true'"
run "E8  a conversion to the same local time is offered" $R \
  "', !tz.isSameAsLocal { out.append(.time(tz)) }'" "' { out.append(.time(tz)) }'"
run "U1  a single dot groups thousands (1.500 km reads 1500)" $U \
  "'            normalized = (dots > 1 && groupsOfThree(\".\")) ? '" "'            normalized = groupsOfThree(\".\") ? '"
run "U2  temperature converted as a ratio" $U \
  "'        case (.fahrenheit, .celsius): v = (q.value - 32) * 5 / 9'" "'        case (.fahrenheit, .celsius): v = q.value * 5 / 9'"
run "U3  imperial gallon instead of US" $U \
  "'            case .gallonUS: return 3.785411784'" "'            case .gallonUS: return 4.54609'"
run "U4  -0 can be shown" $U \
  "'        return f.string(from: NSNumber(value: rounded == 0 ? 0 : rounded)) ?? \"–\"'" "'        return f.string(from: NSNumber(value: rounded)) ?? \"–\"'"
run "U5  Foundation-style six-figure pound (0.453592)" $U \
  "'            case .pound: return 0.45359237'" "'            case .pound: return 0.453592'"
run "T1  PST follows Los Angeles (UTC-7 in October) instead of its definition" $T \
  "'\"PST\": f(-8, \"America/Los_Angeles\")'" "'\"PST\": r(\"America/Los_Angeles\")'"
run "T2  the day shift is dropped" $T \
  "'                      dayShift: max(-1, min(1, dayShift)), regionNote: note)'" "'                      dayShift: 0, regionNote: note)'"
run "T3  12am is noon and 12pm is 24:00" $T \
  "'            return ((h % 12) + (pm ? 12 : 0), minute)'" "'            return (h + (pm ? 12 : 0), minute)'"
run "T4  no daylight note when the region disagrees" $T \
  "'            if regionOffset != srcTZ.secondsFromGMT(for: instant) { note = RegionNote(regionID: id, regionOffset: regionOffset) }'" "'            _ = regionOffset'"
run "S1  Apple Passwords is not a secret store" XFinder/Core/SecretApps.swift \
  "'\"keychain\", \"passwords\",'" "'\"keychain\",'"
run "E9  every AX error is retried (a final -25207/-25211 retries forever)" $R \
  "'        guard error == axCannotComplete, attempt >= 0, attempt < registrationRetryDelays.count else { return nil }'" "'        guard attempt >= 0, attempt < registrationRetryDelays.count else { return nil }'"
# E10 drops the attempt bound from the guard AND clamps the index, so the mutant retries forever instead of trapping.
# (Clamping the index alone was an EQUIVALENT mutant — the guard already returned nil at attempt 3 — and stayed GREEN.)
run "E10 -25204 is retried without a limit" $R \
  "'        guard error == axCannotComplete, attempt >= 0, attempt < registrationRetryDelays.count else { return nil }'" "'        guard error == axCannotComplete, attempt >= 0 else { return nil }; return registrationRetryDelays[min(attempt, registrationRetryDelays.count - 1)]'"
C=XFinder/Core/SmartSelect/CurrencyConversion.swift
run "C1  one separator + three digits read as cents (1.500 € becomes 1.5)" $C \
  "'        if tail.count == 3 && minorUnits(code) != 3 {'" "'        if tail.count == 3 && minorUnits(code) == 99 {'"
run "C2  \$ is not marked as a guess" $C \
  "'        if let c = assumed[marker] ?? assumed[lower] { return (c, marker) }'" "'        if let c = assumed[marker] ?? assumed[lower] { return (c, nil) }'"
run "C3  the ECB cross is inverted" $C \
  "'            value = a.value / s * t'" "'            value = a.value * s / t'"
run "C4  Vietcombank read at the Transfer rate" $C \
  "'rateAttribute: \"Sell\", textElement: \"DateTime\"'" "'rateAttribute: \"Transfer\", textElement: \"DateTime\"'"
run "C5  a dash rate is kept as 0" $C \
  "'            if let v = Double(cleaned), v > 0, v.isFinite { rates[code] = v }'" "'            rates[code] = Double(cleaned) ?? 0'"
run "C6  a table never goes stale (one request ever)" $C \
  "'        return age >= freshFor || age < 0'" "'        return age < 0'"
run "C7  ambiguous symbols (¥, kr) are guessed as a currency" $C \
  "'        guard !ambiguous.contains(marker), let (code, guess) = currency(for: marker),'" "'        guard let (code, guess) = currency(for: ambiguous.contains(marker) ? \"JP¥\" : marker),'"
run "C8  the local currency is converted into itself" $C \
  "'        guard let ctx = context, let a = parse(text), a.code != ctx.localCode,'" "'        guard let ctx = context, let a = parse(text),'"
run "C9  a week-old rate is still shown" $C \
  "'        return age >= -86_400 && age <= usableFor'" "'        return age >= -86_400'"
run "C10 no back-off after a failure" $C \
  "'        if let f = lastFailure, now.timeIntervalSince(f) < retryAfterFailure, now >= f { return false }'" "'        _ = lastFailure'"
echo "RESULT: $red/$total mutations RED"
restore
after=$(fails); echo "after restore failures: $after"
[ "$after" = "0" ] || { echo "FAIL: restored tree is not green"; exit 1; }
[ "$red" = "$total" ] || exit 1
