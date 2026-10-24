# Bằng chứng XF-T28 — FileOctopus, tái dùng XFinder, số đo API, checklist Finder (2026-10-24)

4 agent đọc/đo độc lập (workflow `fileoctopus-understand`). Văn bản gốc của từng agent, không sửa nội dung; trích dẫn trang FileOctopus giữ ngắn.


## 1. Tài liệu FileOctopus 1.0.3 (fileoctopus.com, /guide, /changelog)

I have thorough, verified coverage of all documented feature areas. Here is the dense structured report.

```markdown
# FileOctopus Research Report (site-only; fetched 2026-10-24 via WebFetch)

Sources: fileoctopus.com/ (+#compare, #questions), /guide/ and subpages (browsing, panes-workspaces,
natural-language, file-operations, productivity, shortcuts, cloud-storage, content-source, search,
advanced-search, index-settings, preview-info, limitations, privacy), /changelog, /roadmap (board failed
to load — no items retrievable).

## Product identity
- One-time-purchase macOS file manager pitched as "Finder, with split panes, tabs in every pane and fast
  search." Built "Swift + AppKit." Current version 1.0.3 (22 Oct 2026), "signed and notarized by Apple."
- Min OS/hardware: "Apple Silicon · macOS 15+" (note: higher than XFinder's 14.0+ floor).
- Size: "8 MB download · 22 MB installed."
- 0 accounts; "Your index stays on your Mac."

## Views
Icon, List, Column, Gallery — matches Finder's four.

## Multi-pane / split view
- Presets: Single (1), Side by Side (2, L/R), Stacked (2, top/bottom), Grid (2×2 = 4, "PRO badge on
  Free"). Custom: Split Right/Left/Down/Up (⌃⌥⌘→/←/↓/↑).
- Pane limit: Free "up to 2 panes per window"; 14-day trial and PRO "up to 16."
- Zoom: "Zoom Pane to temporarily focus on one pane," shortcut **⇧⌘Return** (per shortcuts page; site
  landing page separately said "⇧⌘↩," same key).
- Divider: drag to resize, or menu "Make Pane Wider/Narrower/Taller/Shorter," "Make Panes Equal Size"
  (⌃⌥⌘=).
- Trial→Free downgrade: existing >2-pane layouts "stay fully usable"; only adding a 3rd pane needs PRO.
- Pane nav: ⌃⌘]/[ next/prev pane, ⌥⌘]/[ next/prev pane tab, ⌃⌥⌘T new pane tab, ⌃⌥⌘W close pane.

## Location bar
- Click a path segment → jump to that folder; middle segments collapse to "…".
- Chevron after a segment lists subfolders (states: "Loading…", list, "No Folders", "Can't Show
  Folders").
- Right-click segment → Open / Open in New Tab / Open in Other Pane / **Copy as Pathname** / Show in
  Finder.
- Type-a-path mode: ⌃⌘L (Edit Location) or click empty bar space; behaves like Go to Folder (↓/↑ choose,
  Tab completes, Return opens).

## Command palette / Quick Open
- Quick Open: **⌃⌘P** — searches recent folders, sidebar favorites, open tabs/pane tabs, saved
  workspaces.
- Typing **">"** at the start, or View → Command Palette (**⌃⇧⌘P**), switches to searching menu commands
  only, listed "with their shortcuts," restricted to "commands available right now."
- Go to Folder: **⇧⌘G**, autocompletes; "nothing is downloaded from cloud storage" while typing.

## Natural-language search
- Explicitly "Rule-based and local, not AI": "runs locally using finite templates... does not call an AI
  service, infer the meaning of arbitrary sentences, or understand the subject of a photo." Example of
  what it can't do: "photos of my dog at the beach."
- Flow: ⌘F → type phrase → phrase becomes editable chips (kind/date/size/source) → unrecognized words
  stay as filename terms.
- Verbatim example phrases → chips: "pdfs from last week" / "screenshots last week" / "videos larger
  than 1 GB" / "archives older than 30 days" / "documents created this week" / "spreadsheets edited
  today" / "downloaded from github" (→ source metadata only, "No GitHub account connection") / "images
  past 7 days" / "music over 10 mb" / "presentations from last year" / "pdfs from last week over 8 kb" →
  4 chips + "four matching files" demo (removing size chip → "widens to six PDFs").
- Rules/limits: size needs a unit ("over 5" alone is not a filter); singular "pdf/image/video" stay name
  terms (only plural or `kind:` triggers a filter); bare month w/o year infers most recent year, chip
  marked "?"; quoting a phrase (`"last week"`) forces literal match; download dates aren't filterable
  (unreliable metadata) — kept as literal terms with a warning instead.
- Content/OCR is a **separate opt-in**, not enabled by NL search: "Natural-language metadata search does
  not enable content indexing or expand your scope."
- Demo runs scoped to "the current folder" — i.e., NL search respects/filters the active scope rather
  than always searching everything.

## Content / source search (`content:`, `from:`)
- `content:"phrase"` searches document text and OCR'd image text (same prefix for both).
- Per-folder opt-in, two independent toggles after adding the folder in Settings → Search: **Contents**
  and **Text in Images** ("buying PRO never turns them on" automatically).
- OCR: "Apple's on-device Vision recognition" — "text recognition, not image-subject or semantic search";
  accuracy "depends on image quality and the recognition languages available on the running OS."
- Limits (exact): plain text reads "up to 2 MiB," stores "up to 200,000 characters"; PDF text "considers
  up to 50 pages," "skips PDFs above 64 MiB"; OCR "bounded to eligible local images and up to 10
  scanned-PDF pages," "50 MiB file limit," unspecified "image dimension limits," same 200,000-char cap.
  Locked/corrupt/unreadable/nonlocal-cloud files may be skipped; "no promise that an unindexed document's
  contents will be found."
- Index lives locally; "Erase Index…" deletes "stored indexed names, contents, and OCR text" (originals
  untouched). No stated on-disk path. No mdfind/Spotlight detail beyond: Free tier still gets "Filename
  search and available Spotlight results."
- Local content/OCR search itself requires PRO (filename search is Free).

## Advanced search syntax
Prefixes: `ext:`, `kind:`, `size:` (`>`,`<`,`>=`,`<=`,`=`; binary-unit pairs KB/KiB etc. treated
equivalent; decimals like `>1.5GB` valid; bare number = bytes), `mtime:`/`modified:` (e.g. `<7d`),
`created:`, `in:` (scopes within current search, "does not authorize another folder"), `tag:`, `from:`
(source metadata), `content:`, `date:` (alias for mtime). Name matching: fuzzy term, quoted phrase,
`^prefix`, `suffix$`, `!term`/`-term` exclusion, `!ext:zip` negated operator. Combination is **AND only**
— "this interface does not provide a general Boolean OR expression language." Unknown operators → kept
as literal text + warning; invalid values → error, filter dropped.

## Search scope selection
Three mechanisms: (1) type-to-select in a focused list (jumps, doesn't filter); (2) "Filter Current
Folder" (in-memory filter of already-loaded items, no recursive scan); (3) Find (⌘F) — scopes: Current
Folder (includes descendants), This Mac (only folders approved in Search settings — does NOT grant
full-disk access automatically), Open Panes. Default scope configurable in Settings → Advanced. Saved
searches require PRO/trial and re-evaluate relative dates each run.

## File Shelf
- View → Shelf → Show Shelf; shown "at the bottom of the window" in the demo.
- Add via File → Add to Shelf or drag-in. Transfer: "Copy Shelf Items to Active Pane" / "Move Shelf Items
  to Active Pane" (acts on selection, or all if none selected).
- "The Shelf stores references, not copies"; it "is per window/session" (i.e., lasts one window).
- Reveal via double-click or "Show in Enclosing Folder"; Remove / Clear… to empty it.
- Gated: adding items "needs the trial or PRO"; Free shows "Adding items to the Shelf needs PRO" but can
  still reveal/copy/move/remove existing entries post-trial.
- Known gap (per limitations page): "no Quick Look/Open, drag out, or recursive folder size totals."

## Workspaces / session restore
- Save: Window → Save Workspace…; reopen: Window → Open Workspace, via Quick Open, or a toolbar button.
  Manage: Rename/Duplicate/Delete Workspace; "Inspect Saved Workspaces…"/"Export Saved Workspaces…" as
  JSON only (view/export, no file changes).
- Saving/opening/duplicating named workspaces needs trial/PRO; Free users keep existing workspaces and
  can still inspect/rename/export/delete them.
- Workspaces are "layout snapshots, not file backups or synchronized folders."
- Default auto-restore (free, independent of named workspaces): relaunch brings back "windows, tabs and
  split panes," each tab's Back/Forward history, regardless of the macOS "close windows when quitting"
  setting. Missing folder → left out; missing disk → never auto-mounted. Toggle:
  Settings → General → "Reopen windows when FileOctopus opens." One-time skip: **hold Shift at launch**.
  Gap: "the full column path isn't restored yet" (per limitations page).

## Operations panel (copy/move)
- Progress stages: "Preparing…, Verifying…, and Finishing…".
- Pause: click Pause → "Pausing…" → "Paused," resumes "without starting over"; no safe pause point once
  in Verifying/Finishing; source changed during pause → "reported instead of copied"; other operations
  wait for the paused one; quitting blocked ("A file operation is still in progress"); eject also
  refused while paused. Gap: "a paused operation does not resume after relaunch"; Rename/New
  Folder/batch rename "can't be paused."
- Queue: one operation runs at a time, in start order; waiting rows reorderable (Run Next/Move Up/Move
  Down), running one "never interrupted." Free: only one copy/move/duplicate at a time; queueing needs
  trial/PRO. Pause All/Resume All exist.
- Conflict dialog: **Keep Both (Return, default)**, Skip, Stop (Escape), Replace (marked destructive),
  Merge… (folders). Keep Both renames e.g. "Report copy.pdf" → "Report copy 2.pdf". Multi-conflict →
  "Apply to all." No folder/package Replace; no folder Merge inside cloud storage.
- Verified cross-volume moves: "copies first, checks the copy and removes the original only after that"
  (flush-before-delete); same rule inside merges, per item.
- Eject blocking: disk can't eject mid-operation (same mechanism as the quit block).
- Crash/interrupt recovery: next launch "may show a recovery report with items needing review"; "Clear
  File Operation History…" explicitly "is not a file backup."
- Undo: persists "the last 20 steps... for 24 hours," survives quit/relaunch; verifies "each item is
  still the same file, in the same place and unchanged" before undoing; unavailable disk → "Can't Undo
  …" until reconnected; stores only "names, locations and checksums, never file contents"; permanently
  blocked after Replace ("the item that was there is gone"), and when only some items of a multi-item op
  finished.
- Merge preview: counts new / same-name conflicts / already-identical (skipped) before you click Merge;
  "Keep the newer one" needs ≥1s newer (≥2s on FAT/exFAT, i.e. filesystem-timestamp-granularity aware).
- Errors: plain-language messages (e.g. disk-full text), machine code on a separate "Details" line;
  "Retry appears only when trying again is safe" (nothing yet written at destination).

## Cross-pane shortcuts
File → Copy to Other Pane (**⌃⇧⌘C**) / Move to Other Pane (**⌃⇧⌘M**) — moves/copies into the folder shown
in the other pane without changing focus/selection. With 2 panes, "other" = the one you're not in; with
3+, it's "the next one," or use "Copy to Pane"/"Move to Pane" to pick explicitly. Drag mirrors Finder
(same-volume drag = move, cross-volume = copy; Option forces copy, Command forces move). Disabled when:
nothing selected, other pane is searching/Recents/Tags, no write permission there, items already there,
or a folder would nest into itself. All undoable (⌘Z).

## Batch rename
Preview-first: shows every "Original → New Name" row + Status; "Nothing is renamed until you click
Rename." Invalid/colliding names block the Rename button. Undo via ⌘Z immediately after ("the original
names come back") — no explicit separate time window stated beyond the general 20-step/24h undo system.
Available on Free (unlike Shelf/Workspaces/queueing).

## ZIP compress + undo
"Compress to ZIP" with Undo support; site copy: "The archive is tested before it appears, and ⌘Z moves
it to the Trash." (No further verify-mechanism detail, e.g. whether it checksums entries, was given.)

## Google Drive / Dropbox
- No vendor sign-in by FileOctopus itself for either service: "never signs in... makes no network
  connection"; relies on the official Drive/Dropbox desktop app being installed/signed in; accounts then
  appear under sidebar "Locations" (same mechanism as any `~/Library/CloudStorage` provider, "the way
  Finder lists them").
- Cloud-status icon in all 4 views: not-downloaded / downloading-uploading / download-failed /
  upload-failed. Opening/browsing a folder "doesn't download anything."
- Actions: Download Now, Remove Download (frees Mac space, keeps cloud copy; stops on not-yet-uploaded
  files). Single-item Download Now/Remove Download and "Open in Google Drive" (up to 10 items at once)
  are **Free**. Bulk (multi-item) Download Now/Remove Download and **Copy Google Drive Link** (never
  changes sharing) require trial/PRO.
- Dropbox: "View on Dropbox.com" (also cap 10 items, Free); Dropbox's own advanced commands (link copy,
  Share, version history) unsupported directly — user must go via "Show in Finder" + right-click in
  Finder. Dropbox cloud-only items "can't be moved to the Trash yet."
- Unverified by the vendor itself (named gaps): Google-native docs, shared drives, mirror mode, offline
  Drive; Dropbox team spaces.

## Preview / Get Info / Tags
- Quick Look: Space or ⌘Y; Slideshow ⌥⌘Y; inline Preview pane ⇧⌘P; Gallery/Column also preview inline.
  "A preview is not a promise that every third-party file format has a renderer."
- Get Info (⌘I): foldable sections General / More Info / Name & Extension / Tags / Sharing & Permissions;
  multi-select → one summary window; folder size computed in background ("logical total, not a
  storage-accounting guarantee"); cloud-only files never auto-downloaded to fill in More Info; Locked
  checkbox blocks rename/trash/extension/permission changes; permission changes apply to the item only,
  not recursively; search-result Info windows are read-only; Undo (⌘Z) reverses Info-driven changes.
- Tags: comma-separated entry, searchable via `tag:`; "currently unavailable in search results."

## Pricing
- Free: $0, "No daily limits" (but feature-gated: 2 panes, no Shelf/workspaces/queue/bulk-cloud/saved
  search/local content search).
- PRO: one-time purchase, tiered launch pricing — "$14.99" first 100 (until Nov 2), "$19.99" next 200
  (until Nov 30), "$29.99" after. Licenses "up to 2 Macs," "lifetime updates," not a subscription.
  "30-day money-back." 14-day free trial, auto-started on first launch (per changelog v0.9.1).
  Checkout via Lemon Squeezy; license key pasted into FileOctopus → License…; "requests carry purchase
  and license identifiers only."

## System requirements / size / performance
- "Apple Silicon · macOS 15+" (Intel not supported — stricter than XFinder's arm64-only+macOS14+, but
  FileOctopus also excludes Intel).
- "8 MB download · 22 MB installed."
- Performance claim: "29× faster" search than Finder — "Median of 12 searches over 146,000 files on an
  Apple M3 Max," "0.27 s vs 7.7 s." (Single disclosed benchmark; methodology beyond that one line not
  published — no file-type mix, cold/warm cache state, or disk type disclosed.)

## Privacy (site claims)
- Core browsing/search: "no account, cloud sync, or external AI service"; NL search "local templates";
  index/content/OCR data "stored locally," app data under `~/Library/Application Support/FileOctopus`.
- Opt-in usage telemetry → PostHog (US), random ID, "without storing your IP address," excludes
  filenames/paths/search text/contents; toggle in Settings → Privacy; "Reset Anonymous ID" available.
- Opt-in crash reports → Sentry (EU), off by default, scrubbed of folder paths/filenames/emails/
  links/Mac name pre-send, "deleted after 30 days," device info only.
- Sparkle auto-update checks hit fileoctopus.com/updates/appcast.xml then github.com/githubusercontent.com
  redirects; "no macOS version, no system profile, and never your files"; caveat "these servers see your
  IP address."
- Website analytics: GA4, US processing, ad features/Google signals off, "does not store IP addresses,"
  honors GPC/DNT, strips emails/slashes/4+-digit numbers from search terms.
- No explicit sandboxing-architecture statement found; permissions described only as "Desktop, Documents
  and Downloads," then "Full Disk Access," gating actual filesystem access.

## Documented current limitations (from /guide/limitations, verbatim fragments)
No linked-pane nav, no folder compare/sync, no duplicate finder, no remote SFTP/WebDAV/S3/R2 clients, no
AI rename/organize, no semantic similarity search, no ShiftPlus integration, no custom folder-appearance
editing; "Computer/This Mac," "Network," "Connect to Server" not working browsing destinations;
spring-loaded folders not documented as available; Trash view needs Full Disk Access and lacks Empty
Trash/Put Back; no general exclusion-pattern editor for search folders; tag editing unavailable in
search results; paused ops don't survive relaunch; reopened windows don't restore full column path;
Rotate/Trim/Create PDF/Convert Image are "disposable fixture runs only," Markup delegates to Preview;
human-verification still pending for VoiceOver/Full Keyboard Access, real Finder clipboard/drag
round-trips, cloud placeholders, real Trash/Put Back, cross-volume interruption/power loss, and
signing/notarization edge cases.

## Changelog highlights (own-stated dates; app is ~6 days old per site, v0.9.0→1.0.3 "17–22 Oct 2026")
v1.0.3 (22 Oct): Get Info window, disk Get Info, free-space status bar, sidebar customization (hide
disks, custom groups, rename favorites), Settings → Keyboard panel w/ Finder/Windows Explorer/Total
Commander shortcut profiles + import/export, mouse button 4/5 remap. v1.0.2 (21 Oct): Quick Open +
Command Palette, Go to Folder autocomplete, Recent Folders, folder merge w/ conflict resolution,
persistent 24h/20-step Undo, copy speed/ETA, Pause All/Resume All + queue reorder, Problems list,
Explorer-style key options. v1.0.1 (20 Oct): session restore, cross-pane shortcuts, mouse/trackpad
back-forward, Dropbox sidebar. v1.0.0 (19 Oct): PRO sale launch via Lemon Squeezy, pricing tiers set.
v0.9.x (17–18 Oct, beta): initial split-pane/tabs/search release, ZIP+undo, pause/resume, Google Drive,
memory-usage fix, auto 14-day trial.

## Roadmap page
`/roadmap` returned "The board couldn't load" — headers "Planned," "In progress," "Done," "Top New
Ideas" are present but **no items were retrievable**; could not verify roadmap contents.

## What the site does NOT say (gaps we must decide ourselves)
- No ZIP verify mechanism detail (checksum? re-read entries? just "archive is tested").
- No stated max file-count / folder-size practical ceiling for any operation (copy, search index,
  Shelf) beyond the content/OCR byte/page/char limits.
- No index storage format, size on disk, or indexing CPU/memory cost disclosed.
- No concurrency model for the single-operation-at-a-time queue (why serialized — I/O contention
  avoidance is implied, not stated).
- No info on multi-display/External-display handling, window/pane minimum sizes, or memory footprint of
  the app itself (contrast: XFinder tracks footprint in MB explicitly).
- No accessibility statement beyond an internal "still needs verification" limitations note — no public
  VoiceOver/keyboard-navigation claims.
- No explicit sandboxing / entitlements disclosure, App Store distribution status (site implies direct
  DMG download + Sparkle, not Mac App Store).
- Benchmark methodology for "29× faster" is a single aggregate number — no breakdown by query type
  (filename vs content vs NL), cache-warm state, or comparison to Spotlight directly rather than Finder.
- No stated behavior for iCloud Drive specifically beyond being listed like any CloudStorage provider.
- No undo/redo for Shelf actions or Workspace deletion mentioned.
- Pricing tier *content* differences doc lives across multiple pages (Shelf/workspaces/queue PRO-gates);
  no single canonical features-matrix beyond the Finder-comparison table.

## Feature | Site says | Our open question

| Feature | Site says | Our open question |
|---|---|---|
| Multi-pane | Up to 16 panes (PRO), 2 free, presets 1/2/2/4, zoom ⇧⌘↩/⇧⌘Return, manual dividers | What's our pane cap given XFinder's 650×188 Notch isn't a browser window — does "panes" even map, or is this strictly a new Finder-replacement window feature? |
| Location bar | Chevron popups list subfolders; copy-as-pathname; click-to-jump | Do we reuse XFinder's existing breadcrumb code anywhere, or build fresh for this feature? |
| Command palette | ⌃⌘P Quick Open; `>` or ⌃⇧⌘P for commands-only | Conflicts with XFinder's own global shortcuts (e.g., ⌘⇧V clipboard) — need a collision audit before picking keys |
| NL search | Rule-based local templates, explicit non-AI, chips, finite phrase set | Do we match their exact template grammar or design our own (and would an actual on-device LLM parse — which XFinder could justify under "probe before claiming no API" — beat their finite templates)? |
| Content/OCR opt-in | Per-folder Contents + Text in Images toggles; Apple Vision OCR; 2 MiB/50-page/64 MiB/50 MiB/200k-char limits | XFinder's Vision Rule (§6 table) already mandates OCR run in a child process (`XFinder --vision`) — must carry that constraint into this feature's spec |
| File Shelf | Per-window reference list, PRO-gated, no Quick Look/drag-out yet | One-shelf-per-window vs a single persistent global shelf — which matches XFinder's existing Pinboard model better? |
| Workspaces/session restore | Auto-restore free; named Workspaces PRO; Shift-at-launch skips restore | XFinder already has deep-link scheme (`xfinder://`) — should workspace open reuse that, and do we gate named workspaces behind any paywall (XFinder has none currently)? |
| Operations panel | Pause/resume, serialized queue, Keep-Both-default conflict dialog, verified cross-volume moves, 20-step/24h undo | Our Rule 9 (data safety: Trash not rm, pbcopy changeCount, stdin not argv) must be reconciled with "verified moves" — do we implement byte-verify-before-delete the same way? |
| Cross-pane shortcuts | ⌃⇧⌘C / ⌃⇧⌘M, Option/Command drag semantics | Exact same keys requested in task — confirm no existing XFinder binding collision |
| Batch rename | Preview grid, blocks on collision, ⌘Z undo, Free tier | XFinder likely already has batchRename in FeatureCatalog (§2 sidebar lists "batchRename") — reconcile vs. extend existing feature rather than duplicate |
| ZIP verify+undo | "tested before it appears," ⌘Z → Trash | Need our own verify definition (checksum vs re-open test) since site doesn't specify; XFinder has `compress` already in sidebar — likely extend, not new |
| Google Drive/Dropbox actions | No vendor sign-in; relies on official desktop apps; Finder-registered `~/Library/CloudStorage`; Copy Drive Link PRO-gated | Does XFinder also want zero-sign-in (reuse local CloudStorage mount), and do we adopt the Free-vs-PRO bulk-action split, or keep everything free per XFinder's no-monetization-shown pattern? |
| Pricing/min OS | macOS 15+ Apple Silicon only, $14.99→$29.99 tiered, one-time, 2-Mac license | XFinder targets macOS 14.0+ arm64 — decide whether to match FileOctopus's higher OS floor just for this feature or keep 14.0 compatibility |
| Performance claim | "29× faster," 0.27s vs 7.7s on 146k files, M3 Max | We have no comparable measured XFinder search benchmark yet — would need our own probe (same methodology: median of N runs, disclose file count/hardware) before claiming parity or superiority ("FASTER" requirement) |
| App size | 8 MB download / 22 MB installed | XFinder footprint is tracked in MB (idle 26.7 MB baseline per CLAUDE.md) — new feature's memory/binary-size delta needs to be measured post-build, not assumed |
```

Could not verify: `/roadmap` board content (client-side board failed to load in fetch — no planned/in-progress items retrievable). Zoom-pane shortcut appears as both "⇧⌘↩" (landing page) and "⇧⌘Return" (shortcuts page) — same physical key, not a discrepancy. No credentials, Keychain, GUI app launches, or transcripts were touched; all data came from public WebFetch reads of fileoctopus.com pages only. No files were written to the XFinder-claude repo (read-only, as instructed) — all scratch-free since this was pure web research, nothing was created under the scratchpad path either as none was needed.


## 2. Kiểm toán tái dùng trong XFinder

I have all the file:line evidence needed. Now producing the dense structured audit report.

## XFinder File-Browser Reuse Audit

Repo audited: `/Users/wolong/github/XFinder-claude` (read-only, nothing edited/committed). CLAUDE.md read first (project rulebook/map at `/Users/wolong/github/XFinder-claude/XFinder/../CLAUDE.md` — same rules as the system-prompt copy). `git status`/build/tests not run (audit only).

### 1. Capability-by-capability: REUSE / ADAPT / NEW

**Directory listing (the browser's core)**
- No existing recursive/live directory-listing engine. `XFinder/Core/FileWalk.swift:10-36` is an `fts`-based one-shot walker (`FTS_PHYSICAL|FTS_NOCHDIR|FTS_XDEV`), chosen because `FileManager` enumeration APIs hide `._*` regular files on macOS 27 (comment, `FileWalk.swift:7-9`). It returns `(entries, truncated, cancelled)` via a visitor closure, with a `limit` and `isCancelled` check — good shape for a bounded listing pass but not live/FS-event-driven and not sorted/paginated for a UI list.
- **ADAPT**: `FileWalk.walk` as the one-shot "read this directory" primitive (reuse for non-recursive single-level listing by giving it depth awareness, or wrap it), plus `FileWalk.totalSize` (`FileWalk.swift:39-49`) for folder sizes shown in a browser. **NEW**: an `FSEventStream`/directory-watcher for live updates — nothing in the codebase currently watches a folder for change events (only AX window observers and SQLite exist as "watchers").

**Icon / thumbnail cache**
- No file named `ClipboardAppIcon` exists (task's reference name is stale/wrong) — the real precedent is `LRUThumbnailCache` in `XFinder/Core/WindowPreview/ScreenCaptureProvider.swift:12` (capacity-bounded, `Entry{capturedAt, fromProxy}`, `ThumbnailFreshness` staleness window at line 87, cap pixel size). It caches **window** thumbnails via ScreenCaptureKit, not file icons.
- `PerPIDMemo<Value>` (`XFinder/Core/AXWindowID.swift:43-53`) is a tiny pure memoization struct ("ask `fetch` the first time only") — directly reusable pattern for "memoize `NSWorkspace.icon(forFile:)` per extension/UTI once per listing".
- Current plain icon fetch is **not cached**: `NSWorkspace.shared.icon(forFile:)` called directly at `XFinder/Core/QuickSearch/FileSearch.swift:43` and similarly in Drop Tray's SF Symbol-only row icons (`XFinder/Views/Detail/DropTrayDetailView.swift:88-89`, which uses a generic folder/doc SF Symbol, not a real per-file icon).
- **ADAPT**: `LRUThumbnailCache`'s shape (bounded LRU + freshness window) for a new file-icon/thumbnail cache; **ADAPT** `PerPIDMemo`'s memo pattern keyed by path or UTI. **NEW**: the actual file-icon LRU cache class and QuickLook-thumbnail generation (QLThumbnailGenerator is not used anywhere in the codebase — only `QLPreviewPanel` for full preview, see below).

**Quick Look**
- `QLPreviewPanel` is used in three places: `XFinder/Core/Clipboard/ClipboardLibraryStore.swift`, `XFinder/Views/ClipboardQuickLook.swift:7-19` (`ClipboardQLController`, `QLPreviewPanelDataSource`, single-item, `present(url:)` → `reloadData()`), and `XFinder/Views/Detail/QuickLookDetailView.swift` (a settings page about `qlmanage -r cache`, not a panel host).
- **REUSE**: `ClipboardQLController`'s pattern directly — generalize `present(url:)` to accept an array + selected index for multi-file Space-bar preview in a file browser (currently hardcoded to one URL, `ClipboardQuickLook.swift:8`). **NEW**: `QLThumbnailGenerator`-based grid thumbnails (not present anywhere — Quick Look today is only full-panel preview, no thumbnail API usage found via `grep -rn QLThumbnailGenerator`, zero hits).

**NL search chips / Spotlight search**
- `XFinder/Core/FileSearchEngine.swift` is the most reusable piece: `runMdfind` (lines 24-48) streams `mdfind -0` output through `NulRecords` and **stops the child process early** once `limit` is hit (comment at lines 22-23 cites a measured 134 MB/35 s regression fixed 2026-10-23) — this is exactly the backend a file-browser search bar needs. `Criteria` (lines 52-99) is a structured filter (name/kind/modified-within-days) producing an mdfind query string; `parseNaturalLanguage` (lines 111-175) is a rule-based VI/EN parser → mdfield query + human explanation, explicitly "no cloud, no fabricated results" (file header comment, lines 3-6).
- `NulRecords` (`XFinder/Core/NulRecords.swift:8-43`) is the pure NUL-record reader/truncator, symlinked into `Tests/` — reusable as-is for any `mdfind -0` consumer.
- **REUSE**: `FileSearchEngine.runMdfind`, `Criteria`, `NulRecords` wholesale as the backend for an in-browser search/filter bar. **REUSE**: `parseNaturalLanguage` for "search chips" (type/recency chips) — it already emits discrete `notes` strings per matched facet (kind, recency, name) that map 1:1 to removable chips. **ADAPT**: `QuickSearchEngine` (`XFinder/Core/QuickSearch/QuickSearchEngine.swift:12-60`, debounced 0.2 s Task-based search merging quicklinks+apps+calc+files) as the debounce/merge pattern if the browser's search bar also needs instant local results; `FileSearch.swift` uses `NSMetadataQuery` instead of `mdfind` subprocess (index-only, async, with 1.2 s deadline loop at lines 54-58) — a second, different Spotlight path worth picking one of, not both.

**Shelf (staged items for batch action)**
- `DropTrayStore` (`XFinder/Views/Detail/DropTrayDetailView.swift:302-398`) is a complete, persisted (`UserDefaults`, JSON-encoded `[Item]`), de-duplicating, missing-file-flagging shelf with drag-and-drop ingestion (`add(providers:completion:)`, lines 342-354, batches async `NSItemProvider.loadObject` before one assignment — comment at lines 323-325 explains avoiding "1 000 files ⇒ 1 000 renders"). The view wires it to Move/Copy/Compress/Trash/Open-all actions (lines 146-156, 233-296).
- `ClipboardShelfController` (`XFinder/Core/ClipboardShelfController.swift:17-453`) is a different kind of shelf — a floating `KeyablePanel` HUD with a global hotkey (`.cgSessionEventTap`, lines 122-156) and keyboard navigation (←/→/Return/⌘1-9/Esc, header comment lines 13-14) — relevant as the UI/interaction pattern for a "floating file shelf while dragging", not the persistence model.
- **REUSE**: `DropTrayStore` directly as the shelf's backing store (it already is the "shelf" for files — add path dedup, missing-file tracking, drag ingestion, and the four batch actions). **ADAPT**: `ClipboardShelfController`'s floating-panel + global-hotkey + keyboard-shortcut scaffolding if the browser needs a similarly invokable floating shelf instead of (or in addition to) the Drop Tray's settings-page-embedded list.

**Copy/move queue + conflict dialog**
- No queue exists. `DropTrayDetailView.moveOrCopy` (lines 233-254) is synchronous, main-thread, one-file-at-a-time `FileManager.moveItem/copyItem`, and its conflict handling is "skip and count as failed" (line 240) — no dialog, no resolution choice, no progress.
- `ArchiveEngine.ConflictPolicy` (`XFinder/Core/Archive/ArchiveEngine.swift:20-27`: `keepBoth`/`ask`/`merge`) and `ArchiveEngine.destination(base:policy:exists:)` (lines 72-86, loop-safe — comment at lines 70-71 notes a prior recursive version stack-overflowed) are the only real conflict-resolution primitives in the codebase, built for archive extraction, not copy/move.
- **ADAPT**: `ArchiveEngine.ConflictPolicy` + `destination()`/`numbered()` (lines 46-55) — the "Report.zip → Report 2.zip" naming scheme generalizes directly to file copy conflicts. **NEW**: an actual async copy/move queue with progress, cancellation (model after `ArchiveRunner.run`'s `withTaskCancellationHandler` + `OSAllocatedUnfairLock<pid_t>` pattern at `ArchiveRunner.swift:39-70`, which correctly reads stderr before `waitUntilExit()` and SIGTERMs on cancel) and a conflict **dialog** (none exists; `.ask` in `ArchiveEngine.destination` only returns `.needsDecision(existing:)` for the caller to surface — no UI does this yet for files, only `ArchiveRunner.conflicts(_:in:)` lists names for an extraction prompt that isn't shown in the audited view code).

**Batch rename preview + undo**
- Fully reusable as a unit: `BatchRenameEngine.plan(files:options:)` (`XFinder/Core/BatchRenameEngine.swift:41-73`) is pure, returns `[Plan]` with `collides: Bool` for preview, handles prefix/suffix/replace/sequence/case modes; `BatchRenameEngine.execute(_:)` (lines 76-87) performs only the collision-free subset and returns `(moved, failed)`. `BatchRenameDetailView.swift` (194 lines) wires this to `ActionHistoryStore.recordRenames(pairs:)` (`ActionHistoryStore.swift:47-55`) which stores `UndoPayload{from, to}` and powers `undo(_:)` (lines 73-100, skips if target now occupied, moves back via `FileManager`).
- **REUSE**: `BatchRenameEngine` wholesale for any rename-planning the browser offers (inline rename, batch rename panel). **REUSE**: `ActionHistoryStore` wholesale as the undo backbone for ALL file-browser mutating ops (rename/trash already modeled; `kind: String` is open-ended — "move"/"copy" would need new `kind` values and corresponding `UndoPayload` semantics, which the store supports but doesn't yet have call sites for, e.g. `DropTrayDetailView.moveOrCopy` records history but passes `reversible: false`, line 249).

**Zip verify + undo**
- `ArchiveEngine.swift` (205 lines, pure, symlinked) + `ArchiveRunner.swift` (234 lines, Foundation-only, Process-based) together are a complete, hardened compress/extract engine: staging-via-symlinks to avoid `ditto`'s one-source limitation (header comment `ArchiveEngine.swift:7-11`), ZIP central-directory listing verification after compress (`ArchiveRunner.swift:104-119`, re-reads `unzip -Z1` to catch tools that "exit 0" while silently dropping files), symlink-escape detection on extract (`ArchiveEngine.escapingLinks`, lines 189-199, `ArchiveRunner.swift:146-155`), and a staged-then-placed extraction flow with 3 conflict policies (`ArchiveRunner.place`, lines 168-196).
- No "undo" exists for archive ops today — `DropTrayDetailView.zipTray()` (lines 256-276) records history with `reversible: false` (line 270).
- **REUSE**: `ArchiveEngine`/`ArchiveRunner` wholesale for any in-browser compress/extract action — this is the single shared engine already used by 3 call sites (Nén & Giải nén page, Drop Tray's "Nén ZIP", Thao tác Finder's ZIP per the file header, `ArchiveEngine.swift:3-5`) and the Notch hub. **NEW**: undo for zip/extract (nothing reverses an archive op — would need `ActionHistoryStore.UndoPayload` extended or a new payload type, since "undo an extract" means deleting placed files, not moving them back).

**Workspaces persistence**
- Nothing exists for saved window/layout sets scoped to file-browser "workspaces." The closest analog is `SnapMemory` (`Core/Snap/SnapMemory.swift`, referenced in CLAUDE.md §7 2026-10-18 entry) which remembers window geometry per app/display-set — a different domain (app window positions, not file-browser tab/pane state).
- **NEW** entirely: any "saved folder-tab-set" persistence. `DropTrayStore`'s `UserDefaults`+`Codable` persistence pattern (`DropTrayDetailView.swift:382-394`, load/persist via `JSONEncoder`/`JSONDecoder` on one key) is the idiom to copy, not code to reuse.

**Command palette**
- `QuickSearchPanelController` (`XFinder/Core/QuickSearch/QuickSearchPanelController.swift:23-319`) is a complete, working command palette: Carbon `RegisterEventHotKey` (no Accessibility permission needed, comment lines 11-14), hotkey recorder (`beginRecording`/`finishRecording`, lines 134-173), a `KeyablePanel` positioned Spotlight-style (lines 209-234), arrow-key navigation + Esc + click-outside dismiss (lines 267-317), backed by `QuickSearchEngine` (quicklinks + apps + calculator + files).
- **REUSE**: wholesale as the shell for a file-browser command palette (or literally the same palette, extended with file-browser-specific `QuickSearchResult` actions — go-to-folder, recent locations, browser commands). The panel/hotkey/dismiss plumbing needs no changes; only new result types feeding `QuickSearchEngine.search`.

**Cloud status**
- `CloudSyncController.swift` exists (`XFinder/Core/CloudSyncController.swift`) but wasn't opened in this pass (out of the explicitly-listed files); from the filename and `FolderSyncController.swift` neighbor it likely tracks sync status for XFinder's own "Đồng bộ" feature, not iCloud Drive/Dropbox badges for arbitrary files in a browser listing. **Flag as unverified** — would need to open `CloudSyncController.swift` to confirm whether it exposes any per-file cloud-status API reusable for file-browser badges (e.g. `NSURLUbiquitousItemDownloadingStatusKey`). Treat as **NEW** until that file is actually inspected.

### 2. Supporting infrastructure confirmed reusable

- **Finder selection bridge**: `FinderSelection.read()` (`XFinder/Core/FinderSelection.swift:12-43`) — AppleScript-based, async, `Task.detached`, handles `-1743` (Automation not granted) with a precise L10n-keyed message pointing at System Settings. Directly reusable if the file browser needs to seed its initial listing from Finder's current selection, or offer "reveal in Finder"-style interop.
- **Finder keyboard rewriting**: `FinderKeyboardController` (`XFinder/Core/FinderKeyboardController.swift:20-174`) is Finder-specific (gated on `frontmostApplication?.bundleIdentifier == "com.apple.finder"`, line 105) — **not directly reusable** inside XFinder's own window, but its ⌘X/⌘V-via-Finder's-own-Move, Delete→Trash, Return→Open mapping is the exact UX a file browser would want to implement *natively* (not via event-tap rewriting, since it's XFinder's own window/control): **ADAPT the UX spec**, not the event-tap code.
- **Standalone windows**: two concrete patterns exist. (1) `MainWindowController` (`XFinder/App/AppState.swift:38-100`) — singleton holding one `NSWindow`, `NSHostingController` with `sizingOptions = []` + explicit `contentMinSize` (comment lines 64-67 explains why: SwiftUI's own ideal-size reporting previously caused a "page jumps up" bug), `isReleasedWhenClosed = false`, window delegate intercepts close to run cleanup (`relockAll()`, lines 93-98) and hides instead of destroying. (2) `AppDelegate.showAboutWindow()` (`XFinder/App/XFinderApp.swift:300-312`) — simpler lazy-singleton `NSWindow(contentViewController:)`. **REUSE**: `MainWindowController`'s pattern wholesale for a new "file browser" standalone window (own `XxxWindowController.shared`, own `NSWindow`, `sizingOptions = []`, `contentMinSize`, don't destroy on close).
- **Floating/panel surfaces**: `SurfacePanel` (`XFinder/Core/Surface/SurfacePanel.swift:14-99`) is the shared `NSPanel` subclass for every notch/toast/interactive floating surface — `Kind.interactive/.passive/.notch`, `animationBehavior = .none` (comment lines 39-44 explains the measured order-front-zoom stutter this avoids), the critical rule that `.notch`-kind panels must **never assign** `ignoresMouseEvents` (comment lines 49-55, backed by `SurfacePanelHitTestTests`). If any part of the file browser needs a floating (non-window) surface — e.g. a quick preview HUD — **REUSE** `SurfacePanel` rather than hand-rolling another `NSPanel`.
- **Menu bar / hotkey / deep link registration**: `MenubarController.menuNeedsUpdate` (`XFinder/App/MenubarController.swift:96-158`) rebuilds a plain `NSMenu` fresh on every open (no retained state while closed, comment lines 5-11) — **REUSE pattern**: add a "File Browser" row the same way (`ActionItem(L10n.t("...")) { AppState.shared.navigate(to: .someNewCase) }`, line 108 pattern). Global hotkeys for new features go through `applicationDidFinishLaunching`'s `applySettings()` fan-out (`XFinderApp.swift:72-144`) — a new controller's `.shared.applySettings()` call must be added in **both** places (launch, line ~89 area, and `didBecomeActive`, line ~138 area) per existing precedent (e.g. `ClipboardShelfController.shared.applySettings()` appears at both lines 89 and 138). Deep links: `AppDelegate.handleFinderURL(_:)` (`XFinder/App/XFinderApp.swift:193-231`) is a single `switch comps.host` — a new `xfinder://filebrowser?path=` case would be a few lines there, following the `droptray-add` case's shape (lines 197-203) exactly.

### 3. Registration/catalog machinery a new feature must plug into

- `FeatureCatalog.swift` (340 lines): `FeatureID` enum (`FeatureCatalog.swift:97-111`) needs a new case; `FeatureDef` struct (lines 113-125) requires `enabledKey`, `defaultOn`, `permissions: [AppPermission]`, and a **true** `IdleCost` (enum at lines 62-67: `nothingAtRest/listensToKeyboard/listensToMouse/timerWhileActive/helperProcess/watchesWindows`) — CLAUDE.md explicitly forbids claiming `nothingAtRest` if the feature has a tap/timer/observer/helper.
- `FeatureHub.swift` (191 lines): `isOn(_:)` (lines 58-61) is the **ONE reader pattern** — `UserDefaults.standard.object(forKey:) as? Bool ?? f.defaultOn` — every new feature's engine must read its key exactly this way, and the view's `@AppStorage` default must match bit-for-bit (gated by `FeatureKeyDefaultsTests`, mentioned in CLAUDE.md §2).
- `ShortcutCatalog.swift` (287 lines): pure, Foundation-only, `Chord`/`Modifiers`/`Scope` (`.global`/`.whenXFinderFrontmost`/`.finderOnly`) and an `Entry` struct keyed by gate — any new global hotkey must get a catalog entry so the "Phím tắt" clash-check page sees it.
- `SidebarDestination` (not opened directly, but referenced throughout — e.g. `AppState.swift:107`, `XFinderApp.swift:207`) — CLAUDE.md §2 lists the fixed group taxonomy (CHUNG/NOTCH/CỬA SỔ/FINDER & TÌM KIẾM/CÔNG CỤ/KẾT NỐI/TIỆN ÍCH); a file-browser page would likely join **FINDER & TÌM KIẾM** or get `CÔNG CỤ`, per CLAUDE.md's design rule "one page, one job sentence" (§3.1 rule 1).
- `L10n.t("literal")` (`XFinder/Core/L10n.swift:57-65`): keys are the literal Vietnamese source text itself, looked up through `L10nStore.fragments`/`.sentences` (fragment-first). Any new UI string must route through `L10n.t()` directly at the view, never pre-rendered by a model (CLAUDE.md §3.2 rule 8, echoed in `L10n.swift`'s own header comment lines 20-29 about a "language leaked four times" history). New keys get added via a dedicated `scripts/add-<feature>-l10n-entries.py` script (23+ precedents found, e.g. `scripts/add-connect-catalog-l10n-entries.py`) — add-only, conflict-checked against existing keys with different meaning.

### 4. Hard project rules the new feature must satisfy (from CLAUDE.md)

1. **"8 things per feature"** (CLAUDE.md §2, "Một tính năng = đủ 8 thứ"): (1) `FeatureCatalog` row with real `IdleCost`; (2) ONE reader in Core (`UserDefaults.standard.object(forKey:) as? Bool ?? default` for Bool; `string(forKey:) ?? "lit"` for String); (3) view `@AppStorage` with the same default; (4) `FeatureKeyDefaultsTests` row; (5) `FeatureContractTests` row with `.pure([...])` of symlinked pure files (exemption count ≤ 6 and only ever decreasing — confirmed live in `Tests/XFinderLogicTests/FeatureContractTests.swift:27-32`); (6) a `FeatureHub.applySettings` case called from `XFinderApp` at both launch and `didBecomeActive`; (7) an L10n key via an add-only script; (8) a mutation-harness entry whose target file is inside that harness's `FILES` list (confirmed pattern: `scripts/mutation-check-search.sh:14` sets `FILES="XFinder/Core/NulRecords.swift"`).
2. **pbxproj hand-editing**: every new Swift file needs exactly 4 lines added by hand — `PBXBuildFile`, `PBXFileReference`, group-children entry, Sources-phase entry (confirmed 4 matching lines for `Archive/ArchiveEngine.swift` at `XFinder.xcodeproj/project.pbxproj:311,576,888,1458`); resource files need a `PBXResourcesBuildPhase` entry too; new 8-hex ids must be chosen from gaps (`7F1A0xxx`), never by taking "max id"; paths containing `+` need quoting; run `plutil -lint` after each edit; check the compile log **by filename**.
3. **Pure files symlinked into `Tests/`**: logic files (rules/engines like `FileSearchEngine`, `NulRecords`, `FileWalk`, `BatchRenameEngine`, `ArchiveEngine`) must stay Foundation-only (no `import SwiftUI`, which CLAUDE.md says "is forbidden in a rule file") and get a real symlink into `Tests/XFinderLogicTests/` (confirmed: 119+ existing symlinks, e.g. `Tests/XFinderLogicTests/SafeArithmetic.swift`).
4. **L10n gates**: six scripts must pass with 0 — `check-l10n-coverage.py`, `check-l10n-duplicates.py`, `audit-l10n-literals.py`, `audit-l10n-interpolations.py`, `check-sidebar-groups-l10n.py`, `audit-gesture-vocabulary-l10n.py` — plus `verify-l10n-runtime.py` against the **installed bundle** (not source) must show 0 leaked literals.
5. **Mutation harness discipline**: a feature's harness must only mutate files listed in its `FILES=` variable; mutation-green must mean either the test doesn't gate that line, the mutant is semantically equivalent, or it's an anchor-only line; harnesses run sequentially and detached (`nohup … &`), restore via `cp` from backup (not regeneration), with `trap 'restore' EXIT`.
6. **ONE reader per key** (CLAUDE.md §3.2 rule 7): confirmed live pattern throughout — e.g. `ClipboardShelfController.swift:69,77,82,87,93` each comment-labels itself "the ONE reader of ..." for a specific key; a new file-browser feature must not add a second reader of any key it introduces.
7. **Four separate gate results always reported**: build · test · mutation · real run — "never 'works' just because it compiled" (CLAUDE.md §1 reporting rule).
8. **Token-only styling**: `XFinderTokens` (seen throughout `DropTrayDetailView.swift`, e.g. `.font(XFinderTokens.Font.pageIcon)` line 45, `.cornerRadius(XFinderTokens.Radius.tile)` line 58) — no literal colors/numbers in views; `audit-ui-tokens.py` gate must show 0.
9. **User-data safety rules** (§3.2 rule 9): never `rm` (use Trash — confirmed `FileManager.default.trashItem` used in `DropTrayDetailView.trashAll():289` and `ActionHistoryStore` undo path), read pipes before `waitUntilExit()` (confirmed correctly done in `ArchiveRunner.run():62-63`), text through stdin/JSON not argv.
10. **arm64-only, Swift 6 strict concurrency, macOS 14+**: any new engine must be `Sendable`-correct (`FileSearch` is declared `final class FileSearch: Sendable` with a comment "không trạng thái dùng chung", `FileSearch.swift:9`) and callback code arriving off-main must hop via `runOnMainActor`/`Task { @MainActor in }`, never `@unchecked Sendable` except the already-existing, justified `Locked<T>` (`AppState.swift:8`) and `LRUThumbnailCache` (`ScreenCaptureProvider.swift:12`).

### 5. Not verified in this pass

- `CloudSyncController.swift`, `FolderSyncController.swift`, `NotchPages.swift`/`NotchSurfaceLayout.swift` internals (drop-tray notch integration details beyond what `DropTrayDetailView` shows), `ClipboardPasteEngine.swift`'s icon-cache usage (only grep-matched, not read), and the full `FeatureCatalog.swift`/`FeatureHub.swift`/`ShortcutCatalog.swift` bodies beyond the excerpts shown — these were listed in the task but only grepped/partially read, not fully inspected line-by-line. No build, test, or mutation run was performed (task is audit-only); no "chưa verify" claims above should be read as measured — they are static-read findings only.


## 3. Số đo API trên máy này (M3 Pro, macOS 27.0.1)

All probes compiled once with `swiftc -O` and sources/binaries preserved. Here is the dense structured report.

# FileOctopus-inspired File Browser — Native Mechanism Measurements

**Machine**: Apple M3 Pro, 12 cores, 36 GB RAM, macOS 27.0.1 (26A434), arm64, APFS SSD (`/dev/disk3s1`, 460 GiB, 108 GiB free). Swift 6.4 (swiftlang-6.4.0.34.1). All probes in `/private/tmp/claude-502/-Users-wolong-github-XFinder/ec69d774-f3f3-4e1f-91f8-7b0e4b40a2f7/scratchpad/fo/apis/*.swift`, each compiled **once** with `swiftc -O <file>.swift -o <file>` (never `swift file.swift`). XFinder-claude repo was not touched (read-only, no edits/commits).

## 1. Directory listing speed + attributes

Probe: `/private/tmp/claude-502/-Users-wolong-github-XFinder/ec69d774-f3f3-4e1f-91f8-7b0e4b40a2f7/scratchpad/fo/apis/listprobe.swift`. Median of 5 runs, `CLOCK_MONOTONIC`. Test dirs created with `/usr/bin/python3 -I` loop (20 000 files in 0.82 s, 100 000 in 4.89 s). Positive control `pc3/` (3 files, one `._c.txt`) run before every target — see dot-underscore column.

**Dot-underscore positive control** (`pc3`: 2 normal + 1 `._c.txt`): `FileManager.contentsOfDirectory`/`.enumerator` report count=2, saw=false; `fts`/`opendir+lstat`/`getattrlistbulk` report count=3, saw=true. **Confirms CLAUDE.md's claim**: FileManager-based APIs hide `._*` files on macOS 27; the three POSIX-level methods do not.

| Method | 20 000 flat files | 100 000 flat files | /System/Library/Frameworks (340 entries) | /usr/bin (932 entries) | hides `._*` |
|---|---|---|---|---|---|
| `FileManager.contentsOfDirectory` + resourceValues | 165.8 ms | 813.2 ms | 5.87 ms | 10.27 ms | yes |
| `FileManager.enumerator` (shallow) | 145.9 ms | 724.2 ms | 4.69 ms | 8.77 ms | yes |
| `fts(3)` FTS_NOCHDIR (shallow, FTS_SKIP on subdirs) | 22.3 ms | 109.5 ms | 0.65 ms | 1.27 ms | no |
| `opendir`/`readdir` + `lstat` | 41.5-42.0 ms | 215-217 ms | 0.56 ms | 4.06 ms | no |
| `getattrlistbulk(2)` | 19.7-20.6 ms | 96.4-99.3 ms | 0.21 ms | 0.89 ms | no |

**`getattrlistbulk` is fastest everywhere** (~7-8x faster than FileManager at 100k files, ~2x faster than fts). `fts` is second-fastest and simplest to get right. FileManager is consistently the slowest (3.3-7.5x the getattrlistbulk time), plus it silently drops dot-underscore files — a correctness risk for a file browser that must show them.

**Bug found and fixed during measurement**: initial `fts` implementation double-counted and recursed into subdirectories (FTS_PHYSICAL visits each dir at `FTS_D` pre-order and `FTS_DP` post-order at the same `fts_level`); fixed by checking `fts_info != FTS_DP` and calling `fts_set(ftsp, ent, FTS_SKIP)` on directories to keep the listing shallow. Before the fix, Frameworks reported count=671 (recursed) instead of 340 — caught because the same count should equal the already-validated `FileManager`/`opendir` counts.

**Recommendation**: use `getattrlistbulk(2)` as the primary listing engine (bulk syscall, no per-entry `stat`, returns name+type+size+mtime in one buffer walk); use `fts(3)` as the simpler fallback/recursive-walk path; treat `._*` visibility as a deliberate per-view toggle built on the POSIX layer, never rely on FileManager for "show hidden files."

## 2. Change notification latency

Probe: `.../apis/notifyprobe.swift`. Median create→callback latency over 10 runs each, positive-control warm-up before each series.

| Mechanism | Positive-control warm-up | Median latency (10 runs) | Success rate |
|---|---|---|---|
| `DispatchSource.makeFileSystemObjectSource` (dir fd, `.write` mask) | 0.461 ms | **0.521 ms** | 10/10 |
| `FSEventStream` (`kFSEventStreamCreateFlagFileEvents`) | 12.514 ms | **11.884 ms** | 10/10 |

DispatchSource is ~23x lower latency for single-directory watching. FSEventStream's ~12 ms overhead is consistent with its design (coalesces at the `fsevents` kernel device + XPC round trip to `fseventsd`), but it's the only mechanism that works recursively across a whole subtree without opening an fd per directory.

**Bug found and fixed**: first attempt force-cast the `eventPaths` callback argument to `CFArray`, causing an immediate segfault — `kFSEventStreamCreateFlagFileEvents` without `kFSEventStreamCreateFlagUseCFTypes` delivers `eventPaths` as a raw C `char**`, not a `CFArray`. Fixed by reading it as `UnsafePointer<UnsafePointer<CChar>>` and building `[String]` manually.

**Recommendation**: `DispatchSource` per open directory for the currently-visible pane(s) (lowest latency, matches "ONE reader per key" architecture pattern already used in XFinder); `FSEventStream` for background/recursive watching of non-visible trees (e.g. sidebar favorites, search index) where the ~12 ms extra latency doesn't matter but fd-per-directory would not scale.

## 3. Copy with progress, pause/resume, clonefile, verify

Probes: `.../apis/copyprobe.swift` (progress/pause/quit/verify) and `.../apis/cloneprobe.swift` + `.../apis/cloneflag.swift` (clonefile isolation). 1 GiB / 512 MiB / 256 MiB random-content scratch files, deleted after each probe run (confirmed: `du -sh` on scratch dir after all runs = 716 K, no leftover big files).

**copyfile(3) + COPYFILE_STATE_STATUS_CB** (1 GiB, random data defeats any compression/sparse shortcut):
- `rc=0`, elapsed 907.2 ms incl. deliberate 500 ms pause → ~1129 MB/s effective.
- 1024 callbacks fired, `sawProgress=true` (`COPYFILE_STATE_COPIED` increased monotonically across calls).
- **Pause/resume confirmed**: sleeping 500 ms inside the callback (`usleep(500_000)`) measured 505.1 ms actual block — **the callback thread blocking does pause the copy**, and the copy resumes normally afterward (byte-identical result, `rc=0`).
- **COPYFILE_QUIT**: returning `COPYFILE_QUIT` from the callback after 3 progress calls → `copyfile()` returns `rc=-1`, `errno=89` (`ECANCELED`), and **the partial destination file does not exist at all** (`FileManager.fileExists=false`) — copyfile cleans up its own partial output on cancel, confirmed via `stat()` failing on the destination path.

**clonefile / APFS CoW** — `st_blocks` was NOT a usable signal (even an explicit, unambiguous `clonefile(2)` syscall reports `st_blocks` equal to full logical size on this volume/macOS version — Apple's CoW block-sharing isn't reflected in `stat()` here). **Elapsed time is the reliable signal**:

| Call | 256 MiB elapsed | Implied MB/s | Verdict |
|---|---|---|---|
| `clonefile(2)` direct syscall (positive control) | 0.94 ms | n/a (clone) | clone |
| `copyfile(COPYFILE_DATA)` plain | 121.1 ms | ~2100 MB/s | real copy |
| `copyfile(COPYFILE_DATA \| COPYFILE_CLONE)` | 0.16 ms | n/a (clone) | clone |
| `copyfile(COPYFILE_DATA \| COPYFILE_CLONE_FORCE)` | 0.09 ms | n/a (clone) | clone |
| `copyfile(COPYFILE_ALL)` (no explicit CLONE flag) | 115.6 ms | ~2200 MB/s | real copy (does NOT auto-clone) |
| `FileManager.copyItem(atPath:toPath:)` | 0.2-0.21 ms | n/a (clone) | **clones** |
| manual `read()`/`write()` loop (ground truth, cannot clone) | 56-105 ms | ~2400-4900 MB/s | real copy |

**Correction to a prior assumption**: `copyfile(COPYFILE_ALL)` alone does **not** auto-clone on this macOS 27 build — it must be given `COPYFILE_CLONE` or `COPYFILE_CLONE_FORCE` explicitly. `FileManager.copyItem` is consistently ~0.2 ms regardless of file size tested (256 MiB-1 GiB), meaning **Foundation passes `COPYFILE_CLONE` (or equivalent) internally** — confirmed by matching its timing signature to the explicit-flag runs, not to the plain-flag runs.

**To force a non-clone copy** (e.g., "duplicate and immediately diverge" semantics, or testing real throughput): use a manual `read()`/`write()` loop, or `copyfile()` with flags that exclude `COPYFILE_CLONE`/`COPYFILE_CLONE_FORCE` — but note `FileManager.copyItem` cannot be told not to clone; a file browser needing guaranteed non-CoW duplication must call `copyfile(3)` directly with explicit flags.

**Cross-volume (EXDEV) fallback**: **not measured** — no second writable APFS volume was available in this environment. Documented (Apple header comments, not verified here): `clonefile(2)` fails `EXDEV` across volumes; `copyfile(3)` transparently falls back to a real byte copy.

**Verify throughput** (1 GiB, positive control = 1-byte corruption at offset 12345, both methods correctly flagged mismatch):

| Method | Elapsed | MB/s | Detects corruption |
|---|---|---|---|
| SHA-256 (CryptoKit, 4 MiB chunks) | 433-434 ms | ~2360 MB/s | yes (confirmed via corrupted-copy control) |
| Byte-for-byte compare (4 MiB chunks) | 453.9 ms | ~2256 MB/s | yes (confirmed) |

SHA-256 and byte-compare have nearly identical throughput on this hardware (both I/O-bound, not CPU-bound — M3 Pro's SHA extensions keep hashing from being the bottleneck). **Recommendation**: prefer SHA-256 for verify — same speed as byte-compare but produces a storable/comparable digest (useful for later re-verification, dedup, or cross-session integrity checks) rather than requiring both files to be present simultaneously.

**Swift/C-interop pitfalls found and fixed** (useful for whoever implements this for real): `copyfile_callback_t`'s C signature takes `const void *` for both the callback and context slots of `copyfile_state_set`; passing `&localVarHoldingPointer` for the **callback** slot is wrong and causes `EXC_BAD_ACCESS`/SIGBUS (confirmed via crash log backtrace: the crashing frame's symbol was literally the stack variable name, i.e. copyfile tried to **call the stack address as code**). Correct form: `unsafeBitCast(myFunc as copyfile_callback_t, to: UnsafeRawPointer.self)` for the callback, and the plain `UnsafeMutableRawPointer` value itself (not `&localVar`) for the context.

## 4. Cloud status (iCloud Drive / OneDrive)

Probe: `.../apis/cloudprobe.swift`, read-only. **`startDownloadingUbiquitousItem`/`evictUbiquitousItem` were never called** (would mutate the owner's real iCloud/OneDrive data — explicitly out of scope). xattr **names only** printed, never values. Google Drive and Dropbox confirmed not installed (not probed).

Positive control (plain local file, `/private/tmp/cloudprobe_local_control.txt`, outside any cloud folder): `isUbiquitousItem=nil`, no ubiquitous status, xattr names = `["com.apple.TextEncoding"]` only — confirms the resource-value keys read real state, not stale/cached values.

| Path | isUbiquitousItem | downloadingStatus | isDownloading | isUploaded | fileSize | totalFileAllocatedSize | xattr names |
|---|---|---|---|---|---|---|---|
| iCloud `Lumen/Inbox.md` | true | NotDownloaded | false | true | 100 | 0 | `com.apple.provenance` |
| iCloud `Lumen/Todo List.md` | true | NotDownloaded | false | true | 165 | 0 | `com.apple.provenance` |
| iCloud `My Home/*.jpg` | true | NotDownloaded | false | true | 183024 | 0 | `com.apple.lastuseddate#PS`, `com.apple.quarantine` |
| OneDrive `Documents` (empty placeholder dir) | nil | nil | nil | nil | nil | nil | (none) |
| OneDrive-Personal root | nil | nil | nil | nil | nil | nil | `com.apple.file-provider-domain-id` |

**Key finding**: `NSURLUbiquitousItem*` resource keys only work for genuine iCloud Drive items (Apple's own `NSFileProviderExtension` for `com.apple.CloudDocs`). **OneDrive reports `nil` for every ubiquitous key** — it's a third-party File Provider, not Apple's iCloud domain, so a file browser must detect OneDrive/Dropbox/etc. sync state via a different mechanism: the `com.apple.file-provider-domain-id` xattr presence (confirmed present on the OneDrive root) is the generic File Provider signal, but per-file download/sync status for non-Apple providers needs the `FileProvider`/`NSFileProviderManager` APIs or provider-specific UI badging (Finder Sync extension status), not `URLResourceValues`.

iCloud files show `fileSize` populated (metadata known) while `totalFileAllocatedSize=0` (no local blocks) and `downloadingStatus="NotDownloaded"` — this is the standard "placeholder, not yet materialized" state, readable without downloading.

## 5. Icon loading

Probe: `.../apis/iconprobe.swift`. Positive control: `/usr/bin/ls` icon fetched first, size=(32,32) with 32 representations confirms non-empty real icon data before trusting batch numbers.

| Method | Count | Elapsed | Per-item |
|---|---|---|---|
| `NSWorkspace.icon(forFile:)`, uncached | 1000 files (932 `/usr/bin` + 68 flat `.dat`) | 59.8 ms | 0.060 ms |
| `NSWorkspace.icon(for: UTType)`, cache keyed by type incl. per-file contentType lookup | 1000 files, 9 distinct types, 991 cache hits | 50.8 ms | 0.051 ms |
| same, but with UTType pre-computed (isolates pure icon-cache cost) | 1000 lookups, 9 types | 0.227 ms | 0.0002 ms |
| `QLThumbnailGenerator.generateBestRepresentation`, 50 real images (`.heic`), concurrent | 50 | 373.6 ms | 7.5 ms (concurrent) |
| same, single isolated request (positive control) | 1 | 5.5 ms | 5.5 ms |

**`icon(forFile:)` is already fast per-call (~0.06 ms)** on this machine/macOS version — the per-type-cache version only wins once the per-file `contentType` resourceValues lookup is removed from the critical path (0.227 ms total vs 59.8 ms when the type is already known from the listing pass, e.g. from `getattrlistbulk`'s `ATTR_CMN_OBJTYPE`/extension). **Recommendation**: during a `getattrlistbulk`/`fts` listing pass, derive UTType from the file extension (cheap, no extra syscall) and cache `NSImage` per UTType identifier; this collapses icon cost for 1000 files from ~60 ms to a fraction of a millisecond. QLThumbnailGenerator is the right tool for real image/document thumbnails (not generic icons) — ~5-7 ms per image even concurrently, so a visible grid of thumbnails should request them lazily per visible cell, not eagerly for the whole folder.

## What was NOT verified

- Cross-volume `clonefile`/`copyfile` EXDEV fallback behavior (no second writable volume available).
- `COPYFILE_QUIT` behavior when the copy is mid-flight on a genuinely slow device (test used local SSD, so "partial file" window was narrow — only 3 callbacks before quit).
- OneDrive/Dropbox per-file download-progress API (OneDrive app not generating `NSURLUbiquitousItem*` values; would need `FileProvider` framework APIs, not tested here since calling download/evict calls was explicitly prohibited and read-only enumeration of OneDrive's actual sync state wasn't available via the tested keys).
- `getattrlistbulk` behavior on non-APFS volumes (e.g. network/SMB shares) — only tested on local APFS.
- Real end-to-end UI responsiveness (all numbers are backend/syscall timing, not measured inside an actual XFinder UI build).

**Files**: all probe sources and compiled binaries remain at `/private/tmp/claude-502/-Users-wolong-github-XFinder/ec69d774-f3f3-4e1f-91f8-7b0e4b40a2f7/scratchpad/fo/apis/` (`listprobe`, `notifyprobe`, `copyprobe`, `cloneprobe`, `cloneflag`, `cloudprobe`, `iconprobe` + matching `.swift`). Test directories `big/d20000` and `big/d100000` (flat empty files) remain under `/private/tmp/claude-502/-Users-wolong-github-XFinder/ec69d774-f3f3-4e1f-91f8-7b0e4b40a2f7/scratchpad/fo/big/`. No files were created, modified, or deleted outside the scratch directory; `/Users/wolong/github/XFinder-claude` was not touched.


## 4. Checklist Finder

# Finder-Parity Checklist — for "XFinder File Browser" (vs. FileOctopus)

**Sources**: Apple Support 102650 "Mac keyboard shortcuts" fetched live (2026-10-24) via WebFetch — Finder section quoted verbatim below. FileOctopus feature/claims fetched live from fileoctopus.com same session. All other behavioral detail (drag modifiers, rename rules, spring-loading, volumes, packages, iCloud placeholders) is from direct knowledge of macOS 14/15 Finder — **not independently re-probed this session** (task forbids launching/sending events to GUI apps, so no live AX/CGEvent verification was done; flagged where it matters). Scratch notes: `/private/tmp/claude-502/-Users-wolong-github-XFinder/ec69d774-f3f3-4e1f-91f8-7b0e4b40a2f7/scratchpad/fo/claude/sources.md`.

## 0. Context on the model (FileOctopus)

FileOctopus (macOS 15+, Swift+AppKit, Apple Silicon only, 8 MB download / 22 MB installed) explicitly claims Finder-shortcut parity ("works the way Finder does, nothing to relearn") and layers on: up to 16-pane split view, natural-language local search ("29x faster" than Finder search on names-only, 0.27s vs 7.7s on 146k files/M3 Max), a File Shelf, Workspaces, persistent cross-launch undo (20 steps/24h), copy/move queueing, conflict dialogs (Keep Both/Replace/Stop), folder-merge preview, Quick-Open palette (⌃⌘P), and Google Drive/Dropbox sidebar integration — most "PRO"-gated. **Important nuance it states itself**: its search is filename-only while Finder's ⌘F also searches content — a fair target for XFinder to beat on both axes, not just names.

---

## 1. Keyboard shortcuts a Finder-like window must honour

| Shortcut | Apple-documented behaviour | Failure if cloned wrong |
|---|---|---|
| ⌘↑ | "Open the folder that contains the current folder" | Users lose the primary vertical-navigation muscle memory; must select the child they came from when landing in parent |
| ⌃⌘↑ | Opens the containing folder in a **new window** | Confusing if it reuses current window instead of opening new |
| ⌘↓ | "Open the selected item" | Must work identically to double-click, incl. on folders, apps, docs |
| ⌘[ / ⌘] | Back/forward through navigation history ("previous/next folder") | Breaks if history isn't per-window, or if it conflates with file-system parent/child nav |
| ⌘⌫ | "Move the selected item to the Trash" | Must never hard-delete; must support multi-select; must respect "Warn before emptying/removing" prefs if cloned |
| ⇧⌘⌫ | Empty Trash (with confirmation) | — |
| ⌥⇧⌘⌫ | Empty Trash **without** confirmation dialog | Skipping this variant breaks power-user flow |
| ⌘D | "Duplicate the selected files" | Must produce "name copy", "name copy 2" sequencing in same folder, not overwrite |
| ⇧⌘N | "Create a new folder" | Must open with name pre-selected for immediate rename (inline, no dialog) |
| ⌃⌘N | New folder **containing the currently selected items** (Apple's "common shortcuts" list) | Distinct from ⇧⌘N — often missed entirely by clones |
| ⌘I | "Show the Get Info window for a selected file" | Must be non-modal, one window per item, live-updating (e.g. size recalculates) |
| ⌥⌘I | Opens a **single combined** Inspector-style info window for multi-selection (vs one window per item) — not explicitly in the fetched page text but standard Finder behavior; **flag as needing live re-verification** | Easy to miss distinct behavior from plain ⌘I on multi-select |
| Return | Rename the selected item in place | Must NOT open the item (that's ⌘O/⌘↓) — a very common clone bug swaps these |
| Space | Quick Look preview | Must support flipping through multi-selection with arrow keys while QL panel is open; ⌥⌘Y = QL **slideshow** |
| ⌘Y | "Use Quick Look to preview the selected files" | Same panel, different trigger; both must map to identical QL instance |
| Type-to-select | Typing characters jumps to/filters matching filename, accumulates within a short timeout, resets on pause | Must reset buffer after ~1s idle; must wrap-search; case-insensitive; a common clone bug is treating each keystroke as a fresh single-character jump (breaks multi-letter typing) |
| Arrow keys (icon view) | Up/Down/Left/Right move selection spatially by icon grid position | Spatial, not index-based — must account for wrapped rows |
| Arrow keys (list view) | ↑/↓ moves selection; **Right Arrow** opens (expands) selected folder's disclosure triangle; **Left Arrow** closes it | List-view arrows are fundamentally different from icon-view arrows — cloning icon-view logic for list view is a classic bug |
| Arrow keys (column view) | Right advances into a column (opens folder in next column), Left retreats a column | Must not confuse with list-view disclosure-triangle semantics |
| ⌥+click disclosure triangle | Opens **all** nested folders within the selection (list view only) | Shallow single-level expand-all is a common wrong implementation |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Icon / List / Column / Gallery view | Must persist per-folder (Finder remembers view-mode per directory via `.DS_Store`-equivalent) unless "Always open in" global default is set |
| ⌘J | Show View Options (per-view, per-folder settings: icon size, grid spacing, sort key, label, info/icon preview checkboxes) | Must scope to the frontmost folder, not global, unless user clicked "Use as Defaults" |
| ⌘T (with ≥2 tabs) / ⇧⌘T | ⌘T: new tab (when no tabs open, toggles tab bar per Apple's note); ⇧⌘T: show/hide tab bar | Tab semantics are context-dependent — must replicate the "first ⌘T shows bar" nuance |
| ⌘-click on window title | "See the folders that contain the current folder" (path breadcrumb popup menu) | Must list full path hierarchy up to Computer/volume root, each entry navigable |
| ⌘-double-click a folder | "Open a folder in a separate tab or window" | — |
| ⌘F | Start Spotlight search scoped to the Finder window/location | Scope toggle ("This Mac" vs "<folder>") must persist like Finder's |
| ⇧⌘G | "Open a Go to Folder window" (type a path, supports `~`, `/`, tab-completion) | Must resolve symlinks/aliases typed as paths the same way |
| ⇧⌘. (period) | Show/hide hidden files (toggle, not in the fetched official list but standard global Finder shortcut since 10.11) | Must affect only Finder's view, not touch file flags; must persist across relaunch per Finder's actual behavior (it does NOT persist — resets each launch) — a clone that persists it diverges from real Finder |
| ⌘⇧. interaction with dotfiles vs `chflags hidden` | Both hidden-file types must merge in one listing | Two different hidden mechanisms (leading dot vs UF_HIDDEN flag) — showing only one is a common bug |
| ⌥⌘C | Copy path (not in the official Apple list fetched — this is a newer/macOS Sonoma+ Edit-menu "Copy as Pathname" via ⌥ held in Edit menu) | **Flag: not in the fetched Apple page; verify independently** — if offered, must emit POSIX path, not file:// URL |
| ⌘C / ⌥⌘V | Copy, then **Move** here (paste-as-move) — confirmed in fetched text: "moves clipboard files to the current location instead of copying" | A clone that implements only Paste (⌘V, always copy) and omits ⌥⌘V breaks a very common power workflow |
| ⌘V | Paste (copy) | Must handle cut-markers if "Cut" (there's no real Finder "Cut" — only copy + ⌥-paste-move) correctly — do not add a fake "Cut" that conflicts with this model |
| ⌃⌘A | "Make an alias of the selected item" | True alias (resolves if original moves/renamed), not a symlink — see §3 |
| ⌃⌘T | Add selected item to the Sidebar | — |
| ⌃⇧⌘T | Add selected item to the Dock | — |
| ⌘E | Eject selected disk/volume | Must warn/block if files are open on it; must not eject internal boot volume |
| ⌘K | Open "Connect to Server" | Network volume mounting — out of scope for most clones but part of "100% Finder" |
| ⌘R | Context-dependent: show original for alias / refresh Smart Folder / resume AirDrop | Three distinct behaviors multiplexed on one shortcut — must dispatch by selection type |
| ⇧⌘P | Show/hide Preview pane | Column-view-adjacent sidebar — distinct from Quick Look panel |
| ⌥⌘P | Show/hide path bar (bottom breadcrumb strip) | — |
| ⌥⌘S | Show/hide Sidebar | — |
| ⌘/ | Show/hide status bar (item count, free space) | Must recompute live as selection changes | 
| Option-key while dragging | Copy instead of move (when same-volume) | See §2 — direction matters |
| ⌘ while dragging to another volume | Forces **move** instead of the cross-volume default copy | Classic bug: clones often hardcode "same-volume=move, cross-volume=copy" and forget the modifier override |
| ⌘ or ⇧ while clicking | Multi-select (⌘ = toggle individual, ⇧ = contiguous range) | Must support range-extend from last-clicked anchor, not from focus |

---

## 2. Drag-and-drop modifier semantics (critical, easy to get backwards)

| Gesture | Same volume | Cross volume | Failure mode if wrong |
|---|---|---|---|
| Plain drag | **Move** | **Copy** | This default flip trips up almost every clone that treats drag uniformly |
| ⌥ (Option) held | Forces **Copy** | Copy (no change — already copy) | Must show the green "+" badge cursor only when Option actually forces a copy that wouldn't otherwise happen |
| ⌘ (Command) held | No effect (already move) | Forces **Move** | Must NOT show move cursor on same-volume ⌘-drag since it's already the default — but must honor it cross-volume |
| ⌥⌘ held | Creates an **alias** at destination, original untouched | Same | Cursor shows curved-arrow alias badge; a clone that silently copies instead of aliasing breaks a documented workflow |
| Drag onto an app icon (Dock or Finder) | Opens the file with that app (not moved) | Same | Must distinguish "drop ON an app" (open-with) from "drop into a folder" |
| Drag onto a folder/volume icon itself (vs. opening it) | Moves/copies into it without opening | — | Target-highlighting (blue outline) must appear only over valid drop targets |
| Drag out of Trash | Restores item (Put Back semantics) if original location still exists | — | If original folder was deleted, Finder's real behavior falls back to prompting/placing on Desktop — a naive clone may silently fail or crash |
| Spring-loaded folders | Hovering a drag over a closed folder/tab (without dropping) for a short delay (configurable; default ~0.5–1.5s via Finder prefs/trackpad force-click shortcut) auto-opens it in place, stacking a navigation trail so moving back out collapses correctly | Must support both time-based spring AND the "press space while hovering" instant-spring; must restore the original window state when drag is cancelled (Esc) |
| Dragging between two panes/windows of the same app | Same move/copy-by-volume rule applies — NOT automatically a "copy" just because it's the same app | A multi-pane clone (FileOctopus's whole pitch) must not special-case "same app = always copy"; real Finder judges purely by volume |
| Drag a selection that mixes files already in Trash + regular files | Undefined/blocked in real Finder — cannont drag mixed | Should reject or split the operation explicitly, not silently misplace half |

---

## 3. Column view

- Each column is independently resizable by dragging the handle at its right edge; resizing one column does not reflow others.
- Column widths can be set to auto-size to content via double-click-drag divider (standard AppKit behavior) and persist per-folder.
- Preview column (rightmost) shows Quick-Look-style preview + metadata for single selection; for multi-select it shows aggregate info (count, total size).
- Navigating forward with Right Arrow opens the next column; selecting a different item in a column truncates all columns to its right (classic "miller columns" semantics) — **a common clone bug is not truncating stale columns** when the user clicks back into an earlier column and picks a different child.
- Resizing the whole window should proportionally keep/reflow columns, not just stretch the last one.

## 4. List view

- Disclosure triangles allow expanding folders inline without changing directory (tree-in-list); state (expanded/collapsed per folder) should persist within the same window session at minimum.
- Columns: Name, Date Modified, Date Created, Size, Kind, plus optional ones (Date Last Opened, Version, Comments, Tags, etc.) — user-configurable via ⌘J → "Show Columns", with column order draggable and widths resizable by dragging dividers.
- Click a column header to sort by it; click again to reverse direction; the active sort column shows a direction indicator (chevron).
- Sorting must be stable and correct for: name (natural/numeric-aware — "File 2" before "File 10"), size (actual bytes, not displayed rounded units), kind (localized type string), date (actual timestamp, not displayed granularity).
- "Keep arranged by" / Sort vs. manual icon placement is a separate concept (icon view specific) — do not conflate grouping with simple sort.

## 5. Selection model

- Single click selects and clears prior selection (unless ⌘/⇧ held).
- ⇧-click extends a contiguous range from the last "anchor" item (not the most recently added item if ⌘-clicks were interspersed).
- ⌘-click toggles individual item membership without disturbing the rest of the selection.
- Drag a rubber-band selection rectangle in icon/gallery view (and in the empty area of list/column view) to multi-select.
- ⌘A selects all in current folder/window.
- Selection must survive a view-mode switch (icon→list→column) referencing the same underlying items.
- Deleting/moving a selected item should sensibly move the selection to a neighbor, not clear it to nothing (real Finder does advance selection, e.g., after Trash).

## 6. Rename rules

- Return (or single click on an already-selected item's name after a pause, i.e. "slow double-click") enters inline rename; Finder selects the filename stem but **not the extension** by default, so the user can retype just the name — this is a very frequently botched detail.
- Typing `:` (colon) in a name is silently translated — the Finder/HFS+ legacy rule converts `:` to `-` on display/storage boundary (colon is the path separator in classic Mac OS, disallowed in APFS/HFS+ Finder-visible names) — a clone must reject or remap it, not just allow a raw colon that later corrupts path-based tooling.
- `/` (slash) is also disallowed in Finder-level renames (it's the POSIX path separator) — Finder blocks the rename with an alert ("can't contain a ':' or '/'" historically; current wording may differ, should be verified live).
- Leading `.` renames the item hidden (with a confirmation dialog warning this will hide the file) — a clone skipping the confirmation changes real user-facing behavior.
- Renaming an item to an existing sibling name should prompt an error/merge-dialog rather than silently overwrite — behavior differs between "rename collision" (blocked) vs. "move/copy collision" (prompts Keep Both/Replace/Stop in newer macOS, matching what FileOctopus also claims to offer).
- Renaming a package (.app, .pages, etc.) must preserve the extension's association with the bundle unless the user explicitly types a different extension, in which case Finder warns "if you change this extension, your document may open in a different application."
- Multi-selection rename (batch rename, triggered via right-click "Rename N items") offers Replace Text / Add Text / Format (name-index) strategies — distinct from single-item inline rename.

## 7. Trash / Put Back

- ⌘⌫ moves to `~/.Trash` (or the per-volume `.Trashes/<uid>` for external volumes), preserving enough metadata to support Put Back.
- Put Back (right-click in Trash, or drag back out) requires Finder to remember original parent folder; if that folder no longer exists, real Finder's fallback (place on Desktop with alert, or disable Put Back menu item) should be replicated or explicitly chosen and documented — guessing wrong here breaks user trust.
- Emptying Trash should request confirmation by default (⇧⌘⌫) with an override for silent (⌥⇧⌘⌫); "Warn before emptying the Trash" preference should be respected if cloned.
- Deleting from an external/network volume may bypass the macOS Trash (some filesystems don't support `.Trashes`) and ask for instant permanent deletion — must warn clearly, not silently hard-delete.

## 8. Aliases vs. symlinks vs. packages

- **Alias** (⌃⌘A / "Make Alias"): a Finder-level file (resource-fork/bookmark-data based) that keeps tracking its target even if the target moves or is renamed, resolved via `NSURL` bookmark data, not a path string. A clone implementing "alias" as a dumb symlink will break the moment the user renames the target — a very common correctness gap.
- **Symlink** (`ln -s`, created via shell/Process, not Finder's native UI): path-based, breaks silently if target moves; Finder still shows and follows these (curved arrow badge, same badge as alias) but they are NOT alias files — a clone must distinguish them when the user asks "what kind of pointer is this" even though the badge looks the same.
- **Packages** (`.app`, `.pages`, `.key`, `.numbers`, etc. — directories with `com.apple.package` UTI or known extensions): must display as a single opaque file, never auto-expand in-column/in-list without explicit "Show Package Contents" command — a clone that treats every directory identically will explode bundles into visible tree nodes, which is a glaring Finder-parity failure.

## 9. Hidden files & iCloud placeholders

- Dotfiles (`.foo`) and UF_HIDDEN-flagged files both hidden by default; ⇧⌘. toggles visibility and (per real Finder) **does not persist across relaunch** — resets to hidden each new Finder launch (worth explicitly deciding whether to match this quirk or "improve" it, but must be a conscious choice, not an accident).
- iCloud Drive placeholder files (not yet downloaded) show a cloud-with-down-arrow badge; opening or Quick-Looking them triggers download; a clone's file-size/metadata reads must handle the "not yet materialized" state (size may read as the eventual remote size or a placeholder stub) without crashing enumeration code expecting actual bytes.
- Evicting (removing local copy while keeping in cloud) is a distinct action from Trash — must not be conflated with deletion.

## 10. Permissions, volumes, network

- Permission-denied errors (reading a folder you don't have access to, e.g. another user's home folder or a sandboxed container) must surface Finder's standard "You don't have permission" alert, not crash or silently show an empty folder (which looks identical to "folder is genuinely empty" — ambiguity is the actual failure mode to avoid).
- TCC/sandboxing: a cloned file browser running as a normal (non-Finder) app may hit additional TCC prompts (Full Disk Access, Files and Folders per-folder consent) that real Finder doesn't, because Finder has blanket system entitlement — this is a structural parity gap worth flagging explicitly to the user as "cannot fully match without extra permission prompts," per the Honesty Rule rather than claiming silent parity.
- External volume eject: must check for open file handles / busy processes and show the real "disk in use" alert rather than force-unmounting.
- Network volumes (AFP/SMB/NFS mounts): enumeration and metadata reads can have multi-hundred-ms to multi-second latency per call — a clone must not block its main thread/UI per Swift 6 strict-concurrency rules (relevant to this app's own architecture: one reader per key, async I/O patterns already used elsewhere in the codebase) and must handle a volume going unreachable mid-browse (server sleep, Wi-Fi drop) without hanging the whole window indefinitely.

---

## Top 25 failure cases for the spec's failure table

1. Return renames instead of opening (or vice versa) — swapped Return/⌘O semantics.
2. ⌥-drag same-volume does NOT force copy (defaults wrong: treats all drags as copy, or all as move, ignoring volume).
3. ⌘-drag cross-volume does NOT force move (stuck on copy default).
4. ⌥⌘-drag does not create a true alias (silently copies instead).
5. Type-to-select treats each keystroke as independent jump instead of accumulating a buffer with timeout.
6. List-view Left/Right arrows reimplemented as icon-view spatial movement instead of disclosure-triangle collapse/expand.
7. ⌘[ / ⌘] history not implemented per-window (shared global history bleeds across windows).
8. ⌘↑ selects nothing / loses context of which child folder you came from.
9. Rename on Return selects the whole filename including extension (should select stem only).
10. Rename silently allows a `/` or raw `:` that corrupts the stored path or a later shell/tooling interaction.
11. Duplicate (⌘D) overwrites instead of auto-suffixing "name copy", "name copy 2".
12. ⌘⌫ permanently deletes instead of moving to Trash (data-loss class bug).
13. Put Back fails silently or hard-crashes when the original parent folder has since been deleted.
14. Package (.app/.pages/etc.) auto-expands into a visible file tree instead of staying opaque.
15. Alias implemented as a dumb symlink — breaks when the original file is renamed/moved.
16. Spring-loaded folders don't trigger on hover, or never collapse the navigation trail on drag-cancel (Esc).
17. Column view fails to truncate stale columns to the right when a different item is selected in an earlier column.
18. Hidden-file toggle (⇧⌘.) persists across relaunch when real Finder resets it (or vice versa — an unflagged behavioral divergence).
19. Dragging a mixed Trash + non-Trash selection is accepted and silently mishandles half the items.
20. Sort by Size/Date uses the displayed rounded value instead of the actual byte count/timestamp (ties sort inconsistently).
21. Natural sort order wrong ("File 10" sorts before "File 2").
22. Multi-select Get Info opens N separate windows when a combined summary (⌥⌘I behavior) was expected, or vice versa.
23. iCloud placeholder file crashes or hangs metadata/size reads before the file has materialized.
24. External volume eject force-unmounts without checking for open handles/busy processes.
25. Network volume going unreachable mid-browse blocks/hangs the UI thread instead of failing gracefully per-call (Swift 6 concurrency violation risk specific to this codebase's strict-concurrency rule).

---

## What I could not verify this session

- No live Finder or XFinder-claude GUI interaction was performed (task explicitly forbids launching/sending events to GUI apps) — every behavioral claim beyond the Apple-support page text is from prior knowledge, not re-measured.
- ⌥⌘C "Copy as Pathname" and the exact current wording of the `:`/`/` illegal-character rename alert were **not found in the fetched Apple page** and should be independently confirmed (e.g., via Apple's Finder Help pages or a live probe) before being written into a spec as fact.
- FileOctopus's own shortcut-parity claim ("works the way Finder does") was read only from its marketing page — no FileOctopus binary was inspected, so the 25 failure cases above are derived from Finder's documented/known behavior, not from an observed FileOctopus bug.
