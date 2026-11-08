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
FILES="XFinder/Core/Archive/ArchiveEngine.swift XFinder/Core/Archive/ArchiveRunner.swift XFinder/Core/Archive/SystemArchiveReader.swift XFinder/Core/Archive/ArchiveSafetyRules.swift XFinder/Core/Archive/ArchiveJob.swift XFinder/Core/Archive/ArchiveRecoveryStore.swift"
for f in $FILES; do mkdir -p "$BK/$(dirname "$f")"; cp "$f" "$BK/$f"; done
restore() { for f in $FILES; do cp "$BK/$f" "$f"; done; }
trap 'restore' EXIT
# A signal must END the run: with INT/TERM in the restore trap, sh restored the files and carried on — a killed harness
# kept mutating, and a second copy started meanwhile read the first one's mutants as baseline failures (2026-10-14).
trap 'exit 143' INT TERM

FILTER='ArchiveEngine|ArchiveRunner|SystemArchiveReader|ArchivePlacement'
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

# Guards that another layer already covers. A mutation here MUST stay GREEN — that is the claim, and it
# is a claim about redundancy, not about coverage. Listed by name so a new survivor cannot hide among
# them: anything not on this list that stays green is a finding.
#
# C8 (availability fast path): the reader itself throws `libraryUnavailable`, which maps to the same
# failure, so removing the explicit check changes no observable behaviour. Measured: the mutant stays
# green. The explicit check is kept so the message does not depend on how the reader fails.
#
# A8/A9/C5/C6 were listed here in an earlier run and are NOT any more: they were missing tests, not
# equivalence. Each now has a test that drives the guard directly (`testThePostExtractionLinkWalkSees…`,
# `testAMissingArchiveIsRefusedByTheIdentityGuard…`, `testAnArchiveSwappedWhileTheDecoderRuns…`), and all
# four go RED. That is the difference between a redundant layer and an unguarded one.
EQUIVALENT="C8"

red=0; total=0; equivalent_seen=""
run() {   # run <name> <file> <old> <new>
  total=$((total+1)); mutate "$2" "$3" "$4" || exit 2
  n=$(fails); restore
  # No "Executed … with N failures" line means the mutant did not compile or the runner died.
  # That proves nothing about the tests — it is a broken mutation, never a pass.
  if [ "$n" = "NORESULT" ]; then echo "HARNESS ERROR: $1 produced no test result (mutant did not compile?)"; exit 2; fi
  id=$(printf '%s' "$1" | cut -d' ' -f1)
  if [ "$n" != "0" ]; then
    red=$((red+1)); echo "RED   $1 ($n failing)"
    case " $EQUIVALENT " in *" $id "*) echo "HARNESS ERROR: $id is listed as equivalent but the suite went RED — the list is stale"; exit 2 ;; esac
  else
    case " $EQUIVALENT " in
      *" $id "*) equivalent_seen="$equivalent_seen $id"; echo "GREEN $1 (0) -- expected: covered by a redundant layer" ;;
      *) echo "GREEN $1 (0) <-- the tests do not guard this" ;;
    esac
  fi
}

run "A1 two sources go to ditto again" XFinder/Core/Archive/ArchiveEngine.swift \
  "'        !(format == .zip && sourceCount == 1 && level == defaultLevel && !hasPassword && single != .link)'" \
  "'        !(format == .zip && level == defaultLevel && !hasPassword && single != .link)'"
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
  "'                let taken = existing(target) != nil || claimed.contains(target.path.lowercased())'" \
  "'                let taken = existing(target) != nil'"
run "A7 tar stores the staging symlinks" XFinder/Core/Archive/ArchiveEngine.swift \
  "'arguments: [\"-czhf\", output.path] + names,'" "'arguments: [\"-czf\", output.path] + names,'"

run "A8 escaping links inside an archive are accepted" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        return ArchiveEngine.escapingLinks(links).sorted()'" \
  "'        return []'"

# A9: a link walk that cannot see "._" names (as every FileManager listing is for regular ._ files — F1). bsdtar
# creates "._x" symlinks from a foreign tar, so the guard must still see them.
run "A9 the link check is blind to links named ._…" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            while let rel = walker.nextObject() as? String {\n'" "'            while let rel = walker.nextObject() as? String {\n                if (rel as NSString).lastPathComponent.hasPrefix(\"._\") { continue }\n'"

# ---- stage 03B: bounded inspection, ownership, cancellation, destination containment ----

# B1: the per-entry ledger goes back to the WHOLE batch budget (Boss approval point 3, the measured trap).
run "B1 per-entry ledger uses the whole budget again" XFinder/Core/Archive/SystemArchiveReader.swift \
  "'            let entryBudget = remainingOverflowed ? 0 : max(0, remaining)'" \
  "'            let entryBudget = bounds.maxDecodedBytes'"

# B2: the deadline is only checked between entries, never inside the payload loop.
run "B2 deadline leaves the block loop" XFinder/Core/Archive/SystemArchiveReader.swift \
  "'                try checkDeadline()\n                var block: UnsafeRawPointer?\n'" \
  "'                var block: UnsafeRawPointer?\n'"

# B3: the deadline is dropped entirely.
run "B3 deadline check removed" XFinder/Core/Archive/SystemArchiveReader.swift \
  "'            if elapsed >= budget { throw Failure.timedOut(after: elapsed) }'" "'            _ = elapsed'"

# B4: cancellation that lands before the pid is published is ignored again (the measured race).
run "B4 early cancel no longer kills the child" XFinder/Core/Archive/ArchiveRunner.swift \
  "'                if cancelledEarly.withLock({ \$0 }) || Task.isCancelled {'" \
  "'                if Task.isCancelled {'"

# B5: failure cleanup deletes an output path the job never created.
run "B5 failed compression deletes a pre-existing output" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            guard !outputPreexisted, fm.fileExists(atPath: output.path) else { return }'" \
  "'            guard fm.fileExists(atPath: output.path) else { return }'"

# B6: cleanup deletes by path without proving the job still owns the inode.
run "B6 ownership check dropped on cleanup" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            guard isStillOwned else { return false }'" "'            _ = isStillOwned'"

# B7: a destination symlink is followed again (measured: Merge wrote outside the chosen folder).
# B7: a destination symlink is followed again (measured: Merge wrote outside the chosen folder).
# One mutant for both call sites: the detector itself is what has to keep working.
run "B7 destination symlink detector disabled" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            if (info.st_mode & S_IFMT) == S_IFLNK { return current }'" \
  "'            if false { return current }'"

# C1: the manifest is validated AFTER extraction instead of before (the whole 03B point).
run "C1 pre-flight validation disabled" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        switch verdict {\n        case .rejected(let reasons):'" \
  "'        switch ArchiveSafetyVerdict.accepted(ArchivePlan(orderedEntries: [], declaredPayloadBytes: 0, peakBytes: 0, expansionRatio: nil)) {\n        case .rejected(let reasons):'"

# C2: duplicate/aliased entry names are not refused.
run "C2 duplicate entry names accepted" XFinder/Core/Archive/ArchiveSafetyRules.swift \
  "'                if existing.rawPath.utf8.elementsEqual(entry.rawPath.utf8) { reasons.append(.duplicatePath(key)) }'" \
  "'                if existing.rawPath.utf8.elementsEqual(entry.rawPath.utf8) { _ = key }'"

# C3: '..' entries are normalised away instead of refused.
run "C3 dot-dot entries accepted" XFinder/Core/Archive/ArchiveSafetyRules.swift \
  "'                reasons.append(.escapesRoot(raw))\n                return nil'" \
  "'                continue'"

# C4: absolute entries are accepted (ditto would strip the slash).
run "C4 absolute entries accepted" XFinder/Core/Archive/ArchiveSafetyRules.swift \
  "'        if raw.hasPrefix(\"/\") { reasons.append(.absolutePath(raw)); return nil }'" "''"

# C5: the archive identity is never revalidated before extraction.
run "C5 identity guard before extraction removed" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        guard Self.identityStillMatches(inspection.identity, at: archive) else {\n            owned.removeIfOwned()\n            return .failure(.archiveChanged(\"the archive changed after it was inspected\"))\n        }\n'" "''"

# C6: the archive identity is never revalidated after extraction.
run "C6 identity guard after extraction removed" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        guard Self.identityStillMatches(inspection.identity, at: archive) else {\n            owned.removeIfOwned()\n            return .failure(.archiveChanged(\"the archive changed while it was being extracted\"))\n        }\n'" "''"

# C7: a space rejection stops being recognised, so a full disk reports "unsafe archive" instead.
run "C7 space rejection no longer recognised" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            case .insufficientSpace(let required, let available): return .outOfSpace(required: required, available: available)'" \
  "'            case .insufficientSpace: return nil'"

# C8: an unreadable/unsupported format is extracted anyway.
run "C8 unsupported format extracted unverified" XFinder/Core/Archive/ArchiveRunner.swift \
  "'    static func extractToStaging(archive: URL, near destination: URL) async -> Result<ExtractedBatch, Failure> {\n        guard SystemArchiveReader.isAvailable else { return .failure(.readerUnavailable) }\n'" \
  "'    static func extractToStaging(archive: URL, near destination: URL) async -> Result<ExtractedBatch, Failure> {\n'"

# B8: the staging root is not required to be private.
run "B8 staging permission check removed" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        return permissions?.intValue == 0o700'" "'        return permissions != nil'"

# ---- stage 03C: reviewed placement, exclusive publication, replacement transaction, source deletion ----

# D1: Merge replaces colliding leaves again (the destructive behaviour measured in spec §2).
run "D1 merge replaces colliding leaves again" XFinder/Core/Archive/ArchiveEngine.swift \
  "'                if !taken || combines { break }'" \
  "'                if true { break }'"

# D2: folders stop combining, so every incoming folder is numbered beside the existing one.
run "D2 folders no longer combine in merge" XFinder/Core/Archive/ArchiveEngine.swift \
  "'                let combines = item.isDirectory && existing(target) == .directory'" \
  "'                let combines = false'"

# D3: a destination symlink stops being treated as an occupied name.
# D3: a destination link is treated as a FOLDER to merge into. This is the measured escape (spec §2):
# `dest/folder` was a symlink to another directory, Merge wrote `outside/same.txt`. A link must be an
# occupied name, never something to combine with. (`.link` → `.file` would be equivalent and is not
# mutated: both values mean "taken, not a directory", so no behaviour depends on telling them apart.)
run "D3 destination link is merged into as a folder" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        case S_IFLNK: return .link'" \
  "'        case S_IFLNK: return .directory'"

# D4: publication loses RENAME_EXCL, so it replaces again. Measured: `renamex_np(a, b, 0)` returns 0
# and `b` becomes `a`'s content — the exact silent overwrite every no-replace claim rests on.
run "D4 exclusive publication replaces the existing file" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 { return }'" \
  "'        if renamex_np(source.path, target.path, 0) == 0 { return }'"

# D5: the replacement transaction trashes the original and never puts it back.
run "D5 failed replace loses the original" XFinder/Core/Archive/ArchiveRunner.swift \
  "'                try FileManager.default.moveItem(at: trashed, to: existing)'" \
  "'                _ = trashed'"

# D6: the source-delete action ignores whether the archive completed (Boss decision 6).
run "D6 deletion ignores completion" XFinder/Core/Archive/ArchiveJob.swift \
  "'        outcomes.filter { \$0.outcome.isCompleted }.map(\.archive)'" \
  "'        outcomes.map(\.archive)'"

# D7: a partial placement is reported as deletable.
run "D7 partial placement counts as completed" XFinder/Core/Archive/ArchiveJob.swift \
  "'        var isCompleted: Bool { if case .completed = self { return true }; return false }'" \
  "'        var isCompleted: Bool { if case .completed = self { return true }; if case .partial = self { return true }; return false }'"

# D8: the delete confirmation defaults to the destructive button again.
run "D8 delete confirmation defaults to the destructive button" XFinder/Core/Archive/ArchiveJob.swift \
  "'                defaultsToCancel: true)'" \
  "'                defaultsToCancel: false)'"

# D9: per-file Trash failures are swallowed again (the `try?` this stage removes).
run "D9 per-file Trash failures are swallowed" XFinder/Core/Archive/ArchiveJob.swift \
  "'            } catch {\n                report.failed.append((source, \"\\(error)\"))\n            }'" \
  "'            } catch { _ = error }'"

# D10: unknown capacity is reported as a shortage again (the "Zero KB / Zero KB" lie).
run "D10 unknown capacity reported as a shortage" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            case .spaceUnknown: return .spaceUnknown'" \
  "'            case .spaceUnknown: return .outOfSpace(required: 0, available: 0)'"

# D11: a refusal no longer blocks the reviewed plan.
run "D11 refusals do not block extraction" XFinder/Core/Archive/ArchiveJob.swift \
  "'        var isExtractable: Bool { refusals.isEmpty }'" \
  "'        var isExtractable: Bool { true }'"

# D12: the recovery root deletes anything it is handed.
run "D12 recovery store deletes outside its root" XFinder/Core/Archive/ArchiveRecoveryStore.swift \
  "'        guard targetPath.hasPrefix(rootPath + \"/\") else {\n            throw Failure.outsideRoot(targetPath)\n        }'" \
  "'        _ = rootPath'"

# D13: the staged remainder is deleted instead of kept for recovery.
run "D13 unplaced remainder is discarded" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        outcome.recoveryRoot = recoverStagingRemainder(batch, root: recoveryRoot)'" \
  "'        discard(batch); _ = recoveryRoot'"

# D14: source archives stop being protected identities.
run "D14 source archives are overwritable" XFinder/Core/Archive/ArchiveRunner.swift \
  "'            if policy == .merge {\n                steps = ArchiveEngine.mergePlan(items: stagedTree(of: batch), into: destination) { url in\n                    if protectedPaths.contains(url.standardizedFileURL.path) { return .file }' " \
  "'            if policy == .merge {\n                steps = ArchiveEngine.mergePlan(items: stagedTree(of: batch), into: destination) { url in' "

# D15: the Ask choices default to a write again.
run "D15 Ask defaults to writing instead of Cancel" XFinder/Core/Archive/ArchiveEngine.swift \
  "'        static let defaultChoice: AskChoice = .cancel'" \
  "'        static let defaultChoice: AskChoice = .keepBoth'"

# D16: the result line reports a leaf whose name was inherited from a renamed parent folder — so the
# message names a rename the user never got (`deep.txt`) instead of the folder (`folder 2`).
run "D16 result line names an inherited leaf rename" XFinder/Core/Archive/ArchiveEngine.swift \
  "'        steps.filter(\.renamedHere).map { \$0.target.lastPathComponent }'" \
  "'        steps.filter { \$0.renamed }.map { \$0.target.lastPathComponent }'"

# Z1–Z3 (Boss, 2026-11-08): the single-source ZIP shape that failed on every entry point since 0a184ba.
run "Z1 one file is zipped with --keepParent again (parent/one.txt, read-back fails)" XFinder/Core/Archive/ArchiveEngine.swift \
  "'            let keepParent = single == .directory ? [\"--keepParent\"] : []'" \
  "'            let keepParent = [\"--keepParent\"]'"
run "Z2 a linked single source goes to ditto (archived under the target's name)" XFinder/Core/Archive/ArchiveEngine.swift \
  "'        !(format == .zip && sourceCount == 1 && level == defaultLevel && !hasPassword && single != .link)'" \
  "'        !(format == .zip && sourceCount == 1 && level == defaultLevel && !hasPassword)'"
run "Z3 the source kind follows links (a link counts as its target)" XFinder/Core/Archive/ArchiveRunner.swift \
  "'        case .link: return .link\n        case .directory: return .directory\n        case .file, nil: return .file'" \
  "'        case .link: return .file\n        case .directory: return .directory\n        case .file, nil: return .file'"

restore

for f in $FILES; do cmp -s "$BK/$f" "$f" || { echo "FAIL: $f not restored byte-identical"; exit 1; }; done
after=$(fails)
echo "suite after restore: $after failure(s)"
echo "RESULT: $red/$total mutations RED, expected-equivalent survivors:$equivalent_seen"
for id in $EQUIVALENT; do
  case " $equivalent_seen " in *" $id "*) ;; *) echo "HARNESS ERROR: $id is listed as equivalent but was not observed as a survivor"; exit 2 ;; esac
done
[ "$after" = "0" ] && [ "$((red + $(echo $EQUIVALENT | wc -w)))" = "$total" ] || exit 1
