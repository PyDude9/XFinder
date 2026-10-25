# XF-T30 W4 — contract (cửa sổ Cài đặt trình duyệt, đổi phím + hồ sơ, Welcome)

Spec tổng §2 hàng W4, Q-T30-9/10/12. Hành vi: `scratchpad/claude/t30/spec-settings-keyboard.md` (§0–§9). **Ảnh chủ dự án
thắng guide**: tab Chung có "Cửa sổ mới hiện", "Hiện trong cửa sổ: Location Bar · Path Bar · Status Bar", "Mở lại cửa sổ…",
"Return đổi tên / mở", "⌘X để cắt", cập nhật phần mềm; tab Nâng cao có "Hiện mọi đuôi tệp", "Hiện tệp ẩn", "Thư mục lên đầu khi
sắp theo tên", "Khi tìm kiếm: Máy này / Thư mục hiện tại / Phạm vi trước". Stub thêm SAU khi W1 gộp.

## 1. Khoá (ONE reader trong `BrowserSettings`, control duy nhất ở cửa sổ Cài đặt; hàng `FeatureKeyDefaultsTests` cho Bool/Int/String)

| Khoá | Kiểu | Mặc định | Tab |
|:--|:--|:--|:--|
| `fileBrowser.newWindowTarget` | String `home|desktop|documents|downloads|recents|computer?|custom` | `home` | Chung |
| `fileBrowser.newWindowCustomPath` | String | `""` | Chung |
| `fileBrowser.showLocationBar` / `showPathBar` / `showStatusBar` | Bool | true / false / true (W1) | Chung |
| `fileBrowser.reopenWindows` | Bool | true (có sẵn) | Chung |
| `fileBrowser.returnOpens` | Bool | false | Chung (Windows Explorer habits) |
| `fileBrowser.cutWithCmdX` | Bool | false | Chung |
| `fileBrowser.sidebar.favorites` … `.recentTags` | Bool | true, trừ `bonjour` false | Sidebar (W3 đọc) |
| `fileBrowser.sidebar.groupLocationsByType` / `.highlightCurrent` | Bool | false / false | Sidebar |
| `fileBrowser.showAllExtensions` | Bool | false | Nâng cao |
| `fileBrowser.showHidden` / `foldersFirst` | Bool | false / false (có sẵn) | Nâng cao |
| `fileBrowser.search.defaultScope` | String | `mac` (W5a) | Nâng cao |
| `fileBrowser.keyProfile` | String `finder|explorer|commander|custom` | `finder` | Bàn phím |
| `fileBrowser.keyBindings` | Data JSON | (không có = mặc định) | Bàn phím |
| `fileBrowser.tabSwitchesPanes` | Bool | false (Total Commander bật) | Bàn phím |
| `fileBrowser.mouseBackForward` | String `on|off|swapped` | `on` | Bàn phím |
| `fileBrowser.onboardingDone` | Bool | false | (Welcome) |

## 2. Thuần (builder K4 — `KeyBindings.swift` (mới), test)

- `KeyBindings`: mỗi lệnh **đúng hai** ô (Phím, Phím thêm); mặc định từ `BrowserCommands` (bảng W1); ba hồ sơ (Finder; Windows
  Explorer: Return mở, F2 đổi tên, ⌘X cắt, Delete **không** vào Thùng rác; Total Commander: F5 chép sang ngăn kia, F6 chuyển
  sang ngăn kia, F7 thư mục mới, F8 vào Thùng rác, Tab chuyển ngăn, Return mở); áp hồ sơ rồi vẫn sửa được; `validate(chord)`
  từ chối: không có ⌘ hoặc ⌃ (trừ F1–F12 trong hồ sơ), phím hệ thống/Finder dành riêng, Return/Space/Tab/mũi tên/F2 (khi
  không phải hồ sơ cho phép); xung đột ⇒ trả lệnh đang giữ (UI hỏi "Vẫn dùng"); `export() -> Data` (bảng + 2 tuỳ chọn chuột),
  `import(Data) -> Result<KeyBindings, [ImportError]>` kiểm **trọn** trước khi áp (lệnh lạ, một phím hai lần, phím dành riêng —
  liệt kê hết, không áp một phần), JSON chỉ là dữ liệu. `command(for chord:)` thay chỗ gọi `BrowserCommands.command(for:)` ở
  `BrowserWindow`; `chord(for:)` cho menu/toolbar/bảng lệnh.

## 3. AppKit/SwiftUI (builder S4 — `BrowserSettingsWindow.swift` (mới); O4 — `OnboardingWindow.swift` (mới); X4 — `FileBrowserDetailView.swift`, `BrowserSettings.swift`)

- Cửa sổ Cài đặt trình duyệt (⌘, khi cửa sổ trình duyệt là key — dispatcher của `BrowserWindow`; menu "Cài đặt trình duyệt…"),
  toolbar tab kiểu Settings: **Chung · Sidebar · Đám mây · Nâng cao · Bàn phím · Tìm kiếm · Quyền riêng tư** (không License —
  Q-T30-8). Đám mây: nội dung W8 (W4 dựng khung + danh sách `~/Library/CloudStorage` đang có + "Hiện đám mây trong sidebar" =
  cùng khoá với Sidebar). Tìm kiếm: danh sách gốc (+ / −), mỗi gốc ô Nội dung / Chữ trong ảnh, trạng thái, Tạm dừng, Dựng lại,
  Xoá chỉ mục… (gọi `FilenameIndex`/`ContentIndex` W5a). Bàn phím: bảng nhóm theo menu, ô tìm theo tên hoặc phím, nhấp để ghi,
  Esc huỷ, Delete xoá, Control-click một hàng ⇒ "Khôi phục mặc định", "Khôi phục mặc định" chung, hồ sơ, Xuất…/Nhập…, Tab
  chuyển ngăn, nút chuột 4/5 (Bật / Tắt / Đảo); hàng bị Cài đặt hệ thống ▸ Phím tắt ứng dụng ghi đè hiện "(Cài đặt hệ thống)".
  Quyền riêng tư: Desktop / Documents / Downloads (trạng thái + nút "Cho phép" gây đúng hộp thoại TCC bằng cách đọc thư mục
  đó), Full Disk Access Bật / Tắt / Không kiểm được + "Kiểm lại" + gợi ý "thoát và mở lại" khi vừa cấp, "Hiện cửa sổ Chào…".
- Welcome (lần đầu mở trình duyệt khi `onboardingDone` = false, và từ Quyền riêng tư): 4 bước (Q-T30-9) — Chào (không xin
  quyền) · Quyền thư mục (Cho phép từng thư mục + Cho phép tất cả — luôn qua hộp thoại thật của macOS) · Full Disk Access (bỏ
  qua được: "Tiếp tục không cần Full Disk Access") · Chọn bố cục (Một · Cạnh nhau · Chồng · Lưới, thẻ có hình bố cục; "Mở" mở
  cửa sổ theo bố cục, ngăn mở các thư mục đã cho phép). Chạy lại không hỏi lại quyền đã có.
- Trang cũ "Trình duyệt tệp" (Q-T30-12): còn công tắc bật/tắt + phím toàn cục + "Mở trình duyệt" + **"Mở cài đặt trình
  duyệt…"** + bảng phím tắt rút gọn (đọc từ `KeyBindings`). Mọi control `fileBrowser.*` khác chuyển sang cửa sổ mới (một khoá
  một control).
- Hành vi của khoá mới: `returnOpens` (Return mở, F2/menu đổi tên), `cutWithCmdX` (⌘X đánh dấu cắt, biểu tượng mờ, ⌘V nơi khác
  ⇒ chuyển, Esc / ⌘C mới / chép thứ khác huỷ — không huỷ khi Delete hay điều hướng), `showAllExtensions` (tên hiển thị kèm
  đuôi trừ khi tệp có cờ ẩn đuôi riêng), `newWindowTarget` (⌘N / ⌘T / tab ngăn mới mở ở đây), `tabSwitchesPanes`,
  `mouseBackForward` — builder model của W4 (người tích hợp giao) nối vào model/view.

## 4. Nghiệm thu W4

Test thuần `KeyBindingsTests` (3 hồ sơ, validate, xung đột, xuất/nhập round-trip, nhập hỏng liệt kê đủ lỗi và không áp), hàng
`FeatureKeyDefaultsTests` mọi khoá Bool/String mới, harness. T-T30-19…24: ⌘, mở đúng 7 tab; đổi phím ⌘J thành ⌃⌘J có hỏi xung
đột; hồ sơ Total Commander: F5 chép sang ngăn kia; Xuất rồi Nhập lại; Welcome lần đầu + "Hiện cửa sổ Chào…"; ⌘X kiểu Windows.
