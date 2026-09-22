# XFinder — macOS System Utility & Clipboard Manager

**Version**: 2.0 (pivot)
**Platform**: macOS **14.0+** · Swift 5.8 · SwiftUI + AppKit · **arm64 only**

**Two separate builds by design** (not Universal): an Apple-silicon build first,
an optimised Intel build later. `ARCHS = arm64` in all four configs today —
verify with `lipo -archs`. Do NOT "fix" this back to Universal.
**Author**: thang0todev@gmail.com

---

## Part 0: Design mindset (read before changing any page)

This section exists because of a real failure mode in this project: **pages were built by
copying a reference screenshot instead of designing from the user's job.** That produces
layouts that look right and behave wrong — duplicated controls bound to one key, groups
organised by which engine file implements them, and toggles for mechanisms that no longer
work. The rules below are the antidote; they outrank "make it look like the screenshot".

**1. Design from the job, not the picture.** For every page, write one sentence: *"The user
comes here to ____."* If two rows serve the same sentence, merge them. If a row serves no
sentence, delete it. Hệ thống answers "how is my machine doing" — which is why the
per-process CPU list was removed: that is Activity Monitor's job, and the sentence test
catches it instantly.

**2. A reference screenshot is evidence, not a specification.** MFinder shows *one* solution
to a problem. Copy the **problem understanding** (what the user is trying to do, what
information they need at a glance); re-derive the layout for XFinder's own feature set. If
you cannot say *why* a row is placed where it is, you copied it.

**3. Group by user intent, never by implementation.** `batchRename`/`actionHistory` moved to
FINDER & TÌM KIẾM because the user reaches them *from a Finder selection*, even though their
engines live beside the other tools. The sidebar is a map of intentions.

**4. One key, one control.** Two switches bound to one `UserDefaults` key is always a bug:
the second looks broken the moment the first is used. Before adding a control, grep the key.
This killed both the duplicate Dock-icon toggle and the whole `settingsGeneral` page.

**5. Defaults must agree with their reader.** An `@AppStorage` default that differs from the
engine's own default silently flips the feature for every user who never touched it. Grep
the key's reader and match it exactly.

**6. Honesty outranks completeness.** If the mechanism is gone (macOS 27 menu-bar hiding) or
was never public (GPU %, SMART), ship an explainer and a link to what *does* work. Never
ship a control that cannot do what its label says. A page that explains why something is
impossible is a finished page.

**7. Verify before you claim.** For anything touching the OS, write a probe that measures
the mechanism and run it. For pure logic, write a test and **prove it can fail** by injecting
the bug. "It compiles" and "the build succeeded" are not evidence that a file was even
included — check the compile log by name.

**8. Every user-facing string goes through `L10n.t()` — no exceptions.** This rule exists
because the language leak was reported **four times**: each fix wrapped the strings the
screenshot happened to show, then the next page the user opened was mixed again. Wrapping
"the ones you can see" is not a fix; the only fix is a sweep with a **measurement** and a
**lint that fails**.

*Architecture (three dicts, all keyed by the Vietnamese literal so call sites read naturally):*

| Store | File | Holds |
|:--|:--|:--|
| `L10nDB.table` | `Core/L10nDB.swift` | stable dotted keys (`sidebar.dashboard`) — sidebar + destinations |
| `L10n.enDict` | `Core/L10n.swift` | the original ~158 sidebar/Overview/QuickControls strings |
| `L10n.moreDict` | `Core/L10nStrings.swift` | every other full sentence (~550) |
| `L10n.fragDict` | `Core/L10nStrings.swift` | *fragments* used inside interpolation (`" mục"`, `"Đã nén "`) |

`L10n.t(_:)` tries them in that order and **falls back to the Vietnamese** on a miss — a
missing translation degrades to VI, it never crashes or shows a raw key.

*Interpolated strings need splitting, not wrapping.* `L10n.t("Đã nén \(n) mục")` can never
match a dict key, because the key contains a runtime value. The correct shape puts each
literal run through `t()` and leaves the expression alone:

```swift
// wrong — key is unique per n, never found
Text(L10n.t("Đã nén \(items.count) mục"))
// right
Text("\(L10n.t("Đã nén "))\(items.count)\(L10n.t(" mục"))")
```

Fragments keep their leading/trailing spaces on purpose — that is what makes the joined
sentence read correctly in both languages. They live in `fragDict`, separate from
`moreDict`, so a fragment can never shadow the full-sentence translation of the same words.

*Markdown-bearing strings* (`**bold**`) must reach a `Text(.init(…))` / `LocalizedStringKey`,
or the asterisks render literally. Use `L10n.md(_:)` for a bare `Text`; helpers that already
do `Text(.init(t))` — e.g. the `note(_:)` in the Sync/Remote/Share pages — take plain
`L10n.t()`.

*The lint.* This must print `TOTAL 0` before any language work is called done:

```bash
python3 - <<'EOF'
import re, glob
VI = re.compile(r'[À-ỹ]')
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
total = 0
for f in glob.glob("XFinder/Views/**/*.swift", recursive=True):
    for i, line in enumerate(open(f, encoding='utf-8')):
        if line.strip().startswith('//'): continue
        for m in STR.finditer(line):
            if not VI.search(m.group(1)): continue
            p = line[:m.start()].rstrip()
            if p.endswith('L10n.t(') or p.endswith('L10n.md('): continue
            total += 1; print(f"{f}:{i+1}: {line.strip()}")
print("TOTAL", total)
EOF
```

A bare `grep 'Text("'` is **not** sufficient — it misses `Label(…)`, `Button(…)`,
`Picker(…)`, `TextField(…)`, `DisclosureGroup(…)`, `SettingsCard(title:)`, ternaries, and
every non-`Text` call site. The sweep found leaks in all of those.

*Do not mass-wrap with a regex without checking the nested-quote cases.* A naive
`"…"` matcher breaks on `"\(cond ? "a" : "b")"` and `"\(String(format: "%.1f", x))"` — it
cuts the string at the inner quote and produces code that still compiles-looking but is
syntactically wrong. Five such sites broke in this sweep; each needed hand-repair. Build
after the script, and read the first errors as "the regex mis-split here", not "the file is
broken".

---

## What XFinder Is

A native macOS utility app with a **sidebar-driven, two-column layout**: system monitoring
across seven Vietnamese-labelled "Chung" pages, plus a clipboard manager, side notes, and a
menubar flyout. No file browser. No dead tab bar.

**Design reference**: MFinder's sidebar utility layout + Apple HIG.

**Performance targets**
- Idle RAM < 60 MB · Idle CPU ~0% · Launch < 500 ms

**Measured, Release build, Apple Silicon (2026-09):**

| Metric | Value | Tool |
|:--|--:|:--|
| **Dirty memory the app owns** | **28.3 MB** | `vmmap --summary` |
| `footprint` total | 69–189 MB | `footprint -p` |
| **Idle CPU (no metrics page open)** | **0.00 s / 60 s = 0 %** | `ps -o time` over a minute |

**Measure idle CPU with `ps -o time=` over ≥60 s, not `%CPU`.** `%CPU` in
Activity Monitor is an average since launch, so it keeps showing startup cost
(the user reported "5 %" while the process was actually idle).

**The "105 MB graphics" scare was a measurement error — do not chase it again.**
`footprint`'s `Owned physical footprint (unmapped) (graphics)` line counts
**shared GPU / WindowServer memory**, attributed to whichever app is frontmost.
Proof it is not ours: the Mạng page reports 72 MB total with 16 KB graphics,
while Điều khiển nhanh reports 57 MB total yet "105 MB graphics" — a number
larger than the process. `vmmap --summary` (the authoritative dirty figure)
says **28.3 MB**. Disabling the metrics timer entirely changed nothing
(75 MB vs 81 MB), confirming the 2 s tick is not the cause either.
**Always cross-check `footprint` against `vmmap --summary` before concluding
there is a leak.**

The binary is **native arm64** (verify: `lipo -archs`), Release uses `-O` +
`SWIFT_COMPILATION_MODE = wholemodule`.

**Two more idle-CPU fixes that got it to a true 0 %:**
1. `SystemMonitorManager` sampled **every** metric (battery, per-core CPU, disk,
   per-interface network) every 2 s **forever** — `stopMonitoring()` existed but
   was never called. It is now demand-driven: pages that display metrics call
   `retain()` in `.onAppear` / `release()` in `.onDisappear`, and the menubar
   flyout does the same. No consumer ⇒ no timer.
2. `ClipboardManager`'s backoff floor was a permanent **1 s** poll. Now
   0.25 s → 1 s → **5 s**, and every event path (`didActivateApplication`,
   `didBecomeActive`, `didWake`) calls `wakeAndCheck()`, which checks
   immediately *and resets the backoff* — without that reset the 5 s floor would
   persist right after a copy.

**Idle-CPU fix that worked (≈10× better).** Four controllers polled with
`Timer` — SnapZone 0.06 s, NotchDrop 0.05 s, EdgeNotes 0.12 s, DockPreview
0.03 s — i.e. dozens of wake-ups per second forever. All four now use
`NSEvent.addGlobalMonitorForEvents`, which fires only on real pointer activity.
Idle CPU went 1.3–7.3 % → 0.2–0.4 %. **Rule: never poll the pointer with a
Timer.** Where a feature must react to the *absence* of movement (Dock-hover
dwell, tray auto-close) arm a short one-shot/1 s timer only while that state is
live, never app-wide.

`SparklineView` was rewritten from `GeometryReader` + stacked `Path`s to a
single `Canvas` while investigating the above. It did not change the numbers
(the premise was wrong), but `Canvas` is still the better form for a chart
redrawn on a timer — one reused drawing surface instead of a layer per `Path`.

**Privacy**: 100% local, zero telemetry.

---

## The Honesty Rule (governs every metric)

A metric with **no public macOS API** must render an honest placeholder — never a fabricated
number. See the **Explicit Placeholders** section below for the full list. Dropping the private
probes (SMC temperatures, `IOAccelerator` GPU %, `nettop` per-app network, SMART) is deliberate:
they are unstable or unavailable on Apple Silicon, and a plausible-looking fake is worse than a
blank field.

---

## Part 1: Architecture

### 1.1 Navigation — two-column

`RootView` uses `NavigationView { … }.navigationViewStyle(.columns)` (NOT `NavigationSplitView` —
that is macOS 13+, and this app targets 12.0). Sidebar `SidebarView`, detail `DetailHostView`, with
a `SideNotesPanel` overlay toggled by a toolbar button.

### 1.2 State — `App/AppState.swift`

`@MainActor` singleton `ObservableObject`. Owns `selection: SidebarDestination`, `showSideNotes`,
`caffeineActive`. `navigate(to:)` + `bringMainWindowFront()` are the deep-link entry points used
by the menubar flyout. This is the single source of truth for the selected sidebar destination.

### 1.3 Destinations — `Models/SidebarDestination.swift`

`enum SidebarDestination: String, CaseIterable, Identifiable, Hashable`, each with `titleVI`,
`icon`, `isComingSoon`. `static var groups` drives the sidebar; selection is bound via an
**optional** `Binding<SidebarDestination?>` (macOS 12 `List(selection:)` requirement).

**Content vs settings split (2026-09, revised).** Clipboard cards live in the ⌘⇧V floating
shelf and notes live in the screen-edge panel, so the sidebar once carried only their settings.
That turned out to depend on **Accessibility being granted**: ⌘⇧V is an AX-gated CGEvent tap,
and on an ad-hoc dev build (new cdhash every rebuild) the grant is missing — the shelf never
opens and the whole feature reads as dead. The sidebar now has **both rows**: `clipboard`
(content deck, `ClipboardTabView`) and `settingsClipboard` (renamed "Cài đặt Clipboard") whose
first card is the ⌘⇧V hotkey toggle + AX status + one-click `AXIsProcessTrustedWithOptions`
prompt (`WindowManager.requestAccessibilityTrust()`). Pinboard tabs, search, and the ⌘1-9
board switcher still live inside the shelf itself.

| Group | Destinations |
|:--|:--|
| CHUNG | dashboard · quickControls · antiSleep · system · network · storage · pin |
| CỬA SỔ | windowPreview · snapZones · menuIcons (macOS now owns this — see Part 3) · settingsMenubar |
| FINDER & TÌM KIẾM | finderKeyboard · finderActions · finderSearch · aiSearch · **batchRename** · **actionHistory** |
| CÔNG CỤ | **clipboard** · settingsClipboard (renamed "Cài đặt Clipboard") · notes · dropTray · compress · pdfTools · folderLock |
| KẾT NỐI | sync · remoteConnect · quickShare |
| TIỆN ÍCH | finderUtils · quickLookPage · mediaCompat |
| footer | about |

**There is no CÀI ĐẶT group and no `settingsGeneral` destination.** "Cài đặt chung"
held only a theme picker and a Dock-icon toggle, both of which already existed on
Điều khiển nhanh and Tổng quan. A catch-all settings bucket beside pages that each own
their settings is duplication, and duplicated controls bound to one key look broken the
moment the user touches the other copy. `⌘,` and the menubar flyout's gear now open
`quickControls`.

`batchRename` + `actionHistory` live under **FINDER & TÌM KIẾM**, not CÔNG CỤ: they act on
the current Finder selection, so they belong beside the search rows the user reaches them
from. Group by *what the user is doing*, not by which engine file implements it.

Coming-soon rows render `PlaceholderDetailView`; `about` renders `AboutView`.
`SideNotesPanel` is a **column sibling of the detail view inside an `HStack`**, never a
`ZStack` overlay — an overlay floats above the detail cards and clips their right edge
(this was the "MAC stat not fit" bug).


### 1.4 Data managers (all `@MainActor` singletons, public API only, nil-safe)

| Manager | Backs | Source |
|:--|:--|:--|
| `SystemMonitorManager` | dashboard/system/network | host_processor_info, vm_statistics64, getifaddrs, ProcessInfo.systemUptime, sysctl swap |
| `PowerManager` | pin | IORegistry `AppleSmartBattery` (cycle count, capacity, watts) |
| `DiskManager` | storage | statfs/getmntinfo volumes + `IOBlockStorageDriver` Statistics I/O deltas |
| `CaffeineController` | antiSleep + flyout | `IOPMAssertionCreateWithName` (prevent idle sleep) |
| `SystemControls` | quickControls + flyout | CoreAudio volume (real); brightness via synthesized system keys 144/145 (AX-gated, value not readable); dark mode via System Events AppleScript + read-back (`setDarkMode` async, Automation-gated) |
| `ClipboardManager` | clipboard | pasteboard monitor + pinboards |
| `GlobalSearchController` | ⌥Space panel | CGEvent tap (AX-gated) + `mdfind` spotlight queries |

Per-page managers start `.onAppear` and stop `.onDisappear` so idle CPU stays 0%. Calling a
`@MainActor` method from a non-isolated Timer closure requires `Task { @MainActor in … }`.
**App-lifetime controllers** (Caffeine, ClipboardShelf, GlobalSearch, EdgeNotes, DockPreview,
SnapZone, NotchDrop) start in `applicationDidFinishLaunching`, with feature-flag gates so
idle features contribute zero CPU.

---

## Part 2: Pages & shared components

**Components** (`Views/Components/`): `SettingsCard` (grouped card), `ToggleRow`,
`MetricBigNumber`, `StatBarView` (bars drawn via `GeometryReader`/`Path` — no `Gauge`),
`SparklineView` (60-sample history), and the flat-layout set in `PageHeader.swift`:
`PageHeader` (icon + large title + subtitle, opens every page), `SectionHeader`
(icon + bold label + muted description), `StatusChecklistRow` (✓/⚠/○ + label + status
+ optional action button), plus `LabeledLine` and `MeterRow`.

**Layout convention (matches the reference screenshots).** System-monitor and settings
pages use the **flat System-Settings look**, not cards: `PageHeader`, then rows separated
by `Divider()`, all at `.padding(.horizontal, 20)`. Reserve `SettingsCard` for genuinely
grouped, boxed content. A page that opens with a bare `Text(title)` instead of
`PageHeader` is out of style and should be converted.

**Debug affordance**: launch with `-startPage <rawValue>` (e.g.
`XFinder.app/Contents/MacOS/XFinder -startPage network`) to open straight to one page —
`AppState.init` reads it. Useful for screenshotting a single screen.

| Page | Content (public API, else placeholder) |
|:--|:--|
| **Tổng quan** (dashboard) | **setup/status page, not a metrics dashboard**: app language, launch-at-login (`LoginItemController`, `SMAppService` on 13+ / `SMLoginItemSetEnabled` on 12), Dock icon, then a `StatusChecklistRow` list of every capability with its live state (Trợ năng · Ghi màn hình · Tự động hóa · Dock preview · Clipboard · Ghi chú mép · Chống ngủ), each linking to the page or Privacy pane that fixes it, + "Bắt đầu" hints |
| **Điều khiển nhanh** (quickControls) | **Flat three-group layout** (`PageHeader` + `SectionHeader` + `Divider`, no cards): **Hệ thống** — volume slider + mute (live via `VolumeObserver`), brightness −/+ (AX-gated, **no % ever shown**), Sáng/Tối/Hệ thống appearance applied system-wide (`SystemControls.setAppearance`, names the Automation failure + links to the pane), Chống ngủ, Tự động ẩn Dock (`DockPrefs`, a genuine two-way `com.apple.dock autohide` toggle + Dock restart); **Cửa sổ** — Xem trước Dock, Chuyển đổi ứng dụng ⌘-Tab; **Ứng dụng** — XFinder's own theme. This page is also the target of `⌘,` and the flyout gear since `settingsGeneral` was removed. **No Dock-icon toggle here** — Tổng quan owns `ShowDockIcon` |
| **Chống ngủ** (antiSleep) | on/off, duration picker (∞/15m/1h/2h) auto-release, countdown |
| **Hệ thống** (system) | flat layout: CPU/GPU **temp row → "Đang thu thập…"**, `MeterRow` CPU % + sparkline (real), `MeterRow` GPU → **empty track + "Không khả dụng"** (never a fake %), memory table (used/total, áp lực, nén, cache, swap) + sparkline, uptime, per-core bars in a `DisclosureGroup` |
| **Mạng** (network) | **compact**: ↓/↑ live rates (KB/s under 1 MB/s, MB/s above), physical interface, "Ứng dụng dùng mạng" auto-sampling every 2s while the page is visible (cancelled on disappear), session total, "Đo tốc độ" button (Cloudflare 25 MB). No per-interface table, no sparkline wall |
| Per-app network | sampled via `nettop -P` (labeled ≈) | cumulative counters only, no public real-time per-process API — honest sample, not a fake live chart |
| **Ổ đĩa** (storage) | volume picker + usage bar (real), I/O KB/s + sparkline (real), SMART → "Không khả dụng trên phần cứng này" |
| **Pin** (pin) | battery %/time/charging (real), health % + cycle count + watts (real), battery temp → placeholder; no-battery → "Không có pin" |
| **Clipboard shelf** (⌘⇧V, global) | `Core/ClipboardShelfController.swift` — **⌘⇧V now opens a floating bottom shelf over whatever app you are in**, not the in-app page. `.nonactivatingPanel` + `.floating` so the previous app keeps focus and the paste returns to it; `NSVisualEffectView` vibrancy; horizontal `LazyHStack` card deck. Keys: ←/→ select · ↩ paste · ⇧↩ plain text · ⌘1–9 direct · Space Quick Look · Esc close. Global hotkey = CGEvent tap (AX-gated — the same grant pasting already needs) |
| **Clipboard** (page) | PasteApp-style deck (`ClipboardTabView` + `ClipboardCardView`): app-icon accent headers, code/color/link/file/image bodies, keyboard map (Return/⇧Return/Space/⌘P/⌘F/⌘⌫/⌘1-9/Esc), Space Quick Look, Paste Stack queue, event-driven ingest with privacy filter (Concealed/AutoGenerated/Transient + password-manager bundle IDs), disk-offloaded payloads + Vision OCR search, history hydrated from SQLite, ⌘⇧V/⌘⇧C in-app hotkeys |
| **Global Search** (⌥Space, global) | `Core/GlobalSearchController.swift` + `Views/GlobalSearchPanel.swift` — **⌥Space opens a Spotlight-style search panel system-wide**. Floating `.nonactivatingPanel` stays above all apps; live `mdfind` queries (name + content + kind filters); ↑/↓ navigate, Return opens, Esc closes. Global hotkey via CGEvent tap (AX-gated). Results show icon + name + path, capped at 50 per query (0.2s debounce). Search runs on a background task, cancels on dismiss |
| **Tìm nhanh + Bảng lệnh ⌘K** (trang Tìm kiếm, finderSearch + global panel) | `Core/QuickSearch/` + `Views/QuickSearchPanel.swift` + `Views/Detail/SearchDetailViews.swift` — **hai bề mặt dùng chung một engine, không có trang sidebar riêng**. (A) *Trang Tìm kiếm*: khối Tìm nhanh (một ô nhập, kết quả nhóm theo loại: Liên kết nhanh · Ứng dụng · Tính toán · Tập tin, ≤5 dòng/nhóm, ↵ mở kết quả đầu) + khối **Bảng lệnh toàn cục** (công tắc `quickSearch.globalHotkey`, hotkey ⌘K, trạng thái AX + nút `requestAccessibilityTrust()` một chạm) + CRUD quicklink. (B) *Panel toàn cục* (`QuickSearchPanelController`, ⌘K kiểu Spotlight/Raycast/TinyCast): CGEvent tap AX-gated nuốt ⌘K hệ thống-wide; không có AX thì local monitor fallback (chỉ khi XFinder frontmost). Panel = `KeyablePanel` (tái dùng của EdgeNotesController) + `.nonactivatingPanel` → app trước giữ focus, TextField vẫn gõ được; ↑/↓ chọn · ↵ thực thi · Esc đóng (local key monitor trước TextField) · click ngoài đóng (cặp global+local mouseDown). Kết quả phẳng, dùng chung `QuickSearchEngine` (debounce 0.2s: Quicklinks → AppLauncher fuzzy → Calculator NSExpression → FileSearch mdfind). Bản cũ CommandPalette từng trỏ pbxproj sai path làm project không build nổi — đã gỡ trang riêng theo yêu cầu trùng lặp, settings dồn về trang Tìm kiếm |
| **Notes** | real page (`NotesDetailView`) with grid browser (`filterRow` search + color + Đang dùng/Lưu trữ + `notesGrid` `BrowserNoteCard`), edit via `NoteEditorSheet`; + screen-edge strip (Trái/Phải, sensitivity 4–40pt, fullscreen best-effort, hide-on-leave) + `AppearanceCard` (font picker + `fontSize` slider `notes.fontSize` 11–20pt) + `ShortcutsCard` (⌥⌘N/A/L + ⌘T/⌘F/⌘P/Esc legend) + JSON/Markdown/TXT Nhập/Xuất (`NoteStore.replaceAll/importMarkdown/importText`); `NoteStore` thêm `fontSize` + `markdownEnabled` |
| **Screen-edge notes** (`Core/EdgeNotesController.swift` + `Views/EdgeNotesViews.swift`) | **Three states** (matches the reference screenshots): (1) *docked* — one **9×28** coloured pill per note stacked down the edge (no text: at 14pt wide a label is unreadable, and the colour identifies the note; the title is a tooltip), with a small "+" under the stack. **Keep the docked strip tiny** — it sits over the user's work all day; (2) *peek* — pointing at a tab slides that note's body out beside it; (3) *open* — clicking a tab opens a 500×400 editor with title field, autosaving body, A/A font sizing, pin, checklist (⌘T), 8 colour swatches, Lưu trữ / delete / Đóng. Panel width animates per state (never the height — resizing both flickered), using a custom
`CAMediaTimingFunction(0.22, 0.9, 0.26, 1)` over 0.26 s plus a SwiftUI `.spring(response: 0.34,
dampingFraction: 0.86)`. Stock `.easeOut` starts at full speed and reads as a snap. `TextEditor` needs its backing `NSTextView.drawsBackground = false`, since macOS 12 has no `.scrollContentBackground`. Editor **autosaves on every keystroke**: a floating panel can be dismissed without any close event, so a Save button would lose work |
| **Xem trước cửa sổ** (windowPreview) | **settings page only** (no manual window grid — that was never the ask): "Cách hoạt động" hover toggle → `DockPreviewController` (app-lifetime, 0.35s dwell on a Dock icon → thumbnail panel, click to raise; AX-gated); "Xem trước cửa sổ bằng Command-Tab" → `CommandTabController` (CGEvent tap at `.cgSessionEventTap`, AX-gated, consumes ⌘-Tab only while enabled) + "Hiện cả cửa sổ ẩn"; "Quyền cần thiết" rows for Trợ năng + Ghi màn hình with live state |
| **Vùng bắt dính** (snapZones) | `Core/SnapZoneController.swift` + `Views/Detail/WindowDetailViews.swift` (SnapZonesDetailView) — snaps the **focused** window: drag to a screen edge → translucent zone overlay, release to snap; global hotkeys ⌃⌥←→↑↓/↩. **Page** theo MFinder: 3 toggles đầu trang (Khôi phục kích thước khi gỡ bắt dính / Tạo hiệu ứng cho vùng xem trước / Phản hồi rung — `snapzones.restoreOnUnsnap/showPreview/haptic`, haptic qua `NSHapticFeedbackManager.perform(.alignment)`), guide 2×2 grid với 8 check xung quanh (wording "Một phần tư trên bên trái", "Cạnh trái, nửa trên/dưới khi gần góc") + `snapCenterGrid` (4 arrow tiles), picker Ngang/Dọc, nút "Khôi phục mặc định" (reset 8 giá trị), `DisclosureGroup` "Chia cửa sổ của macOS" → Desktop Settings. "Bắt dính ngay" grid 10 zone + haptic trước mỗi `snapFrontmost` |
| **Biểu tượng thanh menu** (menuIcons) | **Explainer + deep link only — the mechanism is dead on macOS 26/27.** The Bartender-style separator trick (expand our own status item to 10 000 pt so items to its left are pushed off-screen) no longer works; see Part 3c for the measurements. The page now states what macOS actually supports, links to Control Centre → Menu Bar, and installs **no status item at all**. `MenuBarHiderController` keeps only `openSystemMenuBarSettings()` and a `separatorTrickAvailable = false` fact so the UI can explain itself. Shipping the old toggle would have left a widget in the user's menu bar that does not do what its own help text promises |
| **Thao tác Finder** (finderActions) | **now real** (`Views/Detail/FinderActionsDetailView.swift`) — 13-toggle **Cấu hình menu** (Bố cục Gọn/Đầy đủ + Terminal picker kitty/Terminal/iTerm/Alacritty + nhóm Mở trong/Tạo file/Sao chép/Hiển thị Finder/Dọn rác/Công cụ ảnh/Nén&Sắp xếp/OCR/PDF/Chống ghi/Khóa thư mục — mỗi `@AppStorage("finderActions.show.*")` default true, filter opacity khi tắt) + đọc selection Finder via AppleScript (Automation-gated, `-1743`) + 6 action buttons (copy-paths/ZIP/add-to-Khay-thả/Thùng rác/reveal/batch-rename hand-off); Finder context-menu items still need a Finder Sync Extension → links to the Extensions pane |
| **Tìm kiếm** (finderSearch) | structured name/kind/recency → `mdfind` with `-onlyin` scopes; results open in place or reveal in Finder (`Core/FileSearchEngine.swift`) |
| **Tìm kiếm AI** (aiSearch) | rule-based VN/EN natural-language → `mdfind` (kind + recency + name filter), with an on-screen "AI hiểu" explanation; 100% on-device, no cloud |
| **Đổi tên hàng loạt** (batchRename) | FileManager-only renames (prefix/suffix/replace/sequence/lower/upper) with live collision preview; successes logged to history as reversible pairs (`Core/BatchRenameEngine.swift`) |
| **Lịch sử thao tác** (actionHistory) | last-200 action log (rename/compress/extract/pdf/trash/other); rename undo moves files back without overwriting (`Core/ActionHistoryStore.swift`) |
| **Khay thả** (dropTray) | Drop-app-style drag shelf (`.onDrop` + persisted paths): move/copy/ZIP/trash/open-all; single shared destination picker. "Xem chi tiết" mở **grid inline ngay dưới header** `Trong khay (n)` (`LazyVGrid` adaptive 120, card icon+tên), thay vì window floating. Tạm ẩn notch/tai-thỏ settings (keys `dropTray.*` vẫn persist, engine vẫn chạy — bật lại UI khi hợp lý). Finder Sync Extension (`XFinderSync.appex`) còn nguyên, nói chuyện qua `xfinder://droptray-add?path=…`. |
| **Đồng bộ thư mục** (sync) | **now real** (`Core/FolderSyncController.swift`) — one-way mirroring via incremental `rsync -a`. Triggers: manual, on-change (`DispatchSource` watch on the source with a 3 s debounce so an edit burst produces one run), and daily at a chosen hour. `--delete` is **off by default** and warns in red, since it deletes permanently rather than to the Trash. Guards against source == dest and a dest nested inside the source (infinite recursion). Two-way sync is deliberately NOT offered — it needs conflict resolution and a change journal, and a half-built version loses data |
| **Khóa thư mục** (folderLock) | **now real** (`Core/FolderLockController.swift`) — AES-256 encrypted **sparsebundle** via `hdiutil` (`-stdinpass`). Locked = detached (ciphertext on disk); unlocked = mounted + opened in Finder. The original folder is only **trashed** (never `rm`) after the copy is verified by entry count. No password is ever persisted. Deliberately *not* `chflags hidden`, which is trivially reversible and would be dishonest to call "locked" |
| **Quick Look** (quickLookPage) | improved previewer: Markdown renders to HTML via WKWebView, archives list entries (`unzip -Z1`/`tar -tf`), anything else falls back to the native `QLPreviewPanel` |
| **Tương thích media** (mediaCompat) | AVFoundation openability check per file: track presence + codec FourCCs, "Phát được/Không" verdict |
| **Tiện ích Finder** (finderUtils) | Own file `Views/Detail/FinderUtilsDetailView.swift` (moved out of `FinderToolDetailViews.swift`), flat layout: a **Trạng thái tích hợp** checklist that reports each Finder surface from a **measurement** — "Thao tác trên mục đang chọn" = Đã bật, and "Tác vụ nhanh trong menu chuột phải" reads the extension's live `pluginkit` state via `Core/FinderExtensionStatus.swift` (enabled / disabled-by-user / registered-not-enabled / not-registered / unknown), each branch naming the next action — then readback + apply of supported `com.apple.finder` keys (extensions / hidden files / path-in-title) with a `cfprefsd` flush before the Finder restart, then a plain-language list of what XFinder adds |
| **Nén & Giải nén** (compress) | pick files/folders → `PageHeader` + 4-way "Giải nén vào" picker (`ExtractionDestination`: newFolderBesideArchive/sameFolder/downloads/custom via `resolvedDestDir`) + 3-way "Khi tên đã tồn tại" picker (`ConflictPolicy`: keepBoth/ask/merge via `uniqueDestURL` "Report 2" suffix) + card "Bộ máy nén 7-Zip 26.02 tích hợp sẵn" + ZIP (`ditto -c -k` default / `zip -P` when password/level≠6) / TAR.GZ (`tar -czf`); extract each source: `ditto -x -k` (zip) / `tar -xzf`, creating destDir first; `ditto`/`tar` via `Process`, "Tách tác vụ … hoạt động" card; log to history |
| **Công cụ PDF** (pdfTools) | PDFKit: merge ≥2 PDFs (with up/down ordering), extract pages (`1-3` / `2,5,7`), rotate 90/180/270° (subset or all); heavy work on a detached task, results written next to source or chosen folder; outcomes log to history |

**Menubar flyout** (`MenubarController.swift` → `MenubarFlyoutView`): volume slider (real,
`SystemControls`), brightness −/+ step buttons (shared `SystemControls.adjustBrightness`), caffeine toggle, system-info rows that
**deep-link** (`AppState.navigate(to:)` + front the window), header gear & footer "Cài đặt" →
`.settingsGeneral`, "Thoát" → quit.

---

## Part 3: Explicit Placeholders (never faked)

| Field | Placeholder | Why |
|:--|:--|:--|
| CPU °C / GPU °C | "Đang thu thập…" | SMC private/unstable on Apple Silicon |
| GPU % | "Không khả dụng" | `IOAccelerator` not public |
| Per-app network (sampled) | top-10 qua `nettop -P`, dán nhãn "≈" | no public API (was `nettop`, dropped) — restored as labeled sample |
| Disk SMART | "Không khả dụng trên phần cứng này" | SMART not exposed via public API |
| Screen brightness % | step −/+ only, no number shown | no public API to read or set the value; keys are synthesized, value unreadable → number never faked |
| Menubar-icon hiding — *other apps' icons* | explainer + link to Control Centre → Menu Bar | **No mechanism left on macOS 26/27.** No API can hide another app's status item, and the separator-expansion workaround stopped working (measured — Part 3c). The page installs no status item and says so |
| CPU per-process list ("which app is using CPU") | **removed from Hệ thống** | Activity Monitor already does it better (sortable, killable, per-thread) and sampling it cost a `top -l 2` subprocess every few seconds. Hệ thống answers "how is the machine doing", not "which app is misbehaving". `ProcessSampler.swift` was deleted with all four pbxproj entries |
| Finder context-menu items | **now real** — `XFinderSync.appex` is a shipped Finder Sync extension and `pluginkit` registers it from `/Applications`; `finderUtils` reports its live state and links to the Extensions pane for the one step no app can do (the user's enable switch) | adding items to Finder's right-click menu needs a Finder Sync Extension target, which this app now ships (see the Part 3c row on the three silent registration bugs). `finderActions` still acts on the current Finder selection |
| Finder hotkeys — Cut/Paste/Delete/Return (finderKeyboard) | **now real** via key *rewriting* | there is no API to remap Finder's shortcuts, but a CGEvent tap can rewrite keys before Finder sees them: ⌘X → ⌘C + a cut flag, then ⌘V → **⌘⌥V** (Finder's own "Move Item Here"), so **⌘Z still undoes it**. Delete → ⌘⌫, Return → ⌘O. Scoped to Finder and skipped while a text field has focus |
| Folder lock / Sync / Remote / Quick share | "Sắp có" | deferred per user ("mục riêng") |
| AI search cloud answers | explicit NL→Spotlight rules + on-screen explanation | 100% local, zero telemetry — no cloud model ever sees the query |

---

## Part 3b: Missing / unimplemented-functions register (audit — do NOT treat as done)

A future multi-function build must not re-introduce name-only tabs. Every sidebar row that is
**not** a real page, and every settings toggle that is **stored but never read**, is listed here.

**Every sidebar row is now a real page** — `isComingSoon` always returns false and
`PlaceholderDetailView` is only reachable via the `default:` arm.

**Removed in the 2026-09 cleanup** (do not re-add): the `SideNotesPanel` column and
`NoteCardView` (notes live in the screen-edge panel; the column repeated them on every
settings page), `AppState.showSideNotes`, and the `settingsPrivacy` destination +
`PrivacySettingsBody` (merged into the Clipboard settings page, where excluding password
managers actually belongs). `NoteEditorSheet` survives in `SideNotesPanel.swift` — the
Ghi chú page still uses it. Command-Tab (`CommandTabController`) is **kept** by request.
**`menuIcons` was un-resolved in the macOS 27 pass** — it is no longer a working feature,
by measurement, and is now an explainer page (see Part 2 / Part 3c). Do not "restore" the
separator trick.
Resolved in the 2026-09 pass: `finderActions`
(Finder-selection actions) · `finderKeyboard` (`FinderKeyboardController`) ·
`folderLock` (`FolderLockController`, encrypted sparsebundle).
Resolved this pass (no longer in this list): `windowPreview` · `snapZones` · `finderSearch` ·
`aiSearch` · `batchRename` · `actionHistory` · `dropTray` · `quickLookPage` · `mediaCompat` ·
`finderUtils` · `notes` (real `NotesDetailView` on shared `NoteStore`; the editor-sheet Save
no-op is fixed).

**Settings keys defined in `SettingsDetailView` but with NO live side effect** (stored in
`UserDefaults`, never read by the engine that should honor them):

| Key | Should drive |
|:--|:--|
(all 5 clipboard keys + all 3 menubar keys now wired — see Clipboard row in Part 2
and the menubar flyout section)

Only `AppTheme` (→ `AppearanceController`), `ShowDockIcon` (→ `DockController`),
the 5 clipboard keys (read at point of use by `ClipboardManager`/`ClipboardSounds`),
the 3 menubar keys (`showBattery`/`showNetwork` gate flyout rows,
`updateInterval` drives `SystemMonitorManager` cadence with live reschedule), and
the 5 `notes.*` keys (`edgeEnabled`/`edgeSide`/`edgeHotspot`/`fullscreen`/`hideOnLeave`,
read at point of use by `EdgeNotesController.applySettings()` on launch and on every
`.onChange`) are wired.
All settings keys now have live side effects — **zero** stored-but-unread keys remain.

**Note:** the old `SideNotesPanel.NoteEditorSheet` Save no-op is fixed (shared `NoteStore`). `AppDelegate` hotkeys are in-app `⌘⇧V` (open clipboard) / `⌘⇧C` (start Paste Stack); true system-wide hotkeys still need a global event tap.

**Rule for the next multi-function pass:** a tab is done only when its controls change observable
behavior AND each of its settings keys is read at the point of use — otherwise it renders
`PlaceholderDetailView`, never a name with dead widgets under it.


---

## Part 3c: macOS API traps — verified the hard way (do NOT re-introduce)

Each line below is a bug that shipped, was diagnosed, and was fixed. Re-check this list
before touching system-control code.

| Symptom | Root cause | Correct approach |
|:--|:--|:--|
| Dark-mode toggle does nothing, no permission prompt ever appears | `NSAppleEventsUsageDescription` missing from `Info.plist` → macOS **silently** denies the Apple event and never prompts | The key is mandatory for any `NSAppleScript` targeting System Events. Its absence fails quietly, which is why this looked like a code bug |
| `UserDefaults(suiteName: NSGlobalDomain)` returns `nil` | macOS explicitly rejects the global domain as a suite ("does not make sense" in Console) | **Read** global keys via plain `UserDefaults.standard` (it falls through to NSGlobalDomain); **write** them via `/usr/bin/defaults write -g` |
| Appearance read-back reports the stale value | `UserDefaults.standard` caches the global domain | Call `UserDefaults.standard.synchronize()` before each read-back poll |
| `AppleInterfaceStyle` absent ≠ error | The key **does not exist** in Light mode; only Dark writes it | Absent ⇒ Light. Never treat a read failure as "unknown" |
| Brightness −/+ buttons dead | Brightness is an NX **system-defined** `NSEvent` (subtype 8), not a virtual keycode — posting `CGKeyCode` 144/145 does nothing | `NSEvent.otherEvent(with: .systemDefined, … subtype: 8, data1: key << 16 \| state << 8)` with `NX_KEYTYPE_BRIGHTNESS_UP/DOWN` = 2/3, then `.cgEvent?.post(tap: .cghidEventTap)`. Needs Accessibility |
| Volume slider not live when the user presses the volume keys | Nothing observed external changes; the value was only sampled on view build | `AudioObjectAddPropertyListenerBlock` on `kAudioDevicePropertyVolumeScalar` + `kAudioDevicePropertyMute`, **and** on `kAudioHardwarePropertyDefaultOutputDevice` to re-bind when the output device changes (`VolumeObserver`, ref-counted via `retain()`/`release()`) |
| Dock-hover preview never triggers | `DockPreviewController` was started in the Xem-trước page's `.onAppear` and stopped in `.onDisappear`, so it only ran while that page was visible | Hover features are **app-lifetime**: start from `applicationDidFinishLaunching`, gate on the settings key (off ⇒ no timer ⇒ idle CPU still 0%) |
| Dock preview fired at the **notch** instead of Dock icons | `AXPosition` is **top-left origin**; `NSEvent.mouseLocation` is **bottom-left**. Comparing them directly maps a Dock icon at the screen bottom onto the pointer at the top | Flip every AX rect into AppKit space before hit-testing (`DockPreviewController.flipToAppKit`). Same trap as the snap-zone `axVisibleFrame` fix — **any** AX rect compared against mouse coordinates needs this |
| Snap zones fired on every mouse drag (text selection, file drags) | The tick only checked `NSEvent.pressedMouseButtons`, which is true for *any* drag | Qualify the gesture once at press time via `AXUIElementCopyElementAtPosition` and require an `AXWindow`/`AXToolbar` role (a title-bar drag); remember that verdict for the whole drag |
| ⌘⇧V opened an **empty** shelf — looked like the hotkey was dead | The event tap was armed and firing correctly; `ClipboardManager.shared` was simply **never instantiated at launch**, so its `init` never installed the pasteboard monitor and nothing was ever captured (`history=0`) | Touch `_ = ClipboardManager.shared` in `applicationDidFinishLaunching`. **Lesson: a lazy Swift singleton whose `init` has side effects does not exist until something references it** — never rely on a view rendering to start a monitor. Diagnose with `NSLog` + run the binary directly (`XFinder.app/Contents/MacOS/XFinder`) to read stderr |
| Dock preview panel covered the icon instead of sitting above it | The panel was positioned from `host.fittingSize` taken **before** the async thumbnails loaded, so the height used was near-zero | Position on a sane default size, then re-anchor after layout settles (50 ms and 250 ms). `anchorAbove` places the panel's bottom at `icon.rect.maxY + 8` |
| Snap overlay highlighted the **wrong corner** (bottom-left drag → top-left box) | `SnapTarget.rect(in:)` is authored in **top-left origin** (it feeds AXPosition), but the overlay passed `screen.visibleFrame`, which is **bottom-left** | Compute in AX space (`axVisibleFrame`) then flip for the NSWindow frame (`axRectToAppKit`). Both helpers live in `WindowManager` — use them, never hand-roll a flip |
| A feature worked in other apps but **not while XFinder itself was frontmost** — hit **three** times: Dock hover preview, edge-notes hover ("phản hồi lúc có lúc không"), clipboard-shelf click-outside-to-close | `NSEvent.addGlobalMonitorForEvents` only sees events delivered to *other* applications. It goes silent the moment any XFinder window — including our own floating panels — is frontmost, which makes the feature look *intermittent* rather than broken | **Rule, no exceptions: every `addGlobalMonitorForEvents` call in this app must be paired with an `addLocalMonitorForEvents` for the same mask, and both must be removed in the stop path.** Grep `addGlobalMonitorForEvents` and check each hit has a sibling. A local monitor must `return event` or it swallows the input. **One documented exception:** `SnapZoneController.startDragWatch` is global-only on purpose — it acts on `frontmostOtherApp()`, which excludes XFinder, so our own drags have nothing to snap |
| Clicking the **Dock icon** sometimes did not raise the window | Two compounding causes. (1) `applicationShouldHandleReopen` guarded on `if !flag`, but `hasVisibleWindows` is true whenever *any* window is up — and XFinder keeps floating panels (edge notes, shelf) on screen permanently, so the branch was skipped. (2) The fallback took `NSApp.windows.first`, which is frequently one of those borderless panels, not the real window | Never trust `hasVisibleWindows` in an app that owns utility panels; always front the main window (it is idempotent). Identify it as `!($0 is NSPanel) && $0.canBecomeMain` — an `NSPanel` can never be main — and `deminiaturize` first, since a minimised window ignores `makeKeyAndOrderFront` |
| Peeking one edge note **hid every other note**, so the user had to leave the strip and come back to read a second one | The preview card (186×118) was laid out **inline in the stack row** (28 pt tall), so it covered roughly three pills below it | Float the card as an `.overlay` beside the strip instead, `offset` past the pill, with `zIndex(1)` on the peeked row. The pill column then keeps its exact geometry — which the controller's row-index hit-testing depends on — and the pointer can slide down the edge from one note to the next. Corollary: `pointerMoved` must check the **pill strip first** and only then the "hold peek while on the panel" rule, or the peek freezes on the first note |
| `top`/`ps` for "which app is using the CPU" | `ps`'s `%CPU` is an **average over the process's whole lifetime**, so an app that was busy an hour ago still shows a high number while idle now | Use `top -l 2` and read the **second** block — the first is the same lifetime average. Same trap as measuring XFinder's own idle CPU. Also: read the pipe **before** `waitUntilExit()`, or a full pipe buffer deadlocks the child (`ProcessSampler`) |
| Khay thả vanished ~3 s after files were dropped into it | `performDragOperation` called `hide()` immediately, *and* the idle auto-close timer applied to a tray holding files | Dropping a file is the **start** of the user's task, not the end. The tray now pins open on drop (`holdOpen`) and never auto-closes while it holds items; an *empty* tray still auto-closes, since that is only clutter. There is an explicit ✕ to dismiss |
| Edge-notes peek **flickered between two notes**, and hovering "+" opened a preview instead of creating a note | The slid-out peek card grows *downward* and covers the tabs beneath it, but `noteID(at:)` maps pointer Y to a **fixed-height row index** — so re-running the hit-test over the open card resolved to the *next* note and the peek oscillated. The "+" button sat directly under the last tab, inside the same covered region | Hold the current peek while the pointer is anywhere on the panel (check panel containment **before** the hit-test, not after). The "+" was removed from the strip entirely — new notes come from the menubar ("Ghi chú mới"); the edge strip only *displays* existing notes. **A hit-test built on fixed rows is invalid once any row can expand** |
| A sidebar row rendered with **no icon at all** | `sparkles.magnifyingglass` is not a real SF Symbol on this macOS — `Image(systemName:)` fails silently | Verify every symbol with `NSImage(systemSymbolName:accessibilityDescription:) != nil` before shipping it. An audit script over all sidebar icons found exactly one bad name |
| Khay thả popped open on **any** mouse drag (text selection, window move) | The tick only checked `pressedMouseButtons`, and an "auto-open on file drag" shortcut had been added on top | **Every** open path now requires `dragCarriesFiles()` (inspect `NSPasteboard(name: .drag)` for `.fileURL`), and opening still needs the deliberate **shake** gesture. Hover-to-open only reveals files already held, never an empty tray |
| Snapped windows covered the **Stage Manager** strip | macOS does **not** shrink `visibleFrame` for Stage Manager — measured left gap is 0 even with it enabled | Read `com.apple.WindowManager / GloballyEnabled` and subtract `snapzones.stageInset` (default 68 pt) inside `axVisibleFrame`, so both the drag overlay and the final frame reserve it. User-tunable since the 68 pt default read as too wide: `snapzones.reserveStage` turns the clearance off entirely, `snapzones.stageInset` (slider, 0–140 pt) sizes it |
| Opening a note from the screen-edge panel **raised the whole Settings window** | `open()` called `NSApp.activate(ignoringOtherApps: true)` to let the panel take typing — but that activates the *application*, so every XFinder window comes forward | A borderless panel cannot become key by default; subclass it (`KeyablePanel`, `canBecomeKey = true` / `canBecomeMain = false`) and call only `makeKeyAndOrderFront`. **Never call `NSApp.activate` to focus one floating panel.** |
| Sidebar width jumped when a long row was selected | Two separate causes. (1) `.frame(minWidth:idealWidth:maxWidth:)` let the column re-negotiate per page. (2) Even with a fixed sidebar it still jumped, because the **detail** pane had no `minWidth: 0` — the batch-rename preview rows reported a wide ideal width and pushed the whole window | Fixed `.frame(width: 240)` + `.lineLimit(1)` on the sidebar, **and** `.frame(minWidth: 0, maxWidth: .infinity)` + `.layoutPriority(1)` on the detail host, plus `.frame(minWidth: 0)` on the long-filename `Text`s. **`lineLimit(1)` alone does NOT stop a view from demanding width** |

| **Pin page showed "Số chu kỳ —" and "Sức khỏe 1%" while IOKit had the data all along** | Two bugs, one root cause — looking in a single place and concluding the data was absent. (1) The reader used `AppleSmartBattery`, whose top level has `CycleCount` but **not** the capacity figures. The complete dictionary is in a *different service*: `AppleSmartBatteryPack → BatteryData`, which carries cycle count, design/nominal capacity, voltage, amperage **and temperature** together. The old code picked whichever dict it found first and silently lost the other's keys. (2) Health was `MaxCapacity / DesignCapacity`, but on Apple Silicon **`MaxCapacity` is a 0-100 percentage, not mAh** — 100 / 8579 = the "1%" on screen | Merge both services, and compute health from `NominalChargeCapacity / DesignCapacity` (measured: 7993 / 8579 ≈ 93%). **Never divide two IOKit numbers without checking their units — neighbouring keys in the same dictionary use different ones.** |
| **Battery temperature declared "no public API" — twice — and both times wrong** | Only `AppleSmartBattery` and `IOPMPowerSource` were dumped. The value is in `AppleSmartBatteryPack/BatteryData/Temperature` = 3469, i.e. **centi-Celsius → 34.7 °C**, with lifetime min/max in `LifetimeData` | Show it. Note the scales differ *within the same tree*: `Temperature`/`VirtualTemperature` are centi-°C, `LifetimeData/AverageTemperature` (248) is deci-°C, and `Maximum/MinimumTemperature` (47 / 9) are whole °C. **A negative result from one IOKit service is not a negative result for the machine** — sweep `ioreg -l` for the key name before concluding anything is unavailable |
| Brightness slider "did nothing", and did not follow the keyboard brightness keys | There was **no reader at all** — the control was a write-only stack of key events, so it could never reflect reality. The earlier claim "macOS has no public API to read brightness" was wrong: `AppleARMBacklight → IODisplayParameters → brightness` = `{value: 32768, max: 65536}` is readable through `IORegistryEntryCreateCFProperty` with no permission | Read via the registry and poll (1 s, demand-driven) since IOKit posts no notification for it — that is what makes the slider track the hardware keys. **Writing genuinely has no public path**: measured, `IODisplayGetFloatParameter`/`SetFloatParameter` return `kIOReturnUnsupported` (-536870201) on *every* display service (AppleARMBacklight, IOMobileFramebuffer ×3), so changes still go through NX key events and the slider re-reads afterwards |
| ⌘⇧V clipboard shelf, brightness slider và Finder-keyboard cùng "chết" một lúc | Cả ba đều **AX-gated** (CGEvent tap, post NX key) và bản dev ký **ad-hoc** — `security find-identity` thấy 0 chứng chỉ, mỗi rebuild có cdhash mới nên macOS âm thầm quên quyền Trợ năng. Probe (ioreg + CLI swift post NX events với terminal chưa được tin) cho thấy đường *đọc* (IORegistry brightness) chạy không cần quyền nào — nên "đọc được nhưng kéo không làm gì" chính là vân tay của việc thiếu AX. `DisplayServices.framework` (private, từ dyld cache) có `DisplayServicesGetBrightness/SetBrightness` nhưng cả hai trả `false` cho process thường → không phải đường ghi không-cần-quyền | (a) Hiện trạng AX + nút `AXIsProcessTrustedWithOptions` một chạm (`WindowManager.requestAccessibilityTrust()`) trên mọi trang cần AX; (b) trả lại hàng nội dung `clipboard` trong sidebar để tính năng với tới được dù chưa cấp quyền; (c) local-monitor fallback cho palette ⌘K. Fix dài hạn: tạo chứng chỉ "XFinder Dev" và cài qua `scripts/dev-install.sh` để quyền sống qua các lần rebuild |
| **macOS permissions reset on every rebuild, so each test needed re-granting** | TCC binds Accessibility / Screen Recording to a **code identity**, not a path. The default signature is ad-hoc, whose identity is the cdhash — and that changes on every build. Measured with two binaries signed under the *same* identifier: `2c6161…` vs `368f37…`. So each rebuild is a new app to macOS. `csrutil` is enabled (TCC.db unwritable) and `tccutil` can only **reset**, never grant, so there is no scripted way to re-apply a grant | Sign with a **self-signed certificate**: the designated requirement becomes "identifier + cert subject", which is stable across rebuilds, and install to a fixed path. `scripts/dev-install.sh` does the build → sign → install → launch, and falls back to ad-hoc with a warning when the cert is missing. The certificate itself must be created once in Keychain Access (Certificate Assistant cannot be driven non-interactively) |
| **Đổi tên hàng loạt resized the window — "fixed" three times before the real cause was found** | Earlier passes blamed the *preview rows* and added `minWidth: 0` / `maxWidth: .infinity` there. The bug reproduced with **zero files selected**, when no preview row is rendered at all — which should have falsified that theory immediately. The real culprit: a **6-segment `.segmented` Picker** whose labels ("Thêm tiền tố", "Đánh số thứ tự", …) sum into a very large *ideal* width, which `SettingsCard` (`maxWidth: .infinity`) passes straight to the split view | Use `.pickerStyle(.menu)` with a bounded `frame` for many/long options; `.segmented` is only safe for 2–4 short labels. Plus a shared `.pageWidthSafe()` modifier (`Views/Components/PageWidth.swift`) now applied at each page root. **Process lesson: when a fix does not hold, re-derive the cause from a case that reproduces it — the "no files selected" case disproved the preview-row theory in one step, but was never tried.** |
| Finder right-click / Quick Actions cannot list XFinder | Verified: the bundle contains **no `.appex`**, no `Contents/PlugIns`, and the project has zero FinderSync references. An app only appears in Login Items & Extensions ▸ Finder if it ships a **FinderSync app-extension target** | Not a settings problem and not fixable by any URL or toggle — it needs a new extension target in the project. Until that exists, the UI must say so plainly rather than linking somewhere that looks like it should work |
| **Files could not be dragged OUT of Khay thả** | Making the tray movable added `override func mouseDown { window?.performDrag(with:) }` on the container view. That swallowed **every** press before SwiftUI's `.onDrag` could begin, so a file drag could never start — the window-move fix broke the feature it was meant to support | A window drag and a file drag both begin with a mouse-down, so they must be separated **by where the press lands**: only the header strip (`dragHandleHeight`) calls `performDrag`; everywhere else falls through to `super.mouseDown` so the tiles keep their drag. **Rule: never blanket-forward `mouseDown` on a view that hosts draggable content.** Also, SwiftUI `.onDrag` vends exactly ONE `NSItemProvider` and `.itemProviders` does not exist on macOS 14 — dragging several files at once needs AppKit's `beginDraggingSession(with:)` (`MultiFileDragSource`); the old code passed `urls.first` and silently dropped the rest |
| **SMART was reported as "Không khả dụng trên phần cứng này" — that was WRONG** | Assumed rather than measured. `diskutil info <mount>` prints a real `SMART Status:` line (Verified / Failing / Not Supported) on Apple Silicon internal storage — verified on macOS 27: `diskutil info /` → "Verified" | Show it (`DiskManager.smartStatus(forMount:)`, off-main, reads the pipe **before** `waitUntilExit`). What is genuinely unavailable is the *attribute table* (reallocated sectors, wear levelling, drive temperature) — that needs `smartctl`/private IOKit, so it stays omitted. **The Honesty Rule cuts both ways: claiming data is unavailable when a public tool provides it is the same failure as faking data.** Re-check every "không khả dụng" placeholder against an actual probe |
| Battery temperature placeholder | Now **verified**, not assumed: a full key dump of `AppleSmartBattery` and `IOPMPowerSource` contains no temperature key at all; `AppleEmbeddedNVMeTemperatureSensor` exists for NAND but exposes no readable value in its properties | Stays a placeholder, and the UI now says it was checked on this machine. Do not re-chase it without the SMC (private) |
| Batch-rename preview kept resizing the window — **recurring, fixed three times** | `.frame(minWidth: 0)` only permits shrinking; the row still reports a wide **ideal** width, and that is what pushes the split view | Long-text rows need `.frame(minWidth: 0, maxWidth: .infinity)` — the `maxWidth` is the load-bearing half — plus `.layoutPriority` on the fixed separator. **Standing rule for this app: any row rendering a file name or path gets `minWidth: 0, maxWidth: .infinity` + `lineLimit(1)` + `truncationMode(.middle)`.** |
| A System Settings deep link "does not open the right section" | `x-apple.systempreferences:` can open a **pane**, never a row inside it. macOS 26/27 also moved Finder extensions into **Login Items & Extensions** (`com.apple.LoginItems-Settings.extension`), so the old `com.apple.ExtensionsPreferences` identifier lands in the wrong place | One shared helper (`WindowManager.openFinderExtensionsPane`) with an ordered fallback chain, and UI text giving the exact click path. Never imply a button lands on a specific switch when the OS cannot do that |
| **Dock hover preview and ⌘-Tab switcher both showed blank boxes on macOS 27** | `CGWindowListCreateImage` is marked **unavailable** by the macOS 26/27 SDK ("Please use ScreenCaptureKit instead"). The app kept *compiling* only because the deployment target is 14.0 — at runtime on 27 the call returns nil, so every thumbnail was empty. Two separate features broke at once, which was the clue: they shared this one API | Rewrite on **ScreenCaptureKit** (`SCShareableContent` + `SCScreenshotManager.captureImage`), verified by probe: 3/3 windows captured on 27.0. `WindowManager.thumbnail` is now `async`, plus `thumbnails(windowIDs:)` which does ONE `SCShareableContent` query for a whole panel instead of one per window. Still needs Screen Recording. **Lesson: a deprecated API that becomes SDK-`unavailable` does not fail the build when your deployment target predates the removal — it fails silently at runtime.** Grep for other deprecated CG/AX calls after every OS bump |
| ⌘-Tab switcher showed one icon per app and no previews | `switchableWindows()` deduped by pid, and the view rendered `NSRunningApplication.icon` only — there was never a thumbnail in it | Per-**window** rows (capped at 12) with a live SCK thumbnail each, and `WindowManager.raiseWindow(_:)` (AX `kAXRaiseAction`, matched by title/position) so picking the 3rd Safari window raises *that* window. `NSRunningApplication.activate` raises every window of the app and is wrong for a per-window switcher |
| ⌘-Tab: SOME windows showed a thumbnail, others a blank placeholder | Not a window-ID mismatch (measured: CGWindowList IDs matched SCShareableContent 12/12). The list was polluted by **phantom windows** — 6 of 12 rows were `WindowManager` "Gesture Blocking Overlay" (Stage Manager's own gesture windows) with `SharingState == .none`, which ScreenCaptureKit cannot capture, so they rendered empty | Filter in `listWindows()`: drop `owner == "WindowManager"`/`"Window Server"` and any window with `kCGWindowSharingState == 0`. Both are public CGWindowList fields. After the filter, 8/8 surviving windows captured. **Lesson: `SharingState == .none` is the reliable "this window is not capturable" signal — filter on it before handing IDs to SCK, rather than discovering the blank after capture fails** |
| **"Biểu tượng thanh menu" silently stopped hiding anything after the macOS 27 upgrade** | The Bartender/Hidden-Bar trick — own an expandable separator status item, let the user ⌘-drag icons to its left, then set `separator.length = 10_000` so everything left of it is pushed off the visible bar — **no longer works.** Measured on macOS 27.0 (26A428), 1728 pt screen: (1) `length = 10_000` is clamped by the OS to **~5016 pt** — still far wider than the screen, so width was never the problem; (2) with the separator expanded, a neighbouring status item **did not leave the bar** — it moved *right*, x=952 → 988, and was still `ONSCREEN` after a 7 s settle. macOS 27 lays the bar out ignoring the oversized item instead of letting it displace neighbours; (3) `CGWindowListCopyWindowInfo` reports **0** windows at the status-item layer, so an app cannot even observe other apps' items to work around it | **Never re-introduce the separator trick.** But note the follow-up below — "no mechanism exists" was too strong a conclusion, and the user was right to push back |
| **Clean-room finding: the macOS 27 menu-bar-hide feature IS buildable, and the safe primitive is now known** | Prompted by `fif7y/pelmet` (GPL-3.0). Licensing line held: **never read pelmet's source** (would taint XFinder's MIT); only its README and a design/plan `.md` the user supplied — both are *ideas/facts*, not copyrightable expression, so GPL does not attach. Every API fact below is from **my own runtime probe** of `MenuBarClientCore`, written in my own words. **The mechanism is a bundle-id ALLOWLIST, not a per-item hide** — verified: `MBAssessmentModeConfiguration(initWithAllowedSystemItems:allowedBundleIdentifiers:)` + `VisibilityRestrictionAssertion` apply a config of *what stays visible*; macOS hides the rest and reflows. This is the same path as exam "Assessment Mode". **Consequence:** to hide XFinder's *own* items, host them in a **helper process whose bundle id is left off the allowlist** — they then hide natively like any third-party icon. Detect side is public AX: `AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar")` → children with owner/title/x (14 real items enumerated here) | **Still not built — it is a multi-session feature** (nested `LSUIElement` helper target, launched via `NSWorkspace.openApplication` so LaunchServices registers it — never `Process()`; XPC main⇄helper; single-instance guard; the assertion lifecycle). The one thing to prove first, in an isolated spike: does the assertion actually hide an item hosted by a *nested* helper bundle, or does LS resolve it to the outer bundle? Everything rests on that. Because the primitive is an allowlist (list what STAYS), there is no payload that can blank the whole bar — that removes the earlier fear. Private + macOS-27-only + App-Store-disqualifying still stand |
| **Correction: a private mechanism DOES exist, and it was wrong to conclude otherwise from one dead workaround** | The user pointed out MFinder still hides icons on macOS 27. Probing further: macOS 27 ships `/System/Library/PrivateFrameworks/MenuBarClientCore.framework`. It is **not linked** by MFinder (absent from `otool -L`) but `dlopen`s fine from an ordinary unsigned binary. `MBMenuBarItemManager` instantiates, carries an `xpcSession` ivar talking to `com.apple.MenuBarAgent`, and responds to `setGloballyHidden:completionHandler:` and `setItems:completionHandler:`. MFinder is **not sandboxed** (zero `app-sandbox` entitlement keys), which is what makes this viable for it | **Still not shipped, and here is the honest reason:** the framework exposes no read path — no delegate protocol, no enumeration API — so XFinder can only hide the **entire** menu bar, not the icons the user picks. MFinder ships its own `MenuBarItemReader` to bridge that gap. A private XPC surface that is undocumented, App-Store-disqualifying, and can break on any point release is not worth a half-feature. **Process lesson (the important one): "I measured X and it failed" justifies only "X is dead", never "the feature is impossible." When a shipping app demonstrably does the thing, the null hypothesis is that you have not found their mechanism yet — keep probing.** |
| **Spike result: `MBAssessmentModeAssertion` does NOT hide third-party status items** | Built a nested `LSUIElement` helper (`com.xfinder.app.menubar-helper`) hosting one `NSStatusItem`, launched via `NSWorkspace.openApplication`. Activated an `MBAssessmentModeAssertion` with the helper's bundle id **excluded** from the allowlist. Measured: (1) assertion callback fires, (2) `com.apple.MenuBarAgent` system items (WiFi/Bluetooth/etc) **do disappear**, (3) helper's item, 1Password, Chrome, AyuGram — all third-party `NSStatusItem`s — **remain visible and unmoved**. Tested with empty allowlist (mode C): same result — only system modules are affected. Also tested `MBMenuBarItemManager.setGloballyHidden:true`: callback fires, **zero items hidden** — likely requires entitlements this process doesn't have. **What DID work**: `NSStatusItem.isVisible = false` from the helper's own process — the item disappears instantly and reappears on `isVisible = true`. This is a public API and only controls the calling app's own items | **The Pelmet/assessment-mode approach is dead for XFinder's use case** (hiding other apps' icons). The assertion only governs system Control Centre modules, not `NSStatusItem`s registered by third-party apps. Pelmet must use a different mechanism — possibly direct XPC to `com.apple.MenuBarAgent` with `setItems:`, or SkyLight manipulation (Thaw approach), or an entitlement we don't have. **For XFinder's own items**: `NSStatusItem.isVisible` is the correct, public path. No assertion needed — a helper can hide its own items on command via `DistributedNotificationCenter` |
| **Deep XPC probe: `com.apple.MenuBarAgent` XPC requires code signature** | Probed `MBMenuBarItemManager` internals: `xpcSession` ivar = nil after `init` (Swift type, not ObjC-visible) — manager does not auto-connect. Found Mach service name `com.apple.MenuBarAgent.systemservices` via launchd plist. Created NSXPCConnection to it with `MBMenuBarItemXPCServer` protocol (18 methods: `setItems:`, `setGloballyHidden:`, `acquireAssertionWithID:...`). Called `setGloballyHidden(true)` from **ad-hoc signed** Swift binary (same as default Xcode Debug build) → **error 4097** "connection to service" (connection refused). MFinder has developer certificate; XFinder has zero codesigning identities in keychain. Also probed SkyLight C functions (`SLSSetMenuBarVisibilityOverrideOnDisplay`, `SLSSetMenuBarInsetAndAlpha`) — both return 0, no visible effect. `NSMenu.setMenuBarVisible(false)` works but hides ENTIRE menu bar | MenuBarAgent XPC rejects ad-hoc/unsigned binaries. **May** accept developer-signed binaries (untested — requires self-signed cert setup per `dev-install.sh` pattern). MFinder binary analysis shows it uses `MBAssessmentModeAssertion` + separator pattern + `MenuBarOverflowController`, but lacks special entitlements (only `automation.apple-events` + `application-groups`). The XPC refusal is likely **signature requirement, not entitlement**. Self-signed cert path not tested — keychain empty |
| **Finder Sync extension had NEVER registered or loaded — three independent causes, all silent** | `pluginkit -m -p com.apple.FinderSync -v` listed six other apps and **no XFinder entry**, Finder showed no XFinder menu, and the appex segfaulted in `ImageIO`/`CFBundleGetInfoDictionary`. Found by comparing against a working extension (MFinder, Keka) rather than by reading our own code. (1) The appex target had `MACOSX_DEPLOYMENT_TARGET = 27.0` while the host app is 14.0, so `GENERATE_INFOPLIST_FILE` wrote `LSMinimumSystemVersion = 27.0` into the appex Info.plist — macOS refuses to register an extension whose minimum OS exceeds its container's. (2) The appex built with `ENABLE_DEBUG_DYLIB` (Xcode 16+ Debug default), shipping a loader stub + `XFinderSync.debug.dylib` + `__preview.dylib` instead of one real binary; working extensions ship a single executable. (3) `install-mouse-rebuild.sh` re-signed the appex with a bare `codesign --force`, which **drops** the sandbox entitlement the target builds with (`ENABLE_APP_SANDBOX = YES`) — `pkd` then logged "Final plugin count: 5" and refused ours. The same script signed the outer bundle `--deep`, re-signing the appex under the OUTER identifier and collapsing `com.xfinder.app.XFinderSync` into `com.xfinder.app` | Fixed all three: deployment target 14.0 + explicit `LSMinimumSystemVersion` in `XFinderSync/Info.plist`; `ENABLE_DEBUG_DYLIB = NO` on both appex configs; the install script writes the appex entitlements file, signs nested content explicitly, signs the outer bundle **without** `--deep`, and hard-fails if the appex loses its identifier or sandbox entitlement. **Measured after**: `pluginkit` shows `+ com.xfinder.app.XFinderSync(1.0) … /Applications/XFinder.app/Contents/PlugIns/XFinderSync.appex`, the extension process is alive and stable, no new crash report. Also: **every intermediate build directory registers the same plugin identifier** — 16 dead paths (staging, `/tmp`, DerivedData, a Desktop copy) all claimed `com.xfinder.app.XFinderSync` and blocked resolution; the script now deregisters build/staging copies and `pluginkit -a` the installed one. `codesign --verify --deep` hides all of this because it only checks the outer bundle. The user still has to enable the extension in System Settings ▸ Login Items & Extensions ▸ Finder, so the script prints the measured state (`!` registered-not-enabled, `+` enabled) instead of implying success |
| **Scripts rot silently onto removed structures and keep printing green** | Two verification scripts still referenced the four-store L10n split (`L10nStrings.swift`/`L10nDB.swift`) after the single `L10n.strings.json` replaced it. `verify-gesture-ui.sh` crashed with `FileNotFoundError`; `check-l10n-duplicates.py` printed `SKIP (missing)` twice and then **`TOTAL 0 duplicates across 0 unique keys`** — a passing result computed over nothing. Worse, `mutation-check-gesture-ui.sh` case 5 stayed **GREEN**: its `sed` target no longer existed in the source, so the "mutation" was a no-op and a green suite proved nothing | Rewrite each script against the live structure and re-prove it can fail. `check-l10n-duplicates.py` now parses the JSON store with an `object_pairs_hook`, which surfaces duplicate object keys that `json.loads` would silently collapse (the inverse of the old fatal Swift-dictionary case) — verified by injection, red then green. **Standing rule: a verification script is code that can rot. Re-run it and re-inject its mutation after any refactor of the structure it inspects; `TOTAL 0` over `0 unique keys` is the signature of a dead check, not a clean one.** |

**Rule:** a system control is "done" only when its effect has been observed on the real
system — not when the code compiles.

**Corollary — an OS upgrade invalidates measurements, not just code.** Every row in this
table was true when written. After a major macOS bump, re-run the probe for anything built
on a layout side-effect or a private/undocumented behaviour before assuming it still holds.
When a user reports "chức năng X không còn hoạt động", the first move is a **probe that
measures the mechanism**, not a code read — probe 1 here (width clamping) would have led to
the wrong fix; only probe 2 (does the neighbour actually move off-screen?) found the truth. Permission-gated features must state the missing
permission in the UI and link to the exact pane, never fail silently.

**After granting a permission, AX-gated features must re-arm without a manual toggle.**
`DockPreviewController`/`CommandTabController`/`SnapZoneController`/`FinderKeyboardController`/`ClipboardShelfController`/`QuickSearchPanelController` all gate on `WindowManager.isTrusted` inside `applySettings()`. If the trust was false at launch, their event taps are `nil`. The fix (2026-09-17): `AppDelegate.applicationDidFinishLaunching` observes `NSApplication.didBecomeActiveNotification` and re-invokes `applySettings()` on all six — so granting Accessibility in System Settings and switching back to XFinder immediately enables Hover Preview / ⌘-Tab / Snap / Finder Keyboard / Clipboard shelf / ⌘K. Pinboard title colour: `Text(board.name).foregroundColor(board.color.color)` (tint the title, not just the dot); keep the dot, colour both shelf and page.

---

## Part 4: Build constraints (macOS 14.0 target, **SWIFT_VERSION 6.0**, arm64 only)

> **Historical note:** the app originally targeted macOS 12 / Swift 5.8, and several rules
> below were written under those constraints (the `NavigationView`/`NavigationSplitView`
> and `scrollContentBackground` notes especially). Both have moved on — but the existing
> layout is stable and battle-tested, so do not churn it without a reason. The old
> rationale is kept because it explains *why* the current code looks the way it does.

### Swift 6 language mode (adopted 2026-09)

Because `SWIFT_STRICT_CONCURRENCY = complete` had already been running in Swift 5 mode, the
migration cost **two fixes, not a rewrite** — the strict-concurrency pass had already
removed the real races.

| Swift 6 error | Fix |
|:--|:--|
| `sending 'sender' risks causing data races` — `MenubarController.togglePopover` | `performClose(sender)` → `performClose(nil)`. `sender` is a non-Sendable `AnyObject?`; this popover does not use the responder chain, so dropping it changes no behaviour |
| `cannot access property 'db' … from nonisolated deinit` — `DatabaseService` | Deleted the `deinit`: it belonged to a **singleton**, so it never ran and the `sqlite3_close` was dead code. `init` is now `private` so a second instance cannot appear and quietly leak a handle |

**Lesson worth keeping: turn `SWIFT_STRICT_CONCURRENCY = complete` on early.** Under Swift 5
it emits the *same* diagnostics as warnings, so the eventual Swift 6 switch is a handful of
fixes instead of a wall of errors.

~55 warnings remain (actor-isolation notes inside `@objc` / C-callback shims, plus
deprecations: one-parameter `onChange`, `allowedFileTypes`, `AVAsset.tracks`,
`CGWindowListCreateImage`). None are races — Swift 6 now *proves* the `nonisolated(unsafe)`
snapshots are safe, which is exactly why it asks for plain `nonisolated`.
**Do not silence any of them with `@unchecked Sendable`.**

### History: strict concurrency under Swift 5

Turning the flag on surfaced **44 warnings, of which 4 were genuine data races**, all fixed:

| Bug it caught | Why it was real |
|:--|:--|
| `DockPreviewController` captured a `var made` array in a detached `Task` and read it from `MainActor.run` | The background thread kept mutating the array after the actor hop. Fixed by building it in a `nonisolated static` helper that returns one finished value |
| `ClipboardSounds` used `@AppStorage` as a `static var` | Global mutable state, and SwiftUI view state touched off the main thread. Now reads `UserDefaults` directly |
| `ClipboardManager` sent a whole `Notification` into a `Task` | `Notification` is non-Sendable. Now extracts `pid`/`policy` at the observer and sends plain values |
| `MenubarController` sent `sender` across isolation | Same class of bug |

The remaining ~15 warnings are benign AppKit isolation notes (calls into main-actor AppKit
from `deinit` / `@objc` shims), not races. **Do not "fix" them with `@unchecked Sendable`** —
that silences the checker without removing the hazard.

**`@Observable` is now adopted** (target raised to macOS 14 for it). All 23 model classes
use `@Observable`; views use `@State` for owned refs, `@Environment(T.self)` for injected
ones, and **`Bindable(x).prop`** where a `Binding` is needed — `@Environment` has no `$`.

Migration gotchas, all hit for real:

| Symptom | Cause / fix |
|:--|:--|
| `value of type 'X' has no member '$prop'` | Observation has **no Combine publishers**. Non-view observers need a plain callback — `NoteStore.onChange` is the pattern |
| `requires that 'X' conform to 'ObservableObject'` | `.environmentObject(x)` → `.environment(x)` |
| `main actor-isolated property … from a nonisolated context` in `deinit` | These were singleton `deinit`s that **never run**. Deleted rather than silenced; macOS reclaims timers/assertions at process exit |
| 70 deprecation warnings after the bump | macOS 14 deprecates the one-parameter `onChange` closure: `{ v in }` → `{ _, v in }`, `{ _ in }` → `{ }` |

Measured after migration: idle CPU **0.04 s / 90 s ≈ 0 %**, footprint **65 MB** (was 80 MB).
Note the first ~20 s after launch shows ~2.5 % — that is Observation registering the model
graph, not a regression. **Always measure a settled window.**

Grep-verify NO use of these 13+ APIs each phase:
`Gauge` · `.monospaced()` · `Grid{` · `scrollContentBackground` · `symbolEffect` · `NavigationSplitView`.

Replacements in use: `NavigationView + .navigationViewStyle(.columns)`; bars via
`GeometryReader`/`Path`; `Font.system(_, design: .monospaced)` (a `.monospacedDigit()` on a `Font`
is fine); `.onChange(of:)` on arrays requires `Equatable` elements; card colors set explicitly
(no `.scrollContentBackground`). LazyVGrid/GridItem ARE available.

**project.pbxproj is hand-authored classic PBX groups.** Every file add needs FOUR entries:
`PBXFileReference`, `PBXBuildFile`, a group-children line, and a Sources-phase listing line. A
missing `PBXFileReference` silently excludes the file from compilation. Removing a file means
scrubbing all four.

### SwiftData: evaluated, deliberately NOT adopted

The clipboard store is hand-rolled SQLite (`DatabaseService`, an `actor`). SwiftData was
considered and rejected **for this specific store**:

- The workload is an append-mostly log with `WHERE timestamp <` pruning and OCR-text search
  — exactly what raw SQL does well and what an object graph adds nothing to.
- `DatabaseService` is already an `actor` that passes Swift 6 cleanly, so there is no
  concurrency problem left for SwiftData to solve.
- SwiftData owns its own store format; migrating means a data migration for every existing
  user, for zero user-visible gain.

Reach for SwiftData if a future feature needs **relationships + undo + SwiftUI queries**
(e.g. notes with tags/folders and live-filtered views). Do not swap it in for its own sake.

**Tests**: `swift test --package-path Tests` — 53 tests, runs in ~0.01 s, no app launch.

A **Swift package**, deliberately not an Xcode test target: this `.pbxproj` is hand-authored
(four entries per file), and bolting on a second target by hand is exactly the edit that
silently excludes sources. The package cannot corrupt the app project.

Covered: coordinate-space flips, snap-target rects + Stage Manager inset, batch-rename
planning (especially **collisions** — that logic moves real files), clipboard classification,
and the **privacy filter**. Excluded on purpose: anything needing AppKit, Accessibility or a
live pasteboard — a unit test asserting those without a running app and a granted permission
would be theatre.

The pure logic is **duplicated** into the tests because an `.app` target cannot be linked by
a package. That is a real trade-off: the copies can drift. It is accepted only for small
pure functions, and the tests lean on *properties* (flip is its own inverse; quadrants do not
overlap) that survive a rewrite. **Verify a new test can fail** — inject the bug it claims to
catch, watch it go red, then revert. A test that has never failed has proven nothing.

**Build**: `xcodebuild -project XFinder.xcodeproj -scheme XFinder -configuration Debug build` →
`./build/XFinder.app`. Git root is the parent `/Users/wolong/github` (XFinder is untracked `./`).

If the build fails with only `MkDir …/build/XFinder.app` errors (no `error:` on any source
file), that is a **sandbox write restriction on `./build`, not a code error**. Build to a
writable path instead and the same sources compile:
`xcodebuild … -derivedDataPath <tmp>/dd CONFIGURATION_BUILD_DIR=<tmp>/out build`

---

## Part 5: Distribution (GitHub)

Repo: `PyDude9/XFinder`, **MIT** licensed, created **private** — the user reviews before
making it public. The parent directory `/Users/wolong/github` is a *different* repo holding
many unrelated projects: **XFinder has its own `.git` and must never be pushed from the
parent.**

`.gitignore` must keep out `build/`, `build-release/`, `Tests/.build/`, and **any `*.app`
bundle** — a built app belongs on a Release page, never in source control (two stray
bundles, 10 MB, were caught on the first pass).

**Update check** (`Core/UpdateChecker.swift`, surfaced in `AboutView`): one user-initiated,
unauthenticated GET to `/repos/{owner}/{repo}/releases/latest`. No background polling and
no data about the user is sent, so the "zero telemetry" promise holds.

| Trap | Rule |
|:--|:--|
| String-comparing versions | `"1.10.0" > "1.9.0"` is **false** lexicographically — the app would silently stop offering updates after minor version 9. Compare component-wise as integers (`UpdateCheckerTests` pins this; the bug was injected and 5 tests caught it) |
| Tag vs bundle format | Releases are tagged `v1.2.0`; `CFBundleShortVersionString` is `1.2.0`. Normalize the leading `v` or every check reports an update forever |
| No releases published yet | GitHub answers **404**, which is not an error — report "bạn đang dùng bản mới nhất", never a scary failure |
| Hard-coded version in the UI | `AboutView` said "Version 2.0" while `Info.plist` said `1.0.0`. **Always** read `CFBundleShortVersionString`; a literal drifts and breaks the comparison |
| Stale README | The shipped README advertised a "File Browser", "Swift 6" and "GPU temps" — all untrue, and the GPU claim contradicts the Honesty Rule. Public docs are subject to the same honesty standard as the UI |

---

## Deferred (later passes)

Real pages for: folder-lock, sync, remote, quick-share, window-management (preview/snap-zones/menu-icons),
per-app network, network speed test, any future SMC temperature reader.

---

**XFinder: system monitor + clipboard, unified in one lightweight macOS app.**

## macOS 27 — Biểu tượng thanh menu (ghi chú đối chiếu sau này)

Tổng hợp để lần sau KHÔNG đo lại. Mục tiêu: ẩn/bố trí icon menu bar của app khác.

* Cơ chế **dwarvesf/hidden (Hidden Bar)** = một trick duy nhất: 2 `NSStatusItem` —
  nút bấm (`variableLength`) + vạch ngăn (`length = 1` khi hiện, phình lên
  `max(500, min(screenWidth+200, 4000))` khi thu gọn để đẩy icon bên trái khỏi bar),
  dùng `NSStatusItem.autosaveName` để nhớ vị trí kéo. **Đây chính là separator-expansion
  mà XFinder đã đo là chết trên macOS 27** — tham chiếu app không thay đổi kết luận.
* macOS 27: `length = 10_000` bị clamp ~5016pt, và layout KHÔNG còn đẩy item hàng xóm
  (hàng xóm dịch sang PHẢI 952→988, vẫn ONSCREEN sau 7s).
* `NSStatusItem.isVisible` CHỈ ẩn item của chính app — công khai, hoạt động tốt.
* `MBAssessmentModeAssertion` (Pelmet / Assessment Mode) chỉ ẩn module Control Centre
  (WiFi/Bluetooth…), KHÔNG ẩn `NSStatusItem` của app thứ ba.
* XPC `com.apple.MenuBarAgent.systemservices` (`setItems:`/`setGloballyHidden:`): chặn
  binary ad-hoc (lỗi 4097). Có thể nhận dev-signed — chưa thử (keychain 0 chứng chỉ).
* `CGWindowListCopyWindowInfo` trả 0 window ở lớp status-item → không quan sát được icon
  của app khác để work-around.
* macOS 26+ chuyển việc ẩn/hiện icon HỆ THỐNG vào Control Centre → Menu Bar (đường native
  XFinder hiện đưa người dùng tới). Không có API công khai nào ẩn icon app THỨ BA.

### Vòng điều tra Thaw (2026-09-18) — KẾT LUẬN: vẫn không làm, và đây là lý do

Người dùng báo "Thaw beta 3 đã ẩn được icon rồi, học họ đi". Đã điều tra đầy đủ. **Tiền đề
không đúng** — và quan trọng hơn, đã tìm ra *nguyên nhân gốc* vì sao cả họ nhà app này chết
cùng lúc.

**Ranh giới giấy phép (giữ nguyên như vòng pelmet).** Thaw = **GPL-3.0**, Ice = GPL-3.0.
**KHÔNG đọc source của chúng** — sẽ nhiễm sang XFinder (MIT). Chỉ đọc README + discussion
công khai (ý tưởng/sự thật, không phải biểu đạt có bản quyền). `SaneBar`, `furl`, `tuck` là
**MIT** → đọc trực tiếp được, và đó là nơi lấy được chi tiết kỹ thuật thật.

**Nguyên nhân gốc — đo trực tiếp trên máy này (macOS 27.0, 26A428):**

| Probe | Kết quả |
|:--|:--|
| `CGWindowListCopyWindowInfo` lớp 24 | **1 window duy nhất mỗi màn hình**: owner `Window Server`, name `Menubar`, 1728×33 |
| `CGWindowListCopyWindowInfo` lớp 25 (status-item cũ) | **0 window** |
| `osascript … menu bar 2` | lỗi **-1728** "Can't get menu bar 2" |
| Process | `/System/Library/CoreServices/MenuBarAgent.app` **tồn tại** (macOS 26 không có — bar do ControlCenter lo) |

Tức là: trước macOS 27 mỗi status item là **một window riêng** nên app thứ ba enumerate /
capture / move / hide được (kể cả khi đã đẩy ra ngoài màn hình vẫn địa chỉ hoá được — chính
điều này làm separator-trick khả thi). macOS 27 gộp **toàn bộ bar thành MỘT window**, không
còn handle cho từng icon. Đây là lý do Bartender · Ice · Thaw · Barbee · Sane Bar · Glow ·
Hidden Bar · BTT **chết đồng loạt**, không phải lỗi riêng app nào.

**Trạng thái thật của Thaw trên macOS 27** (discussion #737 của chính họ, Preview 1→4):
items nhân bản / bật lại / biến mất khi kéo; **con trỏ bị kéo về thanh menu**, icon tự chạy
("almost feels as if it was malware", chỉ hết khi quit Thaw); click/hover-to-reveal hỏng;
Finder crash khi kéo icon. Tester đánh giá trái chiều hẳn nhau. **Đây không phải tính năng
chạy được để học theo.**

**Không ai công bố cơ chế.** BTT (Hegenberg) chỉ nói tìm được "two possible ways forward",
**không nêu tên API nào**, kèm cảnh báo "both ways are not official, so Apple might block
them at any time". Bartender Golden Gate: tính năng macOS-27 duy nhất là "Disabled Items" —
chỉ **phát hiện** icon mà user đã tự tắt trong Control Center, gắn nhãn "experimental", và
tự nói không show/hide được chúng.

**`SaneBar` (MIT, đọc được) xác nhận ngay cả thời Tahoe cũng không có API:**
`kAXPositionAttribute` **read-only** với menu bar item · `NSStatusItem.preferredPosition`
**không tồn tại** · ghi tay UserDefaults `NSStatusItem Preferred Position` **macOS bỏ qua** ·
`AXUIElementSetAttributeValue` **trả lỗi** với status item. Nên họ phải **giả lập ⌘-drag bằng
CGEvent** (16 bước ~240ms, ẩn con trỏ) — chính là nguồn gốc bug "con trỏ bị kéo" ở Thaw.
Tự đánh giá của họ: *"This will always be fragile."* README SaneBar **không** claim hỗ trợ
macOS 27; nó nêu macOS 27 là lý do **dừng dự án**: *"macOS 27 breaks every menu bar manager."*

**Quyết định (user chốt 2026-09-18): giữ trang explainer, KHÔNG implement.** Ship một toggle
dựa trên cơ chế chưa ai xác minh được sẽ vi phạm Honesty Rule — đúng loại "control không làm
được điều nhãn nó hứa" mà Part 0 §6 cấm. `MenuBarHiderController.applySettings()` vẫn
`remove()`; trang vẫn giải thích giới hạn + link Control Centre → Menu Bar.

**Khi nào xem lại:** macOS 27 ra bản chính thức (hết beta) và có app *ổn định* (không phải
preview) chứng minh ẩn được icon app thứ ba. Lúc đó đọc lại discussion #737 + release notes
BTT/Bartender. **Đừng đo lại 4 probe ở bảng trên** — chúng đã xác nhận kiến trúc single-window.

## Vòng sửa 5 lỗi + tối ưu (ghi nhanh)

* Độ sáng %: nguồn đọc thật trên Apple Silicon macOS 27 (IORegistry rawBrightness,
  CoreDisplay, DisplayServices — probe tự viết) HOẶC kẹt HOẶC trả -1/false, không
  có nguồn realtime. Giải pháp trung thực: % bám theo vị trí slider (đúng vì NX
  keys đã đưa phần cứng về đó); ScreenBrightness giữ `level` riêng + chỉ nhận
  re-read khi registry CHUYỂN giá trị (tránh kéo ngược về số ảo).
* ⌘Tab không đổi app: `raiseWindow` chỉ AXRaise + activate(options:[]) — thiếu
  kAXFrontmost + activateAllWindows. Đã bổ sung. Snap drag: nhận diện title-bar
  giờ walk-up cha tới 4 cấp + đổi toạ độ theo màn hình chứa con trỏ (hết lỗi
  multi-display).
* Biểu tượng thanh menu: bỏ kiểu "explainer chỉ đọc", cài cơ chế Hidden Bar thật
  (nút mũi tên + separator NSStatusItem, autosaveName, length 1↔max(500,min(màn+200,4000))
  bằng public API) — kèm ghi rõ giới hạn macOS 27 đã đo.

## BẢN CHUẨN HIỆN TẠI (reconcile cuối phiên 1.1.0)

Tóm tắt trạng thái THỰC của code lúc này (ghi đè mọi mô tả cũ mâu thuẫn):

* **Tìm kiếm + Bảng lệnh**: `Core/QuickSearch/` (QuickSearchEngine, AppLauncher, Calculator,
  Quicklinks, FileSearch via NSMetadataQuery, QuickSearchPanelController hotkey Carbon).
  Panel toàn cục ⌘K (đổi phím được) + khối Tìm nhanh trong trang Tìm kiếm (dùng chung engine).
  KHÔNG còn trang Command Palette riêng. Cấu hình palette nằm trong card "Phím tắt toàn cục"
  của trang Tìm kiếm (key `quickSearch.enabled`).
* **Clipboard**: sidebar CÔNG CỤ = `settingsClipboard` ("Cài đặt Clipboard") duy nhất; nội dung
  ở khay ⌘⇧V + trang `.clipboard` (vào bằng nút "Mở lịch sử…" hoặc ⌘⇧C). Có `.markdown`,
  kéo-thả vào bảng đổi màu (`pinboards` + `pinnedColor`).
* **Biểu tượng thanh menu**: MenuBarHiderController hiện **TẠM TẮT** (applySettings = remove) —
  separator-expansion chết trên macOS 27, cover che cả thanh menu bên phải nên đã tắt. Trang
  giải thích giới hạn macOS 27. Icon menubar = màu xanh (kính lúp), bộ chọn ở Tổng quan.
* **Khay thả**: bỏ Notch, không auto-close (chỉ nút Close). DropOver: stack + nút "Xem chi tiết"
  mở cửa sổ lưới (cap 400).
* **Ghi chú**: NoteStore + EdgeNotesController (dải mép, ghim lên trên cùng), font notes.font,
  hotkey ⌥⌘N/L/P, nhập/xuất MD/TXT/JSON. Editor đã Việt hoá + tự focus.
* **Độ sáng**: % theo slider (registry kẹt, không đọc lại được trên Apple Silicon).
* **Ngôn ngữ**: L10n — **đã quét hết `XFinder/Views/`, 0 literal Việt chưa quấn**. App icon = AppIcon.icns.
* **Finder Sync extension**: target `XFinderSync.appex` (nhúng, URL xfinder://droptray-add).
  **Đã đăng ký và chạy thật** (2026-09-22): `pluginkit` liệt kê
  `+ com.xfinder.app.XFinderSync(1.0)` trỏ `/Applications/XFinder.app/Contents/PlugIns/XFinderSync.appex`.
  Ba nguyên nhân cũ đều đã sửa: appex để `MACOSX_DEPLOYMENT_TARGET = 27.0` (nay 14.0,
  khai `LSMinimumSystemVersion` tường minh), appex sinh `.debug.dylib` do
  `ENABLE_DEBUG_DYLIB` (nay NO), và script ký xoá mất entitlement sandbox của appex
  (nay ký kèm entitlements, app ngoài **không** dùng `--deep`).
  Người dùng vẫn phải tự bật trong System Settings ▸ Login Items & Extensions ▸ Finder.

## Menu Bar Icons re-probe — 2026-09-18 (current implementation)

Explicit user request supersedes the earlier “do not re-probe” decision above.
`applySettings()` now honors `menubar.hiderEnabled` (default false); an opt-in,
clearly labelled experimental arrow and separator replace the unconditional remove.
The overlay-window workaround is removed: it covered the wrong side.
`collapseRequested` describes a request, never verified visibility. Command-drag
positions the arrow beside XFinder and hidden candidates left of the separator.

Fresh probe on macOS 27.0 (26A428): separator widths 1/1928/600/800/300/1 pt;
test neighbour x = 1056/1056/1056/1056/1048/1039, width 48 pt. Repeating with
four extra 480-pt separators also left the test frame in screen bounds. This is
frame evidence only: screencapture failed (`could not create image from display`).
Neither isVisible=true nor an on-screen local window frame proves rendered
visibility on this OS. Other apps' actual hiding is NOT verified; do not infer
that all other mechanisms are impossible from this separator probe.

The actual controller was compiled into an isolated AppKit harness: install,
idempotent apply, performClick collapse/expand and disable cleanup passed.
Debug app build succeeded; compile log includes MenuBarHiderController.swift,
MenuIconsDetailView.swift and L10nStrings.swift; lipo reports arm64. Views VI
literal lint: TOTAL 0. This does NOT certify Bartender-like behaviour on macOS 27.
Verification logs and build: /tmp/xfinder-menu-verification (temporary, not git).

Mutation check: restoring unconditional `remove()` in a scratch controller failed
the harness with exit 133 (items not installed), proving detection of the original bug.

## Mouse gestures module

- Source: `Core/MouseGestures/{GestureModel,GestureEngine,GestureController}.swift`;
  sidebar `mouseGestures` → `MouseGesturesDetailView`. User job: bind a hold trigger
  and inspect/customize the exact shortcut sent by each direction per app.
- Opt-in key `mouseGestures.configuration.v1` stores Codable settings/overrides.
  Default: disabled, Button 2, deadzone 12 raw delta units, tilt/debug off.
- Dedicated serial userInteractive queue + CFRunLoop; no main-thread event callback.
  Worker state is queue-confined. Locked inbox carries commands; UI/persistence is
  MainActor. No per-motion Task, pointer polling or unbounded debug-log queue.
- Unknown actions are Unassigned, not fabricated app commands. Known profiles do
  not fall through to Global for unassigned directions. Trigger is shared across
  devices by event button ID, not per-device HID identity; re-record on swap if needed.
- Tests compile the actual pure model through a symlink. The standalone runtime
  harness compiles the actual callback with a memory-only event sink. Commands,
  mapping table, limitations and measured evidence: `docs/MOUSE_GESTURES.md` and
  `docs/GESTURE_VERIFICATION.md`. Keep those docs in sync when changing mappings.
- Important permission distinction: the terminal-hosted live probe can open a tap,
  while the new ad-hoc XFinder app can still fail. Never claim app-level gestures
  are verified from the probe's grant or a successful build alone.
