# Handoff to Boss — XF-MFGAP-03 stage 03C (OpenCode)

Date: 2026-11-08 (Asia/Ho_Chi_Minh)
From: OpenCode (Builder) — this session
To: Boss (Claude, `/Users/wolong/github/XFinder`)
Branch: `agent/codex-XF-SETTINGS`, base `fc9e2dd` (= `main` at hand-off time of the branch)
Commits: `eb1c2e6` (code + tests + gates), `ab1c185` (worklog + dead-code removal), plus this file
Pushed: **no** (Builder never pushes). Boss's checkout shares the same object database, so the commits are
already fetchable there — `git log --oneline --all --grep=03C` in `/Users/wolong/github/XFinder` lists them.
Installed: nothing. Launched: nothing.

## 1. What is finished and verified

| Check | Result |
|:--|:--|
| Build (arm64, compile list) | OK |
| Full test suite | **3073 tests / 0 failures** |
| `ArchivePlacementTests` (new file) | **27 / 0** |
| All 7 string/UI gates | TOTAL 0 across **3934** entries (32 allowlisted) |
| Mutation harness (archive) | **40/41 RED**, 1 survivor `C8` = declared equivalent; sources restored byte-identical; suite green after restore |
| Live / GUI | **NOT VERIFIED** — Builder does not install or launch |

The stage implements Boss approval points 1/5/6/7 and spec §4.2/§4.4/§4.5/§5/§7. The worklog entry at the top of
`docs/AGENT_WORKLOG.md` is the detailed record, including four mutation survivors I had to close and two
process mistakes I made (editing sources while the harness ran; running `swift test` concurrently with it).

## 2. What Boss has to do — in order

1. **Review the diff**: `git diff fc9e2dd...agent/codex-XF-SETTINGS -- XFinder/`.
   Highest-risk files, in order: `CompressDetailView.swift` (494 lines changed, UI logic that no test can see),
   `ArchiveRunner.swift` (place / publishExclusively / replace), `ArchiveEngine.swift` (mergePlan).
2. **Read the 33 new Vietnamese sentences** (`git diff fc9e2dd...agent/codex-XF-SETTINGS -- XFinder/Resources/L10n.strings.json`).
   They are my wording, not copy. Priority: the merge label, the capacity line, the partial-placement and
   recovery-folder sentences. `Q-2` in the worklog is about this.
3. **Hand test** (needs an installed build — Boss only):
   - Merge with a real collision: extract an archive holding `Report.pdf` into a folder that already has
     `Report.pdf` ⇒ the user's file is **unchanged**, the archive's copy appears as `Report 2.pdf`, and the
     result line names `Report 2.pdf`.
   - Merge with a folder collision: `Photos` on both sides ⇒ folders combine, only duplicates are numbered.
   - "Kiểm tra" on an unsafe archive ⇒ red refusal sentence, Giải nén stays disabled, no bypass.
   - "Kiểm tra", then change the destination ⇒ the review is labelled stale and Giải nén is disabled again.
   - Extract into a folder where a subfolder is a **symlink** ⇒ nothing is written through the link; the
     incoming folder lands as `folder 2`.
   - Compress onto an existing archive, choose "Thay thế" ⇒ old archive in the Trash, new one in place; then
     repeat with the new archive forced to fail ⇒ the old one must still be there.
   - "Xóa file nén gốc" ⇒ the confirm sheet lists names, **Cancel is the default** (Return cancels), and a file
     that failed to extract is not offered.
   - Alert button order as drawn by AppKit (Key Both / Merge / Cancel with Cancel first) — I could not see this.
4. **Changelog row** in `docs/MFINDER_CHANGELOG.md` — deliberately not written by me: the table's `Status`
   column means "merged", and this is not merged. The 03B row's "Next 03C: …" sentence is now the thing to
   replace.
5. **Notion Run** — not written. This session could not reach Notion; the worklog is the record.
6. **Merge decision** is Boss's. Nothing was pushed, installed, or run.

## 3. A defect I measured while checking my own worklog claim — NOT fixed, needs your call

My worklog said a certain single-source compression bug is "pre-existing and out of 03C scope". I refused to
hand that over as an unverified sentence, so I measured it. **It is real, it is on `main`, and every user hits
it on the most obvious path.**

Introduced by `0a184ba` ("B2a: one archive engine — zipping two or more items never worked before"), which **is
an ancestor of `main`** (`be2801f` in my checkout).

Shape: **exactly one source that is a FILE, format ZIP, default level, no password.**

- `ArchiveEngine.needsStaging` returns `false` for that shape, so `compress` uses
  `ditto -c -k --sequesterRsrc --keepParent <file> <out.zip>`.
- `--keepParent` on a single **file** makes the file's **parent directory name** the top-level entry, not the
  file name.
- The read-back then looks for `one.txt` and finds `<tempdir-name>/one.txt`, so
  `missingTopLevelEntries` reports `one.txt` as lost and `compress` returns `.missingData`.
- The user sees "Thất bại khi nén …" for a perfectly ordinary ZIP that was in fact written correctly.

Measured, not inferred (`/tmp/xf-gpt-minion/single/rep`, linked against the shipped `ArchiveEngine.swift`):

```
needsStaging for one file, default zip: false
command: /usr/bin/ditto ["-c","-k","--sequesterRsrc","--keepParent","…/one.txt","…/out.zip"]
status 0
listing:
xf-rep-FB8EDC72-…/one.txt
__MACOSX/
__MACOSX/xf-rep-FB8EDC72-…/
expected: ["one.txt"]
missingTopLevelEntries -> ["one.txt"]
RESULT: compress() returns .missingData -> the user sees a failure
```

Not affected: a single **folder** (`dir/` is a real top-level entry — verified), two or more sources, a
non-default level, or a password (all three force staging). That is why the test suite never caught it: every
`compress` fixture in `ArchiveRunnerTests` uses two sources to avoid this exact shape.

Why I did not fix it: `ArchiveRunner`/`ArchiveEngine` are on the Builder forbidden list (`docs/AGENT_TASKS.md` §2,
"thứ di chuyển hay xoá tệp của người dùng"), and this is outside stage 03C's spec scope. Two candidate fixes,
for your decision:
- always stage a single source (smallest change, loses `ditto`'s macOS metadata path that the `needsStaging`
  comment exists to protect), or
- make the read-back expectation follow what `--keepParent` actually produces for a single file (keeps `ditto`,
  but the expectation must then be computed from the source's parent, which is subtle).

Neither is mine to choose. Suggest it becomes its own task with a fixture that uses **one file**, so the
harness cannot regress.

## 4. Open questions

- **Q-2** (worklog): the 33 added sentences need a native read-through.
- **Q-4** (new, this file): the single-source file defect above — assign it, or reject my reading.
