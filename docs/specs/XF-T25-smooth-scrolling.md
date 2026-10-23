# XF-T25 — Cuộn chuột mượt

## 0. Câu việc

"Bánh xe chuột cuộn **trôi** như trackpad thay vì giật từng nấc — trackpad và Magic Mouse thì để nguyên."

## 1. Đo trước khi viết (2026-10-22, brief `scratchpad/feat/brief.md`)

| | XFinder (`6952224`) | Mos 4.3.0 (đo binary + defaults) | Ứng dụng tham chiếu (đo binary) |
|:--|:--|:--|:--|
| Cuộn mượt | không có (Q-MG-3 của chủ dự án: "cần tap cuộn riêng") | event tap + tự dựng scroll event (`CGEventCreate` + set field), nhịp `CVDisplayLink` | tap + `CGEventCreateScrollWheelEvent2`, nhịp `CADisplayLink`, phát hiện công cụ xung đột, tạm dừng khi chụp cuộn |
| Thiết lập | — | `smooth`, `speed` 1.0, `step` 75, `duration` ≈ 2,86, `reverse`, danh sách app | bật/tắt, đảo chiều, **Tốc độ** ("quãng mỗi nấc"), **Độ mượt** ("thời gian dàn chuyển động"), quy tắc theo app; "Trackpad giữ nguyên" |
| Tách trackpad | — | `IOHIDManager` (vendor/product id) | câu UI "Trackpad scrolling stays native" |

XFinder đã có: một tap trên luồng riêng (`GestureEngine`, mẫu inbox + CFRunLoopSource + `OSAllocatedUnfairLock`), cách gắn tag
sự kiện tự gửi (`eventSourceUserData`), và đo được trên máy này: Razer Basilisk lẫn Magic Mouse đều báo
`scrollWheelEventIsContinuous == 1` ⇒ **không** dùng `isContinuous` để tách trackpad.

## 2. Thiết kế

**2.1 Tách thiết bị bằng phase.** Một sự kiện cuộn được làm mượt khi và chỉ khi: không mang tag của XFinder, `ScrollPhase == 0`
và `MomentumPhase == 0`. Trackpad và Magic Mouse (cuộn bằng chạm) luôn có phase began/changed/ended hoặc momentum; bánh xe
chuột thì không. Bánh xe dòng (`isContinuous == 0`) ⇒ quãng = số dòng × 40 px × tốc độ; bánh xe pixel (`isContinuous == 1`,
không phase — Razer) ⇒ quãng = `PointDelta` × tốc độ. Trang cài đặt hiện **lần cuộn cuối** (bánh xe — đã làm mượt / trackpad —
giữ nguyên) để kiểm trên thiết bị thật.

**2.2 Hoạt ảnh.** Sự kiện gốc bị nuốt; quãng cộng vào "còn lại". Một bộ đếm khung (CFRunLoopTimer trên chính luồng của tap,
1/120 s, chỉ chạy khi còn quãng) gửi mỗi khung `còn lại × (1 − e^(−dt/τ))` px, τ = độ mượt / 3, phần lẻ được cộng dồn để
gửi số nguyên; còn < 0,5 px ⇒ gửi nốt và dừng bộ đếm. Đổi chiều giữa chừng ⇒ bỏ phần còn lại cũ. Sự kiện gửi đi là scroll
pixel (`CGEvent(scrollWheelEvent2Source:units:.pixel…)`), `isContinuous = 1`, không phase, gắn tag `XFSMTH`, gửi vào
session tap. Hai trục dọc/ngang độc lập.

**2.3 Thiết lập (ONE reader mỗi khoá, `SmoothScrollController`).** `smoothScroll.enabled` (Bool, **false** — tính năng nuốt
mọi sự kiện bánh xe, phải tự bật), `smoothScroll.speed` (Int %, 100, 50…300), `smoothScroll.smoothness` (Int ms, 220,
80…600), `smoothScroll.reverse` (Bool, false — chỉ bánh xe chuột, trackpad giữ cài đặt của macOS). Trang: thẻ "Cuộn chuột
mượt" trong trang **Chuột & cử chỉ**.

**2.4 Luồng & quyền.** Engine riêng (không chung tap với cử chỉ): một hàng đợi + CFRunLoop như `GestureEngine`; mọi việc
trong callback chỉ là cộng quãng — không bao giờ chạy hoạt ảnh trong callback. Cần quyền Trợ năng (đã có trong app); thiếu ⇒
trang nói rõ, engine không chạy. `tapDisabledByTimeout` ⇒ bật lại (kiểm `CFMachPortIsValid`).

**2.5 Xung đột.** Mos, LinearMouse, SmoothScroll… đang chạy ⇒ engine **tạm dừng** và trang ghi "Đang tạm dừng: <app> cũng
làm mượt cuộn" (hai lớp làm mượt chồng nhau). Chụp cuộn (XF-T26) đang chạy ⇒ tạm dừng.

## 3. Ca hỏng

| Ca | Trả lời |
|:--|:--|
| Tắt | không có tap, không bộ đếm — 0 chi phí |
| Thiếu quyền Trợ năng | tapCreate nil ⇒ trang báo, không giả vờ bật |
| Trackpad / Magic Mouse | có phase ⇒ đi thẳng, không đụng |
| Sự kiện tự gửi quay lại tap | tag `XFSMTH` ⇒ đi thẳng |
| Cử chỉ chuột (GestureEngine) tự gửi cuộn ("giữ nút + kéo") | tag `XFGEST` ⇒ đi thẳng (không làm mượt hai lần) |
| Lăn liên tục nhiều nấc | quãng cộng dồn, hoạt ảnh nối tiếp, không giật |
| Đổi chiều | bỏ phần còn lại, đi theo chiều mới ngay |
| Giữ ⇧ (macOS biến thành cuộn ngang) | trục ngang làm mượt như trục dọc |
| Giữ ⌘/⌥/⌃ khi lăn (zoom trong nhiều app) | **đi thẳng, không làm mượt** — app cần sự kiện gốc |
| App bị treo, tap timeout | bật lại tap, bỏ quãng dở |
| Mos/LinearMouse đang chạy | tạm dừng + nói rõ |
| Chụp cuộn đang chạy | tạm dừng trong phiên |
| Đảo chiều bật | chỉ bánh xe chuột; trackpad giữ "Cuộn tự nhiên" của macOS |
| Màn 60 Hz / 120 Hz | bộ đếm 1/120 s — phần thừa không hại (khung không vẽ thì sự kiện vẫn tới app) |

## 4. Nghiệm thu

Thuần (`SmoothScrollRulesTests`): phân loại (tag, phase, modifier); quãng theo dòng/pixel × tốc độ; hoạt ảnh hội tụ đúng tổng
quãng (tổng px gửi đi == quãng), không vượt, dừng khi < 0,5; đổi chiều; tốc độ/độ mượt bị kẹp vào khoảng. Mutation harness
mới `mutation-check-smooth-scroll.sh`. Catalog đủ 8 thứ. e2e: tap của chính harness đếm sự kiện XFSMTH khi gửi một sự kiện
bánh xe tổng hợp (không tag) ⇒ tổng pixel đúng.

## 5. Q / T

- Q-SS-1 tap riêng (đã chọn). Q-SS-2 hàng catalog chuẩn, khoá riêng (đã chọn). Q-SS-3 tách bằng phase (đã chọn).
- Q-SS-4 quy tắc theo app → v2. Q-SS-5 mặc định **tắt**. Q-SS-6 có xung đột ⇒ tạm dừng (không chạy song song).
- T-T25-1 bật, lăn bánh xe trong Safari/Finder/Xcode ⇒ trôi mượt; trang ghi "bánh xe — đã làm mượt".
- T-T25-2 cuộn trackpad ⇒ như cũ; trang ghi "trackpad — giữ nguyên".
- T-T25-3 ⌘ + lăn trong trình duyệt/Preview ⇒ zoom như cũ.
- T-T25-4 mở Mos ⇒ trang ghi tạm dừng; thoát Mos ⇒ chạy lại.
- T-T25-5 tắt ⇒ `ps` không thấy CPU, bánh xe như macOS gốc.
