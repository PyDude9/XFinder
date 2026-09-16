# Changelog

Tất cả thay đổi đáng chú ý của XFinder được ghi ở đây, mới nhất ở trên.

## [1.1.0] — 2026-09

### Tìm kiếm / Bảng lệnh
- Tích hợp search kiểu TinyCast vào trang **Tìm kiếm** (QuickSearch), gỡ trang Command Palette riêng vốn làm project không build nổi.
- Bảng lệnh toàn cục (⌘K, đổi được phím) kiểu Spotlight/Raycast: hotkey Carbon `RegisterEventHotKey` (không cần Trợ năng), recorder phím tùy chỉnh.
- Tìm file chuyển sang **NSMetadataQuery** (index Spotlight tức thì, thay cho spawn `mdfind`).

### Clipboard
- Trả lại trang nội dung Clipboard truy cập từ sidebar; thêm phân loại `markdown`.
- Quản lý bảng ghim (Categories): sửa tên/xoá ngay trong Cài đặt Clipboard.
- Kéo-thả item vào bảng → tự đổi màu theo màu bảng.

### Cửa sổ
- ⌘Tab: sửa switch app (kAXFrontmost + activateAllWindows), hiện cảnh báo thiếu quyền Ghi màn hình.
- Vùng bắt dính: nhận diện kéo-thanh-tiêu-đề chuẩn hơn, chặn nhầm khi bấm menu bar/Dock, sửa toạ độ đa màn hình.

### Biểu tượng thanh menu
- Nút mũi tên ẩn icon (cơ chế Hidden Bar). Tạm tắt tính năng này chờ giải pháp ẩn riêng icon app.
- Icon menubar có màu (bộ chọn kính lúp / thư mục / chồng lớp).

### Khay thả
- Bỏ summon ở Notch; khay không tự đóng — chỉ tắt bằng nút Close.
- Kiểu DropOver: stack gọn + nút "Xem chi tiết" mở cửa sổ lưới thẻ từng file (cắt bớt khi quá nhiều).

### Ghi chú
- Chọn phông chữ (Hệ thống/Serif/Mono); hotkey ⌥⌘N / ⌥⌘L / ⌥⌘P.
- Nhập/Xuất Markdown / Văn bản / JSON (tương thích Antinote, Simplenote…).
- Ghi chú ghim luôn nằm trên cùng dải mép màn hình.
- Việt hoá editor + tự focus nội dung.

### Hệ thống / Công cụ
- Độ sáng: % bám theo thanh trượt (nguồn registry trên Apple Silicon không đọc lại được).
- Nén/Giải nén: mật khẩu + mức nén (ZIP), dropdown hành động sau khi xong (kiểu WinRAR).
- Quick Look: tích hợp link QuickLookVideo; Finder Sync Extension (`XFinderSync.appex`) — menu chuột phải "Thêm vào Khay thả".
- Ngôn ngữ: thêm tiếng Anh (sidebar + Tổng quan) + bộ chọn; app icon `.icns` tự tạo.
- `scripts/dev-setup.sh`: tạo chứng chỉ ổn định tự động + một lệnh build/ký/cài/nhắc quyền.
