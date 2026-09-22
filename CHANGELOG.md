# Changelog

Tất cả thay đổi đáng chú ý của XFinder được ghi ở đây, mới nhất ở trên.

## [1.1.1] — 2026-09

### Chuột & cử chỉ
- Nút chuột đặt tên **theo số** (`Nút 3`) vì `CGEventField` chỉ có 5 trường chuột và **không có** trường vendor/product — không code nào biết nút vật lý nào là gì.
- Bảng **Global** thay Mission Control (trùng nút cái đã có trong Logi Options) bằng ⌘⇧] / ⌘⇧[ / ⌘[ / ⌘] và ⌘= / ⌘- cho nghiêng.
- Thêm profile **Kitty / Terminal / iTerm2** — chỉ `⌥←` / `⌥→`; cố ý không gán `⌘T`/`⌘W` vì `⌘W` có thể giết tiến trình đang chạy.
- Nghiêng con lăn mặc định **tắt** (`tiltAvailable = false`): đo được mọi sự kiện cuộn từ Basilisk *và* Magic Mouse đều báo `scrollWheelEventIsContinuous = 1, axis2 = 0`, nên hai nhánh nghiêng không bao giờ chạy.

### Finder Sync
- **Sửa được lỗi extension chưa từng đăng ký/chạy.** Ba nguyên nhân độc lập, đều thất bại im lặng:
  appex để `MACOSX_DEPLOYMENT_TARGET = 27.0` (nay 14.0 + `LSMinimumSystemVersion` tường minh),
  `ENABLE_DEBUG_DYLIB` sinh stub `.debug.dylib` (nay NO), và script ký xoá mất entitlement sandbox của appex (nay ký kèm entitlements, app ngoài không dùng `--deep`).
- `pluginkit` giờ liệt kê `+ com.xfinder.app.XFinderSync(1.0)` trỏ `/Applications`; tiến trình extension chạy ổn định, không còn crash `ImageIO`.
- Dọn **16 đường dẫn build chết** cùng đăng ký plugin identifier (staging, `/tmp`, DerivedData, bản copy Desktop) — chúng chặn việc phân giải extension.

### Kiểm thử
- `verify-gesture-ui.sh` và `mutation-check-gesture-ui.sh` còn trỏ vào cấu trúc L10n 4-store đã gỡ — nay đọc `L10n.strings.json`; mutation case 5 trước đây **xanh** (sửa vào dòng không còn tồn tại) nay **đỏ** với 16 assertion.

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
- Quick Look: tích hợp link QuickLookVideo; Finder Sync Extension (`XFinderSync.appex`) — menu chuột phải "Thêm vào Khay thả" (đã đăng ký/chạy thật từ 1.1.1).
- Ngôn ngữ: thêm tiếng Anh (sidebar + Tổng quan) + bộ chọn; app icon `.icns` tự tạo.
- `scripts/dev-setup.sh`: tạo chứng chỉ ổn định tự động + một lệnh build/ký/cài/nhắc quyền.
