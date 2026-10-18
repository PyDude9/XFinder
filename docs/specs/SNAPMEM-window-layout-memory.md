# SNAPMEM — Nhớ bố cục cửa sổ theo bộ màn hình (Vùng bắt dính)

Đặc tả cho tính năng chủ dự án yêu cầu 2026-10-18: *"Snap Zone có option giữ bố cục màn hình sau khi tôi đã lựa chọn
xong: luôn giữ maximum window của Chrome sau khi tôi đã chọn; khi dùng màn hình ngoài thì nhớ vị trí bố cục cửa sổ đó,
cũng như bố cục trong Space đó là chia đôi hoặc app đó đang fullscreen."*

## 1. Câu việc và phạm vi

**Câu việc:** "Tôi đã xếp Chrome (nửa trái / toàn màn hình) trên bộ màn hình này một lần. Lần sau mở Chrome, hoặc cắm lại
màn ngoài, nó phải về đúng chỗ đó mà tôi không phải xếp lại."

**Đo trước khi thiết kế (2026-10-18, macOS 27.0, M3 Pro + HC-L200A):**

| Probe | Kết quả |
|:--|:--|
| Định danh màn hình công khai | `CGDisplayCreateUUIDFromDisplayID` trả UUID ổn định (`37D8832A…` màn trong, `62512806…` HC-L200A); vendor/model/serial đọc được — màn ngoài khai **serial = 1** (chung chung), nên hai màn cùng model có thể trùng UUID |
| `AXFullScreen` trên cửa sổ chuẩn | đọc được (0) **và** `AXUIElementIsAttributeSettable` = true — toàn màn hình nhớ và áp lại được qua AX công khai |
| Space | **không có API công khai** cho biết cửa sổ ở Space nào. SkyLight private (`SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace`) đếm được: màn trong 2 Space (desktop + fullscreen), màn ngoài 1 — chỉ đo, **không ship** (Q-SNAPMEM-1) |

**Trong phạm vi (v1):** nhớ theo **bộ màn hình đang cắm** (Arrangement = tập UUID màn hình) × **app** (bundle id):
layout = một ô bắt dính của XFinder, hoặc **toàn màn hình**, hoặc (tuỳ chọn) **khung tự kéo** chuẩn hoá theo vùng hiển
thị của màn đó. Áp lại khi app mở cửa sổ đầu tiên sau khi khởi động, và khi bộ màn hình đổi (cắm/rút).

**Ngoài phạm vi:** phân biệt Space thường (cần private API — Q-SNAPMEM-1); nhớ nhiều cửa sổ của cùng một app (v1 chỉ
cửa sổ chính); áp lại liên tục khi người dùng tự kéo (sẽ "đánh nhau" với tay người).

## 2. Luật

1. **Một app vào bộ nhớ chỉ khi người dùng bắt dính nó bằng XFinder** (kéo mép, phím tắt, hàng notch, nút "Bắt dính
   ngay"). Không có luật nào tự ghi app chưa từng được chọn — "sau khi tôi đã lựa chọn" là điều kiện vào.
2. Sau khi có luật, XFinder đặt **một AXObserver cho app đó khi nó đang chạy** (như Thoát ứng dụng): cửa sổ mới → áp
   lại; cửa sổ chính đổi kích thước → đọc `AXFullScreen`, bật/tắt toàn màn hình thì cập nhật luật; di chuyển/đổi cỡ →
   chỉ cập nhật khi "Nhớ cả vị trí tự kéo" bật. Không luật, không observer: chi phí lúc nghỉ bằng 0.
3. **Khung ghi theo tỉ lệ** so với vùng hiển thị của màn (0…1), nên đổi độ phân giải cùng màn vẫn đúng. Khung trùng
   một ô bắt dính (sai số 4 pt) được ghi là ô đó, không phải khung.
4. **Áp lại một lần mỗi lần app khởi động**: cửa sổ đầu tiên xuất hiện → chờ 0,5 s (app hay tự khôi phục vị trí của
   nó) → đặt; kiểm tra lại ở 2 s, lệch thì đặt **thêm đúng một lần** rồi thôi — không bao giờ lặp vô hạn.
5. **Đổi bộ màn hình** → chờ 1 s cho hệ thống ổn định → áp luật của bộ mới cho mọi app đang chạy có luật.
6. Mọi ghi do chính XFinder gây ra bị bỏ qua trong 1,5 s (`ownWriteGrace`) để không tự ghi lại chính mình; không ghi
   khi nút chuột đang giữ (người dùng đang kéo).
7. Luật khoá theo **bộ màn hình đầy đủ**: luật ghi với "màn trong + HC-L200A" không áp khi chỉ còn màn trong (và ngược
   lại) — mỗi bộ có luật riêng cho cùng một app.
8. Toàn màn hình: đưa cửa sổ về màn đã ghi trước, rồi đặt `AXFullScreen = true`; app không cho đặt (`IsAttributeSettable`
   = false) → ghi kết quả "không đặt được" lên hàng luật, không thử lại.
9. Mỗi hàng luật trên trang hiện **kết quả lần áp gần nhất** (đã áp / thiếu quyền / không thấy cửa sổ / không đặt được).
   Người dùng xoá từng luật hoặc xoá hết. Tối đa 200 luật, bỏ luật cũ nhất.

## 3. Khoá và nơi đọc (một khoá một control)

| Khoá | Mặc định | Reader duy nhất |
|:--|:--|:--|
| `snapzones.remember` | `false` | `SnapMemoryController` |
| `snapzones.rememberFrames` | `false` | `SnapMemoryController` |
| `snapzones.memory.v1` | — (JSON `SnapMemory.Store`) | `SnapMemoryController` |

Mặc định **tắt**: tính năng đặt observer lên app khác và tự di chuyển cửa sổ lúc app mở — phải được xin phép.

## 4. Các ca hỏng phải có câu trả lời (AGENT_QUICKSTART luật 11)

| Ca | Trả lời |
|:--|:--|
| App tự khôi phục vị trí sau khi ta đặt (Chrome, VS Code) | đặt ở 0,5 s, kiểm lại 2 s, đặt thêm một lần — luật 4 |
| Thiếu Trợ năng | không observer, không áp; trang hiện banner quyền (đã có); hàng luật ghi "thiếu quyền" |
| App có nhiều cửa sổ (Chrome 3 cửa sổ) | chỉ cửa sổ chính (`AXMainWindow`, rồi `AXFocusedWindow`, rồi cửa sổ đầu) — nói rõ trên trang |
| Cửa sổ chính chưa có kích thước lúc `windowCreated` | độ trễ 0,5 s trước lần đặt đầu |
| Cùng model màn, serial = 1 | UUID trùng ⇒ cùng khoá; ghi chú trên trang "hai màn cùng loại có thể bị coi là một" |
| Người dùng kéo cửa sổ đã ghi sang chỗ khác, "nhớ vị trí tự kéo" tắt | luật giữ nguyên ⇒ lần mở sau vẫn bắt dính lại ("luôn giữ") |
| Người dùng kéo, "nhớ vị trí tự kéo" bật | debounce 0,6 s, chỉ khi không giữ chuột; khung chuẩn hoá; khớp ô bắt dính thì ghi ô |
| Ta tự đặt ⇒ AX báo moved/resized | bỏ qua trong `ownWriteGrace` 1,5 s |
| App thoát giữa chừng | `kill(pid, 0)` trước mỗi lần đặt; observer gỡ khi app kết thúc |
| App ẩn (⌘H) | subrole cửa sổ đổi (F3 đo) — không lọc theo subrole; áp lên cửa sổ chính |
| Người dùng đang kéo cửa sổ khi màn hình đổi | `pressedMouseButtons` ⇒ hoãn 1 s rồi thử lại một lần |
| Quá nhiều luật | trần 200, bỏ cũ nhất |
| JSON hỏng trong defaults | decode lỗi ⇒ kho rỗng, không crash |
| Toàn màn hình không settable | ghi "không đặt được", không lặp |
| Đăng ký AXObserver trả -25204 khi app đang khởi động | thử lại 0,5 / 1,5 / 3 s như E7, không nhớ lần gắn hỏng |

## 5. Nghiệm thu

- `swift test --package-path Tests --filter SnapMemory` xanh; `scripts/mutation-check-snap.sh` S10–S14 đỏ.
- `FeatureKeyDefaultsTests` có hàng cho hai khoá Bool; `FeatureCatalog` có `.snapMemory` (`watchesWindows`, Trợ năng);
  `FeatureContractTests` trỏ `Core/Snap/SnapMemory.swift`.
- e2e (app thử nghiệm riêng, không đụng cửa sổ của chủ dự án): luật `leftHalf` cho bundle thử → mở app thử → cửa sổ
  nằm đúng nửa trái (CGWindowList) trong < 3 s; không luật ⇒ không di chuyển.
- Test tay T-SNAPMEM-1…4 trong `docs/PENDING_TESTS_AND_DECISIONS.md`.
