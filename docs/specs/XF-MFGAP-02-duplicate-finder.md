# XF-MFGAP-02 — Exact Duplicate Finder (APPROVED by Boss 2026-11-07)

## Goal and authorization

Người dùng vào **CÔNG CỤ → Tìm tệp trùng** để quét một thư mục đã chọn, xem các nhóm file có nội dung giống hệt, chọn bản muốn bỏ, kiểm tra lại rồi chuyển chúng vào Thùng rác.

Owner approved exactly this new sidebar page in Q-MFGAP-PAGES (main `f5c7c6c`, 2026-11-07). No other page/control moves, merges or removals are authorized. This is a proposed spec, not permission to start coding: Boss reviews it first. Baseline for the preceding storage task is `4e73910`; XF-MFGAP-01 code is `07257ae` on `agent/codex-XF-SETTINGS`.

Reference: `docs/reference/MFINDER_PROMPT_SYSTEM.md` Feature 2. Teaching material is explanatory only. Similar images/perceptual hashes are a later task.

## Scope

- One explicitly chosen root; local-only, read-only scan; no automatic full-disk/background scan, persistent index, network access or cloud download.
- Exact files only: size grouping → streaming SHA-256 in **1 MiB (1,048,576-byte) chunks** → byte-for-byte confirmation before presenting the destructive confirmation.
- Never permanently delete. Trash only user-selected files after fresh verification, with at least one unselected verified keeper per group.
- Scan state/result is session-only. No new always-on toggle, no persistence of content, hashes or paths across relaunch.

## Screen and controls

Existing sidebar adds exactly one route named “Tìm tệp trùng” under CÔNG CỤ. The page uses current XFinder Settings tokens and localization.

1. Page header and concise “Quét trên máy; tệp chỉ thay đổi khi bạn xác nhận chuyển vào Thùng rác” explanation.
2. “Chọn thư mục…” opens a folder picker; Cancel returns without error. Show chosen root and “Quét” / “Huỷ quét”.
3. Phase/progress area: “Đang nhóm theo kích thước…”, “Đang tính checksum…”, “Đang so sánh nội dung…”, with processed/skipped counts. Do not show a percentage without a known denominator.
4. Summary: group/file counts and **logical bytes of selected copies**, not promised physical/reclaimable APFS space.
5. Grouped results with filename, relative folder, logical size and modification date. Each group has an explicitly labelled suggested keeper; it is only a suggestion. Initial selection is empty. Every row has a checkbox and visible Reveal action. Keyboard/VoiceOver users can select and inspect each row.
6. “Chuyển các bản đã chọn vào Thùng rác…” is disabled with a reason when selection is empty, a group has no keeper, access is unavailable, the scan is incomplete, or verification is running. Changing the keeper is an explicit selection operation; never silently trash the final copy.
7. Preflight/confirmation names exact count and scope, shows changed/skipped candidates, then “Huỷ” and “Chuyển vào Thùng rác”. Cancel is default. A successful action reports actual moved/failed/skipped counts; Reveal Trash is available through the existing system route if supported. Closing a page never approves an operation.

## Architecture and evidence pipeline

### Scan

- A focused scan service owns filesystem I/O off MainActor. UI owns state and receives throttled progress; stale run IDs cannot update a replacement scan.
- Use XFinder's measured physical traversal behavior. Skip symlinks/aliases, application bundles and cloud-only/dataless files without opening them. Count inaccessible/changed/unsupported entries. Do not request Full Disk Access.
- Record a fingerprint for each eligible regular file: URL, device/inode, logical size, modification and change timestamps (including available subsecond precision). Reject identity/type changes before, during and after reads.
- Collapse multiple paths to the same device/inode: hard links are not extra independent copies or reclaimable storage.
- Group by logical size. Unique-size groups need no file-content read. Empty files are eligible, with explicit empty-content equivalence.
- SHA-256 candidates use streaming 1 MiB buffers; never map/load a whole large file. Proposed bounded concurrency: at most four workers, centralized in pure rules and documented as a new design choice; no unbounded task per file. Check cancellation between chunks and directory batches.
- Hash equality creates a candidate group, not final proof. Compare each candidate to a keeper using chunked byte comparison. A mismatch splits/rejects that candidate rather than reporting it identical. Recheck fingerprints around the comparison.
- Proposed v0.1 bound: 500,000 eligible file records; reaching it yields an explicitly incomplete result and disables Trash. This is a documented safety limit to review, not a recovered MFinder default. Measure representative scan/result memory before acceptance.
- Deterministic groups and keeper suggestion: shallowest relative path, then earliest modification date, then path order. Do not call this the original file as an established fact.

### Revalidation and Trash boundary

1. User selects copies; keep one unselected keeper in each affected group.
2. On the Trash action, verify the selected copies **and keeper** again: identity/type/fingerprint, streaming hash and byte comparison. An unchanged timestamp alone is insufficient.
3. Present confirmation only for the freshly verified set. Changed or unreadable groups are excluded with a clear explanation and “Quét lại”.
4. After confirmation, revalidate again before each move, including path identity immediately before the recycle call. If a keeper changes/disappears, skip remaining members of that group. Path-based Trash APIs still have a race boundary; do not claim atomic batch deletion or protection against a hostile concurrent path replacement. Boss must review this boundary.
5. Use the reviewed macOS Trash/recycle service; await each actual outcome. Never use `removeItem`, shell `rm`, or a permanent-delete fallback. If Trash is unavailable (e.g. a volume without supported Trash), refuse that item.
6. Cancellation stops future moves at the next safe boundary; already recycled files stay in Trash. Show the actual completed/remaining counts. Do not pretend cancellation rolled back completed moves.

**Boss prerequisite:** T35's reviewed sandbox configuration grants user-selected files read-only access. Before enabling Trash, Boss must verify a legitimate writable grant in the installed XFinder app and approve the service boundary. A shell probe does not establish the app's permission. No entitlement or permission expansion is in this Builder scope. Without verified write access, scan/reveal works and Trash is disabled with an actionable explanation.

`docs/AGENT_TASKS.md` §2 reserves file-deleting engines for Claude. The Builder must not implement a new destructive coordinator under this draft. Boss must either own that small integration step or explicitly amend the allowed scope after review.

## State machine

`idle → choosing → ready → grouping → hashing → comparing → results | cancelled | failed`.

`results → revalidating → confirmation → revalidating/moving → results-with-outcomes`.

- New scan cancels the previous run and clears old selection.
- Cancelled/truncated scans are visibly incomplete and cannot authorize Trash.
- Closing while scanning cancels work. Closing while moving cancels future moves, waits for an in-flight recycle result, and retains its outcome for the current session.
- Missing permission keeps the root/choices and offers a new picker or the existing permission recovery route; no repeated OS prompt loop.

## Failure cases

| Case | Expected behavior |
|---|---|
| Picker cancelled / no files / no duplicates | Idle or clear empty state; no content changes. |
| Permission denied/revoked or root removed | Fail/partial with counts; never empty successful scan. |
| File removed/edited/replaced during scan/hash/compare | Exclude it, record reason, retain truthful counts. |
| Symlink, alias, app bundle, cloud-only item | Skip without following/downloading; no file-content read. |
| Hard links / APFS clones | Collapse same inode; describe sizes as logical only; do not promise physical savings. |
| Huge file / many files / zero-byte files | Constant-sized read buffers, bounded workers/results; explicit incomplete state at limit. |
| Hash collision or forced equal hashes | Byte comparison rejects non-identical content. |
| All copies selected / keeper changes | Block confirmation or skip affected group; keep a verified unselected copy. |
| Selection/result is stale after confirmation | Fresh verification before move; skip and explain. |
| Trash denied/full/unsupported volume | Keep original file; report per-item failure, never permanent-delete fallback. |
| Cancel or page close during batch | Stop remaining moves, report actual completed subset. |
| Sleep/app quit | Cancel work and release handles; no automatic resume or destructive replay. |
| Feature/page idle | No traversal, hashing, polling or filesystem access. |

## Proposed files / ownership

Builder after spec approval:

- New pure `XFinder/Core/Duplicates/DuplicateRules.swift` (size grouping, stable ordering, fingerprints/state/selection rules), symlink and meaningful tests.
- New `XFinder/Core/Duplicates/DuplicateScanEngine.swift` (non-destructive traversal/hash/byte comparison).
- New `XFinder/Views/Detail/DuplicateFinderDetailView.swift`.
- `XFinder/Models/SidebarDestination.swift`, `XFinder/Views/RootView.swift`: exactly the approved page/route.
- `XFinder.xcodeproj/project.pbxproj`: four registrations per new app source.
- `XFinder/Resources/L10n.strings.json`: add-only entries.
- A focused mutation harness for pure duplicate-safety rules, proposed path `scripts/mutation-check-duplicates.sh`.

Boss-owned/reviewed step: Trash service and app write-access verification. No `FileWalk`, entitlements, Info.plist, Diagnostics, database schema, install/release script or other feature engine changes in Builder scope. Stop if these dependencies become necessary.

## Future acceptance (not executed)

- Given equal-size different-content files, when scanned, then they never appear as confirmed exact duplicates; force hash equality in a test and byte comparison still rejects them.
- Given several identical files including a hard-link alias, when scanned, then groups are stable and the same inode is not counted as an extra copy.
- Given a multi-GB candidate, when hashing/comparing, then only 1 MiB chunks per bounded worker are resident and Cancel is honored between chunks.
- Given user-selected copies and an unselected keeper, when verification passes and the user confirms, then only the verified selected URLs enter Trash and outcomes match actual callbacks.
- Given a changed/deleted keeper, changed selected path, denied write access or unsupported Trash, when the action runs, then affected files remain and an explicit skip/error is shown.
- Given all copies selected, incomplete scan or no selection, then Trash remains disabled with a visible reason.
- Given cancellation mid-batch, then no new moves start and already moved items remain recoverable in Trash.
- Given keyboard/VoiceOver use, then choose root, inspect groups, select copies, reveal, confirm/cancel and rescan are all reachable.

Verification after approval: focused pure and temporary-fixture I/O tests, mutation RED cases for collision/changed fingerprint/last-copy/selection/cancellation, project lint/compile-list, `sh scripts/gate-all.sh` in an isolated output directory; live permissions and Trash only by Boss in installed XFinder. Never install, push or merge from the Builder.

## Boss approval (2026-11-07) — build it

- Spec approved as written. Proposed limits accepted: **4 hashing workers**, **500 000 eligible files**, 1 MiB chunks.
- **Write access measured:** the installed app's signature carries **no** `com.apple.security.app-sandbox` entitlement
  (`codesign -d --entitlements - /Applications/XFinder.app` → 0 matches), so Trash works on user-chosen folders exactly like the
  file browser and `ActionHistoryStore` already do. No entitlement change.
- **Trash step scope amended:** the Builder implements it in `XFinder/Core/Duplicates/DuplicateTrash.swift` — revalidate (fingerprint
  + hash + byte compare, keeper included) immediately before each `FileManager.default.trashItem(at:resultingItemURL:)`, one item at a
  time, await the result, never `removeItem`/`rm`. This one file is reviewed line by line by Boss before merge (exception to
  `AGENT_TASKS.md` §2 for this task only).
- Mutation harness `scripts/mutation-check-duplicates.sh` must cover: forced equal hash rejected by byte compare, changed fingerprint,
  last copy never trashed, empty selection disables, cancellation stops further moves.

