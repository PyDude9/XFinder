# XF-MFGAP-03 archive safety spec — gap review before Boss approval

Date: 2026-11-07 (Asia/Ho_Chi_Minh). Reviewer: OpenCode **on a different model** from the Codex session that wrote the
spec, so this is a cross-tool read per `AGENT_TASKS.md` §3c step 2, not the author reviewing itself.

Reviewed target: `docs/specs/XF-MFGAP-03-archive-safety.md` at blob `bb0e613` (branch `agent/codex-XF-SETTINGS`,
base `main 1143525`). **The spec file was not edited** — it is the artifact Boss approves, and a Builder may not rewrite
an approval artifact. All findings are recorded here instead.

No application source was changed. Nothing was installed, launched, pushed or merged. Every measurement below is a
**compile-and-run probe in a terminal** against the *unchanged* `ArchiveEngine.swift` / `ArchiveRunner.swift`, or a
read of the source. Scratch area: `/tmp/xf-mfgap03-review/` (synthetic data only, no user files).

Environment: macOS 27.2 / 26B123, arm64, same as the spec's measurements, so numbers are comparable.

## Verdict

The spec's direction is sound and its measured findings reproduce in the sources. It is **not yet ready for closure**
because four things it asserts are either unmeasured, unnamed, or contradicted by the code it will modify. Three of
them change code the spec already assigns to a stage, so they should be resolved in the text before implementation
rather than discovered mid-stage.

Re-verified as accurate (no action needed): the two archive suites are 18 + 15 = **33 test functions**, all green
(`Executed 35 tests, 0 failures` under `--filter Archive`, where the filter also picks up two unrelated archive-named
tests). The destination-symlink, self-source-overwrite, duplicate-entry, partial-placement and foreign-output-cleanup
findings all match the code paths the spec cites. Staging permissions are **0o700** (`448` decimal) under
`/var/folders/…/T/TemporaryItems/NSIRD_*`, so the spec's "private 0700 staging root" requirement is already met by
`.itemReplacementDirectory` — worth stating so a stage-03B implementer does not "harden" what is already correct.

## Findings

### 1. High — the spec's no-replace commit primitive does not exist as named, and the obvious substitute is a trap

§7 says "exclusive no-replace publication" and "via the platform's verified replace/exchange primitive", and §9 warns
"if a reliable primitive/identity guard is unavailable, offer a numbered copy or stop". The spec never names the
primitive. Measured on this volume:

| Probe | Result |
|---|---|
| `renamex_np(src, dst, RENAME_EXCL)` onto a **free** path | `ret=0`, file appears |
| `renamex_np(src, dst, RENAME_EXCL)` onto an **existing** path | `ret=-1`, `errno=17 (EEXIST)`, source still present, destination bytes untouched |
| `renamex_np(src, dst, RENAME_SWAP)` | `ret=0`, contents exchanged |
| `FileManager.replaceItemAt(_:withItemAt:backupItemName:"keepme",options:[])` | returns the target path, old bytes gone, **no backup file created** |
| same call with `backupItemName:` and `.usingNewMetadataOnly` | identical: no backup, old bytes gone |

So `RENAME_EXCL` is the real no-replace commit and `RENAME_SWAP` is the real exchange; both are reachable from Swift
with **no hand-written declaration** (`Darwin` exposes `renamex_np`, `RENAME_SWAP = 2`, `RENAME_EXCL = 4` — a probe
compiled against the SDK and ran). But `FileManager.replaceItemAt(backupItemName:)` — which §7's "retain a recoverable
old version" sentence invites an implementer to use — **silently does not keep the old version** in this measurement.
That is exactly the class of false promise the quickstart's rule 1 forbids, and it is the current creation-Replace path
(`CompressDetailView.swift:404–410`, old archive trashed first, then rebuilt).

**Ask of Boss:** the spec should name `renamex_np` + `RENAME_EXCL` (publish) and `RENAME_SWAP` (exchange-then-trash) as
the primitives, and explicitly forbid relying on `replaceItemAt(backupItemName:)` for recoverability. If Boss prefers
not to take a Darwin dependency in `ArchiveEngine`, the honest fallback is the spec's own "numbered copy" branch —
but then the create-Replace flow must stop advertising recovery it does not have.

### 2. High — `numbered()` mangles directory names, and the spec's recursive-Merge numbering inherits it

§4.3 and §7 require Finder-style numbering for "colliding leaf files" and "compound extensions preserved". The existing
helper (`ArchiveEngine.swift:47–55`) is file-oriented: it always splits at the **last** dot. Measured with the shipped
code:

| Incoming name | `numbered(name, 2)` today |
|---|---|
| `Photos.2024` | `Photos 2.2024` |
| `v1.2.3` | `v1.2 2.3` |
| `Hồ sơ.2025` | `Hồ sơ 2.2025` |
| `2024.11 Backup` | `2024.11 Backup 2` (accidentally correct) |
| `Folder` | `Folder 2` (correct) |

For a **file** `v1.2.3` → `v1.2 2.3` is defensible (keeps `.3`). For a **folder** every dotted name is wrong: Finder
appends ` 2` to the whole name, it never treats a dotted folder as `name.ext`. The spec proposes recursive Merge that
numbers colliding *directories* as well ("File/directory type collisions keep the incoming item under a numbered
name"), so it will reuse this helper and produce folders like `Photos 2.2024` next to `Photos.2024`.

**Ask of Boss:** the spec needs one explicit sentence that directory numbering never splits an extension, plus a named
pure-test row. This is cheap now and a user-visible naming bug later.

### 3. High — the `Xóa file nén gốc` hazard is real, reachable, and currently unconfirmed

§3 item 3 says this action "must not run over failed/unprocessed inputs: require explicit confirmation and restrict it
to the successfully handled input identities, or defer that action until separately reviewed." Reading the shipped code
(`CompressDetailView.swift:263–273`), the current behavior is worse than the spec implies and it is a single-click path:

- the button trashes **every** entry in `sources`, not the handled ones;
- there is **no confirmation dialog** — `role: .destructive` only tints the row;
- it appears whenever `resultURL != nil`, which `extract()` sets from *any* successful archive
  (`CompressDetailView.swift:472`), while the batch may have failed on another archive;
- it then clears `sources = []`, so the user cannot even see which inputs were destroyed.

Concrete reachable sequence: select two archives, one valid and one corrupt, destination "Thư mục mới cạnh file nén",
policy "Giữ cả hai" → archive 1 extracts, archive 2 fails with "Lỗi: không giải được …", log says `Đã giải 1/2`, and
the result menu is still shown with `Xóa file nén gốc`. One click moves **both** origins to the Trash, including the
corrupt one that produced no output. Nothing in the app warns.

**Ask of Boss:** keep §3 item 3 as written, but promote it from "must not run over failed inputs" to a named defect
with this sequence, and decide whether it is fixed inside 03C or removed (the spec currently offers "or defer that
action until separately reviewed"). A Builder cannot make that product call.

### 4. Medium — `place(policy: .ask)` silently succeeds and destroys staging

Not reachable from `CompressDetailView` today (the view always resolves `.ask` first), so this is a latent hazard for
the shared API the spec wants to centralize — not a current user bug. Measured:

```
conflicts: ["a.txt"]
RESULT success, placed=0 items=[]
dest a.txt still: OLD
staging exists after place: false
```

`ArchiveRunner.place` returns `.success([])` and deletes the staging folder when the caller passes `.ask` and nobody
resolved it (`ArchiveRunner.swift:177–178` `guard case .write … else { continue }`, plus `defer` removing staging at
`:171`). An empty success reads as "extracted nothing, all fine" and the data is gone. §5 says "a single shared policy
must apply to `extractToStaging`, including clipboard import" — so more callers will hit `.ask`.

**Ask of Boss:** the spec should require `.ask` at the placement boundary to be a hard precondition failure rather than
a silent skip, with a test. Cheap, and it matches rule 1.

### 5. Low — the spec's false-promise copy is still shipped and the spec does not schedule its removal

`CompressDetailView.swift:222` tells Merge users: *"Nếu giải nén lỗi, thư mục đích không bị đụng tới"* ("if extraction
fails, the destination folder is not touched"). The spec's own probe table contradicts this (first placement lands,
then failure, staging removed). §7 correctly replaces the claim with a job journal and partial-result reporting, but no
stage in §9 explicitly says to change this sentence, and its L10n key is add-only-below (`L10n.strings.json:7138`).

**Ask of Boss:** add to stage 03C "replace the Merge InlineNote so it no longer promises an untouched destination".
Otherwise the fix lands and the lie ships with it.

### 6. Verified correct — two things the spec asks for already hold

Recording these so 03B does not re-litigate them:

- **Case and Unicode reservation inside one batch already work.** `README.md` + `readme.md` → `readme 2.md`.
  NFC (`tệp.txt`) and NFD (`te<U+0323>…`) forms are equal as Swift `String`, so the `lowercased()` reservation set
  catches both and the second becomes `tệp 2.txt`; writing both to APFS yields **one** file, so the collision was
  genuinely avoided, not merely renamed.
- **Staging privacy already holds.** `.itemReplacementDirectory` gave mode `0o700`, owner `wolong`, under
  `/var/folders/…/T/TemporaryItems/` and on the same volume as the destination — including when the destination folder
  does not exist yet ("Thư mục mới cạnh file nén" before creation), which is the case most likely to break.

The spec's free-space requirement remains genuinely missing from source: `grep` for
`volumeAvailableCapacity|freeSpace|capacity` across `Core/Archive/`, `CompressDetailView.swift` and `ClipTransfer.swift`
returns **nothing**, confirming §1's "no free-space preflight" row.

## What this review does not cover

- No installed-app or live run; permission, TCC, external-volume and UI behavior stay Boss-only.
- No hostile/large archive, low-disk or expansion-bomb test; the spec already scopes those to stage 03A gates.
- The libarchive/system-reader feasibility claim (§3 item 5) was not re-probed; it stands on the author's measurements
  and its own runtime gate.
- `renamex_np` probes ran on the boot volume only. Cross-volume behavior of `RENAME_EXCL`/`RENAME_SWAP` (EXDEV) was not
  measured — the spec's "same-volume rename" assumption still needs that check in 03B.

## Suggested order for Boss

1. Decide findings 1 and 3 (they are product/destructive-scope decisions only Boss can make).
2. Accept findings 2, 4, 5 as spec text edits (naming rule, `.ask` precondition, 03C copy fix).
3. Then approve, and stage 03A can start with `ArchiveSafetyRules` + the pure numbering tests.
