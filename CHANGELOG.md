# Changelog

Tất cả thay đổi đáng chú ý của XFinder được ghi ở đây, mới nhất ở trên.

## [1.3.0] — 2026-10

### Notch (mới hoàn toàn)
- **Khay thả sống ở notch**: kéo tệp lên notch để giữ, lắc chuột để mở khay dưới con trỏ, rê chuột xem nhanh, kéo ra để dùng. Hub làm việc trên tệp đang giữ: ZIP, Gộp PDF, Sang PDF, Sang JPEG/PNG, Thu nhỏ ảnh (giữ chuột để chọn cỡ), Tách nền, OCR, AirDrop.
- **Live activity**: sạc / pin đầy, mất mạng, Caps Lock, Bluetooth kết nối, cảnh báo hệ thống, âm lượng, hẹn giờ.
- **Đang phát**: bài đang phát từ mọi player (qua trợ giúp Apple ký), ⏮ ⏯ ⏭, tua, xáo trộn, lặp lại.
- **Clipboard trên notch** (⌘⇧V mặc định mở ở đây): hàng thẻ ngang, lọc `@loại`/`@app`, Paste Stack, biến đổi văn bản, đi tới nguồn, khoá Touch ID.
- **Phiên Claude Code**: trạng thái từng phiên và Cho phép / Từ chối yêu cầu quyền ngay trên notch (hook công khai, cài bằng nút).
- **Lịch**: hôm nay, việc kế tiếp, âm lịch theo giờ Việt Nam, nút Tham gia cho link họp.
- Chia cửa sổ ở notch (hàng 7 bố cục, phần ba, Tập trung); một cửa sổ cố định cho mọi trạng thái (không còn giật), bấm xuyên qua phần trong suốt; chọn trang, thứ tự, màu nhấn, độ nhạy rê chuột; notch ảo trên màn không notch; ẩn khỏi ảnh chụp/quay.

### Clipboard
- **Thư viện Clipboard**: mọi clip từng copy, lọc theo loại / app / bảng / thời gian, bảng chi tiết, dán vào app trước đó.
- **Bảng khoá**: mã hoá bằng khoá Secure Enclave, mở từng thẻ bằng Touch ID; không bao giờ xuất qua MCP hay `.xfinderclip`.
- Tô màu code, xuất/nhập `.xfinderclip`, **Clipboard MCP** (`XFinder --mcp`, tắt mặc định), màu `rgb()`/`hsl()`, tạm dừng ghi, chọn âm copy, phát âm, sửa văn bản, xem trước link (opt-in — lần duy nhất clipboard dùng mạng).

### Công cụ mới
- **Chụp & chú thích** (kiểu OneNotch): chụp vùng / cửa sổ / toàn màn hình, thẻ xem trước nổi (tự đóng, dừng khi trỏ vào, kéo thả, vuốt để đóng), trình chú thích (mũi tên, khung, chữ, số thứ tự, làm mờ, tô sáng, cắt), ghim ảnh lên màn hình. Phím tắt chưa gán sẵn; có nút dùng bộ phím giống OneNotch.
- **Chọn văn bản thông minh**: bôi đen chữ ở app khác → đổi đơn vị, tiền tệ (opt-in, Vietcombank cho VND), múi giờ, tính, thêm vào Lịch, dịch (⇧⌘G).
- **Dọn rác thư mục** (chỉ rác metadata đã biết), **Gỡ ứng dụng** (app + phần sót lại), **Thoát ứng dụng** (giữ ⌘Q; tự thoát app trong danh sách khi đóng cửa sổ cuối).
- ⌘-Tab: Q đóng cửa sổ, H ẩn app, Space phóng ảnh, `` ` `` chuyển app ↔ cửa sổ. Chép chữ từ màn hình, nhiệt độ SoC, cảnh báo hệ thống, số liệu trên thanh menu.
- Giao diện: mọi trang dùng chung một hệ token; cửa sổ **Có gì mới** mỗi phiên bản.

### Sửa lỗi đáng kể
- Nén từ hai mục trở lên **chưa bao giờ chạy** (`ditto` chỉ nhận một nguồn); giải nén không còn ghi đè im lặng; từ chối archive có link trỏ ra ngoài.
- Dán một clip dài hơn 200 ký tự bị **cắt cụt** (227 mục trong lịch sử của máy đo đã mất phần đuôi — không khôi phục được).
- Lịch sử clipboard **nạp rỗng** lúc khởi động; kết nối Bluetooth **làm sập app**; gõ `1+` vào ⌘K **làm sập app**.
- Trang Thư viện từng chiếm **886 MB** (đọc nguyên video, TIFF icon app) — nay 79 MB.

### Đo được
- Bộ nhớ (physical footprint, app đã ổn định 90 s): **26,7 MB** với cài đặt thường, **25,1 MB** khi tắt mọi tính năng chạy nền. CPU khi rảnh: **0,00 s / 60 s**.

### Giới hạn đã biết
- Ký bằng chứng chỉ tự tạo, chưa notarize — Gatekeeper chặn lần mở đầu. Chỉ Apple Silicon.
- Chưa có ai bấm thử bằng tay: xem `docs/PENDING_TESTS_AND_DECISIONS.md` (các mục T-*), gồm toàn bộ Chụp & chú thích.
- Chưa quay màn hình; chưa ẩn được icon thanh menu của app khác trên macOS 27 (cơ chế không còn — đã đo).

## [1.2.0] — 2026-10

Gộp luôn các thay đổi của 1.1.1 (chưa từng được phát hành riêng) bên dưới.

### Tính năng & Quyền (trang mới) và thiết lập lần đầu
- Trang **Tính năng & Quyền**: công tắc từng tính năng chạy nền (ghi đúng khoá mà chính tính năng đó đọc), nhãn chi phí khi rảnh, ba gói (Cửa sổ / Clipboard / Yên tĩnh), tab **Quyền** (đã cấp/chưa, ai dùng, cảnh báo quyền thừa). Các điều khiển máy (âm lượng, thiết bị âm thanh ra, độ sáng, sáng/tối, chống ngủ, tự ẩn Dock) dồn vào đầu tab Tính năng; trang "Điều khiển nhanh" cũ đã gộp vào đây.
- **Thiết lập lần đầu**: chọn gói Tối giản / Hằng ngày / Tất cả rồi chỉ xin quyền mà lựa chọn đó dùng. XFinder không còn tự xin Trợ năng, Ghi màn hình, Bluetooth ngay khi mở.
- **Sao lưu cài đặt**: xuất/nhập JSON (chỉ cài đặt; tệp nhập được coi là đầu vào không tin cậy).
- Ô **tìm trang** ở sidebar (gõ không dấu, khớp cả hai ngôn ngữ).

### Tính năng mới
- **Cổng đang mở**: tiến trình nào đang giữ cổng, Dừng / Buộc dừng có xác nhận. Quét bằng `libproc` (netstat trả 0 byte khi bị spawn); không thấy tiến trình hệ thống/người dùng khác và nói rõ điều đó.
- **Giữ ⌘Q để thoát** (opt-in), **Làm sạch liên kết** khi sao chép, **Tự xoá clipboard**, **chọn thiết bị âm thanh ra**, **lấy màu từ màn hình**.
- **Popover thanh menu** dựng lại: tab, công tắc tính năng nhóm gập, chọn mục hiển thị.
- **GPU %** (đọc từ IORegistry) và **SMART** hiển thị thật thay cho placeholder sai.

### Sửa lỗi đáng kể
- `VolumeObserver` đăng ký listener nhân đôi mỗi lần đổi thiết bị (63 lần rebind trên 6 lần đổi) và điếc khi không có output.
- Ba công tắc không nối vào đâu (xem cửa sổ ẩn ⌘-Tab, gợi ý clipboard, xem trước liên kết): hai cái được nối thật, một cái bị gỡ.
- Cửa sổ thiết lập không dùng sheet vì sheet làm ⌘Q không thoát được.

### Giới hạn đã biết
- Bản này **ký bằng chứng chỉ tự tạo**, không có Developer ID và chưa được Apple notarize; Gatekeeper sẽ chặn lần mở đầu — xem ghi chú phát hành để mở.
- Chỉ Apple Silicon (arm64).
- Chưa kiểm bằng chuột/micro thật: cử chỉ chuột chạy thật, nhập giọng nói.

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
