# XFinder

Tiện ích hệ thống + quản lý clipboard cho macOS. Gọn nhẹ, chạy native, **100% cục bộ — không thu thập dữ liệu, không gửi gì lên mạng**.

**Nền tảng**: macOS 14.0+ · Apple Silicon (arm64) · Swift 6 · SwiftUI + AppKit
**Tác giả**: thang0todev@gmail.com
**Giấy phép**: [MIT](LICENSE)

---

## Tính năng

### Chỉ bật thứ bạn dùng

Trang **Tính năng & Quyền** (sidebar → CHUNG) có hai tab — *Tính năng* (đầu trang là các điều khiển máy: âm lượng, thiết bị âm thanh ra, độ sáng, giao diện sáng/tối, chống ngủ, tự ẩn Dock, ẩn icon Desktop) và *Quyền* — và gom mọi tính năng chạy nền vào một chỗ:

- **Công tắc từng tính năng** — mỗi công tắc ghi đúng khoá mà chính tính năng đó đọc, nên trang riêng của tính năng và trang này không bao giờ lệch nhau. Tắt là **ngừng hẳn** bộ lắng nghe/hẹn giờ, không chỉ ẩn.
- **Nhãn chi phí khi rảnh** — "Không chạy nền", "Lắng nghe bàn phím", "Lắng nghe chuột", "Có bộ hẹn giờ". Nhãn phải đúng: tính năng nào cài event tap hay timer thì không được tự nhận là "không chạy nền" (có test chặn).
- **Ba gói bật nhanh** — *Cửa sổ*, *Clipboard và tìm kiếm*, *Yên tĩnh* (tắt mọi thứ lắng nghe hay chạy hẹn giờ; danh sách này **suy ra từ danh mục**, thêm tính năng mới thì tự được tính).
- **Tab Quyền** — Trợ năng, Ghi màn hình, Micro, Nhận dạng giọng nói: đã cấp hay chưa, tính năng nào dùng, cảnh báo khi *có tính năng bật mà thiếu quyền* và khi *đã cấp mà không gì cần nữa*. Mọi quyền đều tùy chọn.

Tính năng đã tắt **không** làm biến mất hàng trong sidebar — trang của nó vẫn mở được và nói rõ nó đang tắt.

### Popover trên thanh menu

Một biểu tượng, các mục tách thành tab: **Điều khiển · Chống ngủ · Hệ thống · Mạng · Ổ đĩa · Pin · Ghi chú**. Tab *Điều khiển* có âm lượng, chọn thiết bị âm thanh ra, chống ngủ, chế độ tối, tắt tiếng và **các công tắc tính năng nhóm theo Cửa sổ / Clipboard / Công cụ / Giọng nói** (cùng khoá với trang Tính năng & Quyền).

**Chọn mục hiển thị**: bấm biểu tượng con mắt ở đầu mục để bật/tắt từng tab — không phải lúc nào cũng cần xem hết. Luôn còn ít nhất một tab (công tắc cuối bị khoá), tab đang xem bị ẩn thì chuyển sang tab đầu tiên còn hiện, và mục mới của bản sau tự hiện mặc định.

### Danh mục tính năng

| Nhóm | Tính năng | Ghi chú |
|---|---|---|
| Cửa sổ & Dock | Xem trước Dock · Chuyển ứng dụng ⌘-Tab · Vùng bắt dính · **Giữ ⌘Q để thoát** | cần Trợ năng; xem trước cần thêm Ghi màn hình |
| Clipboard | Khay ⌘⇧V · **Làm sạch liên kết** (bỏ tham số theo dõi) · Tab Gợi ý · **Tự xoá clipboard** sau một khoảng thời gian | chỉ xoá clipboard hệ thống sau 30 giây – 15 phút kể từ lần chép, và không xoá thứ bạn chép sau đó; lịch sử của XFinder vẫn giữ bản ghi |
| Công cụ | Bảng lệnh ⌘K · Ghi chú mép màn hình · Khay thả file · Đồng bộ thư mục · **Lấy màu từ màn hình** (chép dạng `#RRGGBB`) | |
| Giọng nói | Nhập bằng giọng nói | cần Trợ năng + Micro + Nhận dạng giọng nói |
| Âm thanh | **Chọn thiết bị âm thanh ra** ngay trong popover | chỉ hiện khi có từ 2 thiết bị trở lên |
| Cổng mạng | **Cổng đang mở** (sidebar → KẾT NỐI): tiến trình nào đang giữ cổng, kèm nhãn *Mọi mạng / Chỉ máy này*, nút **Dừng** (SIGTERM, hỏi xác nhận) và **Buộc dừng** (SIGKILL) nếu tiến trình phớt lờ | chỉ dừng được tiến trình của chính bạn; tiến trình hệ thống/người dùng khác macOS không cho XFinder xem nên được đếm và nói rõ, không giả vờ danh sách đầy đủ |
| Giám sát | CPU · **GPU %** (đọc từ IORegistry) · RAM · ổ đĩa kèm **trạng thái SMART** · pin · mạng | không có số nào bị bịa — xem mục *Giới hạn đã biết* |

**Giám sát hệ thống** — CPU, RAM, ổ đĩa, pin (độ chai, số chu kỳ, công suất), mạng (↓/↑ theo thời gian thực, speedtest).

**Clipboard** — lịch sử dạng thẻ, pinboard, tìm kiếm (kèm OCR ảnh qua Vision), Quick Look, Paste Stack. Bộ lọc riêng tư tự động bỏ qua nội dung từ trình quản lý mật khẩu.

**Cửa sổ** — xem trước khi rê chuột lên icon trên Dock, vùng bắt dính (snap) 10 vị trí, **cử chỉ chuột theo ứng dụng**.

**Cử chỉ chuột** — giữ một nút hông, kéo theo hướng, thả để gửi phím tắt của app đang dùng. Ưu tiên preset: **Edge/Safari/Chrome, VS Code/Cursor/Zed/Antigravity/Claude, Photoshop/CapCut, Excel/Word, Discord/Zalo/AyuGram, Kitty/Terminal/iTerm2, Obsidian/Notion** đều có mapping dùng được ngay sau khi bật — không phải cấu hình gì thêm. Hành động mơ hồ (không có phím tắt chung đáng tin) để trống **có chủ ý** thay vì đoán bừa, và mỗi dòng hiện **cả ý định lẫn phím chính xác** sẽ gửi. Sơ đồ vẽ **đúng các nút mô tả HID của chuột bạn khai báo** (nút nào không đọc được thì vẽ mờ, không bấm được), và trang **đo** con số nút khi bạn bấm thật, để bạn biết cử chỉ có chạy hay không thay vì phải tin. Chi tiết: [docs/MOUSE_GESTURES.md](docs/MOUSE_GESTURES.md).

**Ghi chú** — ghi chú dán mép màn hình, hiện ra khi rê chuột.

**Nhập bằng giọng nói** — giữ phím, nói, thả ra là chữ vào đúng ô đang gõ. Sáu chế độ (chép nguyên văn · tút lại & xóa từ thừa · soạn email · văn phong chuyên nghiệp · gạch đầu dòng · câu lệnh riêng), thanh trạng thái nổi vẽ sóng âm theo **buffer âm thanh thật**, xem lại dạng so sánh trước khi chèn, và bốn tầng mô hình: **Apple Intelligence trên máy** · **Ollama** · **khoá API riêng** (OpenAI/Groq/Anthropic/Gemini/OpenRouter/DeepSeek) · *đăng nhập tài khoản ChatGPT/Claude*. Khoá API lưu trong **Keychain**, không bao giờ nằm trong tệp cấu hình. Chi tiết: [docs/VOICE.md](docs/VOICE.md).

**Công cụ** — đổi tên hàng loạt (có hoàn tác), nén/giải nén, công cụ PDF, khay thả file, Quick Look nâng cao, tìm kiếm Spotlight + tìm kiếm bằng ngôn ngữ tự nhiên (xử lý hoàn toàn trên máy).

---

## Giới hạn đã biết

Một số chỉ số macOS không cung cấp API công khai, XFinder hiển thị trạng thái thật thay vì số liệu suy đoán:

- Nhiệt độ CPU / GPU: **không khả dụng** (SMC không có API công khai)
- % GPU: **có** — đọc từ IORegistry (`IOAccelerator`), đã đo bám tải thật; chỉ hiện "Không khả dụng" khi phần cứng không công bố giá trị
- SMART ổ đĩa: chỉ trạng thái Verified/Failing (qua `diskutil`), **không** có bảng thuộc tính
- Độ sáng màn hình: chỉ tăng/giảm, không hiện %
- Mạng theo từng app: số liệu lấy mẫu, ghi rõ "≈"

---

## Cài đặt

Tải bản mới nhất ở trang [Releases](https://github.com/PyDude9/XFinder/releases), giải nén và kéo `XFinder.app` vào thư mục `/Applications`.

Trong app, mở **Giới thiệu → Kiểm tra cập nhật** để so sánh phiên bản đang chạy với bản phát hành mới nhất trên GitHub.

### Quyền cần cấp

XFinder hỏi quyền đúng lúc cần và nói rõ thiếu quyền nào:

- **Trợ năng (Accessibility)** — bắt dính cửa sổ, xem trước cửa sổ, phím tắt toàn hệ thống, nút độ sáng, **cử chỉ chuột**, **nhập bằng giọng nói**.
- **Micro + Nhận dạng giọng nói** — chỉ khi bạn dùng **nhập bằng giọng nói**.
- **Tự động hoá (Automation)** — chuyển giao diện Sáng/Tối toàn hệ thống.

### Cử chỉ chuột — bắt đầu nhanh

1. **Cửa sổ → Chuột & cử chỉ** → cấp **Trợ năng**.
2. Bật **Bật cử chỉ chuột**.
3. Giữ **nút giữ** (mặc định là một nút hông — xem cách xác định bên dưới), kéo
   lên/xuống/trái/phải rồi thả.

Xong — các app được hỗ trợ đã có phím tắt dựng sẵn. Ghi nút, nhập bundle ID
hay ghi phím đều là tuỳ chỉnh **không bắt buộc**. Cấp quyền xong không cần khởi
động lại XFinder: quay về app là Event Tap được mở ngay, và công tắc đã bật thì
tap được arm ngay từ lúc mở app (không cần mở lại trang này).

**Bấm vào bảng số trên thân chuột trong sơ đồ để đổi nút giữ.** Đó là thao tác
duy nhất cần làm, và nó là *tuỳ chọn*: preset đã chạy trước khi bạn chạm vào.

### Nút nào? Đọc số đo, đừng đoán

XFinder **không** nói "nút hông trên" hay "nút ngón cái" như một sự thật, vì không
API nào trả lời được câu đó: `CGEventField` chỉ có năm trường chuột và cao nhất là
`mouseEventButtonNumber` — **không có trường vendor/product/device nào**.

Thay vào đó, trang **đo**:

1. Bấm thử nút bạn định dùng. Trang hiện **"Nút bạn vừa bấm: 4"** ngay dưới dòng thiết bị
   — đó là con số XFinder thật sự nhận được từ chuột bạn (engine vốn đã nhận mọi lần bấm,
   nên không cần bật gì thêm).
2. **Ghi nút** rồi bấm đúng nút đó — hoặc bấm **Đặt làm nút giữ** ngay ở dòng tương ứng.

Số trên UI là **cách bạn đếm** (macOS đếm từ 0, nên `mouseButton(2)` hiển thị
**Nút 3**). Ba nút ai cũng có còn có **tên mô tả** — **Nút trái**, **Nút phải**,
**Bấm con lăn xuống** — nhưng tên đó chỉ nằm ở **tooltip** và ở **dòng rộng trong danh
sách**, không ở sơ đồ (một ô sơ đồ rộng 46 pt). Từ nút thứ tư trở đi chỉ là số, kèm một
gợi ý có điều kiện ("thường là nút hông trên"), vì thứ tự khai báo trong HID descriptor
chứng minh một nút **tồn tại** chứ không cho biết nó **ở đâu**.

**Nút cuộn (tuỳ chọn, mặc định tắt):** giữ một nút hông rồi kéo là cuộn — tiện cho
Photoshop/CapCut. Nút đó vẫn bấm bình thường khi bạn không kéo, và XFinder tự sửa nếu
bạn ghi trùng nút giữ.

Preset dựng sẵn — **ý định** của từng hướng, kèm phím XFinder gửi. Riêng bốn hành động hệ
thống của bảng Global, "phím" chính là **phím bạn đã gán trong macOS** (xem bên dưới), nên
cột đó ghi hành động thay vì một ký tự cố định:

| Nhóm app | ↑ | ↓ | ← | → |
|---|---|---|---|---|
| Edge · Safari · Chrome | ⌘T | ⌘W | ⌘[ | ⌘] |
| VS Code · Cursor · Zed · Antigravity · Claude | — | — | ⌘[ | ⌘] |
| Photoshop · CapCut | ⌘0 | ⌘Z | `[` | `]` |
| **Excel** | ⌘+ | ⌘- | ⌃⇧⇥ | ⌃⇥ |
| **Word** | ⌘+ | ⌘- | — | — |
| Discord · Zalo · AyuGram | — | — | ⌥↑ | ⌥↓ |
| Kitty · Terminal · iTerm2 | — | — | ⌥← | ⌥→ |
| Obsidian · Notion | ⌘P | — | ⌘⌥← | ⌘⌥→ |
| App không có trong danh sách (Global) | Mission Control | App Exposé | Space trước | Space kế tiếp |

"—" là **cố ý để trống**, không phải thiếu preset: những thao tác đó không có
phím tắt chung đáng tin giữa các app trong nhóm (Word **không có worksheet** — nên
Word và Excel là **hai bảng riêng**; "mở chat" khác nhau ở từng IDE; `⌘W` trong
Terminal có thể giết tiến trình đang chạy). Dấu "—" trong một app **đã có preset sẽ
không rơi về bảng toàn cục** — nó không gửi gì cả. Muốn khác thì chọn từ menu hành
động hoặc **Ghi phím** cho hướng đó.

**Tên hành động là ý định; phím tắt mới là điều chắc chắn.** XFinder gửi *đúng phím
hiện trên trang*; việc phím đó có làm đúng hành động hay không còn tuỳ phím tắt riêng
của app — macOS cho phép đổi gần như mọi phím tắt. Vì vậy nếu bạn ghi một phím riêng,
XFinder **không gán tên hành động cho nó** (hiện "Phím bạn tự ghi"), thay vì mượn tên
của preset rồi nói sai về app của bạn.

Bảng **Global** (áp cho app không có profile riêng) phủ bốn hành động hệ thống ai cũng cần:
**Mission Control** (↑), **App Exposé** (↓), **Space trước** (←), **Space kế tiếp** (→).
Đây **không** phải bốn phím hằng số: XFinder **đọc chính phím tắt bạn đã đặt** trong
Hệ thống → Bàn phím → Phím tắt rồi gửi **đúng phím đó**, nên hàng trên trang luôn bằng phím
thực sự được gửi. Máy bạn chưa gán phím cho hành động nào thì hàng đó **nói thẳng “chưa gán
trong macOS”** và cử chỉ **không gửi gì** — thay vì bắn một phím không ai nghe.

Hai bản trước gửi hai cơ chế đều sai, và cả hai đều đo được: `⌃↑ ⌃↓` như hằng số (máy này
**không** gán chúng), rồi keytype hệ thống số 32 (một keytype **không tồn tại** — `ev_keymap.h`
chỉ định nghĩa tới `NX_KEYTYPE_MENU = 25`). Đó chính là nguyên nhân của báo cáo “nhận dạng cho
có, không làm việc”. App **không có** preset riêng thì mới dùng bảng này; app **đã có preset
nhưng hướng đó “—”** thì **không** rơi về Global — nó không gửi gì.

---

## Nhập bằng giọng nói — bắt đầu nhanh

1. **CÔNG CỤ → Nhập bằng giọng nói** → bật công tắc, rồi cấp **Trợ năng**, **Micro** và
   **Nhận dạng giọng nói** (mỗi dòng quyền có nút yêu cầu ngay cạnh).
2. Đặt con trỏ vào ô văn bản bất kỳ, **giữ Option Phải (⌥)**, nói, rồi **thả ra**.

Xong — chữ vào đúng ô đang gõ. Chưa cấu hình nhà cung cấp AI thì XFinder chèn **bản gốc**
(chế độ *Chép nguyên văn* không cần AI), chứ không làm mất lời bạn vừa nói.

Trong phiên nói: **`Space`** chèn ngay bản gốc (không đợi AI), **`Esc`** hủy và khôi phục
clipboard. Bật *Xem lại trước khi chèn* thì **`Return`** chèn bản đã tút, **`Esc`** bỏ.

> **Đăng nhập tài khoản ChatGPT Plus / Claude Pro không được hỗ trợ, và đây là lý do thật:**
> không có OAuth công khai nào cấp quyền dùng API cho hai gói đó, nên cách duy nhất để "đăng
> nhập hộ" là dùng cookie phiên trình duyệt của bạn để gọi endpoint nội bộ của web app — vi
> phạm điều khoản của cả hai, hỏng mỗi lần họ đổi giao diện. Trang nói rõ điều đó và trỏ
> sang khoá API thay vì ship một nút đăng nhập không thể chạy.

Chi tiết đầy đủ: [docs/VOICE.md](docs/VOICE.md).

---

## Đã kiểm chứng tới đâu

Bốn mức, tách rời — không gộp:

| Mức | Trạng thái |
|---|---|
| Build (`arm64`, đủ file trong compile log) | ✅ |
| Test logic (399 test) | ✅ |
| Event Tap mở được trên app đã cài (`active=1 trusted=1`) | ✅ |
| **Chuột thật: giữ nút hông + kéo có mở Mission Control / đổi Space** | ⏳ **cần mắt người xác nhận** |

Bằng chứng hiện có: engine phát **đúng chord mà chính máy bạn khai**, tap đang mở, và trang
hiển thị đúng phím đó. Việc cuối — macOS có **thực sự** đổi Space hay không — phải do mắt
người xác nhận; log “đã gửi” chỉ chứng minh sự kiện được phát, **không** chứng minh hệ thống
phản hồi. Danh sách chính xác các phép đo: [docs/GESTURE_VERIFICATION.md](docs/GESTURE_VERIFICATION.md).

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
