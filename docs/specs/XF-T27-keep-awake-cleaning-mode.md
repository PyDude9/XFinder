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

## 4. Nghiệm thu

Thuần: hết hạn/còn hạn/khôi phục, pin, đếm Esc (5 trong 3 s, reset), kẹp phút. Mutation trong harness mới. Live: probe
`pmset -g assertions` thấy hai assertion "XFinder" khi bật; e2e Lau bàn phím: phím tổng hợp không tới cửa sổ thử, Esc×5 mở.

## 5. Q / T

- Q-T27-1 mặc định giữ cả màn hình sáng (đã chọn: bật — đúng câu việc "trình chiếu").
- Q-T27-2 ngưỡng pin 10 %.
- T-T27-1 bật Chống ngủ 15 phút, để yên ⇒ màn hình không tắt; `pmset -g assertions` có 2 dòng XFinder.
- T-T27-2 bật vô hạn, thoát XFinder, mở lại ⇒ vẫn bật.
- T-T27-3 Lau bàn phím ⇒ gõ không ra chữ, âm lượng không đổi; Esc×5 mở; để yên 2 phút tự mở.
