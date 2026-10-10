# XFinder — Kế hoạch tái cấu trúc UI/UX + Notch Surface (2026-10-10)

**Trạng thái**: kế hoạch, chưa sửa dòng code nào cho Phase A trở đi.
**Nguồn**: `implementation_plan.md` (OneNotch + Vorssaint blueprint), prompt "Đồng bộ & tái thiết kế toàn diện UI/UX",
trang tryonenotch.com/vi + /features (50+ tính năng), 10 video demo, và **bản kiểm kê mã nguồn đọc bằng 5 agent chỉ-đọc**
(2026-10-10) cộng số đo của chính tôi trên máy này. Mọi khẳng định "đã có / chưa có" bên dưới trỏ vào file thật.

---

## 0. Trả lời thẳng ba câu hỏi của chủ dự án

**1. "Tại sao vẫn chưa triển khai Dynamic Island / Notch?"**
Không phải vì thiếu API. Mã đã có và đã bị *tắt có chủ đích* hai lần:

* 2026-09: khay thả mở trên **mọi** cú kéo chuột (chọn chữ, kéo cửa sổ) nên hai đường "rê vào notch" và "kéo file vào vùng notch"
  bị comment lại, chỉ giữ cử chỉ **lắc** (`NotchDropController.swift:137` — *"summon ở Notch đã tạm bỏ"*). Hình học notch
  (`isInNotchZone`, dùng `auxiliaryTopLeftArea/TopRightArea`, dòng 182–199) vẫn nằm đó nhưng không còn ai gọi để *mở*.
* Trang Khay thả ẩn cả khối `notchSettings` (65 dòng, 6 control) khỏi `body` (DropTrayDetailView.swift:173–238) — và để lại
  **hai khoá cài đặt không có reader** (`dropTray.hoverEnabled`, `dropTray.notchDropEnabled`): đúng loại "control không làm được điều
  nhãn hứa" mà Part 0 §6 cấm. Đây là lỗi hiện hữu, không chỉ là tính năng thiếu.
* Kế hoạch 2026-10-09 của tôi ghi "Notch — đã gỡ chủ động" vào mục *Bỏ hoàn toàn*. Đó là tôi kế thừa quyết định cũ mà không hỏi lại.
  **Sai.** Kế hoạch này đưa Notch trở lại làm *bề mặt chính* (Phase B), và mục lỗi hai khoá chết được sửa ngay trong Phase A.

Máy này có notch thật: `auxiliaryTopLeftArea` = (0, 1085, 771.5×32), `auxiliaryTopRightArea` = (956.5, 1085, 771.5×32),
`safeAreaInsets.top` = 32 pt — khoảng hở giữa hai vùng = 185 pt chính là tai thỏ.

**2. "UI thô cứng quá — đồng nhất trước đã."** Đúng, và có số đo: trong `XFinder/Views/` có **739** chỗ `.font(.system(size:` với
**26** cỡ chữ khác nhau, **112** `RoundedRectangle(cornerRadius:` với **14** bán kính, **256** `.opacity(` với **39** giá trị,
**12/40 trang** vẫn dùng `SettingsCard` đóng hộp, **9 trang** mở bằng `Text(title)` 22 pt trần thay vì `PageHeader`. Không có
file token nào ngoài `LiquidGlassTokens` (chỉ dùng cho Dock preview/Switcher). Đây là lý do "thô cứng": không phải thiếu đẹp,
mà thiếu *một nguồn chân lý*.

**3. "Tìm phương pháp chuẩn trước rồi mới code."** Mục 2 và 3 bên dưới là phương pháp: *hợp đồng module* + *hệ thống token/
component* + *gate tự fail*. Code chỉ bắt đầu khi hai thứ đó có test.

---

## 1. Hiện trạng đo được (không suy diễn)

| Hạng mục | Đã có (file) | Thiếu / sai |
|:--|:--|:--|
| Sidebar | 32 hàng + Giới thiệu, 6 nhóm; ô tìm trang (`SidebarSearch`) | — |
| Features hub | `FeatureCatalog` 14 tính năng, 3 gói, tab Quyền 4 quyền, nút Cấp quyền, onboarding, xuất/nhập cài đặt | Quyền còn thiếu: Thông báo (bị từ chối với chữ ký tự tạo — xem §6), Lịch (EventKit), Toàn quyền đĩa |
| Trang phẳng | 28 trang đã `PageHeader` | **12 trang** `SettingsCard`; 9 trang `Text` trần; 3 trang hàng tên file thiếu `minWidth:0/maxWidth:.infinity` (Compress:97, PdfTools:59, FinderTool:65); Storage picker `.segmented` **không giới hạn** số volume; ClipboardSettingsBody **2 control cùng khoá** `maxHistory`/`autoDeleteDays` |
| Token | `LiquidGlassTokens` (24/16/10, popover, white 0.10/0.18/0.12) chỉ cho glass | Không có token typography/spacing/radius/opacity cho trang; `PageHeader` 26 bold, `SectionHeader` 14 semibold, `MetricBigNumber` 28 rounded đã *đúng* mục tiêu — làm hạt nhân |
| Panel nổi | 8 chỗ tự dựng `NSPanel` (EdgeNotes, ClipboardShelf, QuickSearch, ColorToast, AlertBanner, QuitHoldHUD, NotchDrop, DockPreview); `KeyablePanel` dùng chung 3 chỗ; mẫu *prepare-once* chỉ ở `QuitHoldHUD` (đo: dựng NSHostingController trong hot path 0.15–0.65 s) | Không có `SurfacePanel` chung; 3 chỗ lặp y nguyên cặp monitor "click ngoài để đóng"; 3 chỗ tự tính "màn hình chứa con trỏ" |
| Notch | `NotchDropController` 600 dòng: cặp monitor global+local, `dragCarriesFiles()`, lắc để mở, panel 420×180 ở `.floating` neo theo con trỏ, kéo nhiều file ra ngoài (`MultiFileDragSource`), tray detail 720×520 | Không neo vào notch; 2 khoá chết; không action hub; không live activity; không snap tại notch |
| Switcher ⌘-Tab | tap `.cgSessionEventTap`, `PreviewOverlayWindow` (.floating+1), **model theo app** (gộp cửa sổ, `isGroup`), SCK thumbnails, fallback icon+tiêu đề khi thiếu Ghi màn hình, **đã có** ô tìm (`WindowSwitcherSearchPill`, phím `,`), **đã có** danh sách loại trừ `windowPreview.excludedApps`, animation 0.18 s | Thiếu Q (đóng), H (ẩn), Space (phóng), lọc theo màn hình, chế độ cửa sổ bằng `` ` ``; `excludedApps` đọc ở 2 nơi (vi phạm một-khoá-một-reader) |
| Clipboard | Shelf ⌘⇧V (deck, Space Quick Look, Paste Stack, ⌘1–9), pinboard + màu, bộ lọc riêng tư, OCR ảnh (`.fast`), Clean URL, tự xoá | `ClipboardTabView` **chết** (0 call site; `.clipboard` còn trong enum/RootView nhưng không ở `groups`) — nửa gỡ dở; chưa có @filter, transforms, board khoá, MCP, highlight code, "đi tới nguồn" |
| Dữ liệu sống cho Notch | `BatteryStore` (Mac + BT/HID: AirPods, chuột), `VolumeObserver`, `ScreenBrightness`, `AlertMonitor`, `ThermalSensors`, `SnapZoneController.snapFrontmost(to:)` + 10 `SnapTarget` | Now Playing: `MediaRemote` nạp được, trả rỗng — **chưa phân biệt được "không có nhạc" với "bị từ chối"** |
| Hiệu năng | idle 0 % khi không trang nào mở (đo 09/2026) | **Dirty memory 48,4 MB** (`vmmap --summary`, idle trên trang Giới thiệu) so với 28,3 MB ghi trong CLAUDE.md và mục tiêu <30 MB — khoảng cách thật, chưa quy được cho module nào |

---

## 2. Phương pháp chuẩn (làm trước, mỗi mục có gate tự fail)

### 2.1 Hợp đồng module tính năng (đã là thực tế ngầm, nay thành luật + script)

Mỗi tính năng có đúng bộ này, không hơn không kém:

```
Core/<Feature>/<Feature>Model.swift      Foundation-only, thuần, symlink vào Tests/  (mọi luật ở đây)
Core/<Feature>/<Feature>Controller.swift @MainActor @Observable, singleton, retain()/release() hoặc applySettings()
Views/Detail/<Feature>View.swift         PageHeader → SectionHeader → hàng; không SettingsCard
Tests/XFinderLogicTests/<Feature>Tests.swift   + ≥1 mutation được chứng minh đỏ
FeatureCatalog entry                     enabledKey đọc dạng chuẩn `object(forKey:) as? Bool ?? default`
L10n.strings.json                        mọi khoá; model trả KHOÁ, view mới gọi L10n.t
docs/probes/ hoặc scratchpad             một probe đo trên app đã cài
```

Gate mới `scripts/check-feature-contract.py`: với mỗi `FeatureCatalog` entry, phải tìm thấy file Model + symlink test + reader
canonical; fail khi thiếu. (Mở rộng `FeatureKeyDefaultsTests` hiện có.)

- [x] **§2.1 gate (2026-10-10)** làm thành test `FeatureContractTests` (chạy cùng `swift test`, không phải script): bảng khai
  báo tính năng → file luật thuần, 8 thuần + 6 miễn trừ có ghi cách trả nợ, miễn trừ chỉ được giảm. Quy ước đặt tên ở trên
  **chỉ khớp 2/14** nên không dùng làm luật; package test biên dịch được AppKit/IOKit (đo: 12 file) nên chỉ cấm SwiftUI.

### 2.2 Hệ thống thiết kế — `XFinderTokens.swift` là nguồn chân lý duy nhất

**Quyết định**: dùng token *native* của prompt UI/UX (mục 2), **bác** bảng màu web của `implementation_plan.md`
(`#080B10`, `Plus Jakarta Sans`, `#38BDF8`): app macOS phải theo sáng/tối hệ thống và SF Pro; palette cố định sẽ hỏng ở Light mode
và vi phạm HIG. `LiquidGlassTokens` giữ nguyên làm section **Glass** của file token (không viết lại cái đang chạy).

```swift
enum XFinderTokens {
  enum Space  { static let page: CGFloat = 20; static let section: CGFloat = 24; static let row: CGFloat = 10; static let tight: CGFloat = 6 }
  enum Radius { static let badge: CGFloat = 6; static let control: CGFloat = 8; static let tile: CGFloat = 12; static let surface: CGFloat = 24 }
  enum Font   { static let pageTitle = Font.system(size: 26, weight: .bold)
                static let sectionTitle = Font.system(size: 14, weight: .semibold)
                static let row = Font.system(size: 13, weight: .medium)
                static let caption = Font.system(size: 11)
                static let metric = Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit() }
  enum Fill   { static let hairline = Color.primary.opacity(0.06); static let hover = Color.primary.opacity(0.04)
                static let focus = Color.accentColor.opacity(0.35); static let surface = Color(nsColor: .controlBackgroundColor) }
  enum Motion { static let surface = Animation.spring(response: 0.32, dampingFraction: 0.82)   // notch bung/thu
                static let overlayIn: TimeInterval = 0.16 }                                   // switcher (hiện 0.18 → chuẩn hoá)
}
```

Bộ component chuẩn (giữ cái đang đúng, bổ sung cái thiếu): `PageHeader`, `SectionHeader`, `LabeledLine`, `ToggleRow`,
**`PickerRow`** (mới: nhãn + Picker `.menu`, cấm `.segmented` > 4), **`ActionRow`** (mới: nhãn + nút), `StatusChecklistRow`,
`MetricBigNumber`, `StatBarView`, `SparklineView`, **`InlineNote`** (mới: ghi chú/warning/permission note — thay 3 kiểu
`permissionNote` tự viết). `SettingsCard` **rút khỏi mọi trang cài đặt**; chỉ còn cho *lưới thẻ* (gói trong hub, thẻ clipboard,
thẻ pin) và đổi tên thành `TileCard` để không ai dùng nhầm làm khung trang.

Gate mới `scripts/audit-ui-tokens.py` — fail khi trong `Views/Detail/`: còn `SettingsCard(`, `.font(.system(size:` với số literal,
`RoundedRectangle(cornerRadius: <số>`, `Text(` tiêu đề trần ở đầu `body`, `.pickerStyle(.segmented)` với > 4 tag hoặc với
`ForEach` không bị chặn. Phải in `TOTAL 0` như lint L10n.

### 2.3 `SurfacePanel` — một lớp cho mọi bề mặt nổi

`final class SurfacePanel: KeyablePanel` với `init(kind: .interactive | .passive)` (interactive: `.floating`, nhận phím;
passive: `.statusBar`, `ignoresMouseEvents`), `prepare()/show(anchor:)/hide()/destroy()` (mẫu QuitHoldHUD — không dựng
NSHostingController trong hot path), `anchor` (`.notch`, `.topCenter`, `.topRight`, `.pointer`, `.spotlight`) dùng
`WindowManager.screenUnderPointer()`, và `ClickOutsideDismisser` (cặp global+local monitor, gỡ trong `hide()`). Tám chỗ hiện
tại chuyển sang dùng dần — mỗi chỗ một commit, đo lại hành vi cũ bằng probe đã có (popover-probe, winlist, e2e-quithold…).

### 2.4 Gate chạy sau mỗi commit (không thêm gì mới ngoài 2 script trên)

`swift test` · `check-l10n-coverage` · `check-l10n-duplicates` · `audit-l10n-literals` · `check-sidebar-groups-l10n` ·
`audit-gesture-vocabulary-l10n` · `verify-l10n-runtime` (bundle đã cài) · **`audit-ui-tokens`** · **`check-feature-contract`** ·
`probe-ax-dump` trang vừa sửa ở **cả hai** ngôn ngữ · idle CPU đo bằng `ps -o time=` **kèm `HIDIdleTime`** (đo khi người dùng đang
gõ là vô nghĩa — đã mắc hôm nay) · `vmmap --summary` dirty.

---

## 3. So với OneNotch: giữ gì, thêm gì, bỏ gì

Nguồn: /features (50+ mục) + 10 video. Chỉ liệt kê mục làm thay đổi kế hoạch.

**Đã có trong XFinder, kế hoạch cũ liệt kê trùng → bỏ khỏi backlog**: ô tìm sidebar · trang Quyền + cảnh báo quyền thừa ·
Alerts · Menu bar readouts · xuất/nhập cài đặt · Clean URL · tự xoá clipboard · bộ lọc riêng tư (trình quản lý mật khẩu) ·
Paste Stack · fallback switcher khi thiếu Ghi màn hình · ô tìm trong switcher · danh sách loại trừ · "Fix dòng 648", `.gitignore`
(đã xong) · "re-arm MenuBarHider" (**bỏ**: hider đang tắt có chủ đích, không dùng AX — thêm `applySettings()` vào didBecomeActive
sẽ thu gọn thanh menu mỗi lần kích hoạt app).

**OneNotch có, XFinder chưa → THÊM** (xếp theo giá trị/chi phí, có cờ trung thực):

| Mục | Dựa trên | Cờ |
|:--|:--|:--|
| Notch Surface (notch thật + Pill) 3 trạng thái, hover/kéo để mở, trang vuốt được | `NotchDropController` + `SurfacePanel` | — |
| Thả file → ô tác vụ: Nén, OCR, PDF, Tách nền, AirDrop, Đổi định dạng; % tiến trình; Reveal/Copy/Share | `DropTrayStore.runZip`, `ScreenTextRecognizer`, PDFKit (tách engine khỏi `PdfToolsDetailView`), `VNGeneratePersonSegmentationRequest`, `NSSharingService(.sendViaAirDrop)` (đã kiểm có) | Tách nền chỉ tách **người** → nhãn "Tách nền (người)" |
| Kéo cửa sổ lên notch → hàng bố cục Halves/Full/Quarters/Thirds/Focus | `SnapZoneController` + 10 `SnapTarget`; thêm Thirds | — |
| Live activity: pin thiết bị BT, cắm sạc/pin yếu/đầy, Caps Lock, mất mạng, hẹn giờ | `BatteryStore`, `AlertMonitor` (chuyển banner vào notch), `AlertRules` thêm 2 quy tắc | — |
| HUD âm lượng/độ sáng trên notch | `VolumeObserver`, `ScreenBrightness` | **Không thể tắt HUD hệ thống** bằng API công khai (OSDUIHelper là private). Hiện *song song*, nói rõ. |
| Now Playing + điều khiển | `MediaRemote` (private) | **Probe-gated**: nạp được nhưng trả rỗng; macOS 15.4+ được ghi nhận rộng rãi là hạn chế MediaRemote với app không có entitlement. Chỉ làm sau khi probe với nhạc đang phát; fallback Apple Music/Spotify qua Apple Events (Automation) |
| Clipboard trên notch: @image/@link/@code/@color/@<app>, ⌘-click chọn nhiều → ⌘V dán theo thứ tự, menu chuột phải Transform (Normalize whitespace, UPPER/lower, Base64, URL encode, MD5), Dịch, Đi tới nguồn | Shelf deck + `ClipboardClassifier`; transforms là hàm thuần | — |
| Board khoá bằng mật mã | pinboard hiện có; AES-GCM (CryptoKit) + khoá trong Keychain | — |
| Thư viện Clipboard (sidebar theo loại/app/board, inspector) | **hồi sinh `ClipboardTabView`** thành trang này, dọn `.clipboard` mồ côi | — |
| Clipboard MCP (`clipboard_search/get/list_recent`) | target executable mới trong bundle, stdio JSON-RPC, đọc SQLite hiện có | tắt mặc định; ẩn mục từ trình quản lý mật khẩu |
| Smart Selection: dịch ⌘⇧G, tiền tệ, đơn vị, múi giờ, ngày → Lịch | Translation framework (**macOS 15+**, app target 14 → gate), `NSDataDetector`, `Measurement` | Tỷ giá cần **mạng** → opt-in riêng, không gửi định danh, cache 24 h; nói rõ trên nhãn |
| Chụp & chú thích (mũi tên, số, kính lúp, thước px, che) | `screencapture -i` đã dùng cho OCR; studio là module lớn mới | Phase F |
| Lịch & lời nhắc trên notch, thẻ "Tham gia họp" | EventKit → thêm quyền Lịch/Lời nhắc vào tab Quyền | Phase F |
| Theo dõi Claude Code/Codex trên notch | đọc log session cục bộ | Phase F, sau khi đo định dạng log |
| Ẩn khi quay màn hình | `NSWindow.sharingType = .none` | rẻ, Phase B |

**OneNotch có nhưng XFinder KHÔNG làm, kèm lý do**: Ẩn icon thanh menu (chết trên macOS 27 — đã đo, CLAUDE.md) · Lời bài hát
(cần nguồn mạng bên thứ ba) · Đồng bộ iCloud (CloudKit cần tài khoản Developer trả phí; tài khoản hiện free) · Player màn hình khoá
(private) · Thay HUD hệ thống *thay thế* (chỉ làm *song song*) · Dịch bằng Google/Bing/Youdao (gửi văn bản ra ngoài — chỉ Apple
on-device + khoá API riêng người dùng tự nhập, như Voice đã làm).

**Trong `implementation_plan.md` nhưng bỏ**: token màu web, font Jakarta, "ứng dụng web" — sai nền tảng.

---

## 4. Lộ trình (UI/UX trước, đúng yêu cầu)

Mỗi hạng mục = một commit, có test + gate + probe. Thứ tự trong phase là thứ tự làm.

### Phase A — Nền tảng UI/UX đồng nhất (làm trước mọi tính năng mới)

> **Baseline đo bằng gate mới (2026-10-10, sau A1):** `audit-ui-tokens.py` → **606 vấn đề / 32 trang**. Phần lớn là cỡ chữ và bán kính
> literal, không chỉ 12 trang card. A3 vì thế là *mọi* trang trong `Views/Detail/`, ưu tiên 12 trang card trước; con số phải về 0.

- [x] **A2b (một phần)** `ToastSurface` trên `SurfacePanel(.passive)`: ColorToast/TextToast/AlertBanner thành wrapper mỏng (e2e màu 6/6,
  banner 380×68 đo được); `QuitHoldHUD` trên `SurfacePanel` (e2e giữ ⌘Q 10/10). **Còn lại 5 chỗ tương tác** (Shelf, QuickSearch, EdgeNotes,
  DockPreview, NotchDrop) — chuyển khi chạm tới từng tính năng (B/C/D), không chuyển mù.
- [x] **A4a** Tab Quyền thêm hàng **Thông báo** (tùy chọn; nói thẳng bị từ chối với chữ ký tự tạo). Lịch/Toàn quyền đĩa **hoãn** tới Phase F —
  thêm hàng quyền mà chưa tính năng nào dùng là một control không có việc.
- [x] **A5 (đo lần 1, 2026-10-10)** idle CPU **0,02 s / 60 s ≈ 0,03 %** với `HIDIdleTime` tăng đủ 60 s (người dùng thật sự rảnh) — các số
  2 % đo trước đó là lúc người dùng đang dùng máy. Dirty memory **61,6 MB** khi mở trang Tính năng (48,4 MB trên trang Giới thiệu) → Phase G.
- [x] **A2a** `Core/Surface/SurfaceGeometry.swift` (thuần: anchor/clamp/notch/pill/expanded, 6 test, 3 mutation đỏ) + `SurfacePanel`
  (`.interactive/.passive/.notch`, prepare-once, `show(anchor:)`, `hide(after:)`) + `ClickOutsideDismisser`. **Chưa** chuyển 8 chỗ cũ sang (A2b).
- [x] **A3** 32/32 trang phẳng — `audit-ui-tokens.py` 606 → **0**; build xanh; 456 test; sweep AX 33 trang × 2 ngôn ngữ (`scripts/sweep-pages-ax.py`,
  qua `xfinder://settings?page=…`) 0 rò. Sửa kèm: 2 control cùng khoá ở Cài đặt Clipboard; picker volume → menu; `notchSettings` chết và `header`
  chết bị xoá; 3 hàng tên file có `fileNameRowSafe()`; `ClipboardTabView` + case `.clipboard` bị xoá (quyết định #2; `ClipboardQLController` tách ra
  `Views/ClipboardQuickLook.swift` vì shelf còn dùng). **Hai lỗi có sẵn lộ ra khi quét**: khoá store giữ dấu `\"` nên không bao giờ khớp (3 khoá —
  `audit-l10n-literals.py` nay so chuỗi *runtime*); trang Nén khẳng định **"7-Zip 26.02 tích hợp sẵn"/giải nén 7Z, RAR, XZ** trong khi chỉ có
  ditto/zip/tar — đã sửa thành sự thật. Hai agent báo gate đẩy picker 2 lựa chọn sang menu vì regex gộp hai picker — gate đã scope theo từng `Picker(`.
- [x] **A1** `XFinderTokens.swift` · `FlatRows.swift` (PickerRow/ActionRow/InlineNote) · `SettingsCard`→`TileCard` (+typealias tạm) ·
  PageHeader/SectionHeader/StatusChecklistRow/ToggleRow/MetricBigNumber đọc token · `scripts/audit-ui-tokens.py`.
1. `XFinderTokens.swift` + `audit-ui-tokens.py` (gate đỏ ngay vì 12 trang) + `PickerRow`/`ActionRow`/`InlineNote`; `PageHeader`,
   `SectionHeader`, `ToggleRow`, `MetricBigNumber` chuyển sang đọc token (không đổi hình).
2. `SurfacePanel` + `ClickOutsideDismisser`; chuyển `ColorToast` và `AlertBanner` trước (passive, rủi ro thấp), rồi QuitHoldHUD,
   ClipboardShelf, QuickSearch, EdgeNotes, DockPreview, NotchDrop. Mỗi lần: chạy lại e2e tương ứng.
3. Phẳng hoá 12 trang theo câu-việc của từng trang (từ kiểm kê):
   Tìm kiếm (10 card) · Cài đặt Clipboard (9, **gộp 2 control trùng khoá**) · Nén (8, **sửa hàng tên file**) · Ghi chú (5, xoá
   `header` chết) · PDF (5, **sửa hàng tên file**) · Đổi tên (4) · Pin (2, `Text("Pin")` chưa qua L10n) · Ổ đĩa (3, **picker volume
   → `.menu`**) · Khay thả (3, **xoá `notchSettings` chết — sẽ dựng lại trong Phase B**) · Chống ngủ (1) · Tương thích media (2,
   **sửa hàng tên file**) · Quick Look (1).
4. Tab Quyền: thêm Lịch/Lời nhắc (EventKit, dùng từ Phase F), Thông báo (**hiện đúng trạng thái: bị từ chối với chữ ký tự tạo**),
   Toàn quyền đĩa (đo bằng thử đọc `~/Library/Safari/Bookmarks.plist`, không đoán).
5. Đo chốt Phase A: `audit-ui-tokens` TOTAL 0 · `probe-ax-dump` 40 trang × 2 ngôn ngữ, 0 rò · test ≥ 450 · idle CPU với
   HIDIdleTime ≥ 55 s/60 s · vmmap dirty ghi lại (chưa cần giảm).

### Phase B — Notch Surface (hồi sinh, không viết lại từ đầu)
- [x] **B1 (code, 2026-10-10)** `Core/Notch/` (máy trạng thái + layout + phiên kéo, thuần, 32 test, mutation 8/8 đỏ) +
  `NotchSurfaceController` + `NotchSurfaceView`; `NotchDropController` đã xoá. Hai khoá chết `dropTray.hoverEnabled` /
  `notchDropEnabled` **được nối thật** và có công tắc trên trang Khay thả. Phát hiện: pasteboard kéo-thả giữ cú kéo file cũ
  vĩnh viễn ⇒ `dragCarriesFiles()` cũ sai, thay bằng `NotchDragSession`. **Hành vi sống CHƯA đo** (màn hình khoá suốt lượt).
1. `NotchSurfaceController` (đổi tên từ `NotchDropController`, giữ monitor pair + `dragCarriesFiles`) + `NotchGeometry` thuần
   (test: notch thật từ `auxiliaryTop*Area`; Pill cho màn không notch; đa màn hình) + panel `SurfacePanel(.notch)`; 3 trạng thái
   thu gọn/peek/mở với `Motion.surface`. **Wire thật** `dropTray.hoverEnabled` và `dropTray.notchDropEnabled` (hover mở peek; kéo
   file vào vùng notch mở hub) — hoặc xoá khoá. Lắc giữ nguyên.
- [x] **B2a (2026-10-10)** `Core/Archive/ArchiveEngine` (thuần) + `ArchiveRunner` (Process, test tích hợp với công cụ thật);
  3 chỗ gọi ZIP chuyển sang. Phát hiện: `ditto` từ chối >1 nguồn nên **nén 2+ mục chưa bao giờ chạy**; `zip` bỏ sót tệp mà vẫn
  thoát 0; "Hỏi" đệ quy vô hạn; giải nén ghi đè im lặng. PDF/ảnh/AirDrop/TaskProgress còn lại (B2b–B2d).
- [x] **B2b (2026-10-10)** `Core/Pdf/` — hết ghi đè im lặng; rò ngôn ngữ dạng #7 + gate `audit-l10n-interpolations.py`.
- [x] **B2c (2026-10-10)** `Core/Image/` — chuyển định dạng (không có WebP: đo được máy không có encoder), giảm kích thước,
  tách nền Vision; gắn vào Thao tác Finder. Còn B2d: TaskProgress + hàng hành động trên notch + AirDrop.
- [x] **B2d (code, 2026-10-10)** hàng hành động trên hub notch (ZIP, gộp PDF, sang JPEG/PNG, tách nền, AirDrop) + `NotchTask`
  (tiến trình theo số tệp, huỷ được). **Chưa bấm thử sống; AirDrop từ panel không kích hoạt chưa kiểm chứng.**
2. Action hub: tách `CompressEngine`, `PdfEngine` ra khỏi view (thuần, test), thêm `BackgroundRemover`, `AirDropShare`,
   `ImageConverter` (ImageIO: HEIC→JPG/PNG/WebP nếu encoder có). `TaskProgress` thuần (0–100 %, huỷ được) hiện trên notch; kết quả
   cạnh file gốc + Reveal/Copy/Share. Mọi việc nặng `Task.detached`, UI không chặn (đo bằng tap latency).
- [x] **B3 (code, 2026-10-10)** `Core/Snap/SnapLayout` thuần (hình học snap thật được test, bỏ bản sao), chia ba + hai phần ba
  + tập trung, hàng bố cục khi kéo cửa sổ tới notch (`snapzones.notchRow`), ⌃⌥D/F/G. **Chưa kéo thử sống.**
3. Snap tại notch: `SnapZoneController` thêm vùng kích hoạt "đỉnh màn hình quanh notch khi đang kéo cửa sổ" → hàng bố cục; thêm
   `SnapTarget.leftThird/centerThird/rightThird/focus`.
- [x] **B4a (code, 2026-10-10)** thông báo sống: sạc/pin, mạng, Caps Lock, Bluetooth, cảnh báo → notch; hàng đợi gộp cùng loại;
  sự kiện hệ thống, không polling. **Còn B4b:** HUD âm lượng/độ sáng + hẹn giờ. **Chưa thử sống.**
4. Live activities: BT connect/battery (BatteryStore), sạc/pin yếu/đầy + Caps Lock + mất mạng (`AlertRules` thêm quy tắc, banner
   chuyển vào notch), hẹn giờ, HUD âm lượng/độ sáng *song song* hệ thống.
5. Trang Clipboard trên notch (deck của shelf) + @filter + ⌘-click stack + menu Transform/Dịch/Đi tới nguồn.
6. Now Playing: **probe trước** (nhạc đang phát, so MediaRemote vs AppleScript). Không probe xong không ship.
7. Cài đặt notch về trang Khay thả (đổi tên "Notch & Khay thả"): bật từng live activity, Pill cho màn ngoài, độ nhạy hover,
   ẩn khi quay màn hình.

### Phase C — Switcher ⌘-Tab
Q (AX `kAXCloseButtonAttribute` → press), H (`NSRunningApplication.hide`), Space (phóng thumbnail), lọc theo màn hình chứa con trỏ,
`` ` `` chuyển app↔cửa sổ (store đã gộp theo app; thêm lister theo cửa sổ), `Motion.overlayIn` 0.16 s, một reader cho
`excludedApps`. Trang `.windowPreview` phẳng theo A.3.

### Phase D — Clipboard chiều sâu
Thư viện Clipboard (hồi sinh `ClipboardTabView`, dọn `.clipboard`), board khoá (AES-GCM + Keychain), Transform thuần + test,
highlight code (xử lý trên máy), MCP server target (stdio), xuất `.xfinderclip` gộp cả board (mở rộng `SettingsTransfer`),
xem trước link **opt-in** (mạng).

### Phase E — Smart Selection
Lớp phát hiện vùng chọn qua AX (`kAXSelectedTextAttribute`, cần Trợ năng) + popup `SurfacePanel(.pointer)`; dịch (15+),
tiền tệ (opt-in mạng), đơn vị, múi giờ, ngày → sự kiện Lịch (EventKit).

### Phase F — Lớn, sau cùng
Chụp & chú thích studio · Lịch/lời nhắc trên notch + thẻ họp · theo dõi agent AI · Quit-on-close · Cleaning Mode / Uninstaller
(bắt buộc preview + chỉ Thùng rác).

### Phase G — Hiệu năng & phát hành 1.3
Quy dirty 48 MB về từng module (`vmmap -verbose`, `heap`), mục tiêu <30 MB khi tắt hết tính năng nền; idle 0 % đo đúng cách;
release tự ký như 1.2.0.

---

## 5. Tiêu chí nghiệm thu (đo được, không "trông ổn")

| Phase | Lệnh / probe | Ngưỡng |
|:--|:--|:--|
| A | `python3 scripts/audit-ui-tokens.py` | `TOTAL 0` |
| A | `probe-ax-dump` mọi trang, EN và VI | 0 dòng dấu trên EN ngoài allowlist |
| A | `grep -rn "SettingsCard(" XFinder/Views/Detail` | 0 |
| B | mở notch khi kéo file chạm vùng notch (mousedrag tool) | panel hiện trong ≤ 1 frame sau khi vào vùng; không mở khi kéo chữ |
| B | nén/OCR/PDF 1 file qua hub | % tiến trình đổi trên notch; kết quả cạnh file gốc; main thread không chặn (tap CPU ≤ 1 frame) |
| B | kéo cửa sổ lên notch → thả "Nửa trái" | khung = `SnapTarget.leftHalf.rect` ±1 pt (đo AX) |
| B/C | idle sau khi đóng notch/switcher | `ps -o time=` 60 s với HIDIdleTime ≥ 55 s: Δ ≤ 0.05 s |
| C | ⌘-Tab, Q, H, Space | cửa sổ đóng/ẩn thật (đo bằng CGWindowList), ảnh phóng hiện |
| D | MCP `tools/call clipboard_search` | trả đúng mục từ SQLite, mục mật khẩu không xuất hiện |
| G | `vmmap --summary` dirty, mọi tính năng nền tắt | < 30 MB |

---

## 6. Ràng buộc trung thực phải in lên UI (không giấu)

* Chữ ký tự tạo: không Notification Center, không iCloud/CloudKit, không App Store; Gatekeeper chặn lần đầu (đã đo `spctl rejected`).
* `MediaRemote` private; HUD hệ thống không tắt được bằng API công khai; Translation chỉ 15+; tỷ giá/xem trước link cần mạng → opt-in.
* Tách nền = người (Vision); OCR rơi dấu hỏi ở cỡ chữ nhỏ (đo `Thuỷ→Thuy`).
* Dirty memory hiện 48,4 MB — ghi vào README cho tới khi Phase G đo lại.

---

## 7. Quyết định đã chốt (chủ dự án, 2026-10-10)

1. **Đồng ý**: `SettingsCard` → `TileCard` chỉ cho lưới thẻ; mọi trang cài đặt phẳng 100 %. (`typealias SettingsCard = TileCard` tạm thời tới khi 12 trang xong.)
2. **Clipboard sống trong notch + shelf.** Không có trang sidebar riêng → `ClipboardTabView` (0 call site) và case `.clipboard` mồ côi bị **xoá** trong Phase A; deck của shelf là nơi duy nhất.
3. **Song song, probe-gated**: HUD của XFinder hiện cạnh HUD hệ thống; Now Playing chỉ ship sau probe với nhạc đang phát.
4. **Commit thẳng `main`, mỗi commit một việc, message bắt đầu bằng mã hạng mục** (`A1`, `A3-compress`, `B2`…) để đọc lại `git log` là thấy đang ở đâu; không PR (repo một người, PR chỉ thêm bước). Checklist §4 được tích dần trong file này.
