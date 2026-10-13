# OneNotch 2.0.5 — bằng chứng đo trên bundle đã cài (2026-10-13)

Mục đích: hiểu OneNotch **làm gì và làm bằng cơ chế nào**, bằng phép đo trên máy này, để đối chiếu và
nâng cấp XFinder. Không decompile, không đọc mã nguồn (app đóng; license của repo công khai đang được
tra), không bắn sự kiện giả vào OneNotch. Mọi con số dưới đây là đo được; chỗ nào suy luận thì ghi rõ.

Máy: MacBook Pro M3 Pro, macOS 27.0 (26A428), màn 1728×1117 pt, notch 771.5 pt rộng / 32 pt cao
(`NSScreen.auxiliaryTopLeftArea` = (0, 1085, 771.5, 32)). OneNotch đang chạy, pid 88458, lên lúc 05:11.

## 1. Bundle & chữ ký

| Mục | Đo được |
|:--|:--|
| Đường dẫn / bundle id / version | `/Applications/OneNotch.app` · `com.huyt.OneNotch` · **2.0.5 (67)**, SDK macOS 26.5, Xcode 26.6, `LSMinimumSystemVersion 15.0`, `LSUIElement 1` |
| Chữ ký | **Developer ID Application: Huy Tran (43CFN9BTC8)**, có `embedded.provisionprofile` (iCloud + APNs), **không sandbox** (`app-sandbox = false`) |
| Kiến trúc | arm64 thin, binary chính **30.9 MB**; `onenotch-mcp` 126 KB cạnh binary chính |
| Frameworks nhúng | `MediaRemoteAdapter.framework` (`com.vandenbe.MediaRemoteAdapter` 0.1 — adapter perl-hosted của ungive, BSD-3), `OneNotchMediaSessions.dylib` (export duy nhất `_onenotch_sessions`), `Sparkle.framework`, `Sentry.framework`, `Lottie.framework` |
| XPC | `OneNotchXPCHelper.xpc` (`ServiceType = Application`, không sandbox) — theo ghi chú kỹ thuật trong bundle: **chạy OCR ngoài process** vì Vision giữ +41…+77 MB sau mỗi lần OCR; helper tự thoát sau 180 s nhàn |
| Resource đáng chú ý | `CLAUDE.md` (211 dòng ghi chú kỹ thuật tiếng Việt của tác giả — bằng chứng cơ chế, xem §8), 4 video onboarding (`clipboard`, `glance`, `pill`, `tools`) + 2 video what's-new (`pick-color`, `smart-text`), 6 file `clipboard-sound*.wav`, 4 video AirPods + 1 PS5 (live activity Bluetooth), `oembed-providers.json` (xem trước link), `Wallpapers/`, `BluetoothDevices/`, `default.metallib`, `lock_icon_animation.json` (Lottie), bundle `GRDB`, `Defaults`, `KeyboardShortcuts`, `TelemetryDeck` |
| Bản địa hoá | **19 lproj** (ar cs de en en-GB es fr hu it ja ko pl pt-BR ru tr uk vi zh-Hans zh-Hant); `en.lproj` có **14 bảng, 2 471 chuỗi** — `Localizable` 1 217, `Capture` 309, `Annotate` 247, `Settings` 214, `Recording` 97, `Onboarding` 81, `QuickAccess` 79… |

## 2. Quyền & entitlement (đọc từ `codesign -d --entitlements`, Info.plist)

| Entitlement / usage string | Dùng cho |
|:--|:--|
| `automation.apple-events` + temporary-exception cho `com.spotify.client`, `com.apple.Music` | điều khiển Spotify/Music qua Apple Events (ngoài MediaRemote) |
| `device.audio-input` + `NSMicrophoneUsageDescription` + `NSAudioCaptureUsageDescription` | sóng nhạc thời gian thực ("Live audio waveform"), ghi âm khi quay màn hình |
| `device.bluetooth` + `NSBluetoothAlwaysUsageDescription` | live activity thiết bị BT (AirPods, tay cầm PS5) |
| `personal-information.calendars` + `NSCalendars/RemindersFullAccessUsageDescription` | trang Lịch & Lời nhắc trên notch |
| `icloud-services = CloudKit`, container `iCloud.com.huyt.OneNotch`, `aps-environment` | đồng bộ clipboard qua iCloud (`ClipboardCloudSync`), bảng `tombstones` trong SQLite |
| `network.client` + `network.server`, `NSAllowsArbitraryLoads` | lời bài hát (Apple Music/MusicKit), xem trước link (oEmbed, YouTube, TikTok), tỷ giá, YouTube Music WebSocket, cloud upload ảnh chụp, Sparkle, Sentry/TelemetryDeck |
| `NSAppleMusicUsageDescription` (MusicKit) | lời bài hát đồng bộ từng từ |
| `NSScreenCaptureUsageDescription` + ScreenCaptureKit | bộ chụp/quay màn hình (một sản phẩm thứ hai gộp vào 2.0) |
| Trợ năng (AX) — không phải entitlement, xin lúc chạy | thay HUD hệ thống, đọc text đang chọn (dịch), kéo item thanh menu qua vạch ngăn, dán thẳng vào app |
| Full Disk Access — xin lúc chạy | đọc metadata Focus (icon + màu) |

## 3. Kiến trúc runtime (đo lúc đang chạy)

| Phép đo | Kết quả |
|:--|:--|
| Tiến trình | `OneNotch` (pid 88458) · `/usr/bin/perl mediaremote-adapter.pl … stream --no-diff --debounce=120` (21 MB) · `/usr/bin/perl -MDynaLoader … OneNotchMediaSessions.dylib onenotch_sessions` (19 MB) · `OneNotchXPCHelper` (8 MB) |
| RSS | **167 MB** process chính + 48 MB ba helper ≈ 215 MB (XFinder: ~28 MB dirty, mục tiêu < 60 MB) |
| CPU | 05:26:05→05:29:57 (232 s, **trong lúc probe AX + poll CGWindowList của tôi chạy** và trang AI đang hiện session Claude): 37.39 s → 48.70 s = **≈ 4.9 %**. Mẫu 60 s yên tĩnh: xem phụ lục cuối file |
| Cửa sổ (CGWindowList, pid 88458) | **4 cửa sổ**: notch **`700×745` tại x 514 (căn giữa 1728), layer 27, alpha 1, sharing 2, onscreen** · `OneNotch Settings` 870×640 (ordered-out) · 500×500 layer 0 (ordered-out) · 38×36 layer 101 (badge dịch/toast, ordered-out) |
| Khung notch theo thời gian | poll 40 lần × 0.5 s: **không đổi một pixel** — một panel cố định, nội dung animate bên trong (XFinder resize panel theo từng trạng thái, D0c phải vá "giật") |
| Window level | layer **27 = `NSWindow.Level.mainMenu` (24) + 3** — khớp ghi chú trong bundle: "notch ở level `mainMenu + 3`, nằm dưới overlay `.screenSaver`" |
| AX | 1 cửa sổ, subrole `AXSystemDialog`, lúc đo chỉ có 2 text node: `Claude` · `Running Bash` — trang AI agent đang hiển thị **chính session Claude Code này** ở trạng thái thu gọn |
| Màn hình ngủ / khoá | lúc màn ngủ (`CGDisplayIsAsleep = true`, loginwindow shield layer 2000/2001, WindowServer "Display 1 Shield" trên cùng) OneNotch treo **hai cửa sổ mới**: `259×32 @ (734,0)` và `442×234 @ (10,875)` ở layer **2147483628** — tức notch + player trên màn khoá qua SkyLight, bắt quả tang đang chạy |
| Liquid Glass | defaults `forceLiquidGlassCompatibilityFallback = true` + `didMigrateLiquidGlassFallback_v1`; chuỗi "Semi liquid glass mode is still experimental…" — trên 27 họ **ép fallback** |

## 4. Dữ liệu trên đĩa

`~/Library/Application Support/OneNotch/` (576 KB): `clipboard_history.sqlite` (WAL), `clipboard_boards.json`,
`onenotch-captures.db` (GRDB), thư mục `ClipboardImages/ ClipboardThumbnails/ ClipboardVideoPosters/ ClipboardBoardImages/
LinkPreviews/ HistoryThumbnails/ Captures/`, `AI/Claude/{events,sessions,last-seen.txt}`, `bin/` (hook script). Cache riêng
`~/Library/Caches/com.huyt.OneNotch`. Cấu hình còn được **đồng bộ ra `config.toml`** (dotfile, export/import, "Someone edited
config.toml outside the app"). MCP socket `…/OneNotch/mcp.sock` **không tồn tại** lúc đo (tính năng tắt).

Schema clipboard (đọc read-only):

```sql
CREATE TABLE items (id TEXT PK, type TEXT, timestamp REAL, source_bundle_id TEXT, source_app_name TEXT,
                    source_url TEXT, preview TEXT NOT NULL, search_text TEXT, content_json BLOB NOT NULL);
CREATE INDEX idx_items_timestamp ON items(timestamp DESC); CREATE INDEX idx_items_type_ts ON items(type, timestamp DESC);
CREATE TABLE tombstones (id TEXT PK, deleted_at REAL, device TEXT);   -- xoá có dấu vết, phục vụ iCloud sync
```

Bảng: `{"id","name":"Pin","hasLock":false,"iconSystemName":"bookmark","items":[],"isSystem":true,"lockedContentDigests":[],"lockedImageFileNames":[]}`
— khoá bảng của họ giữ **digest** nội dung đã khoá (so với XFinder D4: HPKE + Secure Enclave, không digest).

Defaults `com.huyt.OneNotch`: 68 khoá. Đáng chú ý: `notchOpenBehavior = "activity"` (hover mở trang theo hoạt động đang
có), `history.maxCount 500 / retentionDays 30`, `history.floating.position topCenter`, `clipboardSourceColorRGB` (màu theo
app nguồn, có `com.anthropic.claudefordesktop`), `aiAgentTrackingEnabled / aiTrackClaude = true`, `snapZonesEnabled`,
`KeyboardShortcuts_clipboardHistoryPanel = ⇧⌘C`, `…_toggleNotchOpen = ⇧⌘V`, `…_translateSelection = ⇧⌘G`, 9 cờ
`didMigrate*_v1`, `usageAnalyticsEnabled = false`. Binary còn ~480 khoá dạng `a.b.c` (annotate.*, history.*, quickAccess.*,
screenshot.*, shortcuts.*…).

## 5. Private API & cơ chế không công khai (chuỗi trong binary + process)

| Cơ chế | Bằng chứng | Nhận định cho XFinder |
|:--|:--|:--|
| MediaRemote (Now Playing) | perl + `MediaRemoteAdapter.framework` (**đúng kỹ thuật XFinder B6 đã tự đo và dựng**), và một perl thứ hai nạp `OneNotchMediaSessions.dylib`; binary chính gọi `MRMediaRemoteSendCommand / SetElapsedTime / SetShuffleMode / SetRepeatMode` | XFinder đã có B6; thiếu seek (`SetElapsedTime`) và shuffle/repeat — **probe được**, cùng cơ chế |
| SkyLight / CGS | `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel`, `SLSAddWindowsToSpaces`, `SLSSetLoginwindowConnection`, `CGSSessionScreenIsLocked`, `CGSSetConnectionProperty`; class `OneNotchSkyLightWindow`, `LockScreenBackdropSkyLightOperator`, `NotchSpaceManager` | **Notch trên màn hình khoá** + space riêng cho notch. Private, có thể vỡ mỗi bản macOS → XFinder **không làm** (giữ quyết định cũ) |
| LoginUIKit | `/System/Library/PrivateFrameworks/LoginUIKit.framework` | dựng lại UI lock screen (`LockScreenUIKitReconstructionNSView`) — không làm |
| ToneLibrary | đường dẫn `AlertTones` / `Ringtones` | âm báo hệ thống cho timer/lịch — **đọc file public trong bundle hệ thống**, dùng được nếu muốn |
| libwebp | `OneNotch/WebPEncoder.swift`, `InitVP8Encoder`, `PutVP8XHeader`… | họ **biên dịch libwebp vào binary** (macOS không có encoder WebP — XFinder B2c đã đo). Muốn "Convert → WebP" thật thì phải vendor libwebp (BSD) |
| Thay HUD hệ thống | class `MediaKeyInterceptor`, `BrightnessManager`, `KeyboardBacklightManager`, `_hudReplacement`; chuỗi "Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs… Accessibility access is required" | Cơ chế suy ra (chưa chứng minh): event tap **nuốt phím media** rồi tự đổi âm lượng/độ sáng ⇒ OSD hệ thống không bao giờ được gọi. Âm lượng XFinder ghi được (CoreAudio); **độ sáng XFinder đã đo không có đường ghi công khai** → phần độ sáng là probe-gated |
| Telemetry | Sentry.framework, TelemetryDeck bundle, `crashReporterSampleBucket`, `usageAnalytics.*`, `Send anonymous crash and usage data` (opt-in) | XFinder giữ **0 telemetry** |
| Cập nhật | Sparkle, kênh Stable/Beta, EdDSA `SUPublicEDKey`, tự tải nền | XFinder giữ `UpdateChecker` do người dùng bấm |

## 6. Tính năng — kiểm kê từ chuỗi giao diện, class name, defaults (không phải từ trang web)

**Notch (lõi).** Trạng thái đóng/mở; hover mở (độ trễ chỉnh được "Hover delay"), click, cử chỉ hai ngón (vuốt xuống
mở, vuốt lên đóng, vuốt ngang đổi bài; "Gesture sensitivity"); `notchOpenBehavior`: mỗi hover mở cùng một trang **hoặc theo
hoạt động** ("Music playing opens Media, a running agent opens AI agents"); **trang** cuộn ngang với chấm trang (video: 3 chấm):
Page 1 Media controls · Page 2 (Glance: lịch/lời nhắc/timer) · Page 3 Timers + Clipboard / Custom; "Notch toolbar layout" (kéo
icon sắp xếp/ẩn); chiều cao notch tuỳ chỉnh cho màn có/không notch; "Match menu bar height"; hiện trên mọi màn hoặc theo màn
đang dùng; ẩn khi app full screen (chọn khi); ẩn khỏi chụp/quay màn hình (chọn khi); haptic; bóng cửa sổ; icon pack;
"Sneak Peek" (hiện tên bài dưới notch vài giây khi đổi bài); "cool face animation while inactive" (agent pet); Liquid Glass /
Semi liquid glass / fallback; **notch trên màn hình khoá** (private).

**Clipboard.** Lịch sử + bảng (Pin hệ thống + bảng người dùng, khoá bảng); chip loại có số đếm, `@image`-filter; **panel nổi**
(⇧⌘C, pin, sáng/tối/glass, vị trí trên/giữa/dưới); "Direct Paste on Click" (dán thẳng vào app trước, cần AX) hoặc chỉ copy;
**⌘/⇧-click chọn nhiều → ⌘V dán theo thứ tự** (`ClipboardPasteQueueManager`); cửa sổ sửa (`ClipboardEditWindow`); peek preview
khi hover (`ClipboardPeekPreviewWindow`); màu theo app nguồn; âm copy/paste (6 file); tạm dừng ghi; bỏ qua nội dung nhạy cảm
(concealed/transient) + danh sách app bỏ qua; giới hạn & thời gian giữ (Free 24 h, Pro không giới hạn); xoá có tombstone;
xuất/nhập "history, boards, images, and pins in one file"; **iCloud sync**; xem trước link (`LinkPreviewStore`, oEmbed, YouTube,
TikTok); OCR ảnh clipboard (`ClipboardImageOCR` qua XPC); **MCP cho agent** (`onenotch-mcp` ↔ unix socket; "Claude Code, Cursor
and Codex can now search your clipboard history, read your latest copy **and write back to it**"; "Allow agents to organize
boards: create boards, pin/unpin — not rename/delete; locked boards off-limits"); "Run OneNotch only as a menu-bar clipboard
manager".

**Media.** Now Playing mọi nguồn hoặc chỉ Music/Spotify/YouTube Music; nút player tuỳ biến (volume mở rộng khi active),
shuffle/repeat/seek; ảnh bìa động (Apple Music motion artwork, chỉ khi notch mở); lời bài hát đồng bộ (MusicKit, Pro: phiên
âm/phát âm); visualizer (FFT từ system audio tap, màu theo palette ảnh bìa, custom Lottie); player trên lock screen.

**Glance.** Lịch tháng/tuần + lunar (video: "Sunday · 16/8 Lunar · dải tuần · Good afternoon. Up next: Shipment · Lin at
15:00"), thêm sự kiện/lời nhắc từ notch (Free: hôm nay; Pro: ngày bất kỳ; "Summarize this day" = Pro), ẩn all-day, nhắc họp
+ link họp (meet.google.com, zoom, teams, whereby, jitsi), Focus timer / quick timer / "Mirror Clock app timer", Focus mode
(icon + màu cần FDA).

**AI agents (đo được cơ chế — §7).** Theo dõi session Claude Code & Codex, "Flag sessions waiting on you", **duyệt yêu cầu
quyền của agent ngay trên notch**, hạn mức 5 h/tuần của Claude ("Estimated from local CLI transcripts at list API prices"),
sắp xếp session, giữ session đã xong, âm báo, mở đúng tab terminal (tty/iTerm/tmux/WezTerm/Ghostty/Warp/cmux), cấu hình API
key riêng (Claude/OpenAI/Gemini) cho tóm tắt.

**Live activity & HUD.** Pin/sạc/Low Power/đầy, Bluetooth (AirPods có video riêng từng đời), Caps Lock, mạng, keyboard
brightness, Focus; **thay HUD** âm lượng/độ sáng/bàn phím (cần AX), kiểu HUD + glow + % số.

**Cửa sổ & thanh menu.** Snap Zones kéo lên notch (Halves/Full free; Quarters/Thirds/Focus = Pro; "Moving another app's
windows needs Accessibility"); **ẩn icon thanh menu bằng vạch ngăn** + vạch thứ hai "never show" — kèm chuỗi tự thú *"Puts the
divider back beside the OneNotch icon. Use this if hiding stopped having any effect"* (đúng cái chết XFinder đã đo trên 27).

**File Tray (video `tools`).** Kéo file vào notch → hàng ô: AirDrop · Resize · Convert (JPG/PNG/**WebP**/HEIC) · Compress ·
Remove BG · OCR · To PDF; "Drop to apply · Hold for options"; "Larger drop area".

**Smart text / Translate.** Nút dịch nổi khi bôi đen text ở app khác (`SelectionTranslateMonitor`, `TranslateBadgeController`,
cần AX; danh sách app loại trừ), ⇧⌘G dịch vùng chọn, "Translate in place", Apple Translation on-device + API key, phát âm.

**Bộ chụp màn hình (sản phẩm thứ hai, 2.0).** Area/Window/Full/Scrolling/Smart Element/Subject/Text (OCR)/Repeat Area/Pick
Color (kính lúp, Tab đổi HEX/RGB/HSL/HSB, ⌘-click lấy nhiều màu = Pro, WASD dịch pixel); quay màn hình + mic + keystroke
overlay + GIF; Annotate (arrow, blur, counter, crop, highlighter bám dòng, line, magnifier, measure, oval, pencil, rectangle,
spotlight, text, watermark, che thông tin nhạy cảm tự động); Quick Access card nổi (vị trí góc, swipe hai ngón, countdown,
hành động ở góc card); History panel; cloud upload; `config.toml`.

**Pro (từ chuỗi).** Lịch sử/bảng không giới hạn · thêm sự kiện ngày bất kỳ + tóm tắt ngày · ⌘-click nhiều màu · Quarters/
Thirds/Focus · phiên âm lời bài hát. License qua LemonSqueezy, "Lifetime license".

## 7. Cơ chế theo dõi agent AI — đo trên máy này (vì XFinder plan ghi "chưa rõ cơ chế")

1. OneNotch cài hook vào `~/.claude/settings.json` (nhãn `"statusMessage": "Managed by OneNotch"`): `MessageDisplay`,
   `Notification`, `PermissionDenied`, `PermissionRequest` (timeout **3600 s**), `PostCompact`, `PreToolUse`, `PostToolUse`,
   `UserPromptSubmit`, `SessionStart/End`, `Stop`, `SubagentStop`, `PreCompact`; cộng `statusLine` = script của họ.
2. Hook là **zsh script** `…/OneNotch/bin/OneNotchClaudeHook`: đọc payload stdin, chạy qua `jq` (`OneNotchClaudeHookHelper.jq`)
   để bỏ `tool_response` (ảnh base64 650 KB làm tràn log), thêm `one_notch_request_id` cho PermissionRequest, gom **ngữ cảnh
   terminal** (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `TMUX_PANE`, `WEZTERM_PANE`, Ghostty/Warp/cmux, `__CFBundleIdentifier`,
   `CLAUDE_CODE_ENTRYPOINT`, tty của tiến trình cha qua `ps -o tty= -p $PPID`), rồi **append một dòng JSONL** vào
   `AI/Claude/events/events-YYYY-MM-DD.jsonl` và ghi `last-seen.txt`.
3. `PermissionRequest`: hook **chặn** (vòng `zselect -t 25`, không fork, tối đa 1 h), poll file quyết định
   `AI/Claude/decisions/<session>-<request>.json` do notch ghi; có file → in JSON quyết định ra stdout (đúng giao thức hook của
   Claude Code); OneNotch không chạy/thoát → hook thoát im lặng, Claude Code hỏi ở terminal như thường.
4. `AI/Claude/sessions/<id>.json`: `{session_id, session_name, transcript_path, cwd, updated_at}`. App đọc tail của events
   (`OneNotchVnodeWatcher`, `OneNotchAgentProcessScanner`, `OneNotchClaudeSessionStore`, `OneNotchAIUsageStore`).
   Đo trên máy này: 66 dòng events trong ngày (PreToolUse 23, PostToolUse 22, UserPromptSubmit 5, SessionStart 4…).
5. Hạn mức: đọc transcript local của CLI, "estimated at list API prices"; app không gọi API Anthropic.

**Tất cả là file + hook công khai của Claude Code — XFinder làm được bằng API public, không cần quyền.**

## 8. Ghi chú kỹ thuật của chính tác giả (file `Resources/CLAUDE.md` trong bundle) — sự thật đáng giữ

* OCR trong XPC helper vì Vision giữ RAM trong process (+77 MB auto-language, +41 MB `vi,en`); helper thoát sau 180 s; pixel
  gửi qua `vm_allocate` + `Data(bytesNoCopy:…, .virtualMemory)` để không tính vào footprint.
* OCR lần đầu chậm 1–8 s là **chờ `aned`** (Neural Engine daemon), không phải CPU — prewarm bằng ảnh có chữ thật.
* Ripple khi nhả chuột: panel + hosting view tạo **một lần**, prewarm shader; main-thread block 29 ms → 4.5 ms.
* Crash macOS 27: `NSHostingView` mặc định làm contentView "pins max height" → vòng constraint; fix `NSHostingController`
  với `sizingOptions = []` + tự đo `sizeThatFits` (XFinder đã dùng `sizingOptions = []` từ D0c).
* **"`MainActor.assumeIsolated` từng crash trên macOS 27"** trong timer callback → họ dùng `Task { @MainActor }`. XFinder đã
  gặp đúng lỗi này ở IOBluetooth (B4) và có `runOnMainActor`.
* Notch toast ở level `mainMenu + 3`, nằm **dưới** overlay `.screenSaver` nên không dùng được lúc đang lấy màu.
* Pick Color: backdrop đóng băng full-res (live backdrop ở nominal resolution đọc sai màu trên Retina), kính lúp căn vào
  **tâm pixel** chứ không phải toạ độ con trỏ, màu theo sRGB, tách con trỏ bằng `CGAssociateMouseAndMouseCursorPosition(0)`
  khi giữ ⇧; chụp các màn song song ngoài main (160 ms → tính bằng `grab_ms`).
* Xung đột phím Carbon với app khác (Shottr ⇧⌘2) → cả hai cùng chạy, không có cảnh báo.

## 9. Frame video (bằng chứng hình, scratchpad `onenotch/frames/*.png`, 36 frame)

`onboarding-glance`: trang lịch trên notch (tuần + lunar + "Up next") — **frame ghi "16/8 Lunar" cho CN 27/9/2026, sai**: sóc tháng đó là 11/9 10:27 giờ VN nên 27/9 là 17/8 (cả lịch Việt lẫn lịch Trung); ảnh marketing không phải fixture. `onboarding-clipboard`: dải thẻ ngang, chip
`All 48 · Pin 7 · Links 12 · Code 9 · Images 18 · Work 15 · Ideas 8`, ô tìm `@image`, footer app · tuổi · dung lượng.
`onboarding-pill`: pill đen dưới thanh menu trên màn không notch. `onboarding-tools`: hàng ô AirDrop/Resize/Convert/
Compress/Remove BG/OCR/To PDF với hàng con JPG/PNG/WebP/HEIC khi giữ. `whatsnew-smart-text`: panel clipboard nổi sáng
("⌘/⇧-click to select — ⌘V pastes in order") + card peek có link và `password:` được tô. `whatsnew-pick-color`: kính lúp +
pill `#2A292A` + gợi ý "⌘ Click — Copy and keep picking".

## 10. Đối chiếu với XFinder (thực tế code, không phải kế hoạch)

| Vùng | OneNotch | XFinder hôm nay | Khoảng cách → việc |
|:--|:--|:--|:--|
| Panel notch | **một panel cố định 700×745**, level mainMenu+3, nội dung animate bên trong | panel **đổi frame theo trạng thái** (`render()`: grow/shrink/union + 0.32 s), level của `SurfacePanel(.notch)` | **N1**: một panel cố định, bỏ hẳn nhánh grow/shrink/union; đo bằng CGWindowList: frame không đổi |
| Mở khi hover | `notchOpenBehavior` = cùng trang / **theo hoạt động** | `notch.clipboardOnHover` (một trường hợp) | **N2**: picker "Mở khi hover: trang cuối · theo hoạt động · clipboard · khay" |
| Trang | chấm trang, cuộn ngang, toolbar sắp xếp được | tab `files/clipboard/nowPlaying`, `notch.pages`, vuốt hai ngón (D1) | giữ; thêm chấm trang khi > 3 trang |
| Clipboard notch | thẻ ngang, chip, @filter, dán thẳng, peek hover, paste queue | D0b/D1/D2/D3/D4a: tương đương, thêm Bảng khoá Secure Enclave, Thư viện, MCP đọc | **MCP ghi ngược** (`clipboard_set`) + "agents organize boards" là khoảng cách; peek hover chưa có |
| Now Playing | adapter perl + seek/shuffle/repeat + lyrics + artwork động + visualizer | B6 adapter perl, play/pause/next/prev | seek/shuffle/repeat **probe-gated** (cùng cơ chế); lyrics/visualizer: không (mạng/quyền mic) |
| Glance (lịch) | EventKit, lunar, thêm sự kiện, nhắc họp | chưa có | **N4** (Phase F → kéo lên) |
| AI agents | hook Claude Code/Codex, duyệt quyền trên notch, hạn mức | chưa có; plan ghi "chưa rõ cơ chế" | **N3** — cơ chế đã đo (§7) |
| Live activity | pin/BT/Caps/mạng/Low Power/Focus | B4: pin/BT/Caps/mạng + volume HUD song song | Low Power + Focus: thêm được (IOPS `LowPowerMode`, Focus cần FDA → không) |
| HUD | thay thế (nuốt phím media) | song song | độ sáng không có đường ghi public (đã đo) → giữ song song, nói thật |
| File Tray | AirDrop/Resize/Convert(+WebP)/Compress/RemoveBG/OCR/ToPDF, hold-for-options | B2d: ZIP/PDF merge/JPEG-PNG/RemoveBG/AirDrop | **N6**: Resize · To PDF · OCR · hold-for-options; WebP cần vendor libwebp (hoãn) |
| Dịch khi bôi đen | badge AX + Translation | chưa; `translationd` từ chối bản ad-hoc | **N5** sau probe với chữ ký XFinder Dev |
| Snap ở notch | Halves/Full/Quarters/Thirds/Focus | B3: 7 ô, có Thirds/Focus | ngang nhau, XFinder free hết |
| Ẩn icon thanh menu | vạch ngăn + "nếu hết tác dụng thì reset" | explainer (đo chết trên 27) | giữ quyết định cũ |
| Lock screen | SkyLight private | không | không làm |
| Onboarding / What's New | video + tour + badge NEW | không | **N7** (tĩnh, không video) |
| Telemetry / update / Pro | Sentry + TelemetryDeck (opt-in), Sparkle, LemonSqueezy | 0 telemetry, check thủ công, MIT | giữ |
| Tài nguyên | 167 MB + 48 MB helper, ≈4.9 % CPU lúc đo | 28 MB dirty, 0 % idle | **không** chạy theo hồ sơ tài nguyên của họ |

## 11. Chưa đo được / không đo

* Hình thật của notch khi mở (panel `sharing 2` nhưng tôi không chụp màn hình người dùng; không bắn hover giả).
* Cơ chế thay HUD (suy ra từ tên class, chưa thấy tap hoạt động).
* License của repo công khai và trang web/changelog: đang tra (agent web), bổ sung ở phụ lục.
* Nội dung `mediaremote-adapter.pl` và `OneNotchMediaSessions.dylib`: **cố ý không đọc** (giữ sạch MIT của XFinder; B6 đã tự
  đo cơ chế).

## Phụ lục — bổ sung sau khi đo xong

**CPU 60 s yên tĩnh, không probe nào của tôi chạy** (trang AI của nó vẫn đang hiện session Claude Code này — tức "idle" với
tính năng agent bật): 56.30 s → 59.23 s = **2.93 s / 60 s ≈ 4.9 %**, RSS 168 MB; helper MediaSessions 4.43 s tích luỹ (tăng
0.7 s/4 phút), adapter MediaRemote 0.05 s, XPC 0.01 s. So với XFinder đo 0.00–0.19 s / 60 s. **Không chạy theo hồ sơ này.**

**Tra web (agent chỉ-đọc, báo cáo đầy đủ ở `ONENOTCH_WEB_RESEARCH_2026-10-13.md`):**

* **Không tìm thấy repo GitHub nào**; notchy.dev ghi thẳng "it is not open source"; blog của chính OneNotch gọi Boring Notch /
  Atoll là open source để đối lập. Chuỗi "OneNotch is open-source" trong app **không kiểm chứng được** ⇒ coi là **mã đóng**:
  không đọc, không chép; chỉ đo. (Đúng cách tôi đã làm.)
* Yêu cầu: **macOS 15+, chỉ Apple Silicon**. Giá: Free (50 clip / 24 h, 1 bảng Pin), Pro $9.99 (1 000 clip, 20 bảng × 200,
  iCloud, chụp cuộn/tách nền/che tự động/dịch trong ảnh, lịch ngày bất kỳ, thêm layout, 2 Mac), Supporter $24.99 (5 Mac).
* Changelog (appcast, giờ +0700): 2.0.5 (67) 12-10 — nhập lịch sử từ Paste/PastePal/PasteNow/Maccy/CopyClip, xem trước video,
  Pick Color, sửa trạng thái agent, sửa crash Low Power Mode · 2.0.4 08-10 — kéo nhiều thẻ, Tab/⇧Tab đổi trang, sắp xếp ·
  **2.0.3 05-10 — "menu bar icon hiding disabled on macOS 27 for compatibility reasons"** (đúng kết luận đo của XFinder) ·
  2.0.2 04-10 — MCP list/read/pin/unpin bảng · 2.0.1 03-10 — MCP ra mắt, 10 layout snap · 2.0.0 30-09 — Pill, bảng khoá
  bằng **passcode + AES-GCM** (không nhắc Secure Enclave/Touch ID), Smart File Actions, Snap Zones, Focus Timer, Smart Select.
* Trang web tự mâu thuẫn về CPU: homepage "≈0 % idle", bài so sánh NotchNook "7–10 % idle, ~200 MB". Phép đo của tôi
  (4.9 %, 168 MB) nằm giữa hai con số đó và gần bài blog hơn.
* "Glance" là tên tôi lấy từ file `onboarding-glance.mp4` trong bundle, không phải tên trên web; "Mirror" (camera) có trong
  chuỗi UI (`Enable OneNotch mirror`, cần quyền camera) nhưng web không quảng cáo. OneNotch **không có khay giữ file lâu dài**
  (tự nhận trong bài so NotchNook) — Smart File Actions chạy ngay khi thả; XFinder có khay giữ + hàng tác vụ (B1/B2d).

**Click xuyên vùng trong suốt của panel cố định (đo 2026-10-13 07:17, màn thức, `NSWindow.windowNumber(at:)` — hit-test của window server, không có input giả).** Cửa sổ OneNotch #13634, layer 27, 700×745 tại x 514: điểm giữa thân notch (14 pt dưới mép) trúng **OneNotch**; ba điểm trong vùng trong suốt (300/200/700 pt dưới mép) trúng **cửa sổ bên dưới** (Claude). Nghĩa là panel cố định của họ không chặn thanh tiêu đề. Ma trận đối chứng trên panel tự dựng: thuộc tính `ignoresMouseEvents` **chưa từng gán** ⇒ vùng alpha 0 cho click lọt; **gán `false`** (trước hay sau khi order-front, hay true rồi false) ⇒ cả frame chặn, dù thuộc tính đọc ra `false` ở cả hai trạng thái. Đây là cơ chế, không phải code của họ: chuỗi `setIgnoresMouseEvents:` có trong binary của họ nhưng không nói họ gọi nó ở đâu.
