# Bảng việc cho agent khác — khi Claude hết quota

Tệp này do Claude giữ. Agent khác (OpenCode, Zed, Antigravity, Cursor…) **chỉ làm việc có trong mục 6**, đúng quy trình
mục 3, rồi dừng. Khi có quota lại, Claude review theo mục 4.

## 0. Cách giao việc (cho bạn)

Mở agent ngay trong thư mục repo (`cd ~/github/XFinder && opencode`, hoặc File ▸ Open Folder trong Zed / Antigravity), dán:

```
Đọc docs/AGENT_QUICKSTART.md, rồi docs/AGENT_TASKS.md. Làm ĐÚNG MỘT việc: việc đầu tiên trong mục 6 có trạng thái TODO
(hoặc việc <ID> nếu tôi ghi ở đây: ___). Theo đúng các bước của mục 3, không làm thêm gì ngoài các bước của việc đó.
Gặp bất kỳ điều kiện dừng nào ở mục 3 thì dừng và ghi vào docs/AGENT_WORKLOG.md, không tự xoay xở.
```

Một lần một việc, một nhánh một việc. Làm xong một việc muốn làm tiếp thì dán lại câu trên (agent sẽ lấy việc TODO kế).

## 1. Thế nào là việc NHỎ (cỡ S) — trả lời bằng con số, không bằng cảm giác

Một việc là **S** khi **tất cả** đều đúng:

| # | Câu hỏi | S khi |
|:--|:--|:--|
| 1 | Bao nhiêu file nguồn đổi? | ≤ 3 file (+ 1 file test, + chuỗi dịch thêm bằng script chỉ-thêm) |
| 2 | Bao nhiêu dòng đổi? | ≤ ~150 dòng (`git diff --stat`) |
| 3 | Có tạo file nguồn mới không? | **Không** với file trong `XFinder/` (cần 4 dòng tay trong `project.pbxproj`). Một file test mới trong `Tests/XFinderLogicTests/` thì được — gói test tự nhận, miễn là file app nó test đã có symlink sẵn |
| 4 | Kiểm được mà không mở app không? | **Có** — bằng `build-and-check`, `swift test`, các cổng L10n/UI, hoặc đọc diff |
| 5 | Có đụng vùng cấm (mục 2) không? | **Không** |
| 6 | Có cần bạn quyết định sản phẩm không? | **Không** (sửa lỗi, đồng bộ, cảnh báo deprecated, test còn thiếu, nhãn VoiceOver, câu tài liệu sai) |

Mẹo một câu: **nếu phải mở app, cấp quyền, hay nhìn màn hình mới biết đúng chưa → không phải S, để Claude.**

**M** (để Claude): nhiều file, file mới, một tính năng mới nhỏ, đổi ý nghĩa một cài đặt, cần đo trên máy.
**L** (chỉ Claude, có thể cần bạn): kiến trúc, quyền hệ thống, dữ liệu người dùng, phát hành.

## 2. Vùng cấm với agent khác

Không sửa, kể cả khi việc có vẻ cần:

- `XFinder.xcodeproj/project.pbxproj`, `XFinder/Info.plist`, entitlements
- `scripts/install-mouse-rebuild.sh`, `scripts/make-release.sh`
- `Core/Agents/AgentHookInstaller.swift`, `ClaudeStatusLine.swift`, mọi thứ ghi vào `~/.claude` hoặc `~/.codex`
- `BoardLock*` (mã hoá), `DatabaseService.swift` (dữ liệu clipboard)
- `Core/Notch/NotchSurfaceMachine.swift` (luật đóng/mở notch)
- Các controller có event tap: `QuitProtectionController`, `ClipboardShelfController`, `SnapZoneController`,
  `CommandTabController`, `FinderKeyboardController`, `GestureEngine`, `VoiceHotkeyManager`
- Thứ di chuyển/xoá tệp của người dùng: `ArchiveRunner`, `JunkCleanup`, `Uninstall*`
- `Core/Diagnostics/*` (quyền riêng tư), `MenuBarHider*`
- Mọi thay đổi làm một khoá `UserDefaults` đổi nghĩa hay đổi mặc định

## 3. Quy trình cho agent (làm theo thứ tự, không bỏ bước)

1. `git status` — chỉ được có các file chưa track sẵn của chủ dự án (`assets_info.json`, `strings/`, `.agents/`…). Có file
   đã sửa mà không phải của mình → **dừng**.
2. `git switch main` rồi `git switch -c agent/<công-cụ>-<ID>` (ví dụ `agent/opencode-T03`).
3. Trong tệp này, đổi trạng thái việc thành `ĐANG LÀM (<công cụ>, <giờ>)`.
4. Làm **đúng** các bước của việc đó. Không sửa thêm file nào khác, không "tiện tay" dọn dẹp.
5. Chạy **mọi** lệnh nghiệm thu của việc, cộng: `sh scripts/build-and-check.sh` và
   `swift test --package-path /Users/wolong/github/XFinder/Tests`.
6. Commit trên nhánh, chỉ stage đúng file mình sửa: `git add <file1> <file2>`; message mở đầu bằng ID
   (`T03: …`), ghi kết quả từng lệnh nghiệm thu.
7. Đổi trạng thái thành `CHỜ CLAUDE REVIEW (nhánh agent/…)`; ghi một mục vào `docs/AGENT_WORKLOG.md` (đã làm gì, kết
   quả từng lệnh, điều gì chưa kiểm được). Commit hai thay đổi này cùng nhánh.
8. **Dừng.** Không push, không merge vào `main`, không làm việc kế trên cùng nhánh.

**Điều kiện dừng ngay** (ghi vào worklog rồi dừng):

- Build hoặc test đỏ mà không sửa được trong phạm vi các file của việc.
- Việc cần đụng vùng cấm, cần file mới, hoặc cần quá 3 file.
- Mô tả việc không khớp với code thật (dòng đã đổi, hàm không còn): code đã thay đổi từ khi Claude viết việc.
- Lệnh nghiệm thu cho kết quả khác kỳ vọng.

## 4. Quy trình của Claude khi có quota lại

1. Đọc `docs/AGENT_WORKLOG.md` (mục mới nhất) và `git branch --list 'agent/*'`.
2. Với mỗi nhánh: `git log main..<nhánh>`, `git diff main...<nhánh>`. Kiểm đúng phạm vi (file nào, bao nhiêu dòng),
   vùng cấm, và từng bước có đúng không.
3. Tự chạy lại nghiệm thu + harness mutation liên quan.
4. Đúng → merge vào `main` (giữ commit của agent, hoặc squash thành một commit theo chủ đề). Sai → sửa hoặc bỏ, và ghi
   lý do vào worklog.
5. Đổi trạng thái trong mục 6 thành `XONG (<commit>)` hoặc `BỎ (<lý do>)`; push; xoá nhánh đã gộp.

## 5. Trạng thái hiện tại (Claude cập nhật cuối mỗi phiên)

Cập nhật 2026-10-15.

- `main` = commit mới nhất trên GitHub; không nhánh `agent/*` nào đang mở; không việc nào ĐANG LÀM.
- Bản cài trên máy là bản Debug khớp `main` (đã kiểm hash).
- **Bạn còn nợ tay** (danh sách đầy đủ ở `docs/PENDING_TESTS_AND_DECISIONS.md`): T-ANALYTICS-5 (thấy tín hiệu trên dashboard
  TelemetryDeck), T-ANALYTICS-6 (bấm một nút trên hộp thông báo), T-LAYOUT-1, T-SLEEP-1, T-LIMIT-1.
- **Câu hỏi đang chờ bạn**: Q-RELEASE-14 (đăng 1.4.0), Q-OC (chọn mã OneNotch muốn làm), Q-DIAG-5, và các Q khác trong
  file trên. Agent khác **không** trả lời thay bạn những câu này.

## 6. Hàng đợi việc cỡ S

Mỗi việc dưới đây đã được Claude và một agent soát lỗi độc lập đọc lại trên code thật ngày 2026-10-15. Số dòng có thể lệch
vài dòng khi code đổi: **tìm theo đoạn code được trích**, không theo số dòng. Đoạn trích không còn ⇒ điều kiện dừng.

Không việc nào cần mở app. Việc nào thêm nhãn VoiceOver thì phần "VoiceOver đọc đúng" là **chưa kiểm được**: ghi rõ như vậy
trong worklog, đừng viết là đã xong.

---

### T01 · README ghi sai số test — TODO

- **Cỡ:** S · 1 file (`README.md`), 1 dòng
- **Vì sao:** README dòng ~213 ghi `| Test logic (399 test) | ✅ |`; thật là ~1196.
- **Các bước:**
  1. Đếm: `grep -c "func test" Tests/XFinderLogicTests/*.swift | awk -F: '{s+=$2} END {print s}'` (ngày viết: 1196).
  2. Đổi đúng ô đó thành `| Test logic (~<số vừa đếm> test) | ✅ |`. Không sửa dòng nào khác của bảng.
- **Nghiệm thu:** `grep -rn '(399 test)' README.md docs/*.md` ra rỗng · `git diff --stat` = 1 file, 1 dòng.

---

### T02 · `onChange` kiểu cũ ở Tổng quan và Hệ thống — TODO

- **Cỡ:** S · 2 file, 3 dòng
- **Vì sao:** macOS 14 bỏ kiểu closure một tham số của `.onChange(of:)`; ba chỗ này còn dùng, mỗi lần build sinh cảnh báo.
- **Các bước** (chỉ đổi chữ ký closure, thân giữ nguyên):
  1. `XFinder/Views/Detail/DashboardDetailView.swift`: `.onChange(of: launchAtLogin) { LoginItemController.apply($0) }`
     → `.onChange(of: launchAtLogin) { _, newValue in LoginItemController.apply(newValue) }`
  2. Cùng file: `.onChange(of: showDockIcon) { DockController.apply($0) }`
     → `.onChange(of: showDockIcon) { _, newValue in DockController.apply(newValue) }`
  3. `XFinder/Views/Detail/SystemDetailView.swift`: `.onChange(of: updateInterval) { _ in`
     → `.onChange(of: updateInterval) { _, _ in`
- **Nghiệm thu:**
  - Lệnh dưới, trước khi sửa ra 6 dòng, sau khi sửa còn đúng 3 dòng (DockPreviewController ×2, PreviewOverlayWindow ×1):
    `grep -rn "onChange(of:" XFinder --include='*.swift' | grep -E '\{ *(_|\$0|[a-zA-Z_][a-zA-Z0-9_]*) +in\b|\$0'`
  - `build-and-check` thành công; `git diff --stat` = 2 file, 3 dòng đổi.

---

### T03 · `onChange` kiểu cũ ở xem trước Dock và cửa sổ ⌘-Tab — TODO

- **Cỡ:** S · 2 file, 3 dòng
- **Các bước** (chỉ đổi chữ ký closure, thân giữ nguyên; không đụng phần event monitor của file):
  1. `XFinder/Core/DockPreviewController.swift`: `.onChange(of: pid) { newPID in` → `.onChange(of: pid) { _, newPID in`
  2. Cùng file: `.onChange(of: store.activeBrowserTabs) { _ in` → `.onChange(of: store.activeBrowserTabs) { _, _ in`
  3. `XFinder/Core/WindowPreview/PreviewOverlayWindow.swift`: `.onChange(of: store.selectedIndex) { newIndex in`
     → `.onChange(of: store.selectedIndex) { _, newIndex in`. **Không** đụng chỗ `.onChange(of: store.selectedIndex)` thứ
     hai trong file (đã đúng kiểu).
- **Nghiệm thu:** lệnh grep của T02 ra 0 dòng nếu T02 đã gộp, hoặc chỉ còn 3 dòng của T02 nếu chưa · `build-and-check` thành
  công · `git diff --stat` = 2 file, 3 dòng đổi.

---

### T04 · `allowedFileTypes` (đã bỏ) ở Nén và Công cụ PDF — TODO

- **Cỡ:** S · 2 file, ~4 dòng
- **Các bước:**
  1. Thêm `import UniformTypeIdentifiers` dưới các dòng `import` sẵn có của `XFinder/Views/Detail/CompressDetailView.swift`
     và `XFinder/Views/Detail/PdfToolsDetailView.swift`.
  2. Compress: `panel.allowedFileTypes = ["zip", "gz", "bz2", "tar"]` → đúng nguyên văn:
     `panel.allowedContentTypes = [.zip, .gzip, UTType(filenameExtension: "bz2"), UTType(filenameExtension: "tar")].compactMap { $0 }`
     **Không** dùng `.item` hay `.data` thay cho bz2/tar: chúng mở hộp chọn cho gần như mọi tệp, là đổi hành vi.
  3. PDF: `panel.allowedFileTypes = ["pdf"]` → `panel.allowedContentTypes = [.pdf]`.
  4. **Không** đụng 4 chỗ trong `NotesDetailView.swift` (có hộp lưu với đuôi tính lúc chạy — việc khác).
- **Nghiệm thu:** `grep -rn "allowedFileTypes" XFinder --include='*.swift'` chỉ còn 4 dòng của NotesDetailView · đọc diff:
  dòng Compress đúng nguyên văn ở bước 2 · `build-and-check` thành công.

---

### T05 · Ghi chú mép: chữ "Ghim" lọt tiếng Việt + 3 nút chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/EdgeNotesViews.swift`), ~4 dòng
- **Vì sao:** `.help(note.isPinned ? L10n.t("Bỏ ghim") : "Ghim")` — nhánh sau không qua `L10n.t`, nên UI tiếng Anh hiện
  "Ghim". Lint `audit-l10n-literals.py` **không thấy** được lỗi này (nó chỉ bắt chữ có dấu) — kiểm bằng đọc diff.
- **Các bước:**
  1. Đổi `.help(note.isPinned ? L10n.t("Bỏ ghim") : "Ghim")` thành
     `.help(note.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim")).accessibilityLabel(note.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))`
  2. Sau `.help(L10n.t("Thêm ô đánh dấu (⌘T)"))` nối thêm `.accessibilityLabel(L10n.t("Thêm ô đánh dấu (⌘T)"))`.
  3. Sau `.help(L10n.t("Xóa ghi chú"))` thêm dòng `.accessibilityLabel(L10n.t("Xóa ghi chú"))`.
- **Nghiệm thu:** `python3 scripts/check-l10n-coverage.py` TOTAL 0 (cả bốn khoá đã có sẵn trong store) · đọc diff: không còn
  chuỗi trần nào trong `.help(...)` của file · `build-and-check` thành công.

---

### T06 · Thẻ clipboard: nút ghim và sao chép lại chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/ClipboardCardView.swift`), 2 dòng
- **Các bước:**
  1. Sau `.help(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))` thêm dòng
     `.accessibilityLabel(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))`.
  2. Sau `.help(L10n.t("Sao chép lại vào clipboard"))` thêm dòng `.accessibilityLabel(L10n.t("Sao chép lại vào clipboard"))`.
- **Nghiệm thu:** `grep -c accessibilityLabel XFinder/Views/ClipboardCardView.swift` = 2 (trước là 0) ·
  `python3 scripts/audit-l10n-literals.py` không tăng · `build-and-check` thành công.

---

### T07 · Cử chỉ chuột: menu "…" và nút về mặc định chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/Components/GestureActionPicker.swift`), 2 dòng
- **Lưu ý (đã đo ở P9):** nhãn đặt trên **`Menu`** bị VoiceOver bỏ qua — nó đọc tên biểu tượng. Với `Menu`, nhãn phải nằm
  trên `Image` bên trong `label:`. Với `Button` thì đặt trên Button như thường.
- **Các bước:**
  1. Trong `label:` của Menu có `Image(systemName: "ellipsis.circle")`, nối vào Image đó (sau `.font(.system(size: 14))`):
     `.accessibilityLabel(L10n.t("Đổi hành động cho hướng này"))`.
  2. Sau `.help(L10n.t("Đưa hướng này về preset — không đụng các hướng khác"))` của nút `arrow.uturn.backward`, thêm dòng
     `.accessibilityLabel(L10n.t("Đưa hướng này về preset — không đụng các hướng khác"))`.
- **Nghiệm thu:** đọc diff: đúng 2 dòng thêm, dòng đầu nằm **trong** khối `label:` của Menu · `build-and-check` thành công ·
  `audit-l10n-literals.py` không tăng.

---

### T08 · Trang Pin: 3 nút biểu tượng chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/Components/BatteryViews.swift`), 3 dòng
- **Các bước:** sau mỗi dòng dưới đây thêm một dòng `.accessibilityLabel(...)` cùng chuỗi:
  `.help(L10n.t("Làm mới pin"))` · `.help(L10n.t("Chế độ danh sách"))` · `.help(L10n.t("Chế độ lưới"))`.
- **Nghiệm thu:** `grep -c accessibilityLabel XFinder/Views/Components/BatteryViews.swift` = 3 (trước là 0) ·
  `git diff --stat` = 1 file, 3 dòng thêm · `build-and-check` thành công.

---

### T09 · Nút xoá ô tìm kiếm (sidebar, Ghi chú, Thư viện Clipboard) không có nhãn — TODO

- **Cỡ:** S · 3 file, 6 dòng
- **Các bước:** ở ba nút dưới đây, ngay sau `.buttonStyle(.plain)` của nút đó, thêm hai dòng
  `.help(L10n.t("Xoá tìm kiếm"))` và `.accessibilityLabel(L10n.t("Xoá tìm kiếm"))` (khoá đã có trong store):
  1. `XFinder/Views/Sidebar/SidebarView.swift`: `Button { query = "" } label: { Image(systemName: "xmark.circle.fill")…`
  2. `XFinder/Views/Detail/NotesDetailView.swift`: `Button { searchText = "" } label: {`
  3. `XFinder/Views/Detail/ClipboardLibraryView.swift`: `Button { store.query.text = "" } label: {`
  **Không** đụng nút `xmark.circle.fill` thứ hai trong ClipboardLibraryView (`store.closeInspector()` — nút đóng, không phải
  xoá tìm kiếm).
- **Nghiệm thu:** `grep -n -A4 'xmark.circle.fill' <3 file>` — mỗi nút xoá tìm kiếm có đủ hai dòng · `build-and-check`
  thành công · `audit-l10n-literals.py` không tăng.

---

### T10 · Notch: nút Đang phát và menu sắp xếp không có nhãn VoiceOver — TODO

- **Cỡ:** S · 2 file, ~9 dòng
- **Lưu ý:** như T07 — `Button` thì nhãn trên Button; `Menu` thì nhãn trên `Image` trong `label:`.
- **Các bước** trong `XFinder/Views/NotchSurfaceView.swift`:
  1. Hàm `nowPlayingControls(size:)` và hàm `transportRow(enabled:)`: mỗi nút có `.help(L10n.t("Bài trước"))`,
     `.help(L10n.t("Phát hoặc tạm dừng"))`, `.help(L10n.t("Bài tiếp"))` (3 nút × 2 hàm = 6 chỗ) — nối
     `.accessibilityLabel(L10n.t("<cùng chuỗi>"))` ngay sau `.help(...)` đó.
  2. `transportRow`: `label: { Image(systemName: "shuffle").font(.system(size: 12)) }` → nối
     `.accessibilityLabel(L10n.t("Xáo trộn"))` vào Image; `label: { Image(systemName: "repeat").font(.system(size: 12)) }`
     → nối `.accessibilityLabel(L10n.t("Lặp lại"))` vào Image. Giữ nguyên `.help(...)` trên Menu.
  3. `XFinder/Views/NotchClipboardView.swift`, `sortMenu`: nối vào cuối chuỗi modifier của
     `Image(systemName: "arrow.up.arrow.down")` (sau `.background(Circle().fill(N.capsule))`):
     `.accessibilityLabel("\(L10n.t("Sắp xếp")) · \(model.sort.titleVI)")`. Giữ nguyên `.help` và `.accessibilityLabel` đang
     có trên Menu (giống mẫu đã sửa ở `NotchAgentsPage.swift`, chỗ `arrow.triangle.branch`).
- **Nghiệm thu:** đọc diff: chỉ thêm, không xoá dòng nào; hai nhãn Menu nằm trong khối `label:` · `build-and-check` thành
  công · `check-l10n-coverage.py` và `audit-l10n-literals.py` không đổi.

---

### T11 · Test cho nhánh "Other" của `usagePageName` — TODO

- **Cỡ:** S · 1 file test (`Tests/XFinderLogicTests/DeviceCapabilityTests.swift`), ~10 dòng thêm, không đụng code app
- **Vì sao:** `DeviceCapabilityProbe.usagePageName(_:)` có 4 kết quả; chưa test nào gọi tới "Other" và mốc `>=` của "Vendor".
- **Các bước:** thêm một hàm `testUsagePageNameCoversEveryBranch()` vào class test sẵn có, gọi thẳng `usagePageName` (dùng
  hằng có tên, không viết số trần):
  `usagePageButton` → "Button" · `usagePageConsumer` → "Consumer" · `usagePageVendorDefined` và `usagePageVendorDefined + 1`
  → "Vendor" · `usagePageGenericDesktop` và `usagePageVendorDefined - 1` → "Other".
- **Nghiệm thu:** `swift test` tăng đúng 1 test, 0 lỗi · **chứng minh test đỏ được**: tạm đổi `>=` thành `>` trong
  `DeviceCapabilityTypes.swift`, chạy lại thấy đỏ, sửa tay về `>=`, rồi
  `git diff --quiet -- XFinder/Core/MouseGestures/DeviceCapabilityTypes.swift && echo SẠCH` phải in `SẠCH` (không dùng
  `git checkout`/`git stash`) · `git diff --stat` cuối cùng = chỉ file test.

---

### T12 · Test riêng cho `TimeZoneConversion` — TODO

- **Cỡ:** S · 1 file test **mới** `Tests/XFinderLogicTests/TimeZoneConversionTests.swift` (gói test tự nhận file mới, không
  cần pbxproj; `TimeZoneConversion.swift` đã được symlink), ~110 dòng
- **Các bước:**
  1. Đọc hết `XFinder/Core/SmartSelect/TimeZoneConversion.swift` trước (181 dòng): tên hàm, tên trường, tập `ambiguous`.
  2. Viết test cho từng hàm, mỗi kỳ vọng suy từ code + phép đo, không đoán:
     - `zone(for:)`: `EST` cố định −5h kèm vùng New York; `PT` đi theo vùng; mọi phần tử của tập `ambiguous` trả nil;
       `UTC+7`, `GMT-5:30` đúng offset; `UTC+5:07` trả nil (chỉ phút 0/15/30/45 hợp lệ); chữ thường và dấu "−" được chuẩn hoá.
     - `parseClock(_:)`: `3pm`, `3:30pm`, `9:30 a.m.`, `15:00`, `15h30`, `15h` đúng; `13pm`, `3:99pm`, `25:00`, `hello` → nil.
     - `convert(_:now:to:)`: một ca offset cố định; ca có ghi chú vùng (EST khi New York đang giờ mùa hè) — **tính offset thật
       bằng `TimeZone(identifier: "America/New_York")!.secondsFromGMT(for: ngày_chọn)` rồi mới viết kỳ vọng**, kèm một ngày giờ
       mùa đông để thấy ghi chú biến mất; chuỗi dài quá giới hạn và vùng lạ → nil.
     - `Result.isSameAsLocal`, `RegionNote.city`, `offsetLabel`, `clockLabel`.
  3. Một test chạy xanh chưa chứng minh gì: chọn một kỳ vọng, cố ý đổi sai, thấy đỏ, đổi lại.
- **Nghiệm thu:** `swift test` tăng đúng số test mới, 0 lỗi · `git status --short` chỉ thêm đúng file test mới, không file app
  nào đổi · ghi trong worklog kỳ vọng nào đã được làm đỏ thử.

## 7. Việc cần bạn duyệt trước (agent KHÔNG làm khi chưa duyệt)

Đã kiểm là có thật và nhỏ, nhưng đổi thứ người dùng thấy, nên chờ bạn trả lời Q-OC. Bạn duyệt mã nào thì Claude chuyển nó
xuống mục 6 kèm các bước.

| Mã | Việc | Vì sao cần bạn |
|:--|:--|:--|
| OC-47 | Thanh âm lượng và thanh tiến trình tác vụ trên notch theo màu nhấn (`notch.accent`) thay vì luôn trắng (`NotchSurfaceView.swift`, 2 chỗ `.tint(.white)`) | Mặc định "Theo hệ thống" ⇒ hai thanh đổi từ trắng sang màu nhấn của macOS cho mọi người |
| OC-18 | Tuỳ chọn có con trỏ trong ảnh chụp (`screencapture -C`) | Thêm một công tắc và một khoá cài đặt mới |
| OC-20 | Tuỳ chọn bỏ bóng cửa sổ khi chụp cửa sổ (`screencapture -o`) | Như trên; test hiện đang ghim "không bao giờ có `-o`" |

## 8. Việc chỉ Claude làm (không phải S)

- Mọi mã OC bạn chọn ngoài ba mã trên (phần lớn là tính năng mới hoặc nhiều file).
- Đăng 1.4.0 (Q-RELEASE-14) — đụng script phát hành, ký, GitHub.
- Theo dõi T-LIMIT-1: nếu lần chạm giới hạn thật cho kết quả khác, phải đo lại transcript và sửa `AgentEvents.swift`.
- Bốn chỗ `allowedFileTypes` trong `NotesDetailView.swift` (hộp lưu với đuôi tính lúc chạy) — cần thử hộp lưu thật.
- Mọi việc chạm vùng cấm ở mục 2, mọi việc cần mở app, cấp quyền hay đo trên máy.
