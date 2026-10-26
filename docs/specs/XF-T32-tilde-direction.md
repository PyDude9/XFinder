# XF-T32 — Trình duyệt tệp theo hướng Tilde (giao diện · tính năng · hiệu năng), 2026-10-26

**Người dùng vào đây để** làm việc với thư mục dự án như một không gian làm việc — không phải chỉ liệt kê tệp:
gắn trạng thái cho thư mục, ghim thứ hay dùng lên đầu, gom nhóm tự động ở sidebar, nhảy tới bất kỳ chỗ nào bằng ⌘K,
và xem/đổi tệp ngay trong cửa sổ — mở tức thì, bấm là ăn ngay.

Lệnh của chủ dự án: "Cập nhật lại giao diện và chức năng cũng như hiệu năng của app. Không theo lối mòn nữa", kèm
13 ảnh + 6 video Tilde. Tilde đang cài trên máy (`/Applications/Tilde.app`, `com.blazegreenhalgh.FileExplorer` 1.0.2,
macOS 14+, SwiftUI + AppKit, Sparkle) — mọi cơ chế dưới đây **đo từ bản cài**, không đoán từ ảnh.

## 1. Bằng chứng đo được từ Tilde

### 1.1 Chạy thật (22 h sau khi mở, cửa sổ Home)
- footprint **230 MB / đỉnh 612 MB** (XFinder build16 sau 5 phút: 90–116 / 129). ⇒ **không chép hồ sơ bộ nhớ** của họ;
  giữ mốc XFinder (§5).
- Click → chọn, tạo/xoá tệp → hàng hiện/mất: harness `scratchpad/claude/perf/h2h` (chạy khi chủ dự án rời máy) — điền
  số vào §5 khi có.

### 1.2 Kiến trúc (tên kiểu Swift trong binary, 250 kiểu; `scratchpad/claude/tilde/types.txt`)
- **Split riêng `Bonsplit`**: `SplitState`, `SplitTreeContainerView`, `PaneState`, `TabItem`, `TabDragCoordinator`,
  `TabDragDestinationRegistry`, `TabDragExternalPreviewWindow` (kéo tab ra ngoài có cửa sổ xem trước),
  **`SplitPaneFocusEventRouter`** + **`FocusedPaneOutlineView`** (viền ngăn đang chọn là một view riêng, không phải
  overlay nhận chuột), `RetainedTabSurfaceHostingView` (tab giữ view khi không hiện — đổi tab không dựng lại).
- **Liệt kê và cache**: `DirectoryListingEngine/Service`, **`DirectoryListingDiskCache`** (SQLite: `directory_listing_folders
  (folder_path, validation_token, item_count)`, `directory_listing_items (…name, kind, size, modified, created, added,
  cloud_status, cloud_provider, sort_order)`) ⇒ thư mục đã mở **vẽ ngay từ cache** rồi xác thực bằng token;
  `FolderListingCache`, `FileItemProjectionCache`, `FileColumnDirectoryProjectionCache`, **`FileProjectionActor`**,
  `FileSystemQueryActor` (đọc đĩa ngoài main), **`DirectoryWorkLimiter`** + `DirectoryListingFlightGate` (giới hạn
  số lần đọc song song), `FolderWatcher` + `WatcherBroker` (một watcher mỗi thư mục, chia sẻ), `FolderSessionMemoryRegistry`
  + **`CacheMemoryPressureMonitor`** (xả cache khi hệ thống báo thiếu RAM), **`MainRunLoopHitchProbe`** +
  `WindowInteractionPerformanceState` (tự đo giật main thread).
- **Dữ liệu người dùng (sidecar SQLite, không xattr)**: `FileExplorer-v2.sqlite3` — `file_properties(definitions JSON:
  [{id, name, kind, selectOptions:[{id, title, colorIndex}]}])`, `file_property_selections(item_path, property_id,
  option_id)`, `folder_file_properties(folder_path, property_id, sort_order)` (thuộc tính hiện ở thư mục nào),
  `file_nicknames(item_path, nickname)`, `folder_metadata(folder_path, emoji)`, `folder_contexts(payload)` (ghim),
  `sidebar_state(spaces_json: [{id, name, groups:[{id, name, kind, isCollapsed, folders:[{path, name, bookmark…}]}],
  savedWorkspaces, areWorkspacesCollapsed}], active_space_id)`, `folder_relations(path_a, path_b, bookmark)`,
  `folder_related_urls`, `folder_file_views(view_mode "tree", column_layout, sort/group/filter descriptors)`,
  `tab_sessions(payload)`, `recent_folders`.
- **⌘K**: `CommandPaletteFolderIndex.sqlite3` **176 MB** (FTS5 `unicode61 remove_diacritics 2` prefix 2–4 + bảng
  trigram, `scan_generation` theo gốc), `CommandPaletteUsageStore` (xếp theo tần suất dùng), `CommandPaletteFavouriteStore`.
  XFinder đã có `FilenameIndex` (trigram + generation) — **dùng lại, không thêm chỉ mục thứ hai**.
- Khác: `MarkdownDocument*` + `MarkdownConcealingLayoutManager` (xem/sửa Markdown trong Inspector), `CodePreviewRenderService`
  + module `Highlighter` (tô màu mã), `WindowImageOperationQueue` (WebP/PNG/JPEG, resize, flip), `ShelfStore`,
  `DownloadsTrayStore` + `CarbonGlobalHotKeyRegistrar` (phím tắt toàn cục mở khay Tải về), `LearnWayfinder*` (trang
  Learn 6 bài có tiến độ, lưu `learnWayfinder.completedLessons.v1`), `LicenseGate*`, `SpaceHome*` (trang tổng quan Space).

### 1.3 Giao diện (6 video, 1 fps; `scratchpad/claude/tilde/sheet-*.png`)
- Cửa sổ: sidebar mờ (vibrancy) trái · thanh tab ở đầu (pill tên thư mục, +) · góc phải 3 nút xem (cột / danh sách /
  chia) · dưới ô tìm; vùng nội dung **một cột "tree"** (tam giác mở, không header cột) hoặc Miller columns; **"Pinned"**
  là khối riêng trên đầu thư mục; **chip thuộc tính** màu ở phải hàng; **nhóm theo thuộc tính** có tiêu đề (In Progress ·
  Upcoming · Completed · No Status); nhãn **aka** cạnh tên có nickname; breadcrumb ở **đáy**; thanh "Add related items".
- Sidebar: tiêu đề = tên **Space** (bấm để đổi, chấm phân trang ở đáy), Workspaces, Favorites, **Live Groups** (mỗi nhóm
  = một giá trị thuộc tính, tự liệt kê thư mục), Recents, Locations, Trash.
- Inspector phải: Open · Reveal · Path · Share; Image Actions (WebP · Convert · Resize · Flip H · Flip V); Details (Kind,
  Size, Resolution, Created, Modified, Location, Path, Cloud); **Info | Preview** — Markdown render ngay.
- ⌘K: một ô cho lệnh + thư mục + tệp + nickname; `Move to…` hai bước (chọn đích trong cùng palette); chân palette ghi
  phím: ↵ Open · ⌘↵ New Tab · ⌥↵ Split · ⌘K Actions · esc.
- Toast đáy giữa "Moved to Images" có nút ↩; **Shelf** là viên thuốc nổi đáy giữa "Drop files here to shelve"; khay
  **Downloads** popover.
- Cài đặt 5 tab: General (viewer mặc định, mở thư mục ngoài ở tab mới/tab đang), License, Appearance (**Pane focus: Dim
  inactive panes | Outline focused pane**, Show hidden, Right-size columns, Hide Recents, Show Learn button), Shortcuts
  (tìm, nhóm, Set Shortcut, ×), Inspector.

## 2. Đối chiếu với XFinder hiện có

| Tilde | XFinder đã có | Thiếu / khác |
|:--|:--|:--|
| Spaces (sidebar theo không gian) | `BrowserWorkspace` = snapshot bố cục cửa sổ | sidebar không đổi theo workspace; không có tiêu đề/pager |
| Properties + chip + nhóm theo thuộc tính | `FinderTags` (xattr, 7 màu), `GroupBy` (ngày/loại/thẻ) | chưa có thuộc tính tuỳ biến nhiều giá trị, chưa có DB sidecar, chưa có chip |
| Live Groups | `SavedSearchStore` (câu tìm lưu, hiện trong sidebar) | nhóm theo thuộc tính tự cập nhật — chưa |
| Pinned trong thư mục | — | chưa |
| Nickname (aka) | `makeAlias` (alias tệp) | khác nghĩa; chưa có tên gọi |
| Emoji thư mục | — | chưa |
| ⌘K hợp nhất | `CommandPaletteView` (Quick Open ⌃⌘P + Commands `>`) | tách hai chế độ; chưa có `Move to…`, chưa xếp theo tần suất |
| Inspector Info/Preview | `PreviewPaneView` (thông tin + thẻ + ảnh QL) | chưa render Markdown/mã, chưa có Image Actions |
| Shelf | `ShelfModel` + `ShelfBarView` (thanh) | khác dạng (viên thuốc nổi) — giữ thanh, Q-T32-7 |
| Downloads tray | — | chưa (có Live Activities ở notch) |
| Learn | `OnboardingWindow` (4 bước) | chưa có trang bài học + tiến độ |
| Settings 5 tab | `BrowserSettingsWindow` nhiều tab | thiếu Pane focus dim; License ẩn (Pro ngủ — đúng ý) |
| Pane focus router | `BrowserWindow.sendEvent` (vừa làm, `fe0a418`/`566afac`) | viền còn là overlay vẽ; chưa có chế độ làm mờ |
| Disk listing cache | `DirectoryReader` 101 ms/100 000 tệp, không cache | mở lại thư mục vẫn đọc đĩa |
| Hitch probe | — | Q-T31-3 |

## 3. Quyết định (mặc định đang theo — trả lời bằng mã để đổi)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-T32-0 | Hướng UI: Tilde cho **cửa sổ trình duyệt**; các trang Cài đặt XFinder vẫn OneNotch | theo mặc định |
| Q-T32-1 | Bố cục mặc định: tree một cột (Tilde) hay giữ 4 kiểu xem | giữ 4 kiểu; **List thành tree** (bỏ header cột khi ≤ 1 cột hiện, Pinned + chip + nhóm thuộc tính); mặc định mới = List |
| Q-T32-2 | Thuộc tính lưu ở đâu | SQLite sidecar `Browser/metadata.sqlite` (actor, WAL) — không ghi xattr; Finder tags vẫn là tags |
| Q-T32-3 | Live Groups | nhóm sidebar = (thuộc tính, giá trị); liệt kê từ DB, không quét đĩa; đổi thuộc tính ⇒ sidebar cập nhật ngay |
| Q-T32-4 | Spaces | đổi `BrowserWorkspace` thành Space: thêm `sidebar` (nhóm + thư mục) + tiêu đề + pager; phiên cũ = Space "Tilde"… tên XFinder |
| Q-T32-5 | ⌘K | hợp nhất Quick Open + Commands + nickname + `Move to…`; ⌘K mặc định, ⌃⌘P giữ như alias; xếp theo tần suất (`palette.usage`) |
| Q-T32-6 | Inspector | thêm Info/Preview: Markdown (render bằng AttributedString Markdown), mã (tô màu nhẹ, không thêm module), ảnh: WebP/PNG/JPEG/resize/flip qua **tiến trình con `XFinder --image <op>`** (ImageIO giữ bộ nhớ như Vision — đo trước) |
| Q-T32-7 | Shelf | giữ `ShelfBarView`; thêm dạng viên thuốc nổi khi thanh ẩn? — **không**, một bề mặt |
| Q-T32-8 | Downloads tray | có: popover từ toolbar + phím tắt toàn cục (Carbon, đã có `ShortcutCatalog`), đọc `~/Downloads` 20 mục mới nhất |
| Q-T32-9 | Learn | trang trong cửa sổ (tab "Learn") 6 bài, tiến độ `fileBrowser.learn.completed` |
| Q-T32-10 | Pane focus | thêm `fileBrowser.paneFocusStyle` = `outline` \| `dim` (mặc định `dim` như Tilde); `FocusedPaneOutline` là NSView riêng |
| Q-T32-11 | Hiệu năng | **làm trước UI**: disk listing cache + validation token (mtime+size thư mục), projection ngoài main, work limiter, hitch probe Debug, pressure monitor; mốc §5 |
| Q-T32-12 | Thanh "Add related items" | có, lưu `folder_relations` tương đương |
| Q-T32-13 | Breadcrumb đáy | có, thay `PathBarView` vị trí (mặc định bật) |

## 4. Đợt làm (fan-out theo file, contract trước, stub biên dịch được)

- **W0 Hiệu năng lõi** (Core/Browser, thuần + actor): `ListingDiskCache` (SQLite, token = (mtime, size, count) thư mục),
  `DirectoryLoadCoordinator` (một listing + một watcher mỗi đường dẫn, refcount — Q-T31-1), `DirectoryWorkLimiter`,
  `MainThreadHitchProbe` (Debug, > 250 ms ⇒ log + `sample`), `MemoryPressureRelief`. Nghiệm thu: mở lại thư mục từ cache
  **< 30 ms** tới hàng đầu tiên; 100 000 tệp lần hai < 60 ms; footprint 8 h ≤ 120 MB.
- **W1 Dữ liệu người dùng** (thuần): `MetadataStore` (actor SQLite: properties, selections, pins, nicknames, emoji,
  relations), `PropertyRules` (nhóm, màu, thứ tự), `SpaceStore` (sidebar theo space), migration từ `BrowserWorkspace`.
- **W2 Sidebar**: tiêu đề Space + pager, Workspaces, Favorites, Live Groups, Recents, Locations, Trash, kéo-thả sắp xếp.
- **W3 Nội dung**: List → tree (Pinned, chip, nhóm thuộc tính, aka, emoji), menu `…` mỗi hàng (Pin · Status · Add
  property), breadcrumb đáy, "Add related items", pane focus dim/outline.
- **W4 Inspector**: Info/Preview, Markdown, mã, Image Actions (con), Open/Reveal/Path/Share.
- **W5 ⌘K**: hợp nhất + `Move to…` + tần suất + chân phím.
- **W6 Settings + Learn + Downloads tray**.
- Mỗi đợt: test thuần + mutation vào harness browser; L10n qua script add-only; đo trên bản cài (probe AX/click) trước khi nói xong.

## 5. Mốc đo (bắt buộc, trên bản cài)

| Việc | Mốc | Tilde đo | XFinder nay |
|:--|:--|:--|:--|
| Click → hàng được chọn | ≤ 100 ms | (chờ h2h) | 110–190 ms (build17), build18 chờ đo |
| Mở lại thư mục đã mở (58 mục) | ≤ 30 ms tới hàng đầu | (chờ) | đọc đĩa mỗi lần |
| Tạo tệp → hàng hiện | ≤ 500 ms | 729 ms (FileOctopus) | 4–7 s (probe thô) |
| Footprint sau 8 h | ≤ 120 MB | 230 / đỉnh 612 | 98–116 |
| Main thread giật > 250 ms / 10 phút dùng | 0 (hitch probe) | (có probe) | chưa đo |

## 6. Không làm
Sparkle/Sentry; chỉ mục ⌘K 176 MB riêng; dải License/trial (Pro ngủ — XF-T29); web/TypeScript (tài liệu Gemini là mô phỏng
web, không phải đích); đổi các trang Cài đặt ngoài trình duyệt sang gu Tilde (Q-T32-0).
