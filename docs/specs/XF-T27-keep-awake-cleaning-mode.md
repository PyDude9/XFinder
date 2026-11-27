# XF-T27 — Chống ngủ hoàn chỉnh + Chế độ lau bàn phím

## 0. Câu việc

- Chống ngủ: "Máy **và màn hình** không ngủ trong lúc tôi đang tải, build hay trình chiếu — và không giữ máy thức tới cạn pin."
- Lau bàn phím: "Khoá bàn phím vài phút để lau, không gõ nhầm gì, và không thể bị kẹt."

## 1. Đo trước khi viết (2026-10-23)

| | XFinder (`8506d7f`) | Ứng dụng tham chiếu (changelog 2.1.0 chủ dự án gửi) |
|:--|:--|:--|
| Chống ngủ | `CaffeineController`: `PreventUserIdleSystemSleep` — **màn hình vẫn tắt**; 15 phút…vô hạn; mất khi app khởi động lại/cập nhật; không để ý pin | giữ máy **và màn hình**; 15 phút–8 giờ, vô hạn; **tắt khi pin yếu**; **tiếp tục sau khi khởi động lại/cập nhật** |
| Lau bàn phím | không có | khoá bàn phím; **Esc 5 lần** hoặc nút Mở khoá; **tự mở sau 1–5 phút** |

## 2. Thiết kế

**2.1 Chống ngủ.** `caffeine.keepDisplayOn` (Bool, **true**): thêm assertion `PreventUserIdleDisplaySleep` cùng lúc. Hết hạn
lưu ở `caffeine.until` (Double, giây từ 1970; 0 = tắt; −1 = vô hạn) — app mở lại thấy còn hạn ⇒ bật lại phần còn lại. Đang chạy
bằng pin và pin ≤ 10 % ⇒ tắt + thông báo "Đã tắt Chống ngủ vì pin yếu" (kiểm mỗi lần đếm ngược, không timer mới). Luật thuần
`CaffeineRules` (thời điểm hết hạn, còn hạn hay không, có phải tắt vì pin không).

**2.1b Giữ thức khi đóng nắp (phụ lục).** `caffeine.requestLidWake` (Bool, mặc định **`false`** — giữ nguyên mặc định hiện có, khai báo trong `CaffeineRules.Key.requestLidWake` và kiểm trong `FeatureKeyDefaultsTests`). Chỉ dùng API công khai `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep, ...)` và chỉ tạo assertion `"XFinder: Closed-display wake request"` khi đủ cả ba điều kiện: `isActive == true && requestLidWake == true && onACPower`. Trên trang Hệ thống trong Notch (`354 pt` hữu dụng ở khổ hẹp), hàng `caffeineControls` phải vừa đủ menu thời lượng Caffeine, bộ đếm / nút Dừng, công tắc đóng nắp (nhãn gọn, ví dụ "Đóng nắp" / "Lid closed") và nút mở Settings mà không bị `.clipped()` ở cả VI và EN. UI phải trung thực giữa trạng thái **đã yêu cầu** (`requestLidWake`) và **đang có hiệu lực** (`lidAssertionActive`): khi công tắc BẬT nhưng Caffeine đang TẮT hoặc đang chạy pin, hiển thị trạng thái chờ / lý do chưa có hiệu lực thay vì giả vờ đang hoạt động; tooltip nêu rõ yêu cầu cắm nguồn và giới hạn macOS (đóng nắp không có màn hình ngoài vẫn có thể ngủ). Đồng bộ cùng tùy chọn trong `SystemControlsPanel` khi máy có pin (`hasBattery == true`).

**2.2 Lau bàn phím.** `CleaningMode` (luật thuần + controller): một event tap nuốt `keyDown/keyUp/flagsChanged` và phím hệ thống
(âm lượng/độ sáng, `NX_SYSDEFINED`); chuột vẫn chạy. Một lớp phủ mờ trên mọi màn hình: "Đang lau bàn phím — bấm Esc 5 lần
hoặc Mở khoá", đồng hồ đếm ngược. Esc 5 lần trong 3 s ⇒ mở. Tự mở sau `cleaning.minutes` (Int, **2**, 1…5). Vào: menu bar
"Lau bàn phím…", nút trên trang Hệ thống. Tap chỉ tồn tại trong lúc lau.

## 3. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Chống ngủ vô hạn, rút sạc, pin tụt dưới 10 % | tắt, báo |
| Đang cắm sạc, pin 5 % | không tắt (đang sạc) |
| App thoát rồi mở lại còn 20 phút | bật lại, còn ~20 phút |
| App mở lại sau khi đã hết hạn | không bật |
| Tắt "giữ màn hình sáng" khi đang chạy | bỏ assertion màn hình ngay, giữ assertion hệ thống |
| Lau bàn phím không có quyền Trợ năng | không khoá được ⇒ báo, không giả vờ |
| Tap bị macOS tắt (timeout) giữa lúc lau | bật lại; hết hạn vẫn tự mở |
| Esc lẫn phím khác | đếm lại từ đầu khi gặp phím không phải Esc hoặc quá 3 s |
| App treo / crash khi đang lau | tap chết theo process ⇒ bàn phím tự về |
| Màn hình khoá trong lúc lau | không đổi gì, tự mở theo hẹn |
| Máy không có pin (`hasBattery == false`, Mac để bàn) | ẩn hẳn công tắc giữ thức khi đóng nắp |
| Bật công tắc đóng nắp khi Caffeine đang TẮT | lưu `requestLidWake = true`, KHÔNG tạo assertion (`lidAssertionActive == false`), UI báo trạng thái chờ bật Caffeine |
| Đang chạy pin (rút sạc giữa chừng hoặc bật khi chưa cắm sạc) | KHÔNG tạo / tự nhả assertion `PreventSystemSleep` ngay khi rút sạc; cắm lại khi Caffeine đang chạy thì tự tạo lại; UI báo cần cắm nguồn |
| Pin tụt ≤ 10 % khi đang chạy pin | tắt Chống ngủ và nhả toàn bộ assertion kể cả lid-wake |
| Đóng nắp khi không có màn hình ngoài (Apple Silicon) | macOS vẫn có thể cho máy ngủ dù có assertion — tooltip/mô tả nói thật, không hứa vượt giới hạn OS |
| Chuỗi VI/EN dài trong hàng Notch khổ hẹp `354 pt` | nhãn gọn + giữ ưu tiên bố cục để dropdown thời lượng, timer, nút Dừng, công tắc đóng nắp và nút Settings đều hiện đủ không bị cắt |

## 4. Nghiệm thu

Thuần: hết hạn/còn hạn/khôi phục, pin, đếm Esc (5 trong 3 s, reset), kẹp phút. Mutation trong harness mới. Live: probe
`pmset -g assertions` thấy hai assertion "XFinder" khi bật; e2e Lau bàn phím: phím tổng hợp không tới cửa sổ thử, Esc×5 mở.

## 5. Q / T

- Q-T27-1 mặc định giữ cả màn hình sáng (đã chọn: bật — đúng câu việc "trình chiếu").
- Q-T27-2 ngưỡng pin 10 %.
- T-T27-1 bật Chống ngủ 15 phút, để yên ⇒ màn hình không tắt; `pmset -g assertions` có 2 dòng XFinder.
- T-T27-2 bật vô hạn, thoát XFinder, mở lại ⇒ vẫn bật.
- T-T27-3 Lau bàn phím ⇒ gõ không ra chữ, âm lượng không đổi; Esc×5 mở; để yên 2 phút tự mở.
