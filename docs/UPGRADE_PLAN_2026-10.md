# XFinder — Kế hoạch nâng cấp 2026-10

**Trạng thái**: Lập kế hoạch — chưa sửa dòng code nào  
**Nguồn tham chiếu**: vorssaint/vorssaint-utils (GPL-3.0, chỉ đọc README + docs)  
**Tác giả**: thang0todev@gmail.com  
**Cập nhật lần cuối**: 2026-10-09

---

## Phần 0 — Ba quyết định đã chốt

| # | Câu hỏi | Quyết định |
|---|---------|------------|
| 1 | Phân phối cho người khác? | **Có.** Ký Developer ID + notarize + Homebrew cask là mục tiêu thật. Trang Quyền và onboarding lên trước mọi tính năng mới. |
| 2 | Tính năng tắt có ẩn sidebar không? | **Không ẩn.** Features hub chỉ có công tắc. Thêm ô tìm kiếm đầu sidebar để xử lý ~32 hàng. |
| 3 | Text snippets? | **Bỏ.** Xung đột Telex/VNI chưa đo được, rủi ro không tương xứng lợi ích. Xóa khỏi lộ trình. |

---

## Phần 1 — Những gì tao đo được (không phải suy ra)

### 1.1 GPU % — IORegistry đọc được, AGENTS.md sai

```bash
ioreg -r -c IOAccelerator | grep "PerformanceStatistics"
# → "Device Utilization %" = 48
# → "Tiler Utilization %" = 48, "Renderer Utilization %" = 47
```

`SystemDetailView.swift:7` hiện ghi `"SMC and IOAccelerator are private and unreliable on Apple Silicon"`.  
Thực tế: `IOAccelerator → PerformanceStatistics → "Device Utilization %"` đọc được, không cần quyền.

**Việc cần làm trước khi xem là "xong":**
- [x] **Đo xong 2026-10-09** (sampler plist 0.5 s + bộ đốt Metal compute, không dùng Activity Monitor vì nó cũng chỉ là một UI khác đọc cùng nguồn): nhàn min 0 · median 1.5 · max 22; đốt 12 s median 99 · max 100; nhàn có trình duyệt vẽ ≈ 51. Bám tải thật.
- [x] Hiển thị số thật: `GPUUtilization.swift` (parser thuần + reader IOKit), `SystemMetrics.gpuUsage: Double?`, meter + sparkline trang Hệ thống, flyout. Trang đã render đo bằng `probe-ax-dump` khi đốt: `GPU → 99%`. CLAUDE.md 4 dòng sai đã sửa.
- [x] Placeholder chỉ còn khi khoá vắng (`nil`), không bao giờ bịa 0 — 3 mutation đỏ.

### 1.2 Nhiệt độ — chưa kết luận

`ioreg -r -c "smc-tempsensor"` có node, nhưng không in giá trị số.  
Ảnh Vorssaint hiện 42 °C CPU — có đường đọc được, nhưng không rõ đường nào.  
Repo Vorssaint là GPL nên không đọc Sources/.

**Việc cần làm:**
- [ ] Thử đọc `IOHIDEventSystemClient` thermal (không cần sudo, ít tài liệu)
- [ ] Nếu không tìm ra đường không cần quyền: giữ "Đang thu thập…", ghi rõ vào AGENTS.md

### 1.3 Baseline đỏ — xác nhận

**Build lỗi tại:**  
`Tests/XFinderLogicTests/DeviceCapabilityTests.swift:648`
```swift
// Lỗi: eventButtons(from:) trả về [Int]?, không phải [Int]
XCTAssertFalse(DeviceCapabilityModel.eventButtons(from: descriptor).contains(0xE8), …)

// Fix:
XCTAssertFalse(DeviceCapabilityModel.eventButtons(from: descriptor)?.contains(0xE8) == true, …)
```

**Cây bẩn:** 93 file thay đổi (55 M, 3 D, 34 untracked)

Untracked cần vào `.gitignore`:
- `.claude/`, `.v2c/`, `.zcode/`, `.zcodeignore`

Untracked cần commit (Voice module đang dở):
- `Tests/XFinderLogicTests/Voice*.swift` (AppleOnDeviceRefiner, DictationMode, HTTPRefiner, OllamaRefiner, RefinePrompt, RefinerTypes, VoiceKeychain, VoiceRefiner, VoiceRefinerTests, VoiceSettingsKeys, VoiceTextDiff, VoiceTrigger)
- `XFinder/Core/Voice/DictationMode.swift`
- `XFinder/Core/Voice/Providers/AppleOnDeviceRefiner.swift`
- `XFinder/Core/Voice/Providers/HTTPRefiner.swift`

Deleted cần `git rm` hoặc khôi phục:
- `XFinder/Core/Voice/Providers/OllamaCorrectionProvider.swift`
- `XFinder/Core/Voice/Providers/WhisperKitProvider.swift`
- `XFinder/Core/Voice/VoiceGhostOverlay.swift`

### 1.4 Controls nói dối người dùng — xác nhận bằng grep

| Key | Có Toggle | Có Reader | Hành động cần làm |
|-----|-----------|-----------|-------------------|
| `windowPreview.showHiddenWindows` | ✓ WindowDetailViews.swift:62 | ✗ | Xóa toggle **hoặc** implement reader |
| `clipboard.linkPreviews` | ✓ SettingsDetailView.swift:242 | ✗ | Xóa toggle **hoặc** implement reader |
| `clipboard.intelligentSuggestions` | ✓ SettingsDetailView.swift:118 | ✗ | Xóa toggle **hoặc** implement reader |

Câu "zero stored-but-unread keys remain" trong AGENTS.md là **sai**.

### 1.5 Một khóa bị bind nhiều chỗ — xác nhận

| Key | Nơi đọc/ghi |
|-----|-------------|
| `windowPreview.hoverEnabled` | DockPreviewController.swift:45 · MenubarController.swift:332-334 (UserDefaults thô) · WindowDetailViews.swift:9,77 · DashboardDetailView.swift:17 |
| `windowPreview.commandTabEnabled` | CommandTabController.swift:30 · MenubarController.swift:339-341 (UserDefaults thô) · WindowDetailViews.swift:10,36 |
| `dropTray.hoverEnabled` | NotchDropController.swift:58 · DropTrayDetailView.swift:21,205 |

`MenubarController.swift:332-341` đọc/ghi `UserDefaults.standard` thô — không reactive với SwiftUI `@AppStorage`. Đây là lý do "bật ở flyout, trang Settings vẫn thấy cũ".

### 1.6 MenuBarHiderController thiếu re-arm

`didBecomeActive` block trong `XFinderApp.swift` có 7 controller, thiếu `MenuBarHiderController`:

```swift
DockPreviewController.shared.applySettings()    // ✓
CommandTabController.shared.applySettings()      // ✓
SnapZoneController.shared.applySettings()        // ✓
FinderKeyboardController.shared.applySettings()  // ✓
ClipboardShelfController.shared.applySettings()  // ✓
QuickSearchPanelController.shared.applySettings()// ✓
VoiceManager.shared.applySettings()              // ✓
// MenuBarHiderController.shared.applySettings() ← THIẾU
```

Cần xác nhận `MenuBarHiderController` có thật sự dùng AX không trước khi sửa.

---

## Phần 2 — Thiết kế FeatureRegistry

### 2.1 Tại sao cần Registry

Bất biến hiện tại giữ bằng comment (`"default này PHẢI khớp controller"`).  
Registry biến bất biến thành code và test.

Bốn lỗi Registry xóa được:
1. Controller AX-gated bị bỏ sót khỏi `didBecomeActive` → feature chết sau cấp quyền
2. Flyout dùng `UserDefaults.standard` thô, Settings dùng `@AppStorage` → không sync
3. Default trong View khác default trong Controller → feature flip ngầm
4. Toggle không có reader → control nói dối người dùng

### 2.2 Thiết kế Swift

```swift
// Core/FeatureRegistry.swift

enum FeatureKind {
    case toggle(enabledKey: String, defaultEnabled: Bool)
    case action   // Caffeine, FolderLock, RemoteConnect, QuickShare, FinderUtils
}

enum IdleCost: String {
    case nothing        = "Không hoạt động"
    case eventDriven    = "Nghe sự kiện"
    case timerLight     = "Timer nhẹ (≤ 5 s)"
    case timerMedium    = "Timer trung bình (60 s)"
    case timerHeavy     = "Timer nặng (< 1 s)"
}

struct FeatureDescriptor {
    let id: String
    let nameKey: String
    let kind: FeatureKind
    let requiredPermissions: [PermissionKind]
    let idleCost: IdleCost
    var isEnabled: () -> Bool     // accessor, không phải String
    var setEnabled: (Bool) -> Void
}
```

**Lý do `isEnabled` là accessor, không phải String key:**
- Gesture: bật/tắt nằm trong blob JSON
- FinderKeyboard: OR của 3 khóa
- SnapZones: 1 master + 2 sub-toggle

### 2.3 Bảng tính năng

| Feature | Kind | enabledKey | Default | Permissions | IdleCost |
|---------|------|-----------|---------|-------------|----------|
| DockPreview | toggle | `windowPreview.hoverEnabled` | true | ScreenRecording | eventDriven |
| CommandTab | toggle | `windowPreview.commandTabEnabled` | false | ScreenRecording | eventDriven |
| SnapZones | toggle | `snapZone.masterEnabled` | true | — | eventDriven |
| MenuBarHider | toggle | `menuBar.hideEnabled` | false | AX* | timerLight |
| ClipboardShelf | toggle | `clipboard.shelfEnabled` | true | Accessibility | timerLight |
| FinderKeyboard | toggle | OR(3 keys) | false | Accessibility | eventDriven |
| EdgeNotes | toggle | `notes.edgeEnabled` | true | — | eventDriven |
| DropTray | toggle | `dropTray.enabled` | true | — | timerHeavy (khi hiện) |
| GlobalSearch | toggle | `search.globalEnabled` | true | Accessibility | eventDriven |
| Voice | toggle | `voice.enabled` | false | Microphone | eventDriven |
| FolderSync | action | — | — | — | timerMedium (khi sync) |
| FolderLock | action | — | — | — | nothing |
| RemoteConnect | action | — | — | — | timerMedium (khi chia sẻ) |
| QuickShare | action | — | — | — | timerMedium (khi chia sẻ) |
| ClipboardManager | always-on | — | — | — | timerLight (5 s floor) |

*AX cho MenuBarHider: cần xác nhận bằng grep `MenuBarHiderController.swift`.

### 2.4 Tests bắt buộc

```swift
func testNoTwoFeaturesShareEnabledKey() {
    let keys = FeatureRegistry.all
        .compactMap { if case .toggle(let k, _) = $0.kind { return k } else { return nil } }
    XCTAssertEqual(keys.count, Set(keys).count, "Duplicate enabledKey")
}

func testDefaultsMatchReaders() {
    // Với mỗi toggle: reset UserDefaults → isEnabled() phải == defaultEnabled
}
```

---

## Phần 3 — Tính năng mới từ Vorssaint

### 3.1 Quick wins — Phase 1 (0 idle CPU)

| Tính năng | API | Lưu ý |
|-----------|-----|-------|
| Sidebar search box | SwiftUI `TextField` filter | Không ẩn rows, chỉ filter display |
| ⌘Q hold-to-quit HUD | `NSEvent` + `ProgressView` | Dùng lại hạ tầng HUD Voice |
| Tự xóa clipboard | `NSPasteboard.changeCount` | Failsafe: không xóa nếu changeCount đổi |
| Clean URL | Regex trên string URL | Chỉ trigger khi clipboard là URL |
| Color picker | `NSColorSampler` (macOS 14+) | Copy HEX/RGB/HSL |
| Chọn thiết bị âm thanh | `CoreAudio` public API | Output device list + shortcut |
| Port manager | `lsof -iTCP -sTCP:LISTEN` | Parse PID + process name + kill button |

### 3.2 Tính năng cỡ vừa — Phase 3

| Tính năng | Permissions | Yêu cầu cứng |
|-----------|-------------|--------------|
| OCR vùng màn hình | ScreenRecording | Vision framework |
| Alerts (CPU/RAM/Disk/Temp/Battery) | — | Ngưỡng configurable, không spam |
| Menu bar readouts | — | Chỉ update khi flyout mở hoặc interval người dùng chọn |
| Quit-on-close | — | Per-app whitelist |
| Cleaning Mode | — | **Preview bắt buộc + chỉ Trash** |
| Uninstaller | — | **Hiện danh sách trước + chỉ Trash, không `rm`** |

### 3.3 Bỏ hoàn toàn

- Notch — đã gỡ chủ động
- Fan control — SMC private, không ổn định Apple Silicon
- Extra brightness — AX key không đọc được giá trị
- Recorder — scope quá lớn
- Radial menu — không phù hợp sidebar app
- Text snippets — quyết định: bỏ (xung đột Telex/VNI)

### 3.4 Probe trước — Phase 4

| Tính năng | Vấn đề | Cách probe |
|-----------|--------|-----------|
| Scroll direction riêng chuột/trackpad | Basilisk + Magic Mouse đều `IsContinuous = 1`, CGEvent không có vendor/product | Probe `IOHIDDevice` property khi event tới |
| GPU % thật | **XONG** — bám tải thật (0–22 nhàn / 99–100 đốt) | — |
| Nhiệt độ CPU/GPU | Node có, không ra giá trị | Thử `IOHIDEventSystemClient` |

---

## Phần 4 — Badge idle cost

Mỗi dòng trong Features hub hiện badge trung thực:

| Badge | Tính năng |
|-------|-----------|
| Không hoạt động | FolderLock |
| Nghe sự kiện | DockPreview, CommandTab, SnapZones, FinderKeyboard, EdgeNotes, GlobalSearch, Voice |
| Timer nhẹ (5 s) | ClipboardManager, ClipboardShelf, MenuBarHider |
| Timer trung bình (60 s) | FolderSync (khi sync), QuickShare (khi chia sẻ), RemoteConnect |
| Timer nặng (1 s, chỉ khi hiện) | DropTray |

---

## Phần 5 — Trang Quyền & Onboarding

```
Onboarding (một lần, sau Install):
  Bước 1: Chọn preset (Minimal / Developer / Power User) hoặc custom
  Bước 2: Xin đúng quyền preset đó cần — không xin thừa
  Bước 3: Done

Sidebar destination mới — "Tính năng & Quyền":
  Tab "Tính năng": list + toggle + badge idle cost cho từng feature
  Tab "Quyền": list permissions, tính năng nào cần,
               cảnh báo "Bạn đã cấp [Accessibility] nhưng không tính năng nào đang dùng nó"
```

---

## Phần 6 — Lộ trình

### Phase 0 — Baseline (điều kiện tiên quyết)

- [ ] Sửa dòng 648: `?.contains(0xE8) == true`
- [ ] Thêm `.gitignore` cho `.claude/`, `.v2c/`, `.zcode/`
- [ ] Commit Voice module (untracked + deleted)
- [ ] Commit các mảng còn lại
- [ ] `swift test` xanh

**Phase 1 không bắt đầu khi Phase 0 còn đỏ.**

### Phase 1 — Quick wins

Thứ tự: Sidebar search → ⌘Q HUD → Tự xóa clipboard → Clean URL → Color picker → Output switcher → Port manager  
Quy tắc: mỗi tính năng commit riêng, test riêng, L10n sweep sau mỗi commit.

### Phase 2 — FeatureRegistry

1. `FeatureDescriptor` + `FeatureRegistry.all`
2. Migrate controllers sang registry
3. Thay `UserDefaults.standard` thô trong MenubarController
4. Xử lý 3 dead toggles
5. Trang Tính năng & Quyền
6. Onboarding
7. Tests no-duplicate-key + default-matches-reader

### Phase 3 — Tính năng cỡ vừa

Theo thứ tự: OCR → Alerts → Menu bar readouts → Quit-on-close → Cleaning Mode → Uninstaller  
Cleaning Mode và Uninstaller: không implement nếu chưa có failsafe preview + Trash-only review.

### Phase 4 — Probe-gated

- ~~GPU % thật~~ — đã ship 2026-10-09
- Nhiệt độ (sau probe xác nhận)
- Scroll direction riêng (sau probe xác nhận tính khả thi)
- Developer ID + notarize + Homebrew cask

---

## Phần 7 — Câu hỏi còn mở

1. **Dòng 648**: Tao sửa (1 dòng, không ambiguous), hay mày tự xử?
2. **Cây bẩn**: Tao commit theo mảng (Voice / Clipboard / Gestures / L10n / Core / App), hay mày tự xử?
3. **Apple Developer account**: Có chưa? Quyết định timeline Phase 4.
4. **MenuBarHider + AX**: Tao đọc `MenuBarHiderController.swift` để xác nhận, hay mày biết?
5. ~~GPU probe~~ — đã đo và ship.

*Không sửa dòng code nào cho đến khi mày trả lời ít nhất câu 1 và 2.*

---

## Cập nhật 2026-10-09 — tài khoản Apple Developer miễn phí (đổi quyết định #1)

Chủ dự án xác nhận chỉ có tài khoản **free** (Personal Team, chứng chỉ "Apple Development", 0 thiết bị).
Hệ quả, không phải ý kiến:

- **Không thể** ký Developer ID và **không thể** notarize. Cả hai thuộc Apple Developer Program trả phí.
  Chứng chỉ "Apple Development" của tài khoản free không được Gatekeeper tin trên máy người khác.
- Vì vậy mục "Developer ID + notarize + Homebrew cask" **bị chặn** cho tới khi trả phí. Không có đường vòng bằng code.
- **Giai đoạn A (làm được ngay, miễn phí):** phát hành qua GitHub Releases bản ký bằng chứng chỉ tự ký
  `XFinder Dev`, kèm hướng dẫn cài *trung thực*: người dùng sẽ gặp cảnh báo Gatekeeper và phải mở
  System Settings ▸ Privacy & Security ▸ "Open Anyway" (macOS 15 trở lên đã bỏ cách chuột phải ▸ Open;
  cần **kiểm trên macOS 27**, chưa đo). README phải nói thẳng điều này, không giấu.
- **Giữ MỘT chứng chỉ ký cho mọi bản phát hành** và **sao lưu `.p12` của nó** ra nơi an toàn: designated
  requirement là `identifier + chứng chỉ`, nên quyền Trợ năng/Ghi màn hình của người dùng chỉ sống qua các bản
  cập nhật nếu chứng chỉ không đổi. Mất chứng chỉ = mọi người dùng phải cấp lại toàn bộ quyền.
- Homebrew cask: tao **chưa xác minh** chính sách hiện hành của homebrew-cask với app chưa notarize.
  Kiểm tra trước khi hứa; một tap riêng là phương án, nhưng cũng chưa đo.
- **Giai đoạn B (khi trả phí):** Developer ID + notarize + stapler; kiểm bằng `spctl -a -vv` và
  `xcrun stapler validate`, không chỉ `codesign --verify --deep` (đã biết nó che lỗi appex).
- Hệ quả thứ tự việc: trang Quyền + onboarding vẫn lên trước, **và** README cần mục "Cài đặt & cảnh báo Gatekeeper".
