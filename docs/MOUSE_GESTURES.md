# Chuột & cử chỉ / Mouse & Gestures

> Có trong source hiện tại. **Không đồng nghĩa đã phát hành trên Releases.**
> Đây là bộ gửi phím tắt theo cử chỉ; không tự gọi API riêng của từng app.

## Bắt đầu

1. Mở XFinder → **CÔNG CỤ → Chuột & cử chỉ**.
2. Cấp **Trợ năng / Accessibility** cho đúng bản XFinder đang chạy. Quay lại XFinder
   để thử mở Event Tap lần nữa; trang hiển thị lỗi nếu không mở được.
3. Bật **Bật cử chỉ chuột**. Mặc định tính năng **tắt**, tilt **tắt**, debug **tắt**.
4. Nút mặc định là **nút giữa, Button 2** theo mã CoreGraphics (không phải số in
   trên phần mềm hãng). Chọn **Ghi nút / modifier**, rồi nhấn nút chuột mong muốn
   hoặc một modifier ⌃ / ⌥ / ⇧ / ⌘. Nút trái được giữ riêng, không cho gán.
5. Giữ trigger, kéo lên/xuống/trái/phải, rồi thả: gửi đúng một hành động.
6. Nếu cần thay đổi phím: chọn app, chọn hướng → **Ghi phím**, nhấn tổ hợp mong muốn.
   **Esc**, **Hủy ghi**, rời trang hoặc hết 10 giây sẽ hủy ghi.

**Đổi chuột:** binding không gắn vào hãng/serial. Nếu chuột mới phát cùng mã nút thì
binding dùng tiếp; nếu khác, ghi lại. Magic Mouse không được giả định có nút giữa:
có thể chọn modifier + di chuyển chuột. Không nhận diện riêng từng thiết bị bằng HID.

## Phân biệt click và gesture

- Deadzone mặc định **12 đơn vị delta CoreGraphics**, chỉnh bằng slider. Không phải
  12 point màn hình, không phải khoảng cách vật lý; DPI/driver có thể đổi cảm giác.
- Tổng quãng đường **nhỏ hơn** ngưỡng: phát lại cặp down/up tại vị trí click ban đầu,
  giữ button, modifiers và click count. Click vì thế xảy ra **khi thả nút**, không
  ngay lúc nhấn. Không dùng nút này cho native hold/drag/orbit trong app 3D.
- Đi đủ xa rồi quay về gần điểm bắt đầu: **không click**, không gửi phím.
- Chọn hướng theo tổng delta cuối; đường chéo bằng nhau ưu tiên trục dọc.
- Modifier vẫn được chuyển cho hệ thống để không làm hỏng các shortcut thông thường.
  Gõ phím hoặc nhấn nút khác trong khi giữ sẽ hủy stroke; không giả lập “click modifier”.
- Đổi app, sleep/chuyển phiên, đổi cấu hình hoặc Event Tap bị tắt sẽ hủy stroke.
  Không phát click bù vào app vừa được chuyển tới.
- Hold quá 15 giây sẽ hủy; có drain tạm thời cho release đã bị chặn. Khi tắt trong
  lúc đang giữ, tap có thể còn tối đa 15 giây để thu hồi release, sau đó được gỡ.

## Mapping mặc định — đây chính xác là phím XFinder gửi

Các tên tác vụ là **ý định sử dụng**, không phải đảm bảo mọi phiên bản ứng dụng
đều có cùng shortcut. Tùy chỉnh bàn phím macOS/app có thể đổi kết quả. Ưu tiên
phím hiển thị trong XFinder và shortcut thật của ứng dụng bạn dùng.

| Profile | Giữ + ↑ | Giữ + ↓ | Giữ + ← | Giữ + → | Tilt ← / → (opt-in) |
|---|---|---|---|---|---|
| Global, app không khớp profile | ⌃↑ — Mission Control* | ⌃↓ — App Exposé* | ⌃← — Space trái* | ⌃→ — Space phải* | ⌘[ / ⌘] — lịch sử nếu app hỗ trợ |
| Edge, Safari, Chrome | ⌘T — tab mới | ⌘W — đóng tab | ⌃⇧Tab — tab trước | ⌃Tab — tab sau | Cả hai gửi ⌘⇧T — mở lại tab vừa đóng |
| VS Code, Cursor, Zed, Antigravity, Claude | **Chưa gán** | **Chưa gán** | ⌃- | ⌃⇧- | Chưa gán |
| Photoshop, CapCut | ⌘0 | ⌘Z | [ | ] | **Chưa gán** |
| Discord, Zalo, AyuGram | **Chưa gán** | **Chưa gán** | ⌥↑ | ⌥↓ | Chưa gán |
| Excel, Word | **Chưa gán** | **Chưa gán** | **Chưa gán** | **Chưa gán** | Chưa gán |
| Obsidian, Notion | ⌘P | **Chưa gán** | ⌘⌥← | ⌘⌥→ | Chưa gán |

\* Global gửi shortcut, không dùng private API để ép Mission Control/Spaces.
Phải bật đúng các shortcut đó trong cài đặt bàn phím macOS. Không khẳng định kết
quả nếu bạn đã đổi hoặc tắt chúng.

### Những mục chủ động KHÔNG gán tự động

- Dev/AI ↑: `⌃\`` có thể là terminal nhưng không phải “chat UI” chung cho mọi app.
- Dev/AI ↓: AI refactor và format code là hai hành động khác nhau.
- Chat ↑/↓: unread, đầu trang và cuối trang không phải một hành động chung.
- Office ←/→: Word không có worksheet; không gán shortcut Excel cho Word.
- Notes ↓: tạo block/page khác nhau giữa Notion và Obsidian.
- Design tilt: không gọi cuộn ngang thông thường là “smooth timeline scrubbing”.
  Có thể chọn **Cuộn ngang nguyên bản** để chuyển tiếp sự kiện, không thêm smoothing.

Những ô này có **Ghi phím** riêng theo app. “Chưa gán” trên profile đã khớp **không
rơi về Global**; nó không gửi phím. Không cần tạo thêm tính năng AI hay quản lý tab.

### Bundle IDs được nhận diện

| Nhóm | Bundle IDs |
|---|---|
| Browser | `com.microsoft.edgemac`, `com.apple.Safari`, `com.google.Chrome` |
| Dev/AI | `com.visualstudio.code`, `com.cursor.ide`, `dev.zed.Zed`, `com.antigravity.ide`, `com.anthropic.claude` |
| Design | `com.adobe.Photoshop`, `com.lemon.CapCutMac` |
| Chat | `com.hnc.Discord`, `com.vng.zalo`, `org.telegram.ayugram` |
| Office | `com.microsoft.Excel`, `com.microsoft.Word` |
| Notes | `co.elastic.obsidian`, `com.notion.Notion-App` |

Đây là các ID cấu hình theo yêu cầu, không phải kết quả kiểm kê app đã cài.
Nếu bản app của bạn dùng ID khác (beta, fork…), chọn **Dùng ứng dụng vừa hoạt động**
hoặc nhập bundle ID trong trang cấu hình. Profile tùy chỉnh kế thừa Global cho
những hướng chưa override; đặt **Chưa gán** để vô hiệu hóa riêng một hướng.
Nút **Khôi phục mapping mặc định của ứng dụng** xóa override của profile đang chọn,
không reset trigger, deadzone hay app khác.

## Tilt, driver và tránh xung đột

- Tilt độc lập với trigger, chỉ bật khi công tắc chính và công tắc tilt đều bật.
- Chỉ nhận scroll ngang **rời rạc**, axis dọc bằng 0. Cuộn liên tục/momentum của
  trackpad và Magic Mouse được giữ nguyên. Không thể coi mọi ngang scroll là
  thao tác nghiêng bánh xe thật: Event Tap không cung cấp nhận diện vật lý ở đây.
- Giới hạn một shortcut tilt mỗi **350 ms**, chống đóng/mở tab hàng loạt khi giữ tilt.
- Nếu driver biến tilt thành nút phụ thay vì scroll ngang, ánh xạ tilt này không nhận;
  có thể ghi nút đó làm trigger, hoặc chỉnh driver. XFinder không tự đoán VID/PID.
- Tắt mapping trùng trong Mac Mouse Fix, Mos, Logitech Options, Razer hoặc app khác.
  Thứ tự event tap giữa các app không được bảo đảm.
- Không thay thế Snap Zones, Dock Preview, Clipboard hoặc Finder Keyboard.
  Trigger trái bị cấm để tránh chiếm thao tác kéo/chọn thông thường.

## Hiệu năng và kiến trúc

- `GestureEngine`: queue serial `.userInteractive` riêng + CFRunLoop nhận Mach port;
  callback không ở main thread. Main actor chỉ quản lý UI, UserDefaults và nhận
  thông báo đổi ứng dụng từ NSWorkspace.
- Motion path O(1), không dispatch task cho từng sample, không polling con trỏ.
  Worker ngủ trên run loop khi không có event/command. Tắt tính năng thì gỡ tap;
  không tạo worker ở lần chạy đầu nếu chưa bật hoặc ghi binding.
- Chỉ timer một lần cho ghi binding và hold timeout. Không có timer toàn app.
- Event tổng hợp có marker để tránh tự bắt lại click/phím do engine phát.
- Khi timeout làm tap bị disable: hủy stroke và re-enable **port còn hợp lệ**.
  Không invalidate rồi enable chính port đã hủy. Đây không phải bảo đảm không bao
  giờ timeout trên mọi phần cứng hoặc trong Secure Input.
- Debug mặc định tắt; tối đa 4 bản ghi/giây trên utility queue. Log chỉ gồm bundle ID
  và tổng delta/quãng đường, không ghi nội dung phím hoặc văn bản, không gửi mạng.
- Cấu hình lưu cục bộ trong `mouseGestures.configuration.v1` (UserDefaults JSON).
  Phím được ghi bằng virtual key code: đổi keyboard layout có thể đổi ký tự.

## Kiểm chứng và giới hạn

Build/logic test không chứng minh chuột Razer 8 kHz đã được kiểm thử. Xem
[GESTURE_VERIFICATION.md](GESTURE_VERIFICATION.md) để biết chính xác các phép đo,
những gì đã pass và phần cần thao tác bằng phần cứng thật.

Chạy kiểm tra:

```sh
swift test --package-path Tests
swiftc -swift-version 6 \
  XFinder/Core/MouseGestures/GestureModel.swift \
  XFinder/Core/MouseGestures/GestureEngine.swift \
  Tests/Runtime/MouseGesturesProbe.swift -o /tmp/xfinder-gesture-probe
/tmp/xfinder-gesture-probe
# Riêng lần này sẽ thử mở event tap thật trong 2 giây, trigger là Button 31:
/tmp/xfinder-gesture-probe --live-tap
```

Harness mặc định dùng callback production nhưng thu event đầu ra trong bộ nhớ,
**không gửi click/phím vào ứng dụng khác**. Test package dùng symlink tới model
production để tránh bản sao logic bị lệch. Mutation test phải chạy trên scratch
copy, không sửa nguồn thật trong lúc app đang build.

## Tham khảo

- [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix): trải nghiệm giữ nút + kéo.
- [Mos](https://github.com/Caldis/Mos): trải nghiệm cấu hình chuột/cuộn theo ứng dụng.

Chỉ tham khảo README và ý tưởng tương tác; module này viết riêng, không sao chép
source, không nhúng thư viện của hai dự án và không tuyên bố tương đương mọi tính năng.
