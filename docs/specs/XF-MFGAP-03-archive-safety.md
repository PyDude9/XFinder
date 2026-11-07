# XF-MFGAP-03 — Archive safety (DRAFT — Boss approval required before code)

## Goal / baseline

Người dùng vào **Nén & Giải nén → Giải nén** để chọn nơi nhận, xem dung lượng cần dùng và các xung đột, rồi giải nén mà không mất tệp nguồn hoặc ghi đè im lặng.

- Source baseline measured: main `1143525` (includes XF-MFGAP-02 merge `1ad19cb` and alias fix `8092dd0`). Branch: `agent/codex-XF-SETTINGS`, rebased as Boss requested.
- Requirements: `docs/MFINDER_GAP_AUDIT_2026-11-07.md`, Archive options crosswalk + Feature 3; `docs/reference/MFINDER_PROMPT_SYSTEM.md:145–193`.
- **This deliverable is a measured specification only. No app source was changed.** Do not start implementation until Boss approves this file and the named destructive-engine scope.
- No bundled `7zz`, downloaded executable, new cloud service, or automatic archive upload. Keep the app's Swift/AppKit/SwiftUI identity and current page.

## 1. Existing behavior — source evidence

| Owner / baseline lines | What exists | Gap relevant to this task |
|---|---|---|
| `ArchiveEngine.swift:14–35,123–155` | Create ZIP/TAR.GZ with system ditto/zip/tar; ZIP extraction uses ditto, other input uses tar. | No typed entry manifest, compressed/uncompressed budget or capacity plan. Format detection is partly extension-based. |
| `ArchiveEngine.swift:47–85,173–180` | Finder-style numbering and reserved names within a placement batch; Keep Both/Ask/Merge. | Existence checks are snapshots. `merge` returns the existing path; it is not a no-overwrite commit primitive. |
| `ArchiveEngine.swift:184–198` | Reject absolute/tilde/lexically escaping relative symlink targets after extraction. | Does not validate raw archive entry paths before extraction, destination link components, hard-link targets or a complete link graph. |
| `ArchiveRunner.swift:39–69` | Child process off MainActor, stderr drained before waiting, cancellation sends SIGTERM. | Cancellation before PID publication has a race; no hard timeout/escalation, bounded stderr or parent-owned decoded-byte quota. |
| `ArchiveRunner.swift:76–119` | Creation checks missing sources; ZIP top-level readback; failures remove `output`. | Assumes caller has reserved an unused output. Cleanup does not establish ownership of that path. ZIP readback is not a complete data/CRC manifest check. |
| `ArchiveRunner.swift:132–157` | Same-volume private staging, then escaping-link check and top-level listing. | Entry validation occurs after materialization. No free-space preflight or runtime expansion/file-count limits. Duplicate archive entries can already have overwritten one another inside staging. |
| `ArchiveRunner.swift:168–199` | Place top-level items; merge uses ditto/replaceItemAt, discard staging on return. | Existing destination symlinks can be followed; nested leaf collisions overwrite under Merge; later failure can leave earlier placements with no partial/recovery result. |
| `CompressDetailView.swift:48–84,191–224,346–363` | Four destinations: new folder beside archive (current default), same folder, Downloads, custom; Keep Both (default), Ask, Merge. All are per-run `@State`. | Retain the current defaults. Do not introduce persistent keys or change defaults in this task. Current Merge copy explicitly says files will be replaced. |
| `CompressDetailView.swift:243–253,331–338,433–484` | One untracked Task, busy indicator, per-archive loop, result/reveal actions. | No user Cancel/session ownership; no preflight review; later sources continue after individual failures; result does not describe partially placed files. |
| `CompressDetailView.swift:393–416` | Explicit creation Replace sends the old archive to Trash before building the new one. | If creation fails, the old path is already gone; replacement must wait for validated new output. |

Shared API constraints: `ClipTransfer.swift:98–106` imports through `extractToStaging` and reads its manifest directly. Creation callers also include Finder Actions, Drop Tray, Notch, File Browser and ClipTransfer. Safety must live in the shared runner, not only this page. Keep existing signatures through defaulted options/adapters where possible. New Failure cases require the exhaustive mapping in `ClipTransfer.swift:128+` to be updated without changing clipboard data/schema semantics.

The lesson from Boss fix `8092dd0` is applied here: avoid expensive per-entry Foundation resource-value queries when raw archive metadata or one volume query answers the question. Fingerprint the source and query the actual destination volume; do not add redundant metadata I/O to unrelated paths.

## 2. Terminal measurements (2026-11-07)

Environment: macOS **27.2 / 26B123**, arm64. `/usr/bin/tar --version`: bsdtar 3.5.3, libarchive 3.7.4; system unzip 6.00 with Apple modifications. Probes compiled the **unchanged** ArchiveEngine/ArchiveRunner with `swiftc`; fixtures were generated under `/tmp/xf-archive-safety-probe/data`. No installed XFinder interaction, actual user files or actual Trash operations were used. These observations establish only this terminal/process and OS/tool version.

| Probe | Observed result | Meaning / limit |
|---|---|---|
| Existing archive suites | **33 tests, 0 failures**, 0.610s test execution. | Existing happy paths pass; this is not a security-parity certificate. Log: `/tmp/xf-archive-safety-probe/tests.log`. |
| Ordinary ZIP through runner | Staging succeeds, one top-level folder; ~0.016s in this tiny fixture. | Preserve this flow; timings are observations, not performance promises. |
| Keep Both: existing `folder/same.txt=OLD`, archive holds `NEW` | Success at `folder 2`; old remains `OLD`, new copy is `NEW`. | Current top-level numbering works in this fixture. |
| Merge, same inputs | Success; original `folder/same.txt` becomes `NEW`. | Merge currently replaces leaves, unlike the requested combine-folders/rename-colliding-files behavior. |
| Existing destination `folder` is a symlink to a separate probe directory | Merge reports success; `outside/same.txt` becomes `NEW`. | **Destination containment is a real gap.** Checking only links supplied by the archive is insufficient. |
| Archive contains an absolute symlink | Runner returns `unsafeLinks(["jump"])`; no payload placed. | Current post-extraction link check protects this case. It does not prove pre-materialization safety. |
| Absolute link followed by `jump/payload.txt` entry | ditto returns status 1 (`Not a directory`); no payload appears at the outside target. | This particular tool/version blocks this fixture; do not assume all link-order attacks are covered. |
| ZIP entry `../escaped.txt` through raw ditto into a controlled probe subdirectory | Exit 0, entry normalized to `escaped.txt` inside extraction root; no outside marker. | Tool normalization is not explicit app rejection and changes the requested path. Future preflight must inspect raw names. |
| ZIP absolute entry into a controlled probe subdirectory | Exit 0, leading slash stripped; nested `tmp/.../absolute-output.txt` appears inside root. | Again normalization, not app path-policy enforcement. |
| TAR entry `../tar-escaped.txt` through raw tar | Exit 1, `Path contains '..'`; no outside marker. | Format/tool-dependent behavior; one format's rejection cannot stand in for the shared safety policy. |
| Two ZIP entries both named `same.txt`, contents FIRST then LAST | Runner reports staging success; only one item exists, contents `LAST`. | Duplicate archive paths overwrite silently before placement policy runs. |
| Bounded inflation fixture | **8,273-byte ZIP → 8,388,608-byte file (~1,014×)**; runner staging succeeds in ~0.012s. | Proves absence of an expansion policy for this bounded case. It is not a disk-filling bomb test and does not prove arbitrary-scale behavior. |
| Two planned placements: first valid, second staged source missing | Failure returned; first file is already placed; staging is removed. | Need an outcome journal and rollback/recovery contract, not “nothing changed” on any failure. |
| Same-folder Merge of ZIP holding a leaf named `self.zip`, the selected source's own name | Success; original source archive becomes plain text `REPLACED SOURCE` (`unchanged=false`). | **Source-archive protection is a real gap in a reachable option combination.** |
| Direct runner compression into an already-existing regular output | Returns `missingData`; old sentinel is not preserved and the output path is absent afterwards. | Deliberately violates today's caller-only unused-output precondition; demonstrates the consequence of a plan/commit race. |
| Direct runner compression into an existing nonempty directory | Tool error `Is a directory`; failure cleanup deletes the probe directory and its sentinel. | Cleanup must only remove a proven job-owned candidate, never an arbitrary requested output path. |
| Password ZIP created by current zip backend | Encryption flag set, AES extra field 0x9901 absent, Python stdlib decrypts with the test password. | Current creation is legacy-compatible ZIP encryption, **not evidence of AES-256**. Do not advertise AES-256 under this backend. |
| Destination-volume query | `volumeAvailableCapacityForImportantUsage = 112,685,560,932 bytes` at probe time. | API is usable here; value is volatile. No low-disk volume was filled or mocked in the installed app. |

Feasibility probe for a structured reader: system `/usr/lib/libarchive.2.dylib` loads and reports **libarchive 3.7.4**. Its typed entry API exposes raw `../escaped.txt`, the absolute entry, the absolute symlink target, both duplicate names and the 8 MiB declared size before publication. The SDK has `usr/lib/libarchive.tbd` but **no `usr/include/archive.h` at the checked SDK path**. This is evidence about that SDK header path, not a claim that the system library is absent. Python/ctypes was only a probe and must not ship.

Artifacts: `raw-results.json`, `runner-results.log`, `compress-results.log`, `self-results.log`, `metadata-results.json` in `/tmp/xf-archive-safety-probe`. Temporary examples contain only synthetic data. The spec retains the important results if those scratch artifacts are later removed.

## 3. Scope and proposed decisions for Boss review

1. Keep the current page and destination choices; retain **new folder beside archive + Keep Both** defaults. Downloads/custom remain available. No page move, new UserDefaults key or bundled engine.
2. **Proposed behavior change:** Merge combines directories recursively but numbers colliding leaf files instead of replacing them. File/directory type collisions keep the incoming item under a numbered name. Label: “Gộp thư mục, giữ cả hai file trùng”. Ask offers Keep Both / Merge / Cancel with a reviewed plan. This deliberately fixes today's destructive Merge semantics.
3. Source archives and all selected inputs are protected identities for the entire batch, including an entry named like another input archive. They are never overwritten, removed or automatically trashed by extraction. Number an incoming collision or refuse it. Existing separate “Xóa file nén gốc” action must not run over failed/unprocessed inputs: require explicit confirmation and restrict it to the successfully handled input identities, or defer that action until separately reviewed.
4. Keep ZIP/TAR.GZ creation and current supported extraction formats (ZIP, TAR, TAR.GZ, TAR.BZ2). Preserve helper-only TAR.XZ/tgz behavior only when the new reader's format matrix verifies it; do not advertise unverified formats. No 7z/RAR promise or unsafe CLI fallback.
5. **Proposed technical direction:** a narrow Swift adapter for the public system libarchive C API (`dlopen`/typed C function pointers, runtime symbol/format checks) provides structured metadata and bounded stream reads. Register only approved formats/filters. It needs no downloaded binary, Python runtime, new framework or C-header assumption. Missing symbols/unsupported format fail closed with a clear message. Runtime behavior on macOS 14 remains a future acceptance check, not established by the macOS 27.2 probe.
6. Keep compression tooling initially; write/verify a fresh private candidate and publish it safely. Preserve explicit creation Replace only through the reviewed replacement transaction in §7. Legacy password creation must be labelled honestly; AES-256/Touch ID, new encryption formats and Keychain reuse are a separate task. Encrypted extraction without a supported key/decoder is refused before output placement, not retried with weaker encryption or an online service.

## 4. User flow and controls

Entry: existing **Nén & Giải nén** page. Reading order: mode/input list → destination → collision policy → inspection/review → primary action/progress → results/recovery.

1. Choose/drop supported archives; list each name and source scope. Cancel picker keeps current input. Reject cloud-only/unreadable/nonregular input with an actionable reason; do not download silently.
2. Choose “Thư mục mới cạnh file nén”, “Cùng thư mục với file nén”, Downloads or custom. A custom destination is required when custom is selected: do not silently fall back to the source folder. Show the full resolved destination in the review.
3. Choose Keep Both, Merge or Ask. Keep Both numbers the whole new extraction folder when using the new-folder mode; same-folder/merge plans resolve each incoming path deterministically. Reserve both existing and intra-batch names using the target volume's case/normalization rules. Ambiguous aliases or name collisions that cannot be represented safely are rejected.
4. “Kiểm tra” reads the archive, validates its manifest and budgets, inspects conflicts and checks capacity. Show “Đang kiểm tra tệp nén…” with Cancel and honest counts; never invent a percentage. Input/archive/destination identity changes invalidate the plan.
5. Review archive count, decoded bytes, required temporary bytes, available bytes, selected policy, renamed/conflicting items and skipped optional metadata (if any). Dangerous/unsupported archives block “Giải nén”. Show exact reasons, e.g. “Tệp nén chứa đường dẫn đi ra ngoài thư mục đích”, “Không đủ dung lượng: cần …, còn …”, “Tệp nén vượt giới hạn an toàn”. No “extract anyway” bypass.
6. “Giải nén” uses the approved plan. While running, freeze its inputs/options, show phase/current archive, measured bytes/items and Cancel. Closing the page cancels future work and retains actual outcomes in the session coordinator. Hover, menu dismissal and closing Settings never approve a conflict.
7. Results distinguish completed archives, rejected archives, cancelled untouched items and partial/recovery-needed jobs. Show actual output URLs with Reveal/Open, actual renamed files and errors. No empty or partially placed output is labelled full success. Never auto-open Finder repeatedly during a batch; offer it after completion.
8. Cancel/Return/Escape: picker Cancel returns; passive popover closes first; operation Cancel stops at a safe chunk/item boundary; a commit already in flight finishes and is recorded. Confirmation defaults to Cancel. All selection, review, cancel and reveal controls have keyboard/VoiceOver access.

## 5. Manifest, containment and resource policy

A single shared policy must apply to `extractToStaging`, including clipboard import; UI validation alone is insufficient.

### Input and manifest

- Open an existing local regular archive without following a substituted symlink; bind identity/size/timestamps to the job. Retain/check the descriptor and revalidate between inspection, extraction and publication. Archive mutation causes failure; staging may be discarded, destination remains untouched before commit.
- Read structured raw entry metadata. Reject absolute/drive/UNC paths, root-escaping `..`, NUL/invalid/ambiguous encodings and paths the backend cannot safely represent. Normalize separators and `.` consistently with the selected format, then check containment by components, never a string-prefix test. Do not rely on the CLI stripping a leading slash or `..`.
- Reject duplicate normalized entry paths, case/Unicode aliases on the destination filesystem, file-as-parent/type conflicts, unsupported special files (devices/FIFOs/sockets), external/absolute hard links and sparse/unknown-size features the reader cannot bound. Invalid entries reject the whole archive before publication.
- Absolute/tilde/escaping symlinks are rejected. Proposed v0.1: relative symlinks are allowed only after the complete graph resolves within this archive without cycles, unknown targets or an escaping chain; create them last. No archive entry may write through a symlink. Unsupported hard-link representations are refused explicitly, not silently dropped; enabling internal hard links needs the same graph/type/containment proof.
- Use descriptor-relative no-follow traversal/writes in a private 0700 staging root. Never follow existing destination symlinks/reparse-like aliases; a symlink at any placement component means refuse/replan or preserve the incoming object under an explicitly safe numbered location. Check again at commit.
- Preserve current Mac ZIP metadata where actually supported. Include a measured resource-fork/xattr/AppleDouble round-trip fixture. Do not blindly discard user entries named `__MACOSX`/`.DS_Store`, restore arbitrary ownership/setuid/immutable flags, strip quarantine or apply metadata through a link. Unsupported required metadata is reported before publication; do not claim universal metadata parity. Apply recognized metadata only to job-owned staged objects; preserve/propagate quarantine as appropriate.

### Proposed centralized safety limits (not recovered MFinder defaults)

These are draft product/safety choices for Boss approval, implemented in pure `ArchiveSafetyRules`; no hidden unlimited mode.

| Limit | Proposed initial policy |
|---|---|
| Entry count | 100,000 entries per archive and per active batch |
| Decoded payload | 8 GiB per file; 16 GiB cumulative batch |
| Path bounds | 128 components; 4 KiB encoded path; reject filesystem component overflow |
| Extreme ratio | Reject >1,000× expansion once decoded payload exceeds 256 MiB; small compressible fixtures are still bounded by byte/time limits |
| I/O buffers | At most 1 MiB per stream; no full-archive/full-file RAM loading |
| Time | 10-minute active processing budget per archive, monotonic and checked at safe boundaries; expose a bounded reviewed higher budget through re-planning if future use requires it |
| Capacity reserve | At least 64 MiB operational headroom after planned peak allocation |

Declared sizes are untrusted. Enforce actual decoded bytes, entry count, path bounds, deadlines and cancellation during **inspection as well as extraction**. A 1 MiB caller buffer does not establish a hard total RAM/CPU bound for opaque native header/filter parsing. Stage 03A must measure oversized metadata/header behavior and interruption; if that work cannot be bounded in-process, use a separately approved resource-limited worker or keep that input capability disabled. Do not silently add a helper target outside the approved file list. Reading the next compressed TAR header can itself expand data: do not call an unbounded internal skip and assume inspection is cheap. Drain/verify payloads in bounded chunks when needed, reject CRC/truncation/size disagreement, and never recurse into nested archives automatically. The 8 MiB / 8,273-byte measurement is a benign high-ratio fixture below the proposed ratio floor, not automatically classified malicious.

## 6. Free-space plan

- Query the actual staging/destination volume once per planning boundary (not per entry); obtain fresh available capacity before staging and before commit. If the value is unavailable or the target volume changes, block with retry/change-destination; never treat unknown as infinite.
- Compute a conservative peak: decoded staged payload + placement-copy/metadata overhead + any replacement/recovery allocation + operational reserve. If a bounded source snapshot is needed, include its compressed bytes too. Use checked/saturating arithmetic; overflow means refusal. Do not use compressed ZIP bytes as the required extraction size.
- Same-volume rename can avoid a second payload copy for new items; merging/cross-volume or fallback copies must include both live allocations. Do not promise APFS clone/dedup savings. Use a conservative logical allocation bound for sparse data unless validated physical bounds exist.
- Account for the entire planned batch and concurrent runner users with a per-volume reservation/coordinator. On a mixed-volume batch, plan and report each volume separately. A disappearing/unwritable volume invalidates its plan.
- Preflight cannot guarantee the disk will remain free. Runtime write errors/low-space checks stop safely; never publish a truncated file as success. Capacity tests use an injected provider/quotas, not filling the owner's disk.

## 7. Publication, conflicts, cancellation and recovery

- Each archive extracts independently into its own owned staging root and is fully validated before placement. A bad second archive does not corrupt the first archive's completed result; the batch summary states both outcomes.
- Keep Both and recursive Merge perform exclusive no-replace publication. If a planned destination appears or changes before commit, re-plan/ask/refuse; never reinterpret the collision as permission to replace it. Leaf collisions are numbered with compound extensions preserved.
- Retain a job journal of created objects/identities and completed placement steps. On failure/cancel, roll back only unchanged objects demonstrably created by this job; never remove a pre-existing file or a newly user-modified result. If rollback cannot finish, preserve staging/recoverable data and show exact partial outputs/recovery location. Do not claim all-or-nothing publication across unrelated paths.
- Cleanup may remove only verified job-owned temporary roots/candidates. **Never remove the requested final output path just because a subprocess failed.** The existing-output directory probe must become a regression test.
- Compression writes a unique private candidate, verifies complete output (not only an exit code/top-level-name match), then publishes with no-replace semantics. Refuse unsafe input/output ancestry that can archive the growing output itself. On failure, existing outputs stay unchanged.
- Existing explicit creation Replace is a separate confirmed transaction, after the candidate validates: recheck the exact old target; retain a recoverable old version while publishing via the platform's verified replace/exchange primitive; only then send the old version to Trash. If a reliable primitive/identity guard is unavailable, offer a numbered copy or stop. A failed replacement must leave either the original at its path or a clearly reported recoverable original, never silently delete it. Do not overwrite a protected input archive. Boss must review this destructive path separately before implementation.
- Recovery metadata/files remain in an app-owned restricted job directory (no DatabaseService migration). On opening the Archive page, list interrupted jobs and offer Reveal/explicit verified cleanup/recovery; no automatic destructive replay on launch. Never auto-delete user outputs, source archives or unknown orphan paths.
- Cancellation is cooperative between read/write chunks and items; ensure process cancellation requested before PID publication is honored after launch. Terminate/reap owned child processes and bound stderr. No polling while idle. Sleep/quit must not resume destructive work automatically.

## 8. Failure matrix / future acceptance

All scenarios below are future review/acceptance requirements, not claims this draft implements them.

| Given → When | Then |
|---|---|
| Empty selection / picker Cancel → start/close | No job, no filesystem mutation or error-shaped empty success. |
| Ordinary supported archive → inspect, choose new folder, extract | Reviewed size/paths match real output; source bytes unchanged; Reveal points to the real completed result. |
| Existing folder/file → Keep Both | Existing bytes/metadata unchanged; numbered copy preserves every incoming item. |
| Nested same-name files → Merge | Directories combine; colliding leaves get numbered names; no silent overwrite. |
| Entry equals this or another selected source archive → same-folder placement | Input archives are protected; incoming item numbered/refused. |
| `../`, absolute, drive/UNC, duplicate/aliased paths or a file-as-parent → inspect | Whole archive rejected before publication, with zero outside writes. |
| Absolute/escaping/chained/cyclic link, malicious hard link or existing target symlink → extract/commit | Refused without writing through it; outside sentinels stay byte-identical. |
| Declared sizes lie, CRC fails, archive truncates, many entries, huge/sparse payload, expansion/time budget exceeded → read | Stop within configured bounds; no valid-looking partial output; owned staging cleaned or reported for recovery. |
| Available capacity is below/equal/above requirement, unknown, changes or overflows → plan/commit | Boundary is deterministic; unknown/insufficient/overflow blocks; runtime shortage preserves old data. |
| One placement succeeds and the next fails → finish | Roll back unchanged new outputs or report exact recoverable partial result; never silently discard remaining staged data. |
| Pre-existing output file/directory → compression tool fails or races a new writer | Old sentinel survives; only owned candidate is cleaned. |
| Permission revoked, volume unmounted, source replaced, destination changed → any boundary | Refuse/re-plan with inputs retained; no automatic privilege escalation or Full Disk Access request. |
| Cancel, close page, sleep or process-launch cancellation race → active job | Future work stops; in-flight outcome is recorded; no orphan child or auto-replay. |
| Two archives / clipboard import / other creation caller → shared API | Same resource and path policy, separate outcomes, no UI bypass. |
| ZIP password / unsupported encryption or format → inspect/create | Honest supported/legacy/unsupported message; no AES claim, downgrade or unencrypted fallback. |
| macOS 14 / unavailable reader symbols / small window / keyboard/VoiceOver → use controls | Real compatibility checked; fail closed where unsupported; Cancel/Save/Reveal remain reachable. |

Implementation tests must use fresh temporary fixtures and injected capacity/failure providers. Include the exact measured destination-symlink, self-source overwrite, duplicate-entry, partial-placement and existing-output-cleanup cases. Maintain existing archive happy-path tests; update Merge expectations only as the explicitly approved semantic change. Extend `scripts/mutation-check-archive.sh` with executable mutants for traversal, both link boundaries, size/count overflow, insufficient/unknown space, source protection, duplicate paths, no-replace commit, foreign-output cleanup and cancellation; each must RED and restore byte-identical.

## 9. Implementation stages and proposed allowed files

This is a large task split into reviewable commits, with tests/gates after each stage; do not expose a dead safety switch between stages.

| Stage | Deliverable | Main files / gate |
|---|---|---|
| 03A | Pure manifest/path/link/budget/capacity/placement rules + structured system-reader feasibility/compatibility tests. | New `Core/Archive/ArchiveSafetyRules.swift`, `SystemArchiveReader.swift`; focused tests/symlinks; project registrations. Do not route users through an incomplete reader. |
| 03B | Shared bounded inspection/extraction staging, source/volume identity, cancellations and owned cleanup. | `ArchiveEngine.swift`, `ArchiveRunner.swift`; new `ArchiveJob.swift` / `ArchiveRecoveryStore.swift` only if needed for the specified job ownership/journal; `ClipTransfer.swift` narrowly for failure mapping/defaulted API adaptation. Shared import must get the same checks. |
| 03C | Reviewed placement/replacement recovery and existing-page UX; full fixture and mutation matrix. | `ArchiveRunner.swift`, `CompressDetailView.swift`, job/recovery files; no other page moves. |

Also allowed after approval: `XFinder/Resources/L10n.strings.json` via add-only tooling; `XFinder.xcodeproj/project.pbxproj`; directly related Archive tests/test symlinks; `scripts/mutation-check-archive.sh`; worklog/changelog. Keep other callers source-compatible; if another file must change, report the exact dependency to Boss first.

**Scope amendment needed before Builder code:** `ArchiveRunner` and the existing Trash/replace branches in `CompressDetailView` are destructive-engine territory reserved by `AGENT_TASKS.md` §2. This draft requests Boss approval for these named paths only, or Boss ownership of the destructive substep. Approval of this spec does not authorize edits to other cleanup/uninstall/Trash engines, entitlements, Info.plist, Diagnostics, clipboard schema, install/release scripts or external agent configuration.

After approval: run focused pure + real temporary-fixture tests, project lint and new-source compile-list checks, the archive mutation harness detached (one at a time, no source edits during it), then `sh scripts/gate-all.sh` with a worktree-specific XF_OUT. Report build/tests/mutation/gate/live separately. Builder never installs, launches, pushes or merges. Installed-app permission, external-volume, metadata and UI checks belong to Boss.

## Approval points (proposed, not yet accepted)

Boss review must confirm: recursive Merge keeps conflicting leaves as numbered copies; the proposed safety limits; the system-reader/runtime availability approach; and the named destructive-runner/replacement scope. Exact original MFinder defaults are not inferred. No implementation starts from this draft.

## Boss approval (2026-11-07, after reviewing stage 03A)

Stage 03A was built before this approval; Boss reviewed it as code (gate green 3010/0 outside the builder, mutation 16/20 RED with
four measured-equivalent guards) and merged it unrouted. Decisions for 03B/03C:

1. **Merge semantics — approved.** Directories combine; colliding leaves and file/directory type collisions get numbered names
   (compound extensions kept). Label "Gộp thư mục, giữ cả hai file trùng". Ask = Keep Both / Merge / Cancel, default Cancel.
2. **Limits — approved as proposed** (§5 table). They are XFinder safety choices, not MFinder defaults; keep them in
   `ArchiveSafetyRules.Limits` only.
3. **Reader — approved:** system libarchive through `dlopen`, zip + tar with gzip/bzip2/xz/none only, fail closed. In-process
   parsing of hostile headers is accepted (same system library Archive Utility uses); no helper target. One required change in 03B:
   `BlockLedger` for an entry must be limited by the **remaining** batch budget (`maxDecodedBytes - decoded`), not the whole
   budget, so one entry cannot decode a second full budget before the cumulative check. The 10-minute deadline must be checked in
   the same block loop (monotonic clock, injected for tests).
4. **Destructive scope — approved for exactly these paths:** `ArchiveRunner.swift`, `ArchiveEngine.swift`, the Trash/replace
   branches of `CompressDetailView.swift`, new `ArchiveJob.swift`/`ArchiveRecoveryStore.swift`, `ClipTransfer.swift` failure
   mapping only. Nothing else.
5. **Creation Replace:** build + verify the candidate first; then `trashItem(old, resultingItemURL:)`; then `renamex_np(candidate,
   target, RENAME_EXCL)`. If that rename fails, move the trashed original back from `resultingItemURL` and report; never `rm`.
6. **"Xóa file nén gốc" (decision point 2) — keep, fix in 03C:** only for archives whose extraction completed in this run; a
   confirmation alert listing the names (default button Cancel); Trash only; per-file failures shown (today `try?` hides them and
   the button trashes every selected source even after a failed run).
7. **Password ZIP:** label the current backend honestly ("mật khẩu ZIP chuẩn cũ", no AES-256 claim). AES/Touch ID is a separate
   task, not part of 03.

Order: 03B (shared inspection + staging + identity + cancellation + owned cleanup, routed through `extractToStaging` so
clipboard import gets it too) → Boss review/merge → 03C (placement, recovery, page UX, source-delete fix, mutation matrix).
