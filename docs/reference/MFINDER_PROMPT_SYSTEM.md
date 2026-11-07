# MFinder — Master System Prompt for Claude

> **Purpose:** Paste any section below as a system prompt when asking Claude to add a specific MFinder feature to your own macOS app. Each section is self-contained. Evidence is from the real binary, strings, and source-file names inside MFinder 2.2.134.

---

## HOW TO USE THIS FILE

1. Find the feature you want below.
2. Copy that section's **System Prompt** block.
3. Paste it into Claude's system prompt (or prepend it to your message).
4. Then describe your own app and ask Claude to add the feature.

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 1 — DISK STORAGE ANALYZER (Analyze Storage)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- User picks a folder or volume; the app walks the entire file tree in a background thread.
- Progress is shown live: "Scanning N items" counter + current path.
- After the scan, results display in two chart styles the user can toggle:
  - **Treemap** — nested rectangles, area ∝ file size, deepest visible folders shown as subdivided tiles.
  - **Sunburst** — concentric rings centered on the chosen folder; each ring is one directory depth level; arc angle ∝ size.
- A side inspector panel shows a flat sorted list of the largest files/folders with human-readable sizes (GB / MB / KB).
- One-click "Move to Trash" cleans up items directly from the chart.
- APFS awareness: a note warns that "APFS volumes share storage. Used space includes other volumes in the same container."
- Purgeable space is explicitly included in available storage calculations.

### Source files in MFinder (confirmed from binary)
`StorageWorkspaceChart.swift` · `StorageWorkspaceModel.swift` · `StorageWorkspaceView.swift` · `StorageWorkspaceInspector.swift` · `StorageScanProgressView.swift` · `StorageFileTable.swift` · `StorageWorkspaceWindowController.swift`

### Setting keys (from binary strings)
`storage.chartStyle` → values: `"treemap"` or `"sunburst"`
`storage.chartFraction` → fraction of the window the chart takes vs. inspector
`storage.scan.progress` · `storage.scan.percentage`

---

### 📋 SYSTEM PROMPT — Disk Storage Analyzer

```
You are helping me add a Disk Storage Analyzer feature to my macOS app.

WHAT THE FEATURE DOES:
1. The user picks a folder or volume via an open panel.
2. A background thread (never block the main thread) walks the directory tree with FileManager or NSDirectoryEnumerator, collecting every file's path and byte size (using URLResourceKey.fileSizeKey and .totalFileSizeKey for directories).
3. Build an in-memory tree: each node has { name, url, size, isDirectory, children: [Node] }. After the walk, compute subtree sums bottom-up.
4. Show a live progress indicator while scanning ("Scanning N items...").
5. Once done, display results in TWO chart styles the user can switch between:
   a. TREEMAP: squarified layout — partition the available rect proportionally by size. Each rectangle shows the item name and size. Hover highlights. Click drills down.
   b. SUNBURST: concentric arcs. Center = root. Each ring = one depth level. Arc length ∝ subtree size. Click an arc to re-root there.
6. A sidebar list shows the top-N largest items (flat, sorted descending) with name, path, and size. Clicking an item highlights it in the chart.
7. Items can be moved to Trash directly from the results (use NSWorkspace.shared.recycle).
8. Show disk capacity, used, free, and purgeable space at the top (use URLResourceKey on the volume: .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityForOpportunisticUsageKey).

PRIVACY / PERMISSIONS:
- No special entitlement needed for user-picked folders when opened with NSOpenPanel (sandbox-safe).
- For scanning the full disk, the app needs the "Files and Folders" or "Full Disk Access" entitlement.
- Never scan network volumes automatically — check URLResourceKey.isVolumeKey and skip remote mounts unless the user explicitly chose them.
- No data leaves the device. No network calls.

UI/UX RULES:
- Scan runs in a Task (Swift Concurrency) or DispatchQueue.global(); never block the main actor.
- Show a cancel button during the scan.
- The treemap and sunburst must be drawn with Canvas/CoreGraphics or SwiftUI Canvas, not UIKit tables.
- Color palette: 10 distinct hues, cycling per top-level directory; children use lighter tints of the parent hue.
- Minimum rect to draw a label: 60 × 30 pt.
- Minimum arc to draw a label: arc-length > 50 pt, ring thickness > 14 pt.
- If a file/folder was cloud-only (not downloaded), show it greyed out and skip its size from totals — check URLResourceKey.ubiquitousItemIsDownloadedKey.

ENGINEERING CONSTRAINTS:
- Use Swift with SwiftUI + AppKit where needed.
- The scan must be cancellable: use a Task with cooperative cancellation checks every 500 items.
- Cache scanned results so switching between treemap/sunburst doesn't re-scan.
- Support APFS: note that clones share physical blocks — show a warning "APFS clones or compressed files may share physical storage; allocated sizes may exceed actual disk usage."

Please implement this feature for my app. Ask me to clarify my app's structure before writing code.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 2 — DUPLICATE FILE FINDER
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- Scans a chosen folder for two types of duplicates:
  - **Exact duplicates**: files with identical byte-for-byte content (confirmed by checksum — "Verify unchanged files by checksum" string in binary).
  - **Similar images**: visually similar photos (uses local ML; no network). String: "Exact files and visually similar images, scanned locally."
- Results grouped by duplicate set; each set shows all copies with their paths.
- User selects which copies to delete; MFinder moves them to Trash (never permanent delete).
- Progress: "Scanning N files", "Moving duplicates to Trash".
- Empty-state messages: "No Exact Duplicates", "No Similar Images".

### Source files
`DuplicateFinderView.swift` · `DuplicateFinderWindowController.swift`

---

### 📋 SYSTEM PROMPT — Duplicate File Finder

```
You are helping me add a Duplicate File Finder feature to my macOS app.

WHAT THE FEATURE DOES:
1. User picks a root folder via NSOpenPanel (or passes the current open folder).
2. A background scan walks all files recursively (skip symlinks, app bundles .app, system files).
3. PHASE 1 — group by file size. Files with unique sizes are immediately not duplicates.
4. PHASE 2 — for files sharing a size, compute SHA-256 (or xxHash for speed) of their full content. Files with identical hashes are exact duplicates.
5. PHASE 3 (images only) — for image files (jpg, png, heic, webp, gif, tiff), compute a perceptual hash (pHash or dHash, 64-bit). Pairs with Hamming distance ≤ 10 are "visually similar."
6. Display results in two tabs: "Exact Duplicates" and "Similar Images."
7. Each duplicate group shows: thumbnail (for images), file name, folder path, size, date modified. One item is marked "original" (oldest or in the shallowest path), others marked "copy."
8. User checks the copies to delete; "Move to Trash" calls NSWorkspace.shared.recycle on selected URLs.
9. Show overall stats: "N identical files found", "N similar images found", "X MB reclaimable."

PRIVACY:
- 100% local. No hashes, file contents, or paths leave the device.
- No network calls whatsoever.
- Skip files the user doesn't have read permission on (catch errors silently and count as "skipped").
- Skip cloud-only files (not downloaded to disk).

UI/UX RULES:
- Progress: show current phase ("Grouping by size…", "Computing checksums…", "Comparing images…") with a count.
- Cancellable at any time.
- Thumbnails generated with QLThumbnailGenerator or NSImage(contentsOf:).
- Never auto-delete. Always require explicit user confirmation per batch.
- Show a checksum verification step after the scan finishes: re-read selected files before moving to Trash to confirm they haven't changed since the scan. If changed, show a warning and skip that file.
- Group by duplicate set, not by individual file. Within a group, default-select all but the "original."

ENGINEERING CONSTRAINTS:
- Use Swift Concurrency (async/await + TaskGroup) for parallel hashing across CPU cores.
- Chunk large files for hashing: read in 1 MB blocks, update the hash incrementally. Never load an entire large file into RAM.
- For pHash of images, resize to 32×32 greyscale with vImage, then compute DCT-based hash.
- Store results in a struct: DuplicateGroup { id: UUID, files: [FileInfo], totalWastedBytes: Int64 }.
- Target: handle 500 000 files without freezing the UI.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 3 — ARCHIVE MANAGER (Create & Extract ZIP / 7z)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- Integrates a **bundled 7-Zip engine** (`7zz` binary inside MacOS/). No separate app needed.
- Compression via Finder right-click → "MFinder Actions" extension, or from the app's Archives pane.
- Extraction: "Source ZIP files remain unchanged. Duplicate file names use Finder-style numbered copies."
- Free space check before extraction: "Free space is below the combined ZIP size."
- Multiple ZIPs extracted independently then merged: "Each ZIP is extracted independently, then safely combined into one folder."
- Settings: `newFolderNextToArchive`, `sameFolder` — where to place extracted content.
- Conflict resolution: Keep Both or Merge.

### Source files
`ArchivesPane.swift` · `ArchiveSession.swift` · `ArchiveSessionView.swift` · `ArchiveOperationsController.swift`

---

### 📋 SYSTEM PROMPT — Archive Manager

```
You are helping me add archive (ZIP/7z) creation and extraction to my macOS app.

WHAT THE FEATURE DOES:
1. CREATE: User selects files/folders in my app; they can compress them to ZIP or 7z. Show compression-level options (Fastest / Normal / Best).
2. EXTRACT: User drops or opens an archive (.zip, .7z, .tar.gz, .rar); the app extracts it to a user-chosen or default destination.
3. Progress: show file count, current file name, bytes processed / total bytes.
4. Free-space check before extraction: compare uncompressed size against available disk space; warn if insufficient.
5. Conflict resolution: if the destination already has a file with the same name, offer "Keep Both" (rename the new copy "file 2.ext") or "Merge" (combine folders, rename conflicting files).
6. The extracted folder opens in Finder after success.
7. Never overwrite existing files silently.

APPROACH:
- For ZIP: use libarchive (available via SPM package) or the macOS Foundation ZIPFoundation library for Swift.
- For 7z: bundle the open-source `7zz` command-line binary (from 7-zip.org, arm64+x86_64 universal) in your app bundle at Contents/MacOS/7zz, then call it via Process(). Confirm it's available with FileManager.fileExists.
- Run all archive I/O on a background thread / async context.
- Send progress updates via AsyncStream or Combine publisher on the main thread.

PRIVACY:
- Files are never uploaded. All processing is local.
- Do not read file contents for any purpose other than compression/decompression.
- Encrypted archives: for password-protected ZIPs, use AES-256. Never store the password beyond the operation. Offer Touch ID / Keychain for repeat access.

UI/UX:
- Show estimated output size before compressing.
- Show "X% smaller" label after compression (compare input size to output size).
- Extraction destination picker defaults to "Same folder as archive" with an option for "New folder next to archive."
- After extraction, animate the destination folder appearing in Finder.
- Support drag-and-drop of archives onto the app window.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 4 — FIND IN FILES / AI-POWERED FILE SEARCH
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

Two modes (from binary strings + `AISearchPane.swift`, `SearchPane.swift`):

1. **Standard search** ("Search Here…" in Finder right-click): keyword search over file names and indexed content.
2. **AI / Natural-language search**: requires Apple Intelligence enabled on the device.
   - Semantic indexing: `settings.aiSearch.semanticIndexingEnabled`, `settings.aiSearch.automaticIndexing`.
   - Indexes: Documents, Desktop, Downloads separately (`settings.aiSearch.indexDocuments` etc.).
   - Image OCR: `settings.aiSearch.includeImageOCR`.
   - Query example: `"pdf files from last week"` → parsed to `kinds:[pdf], dateField:modified, dateRange:lastWeek`.
   - Semantic indexing is local: "Processing and indexes stay on your Mac."

---

### 📋 SYSTEM PROMPT — File Search

```
You are helping me add a file search feature to my macOS app.

WHAT THE FEATURE DOES:
1. BASIC SEARCH: User types a query; results show matching file names and snippets of content, filtered by folder scope.
   - Use NSMetadataQuery with NSMetadataQueryLocalComputerScope for system-index search (Spotlight).
   - Set predicates: NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query) for name search.
   - Add kMDItemTextContent CONTAINS[cd] for content search (requires Spotlight indexing).
2. FILTERS: file type (kind), date modified range, size range, folder scope.
3. RESULTS: show file name, folder path, date modified, size, file icon (use NSWorkspace.shared.icon(forFile:)).
   - Double-click reveals in Finder: NSWorkspace.shared.activateFileViewerSelecting([url]).
4. ADVANCED / AI SEARCH (macOS 15+ with Apple Intelligence):
   - Use NSMetadataQuery with natural-language predicates if available.
   - Parse user query locally for date ranges ("last week" = 7 days ago to now), file types ("pdf"), keywords.
   - Offer semantic search with CoreML embeddings of file content (index on first launch, update incrementally via FSEvents).
   - Show "Index file contents for semantic search" toggle. Indexing runs in a low-priority background task.
   - Respect user's privacy: never index files the user hasn't granted access to.

PRIVACY:
- All search is local (Spotlight index on device).
- No query or result is transmitted.
- If using CoreML for semantic embeddings, the model runs on-device.
- Respect sandboxing: use NSOpenPanel to let users grant folder access; store bookmarks with startAccessingSecurityScopedResource.

UI/UX:
- Search field is always visible in the toolbar.
- Results update live as the user types (debounce 300ms).
- Show a "Searching…" spinner while NSMetadataQuery is live.
- Group results by kind (Documents, Images, Other).
- Show a "Search Here…" contextual button for the currently open folder.
- Support keyboard shortcut to open search (Cmd+F).
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 5 — FOLDER SYNC
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- Multiple sync pairs (source → destination), each independently configured.
- Uses `MFinder/FolderSyncFolderRow.swift`, `FolderSyncPairStore.swift`, `FolderSyncScheduler.swift`, `FolderSyncView.swift`.
- Sync extension: `MFinderSync.appex` (a Finder Sync Extension that shows badges on synced folders).
- Checks for conflicts: "changed after the preview. Analyze the folders again before syncing."
- Tags: "Finder tags could not be synced" — tries to preserve macOS Finder tags.
- Safety: "Not enough free space to sync safely (requires X)".
- Scheduled sync support (from `FolderSyncScheduler.swift`).
- Remote connections: also supports SMB shares ("Connect and choose an SMB share").

---

### 📋 SYSTEM PROMPT — Folder Sync

```
You are helping me add folder synchronization to my macOS app.

WHAT THE FEATURE DOES:
1. User defines sync pairs: each pair has a Source folder and a Destination folder.
2. Sync modes:
   a. One-way (backup): copy new/changed files from Source → Destination. Never delete from Source.
   b. Two-way (mirror): reconcile changes in both directions. Conflict resolution: newer file wins (by mtime) or user chooses.
3. Before syncing, show a PREVIEW of changes: "N files to copy, N files to update, N files to delete." User confirms.
4. Free space check: refuse to sync if destination doesn't have enough free space (check URLResourceKey.volumeAvailableCapacityKey).
5. Preserve macOS metadata: Finder tags (xattr com.apple.metadata:_kMDItemUserTags), creation date, modification date, extended attributes.
6. After sync, show a summary: "N files copied, N skipped (unchanged), N errors."
7. Optional schedule: sync daily/weekly via a LaunchAgent or NSBackgroundActivityScheduler.
8. Support SMB network volumes (user authenticates via NetFS or mount_smbfs).

CONFLICT HANDLING:
- Detect conflicts by comparing mtime and size on both sides.
- Options: "Newer wins", "Source wins", "Ask me each time."
- Never silently overwrite; always keep a conflict copy if unsure.

PRIVACY:
- No cloud involved. Purely local or local-to-SMB.
- File contents are never read beyond what's needed for byte-for-byte copy (use FileManager.copyItem or low-level sendfile for efficiency).
- Store source/destination bookmarks in Keychain for persistent sandbox access.

FINDER SYNC EXTENSION (optional advanced):
- Create a Finder Sync Extension (NSExtension with NSExtensionPointIdentifier = com.apple.FinderSync) to show sync-status badges (synced ✓, syncing ⟳, error ✗) on folders in Finder.
- Communicate between the extension and the main app via NSXPCConnection.

UI/UX:
- List of sync pairs in a table: source path, destination path, last sync time, status.
- "+" to add, "−" to remove, gear icon to configure.
- Progress bar during sync with a cancel button.
- Conflict items highlighted in orange; user resolves them before sync completes.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 6 — SCREENSHOT + SCREEN OCR
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- Intercepts ⌘⇧3 (full screen) and ⌘⇧4 (area select) system shortcuts (requires Accessibility permission).
- Annotation tools after capture: text, arrows, shapes, blur/redact, callouts.
- Scroll capture: captures content that scrolls (like a full web page or a long document).
- Screen OCR: "Recognize text so you can search and copy it." Uses local Vision OCR. No network.
- Saves as PNG (⌘S) or JPEG.
- Cloud upload: sends screenshot to configured cloud (MFinder Cloud, R2, Google Drive, OneDrive).

### Source files
`ScreenshotCoordinator.swift` · `ScreenshotEditCanvas.swift` · `ScreenStillCapture.swift` · `ScreenOCRCoordinator.swift` · `ScrollCaptureSession.swift` · `ScreenRecordSession.swift`

---

### 📋 SYSTEM PROMPT — Screenshot & OCR

```
You are helping me add screenshot capture and text recognition to my macOS app.

WHAT THE FEATURE DOES:
1. CAPTURE:
   - Full screen: use CGDisplayCreateImage(CGMainDisplayID()).
   - Area selection: show a transparent overlay window; user drags to select a rect; crop with CGImageCreateWithImageInRect.
   - Window capture: use CGWindowListCreateImage with the window's windowID.
2. ANNOTATION EDITOR after capture:
   - Draw on the image with NSBezierPath / Canvas.
   - Tools: Arrow, Rectangle, Ellipse, Text label, Blur (redact) region, Highlight.
   - Color picker + stroke width.
   - Undo/redo stack.
3. SAVE:
   - PNG (lossless default) or JPEG (user-configurable quality).
   - Save to user-chosen folder, copy to clipboard, or share.
4. SCROLL CAPTURE:
   - Programmatically scroll a window or scroll view in steps.
   - Capture each visible portion with CGDisplayCreateImage.
   - Stitch vertically: compare overlapping edges to find the exact seam (normalized cross-correlation or pixel diff).
5. OCR (Text Recognition):
   - Use Vision framework: VNRecognizeTextRequest with recognitionLevel = .accurate.
   - Run on-device. No network call.
   - Return VNRecognizedTextObservation results with their bounding boxes.
   - Overlay recognized text boxes on the image; user can click any box to copy its text.

PERMISSIONS:
- Screen Recording (com.apple.security.screen-recording): required for CGDisplayCreateImage.
- Accessibility (com.apple.security.automation.apple-events): needed to intercept ⌘⇧3/⌘⇧4 globally.
- These are sensitive. Ask the user to grant them explicitly in System Settings → Privacy.
- Never record audio without explicit permission (com.apple.security.device.audio-input).

PRIVACY:
- Screenshots stay on device unless the user explicitly uploads them.
- OCR text is never stored or transmitted without user action.
- If uploading to cloud, show exactly what will be uploaded and require confirmation.

UI/UX:
- After capture, the annotation window appears immediately (< 100ms feel).
- Global keyboard shortcut configurable by user.
- Show a brief thumbnail preview in the menu bar after each capture.
- Scroll capture must pause between steps (50–100ms) to let the UI render before each capture.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 7 — DROP TRAY (Clipboard / File Staging Area)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- A floating panel that accepts dragged files, images, and clipboard content.
- Items stay until manually cleared or sent.
- "Shake to open while dragging files" — detects cursor acceleration to trigger the panel.
- Quick Share: generates a shareable link (MFinder Cloud, R2, Google Drive).
- Storage limit: "Drop Tray is nearing its storage limit."
- Items received from other Macs via the same account.

### Source files
`DropTrayView.swift` · `DropTrayCoordinator.swift` · `DropTrayStore.swift` · `DropNotchController.swift` · `DropDragMonitor.swift`

---

### 📋 SYSTEM PROMPT — Drop Tray / File Staging Panel

```
You are helping me add a floating "Drop Tray" staging panel to my macOS app.

WHAT THE FEATURE DOES:
1. A small floating panel (NSPanel, non-activating, always-on-top) that accepts:
   - Files/folders dragged from Finder (NSDraggingDestination).
   - Images from the clipboard (NSPasteboard).
   - Text snippets.
2. Items are stored temporarily in a local SQLite database or a known folder (~/Library/Application Support/MyApp/DropTray/).
3. The user can then:
   a. Drag items OUT to any other app.
   b. Copy an item's path or content to the clipboard.
   c. Upload an item to cloud storage (if connected).
   d. Clear individual items or all items.
4. The panel appears when the user drags a file and shakes the mouse (detect: monitor cursor position, compute velocity; if acceleration > threshold → show panel).
5. Show thumbnails for images and file-type icons for other files (QLThumbnailGenerator).
6. Storage limit: enforce a cap (e.g., 500 MB total). Show a warning when approaching the limit.

PRIVACY:
- File contents are only read when the user explicitly requests an upload or copy action.
- Items stored locally in the app's sandbox container.
- If uploading to cloud, show which file, which destination, and require confirmation.
- Never auto-upload.

UI/UX:
- Panel is semi-transparent, rounded corners, blurred background (NSVisualEffectView).
- Items displayed as a grid of thumbnails or a compact list toggle.
- Badge count on the app's menu bar icon showing number of items in tray.
- Shake sensitivity is user-adjustable (settings.dropTray.shakeEnabled, settings.dropTray.shakeSensitivity).
- Animate items in when dropped; animate out when cleared.

ENGINEERING NOTES:
- Use NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) to track cursor velocity.
- Velocity = Δposition / Δtime. Acceleration = Δvelocity / Δtime. Threshold: ~2000 pt/s².
- Panel window level: NSWindow.Level.floating.
- Persist items with SQLite (using GRDB.swift or SQLite.swift) for crash safety.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 8 — SECURE LOCK (Encrypted Folder Container)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- Creates an encrypted container file (`.mfinder-secure-container`) backed by a password.
- Touch ID integration: credentials stored in Keychain; Touch ID unlocks without typing the password again.
- "MFinder keeps older credentials in Keychain so Touch ID can still open existing containers."
- Cannot be used on files that are cloud-only (not downloaded).
- Cannot be used on symlinks.
- Folder Auto-Lock: auto-locks after a timer (`FolderAutoLockManager.swift`).

### Source files
`SecureLockController.swift` · `SecureLockPane.swift` · `SecureSessionManager.swift` · `FolderAutoLockManager.swift` · `FileLockController.swift`

---

### 📋 SYSTEM PROMPT — Secure Encrypted Container

```
You are helping me add an encrypted file container feature to my macOS app.

WHAT THE FEATURE DOES:
1. CREATE: User picks a folder; the app encrypts it into a single container file (custom extension, e.g., .myapp-vault).
   - Encryption: AES-256-GCM. Key derived from password using PBKDF2 (100,000 iterations, SHA-256) or Argon2id.
   - Store the salt + IV header in the container file (not the key).
2. OPEN: User double-clicks a vault file; app prompts for password (or Touch ID if previously saved).
   - Decrypt to a temporary location in a RAM disk or the app's secure temp folder.
   - Mount the decrypted content so the user can browse it in Finder (use a sparse bundle disk image via hdiutil, or just decrypt to a secure temp directory and open it).
3. LOCK: When the user is done, re-encrypt changes back into the container and delete the temp folder securely (overwrite with zeros, then delete).
4. AUTO-LOCK: Lock automatically after N minutes of inactivity (configurable timer).
5. TOUCH ID: Store the decrypted key (not the password) in the macOS Keychain with kSecAttrAccessControl = SecAccessControlCreateWithFlags(LAPolicy.deviceOwnerAuthenticationWithBiometrics).

SECURITY RULES:
- Never store the password in memory longer than necessary; zero out the string buffer after key derivation.
- Never log file paths or names from inside a locked container.
- The container file header is NOT encrypted (stores: magic bytes, version, algorithm ID, salt, IV). The body IS encrypted.
- Reject files that are stored in iCloud (cloud-only) — check URLResourceKey.ubiquitousItemIsDownloadedKey. The user must download them first.
- Reject symbolic links and aliases.

PRIVACY:
- Encryption is local. No key or content is transmitted.
- Keychain entry is per-device (kSecAttrSynchronizable = false).
- If Touch ID fails 3 times, fall back to password entry.

UI/UX:
- Password field: show strength indicator (entropy bits: weak <40, fair <60, strong <80, very strong ≥80).
- Confirm password field on creation.
- After unlocking, show the decrypted contents in a window; user edits files normally.
- Lock button always visible while a container is open.
- Auto-lock countdown shown in the toolbar: "Locks in 4:30".
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 9 — SYSTEM MONITOR (CPU / Memory / Disk / Network / Battery)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

From binary strings: "Storage space, disk activity, and drive health." · "Battery condition, charging, and energy use." · "Live traffic, app activity, and connection speed." · "Memory Pressure" · "Apps Using Energy" · "Apps Using Network."

Source files: `DiskMonitorController.swift` · `SystemMonitorController.swift` · `DiskNetworkContent.swift`

---

### 📋 SYSTEM PROMPT — System Monitor

```
You are helping me add a system resource monitor to my macOS app.

WHAT THE FEATURE DISPLAYS:
1. CPU: usage % (overall and per-core). Use host_processor_info() from <mach/mach.h> or sysctl.
2. MEMORY: used, wired, compressed, free. Use host_statistics64(HOST_VM_INFO64). Show "Memory Pressure" level (normal/warning/critical) via vm_statistics64.
3. DISK I/O: read MB/s and write MB/s per disk. Use IOKit: IOServiceMatching("IOBlockStorageDriver"), IORegistryEntryCreateCFProperties.
4. NETWORK: upload/download KB/s per interface. Use getifaddrs() or SCNetworkInterfaceGetBSDName + sysctl(net.route.0.0.dump).
5. BATTERY: charge %, time remaining, charging state, battery health %, battery temperature. Use IOKit: IOServiceGetMatchingService(kIOPSLocalBatteryType).
6. APPS USING ENERGY / NETWORK: list top-N apps sorted by CPU or bytes transferred. Use NSRunningApplication list + proc_pidinfo(PROC_PID_INFO).

REFRESH RATE: Every 1 second for most metrics. Battery every 10 seconds.

PRIVACY:
- All data is local system calls. No network.
- Reading per-app network usage may require elevated access or only totals are available in sandbox.
- Reading IOKit disk stats is allowed in sandboxed apps.

UI/UX:
- Menu bar icon shows a spark-line graph of CPU or network (user picks).
- Popover panel opens on click with all metrics.
- Each metric has a mini history graph (last 60 seconds).
- Color coding: green (normal) → yellow (warning) → red (critical).
- "Apps Using Network" sorted by bytes/sec, refreshed every 2s.

ENGINEERING:
- Use Swift with Combine: a Timer.publish(every: 1, ...) drives all metric updates.
- Wrap mach/IOKit calls in a utility actor so they never block the main thread.
- History stored in a fixed-size circular buffer: [Float](repeating: 0, count: 60).
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 10 — BATCH RENAME
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

From binary: "Select two or more files in Finder, then right-click and choose MFinder → Batch Rename…" · "nothing changes until you click Rename" · "Changes are previewed before applying."

Source files: `RenameWindowController.swift`

---

### 📋 SYSTEM PROMPT — Batch Rename

```
You are helping me add batch file renaming to my macOS app.

WHAT THE FEATURE DOES:
1. User selects 2+ files (from Finder via Quick Action, or inside the app).
2. A rename editor opens with these pattern options:
   a. FIND & REPLACE: replace text in existing name (supports regex).
   b. ADD TEXT: prepend or append a string to each name.
   c. NUMBER SEQUENCE: add a number (001, 002…) to the start or end. User sets starting number (0–1,000,000) and step.
   d. DATE/TIME: insert the file's creation or modification date in a chosen format (YYYY-MM-DD, etc.).
   e. CHANGE CASE: ALL CAPS, all lowercase, Title Case.
   f. TEMPLATE: user writes a pattern like "{counter:03d}_{name}_{date:YYYY-MM-DD}{ext}".
3. LIVE PREVIEW: show a two-column table — "Before" and "After" — updating instantly as the pattern changes.
4. CONFLICT CHECK: if two files would get the same name, highlight in red and block the rename.
5. Apply: rename all files atomically (rename() system call per file). Never partially rename and leave things inconsistent.
6. Undo: use FileManager to rename back (store the before→after map; undo reverses it).

PRIVACY:
- File names may be shown; contents are never read.
- No data leaves the device.

UI/UX:
- "nothing changes until you click Rename" — make this explicit in the UI.
- The preview table scrolls if there are many files.
- Keyboard shortcut (Return) triggers Rename; Escape cancels.
- After renaming, animate the rows in the preview to show the new names.

ENGINEERING:
- Regex engine: NSRegularExpression.
- Handle edge cases: file extensions, hidden files (starting with "."), macOS reserved names (e.g., ".DS_Store", "Icon\r").
- Date formatting: DateFormatter with the user's locale.
- For the number sequence, pad with leading zeros to the width that fits the total count (e.g., 3 digits for 100–999 files).
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 11 — WINDOW SNAPPING / TILING
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

From binary: `SnapAreasController.swift` · `SnapMouseMonitor.swift` · `SnapCoordinateSpace.swift` · `SnapRestoreRegistry.swift` · "Allow Accessibility to move and resize windows." · "macOS window tiling."

---

### 📋 SYSTEM PROMPT — Window Snapping

```
You are helping me add window snapping/tiling to my macOS app.

WHAT THE FEATURE DOES:
1. Monitor all windows on screen (requires Accessibility permission: AXUIElementCreateSystemWide).
2. When the user drags a window close to a screen edge or predefined zone, snap it to that zone on release.
3. SNAP ZONES (examples):
   - Left half, Right half (50/50).
   - Top-left, top-right, bottom-left, bottom-right (25% quadrants).
   - Full screen, Two-thirds, One-third.
   - Custom zones: user draws zones in a settings grid editor.
4. SNAP TRIGGER: detect when the dragged window's edge is within a threshold (e.g., 20 pt) of a zone boundary.
5. PREVIEW: show a semi-transparent blue overlay of the target zone while hovering near it.
6. KEYBOARD SHORTCUT mode: Ctrl+Arrow key moves frontmost window to the adjacent zone.
7. RESTORE: double-clicking the title bar restores the window to its pre-snap size (store original frame in a registry).
8. MULTI-MONITOR: zones are per-screen, calculated relative to each NSScreen.frame.

PERMISSIONS:
- Requires Accessibility (AXUIElement API).
- Request permission via AXIsProcessTrusted(); guide user to System Settings if not granted.
- In sandboxed apps, Accessibility requires the com.apple.security.temporary-exception.apple-events entitlement or running as a non-sandboxed helper.

PRIVACY:
- Only reads window frame (position and size). Never reads window contents.
- No network calls.

ENGINEERING:
- Use NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]).
- Get dragged window via CGWindowListCopyWindowInfo and AXUIElementRef.
- Move/resize window via AXUIElementSetAttributeValue(window, kAXFrameAttribute, newFrame).
- Snap zones stored as [SnapZone] = [{ id, screenID, normalizedRect: CGRect }] in UserDefaults.
- Coordinate space: normalize all zones to 0–1 relative to screen frame; multiply by screen resolution at render time.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## FEATURE 12 — KEYBOARD CLEAN MODE
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### What MFinder does

- "Block keyboard input while cleaning. Use your mouse or trackpad to unlock. Automatically unlocks after 5 minutes."
- Requires Accessibility permission.
- Power button and Touch ID remain available.
- Incompatible with Secure Input (password fields active).

---

### 📋 SYSTEM PROMPT — Keyboard Clean Mode

```
You are helping me add a "Keyboard Clean" mode to my macOS app.

WHAT THE FEATURE DOES:
1. When activated, block all keyboard input so the user can physically clean their keyboard without triggering shortcuts.
2. Mouse and trackpad remain functional.
3. Auto-unlock after 5 minutes (configurable timer).
4. Show a full-screen overlay with "Keyboard locked" message and the remaining time countdown.
5. The overlay disappears (and keyboard is unblocked) on a mouse click.

HOW TO BLOCK KEYBOARD INPUT:
- Use CGEventTap: CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue | 1 << CGEventType.flagsChanged.rawValue), callback:...).
- In the callback, return nil to consume/block the event.
- This requires the Accessibility permission (AXIsProcessTrusted) and the Input Monitoring entitlement.
- Run the event tap on a dedicated CFRunLoop thread.

WHAT NOT TO BLOCK:
- Do NOT block the power button (hardware, not CGEvent).
- Do NOT block mouse events.
- Detect Secure Input: use CGEventSourceSecureInputMode() — if true, refuse to activate Keyboard Clean (show warning: "Secure Input is active; leave the password field first").

PRIVACY:
- Never log or store keystrokes. The event tap only discards them.
- No network.

UI/UX:
- Overlay: dark, full-screen, non-interactive except for mouse clicks.
- Large text: "Keyboard locked. Click to unlock."
- Countdown timer shown prominently.
- Menu bar icon changes to indicate locked state.
```

---

## GLOBAL PRIVACY PRINCIPLES FOR ALL FEATURES

Paste this block at the end of ANY of the above prompts to reinforce privacy:

```
GLOBAL PRIVACY RULES (apply to every feature):
1. No telemetry. No analytics. No crash reporting sent to any server without explicit user opt-in.
2. No file contents, file names, or paths are ever transmitted to any server without the user explicitly initiating an upload action.
3. All AI/ML processing (OCR, perceptual hashing, semantic search embeddings) runs on-device using Apple's frameworks (Vision, CoreML, CreateML). No third-party cloud AI APIs.
4. Credentials (passwords, API keys, OAuth tokens) are stored in the macOS Keychain, never in UserDefaults or plain files.
5. When requesting permissions (Accessibility, Screen Recording, Full Disk Access, Contacts, etc.), explain exactly why each permission is needed before the system dialog appears.
6. Respect the user's sandbox: use Security-scoped bookmarks (startAccessingSecurityScopedResource / stopAccessingSecurityScopedResource) for every persistent file access.
7. Memory: zero-fill sensitive data (passwords, keys) in memory after use using memset_s or equivalent.
```
