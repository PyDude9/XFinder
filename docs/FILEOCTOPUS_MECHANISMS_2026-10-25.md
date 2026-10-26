# FileOctopus 1.0.4 (build 12) — cơ chế đo từ binary đã cài (2026-10-25)

Cách đo: `otool -L`, `nm -u`, `strings -a`, tên kiểu Swift (`_TtC…`), `plutil`, hình dạng (chỉ tên khoá) của
`session-v1.json` / `sidebar-v1.json`, `sqlite3 -readonly .tables` của hai chỉ mục. **Không** dịch ngược mã, **không**
đọc `Licensing/*`, không đọc dữ liệu người dùng trong chỉ mục. `rea`/Hopper không có trên máy. Mục đích: chép **cơ chế**,
không chép mã (CLAUDE.md §1 "làm y …").

## 1. Kiến trúc

- `com.nghialuong.fileoctopus`, macOS 15+, arm64, 22 MB; Sparkle (cập nhật), Sentry (crash), PostHog (analytics, opt-in),
  LemonSqueezy (license). AppKit thuần cho mọi bề mặt lớn: `NSOutlineView` (List có tam giác mở thư mục: `ListOutlineController`,
  `ListNode`), `NSCollectionView` + FlowLayout (Icon), `NSBrowser` (Column: `FinderColumnBrowser`), `NSSplitView`,
  `NSToolbar` + `NSToolbarItemGroup`, `NSPathControl` (Path Bar), `NSTokenField` (chip tìm kiếm), `NSSearchField`.
- Module Swift (tên kiểu đếm được): `BetterFinder` (224 kiểu UI), `FileSystemCore`, `FileOperationCore` +
  `FileOperationFlow` (queue, pause gate, problem log, undo history, journal), `WorkspaceCore` (store JSON cho sidebar /
  view options / recent / workspace, recovery snapshot), `SearchIndexing`, `SearchContent`, `SearchCore`,
  `TelemetryCore`, `CommerceCore`. Mỗi store có bản `Memory…` (test) + `JSON…`/`UserDefaults…` (thật).
- Đo hiệu năng trong app: `NavigationSignposts`, `SearchLatencyProbe`, `MainThreadWatchdog`, MetricKit hang diagnostics.

## 2. Mô hình phiên (session-v1.json) — **hai tầng tab**

```
windows[] { frame, selectedTab, tabs[] {                 ← tab của CỬA SỔ
  folder, viewMode, selectedNames, focusedPane,
  panes: split { axis: vertical|horizontal, fractions[], children[ split | pane ] }   ← cây chia tuỳ ý, tỉ lệ liên tục
    pane { selectedTab, tabs[] { folder, backStack[], selectedNames[], viewMode } }  ← tab của TỪNG NGĂN
}}
```
- Cây chia lồng nhau n-nhánh với `fractions` (kéo vạch chia), không phải preset cố định.
- Mỗi tab của ngăn lưu `backStack` (không lưu forward), `selectedNames` (chọn lại sau khi mở lại), `viewMode`.
- `sidebar-v1.json`: `favorites[{id, url, displayName}]`, `expandedSections`, `collapsedSections`, `isSidebarVisible`,
  `schemaVersion` — sidebar có phiên bản schema.

## 3. Liệt kê thư mục và theo dõi thay đổi

- Import: `opendir/readdir/fstatat/getattrlist/statfs` — **không** `getattrlistbulk`, không `fts_open`. XFinder dùng
  `getattrlistbulk` (100 000 tệp: 101 ms) — giữ, nhanh hơn readdir + stat từng tệp.
- `FSEventStreamCreate` cho chỉ mục (con trỏ `event_cursors.last_event_id` ⇒ mở lại app tiếp tục từ sự kiện cuối, không quét
  lại); `DirectoryChangeMonitor` / `DirectoryLoadCoordinator` cho ngăn đang mở.
- iCloud "dataless": `DatalessProbing`, `DatalessTreeScan`, `DatalessFlagPlaceholderProbe` — đếm `dataless_count`, không
  bao giờ ép tải để đọc.

## 4. Tìm kiếm — ba nguồn ghép lại

1. **Chỉ mục tên riêng** `~/Library/Application Support/FileOctopus/Search/Names/filename-index.sqlite` (WAL,
   `synchronous=NORMAL`): `search_roots(root_id, canonical_path, active_generation)`, `index_generation(root_id,
   generation, state building|active, item_count, denied_count, dataless_count, started_at, committed_at)`,
   `file_metadata(root_id, generation, path, name, file_identity, device, inode, link_count, size, mtime, ctime,
   content_type, flags, availability) WITHOUT ROWID PK(root_id, generation, path)`, `event_cursors`. Dựng lại = một
   **generation mới** ghi song song, đổi `active_generation` khi xong (không bao giờ có chỉ mục nửa vời); xoá cây con bằng
   khoảng `path >= ? AND path < ?`. Trong RAM: `PostingIndex`, `IndexRowSpool`, `FilenameIndexStore`.
2. **Khớp tên theo tầng** (`NameMatcher`, `MatchTier`: `exact` → `prefix` → … → `basenameFuzzy`, `fuzzyBudget`,
   `tierEndsAt`/`tierEndCause`): tầng rẻ trả kết quả trước, tầng fuzzy có ngân sách thời gian. "Filename, path and fuzzy
   search, and Spotlight results".
3. **Spotlight** (`NSMetadataQuery`, `SpotlightQueryEngine`): `kMDItemFSName/DisplayName/Kind/ContentType(Tree)/FSSize/
   FSCreationDate/FSContentChangeDate/LastUsedDate/DateAdded/UserTags/WhereFroms/TextContent`. Kết quả sống:
   `LiveSearchUpdates`, `VirtualResultsWatcher`, `SearchChangeBridge`.
4. **Nội dung (PRO)** `Search/Content/content-index.sqlite`: `content_fts USING fts5(body, alt,
   tokenize='unicode61 remove_diacritics 2')` (`alt` = chữ OCR từ ảnh), `documents(doc_id, root_id, identity, origin,
   path, device, inode, fingerprint, status, skip_reason, truncated, indexed_at)`, `root_runs`; xếp hạng
   `bm25(content_fts)`, đoạn trích `snippet(content_fts, -1, '', '', '…', 24)`; `PRAGMA secure_delete=ON` + FTS
   `secure-delete` (xoá tệp khỏi chỉ mục là xoá thật), `optimize`, `quick_check`, `wal_checkpoint(TRUNCATE)`. Trích xuất:
   PDFKit (`maxPDFPages`), Vision OCR, `maxStoredCharacters`. Kiểm tra FTS5 có mặt bằng một bảng `probe` lúc chạy.

## 5. Thao tác tệp

`copyfile` / `fcopyfile` / `clonefile` / `renamex_np` (đổi tên đổi hoa-thường an toàn), `NSFileCoordinator`
(`SystemFileCoordinator`), journal (`ProductionFileOperationJournalStore`) + snapshot + fingerprint để Undo và khôi phục
sau crash ("changed after the Undo, so FileOctopus won't…"), `FileOperationPauseGate`, `FileOperationProblemLog`,
`FolderMergeReport` + `MergePolicyChooser`, `FileCutBoard` (⌘X), `DiskArbitration` (đẩy ổ), `NetFS` + Bonjour (Kết nối
máy chủ, Mạng).

## 6. Đo tài nguyên cùng máy

FileOctopus sau 2 phút 54 giây mở (chủ dự án đang thử): **footprint 119 MB, đỉnh 227 MB**, RSS 156 MB, CPU 0 % lúc nghỉ.
XFinder (mọi tính năng, 11 h sau khi cài): footprint 133 MB, đỉnh 228 MB — trong đó ~25 MB là sự kiện agent (sửa ở
`c0bc8b1`).

## 7. Hệ quả cho XFinder (đầu vào cho XF-T30)

- Phiên: chuyển sang cây chia n-nhánh có `fractions` + tab ở từng ngăn (+ tab cửa sổ), `selectedNames` và `backStack`
  trong snapshot, schema có phiên bản (đã có ở sidebar).
- Tìm kiếm: thêm chỉ mục tên riêng cho các thư mục người dùng chọn (SQLite WAL, generation, FSEvents cursor) + khớp theo
  tầng có ngân sách fuzzy, ghép với `mdfind`/Spotlight đang có; chỉ mục nội dung FTS5 `unicode61 remove_diacritics 2`
  (tiếng Việt không dấu khớp có dấu) — OCR chạy ở tiến trình con `--vision` (luật Vision giữ bộ nhớ).
- Giữ lợi thế đo được: `getattrlistbulk` (không readdir + stat), danh sách AppKit.

## 8. Giải mã bằng REA + Hopper (2026-10-26) — danh sách cập nhật tại chỗ

REA `open_binary` (provider Hopper 6.6 demo; bridge chỉ lên sau khi Hopper phân tích xong ~3 phút — đặt `hopper.startup_timeout_ms`
1 200 000 rồi `close_binary` + mở lại), `binary_overview`: 51 863 thủ tục, 23 125 chuỗi; tên hàm Swift đã strip (`sub_…`), tên
kiểu còn trong metadata (`_TtC12BetterFinder22DirectoryChangeMonitor`, `_TtC12BetterFinder18MainThreadWatchdog`,
`_TtC14FileSystemCore16CloudLookupBatch`). Đường vào: `search_strings` selector → `xrefs` → `analyze_function`.

- `sub_100170a18` (Evidence `ev_c9458b86…`, trong `DirectoryBrowserViewController`): kiểm `swift_task_isCurrentExecutor`
  (MainActor) → `tableView.beginUpdates` → nếu `removed` không rỗng `removeItemsAtIndexes:inParent:nil withAnimation:` → nếu
  `inserted` không rỗng `insertItemsAtIndexes:inParent:nil withAnimation:` → `endUpdates`. Hai IndexSet là hai trường của cùng
  một struct kết quả diff.
- `sub_100168b30` (`ev_ac252279…`, 3 142 lệnh, cùng file `DirectoryBrowserViewController.swift`): gọi hàm trên; có nhánh
  `reloadData` dự phòng; `rowForItem:` + `reloadItem:reloadChildren:`; bật/tắt `usesAlternatingRowBackgroundColors`; sau đó
  `rowsInRect:` (vùng nhìn thấy) → tập hàng → **`editedRow` ≥ 0 ⇒ `IndexSet.remove(editedRow)`** (asm `0x10016b224…b24c`) →
  `reloadDataForRowIndexes:columnIndexes:` với `numberOfColumns`. Tức: vá tại chỗ, vẽ lại hàng đang hiện trừ hàng đang đổi tên.
- XFinder chép cơ chế này trong `ListingDiff` + `FileListView.Coordinator.reloadIfNeeded` (commit `b8ba61f` và bản sửa
  `editedRow`). Chưa giải mã: tham số `CloudLookupBatch` (cỡ lô) và ngưỡng `MainThreadWatchdog` — cần đi từ type descriptor.
