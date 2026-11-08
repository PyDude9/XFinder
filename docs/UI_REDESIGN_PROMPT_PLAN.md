# PROMPT PLAN: ĐỒNG BỘ & TÁI THIẾT KẾ TOÀN DIỆN UI/UX XFINDER (MACOS NATIVE SWIFTUI)
*Cập nhật: Bổ sung Chuẩn UI/UX Switch Apps (⌘-Tab) & Hệ thống Dynamic Island / Notch Surface (OneNotch + Vorssaint)*

---

## 1. MỤC TIÊU VÀ NGUYÊN TẮC BẤT BIẾN (MISSION & GUARDRAILS)

1. **Mục tiêu**:
   - Dựng lại toàn bộ giao diện XFinder (macOS 14+ SwiftUI native, arm64) theo ngôn ngữ **Native Flat System Utility** thống nhất, học hỏi trực tiếp từ kiến trúc phân tầng của **Vorssaint** và bề mặt tương tác của **OneNotch**.
   - **Xóa bỏ hoàn toàn phong cách "Boxed Cards"** (`SettingsCard` xám xịt đóng hộp nặng nề kiểu web cũ). Chuyển 100% sang layout phẳng chuẩn macOS HIG: `PageHeader` -> `SectionHeader` -> `Divider().padding(.horizontal, 20)`.
   - **Bảo toàn 100% logic backend hiện có**: Không sửa đổi trái phép các controller nghiệp vụ (`SystemMonitorManager`, `DiskManager`, `ClipboardManager`, `CommandTabController`, `NotchDropController`, v.v.). Chỉ tái cấu trúc lại tầng View & Presentation.
2. **Nguyên tắc kỹ thuật sống còn**:
   - **0.0% Idle CPU & <30 MB Dirty RAM**:
     - Notch & Switcher chỉ kích hoạt khi có tương tác (pointer hover, drag-and-drop, hotkey `⌘-Tab`, audio playing). Khi ở trạng thái nghỉ: giải phóng view, hủy timer, zero polling.
     - Dùng `NSEvent.addGlobalMonitorForEvents` thay vì `Timer` để bắt chuyển động chuột.
   - **Honesty Rule**: Không hiển thị số liệu giả mạo. Không bịa số GPU/SMC khi không có API công khai.
   - **L10n 100%**: Tất cả chuỗi ký tự hiển thị phải bọc `L10n.t()`. Không dùng string interpolation bên trong `L10n.t(...)`. Script `audit-l10n-literals.py` phải ra `TOTAL 0`.

---

## 2. BỘ DESIGN TOKENS CHUẨN (`XFinderTokens.swift`)

Nguồn chân lý duy nhất cho toàn bộ hệ thống giao diện:

* **Màu sắc & Bề mặt (Glass & Surface)**:
  - Nền cửa sổ chính: `Color(nsColor: .windowBackgroundColor)`
  - Bề mặt kính Liquid Glass (Switcher & Notch): `NSVisualEffectView` với `.hudWindow` / `.popover`, `blendingMode = .behindWindow`, bo góc container `20pt - 24pt`, viền `Color.white.opacity(0.10)`.
  - Nền surface phẳng trong trang: `Color(nsColor: .controlBackgroundColor)`
  - Viền đường tóc (Hairline): `Color.primary.opacity(0.06)` (1px, không bóng)
  - Viền Hover: `Color.primary.opacity(0.04)` | Focus: `Color.accentColor.opacity(0.35)`
  - Accent Primary: `#0A84FF` (System Blue) hoặc Accent của macOS.
* **Thang Spacing chuẩn**:
  - Lề ngang toàn trang: `padding(.horizontal, 20)`
  - Khoảng cách giữa các Section: `24pt`
  - Khoảng cách giữa các dòng: `8pt` - `12pt`
  - Bo góc chuẩn: `6pt` (badge/pill), `8pt` (control/nút), `12pt` (thumbnail/card con), `24pt` (Notch/Switcher container).
* **Typography Hierarchy**:
  - Tiêu đề trang (`PageHeader`): `Font.system(size: 26, weight: .bold)`
  - Tiêu đề nhóm (`SectionHeader`): `Font.system(size: 14, weight: .semibold)`
  - Dòng cài đặt (`LabeledLine`, `ToggleRow`): `Font.system(size: 13, weight: .medium)`
  - Đọc số hệ thống (`MetricBigNumber`, `MeterRow`): `Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit()`
  - Phụ đề & chú thích: `Font.system(size: 11, weight: .regular, design: .default)`

---

## 3. THIẾT KẾ UI/UX GIAO DIỆN SWITCH APPS (⌘-TAB SWITCHER)

Thay thế App Switcher mặc định của macOS bằng giao diện **Liquid Glass Switcher HUD** hiện đại, kết hợp quản lý cửa sổ trực quan:

```
┌────────────────────────────────────────────────────────────────────────┐
│                      Liquid Glass Switcher Overlay (⌘-Tab)             │
├────────────────────────────────────────────────────────────────────────┤
│ [Search Window 🔍]                                  Display: All (2) ▾ │
│                                                                        │
│ ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                │
│ │  [XCode Icon] │  │ [Safari Icon] │  │ [Finder Icon] │   ...          │
│ │ ┌───────────┐ │  │ ┌───────────┐ │  │ ┌───────────┐ │                │
│ │ │ Live      │ │  │ │ Live      │ │  │ │ Live      │ │                │
│ │ │ Preview   │ │  │ │ Preview   │ │  │ │ Preview   │ │                │
│ │ └───────────┘ │  │ └───────────┘ │  │ └───────────┘ │                │
│ │ XFinder.swift │  │ GitHub Repo   │  │ Documents     │                │
│ └───────────────┘  └───────────────┘  └───────────────┘                │
│   (Active ⌘)                                                           │
│                                                                        │
│ Phím tắt: ⇥ Tiếp · ⇧⇥ Lùi · Q Đóng · H Ẩn · Space Phóng to · ⎋ Huỷ      │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Kiến trúc Hiển thị (HUD Panel)**:
   - Panel dạng floating `NSPanel` không chiếm focus bàn phím (`canBecomeKeyWindow = false` để giữ ngữ cảnh app trước đó).
   - Căn giữa màn hình hiện tại có con trỏ chuột (`NSScreen.main`).
   - Hiệu ứng mở/đóng: Scale `0.96 -> 1.0` kết hợp Fade in/out trong `120ms` (Zero lag).
2. **Trải nghiệm duyệt cửa sổ (App & Window Level)**:
   - **Cấp độ Ứng dụng (App Mode)**: Dãy icon ứng dụng đang mở, hỗ trợ nhấn giữ ⌘ và gõ Tab để di chuyển, `~` (backtick) để duyệt các cửa sổ bên trong ứng dụng đó.
   - **Cấp độ Cửa sổ (Window Preview Mode)**: Hiển thị thumbnail trực tiếp của từng cửa sổ (ScreenCaptureKit / CGWindowList).
   - Fallback thông minh: Nếu chưa cấp quyền Screen Recording, tự động chuyển về chế độ "Icon + Tiêu đề cửa sổ" mà không bị crash hay hiển thị khung đen.
3. **Thao tác nhanh ngay trên Switcher**:
   - Bấm `Q`: Đóng ngay cửa sổ đang chọn (`AXUIElement` action `Press` trên nút Close).
   - Bấm `H`: Ẩn ứng dụng (`NSApplication` hide).
   - Bấm `Space`: Phóng to Quick Look thumbnail cửa sổ đang chọn để đọc nội dung.
   - Ô tìm kiếm cửa sổ (`WindowSwitcherSearchPill`): Gõ trực tiếp để lọc theo tên ứng dụng hoặc tiêu đề tab browser.
4. **Trang cấu hình trong Settings (`.windowPreview`)**:
   - Đưa về chuẩn **Flat System-Settings**: Bật/tắt ⌘-Tab, cấu hình tốc độ lướt, tùy chọn hiện/ẩn cửa sổ đã thu nhỏ (minimized), danh sách ứng dụng loại trừ không hiện trong Switcher.

---

## 4. HỆ THỐNG DYNAMIC ISLAND & NOTCH SURFACE (ONENOTCH + VORSSAINT)

Nâng cấp `NotchDropController` thành **Notch Surface Engine** toàn diện, biến tai thỏ vật lý (hoặc viên thuốc ảo "Virtual Pill" trên màn hình ngoài) thành trung tâm tương tác trực quan:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Notch / Dynamic Island Surface                  │
├────────────────────────────────────────────────────────────────────────┤
│ 1. Trạng thái Nghỉ: [ 🎧 AirPods 94% ]  ●  [ 🎵 Bohemian Rhapsody ılı ]│
├────────────────────────────────────────────────────────────────────────┤
│ 2. Khi Kéo File Vào:                                                   │
│    ┌─────────────────────────────────────────────────────────────┐     │
│    │  📥 THẢ VÀO ĐÂY ĐỂ XỬ LÝ NHANH                              │     │
│    │  [AirDrop]  [Nén ZIP]  [Tách nền AI]  [OCR Chữ]  [Xuất PDF]  │     │
│    └─────────────────────────────────────────────────────────────┘     │
├────────────────────────────────────────────────────────────────────────┤
│ 3. Khi Kéo Cửa Sổ Chạm Notch:                                          │
│    ┌─────────────────────────────────────────────────────────────┐     │
│    │  📐 GHIM CỬA SỔ (SNAP ZONES)                                │     │
│    │  [ ◧ Nửa Trái ]  [ ◨ Nửa Phải ]  [ ◰ 4 Góc ]  [ ▣ Toàn Màn ] │     │
│    └─────────────────────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Surface Engine & Vị trí hiển thị**:
   - `NotchPanel`: `NSPanel` floating ở level `.statusBar`, gắn sát tọa độ `NSScreen.main.auxiliaryTopLeftArea` & `auxiliaryTopRightArea`.
   - Đối với MacBook có tai thỏ: Khớp chính xác kích thước Notch phần cứng.
   - Đối với iMac/Màn hình ngoài không có Notch: Vẽ một "Dynamic Pill" bo góc `20pt`, đen tuyền viền hairline siêu mảnh sát mép trên.
   - Spring Physics: Animation bung mở chiều ngang/dọc với `response: 0.32s, dampingFraction: 0.82`.
2. **Live Activities trên Notch**:
   - **Pin & Thiết bị**: Kết nối AirPods/Magic Mouse -> hiện phần trăm pin kèm icon động `[🎧 94%]`. Cảnh báo pin yếu `[⚠️ Pin 10%]`.
   - **Now Playing Visualizer**: Đang phát nhạc (Spotify, Apple Music) -> hiện thanh visualizer sóng âm thanh chuyển động nhẹ nhàng bên cánh phải tai thỏ.
   - **HUD Âm lượng & Độ sáng**: Điều chỉnh âm lượng/độ sáng bằng phím vật lý -> Notch bung nhẹ hiện thanh mức âm lượng/độ sáng thay thế HUD cồng kềnh mặc định của macOS.
   - **Pomodoro / Hẹn giờ**: Đếm ngược thời gian làm việc trực tiếp ngay cạnh tai thỏ.
3. **File Shelf & Instant Action Hub (Kéo thả file vào Notch)**:
   - Kéo bất kỳ file nào chạm vào tai thỏ -> Notch tự động bung rộng thành khay thả file.
   - Các nút tác vụ nhanh tức thời:
     - `Nén ZIP`: Nén nhanh file/thư mục.
     - `Tách nền AI` (`Remove BG`): Dùng Vision `VNGeneratePersonSegmentationRequest` tách nền ảnh offline 100%.
     - `OCR Chữ`: Dùng Apple Vision OCR trích xuất văn bản từ ảnh thẳng vào Clipboard.
     - `Xuất PDF`: Chuyển đổi ảnh/tài liệu sang file PDF.
     - `AirDrop`: Mở nhanh khay chia sẻ AirDrop.
   - Hiển thị tiến trình bất đồng bộ trực tiếp trên Notch (`42% Đang nén...`), xong việc có nút `Xem trong Finder` và `Chép`.
4. **Window Snap via Notch**:
   - Kéo bất kỳ cửa sổ nào chạm vào cạnh tai thỏ -> Notch bung menu các bố cục: Chia đôi (Trái/Phải), Chia ba, Chia tư, Toàn màn hình. Thả chuột để cửa sổ tự snap vào vùng tương ứng.
5. **Trang Cài đặt Notch (`.dropTray` & `.snapZones`)**:
   - Cấu hình bật/tắt từng Live Activity (Pin, Nhạc, HUD, Pomodoro).
   - Tùy chọn hiển thị Notch ảo trên màn hình ngoài.
   - Điều chỉnh độ nhạy vùng phát hiện hover chuột (chống kích hoạt nhầm khi dùng chuột bình thường).

---

## 5. THIẾT KẾ TRANG QUYỀN & TÍNH NĂNG (CHUẨN VORSSAINT SETTINGS)

Học tập trực tiếp từ màn hình **Vorssaint Settings** (đính kèm trong ảnh thực tế):

1. **Thanh tìm kiếm Sidebar**:
   - Đặt ô tìm kiếm ở đầu Sidebar: `[🔍 Tìm cài đặt... ]`.
   - Lọc thời gian thực danh sách 32 tính năng bên dưới.
2. **Trang Tính năng & Quyền (`.features`)**:
   - Segmented Control ở đầu trang: `[ Tính năng ]`  `[ Quyền ]` (như ảnh Vorssaint).
   - **Tab Quyền (Permissions)**:
     - Danh sách toàn bộ quyền macOS: `Trợ năng (Accessibility)`, `Ghi màn hình (Screen Recording)`, `Toàn quyền đĩa (Full Disk Access)`, `Thông báo (Notifications)`, `Tự động hóa Finder (Automation)`.
     - Mỗi quyền có: Icon, Tên quyền, Badge trạng thái (`• Đã cấp` xanh lá / `○ Chưa cấp` cam), mô tả chức năng, và danh sách các tính năng đang dùng quyền đó.
     - Nút bấm `Mở Cài đặt hệ thống` trực tiếp tới pane tương ứng.
     - **Cảnh báo trung thực (Vorssaint Pattern)**: Nếu người dùng đã cấp quyền nhưng không có tính năng nào bật đang cần quyền đó -> Hiện khung cảnh báo: *"Bạn đã cấp quyền này, nhưng hiện không có tính năng nào cần nó. Bạn có thể thu hồi trong Cài đặt hệ thống."*

---

## 6. LỘ TRÌNH THỰC HIỆN TỪNG BƯỚC (ROADMAP)

```
[Phase 0: Dọn Baseline & Nền Tảng Kỹ Thuật]
  ├── Fix syntax line 648 DeviceCapabilityTests.swift (?.contains == true)
  ├── Thêm .gitignore cho các thư mục công cụ
  ├── Thêm re-arm MenuBarHiderController vào didBecomeActive
  └── swift test 100% xanh

[Phase 1: Foundation Tokens & Shared Components]
  ├── Tạo `XFinderTokens.swift` (spacing 4..24, hairline 0.06, LiquidGlass tokens)
  ├── Chuẩn hoá PageHeader, SectionHeader, StatusChecklistRow, LabeledLine
  └── Tạo SegmentedPicker style pill (chuẩn Vorssaint)

[Phase 2: Redesign Switch Apps & Window Preview]
  ├── Refactor `CommandTabController` & `WindowPreviewComponents`:
  │     ├── HUD Liquid Glass overlay mở rộng
  │     ├── Phím tắt Q (đóng), H (ẩn), Space (Quick Look), ô tìm kiếm tab
  │     └── Fallback mượt mà khi không có quyền Screen Recording
  └── Đồng bộ trang cài đặt `.windowPreview` sang Flat System-Settings

[Phase 3: Xây Dựng Notch Surface & Live Activities]
  ├── Nâng cấp `NotchDropController` thành Surface Panel (Notch thật + Virtual Pill)
  ├── Tích hợp Live Activities: AirPods Battery, Pomodoro, Audio Visualizer, Volume HUD
  ├── Tích hợp Instant Action Hub (Kéo file vào Notch: Nén, OCR, Remove BG, To PDF)
  └── Tích hợp Kéo cửa sổ chạm Notch để Snap Zone

[Phase 4: Redesign Toàn Bộ 32 Trang Cài Đặt & Hồi Sinh Clipboard Deck]
  ├── Đập bỏ 100% `SettingsCard` ở 11 trang Category B & 4 trang Hybrid -> Đưa về Flat Native
  ├── Hồi sinh `ClipboardTabView` (PasteApp deck) nối lại vào Sidebar & RootView
  ├── Triển khai trang Quyền (Permissions) chuẩn Vorssaint có cảnh báo quyền thừa
  └── Tối ưu Sidebar với search filter và badge idle cost

[Phase 5: Kiểm Thử L10n & Đo Đạc Hiệu Năng]
  ├── L10n sweep: audit-l10n-literals.py = TOTAL 0
  ├── Đo Dirty RAM < 30 MB (`vmmap --summary`)
  └── Đo Idle CPU = 0.00s (`ps -o time=`)
```

---

## 7. TIÊU CHÍ NGHIỆM THU (ACCEPTANCE CRITERIA)

1. **Switch Apps (⌘-Tab)**:
   - Nhấn ⌘-Tab hiện HUD kính mờ Liquid Glass tức thời (<16ms).
   - Duyệt app mượt mà, thumbnail hiển thị chuẩn xác, bấm Q đóng app, bấm Space zoom xem trước, có ô tìm kiếm.
2. **Dynamic Island / Notch**:
   - Kéo file chạm Notch bung khay thao tác nhanh (Nén, Tách nền, OCR, PDF); chạy tác vụ không nghẽn Main Thread; hiển thị tiến trình % trực tiếp trên Notch.
   - Live activities (pin thiết bị, âm lượng, nhạc) hiển thị tinh tế, ôm sát tai thỏ, không đè vỡ thanh Menu Bar.
   - Khi không có tương tác: Tiến trình Notch ngủ hoàn toàn, CPU tiêu thụ = 0.0%.
3. **Mỹ thuật & Thống nhất toàn app**:
   - 100% các trang cài đặt theo phong cách phẳng System-Settings giống ảnh Vorssaint, dẹp sạch card đóng hộp xám cũ.
   - Trang Quyền hiển thị chính xác các tính năng phụ thuộc và cảnh báo quyền thừa.
   - `ClipboardTabView` xem và tìm kiếm clipboard mượt mà.
   - `swift test` pass 100%, L10n không bị rò rỉ ký tự tiếng Việt chưa dịch.
