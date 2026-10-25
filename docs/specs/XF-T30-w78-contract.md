# XF-T30 W7 + W8 — contract (xem trước + thông tin; đám mây)

Spec tổng §2 hàng W7/W8. Hành vi: `scratchpad/claude/t30/spec-preview-info.md` (R1–R48), `spec-cloud.md` (R1–R51). Stub thêm
SAU khi W1 gộp.

## W7 — Xem trước, trình chiếu, Get Info đủ, Thông tin ổ

- **Ngăn Xem trước** ⇧⌘P (builder V7 — `PreviewPaneView.swift` (mới), `PreviewPaneModel.swift` (mới)): dải bên phải mỗi ngăn
  (ẩn/hiện chung, `fileBrowser.showPreview` mặc định false), mục "Thông tin" (loại, cỡ, ngày tạo/sửa/mở, kích thước ảnh, thời
  lượng, số trang) + "Thẻ"; "Hiện thêm / Hiện bớt" nhớ toàn cục (`fileBrowser.previewShowMore`); ảnh qua `QLThumbnailGenerator`
  (ngoài tiến trình), video = khung poster + nút Phát (không tự phát), không xem được ⇒ biểu tượng + giải thích, tệp đám mây
  chưa tải ⇒ không tải. Column view: cột cuối dùng cùng nội dung. ⌥⌘P vẫn là Path Bar.
- **Trình chiếu** ⌥⌘Y: `QLPreviewPanel` toàn màn hình (`enterFullScreenMode`) của mục chọn / cả thư mục ảnh; Space/⌘Y không
  bật khi ô chữ có focus; Quick Look theo ngăn đang chọn và theo hàng kết quả tìm (tệp thật).
- **Get Info** (builder G7 — `GetInfoWindow.swift`, `FileInfoRules.swift`): năm mục gập theo thứ tự Chung · Thêm thông tin ·
  Tên & đuôi · Thẻ · Chia sẻ & Quyền; Chung thêm "Mở lần cuối", "Phiên bản" (app), "Trạng thái đám mây" (chỉ mục đám mây);
  Thêm thông tin theo loại (ảnh: kích thước / không gian màu / máy ảnh; phim: thời lượng / codec; PDF: số trang) — **không tải
  đám mây**; thẻ ghi đúng màu Finder (sửa lỗi 1.0.4 của họ); Khoá ⇒ xám Đổi tên / Thùng rác / Ẩn đuôi / Quyền; từ kết quả tìm ⇒
  chỉ đọc + liên kết "Hiện trong thư mục chứa"; mọi sửa đổi qua `UndoJournal` (W6). **Mở bằng** (Finder có, FileOctopus chưa —
  Q-T30-15 mặc định: thêm "Mở bằng: <app> ▸" + "Thay đổi tất cả…" theo `LSSetDefaultRoleHandlerForContentType`? **Không** —
  đổi mặc định hệ thống là đổi cấu hình máy, chỉ làm khi chủ dự án gật; mặc định W7: chỉ hiện app mở được, không nút Thay đổi
  tất cả). Không ACL thêm, không hỏi mật khẩu admin, không đệ quy (giữ như XF-T28).
- **Thông tin ổ** (builder G7 — `VolumeInfoWindow.swift` (mới)): định dạng, dung lượng, còn trống (dung lượng có thể giải phóng
  ghi riêng), đã dùng, điểm gắn; đọc nền có hạn giờ 2 s, ổ mạng treo ⇒ cửa sổ hiện ngay, bỏ còn trống. Gọi từ ⌘I khi chọn ổ trong
  sidebar.

## W8 — Đám mây

- **Probe trước (luật Honesty)** (builder D8): trên máy này có iCloud Drive và `~/Library/CloudStorage` (OneDrive trước đây chưa
  có — kiểm lại). Google Drive / Dropbox chưa cài ⇒ cơ chế "Mở trong Google Drive" / "Sao chép link Drive" (xattr
  `com.google.drivefs.item-id#S` theo tài liệu công khai của Drive for desktop) và "Xem trên Dropbox.com" (đường dẫn web từ
  thư mục gốc) **chỉ làm khi đo được**; không đo được ⇒ mục menu không hiện (không bịa), ghi T-T30-CLOUD.
- `CloudProviders.swift` (mới): phát hiện nhà cung cấp theo `~/Library/CloudStorage/<Provider>-<account>` (Google Drive mỗi
  tài khoản một hàng có email, Dropbox một hàng, OneDrive, Box…, iCloud Drive khi bật), biểu tượng của app; tab Đám mây của
  Cài đặt (W4 khung): trạng thái cài / đang chạy / đăng nhập, "Mở <app>", "Kiểm lại", "Ẩn trong XFinder" (không ngắt đồng bộ).
- Hành động: **Tải về ngay** / **Gỡ bản tải** một hoặc nhiều mục cho mọi nhà cung cấp dùng File Provider
  (`FileManager.startDownloadingUbiquitousItem` / `evictUbiquitousItem`; Gỡ bản tải từ chối khi chưa tải lên xong); badge ở
  cả bốn kiểu xem (W2) với sáu trạng thái; chép/chuyển tệp chỉ-trên-mây ra ngoài thư mục đám mây ⇒ chặn + gợi ý Tải về ngay;
  chuyển mục đã tải ra khỏi thư mục đám mây ⇒ cảnh báo; Thùng rác mục Drive ⇒ xác nhận (thùng rác của Drive cũng nhận);
  Nén / Gộp loại thư mục đám mây; tìm trong iCloud không tải.
- Không bao giờ: đăng nhập Google/Dropbox trong app, đọc token, tải chỉ để xem thông tin.

## Nghiệm thu W7/W8

Test thuần (`FileInfoRules` mới: mục theo loại, Khoá xám, chỉ đọc từ tìm; `CloudProviders.parse` tên thư mục CloudStorage; luật
chặn chép chỉ-trên-mây), probe đám mây trong scratchpad có positive control (iCloud). T-T30-31…36: ⇧⌘P, ⌥⌘Y, ⌘I đủ năm mục,
⌘I trên ổ ngoài, Tải về ngay / Gỡ bản tải trong iCloud Drive, badge sáu trạng thái.
