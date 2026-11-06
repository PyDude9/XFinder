# XF-T35 — Storage Analyzer v0.1 (read-only folder scan)

## Goal

Add a small Storage Analyzer section to the existing Storage settings page. The user explicitly chooses one folder, starts a cancellable background scan, sees live progress, and receives a truthful summary of logical file bytes plus the 50 largest eligible files. The feature is local and read-only.

This task is deliberately not a complete MFinder clone. It lays a tested scan/state foundation for later chart and duplicate-finder tasks.

## Baseline and inspected code

- Base reference: `main` at `a24bcb21c7ea03e3394b18604f9a3a09f1169889`.
- `XFinder/Core/SystemMonitor/DiskManager.swift` owns volume snapshots and device I/O rates; do not put folder enumeration there.
- `XFinder/Views/Detail/StorageDetailView.swift` is the current UI surface; retain its volume, I/O and SMART sections.
- New file candidates: `XFinder/Core/Storage/StorageScanEngine.swift` and pure `XFinder/Core/Storage/StorageScanRules.swift` if a separately testable top-N/state rule is needed. Follow repository conventions and register every new app source in `project.pbxproj` (four entries per file); pure source added to the Swift test package also needs its test symlink.
- No dependency on T33 PDF/image, Translate, XF-T34 AppSwitcher, or Browser changes. Do not edit those files.

## User flow

1. User taps “Chọn thư mục để phân tích” and chooses a folder with `NSOpenPanel` / the repo's established folder-picker pattern.
2. User starts the scan. Show the selected folder name, scanned-entry count, and current relative path (avoid displaying unrelated absolute paths in logs).
3. User may cancel. Cancellation stops as soon as the engine reaches its next cooperative checkpoint and leaves a clearly labeled partial/cancelled result; it must not imply that the folder is complete.
4. On completion, show eligible file count, summed logical bytes, skipped item count, and top 50 largest files (name, parent path relative to the picked root, logical size).
5. When no eligible files exist, show an explicit empty result. When some entries were inaccessible or changed during scanning, show a partial-result indicator and count rather than silently claiming completeness.

## Architecture

- `StorageScanEngine` is a focused local service. It accepts a user-picked root URL and cancellation/progress callbacks or an async progress stream. It does not own SwiftUI state, settings, or volume-level disk metrics.
- Traversal and metadata reads run away from `MainActor`. Check cancellation at least every 128 visited entries and between directory batches. Never create an unbounded task per file.
- Do not follow symbolic links. Do not trigger downloads for iCloud/File Provider placeholders. Skip cloud-only files; count skips when the reason can be determined safely.
- Count regular files once. Do not add directory aggregate sizes on top of child files. Use checked/saturating byte aggregation so `Int64` overflow cannot wrap to a smaller plausible number; expose an error/partial state if overflow occurs.
- Keep only a bounded top-50 set while traversing. The final result must be stable-sorted by size descending, then relative path ascending for ties.
- Report **logical bytes** from supported file metadata. Do not call it allocated size, physical use, reclaimable space, or APFS-used bytes.
- UI state is a small explicit state machine: `idle → choosing → scanning → completed | partial | cancelled | failed`. Ignore late progress after a terminal transition. A new scan cancels the prior scan before starting. Closing the view cancels active work.
- No new polling timer. Use task progress updates; throttle UI publication to at most 5 updates per second or when the scanned count changes by a meaningful batch.
- Use the existing project localization pipeline for every string, with Vietnamese keys and English values. Add-only localization tooling; no raw user-visible literals.

## Files allowed

- Modify `XFinder/Views/Detail/StorageDetailView.swift`.
- Add `XFinder/Core/Storage/StorageScanEngine.swift` and optionally one focused `StorageScanRules.swift`.
- Add/update directly related tests and test-package symlink only if pure logic is extracted.
- Add required `XFinder/Resources/L10n.strings.json` entries with the repository add-only script.
- Register new source files in `XFinder.xcodeproj/project.pbxproj` as required.
- Update `docs/AGENT_WORKLOG.md` only under the established no-Notion fallback; normally record evidence in the Notion task Run.

No other source areas are in scope. If the existing picker or UI architecture requires an unlisted file, stop and report the exact dependency instead of expanding scope.

## Failure cases and required behavior

| Case | Required behavior |
|---|---|
| Picker cancelled | Return to idle; do not start a scan or show an error. |
| Empty folder | Completed state with zero files and zero bytes; no divide-by-zero/empty top-N trap. |
| Root is unreadable or permission revoked | Fail/partial with a localized explanation; never claim complete. Do not request Full Disk Access. |
| Individual entry unreadable or removed mid-scan | Increment skipped/error count; continue where safe; mark result partial. |
| Symbolic link | Do not follow or count its target. |
| Cloud-only placeholder | Do not trigger download or count unknown bytes; count as skipped if detectable. |
| User cancels / view closes / starts another scan | Cancel old task; terminal state stays cancelled; old progress cannot update the new scan. |
| Root disappears after selection | Stop and show partial/failure, not an empty successful scan. |
| Very large folder | UI remains responsive; memory used for file results remains bounded by top 50 plus traversal stack. |
| Byte count overflow | Never wrap. Mark partial/failure and report count safely. |
| Network volume | No automatic traversal. A network folder explicitly chosen by the user may be scanned, with ordinary cancellation/errors. |
| Switch disabled / scan not started | No filesystem traversal or background activity. There should be no persistent setting toggle in v0.1. |
| App relaunch | No persisted scan or bookmark is promised; user chooses a folder again. |

## Out of scope

- Treemap, Sunburst, drill-down charts, chart-style settings.
- Full-disk/automatic volume scan or Full Disk Access onboarding.
- Persistent security-scoped bookmarks, background scans, cache or indexing database.
- Trash, delete, cleanup, open-in-Finder, duplicate detection, image similarity.
- APFS clone-aware physical allocation, purgeable-space estimate, cloud download.
- Semantic/AI analysis or any network request.
- New dependencies or bundled command-line tools.

## Acceptance

1. UI scan/cancel/completed/partial/failed/empty states are explicit and all dynamic text is localized.
2. Scanning happens off the main actor and is cooperatively cancellable; view disappearance and restart cancel prior work.
3. Top 50 storage stays bounded independent of total file count; final order is deterministic.
4. Symlinks are not followed, directories are not double-counted, and cloud-only items are not downloaded.
5. Labels and accessibility text identify values as logical file bytes; no physical/APFS allocation claim appears.
6. Existing volume capacity, device I/O and SMART sections continue to compile and render unchanged.
7. Add targeted tests for size ordering/tie break, bounded top-N, overflow handling, empty input, and terminal state/cancellation rules where those rules are extracted as pure logic.

## Verification commands

- `swift test --package-path Tests --filter StorageScan` (adapt filter to actual added suite names; record exact command).
- `plutil -lint XFinder.xcodeproj/project.pbxproj` if the project file changes.
- `sh scripts/gate-all.sh`; record the exact output in the task Run.
- Report build, targeted tests, full gate, and live behavior separately. Do not install or launch XFinder from a Builder worktree. Live macOS file-permission behavior remains unverified unless exercised in the installed app by the owner.

## Teaching checkpoint

Explain in the Run in plain language: (a) why volume-used bytes differ from summing folder logical bytes, (b) how cooperative cancellation works, and (c) why bounded top-N storage prevents a large folder from using unbounded result memory. Include one concrete example or analogy for each.

## Independent review notes

The cross-tool reviewer should check that scan scope, logical-size wording, Swift 6 actor boundaries, cancellation ownership, permission semantics, and test-file/project registration agree with current code. Record any blocking issue here before implementation. If a real architectural mismatch requires an unlisted file, stop and return the proposed scope change.

## Independent review

- **Status**: No blocking gaps found.
- **Review date**: 2026-11-06.
- **Baseline verified**: `main` commit `a24bcb21c7ea03e3394b18604f9a3a09f1169889` (gate baseline green, 2894 tests passing).

### Checklist verification

1. **Scope**: Focused v0.1 folder scan in `StorageDetailView` (read-only, local, cancellable, logical bytes, top-50 largest files). No scope creep into charts, disk-wide sweeps, delete/cleanup, or persistent bookmarks.
2. **File list**: Allowed files (`StorageDetailView.swift`, `StorageScanEngine.swift`, optional `StorageScanRules.swift`, tests/symlink, `L10n.strings.json`, and `project.pbxproj`) are complete and do not touch any forbidden areas (`Info.plist`, entitlements, `DatabaseService`, `ArchiveRunner`, `JunkCleanup`, etc.).
3. **Picker permission semantics**: Aligns with macOS App Sandbox (`ENABLE_APP_SANDBOX = YES`, `ENABLE_USER_SELECTED_FILES = readonly`). User-initiated folder selection via `NSOpenPanel` grants in-session access without requesting Full Disk Access or requiring persistent security-scoped bookmarks.
4. **Cancellation and lifecycle**: Cooperative cancellation points (every 128 entries and directory batches), task cancellation on view disappearance (`onDisappear`) or new scan start, and explicit dropping of late progress updates post-terminal state (`cancelled`/`completed`/`failed`) prevent background stalls or UI races.
5. **File-provider placeholders**: Skipping dataless/cloud-only files (`ubiquitousItemDownloadingStatus == .notDownloaded` or `SF_DATALESS`) without opening file handles prevents unintended network downloads.
6. **Symlink and size semantics**: Explicitly disallows following symlinks; counts regular files once; sums logical bytes via `fileSizeKey` rather than physical/APFS-allocated blocks; uses checked/saturating addition (`addingReportingOverflow`) to protect against `Int64` overflow.
7. **Bounded memory**: Ingesting entries into a bounded top-50 structure during traversal guarantees $O(1)$ result memory overhead even across millions of files; stable sort with relative path tie-break ensures determinism.
8. **Test architecture & project registration**: Separating pure algorithms into `StorageScanRules.swift` matches repository conventions (`Tests/Package.swift` + symlink in `Tests/XFinderLogicTests/`). App files require four entries in `project.pbxproj` and pass `plutil -lint`; test files remain outside `project.pbxproj`.
9. **Acceptance commands**: Verification commands (`swift test --package-path Tests --filter ...`, `plutil -lint`, `sh scripts/gate-all.sh`) are executable and verified against the current tree.

### Non-blocking recommendations for implementation

- **Picker-to-scan transition**: In `StorageDetailView`, clarify if selecting a folder immediately triggers the scan (`choosing` → `scanning`), or if selecting sets a picked folder with a dedicated "Quét" (Scan) button. Immediate scan upon picker confirmation is recommended to avoid unnecessary intermediate states.
- **Defensive security scoping**: Although `NSOpenPanel` grants session access in App Sandbox, wrap traversal root access in `rootURL.startAccessingSecurityScopedResource()` with a paired `defer { rootURL.stopAccessingSecurityScopedResource() }` for defensive consistency across execution contexts.
- **Ubiquity key check cost**: Querying ubiquity metadata on large local folders can introduce IPC overhead; check `isUbiquitousItem` before reading `ubiquitousItemDownloadingStatus`, or prefetch keys via directory enumerator properties.
- **Package traversal**: Ensure `FileManager.DirectoryEnumerationOptions` explicitly defines package behavior (e.g., whether `.app` bundles are traversed into constituent files or skipped as packages). Default traversal into regular files satisfies the "count regular files once" rule.
