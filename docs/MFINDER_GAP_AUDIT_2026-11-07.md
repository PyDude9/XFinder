# MFinder → XFinder gap audit

**Audit baseline:** `main` commit `9788415` (the Builder branch points at this commit). This is a source/UI-path audit, not a live feature parity claim. “Done” means the requirement has a reachable current control/implementation with source evidence; it does not mean the Builder installed or live-tested it. Requirements are from `docs/reference/MFINDER_PROMPT_SYSTEM.md`; `MFINDER_PROMPT_TEACHING.md` is educational material and is **not** treated as a feature requirement.

Statuses: **Done**, **Partial**, **Missing**, **Rejected**. Rejected means the requested mechanism conflicts with measured platform/API constraints, data-safety rules, or an explicit product decision; where only one mechanism is rejected but an alternative exists, the feature row is Partial.

For the full current Settings owner/control/key inventory see [MFINDER_SETTINGS_INVENTORY_2026-11-07.md](MFINDER_SETTINGS_INVENTORY_2026-11-07.md). This audit records MFinder's requested option against that current owner page. No control or page is moved by this audit.

## MFinder Settings/options crosswalk — first, per feature

The reference names settings explicitly where it has an exact key. It says `indexDocuments` “etc.” for Desktop/Downloads; those two key names below are a readable inference from the described controls, **not confirmed literal strings in the original spec**.

| Spec ref | MFinder option / setting requirement | Status | XFinder owner, current control/key and evidence on baseline | Next task |
|---|---|---|---|---|
| System §1 L35–38 | `storage.chartStyle` (`treemap`/`sunburst`) | Missing | The reachable owner is **Hệ thống → tab Ổ đĩa**, `StorageDetailView`; it offers a selected-folder scan and top-50 file list, no chart or corresponding key (`StorageDetailView.swift:162–266`; `StorageScanEngine.swift:8–21`). Do not add a dead style picker before charts exist. | XF-MFGAP-01 |
| System §1 L35–38 | `storage.chartFraction` (chart vs inspector split) | Missing | Same owner; no chart/inspector split or corresponding key exists yet (`StorageDetailView.swift:162–266`). | XF-MFGAP-01 |
| System §1 L35–38 | `storage.scan.progress` | Partial | Live count/current relative path is shown in transient scan state (`StorageDetailView.swift:188–200`; `StorageScanEngine.swift:48–50`). There is no persisted progress history. | XF-MFGAP-01 |
| System §1 L35–38 | `storage.scan.percentage` | Missing | Current scan progress exposes counts/path but no percentage (`StorageDetailView.swift:188–200`). | XF-MFGAP-01 |
| System §1 L60–63 | Full-disk scan and “Files and Folders / Full Disk Access entitlement” | Rejected | XFinder's reviewed contract scans only a user-picked folder and explicitly forbids adding entitlements or requesting Full Disk Access for this task (`docs/MFINDER_XFINDER_ROADMAP.md:68–70,84`). Full Disk Access is a user privacy authorization, not an entitlement. | Q-MFGAP-10 |
| System §2 L89–140 | Duplicate Finder settings | Partial | The supplied spec lists no user-facing preference keys. XFinder has no dedicated Duplicate Finder page/service (sidebar routes `SidebarDestination.swift:264–273`; page routes `RootView.swift:78–170`). Baseline has no settings owner. | XF-MFGAP-02 |
| System §3 L155 | `newFolderNextToArchive` extraction destination option | Partial | **Nén & Giải nén** offers new folder beside archive as a per-run destination (`CompressDetailView.swift:48–52,61–72,191–212`); it is not a persisted default. | XF-MFGAP-03 |
| System §3 L155 | `sameFolder` extraction destination option | Partial | The same per-run destination chooser offers the archive's folder (`CompressDetailView.swift:48–52,61–72,191–212`); it is not a persisted default. | XF-MFGAP-03 |
| System §3 L148–194 | Conflict policy / Keep Both or Merge | Partial | Owner control is `CompressDetailView` → “Khi tên đã tồn tại”; per-run values are Keep Both, Ask, Merge (`CompressDetailView.swift:74–83,215–224`). There is no MFinder-named preference key; Replace is separately confirmed. Verify all format-specific safety before claiming parity. | XF-MFGAP-03 |
| System §3 L148–194 | Compression level and format selection | Partial | Per-run format/level controls exist; current formats are ZIP and TAR.GZ; no 7z/RAR (`CompressDetailView.swift:19–46,143–189`). Current engine uses macOS tools; no bundled `7zz` (`CompressDetailView.swift:5–6,228–234`; `ArchiveRunner.swift:4–15`). | XF-MFGAP-03 |
| System §4 L208 | `settings.aiSearch.semanticIndexingEnabled` | Missing | Closest owner is **Finder & Tìm kiếm → Tìm kiếm AI**; local query parsing/Spotlight exists, but semantic indexing/key does not (`SearchDetailViews.swift:350–425`; `FileSearchEngine.swift:1–40`). | XF-MFGAP-04 |
| System §4 L208 | `settings.aiSearch.automaticIndexing` | Missing | No automatic semantic-indexing control/key found on the AI search owner page (`SearchDetailViews.swift:350–425`). | XF-MFGAP-04 |
| System §4 L209 | `settings.aiSearch.indexDocuments` | Missing | No source-folder indexing toggle/key found (`SearchDetailViews.swift:350–425`). | XF-MFGAP-04 |
| System §4 L209 (“etc.”; inferred key name) | Desktop source-folder indexing toggle (proposed key: `settings.aiSearch.indexDesktop`) | Missing | No Desktop indexing toggle/key found (`SearchDetailViews.swift:350–425`). Key spelling is proposed, not recovered. | XF-MFGAP-04 |
| System §4 L209 (“etc.”; inferred key name) | Downloads source-folder indexing toggle (proposed key: `settings.aiSearch.indexDownloads`) | Missing | No Downloads indexing toggle/key found (`SearchDetailViews.swift:350–425`). Key spelling is proposed, not recovered. | XF-MFGAP-04 |
| System §4 L210 | `settings.aiSearch.includeImageOCR` | Missing | No image OCR indexing toggle/key found (`SearchDetailViews.swift:350–425`). | XF-MFGAP-04 |
| System §5 L259–265, L272–306 | Per-pair on-change/daily schedule | Partial | Pair UI exposes on-change/daily timing fields; no separate scheduler implementation or Finder Sync extension is established (`FolderSyncDetailView.swift:204–244`). | XF-MFGAP-05 |
| System §5 L288–290 | Sync conflict policy: newer/source/ask | Missing | No per-pair conflict-resolution selector matching those policies is evidenced; current source/destination model is one-way (`FolderSyncDetailView.swift:54–108,204–244`). | XF-MFGAP-05 |
| System §5 L263–264, L272–306 | Preserve tags/metadata and free-space safety | Partial | Current owner page does not expose a metadata-preservation summary or a “requires X” free-space preflight; exact copy semantics require review (`FolderSyncDetailView.swift:130–175,204–244`). | XF-MFGAP-05 |
| System §5 L262, L272–306 | Revalidate stale preview before sync | Missing | No preview/revalidation surface is available in the owner UI (`FolderSyncDetailView.swift:130–175,204–244`). | XF-MFGAP-05 |
| System §6 L314–372 | Capture format/output folder/countdown | Partial | PNG/JPG/HEIC, destination and delay/countdown are exposed by the capture owner page; additional requested modes/formats are audited separately below (`CaptureDetailView.swift:12–24,71–100`). | XF-MFGAP-06 |
| System §6 L328–372 | Configurable shortcuts and reserved system shortcut conflict | Partial | Capture links to shortcut controls; `⌘⇧3/4` remain macOS-owned unless the user resolves the conflict deliberately (`CaptureDetailView.swift:71–100`; `CaptureRules.swift:238–258`). | XF-MFGAP-06 |
| System §7 L404–432 | `settings.dropTray.shakeEnabled` | Partial | **NOTCH → Khay thả** owns the persisted shake trigger switch (`DropTrayDetailView.swift:18–23,176–195`; `NotchSurfaceController.swift:108–126`). | XF-MFGAP-07 |
| System §7 L404–432 | `settings.dropTray.shakeSensitivity` | Partial | Same owner offers low/medium/high sensitivity; the prompt's numeric acceleration threshold is not evidenced (`DropTrayDetailView.swift:18–23,176–195`). | XF-MFGAP-07 |
| System §7 L380–432 | Tray storage cap, sharing and cross-device settings | Partial | Local staging/actions exist. No configured capacity ceiling, account-based receive, MFinder Cloud/R2/Drive upload path or cross-device sync is evidenced. Optional sharing elsewhere is distinct from tray sync. | XF-MFGAP-07 |
| System §8 L447, L483–487 | Folder auto-lock timer | Missing | `CÔNG CỤ → Khóa thư mục` has lock/unlock actions but no inactivity timer or countdown (`FolderLockDetailView.swift:105–129,141–223`; `FolderLockController.swift:18–44`). | XF-MFGAP-08 |
| System §8 L443–444, L480–483 | Touch ID and per-device Keychain unlock preference | Missing | Password is entered to open the sparsebundle; no Touch ID-backed Keychain credential control is exposed (`FolderLockController.swift:53–81,115–169`). | XF-MFGAP-08 |
| System §8 L445–446, L474–475 | Refuse cloud-only files and symlinks | Partial | User chooses a folder, but no explicit cloud-only/symlink validation is evidenced in the vault controller (`FolderLockController.swift:53–81`). | XF-MFGAP-08 |
| System §9 L525–534 | Menu-bar sparkline metric selection | Missing | **CHUNG → Hệ thống** has metric views and an update interval, but no user-selectable CPU/network sparkline source (`SystemDetailView.swift:10–12,87–103`; `SystemMonitorManager.swift:78–80`). | XF-MFGAP-09 |
| System §9 L532–534 | 1-second metrics / 10-second battery cadence | Partial | XFinder exposes one global 1/2/5-second refresh choice; no separate battery cadence setting (`SystemDetailView.swift:10–12,87–103`). | XF-MFGAP-09 |
| System §9 L527, L534 | 60-second history window | Partial | `SystemMonitorManager` keeps 60 samples (`SystemMonitorManager.swift:104–105`); user cannot configure the requested history length. | XF-MFGAP-09 |
| System §9 L529 | Per-app network rates and 2-second refresh | Rejected | No supported per-process network counters were measured; do not add a control promising app-level rates. Existing roadmap documents this platform/sandbox limitation (`docs/MFINDER_XFINDER_ROADMAP.md`, System Monitor row). | Q-MFGAP-07 |
| System §10 L551–585 | Rename pattern settings: regex, date format, template, start/step and padding | Partial | **FINDER & TÌM KIẾM → Đổi tên hàng loạt** supports a limited in-session prefix/suffix/literal replacement/sequence/case form; no durable pattern controls or regex/date/template/step settings (`BatchRenameDetailView.swift:47–104`; `BatchRenameEngine.swift:8–32,41–87`). | XF-MFGAP-10 |
| System §11 L599–633 | Custom normalized zones, per-screen configuration and edge threshold | Partial | **CỬA SỔ → Vùng bắt dính** offers fixed layouts and margin settings, but no user-drawn zone editor (`WindowDetailViews.swift:224–237,580–633`; `SnapLayout.swift`). The 20pt prompt threshold is not assumed to match XFinder's configured behavior. | XF-MFGAP-11 |
| System §11 L599–633 | Keyboard movement and restore behavior | Partial | Hotkeys and restore/memory choices are available from the snap owner page; target-specific live behavior and custom zone adjacency remain to verify (`WindowDetailViews.swift:224–237,364–424`). | XF-MFGAP-11 |
| System §12 L650–682 | Cleaning-mode duration / automatic unlock timer | Partial | **Điều khiển nhanh → Lau bàn phím** has `cleaning.minutes` (1–5; default 2), not a fixed five-minute-only timer (`SystemControlsPanel.swift:36–37,247–256`; `CaffeineRules.swift:53–70`). | XF-MFGAP-12 |
| System §12 L650–682 | Click-to-unlock and safe escape | Partial | XFinder supports mouse unlock and ESC×5 within three seconds; prompt's “click only / five minutes” exact policy is not the current behavior (`CleaningModeController.swift:62–83,101–119`). | XF-MFGAP-12 |
| System §686–697 | Global privacy principles and per-feature disclosure controls | Partial | The system prompt describes privacy constraints, not a settings page. XFinder's local diagnostics and analytics opt-out are in `SettingsWindow.swift:9–15`; every provider, upload, Keychain item, and folder grant needs a feature-specific review in the rows below. | Per-feature tasks |

## Feature-by-feature requirement audit

Each row covers the full numbered behavior family in the cited part of the System Prompt; settings rows above enumerate the option/key requirements separately. “Partial” means code/UI covers only the listed portion. Source lines below are on baseline `9788415`; commit IDs identify the merged implementation history, not a live install.

### 1. Disk Storage Analyzer

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §1 L20–31, L44–81 items 1–6 | Pick one folder, scan off-main, build hierarchical tree, live progress, treemap+sunburst, drill-down/select/inspector | Partial | `StorageDetailView.swift:162–266` offers selected-folder scan, live count/path and top-50 file rows; `StorageScanEngine.swift:8–21,48–100` detached scan/cancellation/progress. No retained directory tree or charts. Main implementation history: `1c92dc5`, `74fb3c7`. | XF-MFGAP-01 |
| System §1 L44–81 item 7 | Move selected files to Trash directly from chart | Rejected | Current XF-T35 contract is review-only and explicitly has no deletion; see `StorageDetailView.swift:162–210` and `docs/specs/XF-T35-storage-analyzer-v01.md`. Destructive actions require a separately reviewed, revalidated workflow. | Q-MFGAP-01 |
| System §1 L44–81 item 8 and “What MFinder does” L25–30 | Capacity/used/free/purgeable, APFS shared-volume and clone warnings | Partial | Volume capacity and I/O are already shown separately by `StorageDetailView.swift:18–98`; the folder scan reports logical bytes (`:232–240`, `StorageScanRules.swift:2`). It does not associate purgeable/physical APFS usage with the chosen tree or show the requested clone/shared-volume warnings. | XF-MFGAP-01 |
| System §1 L60–63, §686 item 6 | Full-disk scan permission described as an “entitlement” | Rejected | XFinder's storage contract is a user-picked folder and explicitly says not to request Full Disk Access or add entitlements (`docs/MFINDER_XFINDER_ROADMAP.md:68–70,84`). Full Disk Access is a user privacy grant, not an entitlement that grants the access by itself. | Q-MFGAP-10 |
| System §1 L47–81 privacy and engineering | Local-only, user-picked scope, skip auto-visited network volumes/cloud-only, cancellable, cache results, APFS allocated size | Partial | User-picked folder, security-scoped access, symlink avoidance, cloud-only checks and cooperative cancellation exist (`StorageScanEngine.swift:27–60,77–104`); scan result is logical bytes and has no chart cache. Full-disk/FDA and physical allocated-size claims are absent. | XF-MFGAP-01 |
| System §1 L56–77 visual rules | Squarified rectangles, sunburst ring labels, color palette/label thresholds | Missing | No chart renderer or chart layout code in the storage owner page/engine above. | XF-MFGAP-01 |

### 2. Duplicate File Finder

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §2 L89–100, L106–140 items 1–5, 10–13 | Chosen-root traversal; size grouping; streaming exact hashing; local similar-image pHash; parallel/cancellable scaling | Missing | No dedicated Duplicate Finder page or engine in `SidebarDestination.swift:264–273` / `RootView.swift:78–170`; search in current `XFinder/Core` shows unrelated clipboard/file-browser deduplication only. | XF-MFGAP-02 |
| System §2 L106–140 items 6–9 | Exact/similar tabs, grouped results, original/copy markers, metadata/stats, explicit Trash action | Missing | No duplicate-result UI or duplicate-set model. | XF-MFGAP-02 |
| System §2 L89–140 privacy/UI | Local-only, skip inaccessible/cloud-only, explicit batch confirmation, re-hash before trash, progress/empty states | Missing | No feature surface to provide these protections. Must be part of the first implementation; never silently delete. | XF-MFGAP-02 |

### 3. Archive Manager

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §3 L148–160, L163–194 CREATE/EXTRACT | Select files, create/extract supported formats, progress and cancellation, destination/free-space checks | Partial | `CompressDetailView.swift:86–100,310–365,393–487`; `ArchiveRunner.swift:4–15,41–100,133–199`. ZIP and TAR.GZ paths exist; free-space estimate/uncompressed-size refusal and bundled 7z/rar are not established. | XF-MFGAP-03 |
| System §3 L163–194 conflict/merge and safety | Never silently overwrite, keep-both/merge, safe extraction and independent multi-archive behavior | Partial | Existing per-run conflict choices, protected staging and path/link safety are in `CompressDetailView.swift:215–224,393–487` and `ArchiveRunner.swift:79–199`; merge/keep-both semantics and every archive edge require source-level verification. Current product does not bundle 7zz. | XF-MFGAP-03 |
| System §3 L163–194 privacy/UI | Local processing, passwords not persisted, estimate savings, open destination/drag-drop, progress to UI | Partial | Current UI uses local system tools and exposes compression level/password only per run (`CompressDetailView.swift:143–189,228–238`). No estimated output-size/savings preview or drag-drop coverage established by this audit. | XF-MFGAP-03 |
| System §3 L183–194 proposal to bundle `7zz` | Include downloaded binary at `Contents/MacOS/7zz` | Rejected | XFinder's archive owner deliberately uses built-in macOS `ditto`, `zip`, `tar`; the prompt's bundle has licensing, provenance, notarization and update obligations without an approved supply-chain decision (`CompressDetailView.swift:5–6,228–234`; `docs/MFINDER_XFINDER_ROADMAP.md`, “Archive Manager”). | Q-MFGAP-02 |

### 4. Find in Files / AI-Powered Search

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §4 L202–249 items 1–3 | Name/content search, scopes, kind/date/size filters, metadata/icon/open/reveal | Partial | Spotlight-backed searches and filters exist in `SearchDetailViews.swift:76–109,350–425`; general File Browser has a separate query engine. Full indexed-content/snippet and every result metadata contract are not shown as one unified page. | XF-MFGAP-04 |
| System §4 L202–249 item 4 | Apple Intelligence semantic indexing/local embeddings, incremental FSEvents and index toggles | Missing | Current “AI” page documents local natural-language query parsing to Spotlight, not embeddings/vector indexing (`SearchDetailViews.swift:359–402`). No `settings.aiSearch.*` owner/settings or FSEvents semantic index found. | XF-MFGAP-04 |
| System §4 L232–249 privacy/UI | User-granted folder scope, local query, debounce/live results, search shortcut/contextual Search Here | Partial | Local Spotlight query path and browser “Mở thanh tìm” link exist (`SearchDetailViews.swift:363–372`); shortcut catalogue owns global search entries. Semantic indexing privacy contract and full-text index controls are absent. | XF-MFGAP-04 |
| System §4 L218–243 suggestion “natural-language predicates” | Treat the private/unspecified semantic query API as guaranteed | Rejected | No confirmed public API or local embedding engine found in the XFinder baseline. The supported behavior is local parsing plus Spotlight; do not label it semantic AI retrieval. | Q-MFGAP-03 |

### 5. Folder Sync

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §5 L257–270 / L272–306 items 1–2 | Multiple pairs, one-way backup and safe two-way mirror/conflict resolution | Partial | Pair list and one-way source→destination model are reachable (`FolderSyncDetailView.swift:54–108,130–175`); optional mirror deletes extras. No two-way reconciliation or three-way conflict flow established. | XF-MFGAP-05 |
| System §5 L272–306 items 3–6, 8 | Preview exact copy/update/delete; stale preview; free space; tags/metadata; summary; SMB | Partial | Pair detail supports sources/destinations, last result, daily/on-change and deletion toggle (`FolderSyncDetailView.swift:130–175,204–244`). No preflight change preview or SMB setup in this owner UI; preserve-metadata behavior not demonstrated here. | XF-MFGAP-05 |
| System §5 L257–270 / L272–306 items 7 and extension | Schedule + Finder Sync badges/XPC | Partial | Per-pair scheduled and “on change” options exist; Finder Sync extension/badges are not evidenced by this feature owner. | XF-MFGAP-05 |
| System §5 L272–306 privacy | No cloud; bookmarks and local-to-SMB only | Partial | Sync is a local rsync-style operation and user-selected folders, but cloud/SMB scope is not fully specified as a complete contract. Data deletion policy needs explicit review. | XF-MFGAP-05 |

### 6. Screenshot + Screen OCR

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §6 L314–372 capture modes 1 and permissions | Full screen, region, window; screen capture permission; capture overlay/restore | Partial | Modes include region/window/fullscreen; capture goes through macOS `screencapture` and ScreenCaptureKit paths (`CaptureRules.swift:14–39,284–312`; `CaptureController.swift:122–138`). The prompt's `CGWindowListCreateImage` path is unavailable on macOS 27 and is rejected; use current ScreenCaptureKit route. | XF-MFGAP-06 |
| System §6 L314–372 editor/annotation/save | Annotation tools, undo/redo, PNG/JPEG, destination/copy/clipboard, metadata | Partial | Capture editor and several tools/exports exist; `AnnotateWindow.swift` and capture surfaces own details. The complete requested tool list/format and metadata contract is not asserted by the limited capture preferences alone. | XF-MFGAP-06 |
| System §6 L314–372 scrolling + OCR | Scroll and stitch, local Vision OCR with box copy | Partial | Scrolling capture and Vision OCR are represented in `CaptureRules.swift:14–39`, `ScrollCaptureController.swift`, `ScrollStitch.swift`, `OCRText.swift`, and capture UI. Need measure the exact alignment/latency/no-content recovery paths before Done. | XF-MFGAP-06 |
| System §6 L314–372 privacy/UI | User-confirmed cloud upload, configurable shortcuts, preview, cancel, fast editor opening | Partial | Capture has configurable shortcut controls and explicit shortcut conflict checks (`CaptureDetailView.swift:71–100`; `CaptureRules.swift:238–278`). Default keeps macOS ⌘⇧3/4/5. No MFinder cloud upload is assumed. | XF-MFGAP-06 |
| System §6 L340–353 “intercept ⌘⇧3/⌘⇧4 globally” | Take over macOS screenshot shortcuts silently/by default | Rejected | XFinder explicitly lists those shortcuts as still owned by macOS and conflict-detects them (`CaptureDetailView.swift:71–96`; `CaptureRules.swift:248–258`). Deliberate user reassignment is required; no default interception. | Q-MFGAP-04 |

### 7. Drop Tray

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §7 L380–432 items 1–2, 4–5 | Floating tray, drag/file/text/image acceptance, shake trigger, thumbnails | Partial | Local notch/file tray exists; shake setting and controller are visible (`DropTrayDetailView.swift:146–195`; `NotchSurfaceController.swift:108–126`). MFinder-style standalone always-on-top staging panel and full tray payload support are not asserted for every item type. | XF-MFGAP-07 |
| System §7 L380–432 item 3 | Drag out/copy/path/clear; optional explicit upload | Partial | Tray provides batch move/copy/zip/open/trash/clear actions (`DropTrayDetailView.swift:146–160,233–318`). A tray-specific upload flow is not established. | XF-MFGAP-07 |
| System §7 L380–432 item 6 and UI | 500 MB cap/warning, selectable grid/list, menu badge, stored state | Partial | Local tray state persists and has detail view; no 500 MB storage cap or warning represented (`DropTrayDetailView.swift:18–23,326–390`). | XF-MFGAP-07 |
| System §7 L404–432 privacy/engineering | No auto-upload; keep local; threshold tuned to cursor acceleration | Partial | Shake enable/sensitivity is user-controlled; no evidence that the exact 2000 pt/s² threshold is used. No cross-device tray account is implemented in this owner. | XF-MFGAP-07 |
| System §7 L390–432 MFinder cloud/R2/Drive integrations | Treat provider links as configured and available | Rejected | XFinder has no MFinder vendor account/credential/infrastructure; preserve local tray and expose only separately configured, user-initiated providers. | Q-MFGAP-05 |

### 8. Secure Lock

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §8 L440–488 items 1–3 | Password-encrypted container, AES-GCM/password KDF/custom format, browse/unlock/edit/relock | Partial | XFinder creates AES-256 encrypted sparsebundle with `hdiutil`; it does not implement the prompt's custom AES-GCM/KDF file format (`FolderLockController.swift:4–17,53–81,117–169`). Mounted image opens in Finder; edits persist through the image mechanism. | XF-MFGAP-08 |
| System §8 L440–488 items 4–5 | Auto-lock timeout and Touch ID derived-key Keychain | Missing | No auto-lock manager/timer or Touch ID credential flow in `FolderLockController.swift:18–44,115–169`; user enters password when opening. | XF-MFGAP-08 |
| System §8 L440–488 security/privacy rules | Secure memory zeroing, never log inner paths, refuse cloud-only/symlinks, per-device credentials | Partial | Password enters `hdiutil` via stdin; no saved password in vault metadata (`FolderLockController.swift:71–81,173–208`). Explicit cloud-only/symlink validation and secure zeroization are not evidenced. | XF-MFGAP-08 |
| System §8 L440–488 UI | Strength/confirmation fields, Touch ID fallback, visible lock/countdown, password failure states | Partial | Create/unlock forms, password confirmation, explicit no-recovery warning and lock/unlock controls exist (`FolderLockDetailView.swift:105–129,141–223`). Strength meter, Touch ID, and countdown do not. | XF-MFGAP-08 |
| System §8 L459–483 “securely overwrite temp plaintext” | Claim secure deletion of blocks on APFS/SSD | Rejected | The MFinder prompt suggests overwrite-then-delete as a guarantee; XFinder must not promise secure overwrite on APFS/SSD. Current design uses an encrypted sparsebundle rather than a plaintext temp mirror. | Q-MFGAP-06 |

### 9. System Monitor

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §9 L496–535 items 1–5 | CPU, memory, disk I/O, network, battery health/temperature | Partial | CPU/memory/network/battery/disk/thermal metrics are owned by `SystemMonitorManager`, `DiskManager`, `PowerManager`, `ThermalReader` (`SystemMonitorManager.swift:120–150,155–189,308–410`; `DiskManager.swift`). Some values unavailable on certain hardware are intentionally blank; per-disk and detailed battery health/temperature parity is incomplete. | XF-MFGAP-09 |
| System §9 L496–535 item 6 | Apps ranked by energy/network | Partial | CPU/system readings exist; per-process network byte counters and top apps are not established. `docs/MFINDER_XFINDER_ROADMAP.md` records this as unknown. | XF-MFGAP-09 |
| System §9 L496–535 refresh/history/menu bar | 1s overall, 10s battery, 60-point histories, sparkline picker and popover | Partial | Configurable 1/2/5s system cadence and 60 samples exist (`SystemDetailView.swift:87–103`; `SystemMonitorManager.swift:78–80,104–105`). No separate battery interval or metric-picker menu bar sparkline control shown in the owner page. | XF-MFGAP-09 |
| System §9 L510–535 privacy/engineering | Local system calls, no network, background actor, memory history | Partial | Metrics are gathered locally and update only while pages need them (`SystemMonitorManager.swift:45–47,68–80`). No actor wrapping every reader and no per-app network capability is claimed. | XF-MFGAP-09 |
| System §9 L515–531 per-process network API assumptions | Promise per-app network accounting in a sandbox | Rejected | Existing evidence says per-app network accounting needs elevated access or may not be available. Do not display invented per-app rates (`docs/MFINDER_XFINDER_ROADMAP.md`, System Monitor row). | Q-MFGAP-07 |

### 10. Batch Rename

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §10 L543–585 items 1–2 | Select multiple files; prefix/suffix, find/replace, number, dates, case, template/regex | Partial | UI supports file selection, prefix/suffix, literal replace, numbering and case (`BatchRenameDetailView.swift:29–104`; `BatchRenameEngine.swift:8–32`). Regex/date/template/step option are missing. | XF-MFGAP-10 |
| System §10 L543–585 items 3–6 | Live before/after preview, collisions block, atomic rename, undo | Partial | Preview, collision detection, safe subset execution and ActionHistory undo exist (`BatchRenameDetailView.swift:15–21,107–179`; `BatchRenameEngine.swift:41–87`). Multi-file all-or-nothing atomicity is not provided; execution can partially fail. | XF-MFGAP-10 |
| System §10 L543–585 privacy/UI/engineering | Filenames only, no network, explicit apply, keyboard commit/cancel, hidden/extensions/reserved names | Partial | No shell or file-content reads in engine; UI previews before apply. Exact Return/Escape and reserved-name edge handling need verification. Sequence digits have explicit 1–5 range and start 0–9999 (`BatchRenameDetailView.swift:83–94`). | XF-MFGAP-10 |

### 11. Window Snapping / Tiling

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §11 L593–633 items 1–4, 6–8 | AX permission, edge/zone snap, half/quarter/third/focus, keyboard, restore, multi-display | Partial | Snap controls/layouts, global hotkeys, restore/memory, multiple screens and accessibility entry are present (`WindowDetailViews.swift:224–237,272–424,580–691`; `SnapZoneController.swift`; `SnapMemory.swift`). Live drag/movement/restore remains a hand-test gate; no user-drawn custom zones. | XF-MFGAP-11 |
| System §11 L593–633 item 5 | Semi-transparent target-zone preview | Partial | `WindowDetailViews.swift:272–343` exposes preview and drag layout; `SnapZoneController.swift` owns snap operation. Live target-window behavior remains unverified by this Builder. | XF-MFGAP-11 |
| System §11 L593–633 privacy/engineering | AX frame-only interaction, normalized custom zones, global mouse drag monitor | Partial | AX window frame control and stored snap preferences exist; custom normalized zone editor and exact global drag monitor contract are not established. | XF-MFGAP-11 |
| System §11 L593–633 suggested `CGWindowListCopyWindowInfo` | Use CGWindowList APIs as the snapshot/capture implementation | Rejected | `CGWindowListCreateImage` becomes unavailable on macOS 27; image preview uses ScreenCaptureKit (`docs/CLAUDE_HISTORY_2026-10-18.md:497`). AX remains the window-frame API; do not conflate frame inspection with screenshot capture. | Q-MFGAP-08 |

### 12. Keyboard Clean Mode

| Spec ref | Requirement family | Status | Evidence | Next task |
|---|---|---|---|---|
| System §12 L641–682 behavior/UI | Temporarily block keyboard only; mouse exit; full-screen visible countdown; auto-unlock | Partial | Event tap, overlay, countdown and mouse/ESC escape exist (`CleaningModeController.swift:25–59,62–83,85–119`). XFinder uses ESC five presses within 3 seconds, not the MFinder prompt's click-only/5-minute-only behavior. Timeout is configurable 1–5 minutes, default 2. | XF-MFGAP-12 |
| System §12 L641–682 permissions/safety | Accessibility, Secure Input refusal, preserve power/Touch ID, release on tap failure | Partial | Accessibility required and tap is disabled on `stop()` (`CleaningModeController.swift:25–46,62–83`). No Secure Input check or Touch ID/power-button-specific test is visible in source. | XF-MFGAP-12 |
| System §12 L656–682 proposed `Input Monitoring entitlement` / CGEvent tap | Add entitlement or use CGEventTap based only on prompt text | Rejected | The requested blanket entitlement is not supported by the measured implementation contract: XFinder currently creates a session event tap gated by Accessibility trust (`CleaningModeController.swift:25–46`). Do not change entitlements from this prompt; Secure Input behavior still needs a focused review. | Q-MFGAP-09 |

## Cross-feature privacy requirements

| Spec ref | Requirement | Status | XFinder evidence / limitation | Next task |
|---|---|---|---|---|
| System §686–697 item 1 | No analytics/crash submission without explicit opt-in | Partial | SettingsWindow exposes `analytics.optOut`; diagnostics local logging is separate (`XFinder/Views/SettingsWindow.swift:9–15`). Need trace the effective analytics default/submission path before marking complete. | XF-MFGAP-13 |
| System §686–697 items 2–3 | Never transmit file data without action; all AI/ML on-device | Partial | OCR/search/storage scan local paths exist; optional remote services and translation/quick-share integrations mean no blanket whole-app claim. Per-feature rows delimit what was inspected. | XF-MFGAP-13 |
| System §686–697 items 4–5 | API keys in Keychain; explain permissions first | Partial | Voice API key uses Keychain; permission hub has context and recovery rows, but all integration credentials/feature flows require an owner-by-owner audit (`FeatureHub.swift`, `VoiceKeychain.swift`). | XF-MFGAP-13 |
| System §686–697 items 6–7 | Security-scoped bookmarks for persistent access; zero sensitive memory | Partial | User-picked scan scopes access for the scan run (`StorageScanEngine.swift:27–31`); folder sync and other persistent scopes vary. No claim of process-wide secure zeroization. | XF-MFGAP-13 |

## Plan

No pages or controls are moved in this audit. Each implementation task must get its own `docs/specs/XF-MFGAP-*.md` before coding. Tasks are ordered by user-visible gaps and safety dependencies; **settings/options are audited first inside each feature**, but a setting is not added without the feature that gives it meaning.

| Order / task | User outcome (“Người dùng vào đây để…”) | Scope / likely owners | Risk | Page-move question |
|---|---|---|---|---|
| 1. `XF-MFGAP-01` Storage chart & options | Người dùng vào Hệ thống → Ổ đĩa để chọn thư mục, xem treemap/sunburst và chọn kiểu/độ chia biểu đồ đã lưu. | `StorageDetailView.swift`, `Core/Storage/*`, `XFinderLogicTests` symlinks; add `storage.chartStyle` / `storage.chartFraction` only with working chart UI. | Medium: large trees, hard links/APFS, labels/selection. No Trash action in first task. | None; keep on current Storage page. |
| 2. `XF-MFGAP-02` Duplicate Finder | Người dùng vào Công cụ để tìm nhóm file trùng, xác minh lại rồi chuyển bản đã chọn vào Thùng rác. | New duplicate engine/view and route; stream hashing, cancellation, exact duplicates first. | High: destructive file actions and large scans. | **Q-MFGAP-PAGES:** owner approval required before adding/merging sidebar rows; proposed route is a new item under `CÔNG CỤ`. |
| 3. `XF-MFGAP-03` Archive parity/safety | Người dùng vào Nén & Giải nén để chọn đích, xử lý xung đột và biết rõ kết quả trước khi giải nén. | `CompressDetailView.swift`, `ArchiveEngine.swift`, `ArchiveRunner.swift`; persist only after owner confirms desired defaults. | High: overwrite, traversal, archive bombs, free space. No bundled 7zz. | None; retain existing archive page. |
| 4. `XF-MFGAP-04` Search settings & scope | Người dùng vào Tìm kiếm để chọn phạm vi/loại/ngày và hiểu chính xác tìm kiếm local hỗ trợ gì. | `SearchDetailViews.swift`, `FileSearchEngine.swift`, `SearchQuery.swift`. First deliver scoped Spotlight settings; semantic embeddings remain separately gated. | Medium: privacy, folder access and misleading “AI” claims. | None; keep Finder & Search group. |
| 5. `XF-MFGAP-05` Folder Sync preview | Người dùng vào Đồng bộ để xem trước thay đổi, phát hiện nguồn/đích đổi trước khi chạy và kiểm soát xoá. | `FolderSyncController.swift`, pair model/store, `FolderSyncDetailView.swift`. | High: permanent deletion and stale preview. | None; retain current Sync page. |
| 6. `XF-MFGAP-06` Capture/OCR review | Người dùng vào Chụp & chú thích để chọn định dạng/phím, chụp/OCR và hiểu quyền/cancel/error. | `CaptureController.swift`, `CaptureRules.swift`, capture views. Keep ⌘⇧3/4 conflict policy. | Medium: screen recording permission, shortcut conflicts, privacy. | None. |
| 7. `XF-MFGAP-07` Drop Tray capacity | Người dùng vào Khay thả để biết nội dung đang lưu, giới hạn lưu trữ và chủ động dọn/chia sẻ. | `DropTrayDetailView.swift`, `NotchSurfaceController.swift`, tray store. | Medium: storage pressure; avoid auto-upload. | None. |
| 8. `XF-MFGAP-08` Folder vault hardening | Người dùng vào Khóa thư mục để đặt chính sách khóa tự động và biết rõ cách khôi phục dữ liệu. | `FolderLockController.swift`, `FolderLockDetailView.swift`; only after threat-model/security review. | Critical: credential lifecycle, plaintext exposure, data loss. | None. |
| 9. `XF-MFGAP-09` Monitor settings/coverage | Người dùng vào Hệ thống để chọn nhịp cập nhật và đọc được giá trị/giới hạn phần cứng. | `SystemMonitorManager.swift`, monitor detail views. No per-app network claims without measured support. | Medium: energy use and unavailable sensor readings. | None. |
| 10. `XF-MFGAP-10` Batch Rename gaps | Người dùng vào Đổi tên hàng loạt để tạo mẫu an toàn, xem trước xung đột và hoàn tác rõ ràng. | `BatchRenameEngine.swift`, `BatchRenameDetailView.swift`, `ActionHistoryStore`. | High: partial rename/data names; explicit rollback semantics. | None. |
| 11. `XF-MFGAP-11` Snap custom layouts | Người dùng vào Vùng bắt dính để tạo/điều chỉnh zone cá nhân và phục hồi cửa sổ. | `SnapLayout.swift`, `SnapZoneController.swift`, `WindowDetailViews.swift`. | High: Accessibility and multi-display geometry; live test required. | None. |
| 12. `XF-MFGAP-12` Cleaning Mode secure-input | Người dùng vào Điều khiển nhanh để đặt thời lượng lau và không bị khóa phím trong ô mật khẩu. | `CleaningModeController.swift`, `CaffeineRules.swift`, system controls. | High: input suppression; safe escape must always work. | None. |
| 13. Cross-feature privacy review | Privacy requirements are handled in each feature's owner page and captured in the cross-feature table; the MFinder source spec does not define a separate Settings feature. | Feature owners cited in the cross-feature table. | High: privacy/security scope. | No page move proposed. |

### Page/control move list requiring owner approval (no change made)

This MFinder gap audit proposes **no** page or control moves: MFinder's settings are options attached to its twelve feature requirements, not a separate Settings feature. XFinder's current owner page for each option is documented in the crosswalk and companion inventory.

Separate pending request from the owner (“gộp cái browser settings này vào 1 trang của XFinder Settings”): **Q-MFGAP-PAGES** proposes moving the nine categories currently hosted inside File Browser (`Chung`, `Giao diện`, `Sidebar`, `Đám mây`, `Nâng cao`, `Bàn phím`, `Ngăn thông tin`, `Tìm kiếm`, `Quyền riêng tư`; `BrowserSettingsWindow.swift:12–42`) to one “File Browser” page in the existing XFinder Settings window; the Browser gear/entry opens that page. Keep all controls, key names, defaults and behavior unchanged; do not combine these settings with other feature controls. Before implementation, the owner must approve this exact destination/list. No move is made by this audit.

## Decisions / unverified

- The OneNotch-derived 28-group product spec is a separate reference and is not mixed into this 12-feature MFinder audit.
- `docs/reference/MFINDER_PROMPT_TEACHING.md` supplies engineering education, not product requirements.
- The installed XFinder app was not launched by this Builder. All statuses above are source/UI reachability only; permission dialogs, screen capture, actual file I/O, VoiceOver, visual layout, multi-display behavior, and the configured providers remain live verification work for the owner/Boss.
- **Implementation checkpoint:** current `StorageScanResult` has aggregate counts and `largestFiles`, not a retained directory hierarchy. `XF-MFGAP-01-storage-charts.md` says to stop in this case. This audit records the gap and proposed storage task, but chart code is paused until the spec confirms that retaining a tree in the scan engine is in scope.
- **Open scope Q-MFGAP-11:** confirm a revised/approved spec for retaining the scan hierarchy (node identity, parent/children, size semantics and memory bounds) so `storage.chartStyle` / `storage.chartFraction` can be implemented with real charts. The current chart spec's explicit stop condition prevents this Builder from coding that expansion.

## Coverage summary

| Feature group | Options crosswalk rows | Functional audit rows | Current status profile | Live validation |
|---|---:|---:|---|---|
| 1. Storage Analyzer | 5 | 6 | Partial / Missing / Rejected | Not performed |
| 2. Duplicate Finder | 1 | 3 | Missing | Not performed |
| 3. Archive Manager | 4 | 4 | Partial / Rejected | Not performed |
| 4. File Search | 6 | 4 | Partial / Missing / Rejected | Not performed |
| 5. Folder Sync | 4 | 4 | Partial / Missing | Not performed |
| 6. Screenshot/OCR | 2 | 5 | Partial / Rejected | Not performed |
| 7. Drop Tray | 3 | 5 | Partial / Rejected | Not performed |
| 8. Secure Lock | 3 | 5 | Partial / Missing / Rejected | Not performed |
| 9. System Monitor | 4 | 5 | Partial / Rejected | Not performed |
| 10. Batch Rename | 1 | 3 | Partial | Not performed |
| 11. Window Snapping | 2 | 4 | Partial / Rejected | Not performed |
| 12. Keyboard Clean Mode | 2 | 3 | Partial / Rejected | Not performed |
| Global privacy rules | 1 | 4 | Partial | Not performed |

## Boss review (2026-11-07)

- Accepted as the working gap list (source/UI reachability only; 0 rows live-verified).
- **Correction — "Move to Trash from chart" is Missing (deferred), not Rejected:** it is a later task after charts and revalidation
  exist, not a platform impossibility. Same item appears twice (Full-disk-scan rows) — read them as one.
- **Confirmed by Boss:** Cleaning Mode has **no** Secure Input check in source (grep `SecureEventInput` = 0), so XF-MFGAP-12 is a
  real gap; the roadmap sentence "preserve the secure-input refusal" was wrong. Folder lock is an AES-256 sparse bundle via `hdiutil`.
- **Q-MFGAP-11 resolved:** bounded hierarchy retention is in scope — see the Boss decision in `docs/specs/XF-MFGAP-01-storage-charts.md`.

