# XF-T28 Wave 4 — chỉ các dòng chủ dự án đã chọn (2026-10-24)

Chọn qua AskUserQuestion: ✅ Đồng bộ thư mục (lối vào trong trình duyệt) · ✅ Tìm kiếm AI (liên kết sang trình duyệt) ·
✅ Get Info (⌘I) · ✅ Tuỳ biến sidebar. Không gì khác. Trang cũ giữ nguyên.

## A. Get Info (⌘I)

Câu việc: "Xem và sửa thông tin một tệp/thư mục ngay trong trình duyệt, như ⌘I của Finder."
- Lệnh mới `BrowserCommand.getInfo` ⌘I (thêm vào `BrowserCommands`, test bắt trùng phím vẫn xanh).
- `Core/Browser/FileInfoRules.swift` (thuần, symlink): từ `FileInfoFacts` (kích thước logic, kích thước trên đĩa, ngày
  tạo/sửa/mở, quyền POSIX + chủ/nhóm, cờ khoá `uchg`, ẩn đuôi, thẻ) ⇒ các hàng hiển thị (khoá L10n) cho 4 mục Chung ·
  Thêm thông tin · Tên & đuôi · Quyền; `permissionLabel(mode:who:)` ("Đọc & ghi" / "Chỉ đọc" / "Chỉ ghi" / "Không truy
  cập"); nhiều mục chọn ⇒ một bản tóm tắt (tổng cỡ, số mục, loại chung hay "Nhiều loại").
- `Views/Browser/GetInfoWindow.swift`: một cửa sổ cho mỗi lựa chọn (hoặc một bản tóm tắt cho nhiều mục), cỡ thư mục
  tính **nền** (`FileWalk.totalSize`, có nút dừng), không bao giờ hỏi mật khẩu admin; sửa: tên (luật đổi tên như
  Finder), ẩn đuôi, khoá, thẻ, quyền của chính tệp (không đệ quy) — mỗi sửa đổi ghi vào `ActionHistoryStore` khi đảo được.
  Tệp iCloud chưa tải: không tải để đọc thêm thông tin.
- Ca hỏng: thư mục 500 000 tệp (cỡ tính nền, cửa sổ mở ngay); không có quyền đổi quyền ⇒ báo, không hỏi admin; tệp bị
  đổi tên/xoá khi cửa sổ đang mở ⇒ cửa sổ báo "Không còn ở đây"; kết quả tìm kiếm ⇒ chỉ đọc.

## B. Tuỳ biến sidebar

Câu việc: "Sidebar trình duyệt có đúng những chỗ tôi dùng, theo nhóm tôi đặt."
- `Core/Browser/SidebarLayout.swift` (thuần, symlink, **schema có phiên bản từ đầu** — bẫy FileOctopus: bản cũ xoá tuỳ
  biến): nhóm (Mục ưa thích mặc định + nhóm riêng), mục (đường dẫn + tên hiển thị tuỳ chọn), ổ bị ẩn (theo UUID volume,
  bền qua đẩy/gắn lại); thao tác: thêm/đổi tên/xoá nhóm (xoá nhóm ⇒ mục về Mục ưa thích), kéo mục giữa nhóm/đổi thứ tự,
  đổi tên hiển thị + "Đặt lại tên", ẩn ổ + khôi phục; `decode` chịu được bản cũ/lạ (bỏ phần hỏng, giữ phần còn lại).
- `BrowserSidebarView` dùng `SidebarLayout`; chuột phải: Đổi tên… / Đặt lại tên / Bỏ khỏi sidebar / Ẩn ổ / Nhóm mới…;
  kéo thư mục từ ngăn vào sidebar ⇒ thêm mục. Trang cài đặt trình duyệt có mục "Ổ đã ẩn" để khôi phục. Khoá
  `fileBrowser.sidebarLayout` (Data JSON) — ONE reader trong `BrowserSettings`.

## C. Đồng bộ thư mục — lối vào trong trình duyệt

- Sidebar có nhóm "Đồng bộ" liệt kê `FolderSyncController.shared.pairs` (nguồn → đích); bấm ⇒ cửa sổ hiện tại chuyển
  preset Cạnh nhau, ngăn trái = nguồn, ngăn phải = đích, thanh trên lưới hiện "Đồng bộ ‹nguồn› → ‹đích›" + nút
  **Đồng bộ ngay** gọi đúng `FolderSyncController.shared.run(pair)` (không viết lại engine) + kết quả lần chạy cuối.
- Cổng Pro `.folderSync` (XF-T29): Free thấy nhóm với nhãn PRO, nút tắt.
- Cài đặt cặp (lịch, xoá phần thừa) vẫn chỉ ở trang Đồng bộ cũ; trình duyệt có nút "Cài đặt cặp này…" mở trang đó.

## D. Tìm kiếm AI — liên kết

- Trang Tìm kiếm AI thêm một hàng: "Tìm bằng câu thường ngay trong Trình duyệt tệp — có chip sửa được" + nút
  "Mở thanh tìm" ⇒ `BrowserWindowController.shared.openWindow(path: nil)` rồi mở ⌥⌘F ở ngăn đang chọn (thêm
  `openWindow(path:startSearch:)`); trang cũ giữ nguyên mọi thứ khác.

## E. API chốt giữa các cụm (stub đã có trên main — chữ ký bắt buộc)

- `PaneState.runSearch(parsed:scope:paneFolders:)` — chạy thẳng từ chip (sửa lỗi chip 7 ngày/cũ hơn/tháng bị rơi).
- `BrowserWindowModel`: `workspaces`, `saveWorkspace(named:)`, `openWorkspace(_:)`, `renameWorkspace(_:to:)`,
  `duplicateWorkspace(_:)`, `deleteWorkspace(_:)`, `exportWorkspaces()`, `activeSyncPair`, `openSyncPair(_:)`,
  `syncNow() async -> Bool`, `showBanner(_:)`; `perform(.getInfo)` ⇒ `GetInfoWindowController.shared.show(paths:readOnly:)`.
- `BrowserWindowController.openWindow(path:startSearch:)`.
- `BrowserCommand.getInfo` ⌘I ("Lấy thông tin") — đã thêm.
- `GetInfoWindowController.shared.show(paths:readOnly:)` (Views/Browser/GetInfoWindow.swift), `FileInfoRules` (thuần),
  `SidebarLayout` (thuần) — stub rỗng, cụm tương ứng định nghĩa đầy đủ.
- Cổng Pro trong trình duyệt (XF-T29): `LicenseManager.shared.limit(.browserPanes)` (Free 2 — chia ngăn thứ 3 bị chặn,
  bố cục đã có vẫn dùng được), `.browserShelf` (thêm vào Shelf), `.browserWorkspaces` (lưu/mở; Free vẫn xem/đổi tên/xoá/xuất),
  `.browserQueue` (Free: thêm việc khi đang có việc chạy ⇒ banner thay vì xếp hàng), `.browserBatchCloud` (tải về/gỡ > 1 mục).
