# XFinder

Tiện ích hệ thống + quản lý clipboard cho macOS. Gọn nhẹ, chạy native, **100% cục bộ — không thu thập dữ liệu, không gửi gì lên mạng**.

**Nền tảng**: macOS 14.0+ · Apple Silicon (arm64) · Swift 5.8 · SwiftUI + AppKit
**Tác giả**: thang0todev@gmail.com
**Giấy phép**: [MIT](LICENSE)

---

## Tính năng

**Giám sát hệ thống** — CPU (tổng + top ứng dụng đang dùng nhiều nhất), RAM, ổ đĩa, pin (độ chai, số chu kỳ, công suất), mạng (↓/↑ theo thời gian thực, speedtest).

**Clipboard** — lịch sử dạng thẻ, pinboard, tìm kiếm (kèm OCR ảnh qua Vision), Quick Look, Paste Stack. Bộ lọc riêng tư tự động bỏ qua nội dung từ trình quản lý mật khẩu.

**Cửa sổ** — xem trước khi rê chuột lên icon trên Dock, vùng bắt dính (snap) 10 vị trí.

**Ghi chú** — ghi chú dán mép màn hình, hiện ra khi rê chuột.

**Công cụ** — đổi tên hàng loạt (có hoàn tác), nén/giải nén, công cụ PDF, khay thả file, Quick Look nâng cao, tìm kiếm Spotlight + tìm kiếm bằng ngôn ngữ tự nhiên (xử lý hoàn toàn trên máy).

---

## Giới hạn đã biết

Một số chỉ số macOS không cung cấp API công khai, XFinder hiển thị trạng thái thật thay vì số liệu suy đoán:

- Nhiệt độ CPU / GPU, % GPU, SMART ổ đĩa: **không khả dụng**
- Độ sáng màn hình: chỉ tăng/giảm, không hiện %
- Mạng theo từng app: số liệu lấy mẫu, ghi rõ "≈"

---

## Cài đặt

Tải bản mới nhất ở trang [Releases](https://github.com/PyDude9/XFinder/releases), giải nén và kéo `XFinder.app` vào thư mục `/Applications`.

Trong app, mở **Giới thiệu → Kiểm tra cập nhật** để so sánh phiên bản đang chạy với bản phát hành mới nhất trên GitHub.

### Quyền cần cấp

XFinder hỏi quyền đúng lúc cần và nói rõ thiếu quyền nào:

- **Trợ năng (Accessibility)** — bắt dính cửa sổ, xem trước cửa sổ, phím tắt toàn hệ thống, nút độ sáng.
- **Tự động hoá (Automation)** — chuyển giao diện Sáng/Tối toàn hệ thống.

---

## Tự build

Yêu cầu Xcode 15 trở lên và macOS 14+.

```bash
xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Release build
```

Chạy test (logic thuần — hình học toạ độ, phân loại clipboard, kế hoạch đổi tên, so sánh phiên bản):

```bash
swift test --package-path Tests
```

Xem thêm [BUILDING.md](BUILDING.md).

---

## Liên hệ

Báo lỗi hoặc góp ý qua [GitHub Issues](https://github.com/PyDude9/XFinder/issues), hoặc email **thang0todev@gmail.com**.
