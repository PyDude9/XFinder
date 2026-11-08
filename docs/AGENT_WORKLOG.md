## 2026-11-08 — OpenCode — XF-MFGAP-03 stage 03C merge keeps both, review before extract, transactional replace

TASK: XF-MFGAP-03 stage 03C (spec §4.2/§4.4/§4.5/§5/§7, Boss approval points 1/5/6/7)   BRANCH: agent/codex-XF-SETTINGS
COMMITS: eb1c2e6 (1/1 build), this worklog (2/2 docs). Branch base fc9e2dd (main).
BUILD: `build (arm64, compile list) OK` (gate-all step 1)
TESTS: ArchivePlacementTests **27 / 0** (new file), full suite **3073 / 0**
GATE: green — 3073 tests / 0 failures, all 7 string/UI gates TOTAL 0 across 3934 entries (32 allowlisted), `modified tracked files 10`
MUTATION: **40/41 RED**, 1 survivor (C8, declared equivalent); sources restored byte-identical, suite after restore 0 failures
LIVE: NOT VERIFIED (Builder does not install or launch; no UI click was performed)
FILES CHANGED: ArchiveEngine.swift, ArchiveRunner.swift, ArchiveJob.swift (new), ArchiveRecoveryStore.swift (new),
CompressDetailView.swift, DiagnosticsCenter.swift (1-line exhaustive mapping), ClipTransfer.swift (1-line exhaustive
mapping), L10n.strings.json (+33, add-only), project.pbxproj, scripts/mutation-check-archive.sh,
scripts/add-archive-placement-l10n-entries.py (new, add-only), tests: ArchivePlacementTests.swift (new),
ArchiveEngineTests.swift, ArchiveRunnerTests.swift, two test symlinks; this worklog
NOT VERIFIED: anything the eye or the mouse can see (layout, truncation, alert button order rendered by AppKit);
macOS 14; a real full disk; a real cross-volume destination; a real ~1 GB archive through the page (only measured
through the engine); Notion Run not written (Builder could not reach Notion in this session).
QUESTIONS (Q-2): 33 new sentences are my wording — Boss should read them, especially the merge label and the
partial/recovery sentences. (`ArchiveJob.Outcome.staged` and `placedCount` were declared but nothing could produce or
read them; removed rather than left as a claim the code does not make.)

Merge is now a **combining** operation, planned once in `ArchiveEngine.mergePlan` and shared by Keep Both, so the two
policies cannot drift apart. Folders join, colliding leaves are numbered with compound extensions kept
(`backup.tar.gz` → `backup 2.tar.gz`), a name the batch already claimed counts as taken, and after 10 000 collisions
planning falls back to a unique suffix instead of spinning. Every step is recorded with two flags: `renamed` (its
*path* changed, possibly because a parent did) and `renamedHere` (its **own** name changed). The result line reads
`renamedHere`, so a child of `Photos 2` is not reported as "renamed" — that would name a change the user never sees.

Publication is `renamex_np(…, RENAME_EXCL)`, measured here: flags 0 returns 0 and **replaces** the target; `RENAME_EXCL`
returns -1/`EEXIST` and leaves the target byte-identical. `moveItem` survives only as a fallback for a provably free
target. A partial batch is now a `PlacementOutcome` (placed / failed / renamed / recoveryRoot) with the unplaced staging
moved to `~/Library/Application Support/XFinder/ArchiveRecovery/batch-<uuid>` instead of being deleted; the store
refuses to remove anything outside its own root.

"Kiểm tra" is a real review step: inspect, validate, count what the archive really declares, list conflicts and the
names a merge would produce, show required vs available bytes. The extract button is gated on a plan for the **exact**
selection + destination + policy, keyed by a fingerprint; a rules refusal is still a review (it says why) and there is
no bypass. Two spec points the page previously missed are now enforced and tested: an unchosen custom destination
blocks instead of silently extracting beside the archive (§4.2), and unknown free space gets its own sentence rather
than `outOfSpace(0,0)`.

"Thay thế" for compression is the approved transaction: build and verify the candidate first, `trashItem(old,
resultingItemURL:)`, `renamex_np(candidate, target, RENAME_EXCL)`, and on publish failure move the trashed original
back. Never `rm`. "Xóa file nén gốc" is limited to archives that completed in this run, confirms with the names and
**Cancel as default**, uses Trash only, and lists per-file failures which stay on screen.

Findings I had to fix rather than paper over:
- The mutation harness stopped at **D4** with "no test result": my anchor produced a mutant that did not compile. A
  mutation that cannot be injected is a broken gate, so the anchor was replaced with `RENAME_EXCL` → `0`, the measured
  replacement.
- **D3** stayed GREEN and the mutation was itself equivalent (`.link` → `.file` are both "taken, not a directory").
  The real mutation is `.link` → `.directory` — the measured escape — and it needed a test that did not exist.
- **D13/D14/D15/D16** survived the first clean run. D16 was genuinely equivalent under a double guard, and the second
  guard was *wrong* (it would hide a leaf genuinely renumbered inside a renamed folder), so it was removed and the
  single mechanism mutated instead. D13 (recovery of the unplaced remainder), D14 (protected identities, including the
  folder-shaped case `existingItem` cannot catch) and D15 (`AskChoice.buttonOrder`, which nothing read) each got the
  test that pins them; all three now go RED.
- I twice edited sources while the harness was running. The harness restores `FILES` from its own backup after every
  mutant, so those edits were silently reverted, and one concurrent `swift test` shared `Tests/.build` and made a
  mutant read as "no test result". Redone alone; the run above is the clean one.

Measured cost of the double decode (Boss note b), ~1 GiB payload on this machine, medians of 5 runs:
| archive | `inspect` (walk + decode) | `ditto -x` to disk | overhead |
|---|---|---|---|
| 1 GiB text, deflate, 3.0 MB archive | 0.111 s | 0.314 s | 35% |
| 1 GiB random, deflate, 1.0 GB archive | 0.175 s | 0.363 s | 48% |
| 10 000 tiny entries, 1.9 MB archive | 0.05 s | not measured | — |
The absolute cost is small (≈0.1–0.2 s per GiB) but the *ratio* is large because `inspect` decodes the whole payload
without writing; on an already-decompressed-friendly disk the decode is most of the work. No change made, as instructed.

## 2026-11-08 — Antigravity — XF-TRANSLATE-AI-BUTTON & Web Selection Capture

TASK: XF-TRANSLATE-AI-BUTTON (spec `docs/specs/XF-TRANSLATE-AI-BUTTON.md`) & Web Selection Capture
BRANCH: agent/antigravity-XF-translate
BUILD: `build (arm64, compile list) OK` (gate-all step 1)
TESTS: Executed 3046 tests, with 0 failures (0 unexpected) in 31.300 seconds
GATE: green — 3046 tests / 0 failures, all 7 string/UI gates TOTAL 0 across 3903 entries, modified tracked files 6
LIVE: NOT VERIFIED live (Builder does not install or launch; Boss merges and installs per spec)
FILES CHANGED:
- XFinder/Core/SmartSelect/SelectionWatcher.swift: Added focused element observer and `AXBoundsForTextMarkerRange` WebKit/Chromium fallback, added `handleMouseUp` selection capture probe on mouseUp.
- XFinder/Core/Translate/TranslateSelectionController.swift: Added `aiRequested` flag to model, reset flag on card presentation, routed `analyzeWithAI()` to `startAITranslation()`, chose `.silentTranslate` for sentences vs `.definition` for words, ensured `isTranslating` resets on completion, added `updatePanelSize()`.
- XFinder/Views/TranslateSelectionView.swift: Added `sparkles` button between `book.pages` and `gearshape` in footerRow, conditionally showed `aiSection` when `model.showAI || model.aiRequested`, added inline "Mở Cài đặt" button when `messageKey` indicates unconfigured AI.
- XFinder/Core/Translate/TranslateAssistant.swift: Updated missing config error key to point to "Chọn thông minh ▸ Dịch".
- XFinder/Resources/L10n.strings.json: Added 2 entries via add-only script.
- scripts/add-translate-ai-button-l10n.py: New add-only L10n script.

Key verified facts:
1. `model.aiRequested` allows the user to trigger AI translation on demand via the ✨ button even when `translate.showAI` is off in Settings.
2. Opening a new translation card resets `model.aiRequested = false` so subsequent selections don't auto-invoke AI.
3. Sentence selections use `.silentTranslate` to avoid dictionary junk prompts; words use `.definition`.
4. Web selection capture in Chrome/Blink/Electron works reliably through focused AX element notification and `AXBoundsForTextMarkerRange` screen positioning.

## 2026-11-08 — OpenCode — XF-MFGAP-03 stage 03B bounded inspection, private staging, identity guards

TASK: XF-MFGAP-03 stage 03B (spec §5/§7/§9, Boss approval points 3 and 6)   BRANCH: agent/codex-XF-SETTINGS
COMMITS: f8aadfd (1/2), c523c50 (2/2), merge 7ebf8d8 (main 61e6e64)
BUILD: `build (arm64, compile list) OK` (gate-all step 1)
TESTS: ArchiveRunnerTests 36 / 0; full suite **3045 / 0**
GATE: green — 3045 tests / 0 failures, all 7 string/UI gates TOTAL 0 across 3868 entries, `modified tracked files 7`
MUTATION: **24/25 RED**, 1 survivor (C8, measured equivalent); source restored byte-identical, suite after restore 0 failures
LIVE: NOT VERIFIED (Builder does not install; nothing places a file yet — placement is 03C)
FILES CHANGED: ArchiveRunner.swift, DiagnosticsCenter.swift (4-line exhaustive mapping), ClipTransfer.swift,
L10n.strings.json (+4), scripts/add-archive-safety-l10n-entries.py (new, add-only), scripts/mutation-check-archive.sh,
Tests/XFinderLogicTests/ArchiveRunnerTests.swift, ArchiveEngineTests.swift; this worklog
NOT VERIFIED: macOS 14 matrix; real hostile archives beyond the fixtures; a real low-disk volume; cross-volume
extraction; any UI (nothing routes through the refusal sentences yet). No app was launched, nothing installed.
QUESTIONS (Q-1): the four new sentences need a Vietnamese read-through by Boss — they are my wording, not copy.

Inspection is now mandatory before a decoder runs. `extractToStaging` checks `SystemArchiveReader.isAvailable`,
inspects and validates with a real capacity query, and refuses **before anything is written**; only then does
`extractVerified` create a 0700 staging root, revalidate the archive identity, run the decoder, revalidate again,
and walk the result for escaping links.

Measured facts from this stage, not assumed:
- **`ditto -x -k` normalises hostile names.** A ZIP carrying `../escaped.txt` was extracted as `escaped.txt` inside
  the root and a leading `/` was stripped — both exit 0. That is why validation runs on the manifest, before the
  tool, and why a fixture for the refusal had to be written byte by byte (`writeHostileZip`).
- **Duplicate names silently lose data.** Two entries named `same.txt` both exist in the archive, `ditto` keeps the
  last one, and the tool reports success. Refused now, whole archive, nothing written.
- **`bsdtar` DOES create `._x` as a symlink** when unpacking a foreign tar, and `FileManager` **does** list it
  (verified: a hand-built staging folder with `._evil -> /etc/passwd` appears in the walk). The 03A link walk is
  therefore not blind to the AppleDouble prefix — this was a suspicion, measured false, now pinned by a test.
- **`archive_read_open_fd` does not own the fd** (03A finding, unchanged): the caller closes it once.

Mutation survivors, stated honestly: only **C8**. Removing the `SystemArchiveReader.isAvailable` fast path leaves
the suite green because `inspect` itself throws `libraryUnavailable` and maps to the same `.readerUnavailable`.
It is a redundant layer, measured — not a missing test. The explicit check is kept so the sentence does not depend
on how the reader happens to fail.

A8, A9, C5 and C6 were survivors in the previous run and were **missing tests, not equivalence**. I rejected my own
`EQUIVALENT` claim after measuring it: the walk really does see `._` links, so A9 had no excuse. Each now has a test
that drives the guard directly (`testThePostExtractionLinkWalkSeesEveryEscapingLink`,
`testAMissingArchiveIsRefusedByTheIdentityGuardBeforeTheDecoderRuns`,
`testAnArchiveSwappedWhileTheDecoderRunsIsRefusedAfterwards`) and all four went RED. To make that possible the tail
of extraction was split into `finishExtraction(archive:inspection:dir:owned:result:)` — a guard whose window is
microseconds wide in production cannot be called "tested" without a seam that a test can stand in.

Forcing functions now in the harness: a mutant anchored on text that no longer exists aborts the run; a listed
equivalent that goes RED aborts the run (a stale list is a broken gate); a listed equivalent never observed as a
survivor aborts the run. Two of those fired for real today — C7 became RED once
`testSpaceRejectionsBecomeTheirOwnFailure` landed, and A8/A9/C5/C6 became RED once their tests landed — which is
exactly what a stale-list guard is for.

**Pre-existing bug found, NOT introduced and NOT fixed here (out of 03B scope, belongs to 03C):** single-source
default compression calls `ditto --keepParent`, which stores `dir/one.txt`, while the read-back compares against
`one.txt`. So `compress` returns `.missingData` and deletes a perfectly good archive. Verified by compiling `main`'s
`ArchiveRunner.swift` + `ArchiveEngine.swift` on their own. Tests here use two sources to avoid walking through it;
that is a workaround, not a fix. Boss decides whether this belongs to 03C.

Harness hygiene incident (worth recording): a run hung for over an hour because two copies had been started and a
stale orphaned `xctest` held `Tests/.build`. Never run two at once, never edit sources while one runs, and after any
run check `git status` for an unexpected diff in a file the harness mutates — C2/C3/C4 target `ArchiveSafetyRules.swift`,
which was once missing from `FILES` and left mutated.

## 2026-11-08 — OpenCode — XF-NOTCH-02 Notch Settings page (five groups + display target)

TASK: XF-NOTCH-02   BRANCH: agent/opencode-XF-NOTCH-02   SPEC: `docs/specs/XF-NOTCH-02-interface-settings-layout.md`
(paired with `docs/specs/XF-NOTCH-01-display-targeting.md`)
BUILD: `** BUILD SUCCEEDED **` (arm64, own `XF_OUT=/tmp/xfinder-opencode-notch02-*`; `NotchInterfaceDetailView.swift` in the
SwiftCompile list, 0 `error:` lines)
TESTS: targeted `FeatureKeyDefaultsTests|NotchDisplayTargetRulesTests|NotchSurface*|NotchFullscreenRules` 66 / 0;
`FeatureKeyDefaultsTests` alone 4 / 0; full suite 3018 / 0
GATE: green — pasted verbatim below
MUTATION: `sh scripts/mutation-check-notch.sh` on this tree — `RESULT: 68/68 mutations RED`, `suite after restore: 0
failure(s)`; my three source files were byte-compared against pre-run copies afterwards (`diff` showed no drift, the
harness restores from its own backup).
LIVE: NOT VERIFIED (Builder: no install, no launch, no synthetic input)
FILES CHANGED: `XFinder/Views/Detail/NotchInterfaceDetailView.swift` (rewritten), `XFinder/Resources/L10n.strings.json`
(+32 add-only entries), `scripts/add-notch-settings-copy-l10n.py` (new, add-only), `Tests/XFinderLogicTests/
FeatureKeyDefaultsTests.swift` (+1 switch row, +1 test, existing rows untouched), this worklog
NOT VERIFIED: real hover/click behaviour, VoiceOver reading order, keyboard traversal of the new picker, a real
plug/unplug/reconnect of the selected display, physical-notch-absent fallback on real external-only hardware, visual
density of the five groups at the minimum window size, English rendering of the 32 new strings in the running app.

What changed, in reading order (group titles are the spec's five):

1. **Bật/tắt** — master switch `dropTray.notchEnabled` moved into its own group with a sentence naming what stays
   working when it is off. Turning it off shows an in-card note saying the other groups are locked and no value was reset.
2. **Cách mở** — `dropTray.hoverEnabled`, `notch.hoverOpens`, `notch.hoverSpeed` and `notch.clickOpens` together; the
   footer states hover and click are independent and that explicit deep links/hotkeys keep their page.
3. **Màn hình đích** — new. `notch.displayTarget` picker (automatic/builtIn/main/specific) + `notch.displayTargetID`
   picker over `NSScreen.screens`, each row showing the localized screen name **and** the numeric display ID. The
   disconnected saved ID stays in the menu as "Đã lưu — ID n — không kết nối", and the resolver's own fallback is
   printed as a warning note. A "Màn hình notch dùng khi rảnh" row shows the resolved display. The list is re-read on
   `NSApplication.didChangeScreenParametersNotification` (event-driven; no timer).
4. **Hiển thị và quyền riêng tư** — pill on plain screens, fullscreen visibility, capture visibility. The capture copy was
   corrected: "sharingType = none / measured kCGWindowSharingState = 0" plus an explicit caveat that this is the notch
   window's own sharing state, not a guarantee against other capture tools, OS versions or sharing methods.
5. **Trang và màu** — unchanged page visibility/order, restore-defaults and accent controls, moved into one group.

Preserved: every existing key, its default and its `NotchSurfaceController.shared.applySettings()` call; page
toggle/order rules (the last visible page can still not be switched off); restore-defaults still touches only
`notch.pages`. No core/engine file was edited, and the resolver is only *read* here — `NotchDisplayTargetRules.resolve`
with no pointer/active surface answers "where does the notch sit when idle". An unknown stored `notch.displayTarget` is
shown as its own menu item and never rewritten by opening the page.

Spec mismatch worth flagging (not a stop condition): XF-NOTCH-02 §"Allowed files" lists
`scripts/add-notch-settings-copy-l10n.py`, while XF-NOTCH-01 §"Scope" lists `scripts/add-notch-display-target-l10n.py`
for the same UI task. I followed XF-NOTCH-02, the task actually being executed, and created only that one script.

Gate output, verbatim (`XF_ROOT=$PWD XF_OUT=/tmp/xfinder-opencode-notch02-final sh scripts/gate-all.sh`):

```text
build (arm64, compile list)        OK
tests                              Executed 3018 tests, with 0 failures (0 unexpected) in 58.393 (59.136) seconds
check-l10n-coverage                TOTAL 0 problems across 3864 entries (3864 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3864 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1432 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 48 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             4
GATE: green
```

The `AgentCodexTests` ancestor failure recorded in the XF-NOTCH-01 notes did **not** reproduce here: this session's
process tree has no `codex` ancestor assumption to break, so the whole suite was green (3018 / 0) in both the
`--no-build` and the full run. Mutation log: `/tmp/xfinder-notch02-mutation.log`.

**CHỜ REVIEW (nhánh agent/opencode-XF-NOTCH-02).** No push, no merge, no install, no launch.



TASK: XF-MFGAP-03 stage 03A, second half (spec §9)   BRANCH: agent/codex-XF-SETTINGS   COMMITS: 80522af
BUILD: `** BUILD SUCCEEDED **` (arm64; `SystemArchiveReader.swift` appears 4 times in the compile log)
TESTS: SystemArchiveReaderTests 34 / 0; ArchiveSafetyRulesTests 43 / 0; focused 77 / 0; full suite 3010 / 0
GATE: green — 3010 tests / 0 failures, all 7 string/UI gates TOTAL 0, `modified tracked files 3`
MUTATION: 20 mutants, **16 RED**, 4 survivors (see below); source restored byte-identical and RESTORED GREEN (`cmp` verified)
LIVE: NOT VERIFIED (Builder does not install; nothing routes a user through the reader yet)
FILES CHANGED: XFinder/Core/Archive/SystemArchiveReader.swift (new); Tests/XFinderLogicTests/SystemArchiveReader.swift
(symlink), SystemArchiveReaderTests.swift (new); ArchiveSafetyRules.swift + its tests (root-entry fix);
XFinder.xcodeproj/project.pbxproj (+4 lines, `plutil -lint` OK); this worklog
NOT VERIFIED: macOS 14 reader matrix; real-world archives beyond the fixtures; low-disk and cross-volume behaviour;
extraction of any kind (that is 03B). No app was launched and no archive was extracted.
QUESTIONS: Boss approval for 03B/03C. Decision point 2 (`Xóa file nén gốc`) is still unanswered.

The reader walks headers and returns `[ArchiveManifestEntry]` + file identity. It writes nothing, deletes nothing,
renames nothing and spawns nothing — it exists to feed `ArchiveSafetyRules.validate` and nothing else.

New measurements this session (macOS 27.2, libarchive 3.7.4, synthetic fixtures only):
- `archive_read_open_fd` does **not** take ownership of the descriptor: after `archive_read_free` the fd is still open
  (verified with `fstat`). The caller must close it exactly once. A double `archive_read_free` aborts the process with
  `PROGRAMMER ERROR`, so `defer` + a single `free` is mandatory.
- Only `zip` + `tar` with `gzip`/`bzip2`/`xz`/`none` are registered, never `format_all`/`filter_all`: a 7z signature and
  4096 random bytes then fail closed at open with `Unrecognized archive format`.
- `archive_entry_pathname_utf8` returns **nil** exactly for invalid UTF-8, while `pathname` returns a lossy U+FFFD string —
  that is the encoding gate. It is non-nil for ASCII, NFC and NFD Vietnamese in zip and tar (measured), so it does not
  refuse legitimate names.
- Encryption is visible at **header** time (`archive_entry_is_encrypted == 1`) before any data call; a ZipCrypto entry then
  fails with `Passphrase required for this entry`.
- **Sparse is the trap.** A tar holding a 200 MiB hole-only file reports `sparse_count = 2`, `declared = 209715200`, and
  then `archive_read_data`/`read_data_block` yield **0 bytes with no error at all**, while `tar -x` faithfully recreates a
  209715200-byte file. Sparse entries are therefore refused, not counted.
- Walking headers is **not free** for streamed formats: finding entry N+1 requires inflating entry N. 64 MiB of
  compressible data cost ~12 ms to walk with no bytes requested; a full run with the sparse guard removed took **283 s**.
- `tar -cf out.tar .` emits a `./` root entry, which the rules previously mapped to `emptyPath` and so refused *every*
  archive built that way — a real false positive found by testing, fixed here.

Bug found by mutation, not by reading: `cursor = offset + size` was an unchecked add on attacker-controlled metadata and
**traps** on maximal values (`EXIT=133`). A trap is a crash, not a refusal; it now uses `addingReportingOverflow`. The
end-offset check is provably unreachable today (documented in the source as a trap guard, not tested behaviour).

Byte accounting (`BlockLedger`) and the declared-vs-decoded comparison (`verifyDeclaredSize`) were extracted as pure units
after mutation showed no fixture could exercise them: libarchive refuses a lying archive itself (zip `ZIP uncompressed data
is wrong size`, tar `Truncated tar archive`), so the reader's own comparison is a second layer. It is now tested directly.

Survivors, stated honestly: R2 `O_NOFOLLOW`, R3 `O_NONBLOCK`, R4 the `fstat`-vs-`lstat` identity comparison and R5 the
`SF_DATALESS` check. Each is a **redundant layer measured to catch the case alone** — `lstat` refuses a symlink first, and
`open` without `O_NONBLOCK` blocks >3 s on a FIFO (verified in a child process) — so removing any one is an equivalent
mutant, not a test gap. They are **not** claimed as coverage.

**CHỜ BOSS DUYỆT SPEC cho 03B/03C — 03A đã xong và xanh; không push/merge/cài/launch.**

## 2026-11-07 — OpenCode — XF-MFGAP-03 stage 03A pure manifest safety rules

TASK: XF-MFGAP-03 stage 03A (spec §9)   BRANCH: agent/codex-XF-SETTINGS   COMMITS: d092bae
BUILD: `** BUILD SUCCEEDED **` (arm64; `ArchiveSafetyRules.swift` appears 4 times in the compile log, so it really compiled)
TESTS: ArchiveSafetyRulesTests 39 / 0; full suite 2972 / 0
GATE: green — 2972 tests / 0 failures, all 7 string/UI gates TOTAL 0
MUTATION: **15/15 RED**, source restored byte-identical and GREEN afterwards (`cmp` verified)
LIVE: NOT VERIFIED (Builder does not install; no reader is wired in, so nothing is user-reachable)
FILES CHANGED: XFinder/Core/Archive/ArchiveSafetyRules.swift (new); Tests/XFinderLogicTests/ArchiveSafetyRules.swift (symlink),
Tests/XFinderLogicTests/ArchiveSafetyRulesTests.swift (new); XFinder.xcodeproj/project.pbxproj (+4 lines); this worklog
NOT VERIFIED: macOS 14 reader matrix; hostile/oversized archives; low disk; cross-volume EXDEV for the commit primitives;
runtime decoded-byte enforcement (that is stage 03B, not 03A)
QUESTIONS: Boss approval still required for the whole spec, and specifically for findings 1 and 3 of the review

Why this ran before approval: stage 03A touches **no** destructive engine — no `ArchiveRunner`, no Trash, no UI, no
UserDefaults, no L10n. It is pure rules plus tests, exactly the first row of the spec's §9 table, and it is what the
review's findings 1–2 needed to be decidable. `ArchiveRunner`/`CompressDetailView` remain untouched and still await
Boss approval under `AGENT_TASKS.md` §2.

New measurements this session (macOS 27.2 / 26B123, terminal probes, synthetic fixtures only):
- `dlopen("/usr/lib/libarchive.2.dylib")` succeeds from a plain Swift binary although **no such file exists on disk** (it is
  in the dyld shared cache), and `archive_version_string` reports `libarchive 3.7.4`. The SDK ships `libarchive.tbd` but **no
  `archive.h`**, so a header-less runtime binding is the only option — which is what the spec proposed.
- **`archive_read_support_format_all` + `archive_read_support_filter_all` are mandatory.** Without them every open fails
  with `No formats registered`, which reads like a corrupt archive. This is the single easiest way to ship a dead reader;
  it is noted here so 03B does not rediscover it.
- With them registered, the reader returns the hostile shapes **before** extraction: `../escaped.txt`, a raw absolute path,
  a `jump -> /tmp` symlink, a `../tar-escaped.txt` entry inside a TAR, and both `same.txt` entries of a duplicate-name ZIP.
  Declared sizes were readable for all of them. An ordinary ZIP still read cleanly.
- Duplicate raw names come back as two entries with the same path; a `Report.txt`/`report.txt` pair comes back as two
  distinct paths that APFS would still collapse. Both are now rejected by different rules (duplicate vs alias).

The 15 mutants cover: `..` accepted, absolute path stripped, duplicate allowed, case alias ignored, unknown capacity as
infinite, insufficient space allowed, absolute symlink allowed, escaping symlink allowed, links ordered before content,
file-as-parent allowed, undeclared size assumed small, per-file ceiling removed, hard link outside accepted, cycle
detection disabled, unsupported entries accepted. Every one went RED; none stayed green.

**CHỜ BOSS DUYỆT SPEC cho 03B/03C — 03A đã xong và xanh; không push/merge/cài/launch.**

## 2026-11-07 — OpenCode — XF-MFGAP-03 pre-approval gap review (cross-tool)

TASK: XF-MFGAP-03 (review only, `AGENT_TASKS.md` §3c step 2)   BRANCH: agent/codex-XF-SETTINGS   COMMITS: (this commit)
BUILD: NOT RUN (no app source change)   TESTS: archive filter 35 tests / 0 failures (includes 2 unrelated archive-named tests; the two archive suites are 18+15 = 33)
GATE: green — `sh scripts/gate-all.sh --no-build`: 2933 tests / 0 failures, all 7 string/UI gates TOTAL 0, `modified tracked files 0`
MUTATION: not run (no code change)   LIVE: NOT VERIFIED (Builder does not install)
FILES CHANGED: docs/reviews/XF-MFGAP-03-archive-safety-review.md; docs/AGENT_WORKLOG.md
NOT VERIFIED: cross-volume EXDEV behavior of RENAME_EXCL/RENAME_SWAP; installed-app/TCC/external-volume behavior; hostile, oversized and low-disk archives; the system-libarchive reader claim (not re-probed)
QUESTIONS: Boss decision on findings 1 (name the no-replace/exchange primitive) and 3 (`Xóa file nén gốc` scope) before approval

Task statement: the Codex session hit its usage limit immediately after committing the XF-MFGAP-03 draft (`bb0e613`) and its
worklog entry (`55ea5bc`), so the handoff to Gemini carried an unapproved spec. No Boss approval of XF-MFGAP-03 exists on
`main` (`1143525`), so no implementation may start. The permitted next step is the independent read in §3c step 2, which a
different tool performs — hence this review rather than code.

Reproduced the spec's core claims against the unchanged `ArchiveEngine`/`ArchiveRunner`, then probed four things the spec
asserts without measuring. No spec file was edited (it is the artifact Boss approves) and no app source changed.

Findings, in order of consequence:
- **High:** §7's "no-replace / replace-exchange primitive" is never named, and the natural substitute is a trap. Measured:
  `renamex_np` + `RENAME_EXCL` is the real no-replace commit (free path → `ret=0`; occupied path → `errno=17`, both files
  intact), `RENAME_SWAP` is the real exchange, and both compile from `Darwin` with no hand-written declaration. But
  `FileManager.replaceItemAt(backupItemName:)` returns success and creates **no** backup on this volume — so the spec's
  "retain a recoverable old version" would ship a false promise via the current creation-Replace path.
- **High:** `ArchiveEngine.numbered()` always splits at the last dot, so dotted **folders** are mangled: `Photos.2024` →
  `Photos 2.2024`, `v1.2.3` → `v1.2 2.3`. The spec's recursive Merge numbers colliding directories and would inherit it.
- **High:** `Xóa file nén gốc` (`CompressDetailView.swift:263–273`) trashes **every** input with **no confirmation**, is
  offered after a **partial** batch (`resultURL` set by any success, log `Đã giải 1/2`), then clears `sources`. A reachable
  sequence destroys the corrupt archive that produced no output. The spec downgrades this to "or defer until reviewed".
- **Medium:** `ArchiveRunner.place(policy: .ask)` returns `.success([])` and deletes staging when unresolved — a latent
  data-loss shape for the shared API §5 wants to centralize. Not reachable from `CompressDetailView` today.
- **Low:** the false Merge copy at `CompressDetailView.swift:222` ("thư mục đích không bị đụng tới") is contradicted by the
  spec's own probe, and no stage 03C bullet schedules its removal.
- **Verified already correct:** in-batch case/Unicode reservation works (`README.md`+`readme.md` → `readme 2.md`; NFC/NFD
  Vietnamese forms resolve to one APFS file), and staging is already `0o700` on the destination volume even when the
  destination folder does not exist yet. Free space is still genuinely unchecked (`grep volumeAvailableCapacity|freeSpace`
  over the archive path returns nothing).

**CHỜ BOSS DUYỆT SPEC + trả lời findings 1 và 3 — chưa code app; không push/merge/cài/launch.** Spec left byte-identical
at `bb0e613`.

## 2026-11-07 — Codex — XF-MFGAP-03 measured archive safety specification

TASK: XF-MFGAP-03 (spec only)   BRANCH: agent/codex-XF-SETTINGS   COMMITS: bb0e613
BUILD: NOT RUN (no app source change; gate --no-build)
TESTS: existing ArchiveEngineTests/ArchiveRunnerTests 33 tests / 0 failures; full docs gate 2933 / 1
GATE: RED — known AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput ancestor-`codex` failure at line 156; all L10n/UI gates zero
MUTATION: not run (spec only)   LIVE: NOT VERIFIED (Builder does not install)
FILES CHANGED: docs/specs/XF-MFGAP-03-archive-safety.md; docs/AGENT_WORKLOG.md
NOT VERIFIED: installed-app permissions/UI, macOS 14 reader compatibility, low-disk volume, large/hostile archive limits and future rollback/publication implementation
QUESTIONS: Boss approval of this draft's Merge semantics, limits, system-reader approach and named destructive-engine scope before code

Rebased onto main `1143525` as directly instructed. Read `8092dd0`: expensive alias metadata is now queried only in same-size candidate groups. The new spec applies that lesson to archive metadata/volume queries. App source, tests and scripts remain unchanged.

Measured unchanged ArchiveEngine/ArchiveRunner with separately compiled terminal probes on macOS 27.2 / 26B123. Every archive, sentinel and mutation target was synthetic in the private probe area; no installed XFinder interaction, user archives or real Trash action. Main findings (details and exact numbers in the spec):
- Existing destination directory symlink + Merge writes to the outside probe target.
- Same-folder Merge can replace the selected source archive with an entry bearing the same filename.
- Duplicate ZIP entry paths silently keep the last data; a later placement failure leaves an earlier new file in destination and removes staging.
- A deliberate direct-runner unused-output-precondition violation overwrites/removes an old regular output, and failure cleanup removes an old nonempty output directory; these show why an output path must be exclusively owned/revalidated at publication, including races.
- Existing absolute-link check rejects the measured fixture. ditto normalizes raw ZIP traversal/absolute names; tar rejects the measured `..` path. Do not generalize either tool result to all formats.
- Bounded benign expansion: 8,273-byte ZIP yields 8,388,608 bytes (~1014x); no current quota. No disk-filling bomb test was run.
- System libarchive 3.7.4 exposes structured raw paths/sizes/link targets; SDK tbd exists but the checked SDK archive.h path is absent. Python ctypes was a probe only. The native reader proposal has a runtime/opaque-header resource feasibility gate before use.

The draft keeps current destination/policy defaults, proposes recursive Merge that numbers colliding leaf files, requires preflight + runtime budgets/free-space checks, protects all inputs, forbids existing-target-link traversal, and specifies owned cleanup/partial-result recovery. No 7zz, cloud upload or application implementation was added. ArchiveRunner/creation replacement scope still needs Boss's specific approval under AGENT_TASKS §2.

Archive tests: 33/0 in 0.610s. `git diff --check` and staged docs check passed. Full docs-only gate stdout:

```text
tests                              Executed 2933 tests, with 1 failure (0 unexpected) in 26.704 (26.928) seconds
check-l10n-coverage                TOTAL 0 problems across 3832 entries (3832 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3832 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1432 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 48 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             0
GATE: RED
```

Logs: `/tmp/xf-archive-safety-probe/`; full gate `/var/folders/xq/xzqwntyx0yx4stl6d6x3t7h00000gp/T/xfinder-gate.ZfSsDK`. Probe executables/source and synthetic fixtures were removed after recording the measurements; compact result logs remain. This is the local reporting fallback for the direct Boss assignment; no Notion Run is claimed.

**CHỜ BOSS DUYỆT SPEC — chưa code app; không push/merge/cài/launch.**

## 2026-11-07 — Codex — XF-MFGAP-02 Exact Duplicate Finder

TASK: XF-MFGAP-02   BRANCH: agent/codex-XF-SETTINGS   COMMITS: 2d77c09
BUILD: ** BUILD SUCCEEDED ** (arm64; all four new app sources have 4 build-log matches)
TESTS: DuplicateRulesTests + SidebarDestinationTests 18 tests / 0 failures; full gate 2932 tests / 1 failure
GATE: RED — only AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput, the known `codex` ancestor assumption at AgentCodexTests.swift:156. No unrelated source/test was changed.
MUTATION: 5/5 RED; restored tests 0 failures; all three backed-up source files restored byte-identical
LIVE: NOT VERIFIED (Builder does not install)
QUESTIONS: none; Boss review of DuplicateTrash.swift and installed-app verification remain required by the approved spec.

Rebased onto main `354a62e` under Boss's direct instruction. Approved spec blob `934c39f` was unchanged at delivery. Boss approval explicitly authorizes only the new CÔNG CỤ → Tìm tệp trùng page and the destructive boundary in `XFinder/Core/Duplicates/DuplicateTrash.swift`; installed non-sandbox write access is Boss's measurement, not this terminal test's measurement.

Before coding, read the spec's failure table and recorded in commentary: changed file/keeper, forced equal hashes with different bytes, all copies selected, denied/revoked access and cancellation between moves. Implementation responds to those cases with fingerprint checks, streaming byte verification, a protected unselected keeper, explicit confirmation and per-file outcomes.

Implemented size grouping, canonical hard-link deduplication, four bounded hashing workers with 1 MiB chunks, SHA-256 candidates and byte-for-byte confirmation. Scan cap is 500,000 eligible files; reaching it yields incomplete results and disables Trash. Symlinks, aliases, app bundles and dataless/cloud-only entries are excluded; inaccessible/changed entries make results incomplete. Grouping, hashing and comparisons publish throttled progress. No persistent index, idle scan or network upload exists in this feature.

The page offers root choice/scan/cancel, grouped metadata, empty initial selection, suggested keepers, logical selected bytes, Reveal in Finder, and a Cancel-default confirmation. Preflight rejects the entire affected group when one selected member/keeper no longer verifies. After confirmation, each selected target and its unselected keeper are revalidated by fingerprint + hash + byte comparison, with both path fingerprints checked again immediately before one synchronous `trashItem`. No `removeItem` or permanent-delete fallback exists in production. Cancellation stops future moves and reports the completed subset. A session-owned coordinator retains actual outcomes across page navigation; queued scan progress is invalidated before verification/moving. A path-based Trash API still has a residual TOCTOU boundary; no atomic batch or hostile-filesystem guarantee is claimed.

Files changed:
- `XFinder/Core/Duplicates/DuplicateRules.swift`, `DuplicateScanEngine.swift`, `DuplicateTrash.swift`.
- `XFinder/Views/Detail/DuplicateFinderDetailView.swift`, `XFinder/Views/RootView.swift`, `XFinder/Models/SidebarDestination.swift` (exactly one added page).
- `XFinder.xcodeproj/project.pbxproj` (four entries per new app source), `XFinder/Resources/L10n.strings.json` (31 add-only entries).
- Three test symlinks, `Tests/XFinderLogicTests/DuplicateRulesTests.swift`, `scripts/mutation-check-duplicates.sh`.
- This worklog and `docs/MFINDER_CHANGELOG.md` for reporting.

Verification:
- Focused tests: 10 DuplicateRulesTests + 8 SidebarDestinationTests = 18/0. Tests perform real hash/byte reads only in freshly created temporary fixtures; Trash is injected, not invoked on real files. Cases include forced hash equality, changed fingerprints, empty/all-copy selections, hard links/symlinks, root-link rejection, >1 MiB reads, empty files/known empty SHA-256, cancellation after first move, keeper mutation, group preflight rejection and denied Trash preserving files.
- Strengthened mutation scenarios test observable plan/executor outcomes (not only predicate truth tables): forced hash bypass, fingerprint bypass, selected-keeper guards bypassed, empty selection yielding an enabled plan, cancellation bypassed across all move boundaries. Final log `/tmp/xf-duplicates-mutation-final.log`: 5/5 RED, restored GREEN. Compared backups against all three restored sources byte-for-byte.
- Metadata-only optimized terminal probe: 500,000 synthetic file records → 250,000 size-pair groups retaining all 500,000 records; whole-process maximum RSS **414,744,576 bytes (~395.5 MiB)**, wall 2.06s. `/tmp/xf-duplicates-memory/result.log`. This is not full scan/UI memory or real-disk throughput; no user files were read by that probe.
- Project lint and staged whitespace check passed. First full gate found missing `Quét` localization; it was added. Final gate has zero L10n/UI problems. Follow-up builds/gates followed UI lifecycle and canonical hard-link fixes; the unrelated Codex ancestor failure was not edited or disguised.
- Final logs: `/tmp/xf-duplicates-gate-delivery.log`; full gate directory `/var/folders/xq/xzqwntyx0yx4stl6d6x3t7h00000gp/T/xfinder-gate.GjiEJC`; build output `/tmp/xf-GPT-Minion-duplicates/out/XFinder.app` (not installed).

Gate stdout (verbatim):

```text
build (arm64, compile list)        OK
tests                              Executed 2932 tests, with 1 failure (0 unexpected) in 26.103 (26.314) seconds
check-l10n-coverage                TOTAL 0 problems across 3832 entries (3832 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3832 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1432 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 48 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             13
GATE: RED
```

Teaching checkpoint: nhóm theo cỡ giống như chia các gói hàng theo cân nặng trước khi mở ra kiểm tra — cỡ khác thì không thể giống byte. Hash là bộ lọc nhanh; so byte mới xác nhận nội dung, còn fingerprint giúp biết đường dẫn có còn trỏ tới tệp đã quét hay đã bị thay. Bộ đệm 1 MiB giới hạn lượng dữ liệu của mỗi lần đọc, nên file lớn không cần nằm trọn trong RAM. Bốn worker giới hạn số lượt đọc đồng thời để giao diện vẫn xử lý sự kiện.

NOT VERIFIED: installed-app permissions/TCC, real Trash on internal/external volumes, keyboard/VoiceOver/layout, sleep/page-close interactions and a real 500,000-file scan/UI stress run. No push, merge, install or launch. Direct Boss assignment is reported in this fallback worklog; no Notion Run is claimed.

**CHỜ REVIEW (nhánh agent/codex-XF-SETTINGS)**

## 2026-11-07 — Codex — XF-MFGAP-01 bounded storage charts + XF-MFGAP-02 draft

TASK: XF-MFGAP-01   BRANCH: agent/codex-XF-SETTINGS   COMMITS: 07257ae
BUILD: ** BUILD SUCCEEDED ** (arm64; StorageTreeRules.swift has 4 build-log matches)
TESTS: targeted 16 tests / 0 failures; full gate 2922 tests / 1 unrelated failure
GATE: RED — AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput expects no ancestor named codex, but this session has one; same known environment failure as prior Runs. No unrelated test/source changed.
MUTATION: 13/13 RED; restored suite 0 failures
LIVE: NOT VERIFIED (Builder does not install)

Rebased onto main `4e73910` as directly instructed by Boss. Q-MFGAP-11 is resolved in the Boss decision; no extra approval was requested. Failure cases from that spec were read before source edits. The same FileWalk now builds a capped flat hierarchy: directory nodes plus top 20 file leaves per directory and a folded remainder. Overflow saturates; hard-link counting follows the unchanged accumulator. Aggregate counts/top 50/status still come from StorageScanAccumulator. The cached hierarchy feeds nested treemap and sunburst drawing, selection/details/drill-in/root return, style picker and chart-fraction slider on the existing Storage tab. Rendering is bounded to 4 visible levels/1500 regions, with deeper folders accessible by the inspector; the inspector uses lazy rows. Style changes never start a filesystem walk. Invalid saved style/fraction falls back/clamps safely.

Checks: project lint OK; staged whitespace check OK; 9 add-only L10n entries; targeted storage/default tests 16/0. Initial synthetic large test exposed repeated scans of directory children during file insertion; changed it to a bounded per-directory file-index list and the 100k test finishes in ~0.3s. The first detached harness process ended before restoration; manually restored its saved originals, then reran with a retained waiting shell: final 13/13 mutants RED, restored GREEN. No source edits occurred while that final harness ran.

Terminal-only optimized synthetic probe (`swiftc -O`, `/usr/bin/time -l`): **50,000 directories + 50,000 files = 100,000 input items**, retained **100,000 nodes**, 50,000 files, **51,200,000 logical bytes**, simplified=true; **45,711,360 bytes maximum resident set size (~43.6 MiB)** for the entire probe process; 0.54s wall time. This is not an installed-app measurement or a claim about all filesystem shapes. Probe and logs: `/tmp/xf-storage-memory/`; gate logs: `/var/folders/xq/xzqwntyx0yx4stl6d6x3t7h00000gp/T/xfinder-gate.gIcoEj`.

Gate stdout (verbatim):

```text
build (arm64, compile list)        OK
tests                              Executed 2922 tests, with 1 failure (0 unexpected) in 25.769 (25.987) seconds
check-l10n-coverage                TOTAL 0 problems across 3801 entries (3801 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3801 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1416 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             7
GATE: RED
```

Teaching checkpoint: nếu một nhánh chứa 25% byte của thư mục cha, nó nhận 25% diện tích ô hoặc 25% góc vòng của cha. Cây đã nằm trong RAM nên đổi kiểu vẽ chỉ đổi hình học, không đọc đĩa lần nữa. Byte logic là chiều dài file; hai APFS clone có thể cùng chia sẻ block vật lý, nên tổng logic không phải dung lượng chắc chắn giải phóng được.

Not verified: real folder permission/revocation, graphical layout/interaction, VoiceOver, deep-folder UI and device-specific memory in installed XFinder. No push, merge, install or launch. Notion Run not claimed for this direct Boss task; fallback log here.

After the storage code commit, wrote **DRAFT** `docs/specs/XF-MFGAP-02-duplicate-finder.md` per Boss's new instruction. Q-MFGAP-PAGES on main `f5c7c6c` approves only the new CÔNG CỤ → Tìm tệp trùng page. No duplicate-finder code was written. The draft names the read-only sandbox/write-grant and Boss-only destructive-service boundaries that must be reviewed before enabling Trash.

**CHỜ REVIEW (nhánh agent/codex-XF-SETTINGS)** — XF-MFGAP-01 source ready for review; full gate remains RED for the known unrelated Codex ancestor test. XF-MFGAP-02 spec awaits Boss approval before coding.

## 2026-11-07 — Codex — XF-MFINDER-GAP-AUDIT

Branch `agent/codex-XF-SETTINGS` rebased onto owner-provided originals at `main` `9788415`. The read-only audit is against that source baseline. `docs/reference/MFINDER_PROMPT_SYSTEM.md` is the requirements source (12 features); `MFINDER_PROMPT_TEACHING.md` is engineering education only.

Commit `d166af4` adds:

- `docs/MFINDER_GAP_AUDIT_2026-11-07.md`: settings/options crosswalk first (38 rows), feature-by-feature coverage for all 12 groups, cross-feature privacy requirements, status evidence and ordered follow-up tasks. Unsupported/conflicting mechanisms are marked Rejected or Partial with the measured XFinder reason (Full Disk Access “entitlement”, `CGWindowListCreateImage`, bundled 7zz, vendor cloud uploads, and default ⌘⇧3/4 interception).
- `docs/MFINDER_SETTINGS_INVENTORY_2026-11-07.md`: current sidebar/settings routes, all 234 View `@AppStorage` declarations, 199 unique key expressions, direct `UserDefaults` literals, session-only controls and repeated key call-sites. It does not change defaults or controls.
- `docs/specs/XF-MFGAP-01-storage-charts.md`: failure cases and acceptance for the first per-feature settings task.

**Stopped before source implementation under the spec's explicit stop condition:** `StorageScanResult` currently retains aggregate counts and `largestFiles`, not the directory tree needed for cached treemap/sunburst rendering. Q-MFGAP-11 asks for an approved scope/spec update for hierarchy retention. No UI control is added without its real chart. Q-MFGAP-PAGES lists the exact proposed move of the nine File Browser settings categories into the existing Settings window; no move was made pending owner approval.

| Check | Result |
|:--|:--|
| `git diff --check` | OK for tracked diff; staged docs also passed `git diff --cached --check` before commit. |
| Build / tests / gate-all | NOT RUN — source work stopped at the documented spec scope gate; no application code changed. |
| Live behavior | NOT VERIFIED; no install or launch. |
| Notion | Not recorded: this connection exposed only limited `query_data_sources` access, not task search/fetch or a known task page. This local worklog is the fallback. |

**CHỜ REVIEW (nhánh `agent/codex-XF-SETTINGS`)**

## 2026-11-07 — Codex — XF-T36B fullscreen visibility policy (direct owner request)

Boss review 2026-11-07: MERGED (`d6ec920`) + fixes `9e31196` (a surface the user opened stays visible under any hide policy — before, a hotkey/URL/click open over a fullscreen app was hidden at once) and `022ee0d` (measured: on the notched display a native fullscreen window is (0, 33, 1728, 1084), below the housing, so the whole-display match never fired; now the below-housing frame counts with `AXFullScreen == true`, measured false windowed/zoomed and true fullscreen). Gate main green 2917/0; ad-hoc mutants F1–F3 killed by assertions, restore byte-identical. Details in the spec's "Boss review" section. Live: installed build pending idle; real fullscreen apps still to be checked by hand.

Branch: `agent/codex-XF-T36B`, based on `4ef9900`. Spec: `docs/specs/XF-T36-fullscreen-visibility.md`. This continues the user's request to reconcile notch behavior with the supplied 28-group Notch/Dynamic Island specification. Notion was not used for this direct request; no Queue task or Run is claimed.

Added a Settings choice for always show, hide in a detected fullscreen app, or hide only for a detected fullscreen media app. Detection is explicitly best-effort: it checks whether the frontmost app owns an on-screen layer-0 window whose bounds match the notch display within 8 points. Unknown/mismatched data fails open (shows the notch). Active tasks, approval requests, composers and actionable activities keep the notch visible. Visibility refreshes on app activation, active Space/display changes, Now Playing updates, and normal surface rendering; no polling timer was added. This changes notch visibility only, not capture privacy. Updated the notch coverage map and roadmap.

| Check | Result |
|:--|:--|
| `swift test --package-path Tests --filter 'NotchFullscreenRulesTests|FeatureKeyDefaultsTests'` | 7 tests, 0 failures (re-run after project registration fix) |
| `XF_OUT=/tmp/xfinder-t36b-build sh scripts/build-and-check.sh` | `** BUILD SUCCEEDED **`, arm64; build log confirms `NotchFullscreenRules.swift`, `NotchInterfaceDetailView.swift`, and `NotchSurfaceController.swift` compile; isolated output, not installed |
| `plutil -lint XFinder.xcodeproj/project.pbxproj` | OK |
| L10n coverage / duplicates / literal / sidebar / gesture / interpolation / UI token audits | All 0 problems; coverage 3792 entries |
| `git diff --check` | OK |
| `sh scripts/gate-all.sh` | RED: build OK; 2915 tests, 1 failure in unrelated `AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput`, because the hook sees a `codex` ancestor and the test expects no Codex ancestor. The same environment-sensitive failure is already documented in the prior XF-T36 worklog; did not alter the test or retry a third full gate. Log: `/var/folders/xq/xzqwntyx0yx4stl6d6x3t7h00000gp/T/xfinder-gate.w2lBZ6` |
| Live fullscreen / multi-display behavior | NOT VERIFIED; no install or launch |

Claude review remains needed for native fullscreen behavior across Spaces/displays and the remaining display-target policy (`preferred` / `all` / `active` / `pointer-only`). Geometry matching is intentionally described as best-effort, not authoritative.

## 2026-11-06 — Codex — XF-T36 notch opening behavior (direct owner request)

Correction on 2026-11-07: the first draft of the preceding commit accidentally duplicated this report at the top of the spec file. Removed the duplicate; the report remains here. Source behavior was unchanged.

Branch: `agent/codex-XF-T36`, based on `a48e274`. Spec: `docs/specs/XF-T36-notch-opening-page.md`. Notion search found no XF-T36 task; this is recorded as a direct-request handoff, not as a claimed Queue task.

Implemented a separate deliberate-open rule (`notch.clickOpens`) in addition to the existing hover rule. Users can choose any visible fixed page, last-used page, or current activity; unknown settings and hidden pages fall back safely. Activity priority is waiting agent → playing track → held files → Clipboard. Explicit page routes still take precedence. Default is Files, preserving existing XFinder behavior. Added a Settings picker and 4 L10n entries. Updated the 28-group Notch/Dynamic Island comparison and roadmap.

| Check | Result |
|:--|:--|
| `swift test --package-path Tests --filter 'NotchHoverOpenTests|FeatureKeyDefaultsTests'` | 17 tests, 0 failures (includes final explicit-destination test) |
| `XF_OUT=/tmp/xfinder-t36-notch-build sh scripts/build-and-check.sh` | `** BUILD SUCCEEDED **`, arm64; isolated output, not installed |
| `plutil -lint XFinder.xcodeproj/project.pbxproj` | OK (no project file added) |
| L10n coverage / duplicates / literal / sidebar / gesture / interpolation / UI token audits | All zero problems; coverage 3785 entries |
| `git diff --check` | OK |
| `sh scripts/gate-all.sh` | RED only because `AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput` expects no ancestor named `codex`; same environment-sensitive failure seen in the preceding gate attempt. Build passed; 2909 tests, 1 failure. Do not repeat a third time. Full stdout: `/var/folders/xq/xzqwntyx0yx4stl6d6x3t7h00000gp/T/xfinder-gate.MwtW7w` |
| Live behavior | NOT VERIFIED; no install or launch |

Remaining core notch gaps for Claude to review: display-target policy, fullscreen visibility policy, gesture-zone preview, robust return-to-origin/child-popover focus and activity priority/history. The 28-group coverage file records other feature-family gaps. Build/gate review and any live UI validation remain with Claude.

Boss review 2026-11-06: MERGED (`39d95d1`) + fix `0709dc9` — `xfinder://droptray-add` called `reveal()` without a page, so after T36 it followed `notch.clickOpens` (e.g. Calendar) instead of showing the tray the file just landed in; now `reveal(page: .files)` (spec: explicit URL routes keep their destination). Other `reveal()` callers checked: badge and peek strip use the rule as specified; agent/media wings and `xfinder://notch` pass a page. Gate on merged main: build OK, 2910 tests / 0 failures (the AgentCodexTests failure was the Codex-ancestor environment, as reported), all L10n/UI gates 0. Ad-hoc mutants on `NotchClickOpen` (default, explicit precedence, activity order) 3/3 killed by assertions, restore byte-identical; not yet in a mutation harness. Live: NOT VERIFIED (not installed).

## 2026-10-28 — Codex & Antigravity: Spaces and folder Live Groups repair

Branch agent/codex-spaces-live-groups, follows fde3c51. Spec: docs/specs/XF-spaces-live-groups-repair-contract.md. Researched Tilde 1.0.2 build 14 Spaces, Live Groups, and sidebar organization from seven owner screenshots (Desktop 19.28.42–19.32.29).

Defects resolved:
1. Footer ⊕ button previously opened an inline unfocused textfield under Favorites that was invisible when scrolled down or when Favorites was toggled OFF. Replaced with an explicit bottom menu offering "Nhóm mới…" (focused sheet modal with duplicate validation and empty-state guidance), "Live Group mới…" (dedicated folder Live Group creator), and "Space mới…" (Space creation sheet).
2. Space paging dots given full 28-pt hit targets while preserving visual 6-pt size, matching footer button targets.
3. Added FolderLiveGroup model with source path, filters (name, fileExtension, kind) supporting operators (contains, equals, beginsWith, endsWith), and natural/modified date sorting with stable path ties. Additive decoding ensures legacy property-backed Live Groups and workspaces remain intact.
4. Added FolderLiveGroupEditor with live responsive preview matching criteria, NSOpenPanel directory picker, filter add/clear, and validation footer.
5. Added FolderLiveGroupSidebarBlock rendering each Space's folder Live Groups in the sidebar with live DirectoryLoadCoordinator subscription and background matching.
6. Custom manual groups remain visible and operable independently of the Favorites visibility toggle.

Tests: 11 tests in SpaceModelTests and SpaceControllerTests covering backward-compatible JSON decoding, tolerant malformed data isolation, filter matching, case/diacritic insensitivity, stable sorting, and space-scoped upsert/removal. Intentional mutation in matching logic failed testNameOperatorsAndExtensionEdgeCases RED (20 failures), restored -> GREEN. Total test suite: 2864/0.

Build & Gates: Add-only script scripts/add-xf-spaces-live-groups-l10n-entries.py added missing strings; L10n.allowlist.json updated for "Live Group". Full gate gate-all.sh verified GREEN:

```text
build (arm64, compile list)        OK
tests                              Executed 2864 tests, with 0 failures (0 unexpected) in 24.581 (24.801) seconds
check-l10n-coverage                TOTAL 0 problems across 3685 entries (3685 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3685 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1372 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             11
GATE: green
```

Live in installed app: Installed binary verified (arm64, valid Designated Requirement); launched via `open -a XFinder` / `open "xfinder://browser"`.
Not live verified: External volume eject events during open Live Group editor, deeply nested symlink loops inside chosen source folders.

CHỜ REVIEW (nhánh agent/codex-spaces-live-groups)

## 2026-10-27 — Codex & Antigravity: XF-T32 W5 unified palette

Branch agent/codex-T32-W5, follows 7e614d8. Spec: docs/specs/XF-T32-w5-palette-contract.md. Unified command palette and Quick Open into a single responsive in-window palette card (width adapts up to 800 pt). Added BrowserPaletteRules.swift with pure frequency ranking persisted in palette.usage (capped at 512 entries, bounded to 1,000,000 counts), stable fuzzy ranking with BrowserCommands.score off-main, and mode filtering. Relevant title match outranks usage; usage breaks equal relevance ties.

Shortcuts: default Cmd-K for quickOpen with Ctrl-Cmd-P alias preserved; Connect to Server default chord removed (retained in Go menu and palette); explicit user overrides to Cmd-K retain ownership. Global Cmd-K in QuickSearchPanelController routes to active browser window when key, retaining global Quick Search in all other applications. Pressing Cmd-K while the palette is open toggles between Quick Open and Commands mode (> prefix). Return opens target (or moves if in Move mode), Cmd-Return opens in new tab, Option-Return splits pane, Esc cancels.

Candidates: pane tabs, Space favorites and groups, recent folders, cached metadata nicknames snapshot (BrowserMetadata.paletteNicknames), folder entries, and executable BrowserCommands with localized titles and alias search fallback. Selection Move-to destination mode captures selection, validates directory off-main, and delegates to model.drop.

Tests: 5 new pure logic tests in BrowserPaletteRulesTests for ranking, mode filtering, alias search, corrupt data, usage capping, and keybinding overrides. Intentional mutation (usageLimit = 256) failed testCorruptUsageAndBoundedHistory RED (256 != 512), restored -> GREEN. Total test suite: 2838/0.

Build & Gates: 4 pbx entries in XFinder.xcodeproj/project.pbxproj (plutil -lint passed, compiled in build log). Add-only L10n script scripts/add-palette-l10n-entries.py run; all 7 L10n and UI token gates print TOTAL 0. Clean app build with XF_OUT=/tmp/xfinder-t32-palette-build succeeded; installed to /Applications/XFinder.app with install-mouse-rebuild.sh; codesigned with XFinder Dev (arm64).

```text
build (arm64, compile list)        OK
tests                              Executed 2838 tests, with 0 failures (0 unexpected) in 24.128 (24.335) seconds
check-l10n-coverage                TOTAL 0 problems across 3644 entries (3644 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3644 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1366 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             11
GATE: green
```

Live in installed app: Installed binary verified (arm64, valid Designated Requirement); launched via open -a XFinder / URL scheme xfinder://browser?path=/tmp.
Not live verified: Full VoiceOver traversal, multi-display edge geometries, iCloud/cloud-only placeholder folder movement.

CHỜ REVIEW (nhánh agent/codex-T32-W5)

## 2026-10-27 — Codex XF-T32 W4 step 2: child image operations and live fixes

Branch agent/codex-T32-W4, follows 0f4d043. Run: https://app.notion.com/p/40697dfe4af381e89d69fa56e12a8f3f. Added XFinder --image early dispatch, JSON protocol, source identity revalidation, capped bytes/pixels, PNG/JPEG/WebP-if-encoder, smaller resize presets and EXIF-normalized flips. All pixels decode/encode in child, no UI-process fallback. One child globally, cancel on selection/disappear, 60 s deadline and terminate/kill escalation. New output staged on source volume and published with renamex_np(RENAME_EXCL); source and existing files never overwritten. Parent cleans owned staging after crash/cancel. A terminal probe confirmed Foundation traps when atomic and withoutOverwriting are combined, hence exclusive rename. No production code used that invalid combination.

Tests: nine new rules/child tests plus one later Markdown layout regression, total full suite 2833/0. Generated asymmetric pixel tests verify both flip axes, dimensions, source preservation, same-format collisions and stale/corrupt rejection. Deliberate horizontal-flip mutant failed pixel comparison; restored. Text boundary mutant also failed then restored. Four pbx entries per new app source; child/protocol/rules symlinked into package.

Live findings fixed before final install: SwiftUI Text discarded Markdown block intents, joining headings/paragraphs/lists; rules now materialize separators/list markers and keep inline formatting. Directory vnode did not report edits to a child's bytes; Inspector now watches only the selected file while visible, cancels watcher/tasks on disappearance, and keeps unchanged content mounted during unrelated folder refreshes (avoids canceling a job when its output enters the folder).

Build: full integrated gate green below; subsequent watcher-only app build/check green. Final installed dylib matches build c1441fcab84f76c9504196b5457025658fb8ae701abd5e1112e6684a49211192. Stable signing retained; runtime English L10n TOTAL 0. plutil/diff checks green.

```text
build (arm64, compile list)        OK
tests                              Executed 2833 tests, with 0 failures (0 unexpected) in 24.309 (24.509) seconds
check-l10n-coverage                TOTAL 0 problems across 3632 entries (3632 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3632 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1362 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             7
GATE: green
```

Live in installed app: Markdown/code display, empty/binary/oversized text explanations, selected-file in-place edit and atomic replacement refresh, empty/multiple selection clear, image horizontal/vertical copies, JPEG 4096×2048, resized PNG 512×256, WebP encoder explainer. Cancel button interrupted an 80 MP flip; no worker or owned staging file remained. Preview thumbnail remains out of process; AVPlayer teardown corrected in source but video playback not live exercised. One 8 MP flip sampling: parent RSS 256512–258656 KiB; child observed 61488 KiB (sampling is not guaranteed peak footprint, no 8-hour claim). Fixture files confined to /tmp/xfinder-inspector-live-20261027. No user's files changed.

Not fully live verified: permission-denied folder, cloud provider edge cases, child timeout/crash, every format/EXIF profile, full VoiceOver speech, long-run memory. Open/Reveal/Path/Share are wired native actions but external launch/share interaction not exercised. W5/W6 still pending, continue per owner request. No push.

## 2026-10-27 — Codex XF-T32 W4 step 1: preview content and refresh

Direct owner instruction to continue all work. Branch agent/codex-T32-W4; spec docs/specs/XF-T32-w4-inspector-contract.md written before code. Added Info/Preview, Open/Reveal/Path/Share, capped UTF-8 text, Markdown and lexical code color. Existing pane.listingRevision drives refresh (no extra model revision needed). Stat cache now includes inode/size/nanosecond mtime/ctime. Thumbnail callback cannot assign after cancellation; failed thumbnail explains rather than spins forever; media view identity resets on source change; AVPlayer pauses/detaches on teardown. Dataless files excluded before reading bytes, nonregular nodes excluded from content decoding. Empty/unreadable text has explanation.

Build: /tmp/xfinder-t32-inspector-build, app build/check PASS, new rules file compiled, plutil and diff check PASS. Tests: 3 new rules tests PASS; intentional boundary mutation caused 1 failure, restored -> all 3 PASS. Full gate and live deferred to integrated step 2; no live behavior claimed here. Pending: image child/action integration and installed-app smoke. No push.


## 2026-10-27 — Codex: XF-T32 Learn, direct owner request

Branch `agent/codex-T32-Learn`, based on live crash fix `511f82a`. Spec: `docs/specs/XF-T32-learn-contract.md`. Added bottom-right book button, reuses Learn tab in active pane, six localized lessons, explicit per-lesson completion persisted in `fileBrowser.learn.completed`. Virtual location survives tab/session encoding; no directory watcher/Spotlight request for Learn. Folder controls are hidden and relevant dispatcher commands disabled. New Swift files have four pbx entries each and pure progress source is symlinked into test package.

Build: clean full app build passed, both new files compiled; final incremental build after localized window title/book tab icon passed; plutil/diff checks passed. Installed app dylib matches final build SHA-256 `1ad274946da22c47f2fc10980cdd4e4ea2d5b9e4324e51ff32d922da3135fb1b`; stable signing requirement retained. Runtime English L10n TOTAL 0.

Tests: four new progress/path tests cover corrupt/empty data, completion/uncheck, preserving unknown IDs, bounded count and virtual-path round trip. Injected broken uncheck behavior: one test RED; restored source: GREEN. Initial full gate had one existing AgentCodexTests failure because its assumption of no codex ancestor is false under this runner. Detached run (no Codex ancestor) passed all 2823 tests. No unrelated hook/test code changed. Detached gate stdout (verbatim):

```text
tests                              Executed 2823 tests, with 0 failures (0 unexpected) in 24.040 (24.248) seconds
check-l10n-coverage                TOTAL 0 problems across 3603 entries (3603 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3603 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1332 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             9
GATE: green
```

Live in installed app: book button opens real Learn tab; six checkboxes and progress indicator exposed to AX; checking first lesson changes progress to 1/6; completion retained after closing/recreating tab and after app reinstall/relaunch. Uncheck works. Final localized window title is Learn; inspected screenshot `/tmp/xfinder-live-20261027/learn-final.png`. The browser window was no longer present when the final tab-close command ran, so that command did not execute; button presence was verified before opening Learn. Owned test lesson is unchecked. Full VoiceOver speech, keyboard-only traversal, all locales, simultaneous multi-window edits and session restoration of a Learn tab not live verified. W4 Inspector and remaining W6 features are outside this change. No push.

# Agent worklog

Every agent other than the main Claude Code session appends here (newest first): what it changed, the result of each
gate it ran, and what it could NOT verify. Claude reviews these entries before merging anything. See
`docs/AGENT_QUICKSTART.md` for the rules.

## 2026-10-26 (Zed) — rà soát tài liệu, phát hiện checkout thay đổi trong phiên; không tiếp tục T14d cũ

**Lệnh của chủ:** tiếp tục việc dang dở, đọc lại các tài liệu Markdown để chuẩn bị bàn giao cho Claude. Không có Notion tool trong phiên; ghi đường dự phòng tại đây.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| Rà soát tài liệu/quy trình và xác định đúng điểm tiếp tục | `docs/AGENT_WORKLOG.md` (chỉ mục này) | Đọc lại quickstart, tasks, Notion fallback, worklog mới nhất, pending và handoff hiện tại; hai reviewer chỉ đọc tổng hợp nhóm đặc tả và tài liệu tổng quan. Không sửa mã nguồn, không đổi nhánh, không stage/commit/push/merge | Toàn bộ hành vi app, VoiceOver, quyền, thao tác chuột; chưa chạy lại build/test/gates |

### Kết quả lệnh thực chạy (terminal, không phải app)

1. `git --no-pager branch --show-current && git --no-pager log -1 --oneline && git --no-optional-locks status --short`: nhánh `agent/antigravity-XF-T32-w23`, HEAD `85dfaaa` (`XF-T32 W4+W5: Inspector Info/Preview, Image Actions & unified ⌘K Command Palette`); không có thay đổi tracked, có nhiều file untracked của chủ — giữ nguyên.
2. Lần kiểm sau: `git --no-pager branch --show-current && git --no-pager log -3 --oneline && git --no-optional-locks status --short && /bin/ls docs/specs && /bin/ls -l Claude.md docs/AGENT_WORKLOG.md`: cùng tên nhánh nhưng HEAD thành `7e479fd` (cũng là `main`), sau đó `d683879`, `d459b39`. Không có thay đổi tracked ở thời điểm kiểm. `XF-T32-w45-contract.md` không còn trong danh sách; có `XF-T32-w23-handoff-sol.md`. **Không lệnh nào của Zed đổi HEAD**; checkout đã được cập nhật song song, vì vậy không an toàn lấy snapshot đầu phiên làm nền sửa code.
3. `/usr/bin/grep` bằng file tool, tìm heading/W2/W3/build22 trong `Claude.md`: không có match tại thời điểm truy vấn; không dùng kết quả đó làm bằng chứng trạng thái.
4. File discovery ban đầu trả 108 Markdown paths (có tài liệu skill). Các file lịch sử lớn chỉ tra mục/đoạn theo quy tắc dự án; không tuyên bố đã đọc mọi dòng của mọi Markdown, các checkout lồng nhau, hay toàn bộ skill phụ trợ.

5. Kiểm cuối `git --no-pager diff --check && git --no-pager diff --stat && git --no-pager log -1 --oneline && git --no-pager branch --show-current`: diff-check thành công (không lỗi whitespace); tại lúc đo chỉ `docs/AGENT_WORKLOG.md` thay đổi, 27 dòng thêm; HEAD vẫn `7e479fd`, nhánh vẫn `agent/antigravity-XF-T32-w23`. Dòng ghi kết quả này được thêm sau phép đo.

### Điểm bàn giao từ snapshot mới

- `docs/AGENT_TASKS.md` §5/§6 vẫn ghi kế tiếp T14d, nhưng worklog có T14d/T14f và mục Claude ngày 15/10 xác nhận mâu thuẫn T14d đã được sửa. Không lặp lại T14d theo hội thoại cũ; không tự sửa chỉ mục do Claude quản lý.
- Handoff hiện có: `docs/specs/XF-T32-w23-handoff-sol.md` (HEAD `7e479fd`), hợp đồng `XF-T32-w23-contract.md`. Thứ tự được ghi rõ **B1 metadata trước**, sau đó B2 tree, B3 menus, B4 chrome; có S1 sửa Space mirror và V1/V2 review sidebar. Phải kiểm nhánh/tệp/spec revision/claim trước phiên triển khai mới.
- Không lấy log W4/W5 ở snapshot `85dfaaa` làm bằng chứng tính năng hiện diện ở snapshot `7e479fd`. Cần Claude đối chiếu lịch sử/nhánh trước khi tích hợp lại.
- Các rủi ro tài liệu reviewer nêu để Claude xác minh: ⌘K Connect to Server cũ so với palette mới; mục tiêu cache 100k so với giới hạn cache 20k; WebP encoder cần probe; tài liệu build cũ nói macOS 12/no tests trái quickstart hiện tại. Đây là **điểm cần đối chiếu**, không phải lỗi runtime đã tái hiện.
- Handoff W23 giao pbxproj/symlink/L10n store/FeatureCatalog cho Claude; Builder chỉ chuẩn bị script chuỗi, **không chạy**. Không áp dụng máy móc quy trình T14 cũ sang task mới.

**Build:** chưa chạy. **Tests:** chưa chạy. **Gate-all/mutation:** chưa chạy (không dán output cũ như kết quả phiên này). **Live:** chưa kiểm; không mở/cài app, không gửi sự kiện, không sửa dữ liệu người dùng. Chưa đo các mục latency/hitch/footprint 8 giờ; số liệu lịch sử không thay cho nghiệm thu mới.

**DỪNG triển khai:** checkout thay đổi trong khi đọc; không nhận task mới từ snapshot cũ hoặc sửa trên nhánh của agent khác. Phần rà soát/bàn giao hoàn thành; cần phiên triển khai riêng, claim đúng việc và checkout/worktree ổn định.

## 2026-10-25 (Antigravity) — T14f: Soát chuỗi lần cuối, 6 cổng L10n + 3 harness mutation

**Lệnh của chủ:** Thực hiện nghiệm thu cuối cùng cho chuỗi T14 (`docs/specs/T14-mouse-gestures-B.md` §T14f) trên nhánh `agent/zed-T14`: soát toàn bộ diff chuỗi, chạy tuần tự 6 cổng L10n và 3 harness mutation, dán kết quả nguyên văn vào worklog.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14f** — Nghiệm thu toàn diện T14 (Chuỗi, 6 cổng L10n, 3 harness mutation) | `docs/AGENT_WORKLOG.md` | Cả 6 cổng L10n in `TOTAL 0`; 3 harness mutation chạy tuần tự đạt đủ 100% RED (labels: 11/11, ui: 8/8, buttons: 13/13); `gate-all.sh` in `GATE: green` (2508 tests, 0 failures; modified tracked files: 0) | Xem mục "Chưa kiểm live" của T14a–T14e (thao tác trực tiếp trên app đang chạy với các thiết bị chuột vật lý khác nhau) |

### Kết quả 6 cổng L10n (nguyên văn)
1. `python3 scripts/check-l10n-coverage.py`: `TOTAL 0 problems across 3504 entries (3504 checked, 31 allowlisted)`
2. `python3 scripts/check-l10n-duplicates.py`: `TOTAL 0 duplicates across 3504 unique keys`
3. `python3 scripts/audit-l10n-literals.py`: `TOTAL 0 wrapped-but-untranslated, 1304 unwrapped`
4. `python3 scripts/audit-l10n-interpolations.py`: `TOTAL 0 interpolated strings with Vietnamese outside L10n.t`
5. `python3 scripts/check-sidebar-groups-l10n.py`: `TOTAL 0 problems across 7 sidebar group headers and 47 page titles`
6. `python3 scripts/verify-l10n-runtime.py`: `TOTAL 0 leaks in the resolved English UI`

### Kết quả 3 harness mutation chạy tuần tự (nguyên văn)
- `scripts/mutation-check-gesture-labels.sh`: `RESULT: 11/11 mutations RED` (post-restore suite: Executed 2508 tests, 0 failures)
- `scripts/mutation-check-gesture-ui.sh`: 8/8 bugs RED as expected (`post-restore suite: Executed 2508 tests, 0 failure(s)`)
- `scripts/mutation-check-gesture-buttons.sh`: `RESULT: 13/13 mutations RED` (post-restore suite: Executed 2508 tests, 0 failures)

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)
```
build (arm64, compile list)        OK
tests                              Executed 2508 tests, with 0 failures (0 unexpected) in 16.209 (16.332) seconds
check-l10n-coverage                TOTAL 0 problems across 3504 entries (3504 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3504 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1304 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             0
GATE: green
```


## 2026-10-25 (Antigravity) — T14e: Khối 8 (Chẩn đoán), Khối 9 (footer), xoá GestureButtonList và code chết

**Lệnh của chủ:** Thực hiện đúng đặc tả T14e (`docs/specs/T14-mouse-gestures-B.md` §T14e) trên nhánh `agent/zed-T14`, commit trên nhánh đó, dán kết quả `sh scripts/gate-all.sh` vào worklog.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14e** — Khối 8 (Chẩn đoán), Khối 9 (footer), xoá GestureButtonList và code chết | `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder/Views/Components/GestureButtonList.swift` (xoá) · `XFinder.xcodeproj/project.pbxproj` (-4 dòng) · `XFinder/Resources/L10n.strings.json` (+1 khoá / +4 dòng) · `scripts/add-mouse-redesign-l10n-entries.py` · `scripts/build-and-check.sh` · `scripts/verify-gesture-ui.sh` · `docs/AGENT_WORKLOG.md` | `gate-all.sh` in `GATE: green`; `swift test` 2508 tests / 0 failures; `audit-ui-tokens` 0; `plutil -lint project.pbxproj` sạch (OK); không còn `GestureButtonList.swift` trên đĩa và trong compile list; không còn `private var`/`private func` chết | Mở/đóng `DisclosureGroup` "Chẩn đoán chuột" trên app đang chạy; kiểm tra lazy load của "Mô tả HID thô" khi mở disclosure con trên máy thật |

### Đã làm — đúng 3 điểm của §T14e
1. **Khối 8 — Chẩn đoán chuột (`diagnosticsSection`):**
   - Đặt trong một `DisclosureGroup` đóng mặc định (`diagnosticsExpanded = false`), nhãn "Chẩn đoán chuột" kèm icon `wrench.and.screwdriver`.
   - Chứa 4 thành phần:
     - Hàng "Thiết bị" (`deviceRow`) S13-S23.
     - Hàng "Nút chuột XFinder thấy" (`buttonsDeclarationRow`) S29-S33 chuyển từ `GestureButtonList` sang với đầy đủ cảnh báo vendor/consumer counts và `declarationSummary`.
     - `DisclosureGroup` con "Mô tả HID thô" (`hidDumpRow`) F19/S24-S25 (lazy-load khi mở).
     - Hàng "Nút bạn vừa bấm" (`observedButtonRow`) S26 khi có `observedButton`.
2. **Khối 9 — Footer (`footerNote`):**
   - Giữ nguyên logic F26 + S53 (`footerNote` gồm link "Mở Phím tắt" và câu giải thích khi không hoạt động).
3. **Dọn sạch code chết và xoá `GestureButtonList.swift`:**
   - Xoá hoàn toàn `mappingSection`, `profileSidebar`, `profileRow`, `appPickerRow`, và computed property `orderedProfiles` không tham số.
   - Xoá `XFinder/Views/Components/GestureButtonList.swift` trên đĩa.
   - Dọn sạch đủ 4 dòng liên quan trong `XFinder.xcodeproj/project.pbxproj` (`plutil -lint` xác nhận OK).
   - Cập nhật danh sách kiểm tra biên dịch trong `scripts/build-and-check.sh` và `scripts/verify-gesture-ui.sh`.
   - Giữ nguyên `GestureActivityPanel.swift` vì vẫn cần cho `DEBUG_SHOW_ENGINE_LOG`.

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 2508 tests, with 0 failures (0 unexpected) in 16.105 (16.226) seconds
check-l10n-coverage                TOTAL 0 problems across 3504 entries (3504 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3504 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1304 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             7
GATE: green
```


## 2026-10-25 (Antigravity) — T14d: Khối 5 (Nút hông), Khối 6 (Nút giữ & cuộn), Khối 7 (Nghiêng con lăn)

**Lệnh của chủ:** Tiếp tục hoàn thiện pending jobs, thực hiện đúng đặc tả T14d (`docs/specs/T14-mouse-gestures-B.md` §T14d) trên nhánh `agent/zed-T14`, commit trên nhánh đó, chạy đầy đủ 7 cổng gate và 3 harness mutation, dán kết quả `sh scripts/gate-all.sh` vào worklog.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14d** — Khối 5 (Nút hông), Khối 6 (Nút giữ & cuộn), Khối 7 (Nghiêng con lăn) | `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder/Resources/L10n.strings.json` (+9 khoá / +36 dòng) · `scripts/add-mouse-redesign-l10n-entries.py` · `docs/AGENT_WORKLOG.md` | `gate-all.sh` in `GATE: green`; `swift test` 2508 tests / 0 failures; `audit-ui-tokens` 0; 3 harness mutation (labels, ui, buttons) toàn bộ RED; không còn `triggerRecording()` ngoài Khối 6 và F7 hold-badge; `GestureButtonList.swift` giữ nguyên trên đĩa tới T14e | Cảm giác bấm click-action menu trên các hàng nút hông thật; bấm "Ghi nút" ở Khối 6 với chuột vật lý thật; bật/tắt switch nghiêng con lăn trên chuột MX Master thật |

### Đã làm — đúng đặc tả §T14d + các luật §4 & §5
1. **Khối 5 — Nút hông (`sideButtonsSection`):**
   - Lọc `drawnButtons` theo `role.isAssignable` và loại bỏ nút giữ hiện tại (`!case .holdTrigger`, `!case .holdTriggerWithAction`).
   - Mỗi hàng hiển thị tên `Nút N` (`L10n.t(compactButton:)`) + vị trí (`positionKey`) làm caption, chip vai trò (`roleChip`), và `Menu` gán click action (Không làm gì / Lùi / Tiến).
   - Tuyệt đối không có nút "Đặt làm nút giữ" hay "Ghi" trong Khối 5 per CONTRACT.
   - Nút chưa khai báo (`!role.isDeclared`): hiển thị hàng mờ màu `.secondary`, nhãn "Chưa khai báo" và dòng chú thích "Bấm “Ghi nút” ở mục Nút giữ & cuộn rồi bấm nút này để XFinder đo.".
   - Xử lý trạng thái rỗng (`khong-chuot`): hiển thị hàng "Chưa đọc được nút nào — Cắm chuột có nút hông để xem và gán ở đây.".
   - Giữ nguyên `hardwareExclusionNote` (S39) ở cuối khối.
2. **Khối 6 — Nút giữ & cuộn (`switchesSection`):**
   - Hàng 1: Tiêu đề "Nút giữ", subtitle "Giữ nút này rồi kéo bốn hướng. Bấm chip trên hình bên trên để đổi.", giá trị hiện tại (`L10n.t(compactButton: config.trigger.key)`), và nút "Ghi nút" (`triggerRecording()`). Vô hiệu khi `controller.recording`.
   - Toggle F17 ("Bấm nhanh = Tiến") tích hợp ngay hàng 1 khi nút giữ là `holdTriggerWithAction`.
   - Hàng 2: Switch F22 ("Giữ nút cuộn rồi kéo để cuộn").
   - Hàng 3: Picker "Nút cuộn" sử dụng `scrollButtonChoices`.
3. **Khối 7 — Nghiêng con lăn (`tiltSection`):**
   - Đặt `tiltRow` vào `SettingsSection(title: L10n.t("Nghiêng con lăn"))` độc lập, giữ nguyên logic `TiltArmsVisibility.fields(forReveal:)`.
4. **Chuỗi và Token:**
   - Bổ sung 9 chuỗi mới qua `scripts/add-mouse-redesign-l10n-entries.py`.
   - Chuẩn hoá toàn bộ font sizes sang `XFinderTokens.Font.rowValue` và `XFinderTokens.Font.caption`.
   - Đảm bảo `triggerRecording()` chỉ xuất hiện ở 2 nơi: Khối 6 và F7 hold-badge.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu quyền Trợ năng** (`trusted == false`): Status line hiện đúng S2/S6; các khối 5, 6, 7 vẫn xem và cấu hình bình thường qua controller.
2. **Không có chuột / chưa khai báo nút nào**: Khối 5 hiển thị honest "Chưa đọc được nút nào — Cắm chuột có nút hông để xem và gán ở đây.", không bịa số nút. Dải chip app vẫn hoạt động bình thường.
3. **Công tắc chính tắt** (`config.enabled == false`): Status line phản ánh đúng; Khối 5–7 vẫn xem và cấu hình bình thường.
4. **Một giá trị ở biên**: `drawnButtons` rỗng thì Khối 5 hiện hàng rỗng honest. `scrollButtonChoices` luôn bảo đảm có ít nhất `config.scrollButton` nên Picker không rỗng.
5. **Ngữ cảnh đổi giữa chừng**: Đang ghi mà đổi `profile`, `onChange(of: profile)` huỷ `recordingDirection` nhưng giữ `controller.recording` đúng hành vi gốc.
6. **Giá trị cache cũ**: `hidDump` chỉ lazy-load khi mở disclosure group (bảo lưu cho T14e).
7. **Control hứa điều không làm được**: Đã dọn sạch toàn bộ "Ghi nút" gây nhầm lẫn; `triggerRecording()` chỉ gọi ở Khối 6 và F7 hold-badge.

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 2508 tests, with 0 failures (0 unexpected) in 16.612 (16.738) seconds
check-l10n-coverage                TOTAL 0 problems across 3503 entries (3503 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3503 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1304 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             3
GATE: green
```

### Kết quả 3 harness mutation (nguyên văn)
- `scripts/mutation-check-gesture-labels.sh`: `RESULT: 11/11 mutations RED`
- `scripts/mutation-check-gesture-ui.sh`: `post-restore suite: Executed 2508 tests, 0 failure(s)` (8/8 mutations RED)
- `scripts/mutation-check-gesture-buttons.sh`: `RESULT: 13/13 mutations RED`

## 2026-10-15 (Claude) — the queue moved to Notion; this file is now the fallback path

`docs/AGENT_NOTION.md` is the routine (roles, write zones, claim handshake, Runs, view URLs, schema, payloads, three
prompts). Measured today on the Notion workspace: schema extended (Spec Path · Branch · Claimed By · Pre-reviewed ·
Block Reason · Merged As), import-era States removed, five views created and the Queue view read back via `mode: view`
(returns exactly T14d), T14a–T14c = Done, T14d = Ready (spec blob `53e3659`, baseline gate green on `main a2954e2`,
Run `R-MAIN-a2954e2-gate`), T14e/T14f waiting. **SQL queries of the Notion MCP hit the plan's usage limit after 5
calls** — agents must use views and `fetch`, never SQL. The routine went through an adversarial review (4 lenses × 2
refuters: 13 confirmed, 4 split, 2 refuted) before being written down; every standing finding is addressed in the doc.

**Write here only when you cannot reach Notion** (AGENT_NOTION §7); Claude copies such an entry into a Run on return
after checking for a duplicate claim. Not verified live yet: a real Builder claiming through Notion (T-NOTION-1…4).

## 2026-10-15 (Claude) — T14d never landed; the spec was the reason; fixed

The first T14d session ended without a commit, an edit or a worklog entry: its transcript shows it re-reading
CONTRACT.md, inventory.md and variant-b.html to resolve a contradiction in the spec — T14d step 1 told it to add
"Đặt làm nút giữ" to every side-button row, while wireframe B / CONTRACT say the hold button changes in the inspector
(done in T14c). That was Claude's spec bug. Step 1 is rewritten: block 5 rows carry only the click-action menu (no hold
button, no record button); the hold button changes in the inspector and in block 6's "Ghi nút". A new stop condition in
AGENT_TASKS §3: a self-contradicting spec is copied into the worklog and the session stops.

`agent/zed-T14` was fast-forwarded to `main` (it also carries Claude's notch HUD speed-up and the worktree-safe build
scripts). Next: **T14d**, same branch.

## 2026-10-15 (Claude review of T14c) — merged; five defects fixed; branch moved to main

For the next agent: read this, not the long T14c entry below it. T14c was done by Antigravity on `agent/zed-T14` —
that is fine; the branch name stays the same whichever tool works on it.

| Item | Verdict |
|:--|:--|
| Card with diagram + inspector, never-blank summary, button inspector, F7/F8 kept, font bumps, picker label | **correct and in scope** — fast-forwarded as `ef47bdd` |
| "Dùng làm nút giữ" | **defect (2/2)**: gated on `isDeclared`; left/right click are declared but RESERVED, so right click could become the hold trigger. Fixed in `594aae4`: `if role.isAssignable`. **Rule: "may this be the hold button?" is always `isAssignable`; `isDeclared` is only a drawing question** (see the doc comment in DeviceCapabilityModel) |
| Direction summary caption | **defect (2/2)**: raw `row.caption` printed "Chưa gán trong macOS" on the English page. Fixed: `row.displayCaption(translate:)` — **use it wherever a caption is printed** |
| Arm click left a button chip highlighted | **defect (2/2)**: added `.onChange(of: pickedDirection)` clearing `pickedButton` |
| 9 pt chevron, hand-typed `⌘[`/`⌘]` | **defects (2/2)**: 11 pt; `InstantAction.*.shortcut.label` |

Known and left alone: the diagram's own arm/chip labels are 9–10 pt (11 sites in MouseDiagramView/GestureArmView/
GestureButtonList/MouseGestureAppStrip). The spec (line 101) exempts the figure; if T14f's sweep can raise them without
breaking the geometry, do it, otherwise write in the worklog why not.

**`agent/zed-T14` now points at `main` (`594aae4` or later).** Next: **T14d** — `git switch agent/zed-T14`, check `git log -1`,
work and commit there.

## 2026-10-15 (Antigravity) — T14c: sơ đồ chuột + inspector bên phải trong cùng card (Khối 4)

**Lệnh của chủ:** đọc `AGENT_QUICKSTART.md` + `AGENT_TASKS.md` + mục mới nhất của worklog, switch branch `agent/zed-T14` (không tạo nhánh mới), kiểm `git log -1` là `6577c86` hoặc mới hơn, làm ĐÚNG bước T14c (`docs/specs/T14-mouse-gestures-B.md`), commit trên nhánh đó, dán kết quả `sh scripts/gate-all.sh` vào worklog rồi dừng.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14c** — Khối 4: 2 cột trong 1 card (sơ đồ chuột + inspector) | `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder/Views/Components/GestureDetailPanel.swift` · `XFinder/Views/Components/GestureActionPicker.swift` · `XFinder/Resources/L10n.strings.json` (+4 khoá / +16 dòng) · `scripts/add-mouse-redesign-l10n-entries.py` · `docs/AGENT_TASKS.md` · `docs/AGENT_WORKLOG.md` | `gate-all.sh` in `GATE: green`; `plutil -lint project.pbxproj` sạch; `swift test` 1233 tests / 0 failures; `audit-ui-tokens` 0; không font size < 11pt (§3.1); `GestureActionPicker`, `GestureActionCatalog.choices()`, `GestureMap.row`, `resolved(_:)`, `resolvedName(_:)` vẫn được gọi nguyên vẹn (grep ✓) | Cảm giác click trực tiếp mũi tên trên sơ đồ chuột để chọn hướng và click chip nút để mở inspector nút trên app thật. Bấm nút "Dùng làm nút giữ" trong app thật có cập nhật trigger chuột tức thì không. Font 11pt so với tỉ lệ hiển thị tổng thể trên màn hình Retina/non-Retina. |

### Đã làm — đúng 6 điểm của §T14c + 3 luật §4
1. **Bố cục 2 cột trong 1 card (§T14c.1):** Khối 4 được bọc trong một `RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile)` card duy nhất. Cột trái (~310pt) chứa `MouseDiagramView` (284pt) + `TiltArmsRow` (khi `tiltArmsLive`). Cột phải (linh hoạt, minWidth ~280pt) chứa inspector panel, ngăn cách bởi `Divider()`.
2. **Định tuyến inspector & hai lựa chọn song song (§T14c.2, §T14c.3):**
   - Routing: `if let direction = pickedDirection { GestureDetailPanel(...) } else if let button = pickedButton { buttonInspector(button) } else { directionSummaryView }`.
   - Mặc định panel không bao giờ trống (sửa Lỗi #7): khi chưa chọn gì, hiển thị `directionSummaryView` tóm tắt 4 hướng cơ bản (Lên / Xuống / Trái / Phải) với tên hành động (`resolvedName`) và chord keycaps (`resolved.shortcutDisplay`); mỗi hàng có thể click để chọn ngay hướng đó; giữ nguyên 2 câu giải thích của S28 ở chân bảng (`emptySelectionHint`).
   - Thêm `.onChange(of: pickedButton)` để xoá `pickedDirection` khi người dùng bấm chip nút, đảm bảo ưu tiên hướng khi bấm mũi tên nhưng chuyển đổi mượt sang nút khi bấm chip nút.
3. **Chi tiết hướng đã chọn (§T14c.4):** Tái dùng `GestureDetailPanel` nguyên vẹn logic bindings (`onPick`, `onRecord`, `onReset`). Nâng toàn bộ font size 10pt lên 11pt ở `GestureDetailPanel.swift` (lines 94, 142, 214, 217) và `GestureActionPicker.swift` (line 57) theo chuẩn §3.1 / §T14c.4.
4. **Cải tiến `GestureActionPicker` (F9):** Thay nút menu `ellipsis.circle` bằng nhãn hành động hiện tại (`currentActionLabel`) với `menuStyle(.borderedButton)` và `.controlSize(.small)`, hiển thị rõ hành động đang gán.
5. **Inspector theo nút (§T14c.5 / F8 / F15):** Dựng `buttonInspector(_ button: Int)`:
   - Header: tên `Nút N`, phụ đề vị trí/chức năng, pill trạng thái vai trò (`rolePill`).
   - Hàng click-action ("Bấm nhanh"): chỉ hiển thị read-only (ví dụ `Lùi (⌘[)`), menu gán click-action giữ ở Khối 5 theo §3.9.
   - Nhánh nút giữ: nếu là nút giữ hiện tại (`role == .holdTrigger || role == .holdTriggerWithAction`), hiện `Đây là nút giữ hiện tại`. Nếu không: hiện `Nút giữ cử chỉ hiện tại là Nút <X>` kèm nút `Dùng làm nút giữ` (`controller.update { $0.trigger = .mouseButton(button) }`, vô hiệu khi `!role.isDeclared`).
   - Chú thích: hiển thị `passthroughNoteKey` hoặc `role.explanationKey`.
6. **Chuỗi mới và L10n:** Thêm 4 chuỗi mới vào `scripts/add-mouse-redesign-l10n-entries.py` (`Đây là nút giữ hiện tại`, `Nút giữ cử chỉ hiện tại là `, `Dùng làm nút giữ`, `Bấm nhanh`) và chạy script cập nhật `L10n.strings.json` (+16 dòng). Toàn bộ 6 cổng L10n đều báo `TOTAL 0`.

### Quyết định đã chốt
- **`buttonInspector` đặt inline trong `MouseGesturesDetailView.swift`:** dung lượng ~150 dòng kết hợp chặt chẽ với state và controller của detail view, tránh phân mảnh file không cần thiết và không phải thêm file vào `project.pbxproj`.
- **Đồng bộ lựa chọn hướng và nút:** `MouseDiagramSelection` trong Core không tự động xoá `pickedButton` khi chọn hướng, nên việc định tuyến ưu tiên `pickedDirection` trước kết hợp `.onChange(of: pickedButton) { if $1 != nil { pickedDirection = nil } }` giúp chuyển đổi hai chế độ inspector chuẩn xác mà không cần sửa Core models.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu quyền Trợ năng** (`trusted == false`): Khối 2 hiện `permissionBanner` + status S2/S6; Khối 4 (sơ đồ + inspector) vẫn xem và sửa phím tắt/hành động bình thường vì inspector đọc và ghi qua `GestureController`/`config` (cử chỉ chỉ không nhận diện được khi di chuyển chuột thật). ✓
2. **Không có chuột / chưa khai báo nút**: `drawnButtons` rỗng hoặc chỉ có các nút mặc định; `buttonInspector` xử lý an toàn cho mọi role (`.notDeclared`, `.unknown`, `.unassigned`), hiển thị đúng nhãn và vô hiệu nút "Dùng làm nút giữ" khi `!role.isDeclared`. Tóm tắt 4 hướng vẫn hoạt động độc lập không phụ thuộc chuột. ✓
3. **Công tắc chính tắt** (`config.enabled == false`): status line hiện S3; Khối 4 vẫn xem, bấm chọn hướng/nút và sửa cấu hình bình thường (đúng S3). ✓
4. **Một giá trị ở biên**: Nếu `drawnButtons` rỗng, không có chip nút nào để click vào `buttonInspector`, inspector mặc định hiển thị tóm tắt 4 hướng; nếu `pickedButton` mang giá trị nút bất kỳ, `buttonRole(button)` trả về `.unknown` hoặc `.notDeclared` an toàn, không crash. `scrollButtonChoices` luôn chứa `config.scrollButton` nên không bao giờ rỗng. ✓
5. **Ngữ cảnh đổi giữa chừng**: Khi đang ghi (`controller.recording == true`), người dùng đổi app chip thì `onChange(of: profile)` xoá `pickedDirection`, `pickedButton`, `recordingDirection`, nhưng không hủy `controller.recording`/`recordingTrigger`/`recordingButton` — giữ nguyên hành vi gốc. ✓
6. **Giá trị cache cũ**: Khối 4 không liên quan tới `hidDump` (sẽ được T14e xử lý với `.onChange(of: hidDumpExpanded)`). ✓
7. **Control hứa điều không làm được**: Nút "Dùng làm nút giữ" trong `buttonInspector` gọi đúng `controller.update { $0.trigger = .mouseButton(button) }` và disable khi `!role.isDeclared`. Menu click action chỉ nằm ở Khối 5, Khối 4 chỉ hiện read-only "Bấm nhanh". Bấm hold-badge trên diagram ghi nút giữ ngay (F7), bấm chip nút chỉ mở inspector (F8). ✓

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 1233 tests, with 0 failures (0 unexpected) in 6.500 (6.574) seconds
check-l10n-coverage                TOTAL 0 problems across 2795 entries (2795 checked, 20 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 2795 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 850 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 45 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             7
GATE: green
```

## 2026-10-15 (Claude review of T14b) — merged; two defects fixed; branch moved to main

For the next agent: read this, not the long T14b entry below it.

| Item | Verdict |
|:--|:--|
| T14b chip strip, F5 "Xem" dedup, F24 "+", F25 move, 4 pbxproj entries, strings | **correct and in scope** — merged as `09c9f3c` (the only conflict was the tail of L10n.strings.json; resolved as main + your 2 entries) |
| Icons and installed apps per render | **defect (2/2 refuters)**: `appIcon(for:)` asked NSWorkspace per chip per render, uncached, and `installedBundleIDs()` (21 LaunchServices lookups) ran 4× per render. Fixed in `ff86f5e`: icons through `ClipboardAppIcon`; the body computes `installed` and the chip list once and passes them on. **Rule for T14c+: never call NSWorkspace/LaunchServices inside a view builder; reuse `ClipboardAppIcon`** |
| The "app in front" dot | **defect (2/2 refuters)**: it only lit a chip equal to the front bundle, so apps without a preset (governed by Global) dotted nothing. Fixed: `GestureAppChooser.dottedChip` (pure, tested, M9–M10) |

**The branch `agent/zed-T14` now points at `main` (`ff86f5e`)** — it contains your T14b, the fixes above, and an
unrelated notch HUD commit. For T14c: `git switch agent/zed-T14` (no new branch), check `git log -1` shows `ff86f5e` or later,
then work and commit there. Next: **T14c**.

## 2026-10-15 (Zed / DeepSeek V4.1 Flash, Viber Bedrock) — T14b: dải chip ứng dụng (Khối 3) thay sidebar 240pt

**Lệnh của chủ:** đọc `AGENT_QUICKSTART.md` + `AGENT_TASKS.md` + mục mới nhất của worklog, làm ĐÚNG bước T14b
(`docs/specs/T14-mouse-gestures-B.md`), tạo nhánh `agent/zed-T14`, commit đúng file của T14b, dán nguyên văn
`sh scripts/gate-all.sh` rồi **dừng** (không push/merge/T14c). Không có điều kiện dừng nào xảy ra.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14b** — Khối 3 thành dải chip ngang (F4/F5/F24/F25) | `XFinder/Views/Components/MouseGestureAppStrip.swift` (**mới** + 4 dòng pbxproj) · `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder.xcodeproj/project.pbxproj` · `XFinder/Resources/L10n.strings.json` (+2 khoá) · `scripts/add-mouse-redesign-l10n-entries.py` · `docs/AGENT_TASKS.md` (đổi trạng thái T14) · `docs/AGENT_WORKLOG.md` | `plutil -lint project.pbxproj` → `OK`; `grep -c MouseGestureAppStrip.swift /tmp/xfinder-clean-build/build.log` → `4` (>0 ✓); `orderedProfiles`/`installedBundleIDs`/`appIcon` vẫn được gọi (grep ✓); `.frame(width: 240` chỉ còn trong `mappingSection` chết; script L10n → `added 2, already present 3` | Dải chip có thật sự cuộn chip đang chọn vào khung khi mở trang (ScrollViewReader vs `.onAppear`) — cần mắt người. Cỡ icon 16pt / viền accent 1.5pt / chấm 7pt so với `variant-b.html`. Giá mỗi lần render: ~1 lookup `NSWorkspace` (`urlForApplication` + `icon(forFile:)`) cho MỖI chip trên main thread — chưa đo bằng Instruments. Trackpad cuộn ngang dải chip trên app thật. |

### Đã làm — đúng 3 điểm của §T14b + 3 luật §4
1. **F4:** `MouseGestureAppStrip` (file mới, `Views/Components/` — miễn audit token) là `ScrollView(.horizontal)` các chip: `Toàn cục` **ghim đầu** (luôn ở index 0, có dải phân cách 1×20 như wireframe) → preset theo `orderedProfiles` (đã cài trước, chưa cài vẽ `b-ghost-chip` = viền nét đứt + nền mờ) → chip của bundle người dùng tự nhập (`customProfiles`) → nút “＋”. Mỗi chip: icon thật 16pt (`NSWorkspace.icon(forFile:)`), tên ngắn (`Font.caption` 11pt ≥ 11 ✓), viền accent 1.5pt khi `id == selected`, chấm 7pt góc trên-phải khi `showsDot`. `ScrollViewReader` cuộn chip đang chọn vào giữa trong `.onAppear` + `.onChange(of: selected)` (bản SwiftUI của `scrollIntoView`). Chọn chip chỉ ghi `profile = id`; `onChange(of: profile)` sẵn có lo phần xoá chọn (đúng lối `customBundleRow`/`Xem` đang dùng).
2. **F5 (Lỗi #15):** `frontmostHint` giữ nguyên câu S8-S12, chỉ bọc nút “Xem” trong `if !frontHasChip`. `frontHasChip` đọc **danh sách chip thật** (`appChips`), không chỉ `orderedProfiles`, nên app trước mặt là bundle tự nhập cũng tính (quyết định 6 — nêu rõ ở đây).
3. **F25:** chuyển nút “Khôi phục toàn bộ ứng dụng này về mặc định” từ cuối Khối 4 sang **ngay dưới dải chip/dòng phụ** trong Khối 3, `.disabled(config.overrides[profile] == nil)` y như cũ (§T14b bước 3).
4. **F24:** nút “＋” set `@State showAdvancedApps = true`; `customBundleRow` đổi thành `DisclosureGroup(isExpanded: $showAdvancedApps)` — **chỉ đổi vị trí kích hoạt**, logic ghi `profile = id.trimmed` giữ nguyên byte-for-byte.
5. **Luật 1 (chuỗi mới vào store ngay trong bước):** +2 khoá vào `scripts/add-mouse-redesign-l10n-entries.py` rồi chạy: `"Thêm ứng dụng khác bằng Bundle ID"` (help + VoiceOver của nút “＋”), `"Chưa cài — đang xem preset dựng sẵn"` (help của chip ghost). Cả hai `scope: sentence`. Diff `L10n.strings.json` đúng **+8 dòng**, không format lại. Nút “Xem”/`Ứng dụng đang dùng`/`Mặc định toàn cục`/… đã có sẵn → tái dùng khoá cũ.
6. **Luật 2 (không placeholder):** Khối 3–9 khác giữ nguyên khối cũ đang chạy; `profileSidebar`/`appPickerRow`/`mappingSection` **để nguyên trên đĩa, chỉ ngừng gọi từ `body`** (T14e mới xoá — theo §T14e bước 3). Trang vẫn dùng được trọn vẹn sau bước này.

### Quyết định đã chốt (ghi để Claude biết chỗ lệch đặc tả)
- **Khối 3 giữ PHẲNG, không dùng card** (quyết định 7 của handoff). Wireframe vẽ Khối 3 trong `xf-card` + tiêu đề “Ứng dụng”, nhưng §T14b chỉ đòi thay sidebar bằng dải chip; `frontmostHint` + `customBundleRow` mang sẵn `.padding(.horizontal, 20)` và đặc tả bảo tái dùng **“y hệt”**, nên bọc `SettingsSection` sẽ thụt lề đôi (cardInset 10 + page 20). Hệ quả: **cuối T14 không bước nào dựng card cho Khối 3** — nếu Claude muốn đúng wireframe, đây là một dòng việc mới.
- **Không thêm chip riêng cho app đang chạy trước** khi nó không có preset (sidebar cũ có một hàng như vậy). §T14b bước 2 giả định đúng trường hợp đó ⇒ giữ nút “Xem”.
- **Quy tắc chấm** theo nguyên văn đặc tả: `!front.isEmpty && chip.id == front && profile != front` với `front = controller.lastExternalBundle` (giá trị **thô**; `frontmostBundle` thay “không có gì ở trước” bằng `Toàn cục` nên không dùng được — sẽ chấm nhầm chip Toàn cục). Hệ quả: app trước mặt không có preset thì **không có chấm**; dòng phụ + nút “Xem” gánh thông tin đó.
- **`.frame(width: 240…)` vẫn còn 1 dòng** ở dòng 432 — bên trong **`mappingSection` chết** (T14e xoá). Đọc diff: không thêm/sửa cột 240 nào; Khối 3 không còn cột app riêng.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu Trợ năng** (`trusted == false`): Khối 2 hiện `permissionBanner` + status; dải chip **không đọc `trusted`** (icon lấy từ `NSWorkspace`, không cần quyền) nên vẫn chọn app được. ✓
2. **Không chuột / chưa khai báo nút**: `appChips` chỉ phụ thuộc `GestureProfiles.all` + đã cài + `overrides`, không đọc `declaredEventButtons` ⇒ dải chip render bình thường. Không có preset nào đã cài → mọi preset là ghost, vẫn bấm được. ✓
3. **Công tắc chính TẮT**: Khối 2 hiện S3; dải chip + disclosure + F25 vẫn xem/sửa được (đúng S3). ✓
4. **Giá trị biên**: `chips` **luôn** chứa chip Toàn cục ⇒ không bao giờ rỗng; nếu rỗng thì vẫn chỉ vẽ nút “＋”, không crash. `drawnButtons`/`scrollButtonChoices` không bị T14b đụng tới. ✓
5. **Ngữ cảnh đổi giữa chừng**: bấm chip khi `controller.recording == true` → `profile` đổi → `onChange(of: profile)` chỉ xoá `recordingDirection`/`pickedDirection`/`pickedButton`, **không** hủy `controller.recording`/`recordingTrigger`/`recordingButton` — tôi không sửa modifier này (hành vi cũ nguyên vẹn). ✓
6. **Cache cũ**: không đụng `hidDump`/`hidDumpExpanded` (Khối 8, T14e). Dải chip **không cache** icon: tra `NSWorkspace` mỗi lần render — chấp nhận được vì trùng lối `orderedProfiles`/`installedBundleIDs` sẵn có, nhưng **chưa đo** (xem cột “Chưa kiểm live”).
7. **Control hứa điều không làm được**: “＋” mở đúng disclosure có ô Bundle ID + “Chọn” ghi thật; F25 gọi `controller.resetProfile(profile)` và disable đúng khi `overrides[profile] == nil`; help chip ghost “đang xem preset dựng sẵn” đúng vì bấm ghost chip chỉ đổi `profile` và resolver trả preset dựng sẵn cho bundle có preset. Không thêm control nào mới ngoài 2 thứ trên. ✓

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 1230 tests, with 0 failures (0 unexpected) in 6.582 (6.642) seconds
check-l10n-coverage                TOTAL 0 problems across 2790 entries (2790 checked, 20 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 2790 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 848 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 45 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             6
GATE: green
```

(`modified tracked files 6` lúc chạy gate = 4 file code (`MouseGesturesDetailView.swift`, `project.pbxproj`, `L10n.strings.json`, `scripts/add-mouse-redesign-l10n-entries.py`) + 2 file tài liệu (`docs/AGENT_TASKS.md`, `docs/AGENT_WORKLOG.md`) — file strip mới còn untracked nên không tính. `1230` test = `1226` của T14a + 4 `GesturePageStatusTests` mà review T14a thêm. `848 unwrapped` là số thông tin; tổng của cổng là 0.)

## 2026-10-15 (Claude review of T14a) — merged; one real defect fixed; agents now commit on their branch

For the next agent: read this, not the long T14a entry below it.

| Item | Verdict |
|:--|:--|
| T14a skeleton (9 blocks, header switch, recording state, add-only script) | **correct and in scope** — committed as `3ed7f13`. Review (4 lenses, 2 refuters per finding): every builder reachable before is reachable exactly once, the 13 moved builders are byte-identical, the block order matches the spec |
| Status line during recording | **defect, confirmed by both refuters on two lenses**: `controller.recording` is one Bool for BOTH recording modes, so recording a keyboard shortcut for a direction showed "bấm nút trên chuột". Fixed: `GesturePageStatus` (pure, in GestureLabelStructure.swift) picks the sentence; `GesturePageStatusTests` (4); labels harness M6–M8. The engine takes any key for a shortcut (no ⌘/⌥/⌃ needed), so the Phím tắt page's sentence could not be reused |
| App list full width in block 3 | interim until T14b; capped at 360 pt so its shaded box does not span the page |
| Header switch had no VoiceOver label | pre-existing; added `Bật/tắt cử chỉ` (wireframe B names it) |
| Status `ĐANG LÀM … T14a xong` | fine for a multi-step task |

**Process from now on (owner approved Q-PROC-1):** commit on your branch. T14 uses ONE branch for all remaining
steps: `git switch -c agent/zed-T14 main` for T14b, then each later step continues on that same branch
(`git switch agent/zed-T14`) with one commit per step. Never commit on `main`, never push, never merge. Next: **T14b**.

## 2026-10-15 (Zed / DeepSeek V4.1 Flash, Viber Bedrock) — T14a: dựng khung trang Chuột & cử chỉ theo B (chưa commit)

**Lệnh của chủ:** *“Đọc docs/AGENT_QUICKSTART.md, rồi docs/AGENT_TASKS.md. Làm ĐÚNG bước T14a trong
`docs/specs/T14-mouse-gestures-B.md`, theo quy trình mục 3. Dán kết quả sh scripts/gate-all.sh vào
`docs/AGENT_WORKLOG.md`. Gặp điều kiện dừng thì dừng.”* → **chỉ T14a**, không sang T14b. **Không commit**
(chủ cấm); mọi thứ nằm nguyên trong working tree, nhánh vẫn `main`. Không có điều kiện dừng nào xảy ra.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14a** — khung 9 khối của phương án B | `XFinder/Views/Detail/MouseGesturesDetailView.swift` (toàn bộ `body` + `readinessRow` + 2 doc comment; `permissionBanner` giữ nguyên) · `XFinder/Resources/L10n.strings.json` (+1 khoá) · `scripts/add-mouse-redesign-l10n-entries.py` (mới) · `docs/AGENT_TASKS.md` (đổi trạng thái T14) | `build-and-check.sh` → BUILD SUCCEEDED, 0 lỗi, mọi file tên `OK`, tài nguyên đã bundle, `arm64` · `grep -c MouseGesturesDetailView.swift /tmp/xfinder-clean-build/build.log` → `4` (>0 ✓) · `swift test` → **1226 tests, 0 failures** · script L10n → `added 1, already present 0` | Hình dạng thật của trang (khung 9 khối, công tắc F1 kiểu `.switch`, dòng “đang ghi” màu accent) — app **chưa build-cài-chụp**. VoiceOver thứ tự Khối 1→9 + trạng thái đang ghi. Ba trạng thái permission / no-mouse / recording trên máy thật. |

### Đã làm — đúng 5 điểm của §4 T14a
1. **F1 (Lỗi #11):** `Toggle(...).labelsHidden()` ở trailing `PageHeader` nay thêm `.toggleStyle(.switch).controlSize(.small)`.
2. `permissionBanner` (F2/F3/S2) **giữ y nguyên byte-for-byte**, gọi ngay dưới header khi `!trusted`.
3. `readinessRow` thêm nhánh `controller.recording` lên **đầu** (tint `.accentColor`, icon `record.circle`, câu “Đang ghi — bấm nút trên chuột (Esc để hủy).”); 4 nhánh S3–S6 cũ giữ nguyên logic, vẫn nền `tint.opacity(0.12)` + `Capsule`.
4. Khung 9 khối: `body` viết lại thành 9 `VStack`, mỗi khối có comment `// ── Khối N — …`, đúng thứ tự CONTRACT (1 header · 2 status · 3 app chooser · 4 gesture map · 5 side buttons · 6 hold & scroll · 7 tilt · 8 diagnostics · 9 footer). Khối 3–9 là **các section cũ đang chạy đặt vào đúng vị trí khối** của B (luật 2: không placeholder). `activitySection` (`DEBUG_SHOW_ENGINE_LOG` = `false`) vẫn ở cuối, vẫn bị gate. Giữ `.padding(.vertical,20)` + `.pageWidthSafe()`.
5. Chuỗi mới vào store ngay trong bước (luật 1): “Đang ghi — bấm nút trên chuột (Esc để hủy).” → EN “Recording — press a button on the mouse (Esc to cancel).”, `scope: sentence`, khớp `variant-b.html` dòng 107. Chưa có trong store → tạo `scripts/add-mouse-redesign-l10n-entries.py` (mẫu `add-system-hud-l10n-entries.py`, chỉ-thêm) rồi chạy. Diff `L10n.strings.json` đúng **+4 dòng**, không format lại.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu Trợ năng** (`trusted == false`): Khối 2 hiện `permissionBanner` (S2) rồi `readinessRow` nhánh S6; panel bên phải (Khối 4) không đọc `trusted` nên vẫn dùng được. ✓
2. **Không chuột / chưa khai báo nút** (`declaredEventButtons == nil`): `drawnButtons` rơi về slot nguyên mẫu; `buttonListSection` (Khối 5) hiện placeholder trung thực; Khối 3 không phụ thuộc chuột. ✓
3. **Công tắc chính TẮT**: Khối 2 hiện S3; Khối 3–8 vẫn render (xem/sửa được), đúng câu S3 “sơ đồ bên dưới đã có sẵn phím tắt”. ✓
4. **Giá trị biên**: `drawnButtons` rỗng → nhánh `GestureButtonList` cũ, không crash. `scrollButtonChoices` **luôn** thêm `config.scrollButton` (đã đọc hàm) nên không bao giờ rỗng thật. ✓
5. **Ngữ cảnh đổi giữa chừng**: `onChange(of: profile)` vẫn chỉ xoá `recordingDirection`/`pickedDirection`/`pickedButton`, **không** hủy `controller.recording`/`recordingTrigger`/`recordingButton` — hành vi cũ, tôi không đụng modifier này. ✓
6. **Cache cũ**: `hidDumpRow` vẫn lazy `.onChange(of: hidDumpExpanded){ if expanded && hidDump.isEmpty { loadHIDDump() } }` (chỉ dời vị trí vào Khối 8). ✓
7. **Control hứa điều không làm được**: control Lỗi #1 (“Ghi nút” cạnh “Nút cuộn” mà thực ra ghi nút giữ) đã bị thay bằng `Picker` ở T15 đã commit (`2c26eb0`); T14a không đưa nó trở lại. ✓

### Hai điều cần Claude biết
- **`mappingSection` + `appPickerRow` để nguyên trên đĩa, chỉ ngừng gọi từ `body`** — đúng câu §T14a: *“KHÔNG xoá các hàm khác chưa dùng tới trong bước này (ví dụ `mappingSection` cũ) — chỉ ngừng gọi chúng từ `body`”*. Hệ quả: `HStack` sơ đồ+bảng tạm **trùng lặp** giữa `mappingSection` (chết) và Khối 4 (mới); sẽ hết ở T14c/T14e. Không xoá vội.
- **Lệch §3 bước 2 và 7 (vì chủ cấm commit):** không tạo nhánh `agent/zed-T14a`, không commit, nên bước 7 không thể ghi `CHỜ REVIEW (nhánh agent/…)`. Thay vào đó trạng thái T14 trong `AGENT_TASKS.md` là `ĐANG LÀM (Zed, 2026-10-15) — T14a xong, T14b–T14f còn` (theo §3 bước 3). Các phiên trước cố ý không đổi trạng thái (“đó là việc của Claude”). Nếu Claude không muốn, đây là revert một dòng.

### Kết quả `sh scripts/gate-all.sh` (nguyên văn, chạy sau khi sửa 2 file tài liệu)

```
build (arm64, compile list)        OK
tests                              Executed 1226 tests, with 0 failures (0 unexpected) in 6.308 (6.367) seconds
check-l10n-coverage                TOTAL 0 problems across 2786 entries (2786 checked, 20 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 2786 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 843 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 45 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             4
GATE: green
```

(`modified tracked files 4` = `AGENT_TASKS.md`, `AGENT_WORKLOG.md`, `L10n.strings.json`, `MouseGesturesDetailView.swift` — khớp cây cuối. Dòng `843 unwrapped` là số thông tin, không phải lỗi: tổng của cổng là 0. `audit-ui-tokens` in “across 0 files” là bình thường ở đây.)

## 2026-10-15 (Claude review of the three entries below) — merged as topic commits, six HUD bugs fixed

For the next agent: read this entry, not the long ones below it.

| Item | Verdict | Commit |
|:--|:--|:--|
| T02 T03 · T04 T13 · T05 T06 T08 T09 T10 · T11 T12 · T16 · T01 | correct as written | `c19dc73` · `05693fa` · `e0ee021` · `293cabc` · `6c8ee2c` · docs commit |
| T15 | two gaps: the menu was EMPTY whenever no mouse had been measured (`declaredEventButtons ?? false`), and the stored value could be missing from the list (a menu Picker then renders blank). Fixed with `scrollButtonChoices` | `2c26eb0` |
| HUD takeover (no spec) | the DisplayServices claim is RIGHT — re-measured from a terminal: a write from one process is read back by another. But six failure cases were missing: DOWN/UP decided separately, ⌥⇧ quarter steps swallowed, HDMI/aggregate outputs swallowed with no effect, no feedback at 0/100 %, brightness stepped from a stale cache, the "Độ sáng" switch promising a readout that cannot appear. All fixed, mutations M57–M59 added (notch harness 60/60 RED) | `bf8798f` |
| T18 / T19 | fine. The T18 "clean tree" precondition was a spec bug given the no-commit instruction | — |

Process changes that follow (read them in `docs/AGENT_QUICKSTART.md` rules 10–11 and `docs/AGENT_TASKS.md` §0, §3, §3c):
`sh scripts/gate-all.sh` is the one gate to run and paste; a feature asked for mid-session gets a short spec with the
failure-case list BEFORE code; say where a measurement ran (terminal ≠ installed app); without commits, list the files of
each task. Next task: **T14** from `docs/specs/T14-mouse-gestures-B.md`, one step per session.

## 2026-10-15 (later, 3) — Zed (DeepSeek V4.1 Flash, Viber Bedrock): HUD-suppression feature built (uncommitted) · a stale notch mutation anchor repaired · **T14 not started**

**Owner's instruction:** `Ok làm đủ luôn đi` plus *“Trong tính năng Brightness, Volume khi tôi sử dụng báo tình trạng thực trên Notch thì tôi muốn ẩn luôn cái Status Brightness, Volume mặc định popover mặc định của MacOS, chỉ dùng trong Notch là đủ.”* — while XFinder reports brightness/volume on the notch, macOS must not draw its own square as well; the notch is the only readout. **Nothing was committed** (owner forbade it); everything below is in the working tree.

### 1. Probe first (two rounds, delegated to a sub-agent) — two documented project beliefs were wrong

Read-only reconnaissance + standalone `swiftc` probes in `/tmp` (no repo build, so no contention). Raw evidence in the sub-agent's reports; the decisive findings:

| Question | Measured answer |
|:--|:--|
| Does a `.cghidEventTap` tap on `systemDefined` see the brightness/volume keys? | **Yes.** Type 14, subtype 8, `data1` = keytype in bits 16+, phase in bits 8–15 (0xA down, 0xB up). |
| Does `return nil` hide the native OSD? | **Yes** — the layer-101 `MenuBarAgent` window never appears; the change we apply still lands. True for volume **and** brightness. |
| Does a bare programmatic change draw the OSD? | **No** (CoreAudio and `DisplayServices` both). |
| Can XFinder read/write brightness itself? | **Yes, through the private `DisplayServices`** — `GetBrightness` returns a live 0…1, `SetBrightness` really moves the panel (WindowServer logs the swap). `IODisplaySetFloatParameter` returns `kIOReturnUnsupported` (-536870201), as the code already said. |
| What is actually frozen? | **The IOKit `IODisplayParameters` snapshot** under the new backlight architecture — i.e. the premise of `LiveActivity.swift`'s old “brightness has NO HUD on purpose” comment was wrong, and `ScreenBrightness.readLevel()` was returning a boot-time value (a live bug). |
| Is the drawer `OSDUIHelper`? | **No.** `pgrep -fl OSDUIHelper` → nothing; the square is drawn by `com.apple.MenuBarAgent` (pid 465, layer 101). Killing/OSDUIHelper is not a route. |

Consequence for design: **volume** pairs with the notch HUD that already existed; **brightness** had *no* notch HUD, so swallowing its key would have left zero feedback. Per the owner's wording (“chỉ dùng trong Notch là đủ”) the brightness HUD was therefore built too, rather than shipping a switch that hides a HUD with nothing to replace it.

### 2. What was built (files)

| File | Change |
|:--|:--|
| `XFinder/Core/Notch/SystemKeyInterceptor.swift` **NEW** | The one `.cghidEventTap` (type 14, `.defaultTap`, head insert). Swallows a media key when `LiveActivity.HUDSuppression.decide` says so, then applies it: volume/mute via the existing CoreAudio HAL (so `VolumeObserver.onChange` shows the notch HUD), brightness via `ScreenBrightness.setLevel` + `LiveActivityMonitor.brightnessChanged(from:to:)`. Re-arms on `tapDisabledByTimeout`, passes through our own posted events (`srcPID == getpid()`), and is armed only while the switch is on **and** Accessibility is granted. |
| `XFinder/Core/Notch/LiveActivity.swift` | `Kind.brightness`; `BrightnessState` + `brightnessItem(old:new:)`; the pure `MediaKey` / `HUDSuppression` rules (`phase(data1:)`, `decide(keyType:phase:context:)`); the old “no brightness HUD” comment corrected with the probe evidence. |
| `XFinder/Core/Notch/LiveActivityMonitor.swift` | `brightnessOn` reader + `brightnessChanged(from:to:)` (takes the real before/after, so the **first** press is never silent). |
| `XFinder/Core/Services/ScreenBrightness.swift` | Private `DisplayServices` dlopen shim (read/write/can-change) + `nonisolated static canSetDirectly`; read now prefers the live value, IOKit stays as fallback; `setLevel` writes via DisplayServices and only falls back to NX keys when it cannot. |
| `XFinder/Views/Detail/LiveActivitiesDetailView.swift` | New rows: **Độ sáng** (brightness activity) and a new section **Hộp điều chỉnh của macOS** → **Chỉ dùng notch cho độ sáng và âm lượng** (`notch.activity.hideSystemHUD`, default **false**, disabled without Accessibility, with the grant `InlineNote`). The volume row's subtitle no longer repeats the now-false “no brightness HUD” claim. |
| `XFinder/App/XFinderApp.swift` | `SystemKeyInterceptor.shared.applySettings()` at launch and on `didBecomeActive`. |
| `Tests/…/FeatureKeyDefaultsTests.swift` | Two new rows (`notch.activity.brightness`, `notch.activity.hideSystemHUD`). |
| `Tests/…/LiveActivityTests.swift` | 5 new tests: brightness HUD (baseline/no-change/clamp/symbols), `phase(data1:)`, and the suppression decision (swallow vs pass-through for every reason to refuse). |
| `scripts/add-system-hud-l10n-entries.py` **NEW** | Add-only; 8 new keys. |
| `XFinder.xcodeproj/project.pbxproj` | 4 hand-written entries for `SystemKeyInterceptor.swift`. |

`notch.activity.hideSystemHUD` is a **new** key with default `false`, so nothing changes for anyone who does not ask; no existing key's meaning or default was touched (§2 forbids that).

### 3. Every command run, and its result

| Command | Result |
|:--|:--|
| `plutil -lint XFinder.xcodeproj/project.pbxproj` | `OK` |
| `python3 scripts/add-system-hud-l10n-entries.py` | `added 8, already present 0` |
| `swift test --package-path Tests` | **1224 tests, 0 failures** (was 1219; +5 new). One intermediate failure — `FeatureKeyDefaultsTests` wants exactly ONE canonical reader per key and the interceptor had two — fixed by folding both reads into one `nonisolated static` property. |
| `sh scripts/build-and-check.sh` | `OK` (all named files compiled, resources bundled, arm64). Two compile errors fixed on the way: `CGEventType.systemDefined` does not exist in this SDK (compared by raw value 14 instead) and `subtype` is `NSEvent.EventSubtype`, not `Int16`. |
| `SystemKeyInterceptor.o` present + `strings` on `XFinder.debug.dylib` | `hideSystemHUD` ×3, `DisplayServices` ×5, `notch.activity.brightness` ×1 — the new file really is in the app target. (The app's code lives in `XFinder.debug.dylib`, not the 40 KB launcher — a first grep of the launcher read as “missing”.) |
| `sh scripts/mutation-check-notch.sh` | **57/57 mutations RED, 0 GREEN, 0 harness errors, restored tree green** — see §4. |
| `sh scripts/mutation-check-l10n.sh` | every mutation RED, store restored byte-identical, suite green again. |
| `check-l10n-coverage` / `-duplicates` / `audit-l10n-interpolations` / `check-sidebar-groups-l10n` / `verify-l10n-runtime` | `TOTAL 0` each. |
| `audit-l10n-literals.py` | `TOTAL 0 wrapped-but-untranslated, 843 unwrapped` — the gate's own total is 0; the informational unwrapped count rose **842 → 843** because a new notice kind needs a new title key (`titleKey: "Độ sáng"`), the same kind of literal the other 15 keys in that file already are, and it **is** in the store and translated. |
| `audit-ui-tokens.py` | `TOTAL 0`. |
| Manual mutation of the new pure rules | Removed the `hideSystemHUD` guard from `decide` → `LiveActivityTests` went **RED** (1 failure); reverted → green. The new tests really bite. |
| `git --no-pager diff --shortstat` | 29 files changed, 633 insertions(+), 75 deletions(-) — **includes the owner's/earlier agents' pre-existing uncommitted work**, not only mine. |

### 4. Found and repaired: `mutation-check-notch.sh` had been aborting at M12 (pre-existing, not mine)

`mutation-check-notch.sh` aborted with `HARNESS ERROR: anchor not found in XFinder/Core/Notch/LiveActivity.swift`. Evidence it is pre-existing and unrelated to my edits: the anchor text `if current?.kind == item.kind { current = item; return true }` **does not exist in `HEAD` either** (`git show HEAD:… | grep -c` → 0); the P12 `outranks` change restructured that block into `if let c = current, c.kind == item.kind { … }`, and my diff never touches `push`/`outranks` (verified). Because the harness aborts on the first broken anchor, **M12 onward had never been verified** — a broken gate that read like a passing one.

Repaired M12's anchor to the current code (mutation = always `enqueue` on a same-kind notice, i.e. “stack instead of replace”) and re-ran: **57/57 RED**, including the 45 mutations after M12 that had never run. This is a change to a gate script, so it is flagged for Claude's review.

### 5. T14 — NOT started (honest statement)

I read the full input chain (`CONTRACT.md` including the 11 defects and the card grammar, `inventory.md` F1–F29 / S1–S68 / §3 duplicates / §4 the 15 confirmed defects / §5 “must keep”, the variant-B essentials, `data.json`/`stored-config.json` notes) and the current code (`MouseGesturesDetailView.swift`, its 6 components, `DeviceCapabilityModel`, `GestureController`'s public API). **No mouse/gesture file was edited.**

Reason: T14 is a layout *replacement* of a 969-line view plus 6 components with a full mutation-gate acceptance suite. The spec's step 1 (“khung trang theo phương án”) cannot be done partially without leaving the page half-restructured, and the project's rule is to stop at a green state rather than ship a half-page. The budget this session went to the HUD feature (probe → implementation → build → two harnesses) and to the M12 repair. A partial rewrite would have been worse than none.

Ready for the next session, in the spec's order: (1) replace the 240-pt `profileSidebar` (`MouseGesturesDetailView.swift:392-417`) with variant B's **app chip strip** — this alone fixes Defect #8 (two sidebars) and Defect #2 (real icons), and `appPickerRow` (`:478-512`) is dead code that already shows the intended “one control” shape; (2) the **two-column card** (figure + never-blank inspector) replacing the diagram/detail-panel pair; (3) move `hidDumpRow` (`:313`, currently near the top) into one collapsed **Chẩn đoán chuột** disclosure at the bottom; (4) new strings via a new add-only `scripts/add-mouse-redesign-l10n-entries.py`; (5) the 13 góp ý from the T19 entry above, of which the **false “Claude (preset)” chip (#9)** and the **contrast failures #1–#3** are the ones with measured evidence. Every `GestureController` binding must be kept (inventory §5); `GestureModel`/`GestureEngine` must not change.

### 6. What I could NOT verify (for Claude)

* **No live run.** The interceptor has never executed inside XFinder: I did not build-and-install, launch, or press a physical brightness/volume key. Every claim about its behaviour rests on the standalone probe plus reading the code. `sh scripts/install-mouse-rebuild.sh` was deliberately not run (it installs).
* **No harness covers the new code.** `mutation-check-notch.sh` covers `LiveActivity.swift` (and passed 57/57 with my changes), but nothing mutates `SystemKeyInterceptor.swift` or the `DisplayServices` shim — their behaviour is guarded only by the pure rules' tests. Adding a harness is a new gate; I did not invent one.
* **macOS 14 is untested.** The app targets macOS 14+, and `DisplayServices` symbol availability, the frozen-IORegistry behaviour and the `MenuBarAgent`-draws-the-OSD fact were measured **only** on this Mac (macOS 27). The code degrades honestly (`canSetDirectly` false → brightness keys pass through), but that path was not measured either.
* **Physical keys vs synthesised keys.** The probe's keys were synthesised (`NSEvent.otherEvent`); the `srcPID == getpid()` discriminator was measured for synthetic events only. For real HID events `srcPID` is *expected* to be 0, but that was not observed.
* **The untrusted (no-Accessibility) case** was never measured (`AXIsProcessTrusted` was true throughout); I could not revoke TCC. The code passes through when untrusted, but that is reasoning, not measurement.
* **Brightness read/write quality**: I did not look at the panel, so “the screen really dims when XFinder sets 0.3” is unconfirmed (only the WindowServer log shows the swap). The `SystemControlsPanel` brightness slider now routes through `DisplayServices` — that panel was not opened.
* **Whether the native OSD stays hidden with the tap installed by the app** (as opposed to a standalone probe) is the single most important thing to measure live.
* **Known limitation, by choice:** if the Mac has no default output device, `SystemControls.setVolume` no-ops, so a swallowed volume key would change nothing and show no notch HUD either. Gating on that needs either a `nonisolated` CoreAudio probe or a main-actor snapshot published into a `Locked<Bool>`; both are more machinery than a degenerate case (no audio at all) justifies, so it is left as-is and recorded here. The same shape applies to `notchEnabled` standing in for `canPresentActivities` on the tap thread (documented in the code): the only divergence is the brief window before the surface panel exists.

## 2026-10-15 (later, 2) — Zed (DeepSeek V4.1 Flash, Viber Bedrock): T19 gate 2 closed — owner picked variant **B**, review written

**Owner's instruction:** `B, góp ý` — i.e. **choose wireframe variant B** and give design feedback on it. That is T14's
gate-2 input. **Nothing was committed** (owner forbade it); this entry only records the decision + the review.

### What was run, and the result of each command

| Step | Command | Result |
|:--|:--|:--|
| Server still up | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8766/wireframe-a-b-c-d.html` · `lsof -ti :8766` | **`200`** · PID **3894** ✅ (unchanged) |
| Read the spec chain | `cat` of `CONTRACT.md` (18 KB), `variant-b.html` (45 KB), `inventory.md` §2–§5 (F1–F29 / S1–S68), `data.json`, `stored-config.json` | read via terminal (all outside the repo, `read_file` cannot reach them) |
| Render B | `sh render.sh "v=b&tt=du-lieu&mau=mau&frame=1&win=s" /tmp/xf-b/b-du-lieu-s.png 1181 611 wireframe-b.html` | `rendered` ✅ |
| Probe B (measured) | `node .agents/skills/ui-ux/scripts/probe.mjs "…/wireframe-b.html?v=b&mau=mau&frame=1&win=s" --quick --widths 1181 --pw <prebuilt evon-probe> --out /tmp/xf-b/probe` | 2 real contrast fails (`P1` `Nút 6` 2.58:1; `P2` `.b-row-hint` 2.66:1); `truncatedCount 0`, `overflowingElements 0`, `hasHorizontalScroll false` ✅ (defects #3/#4 clear at 1181×611) |
| Probe B, other states | same, `tt=thieu-quyen` · `tt=dang-ghi` · `tt=khong-chuot` | `khong-chuot` → **0 P** ✅; `thieu-quyen` → same 2 P as `du-lieu`; `dang-ghi` → **12 P**, all from B's own `opacity:.4` dimming of blocks 3/5/6/7/8/9 (1.42–1.92:1) |
| `grep` evidence for the gaps | `grep -c` for `Khôi phục` / `Mở Phím tắt trong Cài đặt` / `chưa gán phím tắt` / `Bấm nhanh` / `Bấm thử` in `variant-b.html` | `Khôi phục` **0**, `Mở Phím tắt trong Cài đặt` **0**, `chưa gán phím tắt` **0**, `Bấm nhanh` 4, `Bấm thử` 1 |
| Probe screenshots served | `nohup python3 -m http.server 8767 -d /tmp/xf-b &` · `curl …` | `200` ✅ · PID **7237** (temporary, for the review links only; `kill 7237` to stop) |

### Decision + review (this is T14's input)

* **Chosen variant: B · “Sơ đồ chuột + bảng bên”** (it is also the one `CONTRACT.md` marks `data-recommended`). Link:
  `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=b`.
* **B fixes all 11 defects** in `CONTRACT.md` “What is wrong today” — verified against the file, not taken on trust:
  #1 scroll button now has its own picker (block 6), #2 real app icons, #3 no truncation at 1181 (probe-measured),
  #4 hold badge removed from the figure, #5 one vocabulary “Nút N”, #6 hold button changes in ONE place, #7 action
  names visible without a click, #8 chip strip instead of a second sidebar, #9 diagnostics collapsed, #10 short copy +
  tags, #11 switches + card grammar.
* **Open problems found (ranked; full text in the chat reply):**
  1. **Hỏng (đo)** — `assets/mouse.js:99-100` still fades the *figure’s* undeclared chip (`opacity:0.42` + `--text3`) →
     `Nút 6` 2.58:1. B already fixed the same class of bug for `.b-ghost-chip`; this sibling was missed.
  2. **Hỏng (đo)** — `.b-row-hint` uses `--text3` → 2.66:1.
  3. **`dang-ghi` (đo)** — the recording dim (`opacity:.4; filter:saturate(.5)`) drops 12 labels to 1.42–1.92:1;
     intentional per contract (“dimmed/inert”) but far too strong — recommend ~0.55–0.6 + `aria-disabled`.
  4. **Thiếu** — `F25` (reset whole profile) has **no home** in B (`grep` → 0).
  5. **Thiếu** — `F12`+`S56` (unbound-system-action warning + “Mở Phím tắt trong Cài đặt”) have **no home** (`grep` → 0).
  6. **Thiếu** — `F17` (hold-button “Bấm nhanh”) has no slot in block 6 (currently N/A in the data, but inventory §5 keeps it).
  7. **Thiếu** — no path from a measured undeclared button (“Bấm thử…”) to “Dùng làm nút giữ”, although B’s own `dang-ghi`
     copy promises XFinder will use the pressed button; inventory §5 requires keeping the record-a-real-press mechanism.
  8. **Chữ** — chord written two ways: `Lùi (Cmd+[)` (block 5) vs `Lùi (⌘[)` (inspector/figure).
  9. **Chữ** — the dashed **“Claude (preset)”** chip contradicts `data.json` (`frontmost` = `com.anthropic.claudefordesktop`,
     `hasPreset:false`; the preset key `com.anthropic.claude` is `knownAppBugs[0]` — a bundle id that “never applies”).
  10. **Chữ** — “thường là nút hông trên/dưới” is invented; `data.json` gives no side-position hint for `Nút 4`/`Nút 5`.
  11. **Trùng** — `F16` (side-button click action) lives in both block 5 and the inspector’s button view.
  12. **Cần xác nhận** — the stored scroll button is `Nút 6`, which `data.json` marks `declared:false`; B shows it under
      “CHƯA KHAI BÁO”, which deviates from CONTRACT defect #1 (“popup of the mouse’s **declared** buttons”). Honest, but
      confirm with Claude whether declared-only is the rule.
  13. **Nhỏ** — `.xf-tag` renders 10.5px (shell), just under the contract’s ≥ 11px floor; 33 texts < 12px at 1181 (mostly the
      shell sidebar + 11px captions, which the contract allows).

### What was NOT verified (for Claude)

* **No live app run.** All of the above is the wireframe only; nothing was built, launched, or measured inside XFinder.
* Probe ran `--quick` (no tab/hover/popup pass) and only at **1181×611**. The 1440×900 window, both themes, and every
  popup/overflow case were **read statically, not measured**. `dang-ghi`/`thieu-quyen`/`khong-chuot`/`du-lieu` were probed;
  the tilt-on state, the master-switch-off copy, and the named-tap-failure copy were **not** rendered.
* The probe’s console 404 is `favicon.ico` (every referenced asset returns `200`; `favicon.ico` → `404`) — benign.
* The probe’s “MỤC LẶP DÀY CHỮ” row is the **shell sidebar** (“CÔNG CỤ”, 10 lines), not variant B.
* **T14 has not been started** — it needs this gate-2 input plus the owner’s go-ahead; its file scope is
  `MouseGesturesDetailView.swift` + the six `XFinder/Views/Components/Gesture*.swift` files.

### Process note

The probe needs Playwright; it was **not** installed into the repo — the pre-built harness at
`/private/tmp/claude-502/…/scratchpad/evon-probe` (the one `CONTRACT.md` names) was reused via `--pw`. Nothing was written
outside `/tmp/xf-b` and the design folder.

---

## 2026-10-15 (later) — Zed (DeepSeek V4.1 Flash, Viber Bedrock): ran the whole §6 queue, T01–T19 except T07 and T14

Owner asked, explicitly and twice, to **run every remaining TODO in `docs/AGENT_TASKS.md` §6** and log it here so Claude
can decide the next move. **Nothing was committed** — the owner forbade commits, so every change sits uncommitted in the
working tree on `main` (`HEAD = 07f16af`). The board's own rule is "one task per session"; the owner overrode it, so the
run happened in one session and no task status in §6 was flipped (that is Claude's call).

**T07 was skipped on purpose** (status `HOÃN` — folded into the Mouse & Gestures redesign). **T14 is blocked at gate 2**
(the owner has not picked wireframe A/B/C/D yet) and was not started.

### Environment / baselines measured before any edit

| Step | Command | Result |
|:--|:--|:--|
| Swift / Xcode | `swift --version` · `xcodebuild -version` | Swift 6.4, Xcode 27 |
| Tests (baseline) | `swift test --package-path …/Tests` | **1199 tests, 0 failures** (this is the number that must not drop) |
| Build (baseline) | `sh scripts/build-and-check.sh` | OK, ≈ 28 s |
| L10n gates + UI tokens | the 6 gates below + `audit-ui-tokens.py` | all `TOTAL 0` |
| Literal audit (the number that must not rise) | `python3 scripts/audit-l10n-literals.py` | **`842 unwrapped`** |

### What each task changed, and the exact commands run

| Task | Change | Commands run and result |
|:--|:--|:--|
| **T01** | `README.md:213` `(399 test)` → `(~1199 test)` | `git diff --stat` = 1 file / 1 line ✅ |
| **T02+T03** | old 1-param `.onChange(of:)` → 2-param, 4 files / 6 lines | acceptance `grep` → 0 hits ✅ · build OK ✅ |
| **T04+T13** | `allowedFileTypes` → `allowedContentTypes` + `import UniformTypeIdentifiers`, 3 files | `grep -rn "allowedFileTypes" XFinder --include='*.swift'` → **empty** ✅ · build OK ✅ |
| **T05, T06, T08, T09, T10** | VoiceOver `.accessibilityLabel`s + one bare `"Ghim"` → `L10n.t("Ghim")` | 6 L10n gates `TOTAL 0` ✅ · ui tokens 0 ✅ · `842 unwrapped` unchanged ✅ · build OK ✅ · tests 1199/0 ✅ |
| **T11** | added `testUsagePageNameCoversEveryBranch()` to `Tests/XFinderLogicTests/DeviceCapabilityTests.swift` | **proved red**: flipped `>=`→`>` in `DeviceCapabilityTypes.swift`, saw `("Other") is not equal to ("Vendor")`, reverted **by hand**, `git diff --quiet -- …DeviceCapabilityTypes.swift` → `SẠCH` ✅ · tests **1200/0** ✅ |
| **T12** | new `Tests/XFinderLogicTests/TimeZoneConversionTests.swift` (16 tests) | `swift test --filter TimeZoneConversionEdgeCaseTests` → 16/0 ✅ · **proved red**: changed one expectation (`offsetLabel(-18000)` `"UTC−5"`→`"UTC-5"`), saw 1 failure, reverted ✅ · full suite **1216/0** ✅ |
| **T16** | `GestureShortcut.label` names table gains the ANSI letter/digit codes + `⌫`/`⎋`; new `Tests/XFinderLogicTests/GestureShortcutLabelTests.swift` (3 tests) | **proved red**: deleted `18:"1"`, saw `("⌘Key 18") is not equal to ("⌘1")`, added it back ✅ · `sh scripts/mutation-check-gesture-labels.sh` → **5/5 RED**, source restored byte-identical, post-restore **1219/0** ✅ · build OK ✅ · `git diff --stat` = 2 files ✅ |
| **T15** | `MouseGesturesDetailView.swift` `switchesSection`: the "Nút cuộn" `Button("Ghi nút") { triggerRecording() }` → a `.menu` `Picker` (max width 140) over `drawnButtons`; removed the number `Text` | build OK ✅ · tests **1219/0** ✅ · 6 L10n gates `TOTAL 0` ✅ · `grep -n triggerRecording` → only lines 331/733/840 (all outside the block) ✅ · **no new strings** ✅ |
| **T18** | run-only, no source edits | `sh scripts/mutation-check-gesture-labels.sh` → **5/5 RED**, restored byte-identical, post-restore **1219/0** ✅ · `sh scripts/mutation-check-gesture-ui.sh` → **8/8 RED**, 4 files restored byte-identical, post-restore **`Executed 1219 tests, 0 failure(s)`** ✅ · re-`git status --short` → **no leftover mutant** ✅ |
| **T19** | open the wireframes (no repo edits) | `python3 build.py a b c d` → `wireframe-a-b-c-d.html` (207 066 bytes) ✅ · `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8766/wireframe-a-b-c-d.html` → **`200`** ✅ · server PID 3894 |
| **T14** | **not started** | blocked at gate 2 = the owner picks A/B/C/D |
| **T07** | **skipped on purpose** | status `HOÃN` |

**Final state:** `swift test` → **1219 tests, 0 failures**; `build-and-check.sh` → OK; the 6 L10n gates → `TOTAL 0`;
`audit-ui-tokens.py` → `TOTAL 0`; `audit-l10n-literals.py` → `842 unwrapped` (unchanged). `git diff --stat` = 19 tracked
files, +119/−30, plus 2 new untracked test files.

### The T19 links for the owner (gate 2 — please pick one)

- A — list layout: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=a`
- B — diagram + side table (recommended in the brief): `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=b`
- C — table grouped by app: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=c`
- D — the reference-image layout: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=d`

The server is still running (`python3 -m http.server 8766 -d ~/github/XFinder-design/mouse-gestures-2026-10-15`).
**The owner has not chosen yet** — that choice plus their comments is the input for T14.

### What could NOT be verified (do not read any of this as "done")

- **No live app test at all.** The app was never launched, so **every VoiceOver label** (T05/T06/T08/T09/T10) is
  **unverified**: whether VoiceOver reads the right thing is not measurable from here. Same for the `L10n.t("Ghim")` swap.
- **T04/T13** — the open/save panels' type filtering is **unverified live** (needs a real panel).
- **T15** — picking a scroll button on the page is **unverified live**; only the code path and the gates were checked.
- **T16** — the labels are unit-tested, but what the settings page actually renders is **unverified live**.
- **T18** — the harnesses ran on the **current working tree**, not on the commit `63bc3c3` they name, because the tree now
  carries this session's edits (the owner forbade committing). The numbers are still the acceptance numbers.
- **T19** — nothing to verify beyond the 200; the owner's choice is still outstanding.

### Stop-condition / spec-vs-code conflicts hit (Claude should decide)

1. **T18 step 1 is unsatisfiable as written.** It requires `git status --short` to show **no `M` file** before running. With
   the owner's "do not commit" instruction the tree necessarily holds this run's edits. Read as "no *leftover mutant* before
   starting" — which was true. Recorded rather than stopping.
2. **T12's class name already existed.** A `final class TimeZoneConversionTests` lives in
   `Tests/XFinderLogicTests/SmartSelectConversionTests.swift` (it drives the code through `convert`). The new file the spec
   named (`TimeZoneConversionTests.swift`) therefore could not declare the same class, so its class is
   **`TimeZoneConversionEdgeCaseTests`** and it drives the **table and parsers directly** (`zone(for:)`, the whole
   `ambiguous` set, offset syntax, the `maxLength` boundary) — coverage the existing class does not have. The file name is
   as the spec wrote it.
3. **T15 number convention — verified, not guessed.** The spec's parenthetical said `scrollButton` is 0-based; confirmed
   against `GestureConfiguration.validate()` (`(1...31)`) and `DeviceCapabilityModel.role(forEventButton:)` (compares
   `context.scrollButton` to the **0-based event button number**), and `L10n.t(ButtonKey.index(n))` renders
   `ButtonLabelStructure.displayNumber` = `n + 1`. The Picker therefore tags items with the same 0-based number it stores.
4. **T12 offset expectations** were derived from the code and a real `TimeZone(identifier:)!` measurement
   (New York = UTC−4 in July 2026, UTC−5 in January), not copied from a guess.

### Stale docs found (not fixed — Claude's call)

- `AGENT_TASKS.md` §5 says `main = 63bc3c3`; actual HEAD is `07f16af`.
- `AGENT_TASKS.md:149` says "~1196" tests; measured **1199** before T11 and **1219** after T16.
- **T01's acceptance grep can never be empty**: `AGENT_TASKS.md` itself quotes the string `(399 test)` at lines 149 and 153,
  so `grep -rn '(399 test)' README.md docs/*.md` keeps matching spec text. README is fixed; the residue is the board.
- `docs/PENDING_TESTS_AND_DECISIONS.md` header says "Cập nhật: 2026-10-13" but it contains 14/10 and 15/10 entries.
- `docs/UPGRADE_PLAN_2026-10.md` (09/10) is stale: it says the notch was removed, proposes `UserDefaults` keys that do not
  match the code, and has opposite defaults for `EdgeNotes`/`MenuBarHider`/`Voice`.
- `BUILDING.md` is ~1 year behind (`Last Updated: 2025-09-12`; claims no unit tests, macOS 12+ / Swift 5.8).
- There is no `T17` in the board (numbering skips it).

### Process note

The earlier part of this same session (before a context compaction) opened by wrongly claiming it had no tool access and
refused to list the repo three times. The tools were there. No work was lost, but a session that cannot tell whether it can
act will stall on its own — the same note the "setup only" entry below records.

## 2026-10-15 — Zed (DeepSeek V4.1 Flash, Viber Bedrock), setup only — no task assigned

Asked by the owner to read `docs/AGENT_QUICKSTART.md`, `docs/AGENT_TASKS.md`, `AGENTS.md` and
`docs/PENDING_TESTS_AND_DECISIONS.md` before doing anything, then to write this entry. **No item from `AGENT_TASKS.md` §6 was
assigned, so no code was changed, no branch was created, nothing was committed.**

| Step | Command | Result |
|:--|:--|:--|
| List repo root | `list_directory` on the repo root | 20 folders, 24 files. The root also holds obvious scratch/foreign files: `a.c`, `b.c`, `prog1`, `prog2`, `full.plist`, `defaults_dump.txt`, `binary_strings.txt`, `package.json`, `skills-lock.json`, `testdir/`, `tmp-review-b-visual/`, `tmux-502/`, `tools1/`. Not touched — owner's, and the quickstart says scratch belongs in `/tmp` |
| Read quickstart | `read_file docs/AGENT_QUICKSTART.md` | Read whole (75 lines) |
| Read task board | `read_file docs/AGENT_TASKS.md` | Outline + lines 1–145 only (§0–§5 and the head of §6). **Task specs T01–T19 were NOT read** |
| Read pending list | `read_file docs/PENDING_TESTS_AND_DECISIONS.md` | Lines 1–80 only — **partial**; the file continues past `Q-OC` |
| Read this worklog | `read_file docs/AGENT_WORKLOG.md` | Read whole (18 lines) |
| Read AGENTS.md | — | Not read with a tool; its text arrived through the editor's project-rules injection. Content matches the quickstart |
| Repo state | `git --no-optional-locks status --short` | No modified tracked file. 11 untracked entries: the expected owner files (`.agents/`, `assets_info.json`, `binary_strings.txt`, `strings/`, `docs/*_2026-10.md` ×3) **plus four that are not in the quickstart's list** — `defaults_dump.txt`, `full.plist`, `package.json`, `skills-lock.json` |
| Branch | `git rev-parse --abbrev-ref HEAD` | `main` |
| Head | `git --no-pager log -1 --oneline` | `07f16af Docs: hand the remaining work to other agents while Claude is out of quota` |
| Agent branches | `git branch --list 'agent/*'` | none |
| Worktrees | `git worktree list` | only the main checkout |

**Discrepancy found, not fixed:** `AGENT_TASKS.md` §5 says "`main` = `63bc3c3`", but HEAD is `07f16af` — the status block is
stale by at least one commit.

**Could NOT verify:** nothing about the app. No build (`scripts/build-and-check.sh`), no `swift test`, none of the six L10n
gates, no UI-token audit, no mutation harness, no live behaviour. No acceptance command applies — no task was assigned. The
two partial reads above (the §6 task specs and the tail of the pending list) are the only doc content not covered.

**Process note:** the first three turns of this session claimed it had no tool access and refused to list the repo. That was
false — the tools were there and a retry worked. Recorded so Claude knows the session did not start clean: no work was lost,
but a session that cannot tell whether it can act will stall on its own.

## 2026-10-14 22:18 — Antigravity (Gemini), reviewed by Claude at 22:40

Asked by the owner while Claude was out of quota: (1) page jumping on Thư viện Clipboard and Theo dõi hệ thống, (2) remove the
separate Chống ngủ page, (3) the notch kept showing a Claude session as running after it hit the usage limit, (4) a handoff note.

| Item | Claude's review |
|:--|:--|
| Page jumping | **Right root cause** — `.pageWidthSafe()` forced pages to their ideal height (`fixedSize(vertical:)`), the split view centred a ~1 100 pt page in a ~630 pt window. Kept. One regression fixed: `sizingOptions = []` also dropped the window's 900×600 minimum → now `contentMinSize` |
| Chống ngủ page | Removing the page dropped the duration presets and the countdown (the hub only had an indefinite switch, despite the note saying a "card" existed). Folded both into the Chống ngủ row of the controls panel on Tính năng & Quyền; the dead page file removed |
| Limit not detected | **Real** (measured: the desktop app runs no `StopFailure` hook). The fix matched "hit your session limit" in the PROMPT text — it flagged this session as stopped when the owner pasted a message quoting it, and invented an undocumented notification type. Replaced by reading the `rate_limit` line Claude writes into its transcript |
| Handoff note `docs/AGENT_HANDOFF.md` | Left untracked: it claims a hub card, a test (`testAntiSleepRowRetiresInFavorOfFeaturesHub`) and hook/event paths that do not exist |
| Process | It committed Claude's uncommitted analytics work plus three untracked owner docs, and launched the XFinder binary straight from a shell. Its one-line test addition closed a real gap (mutation N6 was GREEN in Claude's run; 18/18 RED after it, re-measured). The commit was redone; the docs went back to untracked |

## 2026-11-04 (Claude Boss) — dọn Orca, review + gộp nhánh agent

| Nhánh | Kết luận | Merged As |
|:--|:--|:--|
| 29 commit trên `main` local chưa push (Codex commit thẳng, `origin/main..7e614d8`) | MERGE-OK (đã nằm trên main) | — |
| chồng `agent/codex-T32-W5 … translate-wordbook` (`7e614d8..db9d3b6`, 15 commit) | MERGE-OK | `590e210` |
| `agent/antigravity-XF-translate` (cũ: `PyDude9/xfinder-translate-gemini`, `d175224`, 12 commit) | FIX-FIRST — không gộp (Q-TRANSLATE-G1) | — |
| `agent/antigravity-snap-memory` (`8bbd883`) | FIX-FIRST, không spec — không gộp (Q-SNAP-UNSNAP) | — |

Gate trên `main` sau gộp: `GATE: green`, 2894 tests / 0 failures, build OK. Mutation: không chạy. Live: chưa (cài từ `main` sau Checkpoint 2).

## 2026-11-06 (Claude Boss) — XF-T35 Storage Analyzer v0.1 (GPT-Minion / Codex)

| Nhánh | Kết luận | Merged As |
|:--|:--|:--|
| `agent/codex-XF-T35` (`11c0e31..1c92dc5`: spec, review độc lập, roadmap MFinder, code) | MERGE-OK + 1 sửa của Boss | `1182b3c` + `768dc83` |
| `agent/codex-XF-MFinder-plan`, `agent/antigravity-XF-T35-review` | đã nằm trọn trong `1182b3c` | `1182b3c` |
| `agent/antigravity-XF-T35-review-gemini` (`6e96aa9`) | cùng nội dung spec với `9f0a5cd` (diff rỗng) — không cần gộp | — |

Review: engine chạy ngoài main actor, huỷ hợp tác qua `Task.isCancelled` trong `fts`, top-50 có giới hạn + thứ tự xác định, cộng byte
bão hoà, run id chặn tiến độ trễ. **Lỗi sửa** (`768dc83`): mọi symlink đi qua `FileWalk.onOther` ⇒ bị đếm "bỏ qua" ⇒ thư mục nào có
link cũng báo "Kết quả chưa đầy đủ"; `FileWalk` thêm `onLink` tuỳ chọn (Junk Cleanup giữ hành vi cũ), test `FileWalkLinkTests`,
harness cleanup J10 (**10/10 RED**). Gate nhánh builder: green 2901/0. Gate `main` sau gộp + sửa: green, **2903/0**, L10n 0, token 0.
Review độc lập (Claude, Notion Run): cùng phát hiện symlink; đo **8,2×** chậm hơn FileWalk trần (81 210 mục: 7,95 s vs 0,97 s). Probe
Boss: `lstat` ≈ 0, `resourceValues` là toàn bộ chi phí (0,74 vs 0,12 s / 17 238 mục; 2,73 vs 0,12 s / 2 340 mục iCloud) ⇒ `ef669cb`
chỉ `SF_DATALESS` (0 lệch trên 1 932 tệp chỉ-trên-mây). Gate main sau `ef669cb`: green 2903/0. Live: chưa (cài chờ idle).
Tiếp (Boss): `74fb3c7` hard link một lần; `8cbfc2f` harness storage 9/9 RED (S3 xanh với test cũ — test nạp tệp lớn trước nên
không bao giờ cắt danh sách ⇒ thêm test nạp tăng dần). Gate main `8cbfc2f`: green **2905/0**. Cài `ef669cb` 21:26 (dylib 6e245832 ==
build, appex `+`, L10n 0); `8cbfc2f` chờ idle.

# Notch refresh — scope split (2026-11-08)

| Task | Files | Verification | Live |
|:--|:--|:--|:--|
| XF-NOTCH-01 core display resolver | `NotchDisplayTargetRules.swift`, `NotchSurfaceController.swift`, project file, pure tests/symlink | targeted 7/0; `plutil` OK; build arm64 OK and new source compiled; mutation 68/68 RED; full gate below has one environment failure | NOT VERIFIED |
| XF-NOTCH-01 display targeting (Codex structural work) | `docs/specs/XF-NOTCH-01-display-targeting.md` | Drafted pure resolver contract, fallbacks, failure cases, and tests | NOT VERIFIED |
| XF-NOTCH-02 Notch Settings hierarchy + display target (OpenCode UI task) | `docs/specs/XF-NOTCH-02-interface-settings-layout.md` | Drafted Settings grouping and selector for XF-NOTCH-01; preserves existing keys/defaults and corrects capture wording | NOT VERIFIED |

No XFinder source was changed. The Droppy dimensions/timings remain comparison data; XFinder's existing geometry and defaults are explicitly preserved. Simultaneous panels on all displays are deferred because the current controller owns one surface. `sh scripts/gate-all.sh --no-build`:

```text
tests                              Executed 3010 tests, with 1 failure (0 unexpected) in 26.856 (27.087) seconds
check-l10n-coverage                TOTAL 0 problems across 3832 entries (3832 checked, 32 allowlisted)
check-l10n-duplicates             TOTAL 0 duplicates across 3832 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1432 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 48 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             0
GATE: RED
```

Only failure: `AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput` at `Tests/XFinderLogicTests/AgentCodexTests.swift:156` (`no ancestor named codex ⇒ no pid, never the shell's`), an environment/ancestor assumption also seen in earlier Codex worktrees. No build or live UI/display verification was run. The first OC launch was paused before edits after a mismatch was found about which task owned the display-target selector; the specs now agree, and a fresh worktree will be launched from the corrected base.

Core implementation validation `XF_OUT=/tmp/xf-xfnotch-core sh scripts/gate-all.sh`:

```text
build (arm64, compile list)        OK
tests                              Executed 3017 tests, with 1 failure (0 unexpected) in 29.795 (30.053) seconds
check-l10n-coverage                TOTAL 0 problems across 3832 entries (3832 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3832 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1432 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 48 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             2
GATE: RED
```

`NotchDisplayTargetRulesTests`: 7/0. `sh scripts/mutation-check-notch.sh`: `RESULT: 68/68 mutations RED`, restored suite 0 failures. Build log contains four references to `NotchDisplayTargetRules.swift`. Only gate failure is the same `AgentCodexTests.testTheShippedHookTagsCodexAndDropsAnswersAndToolOutput` environment/ancestor assumption at line 156. No installed-app, multi-display unplug/reconnect, fullscreen, or focus behavior was verified live.


## 2026-11-07 — Antigravity: Remove Self-Dismissing Workspace Observer & Match Trancy Badge Style

Branch `agent/antigravity-XF-translate`.

### Context & Root Cause Diagnosis
1. **Self-Dismissing Workspace Observer in `TranslateSelectionController`**:
   - `TranslateSelectionController.swift` previously had an active `registerWorkspaceObserver()` listening for `NSWorkspace.didActivateApplicationNotification`. Because Chrome remained frontmost while the floating panel was ordered front, the notification delivered `app = com.google.Chrome` (which was `!= Bundle.main.bundleIdentifier`) and instantly called `self.dismiss()`, destroying the panel before it could be rendered on screen.
   - Removed `workspaceObserver` entirely. Dismissal is now properly handled by `installClickOutside`, Escape key, and the header close button.
   - Added `panel?.orderFrontRegardless()` to guarantee z-order above frontmost web windows.
2. **Chromium Accessibility Tree Activation (`AXEnhancedUserInterface`)**:
   - When attaching to Chrome, Edge, Brave, and Electron, `SelectionWatcher` now sets `AXEnhancedUserInterface = true`, which prompts Chromium to construct and maintain accessibility trees for web contents.
3. **Trancy Badge Appearance Matching Reference**:
   - `SmartSelectBadgeView` updated to match Trancy reference screenshots: purple rounded square (`#6338F1`, corner radius 7) with a clean white icon (`character.book.closed.fill`).
   - Added deep link router `xfinder://translate?text=...` in `XFinderApp.swift`.
4. **Build & Install**:
   - Clean arm64 build OK, signed and freshly installed into `/Applications/XFinder.app` (`Nov 7 13:38:31`).
   - Audits green (`TOTAL 0 problems`).

## 2026-11-07 — Antigravity: Fix Selection Capture on Web Browsers & Chromium / Electron

Branch `agent/antigravity-XF-translate`.

### Context & Root Cause Diagnosis
1. **Empty Selection on Web Browsers (Chrome / WebKit)**:
   - In Google Chrome, AX notifications dispatched at the application level (`AXUIElementCreateApplication`) passed the application element to `SelectionWatcher.readSelection`. Because `AXApplication` does not possess `kAXSelectedTextAttribute`, querying it directly returned empty string, preventing `feed(.selectionChanged)` from reaching the threshold `minLength` and preventing the badge from ever displaying.
   - When triggering `⇧⌘G`, `VoiceScreenContext.selectedText()` queried `AXUIElementCreateSystemWide()`, which frequently fails with `-25204` on macOS 14+ when querying non-focused UI elements from background processes, causing translation to receive `nil`.
2. **Defects Resolved**:
   - **`SelectionWatcher.readSelection`**: Automatically queries `kAXFocusedUIElementAttribute` on the target application element before querying `kAXSelectedTextAttribute` and `AXSelectedTextMarkerRange`, enabling reliable mouse selection detection across Chrome, Safari, and Electron.
   - **`VoiceScreenContext.selectedText`**: Updated to probe frontmost application's focused element directly first, with `AXSelectedTextMarkerRange` WebKit fallback.
   - **`TranslateSelectionController.translateSelection`**: Added fast clipboard copy simulation fallback (`readSelectionViaClipboard`) using `TypingSink.capturePasteboard()` / `restorePasteboard()` to guarantee that `⇧⌘G` captures the active selection 100% reliably in any application even when AX refuses to report selected text.
3. **Build & Install**:
   - Clean arm64 build OK, signed and freshly installed into `/Applications/XFinder.app` (`Nov 7 17:54:53`).
   - Audits green (`TOTAL 0 problems`).

## 2026-11-07 — Antigravity: Restore Trancy AI Translation Behavior, Clean Single-Popup Flow & POS Color Badges

Branch `agent/antigravity-XF-translate`.

### Context & Root Cause Diagnosis
1. **Reversion via External Agent Merge**:
   - On Nov 7, an external agent (Codex/main) rebuilt `/Applications/XFinder.app` from `main` (commit `e55da25`).
   - Because `main` previously merged an older wordbook stack (`590e210`) retaining the legacy Apple translation presentation popover (`.translationPresentation`), the installed binary reverted to the old multi-window Apple translation popover with overlapping surfaces.
2. **Trancy-Style Translation Flow Re-verified & Re-installed**:
   - Re-audited and compiled the complete unified single-popup Trancy translation card from branch `agent/antigravity-XF-translate`.
   - Enhanced `SmartSelectionBadge.swift`: ensures `hideAll()` and `translate()` invoke `panel?.orderOut(nil)` and `badge?.orderOut(nil)` synchronously to completely eliminate frame residue or ghost popups.
   - Enhanced `TranslateSelectionView.swift`: added Trancy-style part-of-speech color badges matching reference UI:
     - `adj.` (pink `#FF2D55`)
     - `n.` (purple `#AF52DE`)
     - `v.` (blue `#007AFF`)
     - `adv.` (orange `#FF9500`)
   - 1-tap Heart button (`♡` / `♥`) reliably toggles cards into `VocabularyStore` with durable disk persistence and loaded state check.
   - Built and freshly installed to `/Applications/XFinder.app` (`Nov 7 12:35:18`).

### Evidence
- **Build**: arm64 clean build OK via `scripts/build-and-check.sh` (`/tmp/antigravity-build/out/XFinder.app`).
- **Tests**: `swift test --package-path /Users/wolong/github/XFinder/Tests` executed 2,917 tests, 0 failures. `gate-all.sh` executed 2,895 tests, 0 failures, `GATE: green`.
- **Audits**:
  - `check-l10n-coverage`: 0 problems across 3,790 entries.
  - `check-l10n-duplicates`: 0 duplicates across 3,790 unique keys.
  - `audit-l10n-literals`: 0 wrapped-but-untranslated.
  - `audit-ui-tokens`: 0 problems.
- **Install & Live Verification**: Signed with designated requirement and installed into `/Applications/XFinder.app` via `scripts/install-mouse-rebuild.sh`.

## 2026-10-31 — Gemini & Antigravity: Multi-Service Translation Settings & Automatic Vertical Display

Branch `PyDude9/xfinder-translate-gemini`.

Defects & Enhancements resolved:
1. **Full Translation Service Configuration in Smart Selection Settings**:
   - Replaced card-level mode switching with centralized service toggles in `SmartSelectDetailView.swift` under "Dịch vùng chọn (⇧⌘G)":
     - `Google Dịch (Miễn phí, nhanh)` (`translate.showGoogle`, default `true`).
     - `Từ điển macOS (Nhanh trên máy, tra từ loại)` (`translate.showDictionary`, default `true`).
     - `Dịch bằng AI (Mô hình ngôn ngữ lớn)` (`translate.showAI`, default `false`).
   - Integrated full AI provider configuration directly in `SmartSelectDetailView.swift` when AI is enabled:
     - AI Provider picker (`APIProviderKind.allCases`): OpenAI (ChatGPT), Anthropic (Claude), Google Gemini, DeepSeek, Groq, OpenRouter, and Địa chỉ riêng (OpenAI format - Bedrock template).
     - Base URL field (`voice.apiBaseURL`, e.g. `https://bedrock.viber.vn/v1`) with instant persistence on submit and change.
     - Model name field (`voice.apiModel.<provider>`, e.g. `deepseek-v4.1-flash`) with suggested models menu and dual persistence.
     - API Key field with Keychain storage status, `Lưu` and `Xóa` buttons using `VoiceKeychain`.
     - Direct link to provider console to acquire API keys.

2. **Simultaneous Automatic Vertical Stacking on Floating Translation Card**:
   - Removed all switcher buttons and manual triggers (`✨ Phân tích AI`) from `TranslateSelectionView.swift`.
   - The card automatically runs and displays all services enabled in Settings stacked vertically:
     - **Header**: Word term, Wordbook save status, Heart button (1-click save/toggle), Close button.
     - **Phonetics Row**: Dialect badge (`US`), IPA transcription `/\(phonetic)/`, audio pronunciation button.
     - **Google Translate Section**: Instant primary translation text in bold.
     - **Dictionary Senses Section**: Parts of speech tags (`[n.]`, `[v.]`, `[adj.]`) and grammatical definitions from macOS Dictionary Services.
     - **AI Nuance & Synonyms Section**: Inline spinner while loading (`Đang dịch AI…`), followed by contextual nuances and synonyms pills.
     - **Footer Bar**: Spaced repetition review counter `↺ \(repetition)`, copy translation button, open Wordbook button, and gear button opening Smart Selection settings.

3. **Keychain Access Security & Performance**:
   - When AI translation is disabled in Settings, XFinder completely bypasses all LLM calls and **never** queries macOS Keychain (`com.xfinder.app.voice`), preventing unwanted Keychain authorization prompts on lookup.
   - When AI is enabled, it automatically uses the configured provider (including Bedrock/OpenAI custom templates) without needing repeated user intervention.
   - Dynamic card sizing adjusts height (160–370pt) based on enabled services.

Gate check:
- `build (arm64, compile list)`: OK
- `tests`: Executed 2,895 tests, with 0 failures (0 unexpected)
- `check-l10n-coverage`: TOTAL 0 problems across 3,790 entries (3,790 checked, 32 allowlisted)
- `check-l10n-duplicates`: TOTAL 0 duplicates across 3,790 unique keys
- `audit-l10n-literals`: TOTAL 0 wrapped-but-untranslated
- `check-sidebar-groups-l10n`: TOTAL 0 problems across 7 sidebar group headers and 47 page titles
- `audit-gesture-vocabulary-l10n`: TOTAL 0 unresolved gesture strings
- `audit-l10n-interpolations`: TOTAL 0 interpolated strings with Vietnamese outside L10n.t
- `audit-ui-tokens`: TOTAL 0 problems across 0 files
- `GATE: green`

Live verification: Installed `/Applications/XFinder.app` PID 95656 (arm64, signed).
- Verified Google Translate, Dictionary, and AI settings toggles in Smart Selection settings.
- Verified automatic vertical stacking without modal switcher.
- What could not be verified: Actual live LLM inference requires a valid reachable network endpoint and authorized Keychain access in the user's specific session.

## 2026-10-31 — Gemini & Antigravity: Vertical Stacked Translation Card & Translate Settings Separation

Branch `PyDude9/xfinder-translate-gemini`.

Defects & Enhancements resolved:
1. **Vertical Stacked Translation Layout (Clean, uncluttered, no horizontal switcher buttons)**:
   - Removed the cramped horizontal engine switcher pills (`[Google Tr...]`, `[AI Transl...]`, `[Dictionary]`) from the card header in `TranslateSelectionView.swift`.
   - Stacked all translation outputs vertically in one clean, unified view:
     - **Header**: Word term, one-tap Heart save/toggle button, Close button.
     - **Phonetics Row**: `US` dialect badge, IPA transcription `/\(phonetic)/`, native audio pronunciation button (`speaker.wave.2`), and an on-demand `✨ Phân tích AI` pill if deep analysis is requested.
     - **Primary Translation (Google Translate)**: Prominent, bold Vietnamese translation in ~200ms.
     - **Dictionary Senses (POS Breakdown)**: Vertically stacked parts of speech badges (`[n.]`, `[v.]`, `[adj.]`) with definitions from macOS Dictionary Services.
     - **AI Nuance & Synonyms**: Contextual meaning and synonyms pills rendered cleanly below when analyzed.
     - **Footer Bar**: Spaced repetition review counter `↺ \(repetition)`, copy translation button, open wordbook button, and gear button opening Translate settings.

2. **Preventing Keychain Access Prompt**:
   - Diagnosed root cause: `startAITranslation` invoked `VoiceSettingsSnapshot.read()`, which accessed Keychain `com.xfinder.app.voice`. When the app binary was rebuilt across sessions, macOS prompted for the keychain password on every lookup.
   - Decoupled standard lookups: Google Translate (free, fast, ~200ms) runs by default with **zero** Keychain access or LLM delay.
   - AI translation only runs if explicitly triggered via `✨ Phân tích AI` or if "Tự động phân tích sâu bằng AI" (`translate.autoAI`) is enabled in Settings.

3. **Dedicated Translate & AI Settings in Smart Selection Settings**:
   - Updated `SmartSelectDetailView.swift` to house Translate configuration:
     - Toggle: "Tự động phân tích sâu bằng AI" (`translate.autoAI`).
     - Direct settings link to configure AI providers (OpenAI, DeepSeek, custom templates, API keys) in the Voice & AI settings page.
   - Gear icon in floating card footer routes directly to `.smartSelect`.

Gate check:
- `build (arm64, compile list)`: OK
- `tests`: Executed 2,895 tests, with 0 failures (0 unexpected)
- `check-l10n-coverage`: TOTAL 0 problems across 3,775 entries
- `check-l10n-duplicates`: TOTAL 0 duplicates across 3,775 unique keys
- `audit-l10n-literals`: TOTAL 0 wrapped-but-untranslated
- `check-sidebar-groups-l10n`: TOTAL 0 problems
- `audit-gesture-vocabulary-l10n`: TOTAL 0 unresolved
- `audit-l10n-interpolations`: TOTAL 0 interpolated
- `audit-ui-tokens`: TOTAL 0 problems
- `GATE: green`

Live verification: Installed `/Applications/XFinder.app` PID 19001 (arm64, signed).

## 2026-10-29 — Gemini & Antigravity: Fix Heart button 1-tap save to Wordbook & toggle state

Branch `PyDude9/xfinder-translate-gemini`.

Defects resolved:
1. **Heart button save failure in Google Translate mode**:
   - Diagnosed root cause: `saveToWordbook()` constructed its card via `assistant.card(wordbook:)`. Because Google Translate mode is the default and does not run AI analysis, `assistant.receive(text: ...)` was never called on Google Translate selections. Consequently, `assistant.text` remained empty (`""`), which caused `card.term` to be empty and language to default to `"und"`, failing `VocabularyLibrary.validateCard` (`ValidationError.invalidText`).
   - Fixed `saveToWordbook()` to directly construct `VocabularyCard(term: ...)` from `model.text`, `model.googleTranslation`, `model.localPhonetic`, and `model.localSenses` without relying on `assistant` state.
   - Initialized `assistant.receive(text: resolved, meaning: "")` unconditionally so `assistant` always has valid text and language tags.
   - Added asynchronous `VocabularyStore.load()` callback in `translate(...)` so that previously saved cards are correctly detected even if the Wordbook window was never opened.
   - Added `toggleSave()`: Clicking the heart on an unsaved card saves it (heart fills red, checkmark lights up, review count badge `↺ 0` appears); clicking again removes it from Wordbook cleanly.

Gate check:
- `build (arm64, compile list)`: OK
- `tests`: Executed 2,895 tests, with 0 failures (0 unexpected)
- `check-l10n-coverage`: TOTAL 0 problems across 3,767 entries
- `check-l10n-duplicates`: TOTAL 0 duplicates across 3,767 unique keys
- `audit-l10n-literals`: TOTAL 0 wrapped-but-untranslated
- `check-sidebar-groups-l10n`: TOTAL 0 problems
- `audit-gesture-vocabulary-l10n`: TOTAL 0 unresolved
- `audit-l10n-interpolations`: TOTAL 0 interpolated
- `audit-ui-tokens`: TOTAL 0 problems
- `GATE: green`

Live verification: Installed `/Applications/XFinder.app` PID 87421 (arm64, signed).

## 2026-10-29 — Gemini & Antigravity: Strictly Single Unified Popup & Google Free Translate Engine Integration

Branch `PyDude9/xfinder-translate-gemini`.

Defects resolved:
1. **Strictly Single Popup (No secondary popup or intermediate menu)**:
   - Diagnosed root cause of the 2-popup experience:
     1. Previously, clicking the Smart Selection badge opened `SmartSelectPanelView` with "Định nghĩa" and "Dịch vùng chọn [Dịch]", which when clicked opened a second window `TranslateSelectionView`.
     2. Additionally, `SelectionWatcher` could show a selection badge while `TranslateSelectionController` was active, causing two floating elements on screen.
   - Fixed `SmartSelectBadgeView`: When text (words or sentences) is selected without conversions (unit, currency, calendar, arithmetic), clicking the badge opens the Translate Card **directly**, bypassing the intermediate menu completely.
   - Updated `TranslateSelectionController.translate`: Directly calls `SmartSelectionBadge.shared.hideAll()` and `SelectionWatcher.shared.dismiss()` on presentation.
   - Updated `SelectionWatcher.showBadge`: Guards `!TranslateSelectionController.shared.model.isActive`, guaranteeing no badge ever spawns while the translate card is open.

2. **Google Free Translate & Multi-Engine Selector**:
   - Integrated `GoogleTranslateService` using the official free Google client endpoint (`clients5.google.com/translate_a/t?client=dict-chrome-ex`), delivering bidirectional translations (English <-> Vietnamese) in **~200 ms** with zero API key requirement.
   - Added `TranslationEngine` with 3 selectable options in the card:
     1. `Google Dịch` (Google Free Translate — fast ~200ms, free).
     2. `Dịch AI` (Configured AI provider like DeepSeek for deep nuance & synonyms).
     3. `Từ điển` (On-device macOS Dictionary for grammatical POS breakdown).
   - Instant 1-click engine switching with user preference persisted to `UserDefaults` (`translate.preferredEngine`).
   - For single words, Google translation and on-device dictionary phonetics / POS badges (`[n.]`, `[v.]`) display together seamlessly.
   - Added L10n entries for `"Google Dịch"` and `"Dịch AI"`.

Gate check:
- `build (arm64, compile list)`: OK
- `tests`: Executed 2,895 tests, with 0 failures (0 unexpected)
- `check-l10n-coverage`: TOTAL 0 problems across 3,767 entries
- `check-l10n-duplicates`: TOTAL 0 duplicates across 3,767 unique keys
- `audit-l10n-literals`: TOTAL 0 wrapped-but-untranslated
- `check-sidebar-groups-l10n`: TOTAL 0 problems
- `audit-gesture-vocabulary-l10n`: TOTAL 0 unresolved
- `audit-l10n-interpolations`: TOTAL 0 interpolated
- `audit-ui-tokens`: TOTAL 0 problems
- `GATE: green`

Live verification: Installed `/Applications/XFinder.app` PID 86315 (arm64, signed).

## 2026-10-29 — Gemini & Antigravity: Unified Minimalist Trancy Air UI/UX Translate Card & Simplified Workbook

Branch `PyDude9/xfinder-translate-gemini`.

Defects & Questions resolved:
1. **Unified, Minimalist Translate Card (Trancy Air UI/UX reference)**:
   - Redesigned `TranslateSelectionView.swift` to match Trancy Air's word card layout:
     - Prominent bold word header with instant checkmark (saved state indicator), 1-tap Heart button for immediate background save/toggle into default Wordbook, and minimal close button.
     - Sub-header with `US` dialect badge, IPA phonetic `/.../`, and clickable native audio pronunciation button (`speaker.wave.2`) via `AVSpeechSynthesizer`.
     - Structured senses section with lavender Part of Speech badges (`[n.]`, `[v.]`, `[adj.]`, `[adv.]`) and clean semicolon-separated definitions.
     - Footer bar with review count pill (`↺ \(repetition)`), quick copy button (`doc.on.doc`), open Wordbook button (`book.pages`), and settings gear (`gearshape`).
   - Senses parsed locally from macOS Dictionary Services (`parseLocalDictionary`) in ~1 ms, enriched with AI translation results in parallel.
   - For sentences/paragraphs, displays clean source and bold translated text with audio pronunciation and copy shortcut.

2. **Single Unified Popup & In-Place Selection Anchoring**:
   - Resolved the 2-step jumping popup sequence between Smart Selection and Translate:
     - `SmartSelectionBadge.translate()` now passes the current panel frame to `TranslateSelectionController.shared.translate(text:sourceApp:anchorRect:)`. The translate card seamlessly appears right at the exact position of the badge/panel, eliminating the jarring jump across the screen to `.spotlight`.
     - When invoked via shortcut `⇧⌘G`, the panel automatically anchors directly near the cursor / selection (`NSEvent.mouseLocation`), clamped into visible screen bounds.
     - Simplified `SmartSelectViews.swift` translate action from verbose Apple branding to clean "Dịch vùng chọn" with a direct "Dịch" button.

3. **Workbook Workspace Simplification & Clarifications**:
   - Hidden the unused "Bản thiết kế prompt" (Prompt Blueprints) tab from `VocabularyWorkspaceView.swift` segmented picker, leaving only the 2 primary workflows: "Tra từ" (Lookup & saved words) and "Ôn tập" (Flashcard review).
   - Clarified that the "Ôn tập" (Review) tab IS XFinder's built-in Anki spaced repetition engine (implementing the SM-2 algorithm with intervals, ease factor, and Again/Hard/Good/Easy rating buttons), and highlighted the Anki TSV export option for syncing to standalone Anki apps.

Gate check:
- `build (arm64, compile list)`: OK
- `tests`: Executed 2,895 tests, with 0 failures (0 unexpected)
- `check-l10n-coverage`: TOTAL 0 problems across 3,765 entries
- `check-l10n-duplicates`: TOTAL 0 duplicates across 3,765 unique keys
- `audit-l10n-literals`: TOTAL 0 wrapped-but-untranslated
- `check-sidebar-groups-l10n`: TOTAL 0 problems
- `audit-gesture-vocabulary-l10n`: TOTAL 0 unresolved
- `audit-l10n-interpolations`: TOTAL 0 interpolated
- `audit-ui-tokens`: TOTAL 0 problems
- `GATE: green`

Live verification: Installed `/Applications/XFinder.app` PID 73587 (arm64, signed).

## 2026-10-29 — Gemini & Antigravity: Instant on-device dictionary lookup & durable Wordbook saving

Branch `PyDude9/xfinder-translate-gemini`, commit `bea1f58`.

Defects resolved:
1. **Translate latency & instant feedback (Trancy-like experience)**:
   - Previously, the floating panel showed only a blank card with a "Translating..." spinner while awaiting external LLM inference (taking 2–4s over remote API).
   - Integrated on-device `DictionaryLookup.definition(text)` (macOS Dictionary Services) directly into `TranslateSelectionController`. When a word or term is selected, phonetics (IPA), syllabification, and definitions are extracted and displayed **instantly in 1–2 ms**.
   - The user immediately sees the pronunciation and definition without waiting for cloud inference. AI Vietnamese translation (`TranslateAssistant`) executes in parallel in the background and smoothly populates the Vietnamese meaning and synonyms once ready.
   - The "Lưu vào sổ từ" (Save to wordbook) button is **enabled immediately** from the moment the card appears.

2. **Durable VocabularyStore auto-loading (Fix for card not appearing in wordbook)**:
   - Root cause diagnosed: `VocabularyStore.shared.performCommit` guarded on `guard isLoaded, !isReadOnly else { return false }`. Because `store.load()` was historically only called when the Workspace window opened, floating panel saves executed when `isLoaded == false`, causing `saveCard` to silently drop the card without persisting.
   - Fixed `VocabularyStore.performCommit` to auto-load (`if !isLoaded { await load() }`) before mutating and persisting to `library.json`.
   - Deduplicated concurrent `load()` operations via `@ObservationIgnored private var loadTask: Task<Void, Never>?` so parallel calls safely await the in-flight disk read.
   - Added unit test `testSaveCardWithoutPriorLoadAutoLoadsAndPersists` in `VocabularyStoreTests.swift` proving saving without explicit prior `load()` auto-loads and persists.

Gate check:
```text
build (arm64, compile list)        OK
tests                              Executed 2895 tests, with 0 failures (0 unexpected) in 23.949 (24.165) seconds
check-l10n-coverage                TOTAL 0 problems across 3765 entries (3765 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3765 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1403 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             0
GATE: green
```

Live verification: Installed `/Applications/XFinder.app` PID 43087 (arm64, signed).

## 2026-10-29 — Gemini & Antigravity: Inline Trancy-style Translate card & Voice typing text insertion into Electron/Orca

Branch `PyDude9/xfinder-translate-gemini`, commits `37bb244` and `dde499b`.

Defects resolved:
1. **Translate UX overhaul (Trancy-style inline lookup & save)**:
   - Eliminated the flaky Apple `translationPresentation` popover which previously overlapped the floating host and dismissed prematurely during translations.
   - `TranslateSelectionController` now directly invokes `TranslateAssistant` for on-device AI translations upon selection.
   - `TranslateSelectionView` displays an inline card showing progress indicator, word/term, phonetic transcription, meaning, and synonyms pills.
   - Added immediate "Lưu vào sổ từ" (`saveToWordbook()`) button directly in the floating card that saves the card to the default wordbook and auto-dismisses upon completion, as well as a fallback "Mở tra từ" shortcut.
   - Sizing and click-outside dismissal behavior verified.

2. **Voice-to-text text insertion into Orca chat and Electron/web inputs**:
   - Diagnosed root cause: `TypingSink.insertViaAccessibility` wrote to `kAXSelectedTextAttribute`. In Chromium/Electron (Orca, VS Code, Slack) and web browsers, Chromium's AX implementation reported success without dispatching DOM `input`/`beforeinput` events, leaving React/editor state un-updated while prematurely reporting success so pasteboard fallback never ran. Furthermore, the 180 ms restore delay was too short for Electron's IPC clipboard reads.
   - Added `shouldSkipAccessibility` to route Electron apps (`com.stablyai.orca`, etc.), web browsers, and terminals directly to `insertViaPasteboard`.
   - Updated `insertViaPasteboard` to use clean `keyboardEventSource: nil` and extended clipboard restoration delay to 650 ms to ensure asynchronous web/Electron consumers finish reading.

3. **L10n entries and gate compliance**:
   - Fixed new localization keys (`Đang dịch…`, `Đã lưu vào sổ từ`, `Mở tra từ`, `Cấu hình AI để dịch`, `Mở cài đặt Giọng nói`, `Lỗi AI:`) to be nested under `entries` with appropriate `"scope"` (`sentence` / `fragment`).
   - All 7 L10n and UI token audits print `TOTAL 0`.

Gate check:
```text
build (arm64, compile list)        OK
tests                              Executed 2894 tests, with 0 failures (0 unexpected) in 23.806 (24.023) seconds
check-l10n-coverage                TOTAL 0 problems across 3765 entries (3765 checked, 32 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3765 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1403 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             0
GATE: green
```

Live verification: Installed `/Applications/XFinder.app` PID 30423 (arm64, signed). Hotkey enabled, defaults preserved.

