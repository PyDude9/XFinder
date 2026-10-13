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

## 3b. Đối chiếu lại với trang Tính năng OneNotch (2026-10-12, 50 mục, có kiểm chứng)

Nguồn: ảnh chụp trang "Tính năng" của OneNotch (50 mục) người dùng gửi. Cách làm: một agent chỉ-đọc gán trạng thái từng mục
theo code + plan (file:line), bốn agent khác đi bác từng dòng chưa "xong" — **0 bất đồng**. Bảng đầy đủ ở
`scratchpad/plan-reconcile/map/table.md` (phiên); dưới đây là phần làm thay đổi kế hoạch.

**Đã có (17)**: lịch sử clipboard · Copy Stack (⌘-bấm + ⌘V thay cho nhấn đúp ⌘C) · bảng & ghim · tìm `@` · dán khi bấm ·
xuất/nhập cài đặt · riêng tư clipboard · pin & sạc · Đang phát · mọi nguồn phát (MediaRemote) · Bluetooth · Caps Lock ·
mất mạng · hẹn giờ · chia cửa sổ ở notch · xử lý file ở notch · ẩn khi quay màn hình. Live-verify còn nợ ở các mục B4/B6
đã ghi trong CLAUDE.md.

**Việc nhanh (vừa với manager sẵn có, 0 % idle) → Phase D1, làm ngay sau D0c**:

| # | Mục | Dựa trên | Ghi chú |
|:--|:--|:--|:--|
| 3 | Kéo thẻ lên chip bảng để ghim vào bảng | chip bảng đã có; `addItemToPinboard` | menu chuột phải "Bảng ghim ▸" đã có từ D0b |
| 6 | Phím ⌘⌥C mở **khay nổi cũ** (panel thứ hai), ghim panel luôn mở | `ClipboardShelfController` còn nguyên | một hotkey nữa cho bề mặt sẵn có |
| 7 | Nhận diện `rgb()` / `hsl()` ngoài `#hex` | `ClipboardClassifier.color(from:)` | parser thuần + test |
| 9 | Cửa sổ sửa text của một mục (sửa rồi copy lại) | `ClipboardTransform` đã có 17 phép | sheet mỏng |
| 14 | Nút "Tạm dừng ghi clipboard" (một công tắc, một reader) | monitor có `wakeAndCheck` | nay chỉ có bỏ-qua-app |
| 16 | Chọn âm khi copy | `ClipboardSounds` | một khoá + picker |
| 36 | Phát âm văn bản (TTS on-device, `AVSpeechSynthesizer`) | menu chuột phải thẻ | không mạng |
| 43 | Vuốt hai ngón đổi trang / cuộn ngang trên hub | monitor `scrollWheel` chỉ khi hub mở | 0 % idle |
| 44 | Bật/tắt + sắp xếp các trang trên notch | `Page` + một khoá thứ tự | nay bật/tắt riêng từng trang |
| 47 | Màu nhấn tuỳ chọn cho bề mặt notch | `XFinderTokens` | không làm "Liquid Glass" giả |

**Vừa (trang/card mới, timer theo nhu cầu) → xếp vào D/E/F sẵn có**: #4 Thư viện Clipboard (D, đã có) · #12 xuất
`.xfinderclip` kèm media (D, đã có) · #13 tô màu code on-device (D, đã có) · #11 iCloud bằng
`NSUbiquitousKeyValueStore` **cần entitlement + kiểm thật trước khi gọi là có** (nay `isAvailable` báo chưa cấu hình) · #20 nút
player tuỳ biến (**probe mã `MRMediaRemoteSendCommand` shuffle/repeat trước**) · #26 Lịch & lời nhắc trên notch (F, EventKit) ·
#35 từ điển ✅ 2026-10-13 (dòng "Định nghĩa" trên huy hiệu Chọn văn bản thông minh; `DCSCopyTextDefinition` đo 1–73 ms, có cả từ điển Việt, nil cho từ không có) · #39 hiện trên nhiều
màn hình cùng lúc (nay một màn một lúc; notch ảo trên màn không notch đã có từ D0c).

**Tham vọng (target/quyền/API riêng) → F, mỗi cái phải có probe trước**: #21 sóng nhạc thời gian thực ✅ 2026-10-13 (`CATapDescription`
process tap, macOS 14.2+, cần quyền Ghi âm thanh hệ thống — kể cả tap theo process; tap gom player + mọi process macOS coi player chịu trách nhiệm, vì âm thanh Chrome ra từ helper, Safari từ WebKit.GPU; ~3 % CPU khi sóng đang hiện) · #29 dịch nhanh (E; `translationd` từ chối binary ad-hoc — đo lại với chữ ký XFinder Dev) ·
#30 chụp & chú thích (F) · #33 nhắc họp ✅ 2026-10-13 (live activity có nút Tham gia / Hoãn 5 phút / Mở Lịch; một Timer theo giờ thật cho lần báo kế tiếp; khoá mỗi lần lặp theo id+giờ bắt đầu) · #37 hạn mức Claude/Codex ✅ 2026-10-13 (Codex: % do chính nó ghi trong `~/.codex/sessions`; Claude Code không ghi % ra máy ⇒ chỉ token, nói rõ; gộp dòng trùng vì 5 882 dòng = 2 256 tin nhắn) · #38 thay thế vùng chọn (E, Smart Selection) · #40 theo dõi agent (F) · #41 duyệt yêu cầu agent trên notch (F, cần hook
quyền của Claude Code — chưa rõ cơ chế) · #42 Clipboard MCP (D) · #48 19 ngôn ngữ (kiến trúc L10n hai ngôn ngữ — chỉ khi có
người dịch thật).

**Không làm, lý do đo được**: #8 xem trước link chỉ **opt-in mạng** như D đã ghi · #15 lời bài hát (mạng bên thứ ba) · #22 player
màn hình khoá (private) · #25 thay HUD hệ thống (chỉ song song; OSDUIHelper private) · #34 engine dịch cloud (chỉ Apple on-device +
khoá API tự nhập) · #45 ẩn icon app khác (chết trên macOS 27, đã đo) · #49 tự cập nhật nền (`UpdateChecker` do người dùng bấm là đủ
cho MIT, không telemetry) · #50 Free/Pro.

**D1 — tiến độ**: nhóm 1 ✅ 2026-10-12 (#7 màu rgb/hsl · #14 tạm dừng ghi · #16 âm copy · #36 phát âm · #9 sửa văn bản ·
#6 ⌘⌥C + ghim khay · #3 kéo thẻ lên chip bảng — đo: pasteboard thật ghi `color` cho rgb()/hsl(), tạm dừng không ghi dòng
nào, footer notch báo; chưa đo tay: phát âm, editor, ⌘⌥C, kéo-thả). Nhóm 2 ✅ 2026-10-12 (#44 `notch.pages` bật/tắt + sắp
xếp tab, đo thứ tự tab qua AX sau relaunch · #43 vuốt hai ngón trên dải tab đổi trang, chưa đo tay · #47 `notch.accent`
7 màu, chưa đo mắt) + **bo góc hub** theo yêu cầu: bán kính 36 liên tục, fillet lõm 12 pt vào mép trên, hub đo 776×232.
**D1 xong 10/10.**

**D2 ✅ 2026-10-12** — ba mục "vừa" của §3b: #13 tô màu code on-device (`CodeHighlighter` thuần, 15 test; thẻ notch + thẻ shelf) ·
#12 xuất/nhập `.xfinderclip` kèm ảnh + bảng (`ClipExport` thuần 8 test + `ClipTransfer` I/O, nút ở Cài đặt Clipboard; nhập không
ghi đè, mục trình quản lý mật khẩu không xuất) · #42 Clipboard MCP (`XFinder --mcp`, stdio JSON-RPC, 3 tool, `MCPProtocol` thuần
11 test; **tắt mặc định**, đoạn cấu hình để dán vào Claude Code). Kèm yêu cầu riêng của chủ dự án: **⌘⌥C tắt mặc định** sau công
tắc `clipboard.shelfHotkey`. Đo: server trả lời đúng qua stdio trên binary đã build (tắt ⇒ −32000, bật ⇒ 3 dòng thật từ SQLite,
`clipboard_get` trả nguyên văn), `zip`/`tar` với đuôi `.xfinderclip` đo được, trang cài đặt EN 0 chữ Việt qua AX. **Chưa đo tay**:
bấm Xuất/Nhập qua NSSavePanel, màu token bằng mắt, MCP từ Claude Code thật.

**D3 ✅ 2026-10-12 — Thư viện Clipboard, wireframe B** (chủ dự án chọn): hàng sidebar "Thư viện Clipboard" ở CÔNG CỤ,
rail lọc 180 pt (Tất cả · Đã ghim · loại · app · bảng, có số đếm khớp SQLite), lưới `ClipboardCardView`, inspector 320 pt trượt
từ phải, bàn phím ←→↑↓ ↩ ⇧↩ Space ⌘⌫ Esc ⌘F. Store riêng đọc **mọi** dòng SQLite (1 846), không đụng cap 200 của notch.
Ba file viết song song theo hợp đồng (luật thuần 35 test · store · view), review đối kháng 35 agent: 11 xác nhận → sửa hết
trừ 1 chấp nhận (reload cả bảng mỗi lần copy), 2 chia phiếu → sửa, 2 bác. Chưa đo tay: chọn thẻ/inspector/phím/dán vào app
trước (thẻ là `.onTapGesture`, không bấm được qua AX; người dùng đang ở bàn phím nên không bắn sự kiện giả).

**D4a ✅ 2026-10-12 — Bảng khoá (B).** Khoá riêng P-256 trong **Secure Enclave** (`.privateKeyUsage + .userPresence`), khoá công khai
mã hoá clip qua HPKE/AES-GCM-256 không cần hỏi; dòng SQLite chỉ còn loại/thời gian/app/cờ, nội dung + tệp payload/thumbnail vào
`Clipboard/Locked/<id>.{env,payload,thumb}` (0600/0700). Mở từng thẻ trong Thư viện (Touch ID mỗi lần), giữ trong bộ nhớ, quên khi rời
trang hoặc khoá máy; notch/shelf hiện placeholder và mở Thư viện. "Khoá bảng này…" có hộp thoại nói thật bốn ý; "Gỡ khoá (giải mã lại)"
một lần Touch ID. Hàng rào: MCP và xuất `.xfinderclip` bỏ dòng khoá lẫn bảng khoá. Luật thuần `BoardLock` 20 test; harness khoá
Secure Enclave thật 15/15 (không còn chữ rõ trong tệp mã hoá). Ba lỗi an toàn dữ liệu bắt được khi đọc code agent (xem CLAUDE.md "D4").
**Chưa đo tay:** bước mở bằng Touch ID, huỷ Touch ID, mọi click. **Chưa làm (D4b):** xem trước link opt-in.

**Thứ tự tiếp theo của plan**: D0c ✅ → D1 ✅ → D2 ✅ → D3 ✅ → D4a ✅ → §3e N1–N8 + D4b ✅ (2026-10-13, dựng + test, **chưa đo live**) →
**đo live cả đợt** (probe click-xuyên → cài → e2e N1/N3 → AX → CPU) → N5b (badge trên vùng chọn) → E → F → G.

### 3d. Brief D4 — Bảng khoá (U1/U2, 2026-10-12; **đã chọn B — hỏi Touch ID từng thẻ; thẻ khoá ở notch/shelf = placeholder 🔒**)

**U1 — hiện trạng.** Bảng (`Pinboard`) là danh sách `itemIDs` trong UserDefaults; nội dung clip nằm **rõ chữ** trong
`xfinder.db` (snippet 200 ký tự) và các tệp payload/thumbnail trong `Application Support/XFinder/Clipboard/`. Đã có
`clipboard.touchIDLock` (hỏi Touch ID khi **mở** shelf/notch — khoá bề mặt, không khoá dữ liệu), `OwnWriteMark`, bộ lọc trình
quản lý mật khẩu, MCP (chỉ đọc) và xuất `.xfinderclip` (cả hai đọc thẳng SQLite). `LAContext`/`SecAccessControl` chưa dùng ở đâu
ngoài Touch ID của shelf. `CryptoKit` có sẵn (macOS 14).

**U2 — việc chính.** *"Tôi có vài clip nhạy cảm (token, OTP, số tài khoản, ghi chú riêng) muốn giữ trong một bảng mà người nhìn
qua vai, ai cầm máy đang mở khoá, hay ai đọc được tệp `xfinder.db` đều không thấy chữ."* Cơ chế đề xuất: mỗi bảng khoá có một khoá
AES-256-GCM sinh ngẫu nhiên, lưu Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` + `SecAccessControl .userPresence` ⇒
đọc khoá cần Touch ID/mật khẩu máy); clip chuyển vào bảng khoá thì snippet + payload + thumbnail được mã hoá tại chỗ, dòng SQLite
giữ placeholder; mở khoá bảng giải mã **trong bộ nhớ** một phiên 5 phút rồi quên; **MCP và xuất `.xfinderclip` không bao giờ trả
mục trong bảng khoá**; notch/shelf hiện thẻ khoá (không xem trước, không Quick Look) cho tới khi mở. **Nói thật trên trang:** khoá
sống trong Keychain đăng nhập — bảo vệ khỏi nhìn trộm, khỏi tệp DB bị sao chép, khỏi MCP/xuất; **không** bảo vệ trước ai đang có
phiên đã mở khoá *và* vượt được Touch ID. Gỡ khoá bảng = giải mã lại tất cả rồi xoá khoá.

**Đo trước khi dựng (2026-10-12, macOS 27):** CryptoKit HPKE chỉ có `P256_SHA256_AES_GCM_256` và `Curve25519_SHA256_ChachaPoly`
(không có Curve25519 + AES-GCM) → dùng P-256 + AES-GCM-256; `SecureEnclave.isAvailable = true`, khoá P-256 trong Secure Enclave dùng
được làm recipient HPKE và khôi phục từ `dataRepresentation` 284 byte; `SecAccessControl(.privateKeyUsage, .userPresence)` tạo được;
Touch ID khả dụng. ⇒ **Khoá riêng nằm trong Secure Enclave**, mỗi lần dùng phải qua Touch ID; khoá công khai (65 byte) mã hoá clip mới
thêm vào bảng mà không cần hỏi (HPKE một chiều). Hệ quả phải nói trên UI: khoá gắn với chính Secure Enclave của máy này — Mac hỏng =
mất vĩnh viễn; xuất `.xfinderclip` và MCP không bao giờ chứa clip khoá.

**Quyết định đã chốt (wireframe):** cách **mở khoá** khi đang xem — A. một nút "Mở khoá bảng" ở đầu lưới, mở cả bảng
5 phút (khuyên dùng) · B. bấm từng thẻ, hỏi Touch ID từng lần (an toàn hơn, phiền hơn) · C. một công tắc "Mở khoá" chung ở
hàng sidebar, mở mọi bảng khoá cùng lúc. Và: thẻ khoá trong **notch/shelf** hiện placeholder (đề xuất) hay ẩn hẳn khỏi hai bề mặt đó?


### 3c. Brief D3 — Thư viện Clipboard (U1/U2, 2026-10-12; **đã chọn B, đã dựng**)

**U1 — hiện trạng đo được.** Sidebar **không có** trang nội dung clipboard (quyết định 2026-10-10: nội dung ở ⌘⇧V/notch);
`ClipboardTabView` đã bị xoá, `.clipboard` không còn trong enum. Hai bề mặt hiện có đều là *bề mặt nhanh*: notch = 4 thẻ,
shelf = một hàng ngang + tìm. Lịch sử thật trên máy này: 1 846 bản ghi (text 1 020 · ảnh 295 · link 209 · markdown 190 · code 73 ·
file 51 · màu 8), cap đang là 200 ⇒ **~1 600 bản ghi không có bề mặt nào với tới được**. Component có sẵn để tái dùng:
`ClipboardCardView` (thẻ shelf, đủ loại), `NotchClipCardView`, `ClipboardQuickLook`, `HighlightedCodeText`, `PageHeader`/
`SectionHeader`/`XFinderTokens`, bộ lọc `ClipboardFilterToken` (`@image @link …`), `ClipboardTransform` (17 phép), `ClipTransfer`.

**U2 — việc chính.** *"Tôi cần tìm lại một clip cũ — ngoài 4 thẻ ở notch — lọc theo loại / app / bảng, xem kỹ, rồi dán, ghim
vào bảng, hoặc dọn."* Thứ cần thấy ngay: **ô tìm**, **bộ lọc** (loại · app nguồn · bảng · thời gian), **lưới thẻ** (ảnh thấy
ảnh, code có màu), **chi tiết một mục** (toàn văn / ảnh gốc, meta: app, lúc, kích thước; hành động: Dán · Sao chép · Ghim ·
Bảng ▸ · Biến đổi ▸ · Xoá). Việc KHÔNG thuộc trang này (đã có chỗ): cài đặt (Cài đặt Clipboard), dán nhanh (notch/shelf),
xuất/nhập (nút ở Cài đặt).

**Ràng buộc.** Cap 200 là của notch — thư viện có **store riêng** nạp toàn bộ bảng một lần (`fetchAllClipboardRecords`, 1 846
dòng = vài ms trên actor) rồi lọc/sắp xếp trong bộ nhớ bằng luật thuần có test; "trang" chỉ là cửa sổ hiển thị 60 thẻ.
(Brief ban đầu định phân trang từ SQLite; đổi vì facet đếm đúng cần cả tập, và 1 846 dòng không đáng một đường paging thứ hai.) Không timer. Mọi chuỗi
qua `L10n.t`. Hành động Dán cần app đích ⇒ từ trang chính chỉ "Sao chép" + "Dán vào app trước đó" (ẩn cửa sổ rồi ⌘V, như
shelf). Quyết định cần chủ dự án chốt khi chọn wireframe: **đưa lại một hàng sidebar "Clipboard" ở CÔNG CỤ** (đảo quyết định
2026-10-10) hay mở thư viện từ nút "Mở thư viện…" trong notch/shelf + Cài đặt (không hàng sidebar).

**U3 — ba wireframe** (`scratchpad/uiux/lib/wireframe.html?v=a|b|c`, ảnh gửi kèm):
A. **Ba cột** (rail lọc · lưới thẻ · inspector cố định) — kiểu Paste/OneNotch; thấy nhiều nhất, cần cửa sổ ≥ 1 100 pt.
B. **Hai cột + inspector trượt** (rail lọc · lưới; chọn một thẻ thì inspector trượt từ phải, Esc đóng) — vừa cửa sổ 900 pt.
C. **Một cột, chip lọc trên** (như trang notch phóng to: chip loại/app/bảng + lưới; chi tiết là sheet) — ít code nhất, tái dùng
`NotchClipboardView`. **Khuyên dùng: B** — cùng lưới với A, không ép bề rộng, inspector không chiếm chỗ khi chỉ lướt.


---

### 3e. Đối chiếu theo bằng chứng đo trên bundle OneNotch 2.0.5 (2026-10-13) — thay §3/§3b ở chỗ mâu thuẫn

Nguồn: `docs/ONENOTCH_EVIDENCE_2026-10-13.md` (đo trực tiếp: plist, entitlements, chuỗi UI 2 471 mục, class name, defaults,
SQLite, CGWindowList, AX, CPU) + `docs/ONENOTCH_WEB_RESEARCH_2026-10-13.md` (web). **OneNotch là mã đóng** (không có repo; chuỗi
"open-source" trong app không kiểm chứng được) ⇒ chỉ học *cơ chế đo được*, không chép gì.

Điều bằng chứng **sửa lại** trong kế hoạch cũ:

| Mục cũ | Bằng chứng mới | Kế hoạch mới |
|:--|:--|:--|
| §3b #37/#40/#41 "theo dõi agent — chưa rõ cơ chế" | Cơ chế đo được (§7 evidence): hook Claude Code trong `~/.claude/settings.json` + script zsh ghi JSONL + jq; PermissionRequest chặn chờ file quyết định; không API riêng, không quyền | **N3** làm được bằng file + hook công khai |
| §3 "HUD: không thể tắt HUD hệ thống" | OneNotch *thay* HUD bằng cách nuốt phím media (class `MediaKeyInterceptor`, cần AX) — suy ra từ tên class, chưa thấy tap | âm lượng: probe nuốt phím + CoreAudio; độ sáng vẫn không có đường ghi public (đã đo) ⇒ giữ song song cho độ sáng |
| §3 "Now Playing probe-gated" | Cùng adapter perl (B6 đã làm); họ thêm `SetElapsedTime`, `SetShuffleMode`, `SetRepeatMode` | seek/shuffle/repeat là probe nhỏ cùng cơ chế (N8) |
| §3 "Convert → WebP nếu encoder có" | Họ **biên dịch libwebp vào binary** (`WebPEncoder.swift`, `InitVP8Encoder`) | WebP = vendor libwebp (BSD) — hoãn, không phải "không có" |
| §3b #45 ẩn icon thanh menu | changelog 2.0.3: *"menu bar icon hiding disabled on macOS 27"* | giữ explainer, đã được bên thứ ba xác nhận |
| §3b "#22 player màn hình khoá (private)" | SkyLight (`SLSSpaceCreate`, `SLSSetLoginwindowConnection`), LoginUIKit | giữ: không làm |
| Khoá bảng | Họ: passcode + AES-GCM + digest; XFinder D4a: Secure Enclave + HPKE | XFinder đã vượt; giữ |
| Hồ sơ tài nguyên | OneNotch 168 MB + 48 MB helper, ≈4.9 % CPU "idle" | **không** chạy theo; mỗi mục N* phải giữ 0 % idle khi tắt |

**Khác biệt kiến trúc lớn nhất đo được:** panel notch của OneNotch **cố định 700×745 pt** (poll 20 s không đổi 1 px), level
`mainMenu + 3`; nội dung animate bên trong. XFinder `render()` đổi frame panel theo trạng thái (grow / shrink-sau-0.32 s /
union) — chính nguồn của lỗi "giật" D0c phải vá. Tiền đề phải đo trước khi đổi: click trên vùng **alpha 0** của panel có xuyên
xuống cửa sổ dưới không (`NSWindow.windowNumber(at:)`).

**Thứ tự dựng mới (thay cho "D4b → E → F → G"):**

| # | Việc | Dựa trên | Cổng đo |
|:--|:--|:--|:--|
| **N1** | Một panel notch cố định (max của mọi trạng thái ở notch), bỏ grow/shrink/union; tray tại con trỏ giữ nguyên | `NotchSurfaceLayout.panelFrame`, `render()` | CGWindowList: frame không đổi qua mọi trạng thái; click xuyên vùng trong suốt; test "mọi state ⊆ panelFrame" + mutation |
| **N2** | "Mở khi hover" = trang cuối · **theo hoạt động** (nhạc → Đang phát, agent chạy → Agent, có file → Khay) · clipboard · khay | thay `notch.clipboardOnHover` bằng một picker (một khoá, một reader) | FeatureKeyDefaultsTests + test luật thuần |
| **N3** | Trang **Agent AI** trên notch: cài hook Claude Code (có hỏi, nhãn "Managed by XFinder"), đọc JSONL, danh sách session (đang chạy tool / chờ nhập / **chờ duyệt quyền → Cho phép / Từ chối trên notch**), mở đúng terminal, tiêu thụ token "ước tính" | cơ chế §7 evidence; file + `DispatchSource` vnode; luật thuần `AgentSessions` | harness: bơm JSONL giả → trạng thái đúng; e2e với chính Claude Code này; không bao giờ tự trả lời quyền |
| **N4** | Trang Lịch & Lời nhắc ("Glance"): hôm nay + dải tuần + "Tiếp theo", thêm sự kiện, link họp | EventKit (quyền Lịch/Lời nhắc vào tab Quyền) | AX dump trang; không mạng |
| **N5** | Nút dịch khi bôi đen (badge AX) + ⇧⌘G | `AXSelectedText`, Translation (macOS 15 gate) | **probe `translationd` với chữ ký XFinder Dev trước**; thất bại ⇒ chỉ ⇧⌘G mở Dịch của Apple |
| **N6** | File actions: Resize · To PDF · OCR trên file thả · "giữ để chọn biến thể" | `ImageRunner`, PDFKit, `ScreenTextRecognizer` | integration test như B2c |
| **N7** | Onboarding 4 bước + What's New (tĩnh) | `lastSeenWhatsNewVersion` | AX dump |
| **N8** | Now Playing: seek, shuffle, repeat | `MRMediaRemoteSetElapsedTime/SetShuffleMode/SetRepeatMode` qua cùng đường dlsym | probe với publisher im lặng như B6 |
| — | D4b (xem trước link opt-in) | giữ, xếp sau N3 | — |

**Tiến độ (2026-10-13):** **N1 ✅ dựng + test** — `panelSize/panelFrame`, `render()` một frame mỗi anchor, hit-test và drop theo
`drawnFrame`; 28/28 mutation notch RED (M27/M28 mới). **N1b (07:14–07:25):** probe click-xuyên đo được khi màn thức và báo **BLOCKS CLICKS** — nguyên nhân là chính dòng `ignoresMouseEvents = false` trong `SurfacePanel(.notch)`: chưa từng gán ⇒ vùng alpha 0 cho click lọt xuống; gán `false` (trước/sau order-front, true→false) ⇒ cả frame chặn; thuộc tính đọc ra `false` ở cả hai. Panel cố định 700×745 của OneNotch đo bằng cùng phép thử: thân notch trúng OneNotch, vùng trong suốt trúng cửa sổ bên dưới. Đã bỏ dòng gán, gate `SurfacePanelHitTestTests` (mutation tiêm lại dòng gán ⇒ đỏ), 793/0; đã cài 07:25. **Chưa đo trên panel thật của app đã cài**: probe e2e đầu tiên thiếu `NSApplication` nên trả "none" cho cả hai điểm (PASS giả, đã sửa thành INVALID); người dùng thoát XFinder lúc 07:29 trước khi đo lại. **Đo lại 07:56–08:25 trên app đã cài: N1 4/4** (thu gọn: click xuống cửa sổ dưới; hub: điểm vẽ trúng XFinder layer 25, điểm trong suốt xuống cửa sổ dưới; frame cố định qua 3 trạng thái) · **N3 5/5** · idle 0,03 s/60 s. Cùng đợt tìm ra **trang Thư viện Clipboard phình 886 MB** (màu nhấn = TIFF icon 74 MB/app; thẻ file đọc nguyên .mp4 42 MB mỗi lần render) — sửa `9855a97` + `142e334`, còn 78,5 MB đỉnh. **N3 ✅ dựng + test** — hook zsh (đo trong scratchpad 4/4), `AgentEvents`/`AgentSessionRules`/
`AgentHookInstaller` 17 test, `AgentSessionMonitor`, trang Agent AI trên hub + mục cài hook ở Notch & Khay thả, catalog + gate;
schema hook đối chiếu tài liệu chính thức (`decision.behavior`, exit 2 bị bỏ qua, `statusMessage`/`timeout` thật); **chưa đo
live** (e2e `scratchpad/n3/e2e-agents.sh` chờ màn thức; phiên Claude Code thật chỉ sau khi người dùng bấm Cài hook).

**N2 ✅ dựng + test** — picker `notch.hoverOpens` (7 lựa chọn) thay Bool `notch.clipboardOnHover` (migrate sang Theo hoạt động),
`NotchHoverOpen` thuần 10 test, M29/M30 mới; chưa đo live.

**N6 ✅ dựng + test** — Sang PDF (`PDFAssembler`, ảnh + PDF → một PDF cạnh tệp đầu), OCR tệp ảnh (`ImageTextOCR`, .txt cạnh ảnh
+ clipboard), Thu nhỏ ảnh với 5 preset qua press-and-hold (`Menu(primaryAction:)`); 8 test tích hợp trên ảnh sinh, M31; WebP vẫn
hoãn (cần vendor libwebp). Chưa đo live (click trên hub).

**N4 ✅ dựng + test** — trang Lịch (`GlanceRules` thuần 8 test + `VietnameseLunar` theo Hồ Ngọc Đức, ghim Tết 2024–2026,
Trung thu 2026, nhuận 2025, lệch 1985), `CalendarGlanceMonitor` EventKit (fetch ±5 ngày, ticker 60 s chỉ khi trang mở), quyền
Lịch/Lời nhắc vào tab Quyền; chưa đo live.

**N8 ✅ dựng + đo cơ chế** — seek (slider), shuffle/repeat (menu 3 chế độ, không đọc được trạng thái nên không giả vờ hiện);
probe publisher đo đúng số: SetShuffleMode 1/2/3 → off/collections/items, SetRepeatMode 1/2/3 → off/one/all; M32.

**N5 probe ✅ (chưa dựng)** — `LanguageAvailability.status(en→vi)` trả `installed` sau 8.48 s, 47 ngôn ngữ, giống nhau cho bản ad-hoc
và bản ký XFinder Dev; "treo" ở B5 là do probe bị giết trước 8.5 s. Dịch thật chỉ có qua `.translationTask`/`.translationPresentation`
(SwiftUI, macOS 15) ⇒ badge dịch phải host trong panel SwiftUI, gate `#available(macOS 15, *)`.

**N7 ✅ dựng + test** — Có gì mới một lần mỗi phiên bản cho người cũ (`WhatsNewRules` thuần 2 test, cửa sổ riêng); **tour đã có sẵn**
(`Onboarding` c436b80: chọn preset + xin đúng quyền) — dòng "Chưa làm: onboarding" ở trên là cũ. Chưa đo live.

**N5a ✅ dựng + test** — ⇧⌘G (Carbon, chữ ký riêng) đọc `AXSelectedText` → panel với `.translationPresentation` của Apple
(macOS 15+); `TranslateSelectionRules` thuần 2 test; khoá `translate.hotkeyEnabled` mặc định tắt, mục trên trang Giọng nói + hub.
Badge-trên-vùng-chọn (AXObserver theo app) chưa làm. Chưa đo live.

**D4b ✅ dựng + test** — xem trước link opt-in (`LinkPreviewRules` thuần 5 test + D32, `LinkPreviewFetcher` qua `LPMetadataProvider`,
ảnh ≤ 480 px vào `Clipboard/LinkPreviews/`, metadata `linkTitle/linkImage/linkFetched`), thẻ shelf/notch/Thư viện hiện tiêu đề + ảnh;
chỉ host công cộng, không localhost/mạng nội bộ; mặc định tắt. Chưa đo live qua app.

**Không làm (bằng chứng, không phải sở thích):** lock screen (SkyLight/LoginUIKit private) · lời bài hát/visualizer (mạng
bên thứ ba, mic) · iCloud (CloudKit cần tài khoản trả phí) · Sentry/TelemetryDeck/Sparkle tự tải (0 telemetry) · Pro/license ·
camera "Mirror" (câu job: không ai tới notch để soi gương) · thay HUD độ sáng (không có đường ghi public).

### 3f. Đợt E — Chọn văn bản thông minh (kế hoạch sau đối chiếu, 2026-10-13)

**Câu job:** *"Tôi vừa bôi đen một đoạn chữ ở app khác — tôi muốn dịch, đổi đơn vị, đổi múi giờ, tính, hoặc đưa ngày đó vào
Lịch mà không rời app."* OneNotch (bằng chứng, không chép): huy hiệu tự hiện khi bôi đen (`SelectionTranslateMonitor`,
`TranslateBadgeController`, cần AX), cài đặt **độ dài tối thiểu** + **danh sách app loại trừ** (Localizable 505/207/1091),
⇧⌘G riêng, badge `smart-select` + `currency-conversion` trong `seenFeatureBadges`; quy đổi đơn vị/tiền **chỉ có trong quảng cáo**,
không một chuỗi UI nào — nên chỉ học phần đo được.

**Đo trước khi thiết kế (probe thụ động `scratchpad/e-probe/selwatch`, 10 phút, chỉ ghi độ dài, không ghi chữ):**

| Sự thật | Số đo | Hệ quả thiết kế |
|:--|:--|:--|
| `AXObserverAddNotification(kAXSelectedTextChangedNotification)` | **= 0 (thành công) ở mọi app**, kể cả Chrome và Claude (Electron) — **không** cần ghi `AXManualAccessibility` | không đụng thuộc tính của app khác |
| Tần suất | 110 lần Chrome, 46 Claude trong 10 phút; **mỗi bước kéo chuột một lần** (độ dài 1 → 11 → 14 → 17 → 20…) | phải chờ vùng chọn **đứng yên** + **nhả chuột** |
| `kAXBoundsForRangeParameterizedAttribute` | Chrome **94/94**, Claude **42/42** trả `0,1117 0×0` (1117 = chiều cao màn hình chính tính bằng point ⇒ "không có dữ liệu") | **neo huy hiệu vào điểm nhả chuột**, chỉ dùng khung AX khi không suy biến |
| Safari | 21 thông báo, `AXSelectedText` **luôn rỗng** | WebKit dùng text-marker — probe `AXSelectedTextMarkerRange` + `AXStringForTextMarkerRange`; nếu đúng thì **N5a ⇧⌘G cũng mù trong Safari** và phải sửa chung |
| Bàn phím (⇧+mũi tên) | không có điểm con trỏ đáng tin | huy hiệu chỉ hiện cho vùng chọn bằng chuột; bàn phím dùng ⇧⌘G |

**Hạng mục — mỗi mục một commit, có test + mutation + đo:**

| # | Việc | File (thuần ⇒ symlink vào Tests) | Cổng |
|:--|:--|:--|:--|
| **E1** | Luật thuần: phân loại vùng chọn → hành động (dịch · đơn vị · múi giờ · ngày → Lịch · phép tính · tiền tệ nếu bật), máy trạng thái "đứng yên + nhả chuột", cổng độ dài/app loại trừ, chọn điểm neo (khung AX suy biến ⇒ điểm chuột; lật toạ độ AX→AppKit) | `Core/SmartSelect/SmartSelectionRules.swift` | test + mutation; tái dùng `Calculator` cho phép tính |
| **E2** | Đổi đơn vị (Foundation `Measurement`): độ dài, khối lượng, nhiệt độ, thể tích, tốc độ; mét ↔ Anh/Mỹ; dấu phẩy thập phân tiếng Việt (`1,5 km`) vs dấu phân nghìn (`1,500 mi`) theo luật có test | `Core/SmartSelect/UnitConversion.swift` | test bảng giá trị chuẩn, mutation |
| **E3** | Đổi múi giờ: `3pm PST`, `15:00 UTC`, `9:30 am EST` → giờ máy; bảng viết tắt **không mơ hồ** (IST/CST… bị loại, nói rõ), DST tính theo ngày tham chiếu | `Core/SmartSelect/TimeZoneConversion.swift` | test với ngày cố định qua mốc DST |
| **E4** | `SelectionWatcher`: một `AXObserver` cho app phía trước (đổi khi kích hoạt app khác), cặp monitor nhả chuột global+local **chỉ khi bật**, một hẹn giờ một-lần 300 ms khi vùng chọn đang đổi; tắt ⇒ không observer, không monitor; loại XFinder + app trong danh sách; đường text-marker cho WebKit nếu probe xác nhận | `Core/SmartSelect/SelectionWatcher.swift` | idle 60 s Δ ≤ 0.05 s khi bật; FeatureCatalog `.smartSelect` (Trợ năng); FeatureKeyDefaults/Contract |
| **E5** | Huy hiệu + bảng kết quả: `SurfacePanel` dựng một lần, viên thuốc nhỏ cạnh điểm nhả chuột (kẹp trong màn hình chứa điểm đó), ẩn khi bấm chỗ khác / đổi app / Esc / 6 s; bấm ⇒ bảng: kết quả quy đổi có nút Sao chép, Dịch ⇒ panel N5a (macOS 15+), Thêm vào Lịch ⇒ EventKit sau khi xác nhận. Trang **Chọn văn bản thông minh** (CÔNG CỤ): công tắc, độ dài tối thiểu, app loại trừ, và công tắc ⇧⌘G **chuyển** từ trang Giọng nói sang (một khoá, một control) | `Views/SmartSelect*.swift`, `Views/Detail/SmartSelectDetailView.swift` | AX dump EN/VI 0 rò rỉ; L10n 6 gate |
| **E6** | Tiền tệ **opt-in mạng**: tỷ giá ECB hằng ngày (`eurofxref-daily.xml`, không khoá API), cache 12 h, hiện "≈" + ngày tỷ giá; tắt mặc định; nhãn nói rõ gửi gì đi đâu | `Core/SmartSelect/CurrencyRates.swift` (luật thuần + fetcher) | test parser trên XML mẫu; không request khi tắt |
| **E7** | Đo live: e2e trên một tài liệu TextEdit do harness tạo (đặt vùng chọn bằng thuộc tính AX của chính tài liệu đó, không gửi phím/chuột) ⇒ huy hiệu hiện (CGWindowList + AX dump) ⇒ bảng đúng kết quả; probe Safari text-marker khi người dùng bôi đen | scratchpad harness | kết quả ghi vào commit |

**Tiến độ đợt E (2026-10-13):** **E0 ✅** (`2ce9036`) ⌘K/Tìm nhanh không còn abort khi gõ `1+` — `NSExpression(format:)` ném
NSException trên `1+`, `(1+2`, `1..2+3` (đều qua regex của `Calculator`) và trả `1/0 = 0`; `SafeArithmetic` thay thế, gate cấm
`NSExpression(format:` trong toàn app. **E1–E3 ✅** (`72f83a2`) luật thuần + đổi đơn vị (hệ số CHÍNH XÁC — `Measurement` làm tròn
6 chữ số: km/h, lb, gal) + múi giờ (bảng riêng: `TimeZone(abbreviation:)` cho EST = −4 tháng 10, CST → Chicago); `SecretApps` gom
danh sách app mật khẩu (bản của MCP đã lệch). **E4–E5 ✅** (`af9e5c8`) watcher AX + huy hiệu + panel + trang "Chọn văn bản thông
minh"; công tắc ⇧⌘G chuyển từ trang Giọng nói sang. **E7 ✅ đo live 13/13** trên app đã cài (harness `.app` riêng, chọn vùng bằng
API của chính nó, MỘT nhả chuột tại vị trí con trỏ khi người dùng rời tay ≥ 20 s): huy hiệu hiện cho `5 km`/`3pm PST`/`12 * (3 + 4)`,
panel đọc qua AX đúng `5 km ≈ 3.11 mi`, `15:00 PST (UTC−8) = …` + ghi chú `Los Angeles is on UTC−7 right now.`, `= 84`; không nhả
chuột ⇒ không huy hiệu; app bị loại trừ ⇒ không huy hiệu; neo theo khung AX thật. **Lần chạy đầu 2/7** — nó tìm ra lỗi thật: app
vừa mở trả `-25204` cho đăng ký observer (timeout 0,3 s) và watcher vẫn nhớ pid ⇒ tính năng câm tới lần đổi app sau; sửa bằng luật
thử lại thuần (0,5/1,5/3 s, chỉ cho -25204), đo lại: lần 0 = −25204, 532 ms sau lần 1 = 0. **Chưa đo:** Safari (text marker),
ghi vào Lịch thật, panel Dịch (macOS 15 + tay người), app Chromium/Electron với vùng chọn thật (probe thụ động đã thấy thông báo tới).
**E6 ✅ đo live 16/16** (`$20 ≈ 522,200 VND`, `1,500.00 EUR ≈ 44,489,205 VND`, một request, 20 tỷ giá; lượt đầu 14/14 lộ ra lỗi panel giữ giá trị cũ — sửa ở E6b) — đo trước khi viết: feed ECB có 29 đồng tiền và **không có VND**, trong khi vùng máy là `en_VN`; nguồn giờ theo tiền tệ địa phương: VND → XML công khai của Vietcombank (giá bán, 20 đồng tiền), còn lại → ECB. Đọc số tiền theo số chữ số lẻ ISO (`1.500 €` = 1 500, `KWD 1.500` = 1,5); `¥`/`kr` bị từ chối; `$` hiểu là USD và panel nói ra. Một request ≤ 12 giờ/lần, không timer, không gửi chữ đã chọn. 851 test, mutation 30/30 RED. E2e (`scratchpad/e6h/e2e.sh`, 14 kiểm tra) — chạy khi người dùng rời máy.

**Sau đợt E (giữ thứ tự, mỗi mục probe trước):** đo **B7 trên màn hình ngoài 1920×1080 vừa cắm** (notch ảo, hover, kéo cửa
sổ) · F: Quit-on-close, Uninstaller (bắt buộc xem trước + chỉ vào Thùng rác), Cleaning Mode, studio chụp & chú thích · G: quy
dirty memory về từng module (`vmmap -verbose`, `heap`), mục tiêu < 30 MB khi tắt hết tính năng nền.

**Chỉ tay người làm được (không probe nào thay):** Touch ID mở/huỷ bảng khoá · mọi click trên Thư viện Clipboard · AirDrop từ hub ·
kéo cửa sổ vào hàng snap ở notch · rút sạc / mất Wi-Fi / Caps Lock / nối AirPods cho live activity · ⌘⇧V và ⌘V Paste Stack bằng
bàn phím thật · Now Playing với Music/Spotify/YouTube thật · nghe TTS · vuốt hai ngón đổi trang notch.

### 3g. Đợt F — kế hoạch sau khi đo (2026-10-13)

**Đã đo, đổi cách hiểu một mục.** Plan cũ ghi "Cleaning Mode — preview bắt buộc + chỉ Thùng rác". Tôi tưởng là chế độ khoá bàn
phím để lau. Đo MFinder (app tham chiếu): đó là **Junk Cleanup** — chọn một thư mục, quét *rác metadata đã biết*, đưa vào Thùng
rác. Chuỗi của chính nó: *"only matches known Finder, AppleDouble, archive, and Windows metadata. Generic temporary files are
never selected. Finder may recreate .DS_Store later."* Danh sách tên nó biết: `.DS_Store`, `Thumbs.db`, `.localized`, AppleDouble
`._*`, và các thư mục cấp ổ (`.Spotlight-V100`, `.fseventsd`, `.Trashes`, `.TemporaryItems`).

| # | Việc người dùng (Part 0) | Làm | Đo / gate trước khi gọi là xong |
|:--|:--|:--|:--|
| **F1** | *"Sắp nén / gửi / chép thư mục sang USB hay máy Windows — dọn rác hệ thống bên trong, xem trước, vào Thùng rác."* | `Core/Cleanup/JunkRules.swift` (thuần): `.DS_Store`, `Thumbs.db`, `ehthumbs.db`, `desktop.ini`, thư mục `__MACOSX`, và `._x` **chỉ khi 4 byte đầu là magic AppleDouble `00 05 16 07`** (một file tên `._x` trên APFS có thể là dữ liệu thật). **Không bao giờ** đụng `.Spotlight-V100`/`.fseventsd`/`.Trashes` (đồ của hệ thống trên ổ đang gắn), không đi theo symlink, không đi vào package (`.app`, `.photoslibrary`), bỏ qua file iCloud chưa tải. Quét nền có giới hạn + huỷ được; xem trước theo nhóm (đếm + dung lượng, bỏ chọn từng nhóm); `FileManager.trashItem` từng mục; báo số đã vào Thùng rác + số lỗi; ghi Lịch sử thao tác. Trang ở **FINDER & TÌM KIẾM** (người dùng tới từ một thư mục) + nút "thư mục đang chọn trong Finder" | test thuần trên cây thư mục thật trong temp (có `._x` giả không magic, symlink ra ngoài, package); e2e trên thư mục harness: đúng N mục vào Thùng rác, file thật còn nguyên |
| **F2** | *"Gỡ app X sạch: app + file nó để lại trong Thư viện — thấy trước từng file, tất cả vào Thùng rác."* | Luật thuần khớp theo **bundle id chính xác** (mặc định chọn) và tên app (mặc định KHÔNG chọn, độ tin thấp); loại trừ app hệ thống, app đang chạy (yêu cầu thoát trước), group container còn app khác dùng | **probe trước:** `trashItem` một `.app` từ process không phải Finder (App Management, macOS 13+) và container sandbox của app khác (App Data, macOS 14+) — đo bằng app harness sandbox tự tạo, không đụng app thật |
| **F3** | *"Đóng cửa sổ cuối của Preview/TextEdit thì app thoát luôn, không nằm chết trong Dock."* | Opt-in **theo danh sách app** người dùng chọn; `AXObserver` (`kAXUIElementDestroyedNotification`) chỉ cho app trong danh sách; đếm lại `kAXWindows` sau 1 s (cửa sổ thu nhỏ vẫn tính); `terminate()` (vẫn hỏi lưu) | probe AX trên TextEdit: số cửa sổ sau ⌘W, cửa sổ thu nhỏ, hộp mở file lúc khởi động |
| **F4** ✅ code `57e0b0c` | Chụp & chú thích | Brief + 3 wireframe đã làm; chủ dự án chốt "làm y OneNotch trước" ⇒ phím tắt + thẻ xem trước nổi + trình chú thích (wireframe A). Mâu thuẫn với brief ghi thành Q-F4-1…6 trong `docs/PENDING_TESTS_AND_DECISIONS.md` | đã cài, **chưa test tay** (T-F4-1…11); chưa quay màn hình (Q-F4-1) |

Thứ tự: F1 → F2 → F3 → F4. Mỗi mục commit khi gate xanh; phép đo live ghi bù nếu người dùng đang dùng máy.

**Tiến độ F:** **F1 ✅** — phát hiện trong lúc làm: trên macOS 27 **mọi API liệt kê thư mục của `FileManager` giấu FILE THƯỜNG
tên bắt đầu bằng `._`** (`contentsOfDirectory(atPath:)`, `contentsOfDirectory(at:)`, `enumerator(at:)`, `enumerator(atPath:)` — có
header AppleDouble hay không, kể cả file rỗng; symlink và thư mục tên `._` vẫn được liệt kê), chỉ `readdir` thấy; `stat`/`fileExists`/`trashItem` vẫn chạy trên chúng. Bộ quét vì thế dùng `fts`
(`FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV`). 861 test, mutation 9/9 RED; đo live bằng chính `JunkCleanup.swift` trên Thùng rác thật
9/9 (5 mục vào `~/.Trash` rồi được chuyển ra lại); trang đo qua AX trên app đã cài, EN 9/9 chuỗi và VI 5/5. **Chưa đo:** bấm nút
chuyển vào Thùng rác qua giao diện (cần chọn thư mục bằng NSOpenPanel / Finder / thả — tay người).
**F2 ✅ đo live 18/18** — probe bằng một APP (không phải terminal): app bundle ở /Applications và ~/Applications, kể cả bản sao app
ký Developer ID hardened runtime, và thư mục trong Application Support/Caches: `trashItem` được; **container sandbox của app khác:
lỗi 513**, cả `NSWorkspace.recycle`. Cùng lệnh đó chạy từ terminal lại THÀNH CÔNG — TCC xét tiến trình chịu trách nhiệm, nên mọi
câu hỏi quyền phải đo từ một app bundle. Trang: Containers không có ô chọn mà có "Hiện trong Finder"; Group Containers / Application
Scripts vẫn cho thử (chưa đo được) và từng dòng báo kết quả thật. E2E trên app đã cài: preview đủ 4 mục + container được bảo vệ, bấm
nút → đúng 4 mục vào `~/.Trash`, container còn nguyên; mọi thứ được chuyển ra lại. 871 test, mutation 9/9 RED.
**F3 ✅ (chờ đo live)** — trang **Thoát ứng dụng** (CỬA SỔ) gộp "giữ ⌘Q" (trước chỉ có ở hub) và "thoát khi đóng cửa sổ cuối" theo
danh sách app. Đo bằng app harness hai cửa sổ: đóng cửa sổ → `AXUIElementDestroyed` sau ~0,05 s; đóng cửa sổ cuối → `kAXWindows`
rỗng mà app vẫn chạy; **app bị ẩn vẫn liệt kê cửa sổ nhưng subrole đổi `AXStandardWindow` → `AXDialog`** ⇒ luật đếm MỌI cửa sổ,
không lọc subrole. Thu nhỏ không tạo được khi Stage Manager bật (cả nút AX lẫn `miniaturize` — CGWindowList vẫn `onscreen=true`)
⇒ chưa đo. 876 test, mutation 7/7 RED. **Đo live 7/7 (13:02)** trên app đã cài, có xác nhận từ phía harness (nó ghi mọi lệnh nhận được): đóng 1/2 cửa sổ ⇒ `recount windows=1 quit=false`; đóng cửa sổ cuối rồi mở cửa sổ mới trong 0,3 s ⇒ không có recount nào (cửa sổ mới huỷ lượt đếm đang chờ); đóng cửa sổ cuối ⇒ `windows=0 quit=true`, app thoát; app không trong danh sách ⇒ vẫn chạy, không bị theo dõi. Ba lượt thất bại trước đó đều do **zsh**: `"$T:close0"` thành `…lose0` (modifier `:c`), `"$T:quit"` thành `…uit` (`:q`), chỉ `"$T:new"` sống sót — F3 chưa hề được thử ở ba lượt đó.

**G (đo, 2026-10-13 12:25)** — bản đã cài (F2), khởi chạy nền, đợi ổn định 90 s: **physical footprint 26,7 MB** như người dùng cấu hình
(đỉnh 30,5), **25,1 MB khi tắt hết 21 tính năng** (đỉnh 26,6) — cả hai dưới mục tiêu 30 MB; con số "48,4 MB" ở §1 đã cũ. Malloc dirty
15,8 MB, trong đó **phân mảnh 44 %** (7,4 / 17 MB vùng); top lớp: `non-object` 3,6 MB, Swift metadata 1,1 MB, dictionary storage
0,5 MB, method cache 0,4 MB, CFString 0,37 MB, CoreSVG 0,1 MB. **CPU idle CHƯA đo được**: người dùng thao tác suốt cả hai cửa sổ 60 s
(HIDIdle cuối cửa sổ = 0 s), nên 0,17 / 0,61 s không phải số idle. **CPU idle đo hợp lệ (12:57–12:58): 0,00 s / 60 s** (`0:00.44` → `0:00.44`), HIDIdle cuối cửa sổ 313 s, cấu hình của người dùng, bản build F3. Còn: xem phần phân mảnh malloc.

### 3h. Brief v3 — UI/UX theo OneNotch, tính năng agent theo NotchCrew (chủ dự án duyệt 2026-10-13)

Phạm vi UI/UX là OneNotch trước, cho toàn app; quy trình agent lấy từ NotchCrew (probe trước); trang AI là trang cài đặt
của XFinder (không lấy UI cài đặt từ notch như NotchCrew). Năm câu hỏi của brief lấy mặc định: statusLine của XFinder nối
vào statusLine đang có (opt-in, có sao lưu, gỡ được) · Claude + Codex + OpenCode trước, Cursor sau probe · thẻ duyệt quyền
chỉ hiện khi hook của XFinder được cài, probe cách nhiều hook PermissionRequest kết hợp · Giọng nói và Chọn văn bản thông
minh giữ trang riêng · màn có ảnh OneNotch dựng thẳng theo ảnh, wireframe chỉ cho phần riêng của XFinder.

| Phase | Nội dung | Trạng thái |
|:--|:--|:--|
| P1 | Vỏ notch: cánh khi thu gọn (cao bằng notch), dải 32 pt (chấm trang + tìm / toolbar), hai thân 382 / 612, loe mép trên, mở nảy nhẹ / đóng nhanh / đổi trang mờ chéo; restyle Clipboard + Đang phát | ✅ dựng + gate (CLAUDE.md "P1"); chưa kiểm trực tiếp — T-P1a…d |
| P2 | Trang Agents + view hạn mức AI trên toolbar (Claude % qua statusLine, opt-in, nối chuỗi) + Lịch + Hẹn giờ tập trung | ✅ dựng + gate (CLAUDE.md "P2"); chưa kiểm trực tiếp — T-P2-* |
| P3 | Vỏ cài đặt (sidebar 220 pt có ô màu, thẻ nhóm #F7F7F7 r10, header 52) + trang Giao diện / Media / AI / Lịch / Live Activities / Phím tắt; tách "Notch & Khay thả"; bỏ trùng (`notes.font` hai picker; gom phím tắt; đổi nhãn mặc định chụp "mặc định cho lần sau"; xoá tài liệu ⌥Space cũ) | ✅ dựng + gate (CLAUDE.md "P3"); quyết định mặc định Q-P3-1…9; chưa kiểm trực tiếp — T-P3-* |
| P4 | Restyle các trang cài đặt còn lại qua component chung | chưa |
| P5 | Kết nối Codex / OpenCode / Cursor (probe trước) + thông báo + phiên gần đây | chưa |
| P6 | Nói chuyện với phiên (probe kitty `send-text`, Terminal.app `do script`, socket nhắn tin của Claude) | chưa |
| P7 | Crew + phiên không cửa sổ | chưa |

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
  sự kiện hệ thống, không polling. **Chưa thử sống.**
- [x] **B4b (code, 2026-10-10)** HUD âm lượng (CoreAudio thật) + hẹn giờ trên notch. **Không làm HUD độ sáng**: giá trị đọc được bị kẹt.
4. Live activities: BT connect/battery (BatteryStore), sạc/pin yếu/đầy + Caps Lock + mất mạng (`AlertRules` thêm quy tắc, banner
   chuyển vào notch), hẹn giờ, HUD âm lượng/độ sáng *song song* hệ thống.
- [x] **B5 (code, 2026-10-10)** tab Clipboard trong hub notch: @filter, ⌘-bấm xếp Paste Stack (**vòng tiêu thụ ⌘V mới có từ đây** —
  trước đó `popNext()` không ai gọi), menu Biến đổi (17 phép, thuần) + Đi tới nguồn (app / trang nguồn Chromium / Finder).
  **Không có Dịch**: `translationd` từ chối binary ad-hoc, chưa đo từ app ký. **Chưa bấm thử sống.**
  - [x] **fix kèm theo (2026-10-10)** dán clip dài hơn 200 ký tự bị **cắt**: snippet lưu 200 ký tự, payload chỉ ghi khi >4096,
    dán đọc snippet. Đo trên `xfinder.db`: **227 bản ghi** 201–4096 ký tự chỉ còn 200 — không khôi phục được. `ClipboardText`
    (thuần) giữ luật; mutation C7/C8 tiêm lại cả hai nửa.
5. Trang Clipboard trên notch (deck của shelf) + @filter + ⌘-click stack + menu Transform/Dịch/Đi tới nguồn.
- [x] **B6 (code, 2026-10-11)** Đang phát trên notch: badge (ảnh bìa + tên bài), peek khi rê chuột (tên/nghệ sĩ + ⏮⏯⏭),
  trang trong hub (tiến trình nội suy, Mở <app>), hàng flyout, công tắc `notch.nowPlaying` (mặc định **tắt**). **Đã probe với
  nhạc "đang phát"** (publisher `MPNowPlayingInfoCenter` câm): MediaRemote **từ chối** tiến trình thường (trả rỗng khi đang phát),
  **trả đủ** khi dylib được nạp vào `/usr/bin/perl` (Apple ký) — nên đọc qua helper perl, không polling, ~18 MB; **gửi lệnh** thì
  app tự gửi được. Không AppleScript (chỉ Music/Spotify, cần Automation từng app, không trình duyệt). **Đã bấm thử sống
  qua app đã cài (2026-10-11): 13/13** — công tắc → helper → badge → bấm badge mở trang → Next/Play tới player → tắt → perl
  thoát; helper 0.01 s CPU / 17.6 MB. Player thật (Music/YouTube) chưa đo.
- [x] **fix kèm theo (2026-10-11)** callback IOBluetooth (B4a) đến trên `coordinatorQueue`, `assumeIsolated` làm app crash ngay
  khi mở với chuột BT đang kết nối (3 report). Nay `runOnMainActor`; gate `CallbackIsolationTests` đọc source.
6. Now Playing: **probe trước** (nhạc đang phát, so MediaRemote vs AppleScript). Không probe xong không ship.
- [x] **B7 (code, 2026-10-11)** trang đổi tên **Notch & Khay thả**; mục "Hành vi notch": độ nhạy rê chuột (0,12/0,25/0,5 s),
  pill dưới thanh menu cho màn không notch (**chỉ hình học — máy này một màn, có notch**), và **ẩn khỏi ảnh chụp/quay/chia sẻ**
  (`sharingType .none`; đo trên app đã cài: `kCGWindowSharingState` 0 ↔ 1 theo công tắc, 5/5). Per-activity switch đã có từ B4.
7. Cài đặt notch về trang Khay thả (đổi tên "Notch & Khay thả"): bật từng live activity, Pill cho màn ngoài, độ nhạy hover,
   ẩn khi quay màn hình.

### Phase C — Switcher ⌘-Tab
**C1 ✅ 2026-10-11** — Q/H/Space/`` ` ``, lọc theo màn hình con trỏ, `excludedApps` một reader, `Motion.overlayIn`; 9 test + 5 mutation đỏ. Hành vi phím thật trong switcher **chưa đo** (`windowPreview.commandTabEnabled` của máy này = 0).
Q (AX `kAXCloseButtonAttribute` → press), H (`NSRunningApplication.hide`), Space (phóng thumbnail), lọc theo màn hình chứa con trỏ,
`` ` `` chuyển app↔cửa sổ (store đã gộp theo app; thêm lister theo cửa sổ), `Motion.overlayIn` 0.16 s, một reader cho
`excludedApps`. Trang `.windowPreview` phẳng theo A.3.

### Phase D — Clipboard chiều sâu
Thư viện Clipboard (hồi sinh `ClipboardTabView`, dọn `.clipboard`), board khoá (AES-GCM + Keychain), Transform thuần + test,
highlight code (xử lý trên máy), MCP server target (stdio), xuất `.xfinderclip` gộp cả board (mở rộng `SettingsTransfer`),
xem trước link **opt-in** (mạng).

**D0 ✅ 2026-10-11** — Shelf ⌘⇧V dồn vào notch (wireframe B, `uiux/wf/wireframe.html?v=b`): một khoá
`clipboard.hotkeySurface` (`notch` mặc định / `shelf`, một picker ở Cài đặt Clipboard), tap CGEvent của
`ClipboardShelfController` giữ làm engine (⌘⇧V + chặn ⌘V cho Paste Stack), panel cũ chỉ còn sau picker. Trang notch
(bản 2, theo ảnh + video OneNotch người dùng gửi): hub **752×232** dùng cả dải hai bên notch (tab trái, ô tìm + ✕ phải),
hàng chip = Tất cả · Đã ghim · Đã lưu · Gợi ý · chip loại có số đếm · bảng · "+", menu Sắp xếp ở mép phải, **deck ngang**
4 thẻ 174×122 (`NotchClipCardView`), phím ⇧↩/Space/⌘P/⌘⌫/⌘F/⌘1–9, khoá Touch ID, menu chuột phải đủ việc của shelf
(+ Bảng ghim ▸). Hub theo trang: `NotchSurfaceLayout.expandedWidth/Drop(for:)`. Luật thuần `NotchClipboardRules` 11 test
+ 9 mutation. Fix kèm: lịch sử nạp rỗng lúc khởi động (DB mở sau fetch). **Chưa đo tay thật ⌘⇧V** — đo qua
`xfinder://clipboard` + CGWindowList (752×232 tại x 488) + cây AX.

**D0c ✅ 2026-10-12** — tốc độ & chuyển động: mở bằng một bước (`activateOn(page)`, hết nhảy x 649→488), hub **nở ra từ
notch** (`appearFromNotch`), frame hợp khi đổi trang, **`SurfacePanel.animationBehavior = .none`** (zoom order-front của AppKit
chặn main thread 214 mẫu/mở — đo bằng `sample`), root `GeometryReader` + nội dung layout một lần; cache icon app/file, thumbnail
ImageIO ≤ 480 px, text payload; ảnh lệch tỉ lệ > 1,5× thì fit (luật thuần, mutation D10); History limit 20 · 100 · 1000 với dòng
"hiện tại" cho giá trị cũ, cap là một reader và cũng giới hạn số dòng nạp; **màn không notch = notch ảo dính mép trên** (đảo B7).
Đo: cửa sổ hiện một mẫu 752×232 (106 ms sau URL; 258 ms lần đầu), `_runBlocking` 0; CPU/mở+đóng ≈ 0,45 s **chưa giảm**.

**D2 ✅ 2026-10-12** — highlight code on-device (`Core/Clipboard/CodeHighlighter.swift` + `Views/Components/HighlightedCode.swift`),
xuất `.xfinderclip` (`ClipExport` kế hoạch thuần + `ClipTransfer` panel/zip/unzip qua `ArchiveRunner`; `Pinboard.swift` tách
Foundation/SwiftUI để symlink vào test), **MCP không phải target mới**: `XFinder --mcp` trong `XFinderApp.init` trước mọi scene
(`Core/MCP/MCPProtocol.swift` thuần + `MCPServer.swift` đọc SQLite read-only). Khoá: `clipboard.mcpEnabled` (tắt),
`clipboard.shelfHotkey` (tắt — ⌘⌥C). Chi tiết đo trong CLAUDE.md "D2".

### Phase E — Smart Selection
Lớp phát hiện vùng chọn qua AX (`kAXSelectedTextAttribute`, cần Trợ năng) + popup `SurfacePanel(.pointer)`; dịch (15+),
tiền tệ (opt-in mạng), đơn vị, múi giờ, ngày → sự kiện Lịch (EventKit).

### Phase F — Lớn, sau cùng
Chụp & chú thích studio · Lịch/lời nhắc trên notch + thẻ họp · theo dõi agent AI · Quit-on-close · Cleaning Mode / Uninstaller
(bắt buộc preview + chỉ Thùng rác).

### Phase G — Hiệu năng & phát hành 1.3
Quy dirty 48 MB về từng module (`vmmap -verbose`, `heap`), mục tiêu <30 MB khi tắt hết tính năng nền; idle 0 % đo đúng cách;
release tự ký như 1.2.0.
**G1–G2 ✅ 2026-10-13** — đo bộ nhớ (26,7 / 25,1 MB physical footprint) + idle 0,00 s/60 s (xem §3g); **1.3.0**: Info.plist 1.3.0 (build 4),
What's New chuyển sang "1.3" (các ghi chú đợt N từng gắn "1.2" dù zip 1.2.0 ra trước chúng) + 4 ghi chú mới (Chụp & chú thích, Chọn văn
bản thông minh, Dọn rác/Gỡ app, Thoát ứng dụng), CHANGELOG 1.3.0 viết từ log 76 commit, `make-release.sh` giờ ký trợ giúp Now Playing
bằng XFinder Dev + bắt buộc có nó và hook Claude Code + `--verify --deep`. `dist/XFinder-1.3.0-arm64.zip` 6,3 MB, giải nén ra vẫn
hợp lệ chữ ký, checksum OK. **Chưa đăng** (Q-RELEASE). **G3 còn lại:** phân mảnh malloc 44 % — cần app chạy để đo (`heap`/`vmmap -verbose`).

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
* Bộ nhớ: Phase G đo lại 2026-10-13 — physical footprint 26,7 MB (cài đặt thường) / 25,1 MB (tắt hết tính năng nền); con số 48,4 MB cũ là thước đo *dirty* của `vmmap` trên một bản cũ, không so thẳng được. Đã ghi vào CHANGELOG 1.3.0; phân mảnh malloc 44 % còn chưa xử lý.

---

## 7. Quyết định đã chốt (chủ dự án, 2026-10-10)

1. **Đồng ý**: `SettingsCard` → `TileCard` chỉ cho lưới thẻ; mọi trang cài đặt phẳng 100 %. (`typealias SettingsCard = TileCard` tạm thời tới khi 12 trang xong.)
2. **Clipboard sống trong notch + shelf.** Không có trang sidebar riêng → `ClipboardTabView` (0 call site) và case `.clipboard` mồ côi bị **xoá** trong Phase A; deck của shelf là nơi duy nhất.
3. **Song song, probe-gated**: HUD của XFinder hiện cạnh HUD hệ thống; Now Playing chỉ ship sau probe với nhạc đang phát.
4. **Commit thẳng `main`, mỗi commit một việc, message bắt đầu bằng mã hạng mục** (`A1`, `A3-compress`, `B2`…) để đọc lại `git log` là thấy đang ở đâu; không PR (repo một người, PR chỉ thêm bước). Checklist §4 được tích dần trong file này.
