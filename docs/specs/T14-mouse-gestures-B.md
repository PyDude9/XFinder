# T14 — Chuột & cử chỉ, phương án B (Sơ đồ chuột + bảng bên)

Đặc tả này đủ để một model rẻ (DeepSeek qua OpenCode) dựng lại trang mà không cần đọc
`CONTRACT.md` hay `inventory.md` — nhưng khi có mâu thuẫn, hai file đó (trong
`~/github/XFinder-design/mouse-gestures-2026-10-15/`) và `variant-b.html` thắng đặc tả này.

## 1. Mục tiêu, và cái gì KHÔNG được đụng

**Câu việc của người dùng:** "Tôi cầm chuột, tôi giữ một nút rồi kéo một hướng — trang này
phải cho tôi biết NGAY hướng đó gửi phím gì cho app tôi đang quan tâm, và cho tôi đổi nó
hoặc đổi nút giữ, không cần đọc bảng hay bấm thử."

**Ngoài phạm vi — không sửa, dù tiện tay:**
- `XFinder/Core/MouseGestures/GestureEngine.swift`, `GestureController.swift`,
  `GestureModel.swift`, `GestureMap.swift`, `DeviceCapabilityModel.swift`,
  `DeviceCapabilityTypes.swift`, `GestureLabelStructure.swift`, `GestureUIDisplay.swift`,
  `GestureSystemBindings`, `ScrollButtonRepair`, `TiltArmsVisibility` — **mọi logic, mọi bảng
  mapping, mọi default giữ nguyên**. Ba harness mutation của module này (`mutation-check-
  gesture-labels.sh`, `-ui.sh`, `-buttons.sh`) chỉ mutate các file Core này — nếu bước nào
  của bạn sửa một trong các file trên, bạn đã ra ngoài phạm vi: dừng và báo lại.
- **Không thêm UserDefaults key mới.** Mọi field đã có (`trigger`, `scrollButton`,
  `scrollButtonEnabled`, `tiltAvailable`, `tiltEnabled`, `buttonActions`, `overrides`,
  `holdButtonSingleClickEnabled`, `debug`) là đủ cho phương án B. Nếu khi dựng bạn thấy
  thật sự cần một key mới, viết vào worklog thay vì tự thêm — việc đó cần Claude duyệt.
- Không đổi `F27`/`DEBUG_SHOW_ENGINE_LOG` (vẫn `false`, khối hoạt động vẫn ẩn khỏi bản
  release) — chỉ dời `GestureActivityPanel` nếu bước nào cần, không bật nó lên.
- Không build app, không `swift test` kèm theo chạy app, không mở `xfinder://`, không chạy
  mutation script song song hoặc trong lúc một harness khác đang chạy.

## 2. Bản đồ F1–F29 / S1–S68 → nơi ở trong B

Nguồn: `inventory.md` tại thư mục design (đọc lại nếu một dòng dưới đây không khớp số dòng
hiện tại — tìm theo tên hàm, không theo số dòng).

### Luôn giữ, đổi chỗ

| # | Tên | Ở B, trong bước nào |
|---|---|---|
| F1 | Công tắc Bật/Tắt | Trailing của `PageHeader`, đổi từ `Toggle` kiểu checkbox sang `.toggleStyle(.switch)` (Lỗi #11) — Bước T14a |
| F2/F3 | Mở Cài đặt Trợ năng / Kiểm tra lại | Giữ nguyên `permissionBanner`, không đổi vị trí — Bước T14a |
| F4 | Chọn app/profile | Đổi từ `profileSidebar` (cột 240pt) sang **dải chip ngang** (Khối 3) — Bước T14b |
| F5 | Nút "Xem" | Gộp vào dòng phụ dưới dải chip (S9-S12), không lặp với việc bấm thẳng vào chip của app đó (Lỗi #15) — Bước T14b |
| F6 | Bấm một mũi tên | Giữ nguyên cơ chế chọn trên `MouseDiagramView`; panel bên phải (`b-insp`) thay cho `GestureDetailPanel` hiện render bên cạnh figure — Bước T14c |
| F7 | Bấm hold-badge trên hình | Giữ — đây vẫn là lối "bấm hình để đổi nút giữ" — Bước T14c |
| F8/F29 | Bấm chip nút trên hình / bấm dòng trong danh sách | Hai chọn cùng mở **cùng một** view inspector-theo-nút (Bước T14c); bỏ `GestureButtonList` làm danh sách riêng — nội dung của nó (role chip, cảnh báo, nút Ghi, Đặt làm nút giữ) chuyển vào Khối 5 (Nút hông) dạng hàng đơn giản như trong `variant-b.html`, KHÔNG còn danh sách cuộn dọc 6 dòng với popup riêng từng dòng |
| F9 | Menu chọn hành động | Giữ nguyên `GestureActionPicker`'s nguồn dữ liệu (`GestureActionCatalog.choices()`), đổi vỏ UI thành `xf-popup`-style (SwiftUI: `Menu` + label hiện tên hành động hiện tại, không phải icon `ellipsis.circle`) — Bước T14c |
| F10 | "Ghi phím tắt…" | Trong menu hành động, cuối danh sách — giữ — Bước T14c |
| F11 | Reset-hướng-này | Nút tròn cạnh tiêu đề panel (như `b-menu-reset` trong wireframe) — Bước T14c |
| F12 | "Mở Phím tắt trong Cài đặt" | Trong panel, khi `row.isUnboundSystemAction` — Bước T14c |
| F15 | "Đặt làm nút giữ" | **Chỉ còn ở ĐÂY**: view inspector-theo-nút (chọn 1 chip nút) — Bước T14c. Đây là nơi duy nhất đổi nút giữ (Lỗi #6) |
| F16 | Gán hành động (Back/Forward/Unassigned) cho nút hông | Khối 5 (Nút hông), mỗi hàng một `Menu` — Bước T14d |
| F17 | "Bấm nhanh = Tiến" | Khối 5, chỉ hiện khi `role == .holdTriggerWithAction` (tức nút giữ đang có click action) — Bước T14d |
| F19 | Mô tả HID thô | Trong `DisclosureGroup` "Chẩn đoán chuột" (Khối 8), lazy-load khi mở — Bước T14e |
| F20 | Công tắc nghiêng con lăn | Khối 7, ghi cả `tiltAvailable` VÀ `tiltEnabled` qua `TiltArmsVisibility.fields(forReveal:)` — giữ nguyên hàm gọi, đổi chỗ — Bước T14d |
| F22 | Công tắc giữ-nút-cuộn-để-cuộn | Khối 6 — Bước T14d |
| F24 | Bundle ID tuỳ chỉnh | Dưới dải chip, trong `DisclosureGroup` "Nâng cao — ứng dụng khác" liên kết từ nút "＋" ở cuối dải chip — Bước T14b |
| F25 | Reset toàn bộ profile | Giữ — đặt cuối bảng hành động theo app đang chọn (menu hoặc nút nhỏ cạnh app chip đang chọn), `.disabled(config.overrides[profile] == nil)` — Bước T14b |
| F26 | "Mở Phím tắt" footer | Khối 9 — Bước T14e |

### Hợp nhất (nhiều control cùng một field → một control)

| Nhóm Record nút giữ (F7, F13, F14-khi-đổi-trigger, F18, F21) | → **CHỈ CÒN F7 (bấm hold-badge trên hình) + nút "Ghi nút" trong Khối 6 (Nút giữ & cuộn)**. Hai chỗ, không phải một, vì CONTRACT chấp nhận "khối Nút giữ & cuộn giữ control riêng của nó" miễn là KHÔNG còn bản sao thứ ba — đọc kỹ: Lỗi #6 đòi "MỘT nơi"; biến thể B của CONTRACT mô tả nút giữ đổi được "bằng chip trên hình → Dùng làm nút giữ trong panel" (tức qua F8/F15, không phải record). Vậy: **ghi nút giữ bằng cách GHI (record) chỉ còn ở Khối 6** ("Nút giữ & cuộn" → nút "Ghi nút"); **đặt một nút đã khai báo làm nút giữ** chỉ còn qua inspector-theo-nút (F15, bấm chip trên hình). Xoá: F13 (badge không tự ghi khi bấm — đổi nghĩa: bấm hold-badge giờ CHỈ chọn/hiện inspector của nút giữ, không tự ghi — xem Bước T14c), F14 header-ghi trong danh sách cũ, F18, F21. |
| F23 (Ghi nút cạnh Nút cuộn, lỗi #1/#14) | → thay bằng **Picker** liệt kê nút đã khai báo (trừ nút giữ) + giá trị đang lưu — xem T15 bên dưới, đã làm nếu T15 chạy trước; nếu chưa, Bước T14d làm luôn |

### Số liệu/trạng thái (S…) — giữ nguyên ý nghĩa, đổi nơi hiện

| # | Ở B |
|---|---|
| S1 | Không còn — nhãn "Bật"/"Tắt" cạnh switch (vẫn F1) |
| S2 | `permissionBanner`, không đổi — T14a |
| S3-S6 | **Một `xf-note`/status line** (Khối 2), y hệt mapping 4 trạng thái trong wireframe (`du-lieu`→S4, tắt→S3, lỗi có tên→S5, lỗi chung→S6) — T14a |
| S7 | Tiêu đề + phụ đề của Khối 4 ("Sơ đồ cử chỉ") | T14c |
| S8-S12 | Dòng phụ dưới dải chip (Khối 3) | T14b |
| S13-S23 | Trong Khối 8 "Chẩn đoán chuột" (hàng "Thiết bị") | T14e |
| S24-S25 | Trong `DisclosureGroup` con "Mô tả HID thô" bên trong Khối 8 | T14e |
| S26 | Trong Khối 8, hàng "Nút bạn vừa bấm" | T14e |
| S27 | Dòng ghi trong status line khi `controller.recording` (đổi từ sidebar cũ) | T14a/T14c |
| S28 | View mặc định của panel bên phải khi chưa chọn gì — **nhưng B đòi panel KHÔNG BAO GIỜ trống**: thay S28 (hint dạy tương tác) bằng **bảng tóm tắt 4 hướng** như `variant-b.html` (`b-insp-empty-row` ×4). Giữ 2 câu giải thích ngắn của S28 làm `xf-footer` dưới bảng tóm tắt đó, không xoá — T14c |
| S29-S33 | Khối 8, hàng "Nút chuột XFinder thấy" + 2 ghi chú vendor/consumer — T14e |
| S34/S35 | Cảnh báo nút chưa khai báo / under-reported — chuyển vào Khối 5 (Nút hông), không còn ở Khối 8 vì đây là cảnh báo hành động được (có nút "Ghi"/"Bấm thử…"), khác với Khối 8 là chẩn đoán đọc-only — T14d |
| S36-S38 | Role chip + "Đang là nút giữ" + "Không đổi được" — trong hàng Khối 5 và trong inspector-theo-nút — T14c/T14d |
| S39 | "Nút do chuột tự xử lý" — cuối Khối 5, y hệt wireframe — T14d |
| S40 | Chú giải màu — giữ **nhưng đánh dấu `data-wf-lap`-tương-đương**: đặt cuối Khối 5, có thể bớt nếu các tag đã tự nói đúng chữ đó (wireframe làm vậy) — tuỳ chọn, không bắt buộc xoá — T14d |
| S41/S42 | Giải thích nghiêng — Khối 7 — T14d |
| S43-S46 | `activitySection`, vẫn sau `DEBUG_SHOW_ENGINE_LOG` compile-gate, không hiện trong bản release — giữ nguyên gate, chỉ dời vị trí trong `body` nếu cần — T14a (không xoá) |
| S47-S51 | Khối 6 (Nút giữ & cuộn) — T14d |
| S52 | Dưới `DisclosureGroup` "Nâng cao — ứng dụng khác" — T14b |
| S53 | Khối 9 (footer) — T14e |
| S54-S57 | Panel hướng đã chọn (Khối 4 bên phải) — T14c |
| S58-S63 | Trạng thái mũi tên trên `MouseDiagramView`/`GestureArmView` — không đổi logic, chỉ đổi khung chứa panel bên cạnh — T14c |
| S64 | `provenanceText` trong `GestureActionPicker` — giữ nguyên, hiện trong panel — T14c |
| S65-S68 | `keyCap` branches trong `GestureDetailPanel`/panel mới — giữ nguyên 4 nhánh — T14c |

### Xoá có lý do (không phải "rơi mất")

| # | Lý do xoá |
|---|---|
| F13/F14(header)/F18/F21/F23(bản ghi-nút-giữ-nhầm) | Trùng chức năng với F7 + nút "Ghi nút" Khối 6 — đây chính là Lỗi #6 cần sửa |
| `appPickerRow` (dead code, không phải F) | Đã chết, không bao giờ được gọi từ `body` — xoá khi xoá `MouseGesturesDetailView.swift` cũ, đừng "khôi phục" nó |
| Cột `profileSidebar` riêng (240pt) | Thay bằng dải chip — đúng Lỗi #8 |
| Dòng số nút 10-11px trên figure cũ (không phải F/S, là lỗi cỡ chữ) | `MouseDiagramView`/`GestureArmView` của bạn (xem 3.0) không đổi cỡ chữ các view con này — nhưng panel/inspector MỚI không được dùng cỡ dưới 11px (Lỗi #11) |

**Nếu khi dựng bạn thấy một F hoặc S nào ở trên không có chỗ rõ ràng trong `variant-b.html`
(không nằm trong bất kỳ khối nào), dừng lại, đọc lại `variant-b.html` phần đó, và nếu vẫn
không thấy — ghi vào worklog thay vì bỏ qua.**

## 3. Quyết định đã chốt (không mở lại)

Áp dụng các nghị quyết review của B đã có trong `CONTRACT.md`/`variant-b.html`:

1. **Tương phản**: không chữ nào dưới màu chữ phụ chuẩn (`.foregroundColor(.secondary)` là
   mức tối thiểu cho chữ phụ); không dùng `.opacity()` lên `Text` để làm mờ chữ (chỉ dùng
   opacity cho fill/stroke của hình, như `MouseDiagramView` đã làm với chip chưa khai báo);
   không cỡ chữ nào dưới 11pt bất cứ đâu trên trang mới.
2. **Trạng thái đang ghi (`dang-ghi`)**: khi `controller.recording == true`, làm mờ các khối
   KHÔNG liên quan recording bằng `.opacity(0.6).disabled(true)` (không phải `0.4` như
   wireframe CSS — 0.6 giữ được tương phản đọc được, và `.disabled()` tắt tương tác cho
   VoiceOver, không chỉ nhìn mờ). Khối còn sống trong lúc ghi: status line (Khối 2) và
   figure/panel (Khối 4) — đúng class `body[data-tt="dang-ghi"] …` trong `variant-b.html`
   liệt kê các khối 3,5,6,7,8,9 bị mờ.
3. **F25 (Reset toàn bộ profile)**: GIỮ, một nút "Về mặc định cho `<tên app>`" ở cuối Khối 4
   (dưới panel hoặc dưới dải chip), `.disabled(config.overrides[profile] == nil)` như code
   cũ — không xoá dù `variant-b.html` không vẽ nó rõ trong wireframe (CONTRACT.md không nói
   bỏ F25).
4. **F12 (Mở Phím tắt khi unbound-system-action)**: giữ nguyên — xuất hiện trong panel
   hướng-đã-chọn (Khối 4 bên phải) khi `row.isUnboundSystemAction`, với dòng cảnh báo cam
   S56.
5. **F6 (quick-click = Forward)**: engine thật sự đọc field này
   (`GestureEngine.swift` dòng ~335: `if duration < 0.200, configuration.
  holdButtonSingleClickEnabled { … }`) — **GIỮ** control này, hiện trong Khối 5 (Nút hông) y
   hệt code cũ, chỉ hiện khi `role == .holdTriggerWithAction` qua `GestureButtonList.action`
   case `.holdTrigger, .holdTriggerWithAction`.
6. **Một quy ước hợp âm**: mọi chord hiển thị dùng `GestureShortcut.label` (glyph như "⌘["),
   KHÔNG BAO GIỜ viết tay "Cmd+[" (wireframe HTML có hai chỗ viết "Cmd+[" trong tĩnh mạch
   demo — khi dựng SwiftUI thật, luôn lấy từ `.label`, không chép tay chuỗi đó).
7. **App chip đến từ dữ liệu thật**: dải chip app (Khối 3) build từ
   `GestureProfiles.all` + app đang chạy ở trước (`controller.lastExternalBundle`), lọc theo
   đã cài (`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` — logic này đã có
   trong `orderedProfiles`/`installedBundleIDs` của code cũ, giữ nguyên, chỉ đổi cách vẽ từ
   list sang chip). KHÔNG dùng danh sách tĩnh trong `variant-b.html`/`data.json` (chip
   "Claude (preset)" trong wireframe là demo cũ từ trước commit `f9b8d5d` sửa bundle id —
   đừng chép chuỗi `"com.anthropic.claude"` hay danh sách app tĩnh nào từ wireframe).
8. **Không thêm hint vị trí mới**: `MouseControlSlot.positionKey` hiện có ("hông trên"…) là
   đủ — không thêm câu mới kiểu "thường là…" ngoài cái `ButtonLabelStructure` đã sinh sẵn
   (hint có điều kiện cho nút hông, xem `hintKey(forButtonNumber:)` nếu có trong code — nếu
   hàm đó không tồn tại, bỏ qua yêu cầu này, không tự chế câu mới).
9. **F16 (click action nút hông) chỉ còn MỘT nơi**: hàng trong Khối 5 (Nút hông). Inspector-
   theo-nút (khi bấm chip trên hình) chỉ cho phép **liên kết tới hàng đó** (ví dụ nút
   "Xem trong danh sách Nút hông" cuộn tới hàng, hoặc đơn giản là hiển thị read-only + một
   dòng "Sửa ở khối Nút hông bên dưới") — không lặp lại menu Back/Forward/Unassigned y hệt ở
   cả hai chỗ. Quyết định cụ thể: **inspector-theo-nút hiện giá trị hiện tại (read-only)
   + nút "Dùng làm nút giữ"; menu đổi click-action chỉ có trong hàng Khối 5.**
10. **Nút cuộn** (nếu T15 chưa chạy trước T14): dùng đúng logic đã có ở
    `scrollButtonChoices` (computed property hiện tại trong
    `MouseGesturesDetailView.swift`) — danh sách là các nút đã khai báo trừ nút giữ, cộng
    giá trị đang lưu nếu nó không nằm trong danh sách đó. Nếu T15 đã chạy, `Picker` đã tồn
    tại — chỉ cần giữ nguyên khi dời vào Khối 6 của layout mới.

## 4. Các bước (mỗi bước = 1 commit, build + test xanh mới sang bước sau)

Thứ tự: rủi ro bố cục trước (để lỗi lớn lộ sớm), xoá code cũ sau cùng (để không có khoảng
trống nửa trang giữa chừng).

**Ba luật cho MỌI bước (Claude thêm khi review đặc tả, thắng mọi câu khác bên dưới):**
1. **Chuỗi mới vào store ngay trong bước dùng nó.** Tạo `scripts/add-mouse-redesign-l10n-entries.py` ở bước đầu tiên có
   chuỗi mới (mẫu: `scripts/add-system-hud-l10n-entries.py` — chỉ-thêm, dừng khi khoá đã có với nghĩa khác) và **mỗi bước
   thêm các dòng của nó vào cùng script**, chạy lại script, commit kèm `L10n.strings.json`. Không để chuỗi nào chờ tới T14f:
   một `L10n.t("…")` chưa có trong store làm `audit-l10n-literals.py` đỏ và UI tiếng Anh hiện tiếng Việt.
2. **Không placeholder.** Không `Text("TODO")`, không khối rỗng hiện ra cho người dùng. Khối nào chưa dựng thì **giữ khối cũ
   đang chạy** ở chỗ đó cho tới bước thay nó. Sau mỗi bước trang phải dùng được trọn vẹn.
3. **Nghiệm thu mỗi bước = `sh scripts/gate-all.sh` in `GATE: green`** (thay cho các lệnh build/test rời bên dưới), cộng
   phần riêng của bước. Dán nguyên văn kết quả vào worklog.

### T14a — Khung trang: header, status line, bố cục skeleton

**File sửa:** `XFinder/Views/Detail/MouseGesturesDetailView.swift` (toàn bộ `body` và các
hàm hỗ trợ bố cục: `readinessRow`, `permissionBanner`). KHÔNG xoá các hàm khác chưa dùng
tới trong bước này (ví dụ `mappingSection` cũ) — chỉ ngừng gọi chúng từ `body`, xoá ở bước
sau khi chắc không còn cần.

**Làm gì:**
1. `PageHeader` trailing: đổi `Toggle(...).labelsHidden()` cho F1 thành
   `.toggleStyle(.switch).controlSize(.small)` — sửa Lỗi #11.
2. Giữ `permissionBanner` (F2/F3/S2) y nguyên, gọi ngay dưới header khi `!trusted`.
3. Viết lại `readinessRow` thành MỘT `xf-note`-style block (dùng `SettingsSection` hoặc một
   `VStack` card đơn giản — không bắt buộc `SettingsSection` ở khối 2 vì đây không phải
   "card có tiêu đề", nhưng PHẢI dùng nền màu theo trạng thái như code cũ đã có
   (`tint.opacity(0.12)` + `Capsule`) — giữ 4 nhánh S3-S6 y hệt logic hiện tại, chỉ đổi text
   nếu cần khớp wireframe (không bắt buộc đổi, vì S3-S6 hiện tại đã đúng nghĩa).
4. Thêm nhánh hiển thị khi `controller.recording`: dùng đúng câu "Đang ghi — bấm nút trên
   chuột (Esc để hủy)." (khớp wireframe) thay cho màu cam cũ nếu bạn muốn tái dùng text đó —
   tra cứu chuỗi này trong `L10n.strings.json` trước khi thêm (có thể đã tồn tại từ chỗ
   khác, ví dụ `GestureButtonList`'s "Đang ghi — Esc để hủy" — nếu gần giống nhưng khác chữ,
   coi là CHUỖI MỚI, không tái dùng khoá cũ sai nghĩa).
5. Khung `xf-page`/blocks: tạo các `VStack`/`VStack` con cho 9 khối theo đúng số trong
   `CONTRACT.md` (1 header, 2 status, 3 app chooser, 4 gesture map, 5 side buttons, 6 hold &
   scroll, 7 tilt, 8 diagnostics, 9 footer) — khối 3-9 ở bước này **là các section cũ đang
   chạy, đặt vào đúng vị trí khối của B** (luật 2 ở trên: không placeholder), sẽ thay dần ở các bước sau. Giữ
   `.pageWidthSafe()` trên root `ScrollView` content như code cũ.

**Nghiệm thu T14a:**
```sh
sh scripts/build-and-check.sh
grep -c "MouseGesturesDetailView.swift" /tmp/xfinder-clean-build/build.log   # > 0
swift test --package-path /Users/wolong/github/XFinder/Tests
```
Cả hai phải không lỗi. Trang có thể còn thiếu nội dung — đó là OK ở bước này, miễn là build
chạy và F1/F2/F3/S2/S3-S6 hoạt động (đọc code, không cần mở app).

### T14b — Dải chip ứng dụng (Khối 3) thay cho sidebar 240pt

**File sửa:** cùng file trên, có thể thêm **một file mới**
`XFinder/Views/Components/MouseGestureAppStrip.swift` nếu nội dung quá dài cho một hàm
trong view chính (khuyến nghị — giữ view chính dễ đọc). Nếu tạo file mới, thêm đủ **4
dòng** vào `XFinder.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, dòng group,
dòng Sources phase) — chép đúng mẫu 4 dòng của một file `.swift` khác đã có trong cùng
group `Views/Components` (ví dụ tìm 4 dòng của `GestureArmView.swift` làm mẫu offset ID).

**Làm gì:**
1. Thay `profileSidebar` (cột dọc 240pt) bằng một `ScrollView(.horizontal)` chứa các chip:
   - Chip "Toàn cục" LUÔN Ở ĐẦU (không phụ thuộc vị trí cuộn) — giữ logic
     `orderedProfiles` hiện có (map `mine + rest + fallback`), nhưng khi build danh sách
     chip, tách `fallback` ra đặt đầu thay vì cuối (chỉ đổi thứ tự hiển thị, không đổi hàm
     `orderedProfiles` nếu nó được dùng chỗ khác — kiểm bằng `grep -rn orderedProfiles`
     trước khi sửa chữ ký hàm).
   - Mỗi chip: icon app thật (`NSWorkspace.shared.icon(forFile:)`, logic đã có trong
     `appIcon`), tên ngắn, viền accent khi đang chọn (`aria-selected`-tương-đương dùng
     `profile == item.id`).
   - Chip của app đang chạy ở trước (`controller.lastExternalBundle`) có một chấm nhỏ góc
     trên-phải nếu nó khác app đang được xem (`profile != frontmostBundle`) — tương đương
     `b-dot` trong wireframe.
   - Cuối dải: nút "＋" mở `DisclosureGroup`/popover chứa ô nhập bundle ID + nút "Chọn"
     (F24, logic `customBundleRow` đã có — chỉ đổi vị trí kích hoạt, không đổi logic ghi
     `profile = id.trimmed`).
   - Khi trang xuất hiện hoặc đổi `profile`, cuộn chip đang chọn vào khung nhìn
     (`ScrollViewReader` + `scrollTo(profile, anchor: .center)` trong `.onAppear`/
     `.onChange(of: profile)`) — đây là điều wireframe JS làm bằng `scrollIntoView`; bản
     SwiftUI dùng `ScrollViewReader`.
2. Dưới dải chip: dòng phụ y hệt `frontmostHint` cũ (S8-S12 + F5) nhưng bỏ nút "Xem" riêng
   NẾU app đang dùng đã có mặt trong dải chip (tức đã là một chip bấm được) — chỉ giữ nút
   "Xem" khi `front.isEmpty == false && !orderedProfiles chứa front` (app chưa cài, không có
   chip cho nó) — đây là cách sửa Lỗi #15 (trùng chức năng) mà không xoá hẳn F5.
3. F25 (Reset toàn bộ profile): đặt ngay dưới dải chip/dòng phụ, dùng logic
   `.disabled(config.overrides[profile] == nil)` y hệt cũ.

**Nghiệm thu T14b:** như T14a, cộng: đọc diff — không còn `.frame(width: 240…)` áp cho một
cột app riêng; `orderedProfiles`/`installedBundleIDs`/`appIcon` vẫn được gọi (grep xác nhận
không xoá nhầm).

### T14c — Khối 4: sơ đồ chuột + inspector bên phải (lõi của phương án B)

**File sửa:** `MouseGesturesDetailView.swift`; có thể cần sửa chữ ký một vài tham số truyền
vào `MouseDiagramView`/`TiltArmsRow` NẾU bạn đổi cách inspector nhận biết lựa chọn — nhưng
**không đổi bất kỳ `struct`/`enum` nào trong `MouseDiagramView.swift`, `GestureArmView.swift`
bản thân chúng** (chỉ đổi cách `MouseGesturesDetailView` gọi chúng và đặt panel bên cạnh).
`GestureDetailPanel.swift` và `GestureActionPicker.swift` có thể **sửa phần trình bày**
(không đổi tham số đầu vào/`onPick`/`onRecord`/`onReset` — chữ ký không đổi) nếu cần để
khớp khung "panel bên phải không bao giờ trống" — xem bước 3 dưới.

**Làm gì:**
1. Bố cục hai cột trong MỘT card (`xf-card`-tương-đương: dùng `RoundedRectangle(cornerRadius:
   XFinderTokens.Radius.tile).fill(...)` hoặc tái dùng style `GestureDetailPanel` đã có
   sẵn — chọn cách nào giữ code ngắn hơn): cột trái ~300pt chứa `MouseDiagramView` +
   `TiltArmsRow` (khi `tiltArmsLive`), cột phải chứa inspector.
2. **Hai lựa chọn tồn tại song song**: `pickedDirection` (hướng) và `pickedButton` (nút).
   Khi người dùng bấm một mũi tên: set `pickedDirection`, **không đổi `pickedButton`** (để
   không nhảy qua lại) nhưng panel phải ƯU TIÊN hiển thị hướng khi cả hai khác nil cùng lúc
   — vì bấm mũi tên và bấm chip nút là hai thao tác loại trừ nhau trên hình, logic hiện có
   trong `MouseDiagramSelection.afterClick`/`afterButtonClick` **đã xử lý việc clear chọn
   kia** (đọc hai hàm đó trước khi viết panel — rất có thể chúng đã tự set cái còn lại về
   nil). Nếu đúng vậy, panel chỉ cần: `if let d = pickedDirection { hướng-view } else if let
   b = pickedButton { nút-view } else { tóm-tắt-4-hướng }`.
3. **Panel không bao giờ trống** (sửa phần "cần click" của Lỗi #7, và thực hiện đúng
   `variant-b.html`'s "default: 4-direction summary"): nhánh `else` ở trên hiện 4 dòng tóm
   tắt (lên/xuống/trái/phải → tên hành động + chord), mỗi dòng gọi `resolved(direction)` +
   `resolvedName(direction)` đã có sẵn trong view hiện tại — không cần hàm mới. Giữ 2 câu
   giải thích ngắn của S28 (emptySelectionHint cũ) làm chú thích nhỏ dưới bảng tóm tắt, dùng
   `xf-footer`-style (caption, secondary).
4. **Nhánh hướng đã chọn**: dùng lại `GestureDetailPanel` với các tham số y hệt code cũ
   (`direction`, `row: resolved(direction)`, `actionName: resolvedName(direction)`,
   `trigger: config.trigger`, `isRecording`, `appName: profileDisplayName()`, `hasAppPreset`,
   `systemBindings: controller.systemBindings`, `onPick`, `onRecord`, `onReset`) — chỉ đổi
   `.frame`/`.padding` bao quanh nó để vừa cột phải ~300pt, KHÔNG sửa bên trong
   `GestureDetailPanel.swift` trừ khi cỡ chữ cần chỉnh (xem §3.1, không chữ nào dưới 11pt —
   `GestureDetailPanel` hiện tại đã dùng 10-15px ở vài chỗ, ví dụ `size: 10` cho caption —
   NẾU bạn phải nâng những cỡ đó lên 11, đó là một sửa hợp lệ trong file này, nhưng ghi rõ
   trong commit message bạn đã đổi cỡ chữ ở `GestureDetailPanel.swift`).
5. **Nhánh nút đã chọn** (F8/F15 — ĐÂY LÀ NƠI DUY NHẤT đổi nút giữ): viết view mới (có thể
   là một `private var buttonInspector: some View` ngay trong `MouseGesturesDetailView`,
   hoặc file mới `GestureButtonInspector.swift` nếu dài — nếu file mới, nhớ 4 dòng pbxproj):
   - Tiêu đề: `Nút N` (dùng `L10n.t(ButtonKey.index(button))`), phụ đề là hành động click
     hiện tại (đọc `role = buttonRole(button)`, hiện `role.labelKey` hoặc nếu
     `role.isAssignable` thì tên hành động click đang gán — logic này tương đương
     `DeviceCapabilityModel.passthroughNoteKey`/`role` đã có, không bịa thêm).
   - Nếu `role == .holdTrigger || role == .holdTriggerWithAction`: hiện "Đây là nút giữ
     hiện tại" (không có nút "Dùng làm nút giữ" vì nó đã LÀ nút giữ).
   - Nếu không: hiện dòng "Nút giữ cử chỉ hiện tại là Nút `<trigger>`" + nút "Dùng làm nút
     giữ" gọi `onSetTrigger(button)` tức `controller.update { $0.trigger = .mouseButton(button)
     }` — **y hệt logic `GestureButtonList`'s `onSetTrigger` đã có**, chỉ chuyển nơi gọi.
     `.disabled(!role.isDeclared)` giữ nguyên quy tắc cũ (không đặt nút chưa khai báo làm
     nút giữ).
   - Dòng click-action: CHỈ hiện read-only (ví dụ "Bấm nhanh: Lùi (⌘[)") — việc ĐỔI click
     action vẫn ở Khối 5 (quyết định §3.9). Không vẽ menu Back/Forward/Unassigned trong
     inspector này.
6. Nối `MouseDiagramView`'s `onRecordTrigger`: giữ callback hiện tại
   (`triggerRecording()` không tham số, tức ghi nút giữ) khi bấm hold-badge — **nhưng đọc
   kỹ quyết định §3's "Hợp nhất"**: bấm hold-badge VẪN ghi nút giữ trực tiếp (giữ F7 nguyên
   nghĩa, không đổi thành "chỉ mở inspector") — đây khác với bấm CHIP NÚT (F8), chip nút mở
   inspector chứ không tự ghi. Nếu thấy mâu thuẫn với dòng "Hợp nhất" ở §2, ưu tiên: **F7
   (bấm hold-badge) = ghi ngay** (giữ hành vi hiện tại của `holdBadge` trong
   `MouseDiagramView.swift`, không sửa file đó); **F8 (bấm chip nút)** = mở inspector, không
   tự ghi gì.

**Nghiệm thu T14c:** build + test như trên, cộng đọc diff xác nhận `GestureActionPicker`,
`GestureActionCatalog.choices()`, `GestureMap.row`, `resolved(_:)`, `resolvedName(_:)` vẫn
được gọi nguyên vẹn — không tạo bản sao logic hành động nào trong file mới.

### T14d — Khối 5 (Nút hông), Khối 6 (Nút giữ & cuộn), Khối 7 (Nghiêng con lăn)

**File sửa:** `MouseGesturesDetailView.swift`. `GestureButtonList.swift` có thể bị **xoá
hoàn toàn khỏi `body`** (không gọi `buttonListSection` nữa) nhưng giữ file trên đĩa tới
Bước T14e (xoá file ở bước đó, sau khi chắc không còn tham chiếu) — tránh half-page nếu một
bước bị dừng giữa chừng.

**Làm gì:**
1. **Khối 5 (Nút hông)** — *(sửa 2026-10-15 sau khi một lượt agent kẹt ở đây: bản cũ bảo thêm "Đặt làm nút giữ" vào
   từng hàng, mâu thuẫn với wireframe B / CONTRACT; câu dưới đây THẮNG mọi câu khác về nút giữ)*.
   Với mỗi nút trong `drawnButtons` có `role.isAssignable` mà **không phải** nút giữ hiện tại: một hàng gồm
   tên `Nút N` (`L10n.t(compactButton:)`) + vị trí (`positionKey`, nếu có) làm dòng phụ, tag vai trò, và `Menu` đổi
   click action (Không làm gì / Lùi / Tiến — chép đúng nhánh `.isAssignable` của `GestureButtonList.action`, giữ
   `controller` call y nguyên). **Không có nút "Đặt làm nút giữ" hay "Ghi" nào trong khối này.** Nút giữ đổi ở đúng
   hai chỗ đã có: bảng bên phải (T14c, "Dùng làm nút giữ" cho nút đã khai báo) và "Ghi nút" ở Khối 6 (bấm thật một
   nút bất kỳ — đường đi của quyết định 7 cho nút máy chưa khai báo); hình chuột (F7) gọi cùng `triggerRecording()`.
   Nút chưa khai báo (`!role.isDeclared`): hàng mờ (màu `.secondary`, không opacity trên chữ) ghi "Chưa khai báo"
   và một dòng phụ: "Bấm “Ghi nút” ở mục Nút giữ & cuộn rồi bấm nút này để XFinder đo." — không thêm nút riêng.
   F17 (Bấm nhanh = Tiến) hiện trong hàng của nút đang là `holdTriggerWithAction` nếu nút đó không bị loại ở trên;
   nếu nút giữ bị loại khỏi khối, F17 nằm ở Khối 6 cạnh "Nút giữ". Cuối khối: `hardwareExclusionNote` (S39) y nguyên.
   - Nếu KHÔNG có hàng nào (ví dụ trạng thái `khong-chuot`): một hàng "Chưa đọc được nút nào — Cắm chuột có nút hông
     để xem và gán ở đây." (khớp `variant-b.html` nhánh `khong-chuot`).
   - **Chỉ cần đọc** (đừng đọc lại cả file 1 450 dòng): `buttonListSection`, `switchesSection`, `tiltRow`, `legend`,
     `scrollButtonChoices`, `buttonRole`, `roleContext`, `drawnButtons` trong `MouseGesturesDetailView.swift`;
     `GestureButtonList.swift` (hàm hàng và `action`); `hardwareExclusionNote` ở chỗ nó được khai báo. Đọc một lần rồi
     viết — nếu thấy mâu thuẫn mới, ghi vào worklog và dừng, đừng đọc vòng.
2. **Khối 6 (Nút giữ & cuộn)**: 3 hàng —
   - Hàng 1: "Nút giữ" + giá trị hiện tại (`L10n.t(compactButton: config.trigger.key)`) +
     nút "Ghi nút" (`triggerRecording()`, **chỗ record nút giữ còn lại sau khi hợp nhất** —
     xem §3's "Hợp nhất"). Disable khi `controller.recording`.
   - Hàng 2: switch F22 (giữ nút cuộn rồi kéo để cuộn).
   - Hàng 3: "Nút cuộn" + Picker (dùng đúng `scrollButtonChoices` đã có trong file hiện tại
     — nếu T15 đã chạy, Picker đã tồn tại, chỉ dời vào khối này; nếu chưa, triển khai y hệt
     logic T15 mô tả: liệt kê `drawnButtons` lọc theo đã khai báo trừ nút giữ, cộng giá trị
     đang lưu nếu thiếu, gọi `controller.update { $0.scrollButton = n }`).
3. **Khối 7 (Nghiêng con lăn)**: giữ nguyên `tiltRow` (F20) — chỉ đổi vị trí vào khối riêng,
   không đổi logic `TiltArmsVisibility.fields(forReveal:)`.

**Nghiệm thu T14d:** build + test; đọc diff xác nhận KHÔNG còn `triggerRecording()` nào
được gọi ở nơi khác ngoài Khối 6 và hold-badge (F7) — grep
`grep -n "triggerRecording(" XFinder/Views/Detail/MouseGesturesDetailView.swift
XFinder/Views/Components/GestureButtonList.swift` (nếu `GestureButtonList.swift` vẫn còn
trong `body` lúc này, kết quả sẽ còn 2 chỗ do file cũ — OK, file đó bị xoá ở T14e).

### T14e — Khối 8 (Chẩn đoán), Khối 9 (footer), xoá code chết

**File sửa:** `MouseGesturesDetailView.swift`; XOÁ `XFinder/Views/Components/
GestureButtonList.swift` và `XFinder/Views/Components/GestureActivityPanel.swift` **CHỈ
NẾU** không còn bất kỳ `body`/file nào gọi chúng (grep xác nhận) — nếu
`activitySection`/`GestureActivityPanel` vẫn cần cho `DEBUG_SHOW_ENGINE_LOG` build (biến
`false` nhưng code phải compile), **ĐỪNG xoá `GestureActivityPanel.swift`** — chỉ xoá
`GestureButtonList.swift` nếu nó thật sự không còn được gọi. Xoá một file cần dọn **đủ 4
dòng** tương ứng trong `project.pbxproj` (ngược lại với thêm) — tìm và xoá
`PBXBuildFile`/`PBXFileReference`/dòng group/dòng Sources có tên file đó.

**Làm gì:**
1. **Khối 8 (Chẩn đoán chuột)**: một `DisclosureGroup` (đóng mặc định — khác wireframe demo
   mở sẵn, vì wireframe chỉ mở để review) chứa: hàng "Thiết bị" (S13-S23, dùng `deviceRow`
   logic cũ), hàng "Nút chuột XFinder thấy" (S29-S33, dùng `header`/`declarationSummary`
   logic từ `GestureButtonList` TRƯỚC KHI xoá file đó — chép logic cần thiết sang view mới
   hoặc giữ các hàm đó là `static`/free function nếu tiện), `DisclosureGroup` con "Mô tả
   HID thô" (F19/S24-S25, dùng `hidDumpRow` logic cũ — lazy load, không đổi), hàng "Nút bạn
   vừa bấm" (S26, dùng `observedButtonRow` logic cũ).
2. **Khối 9 (footer)**: F26 + S53, dùng `footerNote` logic cũ, không đổi.
3. Xoá `profileSidebar`, `appPickerRow` (dead code), và bất kỳ hàm private nào trong
   `MouseGesturesDetailView.swift` không còn được gọi từ `body` — `grep -n "private var\|
   private func" XFinder/Views/Detail/MouseGesturesDetailView.swift` rồi kiểm từng tên có
   xuất hiện trong `body`/trong một hàm khác đang được gọi hay không.

**Nghiệm thu T14e:**
```sh
sh scripts/build-and-check.sh
swift test --package-path /Users/wolong/github/XFinder/Tests
python3 scripts/audit-ui-tokens.py       # TOTAL 0
```
Đọc diff: không còn `private var`/`private func` chết; nếu xoá file, `plutil -lint
XFinder.xcodeproj/project.pbxproj` sạch.

### T14f — Soát chuỗi lần cuối, rồi 6 cổng L10n + 3 harness mutation

(Theo luật 1 ở đầu mục 4, chuỗi mới đã vào store ở từng bước. Bước này chỉ SOÁT: chuỗi nào lọt thì thêm vào cùng script.)

**File mới:** `scripts/add-mouse-redesign-l10n-entries.py` (mẫu:
`scripts/add-analytics-l10n-entries.py`, đã đọc ở trên — copy cấu trúc: `ENTRIES` dict
`{câu tiếng Việt: (câu tiếng Anh, scope)}`, kiểm xung đột trước khi ghi, KHÔNG rewrite khoá
đã có).

**Làm gì:**
1. Soát toàn bộ diff từ T14a–T14e, liệt kê MỌI chuỗi tiếng Việt mới (câu không có trong
   `L10n.strings.json` trước đó) — kể cả câu bạn nghĩ là "chép lại từ chỗ khác" (nếu chữ
   khác một dấu phẩy, nó là khoá MỚI). Nếu một bước chỉ DI CHUYỂN một `Text(L10n.t("..."))`
   đã tồn tại (không đổi nguyên văn), KHÔNG cần thêm gì cho câu đó.
2. Thêm toàn bộ vào `ENTRIES` của script mới, chạy nó, commit cả script lẫn
   `XFinder/Resources/L10n.strings.json`.
3. Chạy đủ 6 cổng L10n, lần lượt (không song song):
```sh
python3 scripts/check-l10n-coverage.py
python3 scripts/check-l10n-duplicates.py
python3 scripts/audit-l10n-literals.py
python3 scripts/audit-l10n-interpolations.py
python3 scripts/check-sidebar-groups-l10n.py
python3 scripts/verify-l10n-runtime.py
```
Mỗi lệnh phải in `TOTAL 0`. `verify-l10n-runtime.py` đọc bundle ĐÃ CÀI trong
`/Applications/XFinder.app` — nếu bản cài hiện tại cũ hơn commit này, lệnh đó có thể báo
sai (đo bundle cũ). Nếu vậy, ghi rõ trong worklog "verify-l10n-runtime.py đo bản cài cũ,
chưa đo được bản mới" — **không tự ý cài app** (nằm ngoài vùng Agent Tasks M/L thường làm,
và `install-mouse-rebuild.sh` nằm trong vùng cấm của `AGENT_TASKS.md` mục 2 — chỉ Claude
chạy).
4. Chạy TUẦN TỰ, không song song, mỗi cái chạy xong rồi mới chạy cái tiếp. Trước khi bắt đầu, `git status --short` không
được có `M` ở các file Core mà harness mutate (danh sách ngay dưới) — file T14 bạn đang sửa trong `Views/` thì được phép:
```sh
sh scripts/mutation-check-gesture-labels.sh
sh scripts/mutation-check-gesture-ui.sh
sh scripts/mutation-check-gesture-buttons.sh
```
Cả ba phải báo mọi mutation RED, và sau mỗi lần chạy, `git status --short` phải GIỐNG HỆT
trước khi chạy (các harness tự phục hồi file Core chúng mutate — `GestureModel.swift`,
`GestureLabelStructure.swift`, `DeviceCapabilityModel.swift`, `DeviceCapabilityTypes.swift`,
`GestureUIDisplay.swift` — những file này KHÔNG nằm trong phạm vi sửa của T14, nên nếu
`git status` cho thấy chúng bị đổi SAU khi ba harness chạy xong, đó là mutant còn sót: ghi
vào worklog, `git diff <file>` để chép phần khác, rồi DỪNG — không tự `git checkout`, đúng
quy tắc `AGENT_TASKS.md` §3 điều kiện dừng).

**Nghiệm thu T14f:** 6 lệnh L10n in `TOTAL 0`; 3 harness in đủ số dòng RED mong đợi (xem
log của mỗi script để biết số chính xác — labels 5, ui tuỳ phiên bản script hiện tại,
buttons tuỳ phiên bản — đọc output "RESULT: n/n" hoặc "X/X RED" mà script tự in, không đoán
số).

## 5. Danh sách việc-cạnh (edge case) phải trả lời trong worklog, từng bước

Với MỖI bước T14a–T14f, trả lời (không cần dài, 1 câu/ý là đủ):

1. **Thiếu quyền Trợ năng**: `trusted == false` — status line có hiện đúng S2/S6 không?
   Panel bên phải có còn dùng được không (vẫn hiện bảng tóm tắt, chỉ là cử chỉ không chạy)?
2. **Không có chuột / chưa khai báo nút nào**: `declaredEventButtons == nil` hoặc rỗng —
   Khối 5 có hiện đúng thông báo honest (không bịa số nút) không? Dải chip app vẫn dùng
   được chứ (không phụ thuộc chuột)?
3. **Công tắc chính tắt** (`config.enabled == false`): status line hiện đúng nhánh, nhưng
   mapping (Khối 3-7) có VẪN xem/sửa được không (đúng S3 "sơ đồ bên dưới đã có sẵn phím
   tắt")?
4. **Một giá trị ở biên**: `drawnButtons` rỗng (mảng 0 phần tử) — Khối 5 không crash, hiện
   thông báo "Chưa đọc được nút nào". `scrollButtonChoices` rỗng (mọi nút đều là nút giữ —
   không thể, nhưng nếu chỉ có 1 nút khai báo và nó là nút giữ) — Picker không được render
   trống không nhãn; `scrollButtonChoices` hiện tại LUÔN thêm `config.scrollButton` nếu
   thiếu nên không bao giờ thực sự rỗng — xác nhận lại bằng cách đọc hàm, không giả định.
5. **Ngữ cảnh đổi giữa chừng**: đang ghi (`controller.recording == true`) thì người dùng đổi
   app chip (`profile` đổi) — `onChange(of: profile)` hiện tại gọi
   `recordingDirection = nil` nhưng KHÔNG hủy `controller.recording`/`recordingTrigger`/
   `recordingButton` — giữ đúng hành vi cũ (đây là hành vi đã có, không phải lỗi mới; chỉ
   xác nhận bước của bạn không vô tình đổi nó).
6. **Giá trị cache cũ**: `hidDump` chỉ load khi mở `DisclosureGroup` lần đầu
   (`hidDumpExpanded`) — xác nhận bước T14e giữ đúng `.onChange(of: hidDumpExpanded)` cũ,
   không load lại mỗi lần render.
7. **Control hứa điều không làm được**: sau khi hợp nhất "Ghi nút giữ" về 2 chỗ (hold-badge
   + Khối 6), kiểm KHÔNG còn control nào tên "Ghi nút" nằm cạnh "Nút cuộn" mà thực ra ghi
   nút giữ (đây chính là Lỗi #1 — phải hết hẳn).

## 6. "Chưa kiểm live" — ghi đúng những mục này, đừng ghi là đã xong

- Cảm giác thao tác thật: bấm hold-badge, kéo dải chip bằng trackpad, mở `DisclosureGroup`
  "Chẩn đoán chuột" trên app đang chạy.
- VoiceOver đọc đúng thứ tự Khối 1→9 và đọc đúng trạng thái đang ghi (mờ + "không tương
  tác được") — chỉ code `.disabled(true)` là cơ chế, không ai nghe thử.
- Dải chip có thật sự cuộn chip đang chọn vào khung nhìn khi mở trang lần đầu (ScrollViewReader
  hoạt động đúng thời điểm `.onAppear`, không bị race với layout) — cần mắt người.
- AX dump / ảnh chụp cửa sổ thật so với `variant-b.html` ở `win=s` (1181×611) — Claude làm
  khi review, agent không cần tự chụp.
- Ba trạng thái permission/no-mouse/recording trên MÁY THẬT (agent chỉ xác nhận code nhánh
  đúng, không ép được trạng thái thật mà không có chuột/không rút quyền).

**Điều kiện dừng ngay** (giống `AGENT_TASKS.md` §3): sửa 2 lần mà cùng lỗi build/test vẫn
còn → dừng, ghi 2 cách đã thử + lỗi nguyên văn vào worklog, không thử lần 3. Đặc tả không
khớp code thật (hàm đã đổi tên, dòng đã khác) → dừng, ghi rõ chỗ lệch.
