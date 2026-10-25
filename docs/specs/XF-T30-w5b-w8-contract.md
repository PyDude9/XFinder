# XF-T30 W5b + W8 — contract (nối tìm kiếm vào giao diện; đám mây)

Chạy SAU khi W2–W7 và W5a đã gộp (chạm file của các đợt đó). Hành vi: `scratchpad/claude/t30/spec-search.md` §1–§7,
`spec-cloud.md`. Bộ máy: `docs/specs/XF-T30-w5a-contract.md`.

## W5b — tìm kiếm trong trình duyệt

- **Một đường tìm**: `PaneState.startSearch` gọi `SearchCoordinator.shared.search(parsed, folders:, limit: 500, onUpdate:,
  onFinish:)` thay `FileSearchEngine.runMdfind` trực tiếp; kết quả cập nhật dần (kết quả sống), huỷ khi tab đổi thư mục/đóng
  (`Handle.cancel`), chip áp như cũ; nhãn nguồn (tên / Spotlight / nội dung) + đoạn trích nội dung ở hàng kết quả; cột "Nơi chứa"
  (thư mục cha) trong List khi đang tìm.
- **Phạm vi**: thanh phạm vi Máy này · Thư mục hiện tại · Các ngăn đang mở dưới ô tìm; mặc định theo
  `fileBrowser.search.defaultScope` (`previous` = phạm vi lần trước, nhớ trong phiên); "Máy này" khi chưa có thư mục đánh chỉ
  mục vẫn dùng Spotlight toàn máy (Q-T30-14).
- **Tìm đã lưu** (`BrowserSettings.savedSearches`): "Lưu tìm kiếm…" ở thanh tìm (tên + "Thêm vào sidebar"), mục "Tìm kiếm đã lưu"
  trong sidebar (W3) và menu Đi ▸ Tìm kiếm đã lưu (Hiện trong sidebar / Đổi tên / Xoá / Sao chép câu tìm); mở = chạy lại câu
  tìm (ngày tương đối tính lại).
- **Vòng đời chỉ mục**: cửa sổ trình duyệt đầu tiên mở ⇒ `FilenameIndex.shared.resume()` + `ContentIndex.shared.resume()` +
  `setRoots(BrowserSettings.indexRoots)`; đóng cửa sổ cuối ⇒ `suspend()`; đổi gốc trong Cài đặt ⇒ `setRoots`. Trạng thái
  "Đang cập nhật chỉ mục…" ở thanh tìm khi một gốc trong phạm vi đang indexing/updating.
- File: `BrowserWindowModel.swift` (startSearch), `SearchBarView.swift`, `BrowserSidebarView.swift` (mục đã lưu),
  `BrowserWindowController.swift` (vòng đời), `FileListView.swift` (cột Nơi chứa khi tìm), `BrowserMainMenu.swift` (Đi ▸ Tìm
  kiếm đã lưu).

## W8 — đám mây

- `CloudProviders.parse` (thuần, test): `GoogleDrive-<email>`, `Dropbox`, `Dropbox-<team>`, `OneDrive-<tên>`,
  `OneDrive-Personal`, `Box-Box`, còn lại `other`; iCloud Drive riêng.
- Sidebar Vị trí: mỗi tài khoản Google Drive một hàng có email, Dropbox một hàng, nhà cung cấp khác như Finder; tắt bằng công
  tắc Đám mây (cùng khoá với tab Đám mây).
- Hành động (menu chuột phải W2 + lệnh có sẵn): Tải về ngay / Gỡ bản tải một và nhiều mục (Free) qua
  `FileManager.startDownloadingUbiquitousItem(at:)` / `evictUbiquitousItem(at:)` chạy nền; Gỡ bản tải từ chối khi chưa tải lên
  xong; chép/chuyển tệp chỉ-trên-mây ra ngoài thư mục đám mây ⇒ chặn + "Tải về ngay"; chuyển mục đã tải ra ngoài ⇒ hỏi; Thùng rác
  mục Google Drive ⇒ xác nhận; Nén / Gộp bỏ thư mục đám mây; "Mở trong Google Drive" / "Sao chép liên kết Drive" / "Xem trên
  Dropbox.com" **chỉ khi probe đo được cơ chế trên máy có cài** — không có ⇒ không hiện, ghi T-T30-CLOUD.
- Tab Đám mây (W4 khung): mỗi nhà cung cấp trạng thái (đã cài / đang chạy / tài khoản), "Mở <app>", "Kiểm lại", "Ẩn trong XFinder";
  không OAuth, không đọc token.
- File: `CloudProviders.swift` (+ test), `CloudBadge.swift`, `SidebarSources.swift`, `BrowserSidebarView.swift`,
  `BrowserContextMenu.swift`, `BrowserSettingsWindow.swift` (tab Đám mây), `BrowserWindowModel+Cloud.swift` (mới).

## Nghiệm thu

W5b: tìm "bao cao" thấy "Báo cáo.pdf" theo tên trong thư mục đã đánh chỉ mục trước khi Spotlight trả về; nội dung PDF có chữ
"hợp đồng" tìm được bằng "hop dong"; lưu tìm "ảnh 7 ngày qua" vào sidebar, mở lại tuần sau ra kết quả mới. W8: Tải về ngay /
Gỡ bản tải trong iCloud Drive; badge đổi trạng thái; chép tệp chỉ-trên-mây ra Desktop bị chặn kèm gợi ý.
