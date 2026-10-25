# XF-T30 — Trình duyệt tệp: clone đầy đủ FileOctopus (2026-10-25)

**Câu việc:** "Người dùng làm mọi việc với tệp trong một cửa sổ giống Finder (tab, chia ngăn, sidebar, tìm, thao tác,
cài đặt) — đủ như FileOctopus, nhanh hơn nó."

Lệnh chủ dự án (2026-10-25, kèm 18 ảnh FileOctopus 1.0.4): "test thì có vẻ chỉ đang ở mức cơ bản chưa giống FinderOctopus.
Đọc lại toàn bộ guide … clone y toàn bộ tính năng Finder y chang", "chưa muốn kinh doanh ngay … hoàn thiện toàn bộ mới bán
sau", "có thể dùng REA dịch ngược các tính năng search và tối ưu".

## 0. Nguồn và ràng buộc

- Hành vi: 9 bản đặc tả đọc từ toàn bộ guide + changelog + trang chủ (workflow `wf_736d7763-89e`, scratchpad
  `claude/t30/spec-*.md`), kiểm kê XFinder (`inventory.md`), bảng thiếu theo mảng (`gap-*.md`), critic (`critic.md`).
- Cơ chế: `docs/FILEOCTOPUS_MECHANISMS_2026-10-25.md` (đo binary: mô hình phiên hai tầng tab, chỉ mục tên SQLite có
  generation + con trỏ FSEvents, khớp tên theo tầng, FTS5 `remove_diacritics 2`, AppKit `NSOutlineView`/`NSBrowser`/
  `NSCollectionView`/`NSToolbar`/`NSPathControl`/`NSTokenField`).
- **Ảnh của chủ dự án thắng guide** khi lệch (vd. guide không nói "New windows show" / "Show in windows" / "Show all
  filename extensions" / "Show hidden files", ảnh Cài đặt có đủ).
- Không chép mã; không đọc license của app kia. Pro **ngủ** (Q-PRO-*): mọi cổng giữ nguyên, bản build luôn đủ; không làm
  cửa sổ License, không dải "14 days left · Upgrade", không bước trial trong Welcome (lưu ở Q-T30-8).
- Trang cũ của XFinder **không gộp** (memory "ask before merging pages"). Cài đặt **của chính trình duyệt** chuyển vào cửa sổ
  Cài đặt trình duyệt (Q-T30-12).
- Giữ lợi thế đo được: `getattrlistbulk` (FileOctopus dùng readdir + stat từng tệp), khoá gập tên một lần, bộ đệm sắp phẳng.

## 1. Quyết định (mặc định đang theo — `Q-T30-*` trong pending list)

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-T30-1 | Nút Lùi/Tiến trên toolbar áp cho ngăn nào? | Ngăn đang chọn (như FileOctopus); nút chuột 4/5 + vuốt áp cho ngăn dưới con trỏ và chọn ngăn đó |
| Q-T30-2 | ⌘F | = Tìm (như FileOctopus, có thanh phạm vi); "Lọc thư mục hiện tại" thành lệnh riêng không phím (bỏ tách ⌘F/⌥⌘F của Q-T28-3) |
| Q-T30-3 | Tab cửa sổ | Tab macOS gốc (`NSWindow` tabbing, ⌘T); ⌘N cửa sổ mới |
| Q-T30-4 | Đóng tab cuối của một ngăn | Đóng ngăn nếu còn ngăn khác; ngăn cuối + tab cuối ⇒ lệnh xám |
| Q-T30-5 | Phóng ngăn (⇧⌘↩) trở lại | Bấm lại cùng phím; không lưu vào phiên |
| Q-T30-6 | "Đổi chỗ với ngăn kế" | Đổi **nội dung** (cả chồng tab + lịch sử), vị trí ngăn giữ nguyên |
| Q-T30-7 | Khôi phục Column view | **Hơn** FileOctopus: khôi phục cả đường cột (NSBrowser `setPath`) |
| Q-T30-8 | License / dải gói / bước trial | Không làm khi Pro ngủ |
| Q-T30-9 | Bước "Usage Statistics" của Welcome | Bỏ (XFinder không gửi analytics của trình duyệt); Welcome còn 4 bước: Chào · Quyền thư mục · Full Disk Access (bỏ qua được) · Chọn bố cục |
| Q-T30-10 | Đổi phím + hồ sơ Finder / Windows Explorer / Total Commander | Làm (chủ dự án: "y chang") |
| Q-T30-11 | Tìm kiếm đã lưu | Làm |
| Q-T30-12 | Trang "Trình duyệt tệp" cũ | Giữ công tắc bật/tắt + phím toàn cục + nút "Mở cài đặt trình duyệt…"; mọi khoá `fileBrowser.*` khác chỉ có MỘT control, trong cửa sổ Cài đặt trình duyệt (luật 7) |
| Q-T30-13 | Menu bar khi cửa sổ trình duyệt ở trước | Thêm menu Tệp/Sửa/Xem/Đi/Cửa sổ của trình duyệt nếu đo được SwiftUI không ghi đè; không được ⇒ đủ lệnh qua toolbar "…", chuột phải, bảng lệnh |

## 2. Các đợt (thứ tự = phụ thuộc; mỗi đợt: contract + stub → builder theo file → verify → tích hợp → gate → mutation → cài → push)

| Đợt | Nội dung | File chính |
|:--|:--|:--|
| **W1 Tab + khung** | Tab trong từng ngăn (⌃⌥⌘T, ⌥⌘]/[, đóng tab, chuyển tab sang ngăn kế / ngăn mới phải ⌥⇧⌘→ / dưới ⌥⇧⌘↓, đổi chỗ, ra cửa sổ, kéo tab giữa ngăn và ra mép ngăn ⇒ chia), tab cửa sổ gốc ⌘T, chọn ngăn theo hướng ⌃⇧⌘←→↑↓, rộng/hẹp/cao/thấp, vạch nhấn màu trên ngăn đang chọn; `NSToolbar` gốc (Lùi/Tiến giữ-để-xem-lịch-sử, Xem, Nhóm, Bố cục ngăn có biểu tượng theo bố cục, Chia sẻ, Tác vụ "…", Tìm; tuỳ biến + Thư mục cha, Đến thư mục, Workspace, Shelf, Thao tác); Location Bar (ẩn/hiện), Path Bar ⌥⌘P, Status Bar ⌘/ ("N mục, X còn trống"); phiên v2 (năm tầng: cửa sổ → tab cửa sổ → ngăn → tab ngăn → lịch sử; mục đã chọn; thư mục mất ⇒ tab chết "Thử lại", không về Home); menu bar (Q-T30-13) | `PaneTabs`(mới, thuần), `PaneTree`, `BrowserWorkspace`, `BrowserCommands`, `BrowserWindowModel`, `BrowserWindowController`, `BrowserToolbar`(mới), `BrowserMainMenu`(mới), `PaneTabStripView`(mới), `PaneView`, `PaneGridView`, `BrowserRootView`, `PathBarView`(mới), `StatusBarView`(mới) |
| **W2 Kiểu xem** | List = `NSOutlineView` có tam giác mở thư mục tại chỗ (→ ← ⌥→ ⌥←), nhóm theo (Không, Tên, Loại, Ứng dụng, Ngày mở gần nhất, Ngày thêm, Ngày sửa, Ngày tạo, Cỡ, Thẻ) với tiêu đề Hôm nay / Hôm qua / 7 ngày trước…, ⌃⌘0, Sắp theo cho Gallery; cột thêm (Ngày tạo, Ngày thêm, Ngày mở, Thẻ, Phiên bản, Ghi chú) qua chuột phải tiêu đề + menu "Vừa cỡ cột"; Tuỳ chọn xem ⌘J (cỡ biểu tượng, cỡ chữ, cột, nhớ theo thư mục); badge đám mây + chấm màu thẻ ở cả 4 kiểu xem; một menu chuột phải chung (Lấy thông tin, Mở bằng, Sao chép đường dẫn, Chia sẻ, Thẻ, Hiện bản gốc ⌘R, Tạo bí danh ⌃⌘A, Thêm vào sidebar ⌃⌘T, Thêm vào Shelf, Nén…); kéo-thả chung + thư mục bật mở khi giữ kéo (spring-loaded, theo cài đặt hệ thống) + tô sáng đích thả | `GroupBy`(mới, thuần), `FolderViewOptions`(mới, thuần), `DirectoryEntry`, `DirectoryReader`, `FileListView`, `FileIconView`, `FileColumnView`, `FileGalleryView`, `BrowserContextMenu`(mới), `DragDropCoordinator`(mới), `ViewOptionsPanel`(mới) |
| **W3 Sidebar + Đi + Mạng** | Gần đây, AirDrop (thả = gửi qua AirDrop; bấm = cửa sổ AirDrop của Finder), Thẻ (theo tên/thứ tự của Finder, đồng bộ ~1 s, "Tất cả thẻ…" là danh sách trong sidebar), iCloud, Vị trí (ổ trong / ngoài / đám mây / máy chủ đã nối) + tuỳ chọn nhóm theo loại, Mạng Bonjour (mặc định tắt), tô sáng vị trí chứa thư mục hiện tại; đẩy ổ ⌘E (hỏi đẩy một hay mọi volume của đĩa; Thử lại / Buộc đẩy đúng phạm vi); làm mới khi gắn/tháo ổ; kéo sắp xếp mục ưa thích/thẻ + hoàn tác; menu chuột phải đúng 5 mục; menu Đi (⇧⌘F/O/D/H/R/K/I/A/U, ⌥⌘L, ⇧⌘C xám) + Thư mục gần đây (10, Xoá menu) + Kết nối máy chủ ⌘K (NetFS) | `SidebarLayout`, `BrowserSidebarView`, `SidebarSources`(mới), `TagLibrary`(mới), `VirtualLocations`(mới: Gần đây, Thẻ), `EjectGuard`, `ConnectToServer`(mới) |
| **W4 Cài đặt + phím + Welcome** | Cửa sổ Cài đặt trình duyệt ⌘, khi trình duyệt ở trước: Chung (Cửa sổ mới hiện, Hiện trong cửa sổ: Location/Path/Status Bar, Mở lại cửa sổ, Return đổi tên/mở, ⌘X để cắt kiểu Windows), Sidebar (công tắc từng mục + Ổ đã ẩn + 2 tuỳ chọn), Đám mây, Nâng cao (hiện mọi đuôi tệp, hiện tệp ẩn, thư mục lên đầu, phạm vi tìm mặc định), Bàn phím (3 hồ sơ, bảng Phím / Phím thêm / Mặc định có tìm, ghi phím, xung đột "Vẫn dùng", nhập/xuất JSON kiểm trọn trước khi áp, Tab chuyển ngăn, nút chuột 4/5 + đảo), Tìm kiếm (W5), Quyền riêng tư (Desktop/Documents/Downloads, Full Disk Access Bật/Tắt/Không kiểm được + Kiểm lại, "Hiện cửa sổ Chào…"); Welcome 4 bước (Q-T30-9) | `BrowserSettings`, `KeyBindings`(mới, thuần), `BrowserSettingsWindow`(mới), `OnboardingWindow`(mới), `FileBrowserDetailView` |
| **W5 Tìm kiếm** | Chỉ mục tên riêng cho thư mục người dùng duyệt (SQLite WAL, generation, con trỏ FSEvents, `getattrlistbulk`), khớp theo tầng (đúng → đầu → đầu từ → chứa → mờ có ngân sách), ghép với Spotlight; chỉ mục nội dung FTS5 `unicode61 remove_diacritics 2` (văn bản, PDF ≤ 50 trang, OCR ảnh qua `--vision`), giới hạn 2 MiB / 64 MiB / 200 000 ký tự, trạng thái (Đang đánh chỉ mục / Tạm dừng / Ngoại tuyến / Không truy cập / Bị dời / Lỗi), Tạm dừng / Dựng lại / Xoá chỉ mục; tìm đã lưu (sidebar, ngày tương đối); kết quả sống | `SearchIndex`(mới), `NameMatcher`(mới, thuần), `ContentIndex`(mới), `SavedSearch`(mới, thuần), `SearchQuery`, `SearchBarView` |
| **W6 Thao tác tệp** | Gộp thư mục (Gộp…, báo cáo), danh sách Sự cố + Thử lại, tốc độ/ETA, Hoàn tác bền 20 bước / 24 h có kiểm lại, cắt ⌘X kiểu Windows, Thư mục mới chứa mục chọn ⌃⌘N, Tạo bí danh, Làm lại ⇧⌘Z khi an toàn, Xoá lịch sử thao tác | `FileOperationRules`, `FileOperationQueue`, `FolderMerge`(mới), `UndoJournal`(mới), `OperationsPanelView`, `ConflictSheet` |
| **W7 Xem trước + thông tin** | Ngăn Xem trước ⇧⌘P, trình chiếu ⌥⌘Y, Get Info đủ mục (Mở bằng + Thay đổi tất cả, Chia sẻ & Quyền có ACL, Ghi chú Spotlight), Thông tin ổ đĩa | `PreviewPane`(mới), `GetInfoWindow`, `FileInfoRules`, `VolumeInfo`(mới) |
| **W8 Đám mây** | Google Drive / Dropbox / OneDrive / iCloud trong sidebar theo tài khoản, Tải về ngay / Gỡ bản tải (một và nhiều), Mở trong Google Drive / Sao chép link Drive / Xem trên Dropbox.com (probe cơ chế trước — luật Honesty), tab Đám mây | `CloudProviders`(mới), `CloudBadge`, `BrowserSidebarView` |

## 3. Ca hỏng chung (áp cho mọi đợt)

- 100 000 tệp: liệt kê ≤ 150 ms, lọc ≤ 16 ms/phím, không đọc đĩa trên main (kể cả `statfs` trong `body`).
- Tab/ngăn bị đóng khi đang tải ⇒ huỷ tải + watcher (không rò `DirectoryWatcher`).
- Phiên v1 (XF-T28) phải mở được bằng bản v2 (mỗi ngăn thành một tab); phiên hỏng một phần ⇒ chỉ mất phần hỏng.
- Ô tìm luôn theo ngăn của nó (FileOctopus sửa hai lần) — test chia 2 ngăn, gõ ở ngăn 1, ngăn 2 không đổi.
- Mọi chuỗi qua L10n (VI + EN), mọi khoá mới có reader ONE + `@AppStorage` cùng mặc định + hàng FeatureKeyDefaults.

## 4. Nghiệm thu chung

Mỗi đợt: build xanh, toàn bộ test 0 lỗi, gate L10n/token xanh, harness browser (mở rộng) 100 % RED, cài + so hash dylib,
runtime L10n 0, e2e AX trên bản cài khi chủ dự án rời máy. Chủ dự án test tay theo `T-T30-*` của từng đợt.
