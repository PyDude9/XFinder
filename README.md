# XFinder

Tiện ích hệ thống + quản lý clipboard cho macOS. Gọn nhẹ, chạy native, **100% cục bộ — không thu thập dữ liệu, không gửi gì lên mạng**.

**Nền tảng**: macOS 14.0+ · Apple Silicon (arm64) · Swift 5.8 · SwiftUI + AppKit
**Tác giả**: thang0todev@gmail.com
**Giấy phép**: [MIT](LICENSE)

---

## Tính năng

**Giám sát hệ thống** — CPU, RAM, ổ đĩa, pin (độ chai, số chu kỳ, công suất), mạng (↓/↑ theo thời gian thực, speedtest).

**Clipboard** — lịch sử dạng thẻ, pinboard, tìm kiếm (kèm OCR ảnh qua Vision), Quick Look, Paste Stack. Bộ lọc riêng tư tự động bỏ qua nội dung từ trình quản lý mật khẩu.

**Cửa sổ** — xem trước khi rê chuột lên icon trên Dock, vùng bắt dính (snap) 10 vị trí, **cử chỉ chuột theo ứng dụng**.

**Cử chỉ chuột** — giữ một nút (mặc định **Nút 3** — bấm con lăn), kéo theo hướng, thả để gửi phím tắt của app đang dùng. Ưu tiên preset: **Edge/Safari/Chrome, VS Code/Cursor/Zed/Antigravity/Claude, Photoshop/CapCut, Discord/Zalo/AyuGram, Kitty/Terminal/iTerm2, Obsidian/Notion** đều có mapping dùng được ngay sau khi bật — không phải cấu hình gì thêm. Hành động mơ hồ (thao tác không có phím tắt chung đáng tin) để trống có chủ ý thay vì đoán bừa. Chi tiết: [docs/MOUSE_GESTURES.md](docs/MOUSE_GESTURES.md).

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

- **Trợ năng (Accessibility)** — bắt dính cửa sổ, xem trước cửa sổ, phím tắt toàn hệ thống, nút độ sáng, **cử chỉ chuột**.
- **Tự động hoá (Automation)** — chuyển giao diện Sáng/Tối toàn hệ thống.

### Cử chỉ chuột — bắt đầu nhanh

1. **Cửa sổ → Chuột & cử chỉ** → cấp **Trợ năng**.
2. Bật **Bật cử chỉ chuột**.
3. Giữ **Nút 3** (bấm con lăn xuống), kéo lên/xuống/trái/phải rồi thả.

Xong — các app được hỗ trợ đã có phím tắt dựng sẵn. Ghi nút, nhập bundle ID
hay ghi phím đều là tuỳ chỉnh **không bắt buộc**. Cấp quyền xong không cần khởi
động lại XFinder: quay về app là Event Tap được mở ngay, và công tắc đã bật thì
tap được arm ngay từ lúc mở app (không cần mở lại trang này).

**Nút được đặt tên theo số** vì đó là định danh duy nhất đúng với mọi con chuột:
macOS đếm từ 0 nên `mouseButton(2)` là **Nút 3** bạn đang bấm. Số nút in ngay trên
mỗi mũi tên của sơ đồ (`Nút 3 ↑`) và trong tiêu đề bảng chi tiết
(`Nút 3: kéo lên`), nên không phải đoán đang giữ nút nào. Ba nút ai cũng có được
kèm ghi chú ngắn: **Nút 1** (chuột trái, bị chặn), **Nút 2** (chuột phải),
**Nút 3** (bấm con lăn xuống). Từ Nút 4 trở đi chỉ là số — XFinder **không** biết
nút nào trên con chuột cụ thể của bạn, vì macOS không cung cấp thông tin thiết bị
trong luồng sự kiện.

Preset dựng sẵn — đây **chính xác** là phím XFinder gửi:

| Nhóm app | ↑ | ↓ | ← | → |
|---|---|---|---|---|
| Edge · Safari · Chrome | ⌘T | ⌘W | ⌃⇧Tab | ⌃Tab |
| VS Code · Cursor · Zed · Antigravity · Claude | — | — | ⌃- | ⌃⇧- |
| Photoshop · CapCut | ⌘0 | ⌘Z | `[` | `]` |
| Discord · Zalo · AyuGram | — | — | ⌥↑ | ⌥↓ |
| Kitty · Terminal · iTerm2 | — | — | ⌥← | ⌥→ |
| Obsidian · Notion | ⌘P | — | ⌘⌥← | ⌘⌥→ |
| Excel · Word | — | — | — | — |
| App không có trong danh sách | ⌘⇧] | ⌘⇧[ | ⌘[ | ⌘] |

"—" là **cố ý để trống**, không phải thiếu preset: những thao tác đó không có
phím tắt chung đáng tin giữa các app trong nhóm (Word không có worksheet; "mở
chat" khác nhau ở từng IDE; `⌘W` trong Terminal có thể giết tiến trình đang chạy).
Dấu "—" trong một app **đã có preset sẽ không rơi về bảng toàn cục** — nó không
gửi gì cả. Muốn khác thì **Ghi phím** riêng cho hướng đó. Tên hành động là ý
định; app hoặc bản macOS của bạn có thể gán khác, nên đối chiếu với phím tắt thật
của app.

Bảng **Global** (áp cho app không có profile riêng) gửi **điều hướng trang/mục**
chứ không phải Mission Control: `⌘[` / `⌘]` lùi/tiến theo lịch sử, `⌘⇧[` / `⌘⇧]`
chuyển mục, tilt là zoom. Bản cũ gửi `⌃↑ ⌃↓ ⌃← ⌃→` và hầu như không dùng được vì
chuột như MX Master 3 đã tự gán Mission Control vào nút ngón cái trong Logi Options.

---

## Tự build

Yêu cầu Xcode 15 trở lên và macOS 14+.

```bash
xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Release build
```

Chạy test (logic thuần — hình học toạ độ, phân loại clipboard, kế hoạch đổi tên, so sánh phiên bản, phân giải preset cử chỉ chuột):

```bash
swift test --package-path Tests
```

Xem thêm [BUILDING.md](BUILDING.md).

---

## Liên hệ

Báo lỗi hoặc góp ý qua [GitHub Issues](https://github.com/PyDude9/XFinder/issues), hoặc email **thang0todev@gmail.com**.
