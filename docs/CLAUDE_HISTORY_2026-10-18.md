# XFinder — lịch sử CLAUDE.md đầy đủ (ảnh chụp 2026-10-18)

Đây là toàn bộ `CLAUDE.md` cũ (494 KB, 102 mục, 2026-09 → 2026-10-18) được chuyển nguyên văn sang đây khi `CLAUDE.md` được rút gọn thành bản chỉ-luật. **Đừng đọc hết** — grep theo tên tính năng, mã bước (B1, D4, P7b…) hoặc từ khoá (`giật`, `TCC`, `SIGPIPE`). Mỗi mục giữ nguyên bài học + phép đo + danh sách chưa verify của nó. Phần sau mốc này được ghi tiếp trong `CLAUDE.md` mới (mục 7) và các commit message.

---

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
was never public (SMC temperatures, the SMART attribute table), ship an explainer and a link to what *does* work. Never
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

*Architecture — **one** store, keyed by the Vietnamese literal so call sites read naturally:*

| Piece | File | Holds |
|:--|:--|:--|
| `L10n.strings.json` | `XFinder/Resources/` | every entry: `{ "en": …, "scope": "sentence" \| "fragment" }`, optionally `"swap": true` |
| `L10n.allowlist.json` | `XFinder/Resources/` | strings that are identical in both languages **on purpose** — proper nouns (`Mission Control`, `Quick Look`, `OCR`, `App Exposé`…) |
| `L10nStore` | `Core/L10nStore.swift` | loads the JSON and splits it into `sentences` / `fragments` by `scope` |
| `L10n.t(_:)` | `Core/L10n.swift` | looks in `fragments`, then `sentences`, then **falls back to the Vietnamese** |

The earlier **three-dictionary design (`L10nDB` / `enDict` / `moreDict` / `fragDict`) was removed**,
and the reason is the leak itself: with three Swift dictionaries *nothing said where a new string
belonged*, so a new string usually belonged to none of them — and because `t()` falls back to
Vietnamese, the English UI silently showed Vietnamese while the build stayed green. `scope` makes
that a property of the **data** instead of a property of the file the string happens to live in, and
one store means one thing to lint. Do not re-introduce the extra dictionaries; if a string needs a
new *kind*, add a `scope` value and a gate for it.

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
sentence read correctly in both languages. `scope: "fragment"` is what keeps them apart from
full sentences, so a fragment can never shadow the full-sentence translation of the same words.
A string that is concatenated with a runtime value **must** be declared `fragment`:
`check-l10n-coverage.py` rejects edge padding on a `sentence`, so decide the scope from the call
site, not from how the string reads.

*Markdown-bearing strings* (`**bold**`) must reach a `Text(.init(…))` / `LocalizedStringKey`,
or the asterisks render literally. Use `L10n.md(_:)` for a bare `Text`; helpers that already
do `Text(.init(t))` — e.g. the `note(_:)` in the Sync/Remote/Share pages — take plain
`L10n.t()`.

*The lint.* This must print `TOTAL 0` before any language work is called done. The repo ships
the same sweep as `scripts/audit-l10n-literals.py` (run as §2 of `scripts/verify-gesture-ui.sh`);
the inline version below is what to run when the script is not at hand:

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

*A string that reaches the screen through `L10n.t(variable)` is protected by **no** literal sweep.*
This is the leak that survived four fixes: the call site is correct, but the key lives in a
*model* file, so `audit-l10n-literals.py` only sees it as an unwrapped literal elsewhere and
`check-l10n-coverage.py` only compares the store with itself. Two gates close it, and both must
run:

* `scripts/check-sidebar-groups-l10n.py` — parses the `groups` declaration in
  `SidebarDestination.swift` and fails if it resolves fewer than 4 headings (guards against a
  rotted anchor). Six sidebar headings leaked this way.
* `scripts/audit-gesture-vocabulary-l10n.py` — parses the gesture module's own declarations
  (`labelKey`, `namedKey(…)`, `static let all`) and resolves every key against the shipped store.
  Five model captions leaked this way.

The full battery, all of which must be green before language work is called done:

```sh
python3 scripts/check-l10n-coverage.py            # store: no missing/identical en
python3 scripts/check-l10n-duplicates.py          # no duplicate object keys in the JSON
python3 scripts/audit-l10n-literals.py            # VI literals not wrapped in t()
python3 scripts/check-sidebar-groups-l10n.py      # variable-passed sidebar keys
python3 scripts/audit-gesture-vocabulary-l10n.py  # variable-passed model keys
python3 scripts/verify-l10n-runtime.py            # resolves against the store in the INSTALLED bundle
```

`verify-l10n-runtime.py` is the one that measures the *shipped* app rather than the tree: it reads
`/Applications/XFinder.app`, so it is the gate that would have caught a store that never made it
into the bundle. Measure the rendered page too — `docs/probes/probe-ax-dump.swift <pid>` reads the
real text nodes in both languages, which is how six sidebar headings were found after three literal
sweeps had reported `TOTAL 0`.

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
probes (SMC temperatures, `nettop` per-app network, SMART attributes) is deliberate:
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
| CỬA SỔ | windowPreview · snapZones · menuIcons (macOS now owns this — see Part 3) |
| FINDER & TÌM KIẾM | finderKeyboard · finderActions · finderSearch · aiSearch · **batchRename** · **actionHistory** |
| CÔNG CỤ | **clipboard** · settingsClipboard (renamed "Cài đặt Clipboard") · notes · dropTray · compress · pdfTools · folderLock · **mouseGestures** |
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

Per-page managers start `.onAppear` and stop `.onDisappear` so idle CPU stays 0%. Calling a
`@MainActor` method from a non-isolated Timer closure requires `Task { @MainActor in … }`.
**App-lifetime controllers** (Caffeine, ClipboardShelf, QuickSearchPanel (⌘K), EdgeNotes, DockPreview,
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
| **Hệ thống** (system) | flat layout: CPU/GPU **temp row → "Đang thu thập…"**, `MeterRow` CPU % + sparkline (real), `MeterRow` GPU % + sparkline (**real** — IORegistry `IOAccelerator/PerformanceStatistics/Device Utilization %`; nil ⇒ "Không khả dụng", never 0), memory table (used/total, áp lực, nén, cache, swap) + sparkline, uptime, per-core bars in a `DisclosureGroup` |
| **Mạng** (network) | **compact**: ↓/↑ live rates (KB/s under 1 MB/s, MB/s above), physical interface, "Ứng dụng dùng mạng" auto-sampling every 2s while the page is visible (cancelled on disappear), session total, "Đo tốc độ" button (Cloudflare 25 MB). No per-interface table, no sparkline wall |
| Per-app network | sampled via `nettop -P` (labeled ≈) | cumulative counters only, no public real-time per-process API — honest sample, not a fake live chart |
| **Ổ đĩa** (storage) | volume picker + usage bar (real), I/O KB/s + sparkline (real), SMART → "Không khả dụng trên phần cứng này" |
| **Pin** (pin) | battery %/time/charging (real), health % + cycle count + watts (real), battery temp → placeholder; no-battery → "Không có pin" |
| **Clipboard shelf** (⌘⇧V, global) | `Core/ClipboardShelfController.swift` — **⌘⇧V now opens a floating bottom shelf over whatever app you are in**, not the in-app page. `.nonactivatingPanel` + `.floating` so the previous app keeps focus and the paste returns to it; `NSVisualEffectView` vibrancy; horizontal `LazyHStack` card deck. Keys: ←/→ select · ↩ paste · ⇧↩ plain text · ⌘1–9 direct · Space Quick Look · Esc close. Global hotkey = CGEvent tap (AX-gated — the same grant pasting already needs) |
| **Clipboard** (page) | PasteApp-style deck (`ClipboardTabView` + `ClipboardCardView`): app-icon accent headers, code/color/link/file/image bodies, keyboard map (Return/⇧Return/Space/⌘P/⌘F/⌘⌫/⌘1-9/Esc), Space Quick Look, Paste Stack queue, event-driven ingest with privacy filter (Concealed/AutoGenerated/Transient + password-manager bundle IDs), disk-offloaded payloads + Vision OCR search, history hydrated from SQLite, ⌘⇧V/⌘⇧C in-app hotkeys |
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
| **Khay thả** (dropTray) | Page: drag shelf (`.onDrop` + persisted paths) with move/copy/ZIP/trash/open-all, an inline grid, and **"Mở khay từ notch"** — three live switches (`dropTray.notchDropEnabled` / `hoverEnabled` / `shakeEnabled` + `shakeSensitivity`). The floating surface is **`Core/Notch/NotchSurfaceController`** (B1, replaced `NotchDropController`): collapsed badge · peek · expanded hub, decided by the pure `NotchSurfaceMachine`. See *Notch surface — B1* at the end of this file. Finder Sync Extension (`XFinderSync.appex`) talks to it via `xfinder://droptray-add?path=…` → `reveal()`. |
| **Đồng bộ thư mục** (sync) | **now real** (`Core/FolderSyncController.swift`) — one-way mirroring via incremental `rsync -a`. Triggers: manual, on-change (`DispatchSource` watch on the source with a 3 s debounce so an edit burst produces one run), and daily at a chosen hour. `--delete` is **off by default** and warns in red, since it deletes permanently rather than to the Trash. Guards against source == dest and a dest nested inside the source (infinite recursion). Two-way sync is deliberately NOT offered — it needs conflict resolution and a change journal, and a half-built version loses data |
| **Khóa thư mục** (folderLock) | **now real** (`Core/FolderLockController.swift`) — AES-256 encrypted **sparsebundle** via `hdiutil` (`-stdinpass`). Locked = detached (ciphertext on disk); unlocked = mounted + opened in Finder. The original folder is only **trashed** (never `rm`) after the copy is verified by entry count. No password is ever persisted. Deliberately *not* `chflags hidden`, which is trivially reversible and would be dishonest to call "locked" |
| **Quick Look** (quickLookPage) | improved previewer: Markdown renders to HTML via WKWebView, archives list entries (`unzip -Z1`/`tar -tf`), anything else falls back to the native `QLPreviewPanel` |
| **Tương thích media** (mediaCompat) | AVFoundation openability check per file: track presence + codec FourCCs, "Phát được/Không" verdict |
| **Tiện ích Finder** (finderUtils) | Own file `Views/Detail/FinderUtilsDetailView.swift` (moved out of `FinderToolDetailViews.swift`), flat layout: a **Trạng thái tích hợp** checklist that reports each Finder surface honestly — "Thao tác trên mục đang chọn" = Đã bật, "Tác vụ nhanh trong menu chuột phải" = **Chưa có**, linking to the Extensions pane because that needs a Finder Sync/Action extension target this app does not ship — then readback + apply of supported `com.apple.finder` keys (extensions / hidden files / path-in-title) with a `cfprefsd` flush before the Finder restart, then a plain-language list of what XFinder adds |
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
| GPU % | **shown** — this row was WRONG until 2026-10-09 | `IOAccelerator/PerformanceStatistics/Device Utilization %` is a plain `IORegistryEntryCreateCFProperty` read, no entitlement. Measured: idle 0–22 %, Metal compute burn 99–100 %, ~1.5 % after. Placeholder only when the key is absent (`GPUUtilization.percent(from:) == nil`) |
| Per-app network (sampled) | top-10 qua `nettop -P`, dán nhãn "≈" | no public API (was `nettop`, dropped) — restored as labeled sample |
| Disk SMART | "Không khả dụng trên phần cứng này" | SMART not exposed via public API |
| Screen brightness % | step −/+ only, no number shown | no public API to read or set the value; keys are synthesized, value unreadable → number never faked |
| Menubar-icon hiding — *other apps' icons* | explainer + link to Control Centre → Menu Bar | **No mechanism left on macOS 26/27.** No API can hide another app's status item, and the separator-expansion workaround stopped working (measured — Part 3c). The page installs no status item and says so |
| CPU per-process list ("which app is using CPU") | **removed from Hệ thống** | Activity Monitor already does it better (sortable, killable, per-thread) and sampling it cost a `top -l 2` subprocess every few seconds. Hệ thống answers "how is the machine doing", not "which app is misbehaving". `ProcessSampler.swift` was deleted with all four pbxproj entries |
| Finder context-menu items | link to the Extensions pane | adding items to Finder's right-click menu needs a Finder Sync Extension target; `finderActions` instead acts on the current Finder selection |
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
| Khay thả popped open on **any** mouse drag (text selection, window move) | The tick only checked `pressedMouseButtons`, and an "auto-open on file drag" shortcut had been added on top | **Every** open path requires a real file drag, and hover only reveals files already held, never an empty tray. **The original `dragCarriesFiles()` fix was itself incomplete** — see the next row |
| **The drag pasteboard keeps the last file drag forever** (found 2026-10-10, B1) | `NSPasteboard(name: .drag)` is not cleared when a drag ends. Measured with no button down, 77 min after the last drag: types still `public.file-url` + `com.apple.finder.node`. So reading its types alone says "files!" for every later press — a window dragged by its title bar, a text selection. Only the shake requirement hid it; "drag into the notch" would have exposed it at once | `NotchDragSession`: remember the pasteboard `changeCount` at **mouse-down**; trust its types only once a NEW drag session has written to it during this press, then cache the verdict for the press. 6 tests, mutation M1 red |
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
| **Finder Sync extension had NEVER registered or loaded — three independent causes, all silent** | `pluginkit -m -p com.apple.FinderSync -v` listed six other apps and **no XFinder entry**, Finder showed no XFinder menu, and the appex segfaulted in `ImageIO`/`CFBundleGetInfoDictionary`. Found by comparing against a working extension (MFinder, Keka) rather than reading our own code. (1) The appex target had `MACOSX_DEPLOYMENT_TARGET = 27.0` while the host app is 14.0, so `GENERATE_INFOPLIST_FILE` wrote `LSMinimumSystemVersion = 27.0` into the appex Info.plist — macOS refuses to register an extension whose minimum OS exceeds its container's. (2) The appex built with `ENABLE_DEBUG_DYLIB` (Xcode 16+ Debug default) shipping a loader stub + `XFinderSync.debug.dylib` + `__preview.dylib` instead of one real binary; working extensions ship a single executable. (3) `install-mouse-rebuild.sh` re-signed the appex with a bare `codesign --force`, which **drops** the sandbox entitlement the target builds with (`ENABLE_APP_SANDBOX = YES`) — `pkd` then logged "Final plugin count: 5" and refused ours. The same script also signed the outer bundle `--deep`, re-signing the appex under the OUTER identifier and collapsing `com.xfinder.app.XFinderSync` into `com.xfinder.app` | Fixed all three: deployment target 14.0 + explicit `LSMinimumSystemVersion` in `XFinderSync/Info.plist`; `ENABLE_DEBUG_DYLIB = NO` on both appex configs; the install script writes the appex entitlements file, signs nested content explicitly, signs the outer bundle **without** `--deep`, and hard-fails if the appex loses its identifier or sandbox entitlement. **Measured after**: `pluginkit` shows `+ com.xfinder.app.XFinderSync(1.0) … /Applications/XFinder.app/Contents/PlugIns/XFinderSync.appex`, the extension process is alive and stable, no new crash report. Also: **every intermediate build directory registers the same plugin identifier** — 16 dead paths (staging, `/tmp`, DerivedData, a Desktop copy) all claimed `com.xfinder.app.XFinderSync` and blocked resolution; the script now deregisters build/staging copies and `pluginkit -a` the installed one. `codesign --verify --deep` hides all of this because it only checks the outer bundle. The user still has to enable the extension in System Settings ▸ Login Items & Extensions ▸ Finder; no app can do it for them, so the script prints the measured state (`!` registered-not-enabled, `+` enabled) instead of implying success |

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
* **Khay thả**: sống ở **notch** từ B1 (`Core/Notch/`). Lắc mở khay tại con trỏ và khay đang giữ tệp
  không tự đóng; ở notch khay thu về badge đếm tệp. "Xem chi tiết" mở cửa sổ lưới (cap 400).
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
## Menu Bar Icons: Native Visibility Engine (macOS 27+ Assessment Mode)

**Architecture**:
- Framework: Private `/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore`.
- Shim: `XFinder/Core/MenuBar/Native/HBNativeVisibilityShim.{h,m}` invoking `MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion`.
- Engine: `NativeVisibilityEngine.swift` (macOS 27+) and `LegacyLengthEngine.swift` (fallback).
- Controller: `MenuBarHiderController.swift` with auto-hide timer and startup collapse.

**Critical Rules & Lessons Learned (DO NOT REGRESS)**:
1. **`allowedBundleIdentifiers` MUST contain ONLY visible bundles**:
   `allowedBundleIdentifiers` is an allowlist for items that stay VISIBLE.
   Passing `layout.bundles(in: [.visible, .hidden])` or `runningApplications` allows EVERY app to be displayed, causing macOS to hide 0 icons.
   Always pass `layout.bundles(in: [.visible])` (plus own bundle).
2. **`NSStatusItem.button?.window?.frame` returns (0,0) on macOS 14+ / 27**:
   Because `NSStatusBarWindow` is remotely hosted by `MenuBarAgent`, local window frames have origin `(0, 0)`.
   Using `button.window.frame.midX` yields ~14.0, which incorrectly places all menubar icons (x > 1000) into `.visible`.
   The arrow's authoritative screen position MUST be resolved via Accessibility (`AccessibilityMenuBarInventory.ownStatusItemFrame(matching:)`).
3. **Initial Collapse at Launch (`attemptInitialCollapse`)**:
   At app launch, WindowServer status items register asynchronously. A single fixed delay can fail if AX has not yet populated the status item child. Use `attemptInitialCollapse(retriesLeft: 4)` which retries every 0.6s until the boundary resolves and collapse succeeds.
4. **Auto-Hide Timer in `RunLoop.common`**:
   Timers in `RunLoop.Mode.default` stall during event tracking or modal interactions. Always add the auto-hide timer to `RunLoop.main` in `.common` mode. Check `isMouseInMenuBar()` before collapsing and re-arm if the mouse is hovering.

## Mouse gestures module

- Source: `Core/MouseGestures/{GestureModel,GestureEngine,GestureController}.swift`;
  sidebar `mouseGestures` → `MouseGesturesDetailView`. User job: bind a hold trigger
  and inspect/customize the exact shortcut sent by each direction per app.
- Opt-in key `mouseGestures.configuration.v1` stores Codable settings/overrides.
  Default: disabled, Button 2, deadzone 12 raw delta units, tilt off, debug off.
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

### Buttons are named by NUMBER (2026-09-22) — do not re-invent physical names

`TriggerSource.buttonName(n)` returns **`Nút \(n + 1)`** (slash numbering: macOS
counts from 0, the user counts from 1), with a short factual note on 0/1/2 only
(`Nút 1 (chuột trái)` / `Nút 2 (chuột phải)` / `Nút 3 (bấm con lăn xuống)`).
`TriggerSource.numberedName` is the number alone, for the diagram's arms.

**Why, in order, because this reversed once:** round 2 named the physical control
(`Nút hông sau — nút 4`) because the user said a bare number was unreadable; the user
then reversed it (*"Hãy đặt tên nút theo số đi"*). The reversal was right for a
measured reason: `CGEventField` has five mouse fields and the highest index is `3`
(`mouseEventButtonNumber`) — **there is no vendor/product/device field**, so no code
path can know which physical control a number maps to. `IOHIDDeviceCopyMatchingElements`
over-matches (a probe printed “873 input-button elements” — a probe defect, not a
button count). A physical name is an **assertion about a layout nothing measured**;
the number is always true.

Where round 2's complaint is still answered: the number is **printed on every arrow**
(`Nút 3 ↑`) and in every detail heading (`Nút 3: kéo lên`, via
`GestureDirection.title(trigger:)`). Never render a bare `↑` as a heading.

`testTriggerLabelsNameButtonsByNumber` pins the `+1` offset for 1...31;
`testEveryDirectionHeadingNamesTheHeldButton` pins that each heading contains the
trigger's `numberedName` and that no heading says “giữ nút” without naming it.

### Global sends page/item navigation, NOT Mission Control (2026-09-22)

The user called the old Global *"hơi vô dụng"*. Root cause, confirmed against
Logitech's own docs rather than guessed: the **MX Master 3 already binds Mission
Control to its thumb button** in Logi Options, so Global `⌃↑` repeated a binding the
user already had. Global is now `⌘⇧]` / `⌘⇧[` / `⌘[` / `⌘]` plus `⌘=` / `⌘-` for tilt.

**The old `⌃↑ ⌃↓ ⌃← ⌃→` mapping is gone, not shadowed** — a test asserts each old
binding is now unequal to what Global sends, so a partial revert cannot hide.

### `tiltAvailable` — an honesty switch, distinct from `tiltEnabled`

`MouseGesturesDetailView.hasTiltHardware` used to be `private var … { true }`, so two
tilt arms were drawn on hardware that can never fire them. Measured with
`DeviceCapabilityProbe`: **every** scroll event from the Razer Basilisk *and* the
Apple Magic Mouse reports `scrollWheelEventIsContinuous = 1, axis2 = 0`, and
`GestureEngine` requires `IsContinuous == 0 && DeltaAxis2 != 0` on purpose so it never
steals trackpad scrolling. Two of the user's three mice therefore could not fire it.

* `tiltAvailable` (default **false**) — whether the page **reveals** the tilt arms.
* `tiltEnabled` — whether the **engine** reads them.

Revealing and enabling are independent on purpose (`testTiltArmsAreHiddenByDefault`
asserts both, including that revealing does not enable). The page's `tiltRow` states
what was measured and that XFinder cannot probe the hardware itself, and names a mouse
that *can* work (MX Master + Logi Options) so the user is not told "unavailable" with
no remedy.

### Kitty / Terminal profile (2026-09-22) — the gap in the daily-driver list

`net.kovidgoyal.kitty`, `com.apple.Terminal`, `com.googlecode.iterm2` → **only**
`⌥←` / `⌥→` (word backward/forward). Kitty, Terminal and iTerm2 all set
`macos_option_as_alt` **off** by default precisely so those arrive as
Option-Left/Option-Right, and AppKit's `moveWordBackward:` / `moveWordForward:` are
standard bindings — so this is a real convention, not a guess. Everything else stays
Unassigned deliberately: `⌘T` is a new *window* in Terminal, `⌘W` can **kill a running
command**, and there is no shared “next pane” key. A wrong keystroke in a terminal
destroys work.

### A resource in the pbxproj is FOUR entries too, and the compile check cannot see it

`L10n.allowlist.json` had **zero** `project.pbxproj` references. It happened to work
because only the test package reads it, and the installed app carried a stale build —
the same silent-exclusion shape as a source file missing its `PBXFileReference`.
Build before believing. A **resource** needs `PBXBuildFile` + `PBXFileReference` +
group-children line + **`PBXResourcesBuildPhase`** line, with `sourceTree = SOURCE_ROOT`
and a full `XFinder/Resources/…` path. `scripts/build-and-check.sh` now also checks the
**built bundle** for both resource files, because a resource never appears in
`XFinder.SwiftFileList` and so the by-name check cannot catch it.

### The gates for this module

```sh
sh scripts/build-and-check.sh              # build + compile-log-by-name + resources + lipo
cd Tests && swift test                     # 97 tests
sh scripts/mutation-check-gesture-labels.sh  # 5 injected gesture bugs, all must go RED
sh scripts/mutation-check-l10n.sh            # 6 injected L10n bugs, all must go RED
sh scripts/verify-l10n.sh                    # the whole language suite, incl. runtime
```

**A mutation that stays GREEN is a finding.** `mutation-check-l10n.sh` case 5 stayed
green on the first run of this pass: the heading is assembled at runtime from
`numberedName` **plus** a hint fragment (`"kéo lên"`), and the test only probed the
*whole* assembled sentence, which was still in the store. Deleting the hint left the
English page rendering `Button 3: kéo sang trái` with a fully green suite. Fixed by
`L10nFixture.directionHint(_:)`, which **derives** the hint from the real functions
rather than a hand-written table so it cannot drift.

When you add a gesture string: it goes in `L10n.strings.json` with the right `scope`
(`fragment` for the hint half, `sentence` for a whole heading), and
`scripts/add-gesture-l10n-entries.py` is the idempotent place to declare it.

### Report four results separately, always

**Build success / automated tests / Event Tap activation / physical-mouse behaviour**
are four different things. The first three are verified in `GESTURE_VERIFICATION.md`
Round 4; **physical mouse behaviour is still unverified** and needs the user's hand on
their three mice. `screencapture` fails on this host, so no claim about how the page
*looks* is checkable either.

### The mutation scripts CAN leave the working tree mutated (2026-09-22) — checked first

Found at the start of this pass: `GestureModel.swift` on disk held **mutation M1 already
applied** (`default: return "Nút hông sau — nút \(n + 1) (Button \(n))"`), uncommitted. A
previous mutation run was killed between `mutate` and `restore`, so **the installed build
contained the bug the mutation was meant to simulate** — i.e. the shipped app really did
render `Nút hông sau — nút 4 (Button 3)` in the English UI. That is the mechanism behind
the user's report that the Mouse Gestures page looked wrong.

It was *visible* to the suite, but easy to miss: `cd Tests && swift test` reported 2
failures while `sh scripts/verify-l10n.sh` printed a green `97 tests, 0 failures` from a
**different, earlier build directory**.

Rules now:
1. **`git --no-optional-locks status --short` before trusting any "all green" result.** An
   unexpected modified gesture/L10n source is a leftover mutation until proven otherwise.
2. **Run the three mutation scripts last, never first**, and never with the terminal about
   to be interrupted. If one is interrupted: `git checkout --` the file it names, then
   `cd Tests && swift test` before anything else.
3. **"Baseline is not green" is a finding, not harness noise.** That is exactly how this
   was found — `fails()` returned 2 on the baseline step while a direct `swift test`
   returned 0, because the two runs used different build state. Do not "retry until
   green"; find which source file differs from `HEAD`.
4. **A green count from a script that builds elsewhere is not proof about the tree in front
   of you.** `verify-l10n.sh` builds to `/tmp/xfinder-l10n-build`; `cd Tests && swift test`
   compiles the symlinked sources in place. When they disagree, the in-place run wins.

## Mouse gestures — PATCH v3 (L1–L4) — 2026-09-22

### Sáu lỗi thật đã sửa

| # | Triệu chứng người dùng báo | Nguyên nhân gốc |
|:--|:--|:--|
| L1 | Mọi mũi tên đều ghi "Nút 3" | `MouseDiagramView` in `trigger.numberedName` trên **cả bốn** nhánh. Nút giữ là *một* nút cho mọi hướng, nên bốn bản sao đọc thành "cả bốn nút đều là Nút 3". Số giờ chỉ hiện **một lần** trên thân chuột |
| L2 | Tiếng Việt lọt vào UI English | `TriggerSource.label`, `numberedName`, `GestureDirection.title(trigger:)` trả **câu tiếng Việt** từ file model; call site bọc `L10n.t(...)` quanh chuỗi đã render — không bao giờ khớp khoá được. Đã gỡ hết khỏi model; model chỉ trả khoá ngữ nghĩa |
| L3 | Sơ đồ luôn vẽ đủ nhánh | Không có probe phần cứng. Giờ `DeviceCapabilityModel.armSupport` quyết định, có ba trạng thái |
| L4 | "873 input-button elements" | **Lỗi filter**, không phải sự thật về phần cứng. `usagePage == 0x01 && usage == 0x09` là Button *collection*. Filter đúng cần **cả hai** guard: type `0x02` **và** page `0x09` |
| — | Nút "Về mặc định" reset cả app | Gọi `resetProfile` trong khi nhãn hứa một hướng. Nay `resetDirection` |
| — | Heading trùng số ở panel chi tiết | Heading giờ gồm 2 phần khoá: nút + chuyển động, ghép ở **một** chỗ |

### Chia file theo khả năng test, không theo sở thích

`Tests/` là package Foundation thuần và symlink từng file. Nên bất cứ file nào
import SwiftUI/IOKit đều **không test được** — và một test mở IOHID rồi khẳng định
trên chuột đang cắm là kịch, chạy được trên máy tác giả và fail ở mọi nơi khác.

| File | Import | Trong package | Chứa |
|:--|:--|:--|:--|
| `DeviceCapabilityTypes.swift` | Foundation | **có** | type + suy dẫn thuần (filter, axes, features, confidence) |
| `DeviceCapabilityModel.swift` | Foundation | **có** | `ArmSupport`, provenance, chọn chuột (D4) |
| `GestureLabelStructure.swift` | Foundation | **có** | đánh số nút + **cấu trúc** câu heading |
| `DeviceCapability.swift` | **IOKit.hid** | không | chỉ phần probe sống |
| `GestureUIDisplay.swift` | Foundation | **bỏ khỏi package** | chỉ state machine click mũi tên |
| `Core/L10n.swift` | SwiftUI | không | chỉ phần **từ ngữ** |

### Đo thật trên macOS 27.0 (`/tmp/probe-capability.swift`)

```
IOHIDManagerOpen kIOReturn: 0   (kIOReturnSuccess)
raw device count TRƯỚC dedupe: 4        ← 4 entry cho 2 thiết bị vật lý
  Apple Internal Keyboard / Trackpad  FIFO  vid=nil pid=nil    buttons=[1,2,3] axes=[x,y]   inferred
  BSKV3P 35K   Bluetooth Low Energy  vid=0x068E pid=0x00D8     buttons=[1,2,3,4,5] axes=[x,y,wheel]  verified
```

Ba điều đã chốt:
1. **C2 đúng** — `0x068E/0x00D8` là định danh thật của Basilisk, xác nhận từ property IOHID.
2. **`IOHIDManagerCopyDevices` trả trùng** — 4 entry cho 2 thiết bị. Bắt buộc phải dedupe.
3. **Basilisk KHÔNG khai trục nghiêng** → `supportsTiltArms == false` cho chính con chuột
   mà tính năng này được làm ra. Đây là lý do hai nhánh nghiêng mặc định tắt.

### Lỗ hổng gate phát hiện trong lượt này — đọc trước khi tin một harness xanh

**5 mutation đã báo "STAYED GREEN"**, trong đó `mutation-check-gesture-ui.sh` còn
abort với `mutation target not found` **sau khi** đã in hai kết quả xanh. Hai nguyên nhân:

1. **Anchor mục** — `sed`/python trỏ vào câu mà model không còn sinh ra.
2. **Hành vi đã chuyển vào file test không compile được.** `L10n.swift` import SwiftUI,
   nên phần đánh số (`n + 1`) và ghép heading nằm ngoài tầm với của mọi test. Sửa anchor
   **không đủ** — phải chuyển *cấu trúc* sang `GestureLabelStructure.swift`, chỉ để
   *từ ngữ* lại ở `L10n.swift`.

**Quy tắc cố định, đã ép trong cả hai script:** mỗi `mutate` nhận đường dẫn target
tường minh và **abort toàn bộ lượt chạy** khi thiếu anchor, thay vì in "inconclusive"
rồi đi tiếp. Mutation không tiêm được = gate hỏng, mà gate hỏng thì đọc như gate đạt.

### R2 — ép ở ba tầng (model không được phát chuỗi hiển thị)

1. **Tĩnh** — `GestureModel.swift` không còn member `String` nào dựng câu.
2. **Unit** — `testDirectionKeysAreStoreKeysNotRenderedSentences`,
   `testGesturePageStringsAreAllTranslatable` duyệt đúng từ vựng của model.
3. **Tích hợp** — `testArmCaptionsCarryNoButtonNumber` + `verify-gesture-ui.sh` §2/§3.

### Hoãn, kèm lý do (không có gì trong UI claim là đã có)

* **Picker nhiều thiết bị** — D4 khoá single-mouse; `DeviceSelection` tự chọn + cho ghi đè.
* **Profile theo thiết bị** — config khoá theo *bundle ID*, nên binding theo app chứ
  không theo chuột. Muốn theo chuột thì cần store theo device + migration.
* **Learning / suggestions** (§3 của brief) — chưa làm. UI không claim là có.

---

## Mouse gestures — PATCH v7 (one map, real engines, measured activity) — 2026-09-22

Lượt này sửa đúng thứ mà **ba lượt UI trước đó không chạm tới**: *bảng mapping*.
Người dùng nói lần thứ ba *"chức năng của gestures không phù hợp"* trong khi UI đã
được khen — nên bệnh nằm ở dự định hành động, không ở bố cục.

### Nguyên nhân gốc: một preset KHÔNG THỂ nói hành động đó *là gì*

Mapping cũ là một `GestureShortcut` trần, và trang **đoán tên hành động từ mã phím**:

```swift
case 17: return L10n.t("Tab mới")     // ← nếu ⌘T là phím người dùng tự đổi thì sao?
case 29: return L10n.t("Vừa khung")
```

Câu hỏi "phím 17 là gì?" có **câu trả lời khác nhau ở mỗi app** — nên bảng đó không
thể đúng. Nó còn nằm trong `GestureDetailPanel.swift` (import SwiftUI) nên **không test
nào chạm tới**. Sửa gốc: `GestureMapEntry` mang **`GestureActionKind`** (ý định), UI hỏi
đang mô tả app nào rồi mới gọi tên.

**Hệ quả cần nhớ:** một phím **người dùng tự ghi** không được gán tên hành động.
`GestureMap.displayName` chỉ trả `labelKey` khi phím đó **đúng bằng** phím preset khai
cho ý định ấy. Người dùng ghi `⌘↩` cho "Up" trong Safari không tạo ra nghĩa mới cho mũi
tên — họ trỏ nó vào phím của họ. Hiện tên preset lên đó là **nói sai về app của họ**.

### Nguyên nhân gốc thứ hai: danh sách có thể NGẮN HƠN từ vựng

Đây là cùng hình dạng với lỗi "trang rỗng" đã gặp hai lần: màn hình hiện **ít lựa chọn
hơn** thứ engine làm được, nên người dùng kết luận tính năng không có gì.
`GestureActionCatalog.choices()` sinh từ `GestureActionKind.allCases`, nên nó **không
thể** ngắn hơn. Test `testActionCatalogCoversEveryIntentAndEveryChoiceIsSendable` giữ
điều đó — và nó **đã bắt được** `.horizontalScroll` có trong từ vựng mà thiếu trong danh
sách, đúng loại lỗi mà test này tồn tại để chặn.

### File mới, và vì sao tách như vậy

| File | Import | Trong test | Chứa |
|:--|:--|:--|:--|
| `Core/MouseGestures/GestureMap.swift` | Foundation | **có** | từ vựng ý định + catalog picker + resolver `row(overrides:bundle:direction:)` |
| `Views/Components/GestureArmView.swift` | SwiftUI | không | một nhánh sơ đồ (là `Button` thật) |
| `Views/Components/GestureActionPicker.swift` | SwiftUI | không | menu chọn hành động, nhóm theo ý định |
| `Views/Components/GestureActivityPanel.swift` | SwiftUI | không | danh sách **đo được** |

`GestureMap.swift` phải Foundation-only vì chính nó là thứ cần test: nó là **một**
resolver cho cả trang lẫn engine, và `testMapRowAgreesWithRuntimeActionForEveryBundleAndDirection`
khẳng định điều đó cho **mọi** bundle × direction (kèm một override thật, để không chỉ
kiểm tra nhánh preset).

### Bảng mapping đã đổi — đây là lần thứ ba, nên ghi lại *vì sao*

| Nhóm | Cũ | Mới | Lý do |
|:--|:--|:--|:--|
| Global | `⌘⇧]` `⌘⇧[` `⌘[` `⌘]` | `⌘[` `⌘]` `⌃←` `⌃→` | `⌘⇧]` là quy ước **trình duyệt**; trong editor văn bản nó **không làm gì**, mà editor là phần lớn ngày làm việc. Hai trục giờ là hai quy ước phủ rộng nhất: lịch sử + Spaces |
| Browsers | ←→ = `⌃⇧⇥` `⌃⇥` | ←→ = lịch sử, tilt = `⌃⇥` | lịch sử là thứ cử chỉ làm tốt hơn bàn phím |
| Dev/AI | `⌃-` `⌃⇧-` | `⌘[` `⌘]` | `⌃-` là phím **của một editor**, không phải quy ước; `⌘[`/`⌘]` thì mọi editor hiểu |
| Excel + Word | **một bảng rỗng dùng chung** | **hai bảng** | Word **không có worksheet** — `⌃⇧⇥` vô nghĩa trong Word. Excel có tài liệu riêng cho cặp đó. `testWordAndExcelDoNotShareOneTable` giữ hai dictionary tách rời |
| Tilt preset | `⌘=` `⌘-` | để trống | nhánh tilt của engine coi `.unassigned` là "để cuộn ngang đi thẳng" — preset gửi phím ở đây là phím **không bao giờ làm được gì có ích** |

### Engine C và diagnostics

* **Engine C — giữ nút cuộn rồi kéo để cuộn.** Mặc định **tắt**: nút hông thường đã
  được driver gán (back/forward), chiếm nó là đánh nhau với driver. Wheel event có
  **tiết chế ~60 Hz** — chuột 8 kHz sẽ bắn hàng nghìn event/giây và đọc như một cú nhảy.
  `validate()` **sửa** nếu nút cuộn trùng nút giữ: một nút không thể vừa "bắt đầu cử chỉ"
  vừa "cuộn", và triệu chứng duy nhất của lỗi đó là "lúc được lúc không".
* **Diagnostics** — `GestureDiagnostic` + một ring 20 dòng, engine tự báo
  *nút giữ được nhấn / đã khoá hướng / đã gửi phím / phát lại click / quay về vùng chết*.
  Chỉ chạy khi `debug == true`: hot path khi tắt là **một lần đọc boolean**, không cấp
  phát, không lock. Chỉ ghi bundle ID + số nút + hướng — **không ghi phím người dùng gõ**.
* **`observedPress`** — trang in ra **số nút XFinder thật sự nhận được** khi người dùng
  bấm thử. Đây là câu trả lời *đo được* cho "tôi dùng nút nào?", thay vì một lời khuyên
  về vị trí mà không API nào xác nhận.

### Gate của lượt này

```sh
sh scripts/verify-gesture-ui.sh     # §2 VI-literal lint, §3 109 khoá gesture, §4 137 test,
                                    # §5 compile-log-by-name, §6 arch/signature, §7 tap state
cd Tests && swift test              # 137 tests
python3 scripts/check-l10n-coverage.py    # TOTAL 0 problems across 1018 entries
python3 scripts/check-l10n-duplicates.py  # TOTAL 0 duplicates
```

**Hai mutation được tiêm và xem đỏ, rồi revert và chạy lại xanh:**

1. `GestureMap.row` bỏ qua `overrides` → **4 test fail** (đúng cái test đối chiếu
   row ↔ runtime cho mọi bundle/direction).
2. `displayName` trả tên cho **mọi** shortcut → **1 test fail**
   (`testRecordedShortcutIsNotGivenAnInventedActionName`).

### Bốn kết quả, tách rời — và cái thứ tư vẫn chưa có

Build ✅ · test ✅ · Event Tap ✅ (`{active: True, trusted: True, failure: ""}`) ·
**hành vi chuột thật ❌**.

Ghi rõ hai điều **chưa** đo được, để lần sau không bị đọc thành đã đo:

1. **Nút nào trên Basilisk V3 35K là số mấy.** HID khai `buttons = [1,2,3,4,5]`; **thứ tự
   khai báo không chứng minh vị trí vật lý.** Trang giờ đọc ra được số khi người dùng bấm
   — nhưng **số đó chưa được đọc**.
2. **Cảm giác của Engine C.** Ngưỡng ~60 Hz là suy luận, không phải đo với tay người.

### Cạm bẫy đã gặp trong lượt này (đừng lặp lại)

* **`@ViewBuilder` + ternary trong `L10n.t(...)`** làm lint VI-literal **mù**: nó chỉ
  thấy literal là **đối số trực tiếp**. Phải viết `if`/`else` với hai `Text(L10n.t(...))`.
  Lint đã bắt đúng chỗ này (`GestureArmView`), tức lint đang chạy.
* **Đọc một tên hàm là giá trị.** `appName: profileDisplayName` khi hàm đã thành
  `func profileDisplayName() -> String` cho ra ba lỗi biên dịch **ở ba dòng khác nhau**.
* **`private static func` dùng từ file khác** (`GestureMap.systemKeystroke` gọi bởi
  `GestureActionCatalog`) — compiler nói rõ, nhưng đọc lướt dễ tưởng là lỗi kiểu.
* **Hai file mới trong `Core/MouseGestures/` phải thêm ĐỦ BỐN entry pbxproj**, và
  **ba file view mới cũng vậy**. Triệu chứng khi thiếu là `cannot find type … in scope`
  ở file **dùng** nó, không phải ở file mới — dễ đi sai hướng.
* **Thêm symlink mới vào `Tests/XFinderLogicTests/`** cho mọi file Foundation mới.
  `GestureMap.swift` được symlink; ba file SwiftUI thì không (và không thể).

### Lỗi ngôn ngữ lần thứ NĂM: `LanguageNeutralKeys` là một DÒNG CODE KHẲNG ĐỊNH
(2026-09-22) — đọc trước khi "sửa" bất kỳ chuỗi nào không dịch được

Người dùng báo lỗi ngôn ngữ **năm lần**, và bốn lần trước đều sửa bằng cách bọc
thêm `L10n.t()` ở call site. Lần này tìm được cơ chế thật, và nó **không phải**
thiếu bản dịch:

* `L10n.LanguageNeutralKeys` chứa **ba CÂU TIẾNG VIỆT** —
  `"Nút 1 (chuột trái)"`, `"Nút 2 (chuột phải)"`, `"Nút 3 (bấm con lăn xuống)"` —
  được khai là "trung tính ngôn ngữ", nên `t(_:)` trả về **nguyên văn**. Đó là một
  dòng code *khẳng định* chuỗi này không bao giờ được dịch. Bọc call site bao nhiêu
  lần cũng vô ích.
* Nó còn **sai sự thật**: macOS đếm nút từ **0** (0 = trái, 1 = phải, 2 = con lăn,
  3 = nút hông đầu). Nhãn cũ gọi con lăn là "Nút 3" — đặt sai tên đúng cái nút mà
  tính năng này lấy làm nút giữ mặc định.

**Sửa, và cách ép để không tái diễn:**

1. `LanguageNeutralKeys` nay chỉ còn **glyph**: `"⌘", "⌥", "⌃", "⇧"`. Câu chỉ có
   thể nằm ở store.
2. `ButtonLabelStructure` trả **khoá** (`"Nút trái"`, `"Nút phải"`,
   `"Bấm con lăn xuống"`, `"Nút "` + số) — không trả câu hiển thị. Nút hông mang
   thêm một *gợi ý có điều kiện* (`hintKey(forButtonNumber:)`: "thường là nút hông
   trên"), vì không API nào xác nhận được vị trí — chữ "thường là" là cố ý.
3. **Gate mới** `testLanguageNeutralKeysContainNoSentences` **đọc trực tiếp
   `Core/L10n.swift`** (`L10nFixture.declaredLanguageNeutralKeys()`), vì file đó
   import SwiftUI nên package test không compile được nó. Đây là chỗ duy nhất phải
   đọc source: điều cần bắt là chính cái *khai báo* sai, nên một fixture chép tay
   sẽ vô hiệu hoá gate. Parse hẹp giữa `static let all` và `]`, và **fail nếu
   không tìm thấy gì** — "gate đọc được 0 khoá" phải đỏ, không được xanh.

**Quy tắc rút ra: không bao giờ giết một assertion rò rỉ ngôn ngữ bằng cách gọi
chuỗi đó là "language-neutral".** Đó chính là lỗi, không phải cách sửa. Chỉ glyph
mới đủ tư cách. Và khi UI English hiện tiếng Việt, thứ tự điều tra là:
**(a)** grep `LanguageNeutralKeys`, **(b)** `L10n.t(...)` có được gọi từ một tầng
model trả `String` không, **(c)** khoá có phải chuỗi nội suy (`"\(x)"`) không,
**(d)** chỉ khi đó mới là "thiếu entry trong store".

### PATCH v7 R1 — TIỀN ĐỀ SAI, và probe là lý do để nói vậy (2026-09-22)

R1 khẳng định probe HID **đếm thiếu** nút Basilisk: phải ra "≥7 nút, không phải 5",
vì filter bỏ sót Vendor Defined Page `0xFF00+` của Razer. Brief cũng yêu cầu chạy
probe trước khi sửa code. Đã chạy (`scripts/probe-hid-raw.swift`) — dump
`UsagePage`/`Usage`/`type` của **mọi** element trước mọi filter:

```
=== Razer Basilisk V3 Pro 35K ===   transport USB  vid 0x1532  pid 0x00D6
  TOTAL elements: 105
  page=0x0009 type=0x02  ×5       ← năm nút
  page=0xFF00 type=0x101 ×92      ← trang vendor: toàn FEATURE element
  CURRENT filter (type 0x02 && page 0x09) buttons: [1,2,3,4,5]
  v7 PROPOSED filter (page 0x09 only)     buttons: [1,2,3,4,5]  count=5
  ALL button-typed elements (any page): chỉ [1..5] trên 0x09 — không gì khác
```

Ba điều đã chốt:

1. **5 là ĐÚNG.** Không phải đếm thiếu: filter hiện tại và filter v7 đề xuất trả **cùng**
   năm usage, nên `0xFF00` không giấu nút nào trên thiết bị này. Thêm nhánh đó sẽ **không
   đổi gì** trên Basilisk, nhưng phá mọi thiết bị khác — trên **trackpad Apple**, cùng cây
   đó khai `page=0xFF00 type=0x02` với `usage=0xFFFFFFFF` trên **1753 element**; quét
   `0xFF00` tìm nút sẽ báo **1756 nút**, và `usage = -1` không render được thành số.
2. **Không cần loại trừ 2 nút profile.** Không element nào trên bất kỳ trang nào khai nút
   thứ sáu/thứ bảy, nên không có gì để loại. Hai nút trên con lăn do firmware/driver Razer
   xử lý và **không bao giờ tới được HID button page**.
3. **Định danh khai báo KHÁC giá trị đang ghi trong file này.** Đo bây giờ: `USB`,
   `vid 0x1532` (Razer), `pid 0x00D6`. Ghi chú cũ nói `Bluetooth Low Energy`,
   `0x068E / 0x00D8`. **Cả hai đều thật** — cùng một con chuột qua hai transport, hiện đang
   cắm USB. Ghi chú cũ không sai, nó **thiếu**: đổi transport là đổi luôn tuple định danh,
   mà `deduplicated(_:)` key theo tuple đó.

**Đã làm thay vào đó:** không đổi probe. Nhánh `0xFF00` mà brief yêu cầu **đã KHÔNG thêm** —
`DeviceCapabilityTypes.swift` và `DeviceCapability.swift` không bị chạm. Thêm nó sẽ tái sinh
đúng loại lỗi (`[1,2,3,4,5,9]` từ filter quá rộng) mà một fixture test đang ghim.

### Hai nguyên nhân "cử chỉ không chạy" — trang giờ nói thẳng (2026-09-22)

Khi cử chỉ không chạy, có đúng **hai** nguyên nhân, và cả hai đều **vô hình** trong bảng
mapping:

1. **Nút giữ sai.** Config trên đĩa của người dùng vẫn là `mouseButton(2)` — bấm con lăn —
   vì đó là default của build cũ, và `validate()` **chỉ sửa trigger KHÔNG hợp lệ**. 2 là
   *hợp lệ*, nên không migration nào chạm tới. Giữ con lăn rồi kéo là thao tác tay không
   làm được. Trang giờ có **cảnh báo cam** riêng cho giá trị 2 + nút ghi lại.
2. **XFinder đang là app phía trước.** Engine tra preset theo bundle ID của app frontmost;
   khi người dùng *đang thử* từ chính trang này thì XFinder frontmost, nên log hiện
   `com.xfinder.app` một cách hợp lệ và cử chỉ trông như hỏng trong khi nó chạy đúng cấu
   hình. Trang nói rõ thay vì âm thầm thay bằng bảng Global — thay ngầm sẽ làm trang
   **mâu thuẫn với engine**, đúng thứ mà
   `testMapRowAgreesWithRuntimeActionForEveryBundleAndDirection` tồn tại để chặn.

**CTA "đặt nút này làm nút giữ"** chỉ hiện khi `observedPress` khác nút giữ hiện tại.
Đây là điểm khác biệt cốt tử so với gợi ý của PATCH v6 R1 (gate trên
`trigger == 2 && overrides == {}`), vốn **khớp mọi bản cài mới** vì 2 khi đó là default code.
Gate trên một lần bấm **thật sự quan sát được** mới là dạng trung thực.

**`DEBUG_SHOW_ENGINE_LOG`** (v7 R5) là gate **lúc biên dịch**, không phải `if` runtime:
chuỗi, view và plumbing của block chẩn đoán **rời khỏi binary**. Đã kiểm cả hai chiều.

### Bốn kết quả, tách rời — và kết quả thứ tư vẫn chưa có (2026-09-22)

Build ✅ · test ✅ 143/143 · Event Tap ✅ `{active: True, trusted: True}` · **hành vi chuột
thật ❌**. `screencapture` vẫn fail trên máy này, nên **không có phát biểu nào về việc trang
*trông* thế nào** là kiểm chứng được.

**Việc người dùng còn phải làm — đúng một thao tác:** mở **Chuột & cử chỉ**, đọc dòng cam,
bấm **Ghi lại nút giữ**, bấm nút hông muốn giữ. Không có code nào tự đổi giúp, theo thiết kế:
2 là giá trị hợp lệ, nên migration ngầm sẽ **ghi đè lựa chọn có chủ ý** của người thật sự
muốn nó.

---

## Mouse gestures — Round 7: "nhận dạng nhưng không làm gì" (2026-09-22)

Người dùng báo: gesture **được nhận** (UI hiện nút giữ + hướng) nhưng **không có tác dụng**
ở profile Global, cụ thể Hold + kéo LÊN = Mission Control và kéo PHẢI = next Space.

### Nguyên nhân gốc: **preset sai**, không phải engine

Global gửi `⌃↑`/`⌃↓` (Mission Control / App Exposé) và `⌃←`/`⌃→` (Space trước/sau).
**Bốn phép đo chứng minh các phím đó KHÔNG được gán gì trên máy này:**

| Probe | Kết quả |
|:--|:--|
| `defaults export com.apple.symbolichotkeys -` | id 79–82 ("Move left/right a space") **có mặt, `enabled = 1`, nhưng KHÔNG có `value`** → công tắc bật mà không gán phím nào |
| cùng nguồn, id 32 (Mission Control) | `vk = 232`, `mods = 0` — keycode 232 là **NX system-defined key**, không tồn tại `CGKeyCode` 232, nên `CGEvent(keyboardEventSource:)` **không thể** diễn tả nó |
| `/System/Library/User Template/English.lproj/…/com.apple.symbolichotkeys.plist` | **không có** id 32/34/79–82 → macOS 27 không ship binding mũi tên nào cho các hành động này |
| `docs/probes/probe-post-shortcut.swift` + `probe-observe-shortcut.swift` | `⌃→` do engine tự dựng **đến nơi nguyên vẹn**: `vk=124 flags=537133056 mods=[⌃]`, cả down lẫn up → event đúng, **chỉ không có ai nghe** |

⇒ Đường dispatch chưa bao giờ hỏng. `GestureMap.systemKeystroke` **đặt tên bốn hành động mà
nó không gửi được** — đúng thứ Honesty Rule cấm.

### Đã sửa

1. **`GestureAction.systemAction`** + `SystemKeySender`: Mission Control / App Exposé /
   Show Desktop gửi bằng `NSEvent.otherEvent(with: .systemDefined …)` — **cùng cơ chế
   `SystemControls.adjustBrightness` đã ship**. Tách bằng `#if canImport(AppKit)` để phần
   số học `data1` test được trong package Foundation-only.
2. **`systemKeystroke` trả `nil`** cho ba intent đó thay vì bịa phím;
   `GestureMapEntry.systemAction` **loại trừ lẫn nhau với `shortcut`** theo cấu trúc.
3. **Global suy lại**: up → Mission Control, down → App Exposé (system event);
   left/right → `⌘[` / `⌘]` (history — quy ước **không cần binding hệ thống nào**).
   **Space cố ý KHÔNG có trong default**: không có API event-level, nên ship nó = lặp lại bug.
   Vẫn còn trong picker.
4. **`SpaceBinding`** đọc symbolic hotkey **của chính người dùng** để trang nói được
   `⌃←`/`⌃→` có được gán hay không, thay vì giả định. Parse `enabled` từ **integer** —
   OS ghi `1`/`0`, **không** bridge sang `Bool`, nên `as? Bool` báo mọi shortcut đã tắt là bật.
5. **UI**: `ResolvedGestureRow.caption` gọi tên cơ chế cho system action. Trước đó
   `shortcut?.label ?? ""` render **caption rỗng** → đọc như "chưa gán".

### Trạng thái kiểm chứng — tách rời, và một mục **thất bại**

| Phát biểu | Kết quả |
|:--|:--|
| Build, arm64, tên file mới **có trong compile log** | ✅ `SystemKeySender.swift`, `SpaceBinding.swift` |
| 164 unit test (trước 143) | ✅ |
| `⌘[` / `⌘]` **đến app và ĐỔI TRANG** | ✅ đo trong Safari: title `Binance Spot` → `Crypto Exchange` → `Trade ETHFI/USDT` |
| Keystroke engine tự dựng đúng định dạng, tới HID | ✅ quan sát bằng tap `.listenOnly` thứ hai |
| `⌃←`/`⌃→` vô tác dụng ở đây | ✅ kèm lý do trong bảng trên |
| 2 test mới **có thể fail** (đã inject) | ✅ `data1` shift (3 fail); Global→Space key (8 fail) |
| **Mission Control MỞ khi post system key** | ❌ **CHƯA KIỂM CHỨNG ĐƯỢC** |

### Vì sao Mission Control không kiểm chứng được — và vì sao ghi là thất bại

`docs/probes/probe-mission-control-detect.swift` định phát hiện qua window list. Detector đó
**sai**, và sai **hai lần** — đây mới là bài học:

1. Lần đầu so `kCGWindowBounds` width (**point**, 1728) với `CGDisplayPixelsWide`
   (**pixel**, 3456) → báo "not open" cho một Mission Control đang **hiện rõ**. **Probe hỏng
   đọc ra kết quả âm tính.**
2. Sau khi sửa, nó khớp **mọi** cửa sổ Dock full-width ở layer > 10 — và **macOS 27 giữ
   đúng một cửa sổ như vậy thường trực** (đo được: `owner=Dock layer=20 1728x1117 alpha=1`,
   id **sống sót qua `killall -9 Dock`**). Nên **mọi** kết quả "MC OPEN" trong vòng này —
   kể cả lần trông như thành công — đều đang đo bề mặt Dock bình thường.

Cuối cùng: không variant post nào (`.cgSessionEventTap`, `.cghidEventTap`,
`.cgAnnotatedSessionEventTap`) và không tốc độ lấy mẫu nào (xuống 25 ms) làm đổi tập cửa sổ
Dock. Bối cảnh: `com.apple.dock` có `showMissionControlGestureEnabled = 0`,
`showAppExposeGestureEnabled = 0`, `expose-animation-duration = 0`.

**Kết luận trung thực: `⌃↑`/`⌃↓` chứng minh được là không gán → đó là lý do preset đổi.
Cơ chế system-event CHƯA chứng minh được là mở Mission Control trên máy này.** Cần người
ngồi nhìn màn hình. **Đừng báo nó chạy cho tới khi có người xác nhận.**

### Hai cái bẫy script mới (đã sửa, ghi để không lặp)

* **`mutation-check-l10n.sh` hardcode danh sách restore của allowlist**
  (`d["sameByDesign"] = ["Apple Intelligence","Clipboard","OCR","Quick Look"]`), nên nó
  **xoá mọi entry thêm sau** — cụ thể `"Mission Control"`. Script báo mutation run **xanh**
  nhưng để lại cây với allowlist **cũ**, và lỗi nổi lên **sau** dưới dạng một test đỏ không
  liên quan. Sửa: **chỉ thêm lại đúng tên nó đã xoá** (`OCR`), không gán cả list.
  **Bài học: một restore hardcode là một mutation thứ hai không ai yêu cầu.**
* **Anchor M3 đã mục lần thứ ba** (Global đổi từ browser-pair sang system event). Script báo
  `HARNESS ERROR` chứ **không** xanh giả — đúng hành vi mà rule rotting-anchor ở trên tạo ra.
  Đã re-anchor vào system-action declaration.

## Mouse gestures — Round 8: Global thật sự gửi phím (2026-09-23)

Người dùng: *"Hold Scroll Button + kéo lên là Mission Control hoặc kéo sang phải là next
space… đều không hoạt động, chỉ là xuất hiện và nhận dạng cho có, không làm việc ở Profile
Global Default."* Round 7 đo ra `⌃↑`/`⌃↓` không được gán — nhưng **cách sửa của round 7 cũng
sai**, nên round này thay cả cơ chế.

### Nguyên nhân gốc — hai lần sai, không phải một

1. **`NX_KEYTYPE_MISSION_CONTROL` KHÔNG tồn tại.** `SystemKeySender` post keytype **32**
   qua `NSEvent.systemDefined`. `ev_keymap.h` chỉ định nghĩa tới `NX_KEYTYPE_MENU = 25`;
   32 là số bịa ⇒ post một sự kiện không định nghĩa ⇒ **không làm gì**. Comment trong code
   ("id 32 → NX_KEYTYPE_MISSION_CONTROL") là folklore sai.
2. **Mission Control / Exposé / Space là symbolic hotkey phần mềm**, không phải phím cứng —
   nên cơ chế *đúng* không phải keytype nào cả, mà là **đọc binding người dùng đã đặt** rồi
   post **đúng chord đó**.
3. **Cả hai trạng thái đều có thật.** Đo lại 2026-09-23 trên máy này: `32→⌃↑ vk=126
   mods=0x840000`, `33→⌃↓`, `34→⇧⌃↑`, `79→⌃←`, `80→⇧⌃←`, `81→⌃→`, `82→⇧⌃→`. Round 7 đo được
   ids 79–82 `enabled` **không `value`**; giờ chúng có. ⇒ **preset ship hằng số là sai ở một
   trong hai trạng thái** — phải đọc, không đoán.
4. **Bit `fn` là bắt buộc.** `0x840000` = `control | maskSecondaryFn`; Apple mã hoá arrow bằng
   bit này, mask nó đi là post chord hệ thống không khớp. `GestureShortcut.label` **bỏ** bit fn
   khi *hiển thị* (nên hàng đọc `⌃↑` như System Settings) nhưng **post nguyên mask**.

### Đã sửa

1. **`SystemKeySender` bị xoá**: file, symlink test, `SystemKeySenderTests.swift`, **4 entry
   pbxproj**, và tên nó trong 2 script. Post một keytype bịa là cả một lớp bug.
2. **`SpaceBinding`** thêm `appExpose = 33` (round 7 thiếu ⇒ App Exposé không giải được),
   fallback `79→80` / `81→82`, và **`GestureSystemBindings`** — value bất biến
   (`[GestureSystemAction: GestureShortcut]`) truyền tường minh vào **cả** resolver và engine,
   nên test truyền được `.empty` và thấy đúng hàng "máy chưa gán" thay vì phím bịa.
3. **`GestureSystemAction` thêm `.previousSpace` / `.nextSpace`** + `unboundCaptionKey`.
   Global preset: up/down/left/right = **bốn system action**, không hằng số nào.
4. **Một resolver cho UI và engine**: `GestureMap.row(..., systemBindings:)` trả
   `systemShortcut` + `isUnboundSystemAction`; `caption` là chord đã giải, hoặc câu "chưa gán
   trong macOS". Engine post đúng `systemShortcut` đó; **không giải được ⇒ post không gì** và
   ghi `.systemActionUnbound`.
5. **`systemAction(of:)`** — override chọn system action trước đây render thành "chưa gán" vì
   resolver dựng entry với `shortcut: nil` **và** `systemAction: nil`.
6. **Migration trigger 2 → 3**, một lần, **chỉ khi `overrides` rỗng** (2 là default cũ chưa ai
   đụng; ai đã cố ý đặt con lăn thì giữ).
7. **Trang**: hàng "Phím hệ thống trên máy này" đọc thẳng binding của máy + nút mở
   Bàn phím → Phím tắt; arm không giải được tô **cam** + tooltip + nút sửa; hàng "Đã gửi
   phím tắt" **không còn hiện cho hàng `.unassigned`** (đo ở Zed up/down: log cũ ghi
   "Shortcut sent — Raw horizontal scroll" cho một hàng gửi **không gì cả**).

### Kiểm chứng — tách rời

| Phát biểu | Kết quả |
|:--|:--|
| Build Debug, `lipo -archs` = arm64, tên file trong compile log | ✅ gồm `SpaceBinding.swift` |
| `cd Tests && swift test` | ✅ **162 test, 0 fail** |
| `scripts/verify-gesture-ui.sh` §1–§7 | ✅ 0 / 0 / 0 / 162 / đủ tên / arm64 / `active=1 trusted=1` |
| `verify-l10n-runtime.py` (store **trong bundle đã cài**) | ✅ TOTAL 0 leaks |
| Harness runtime, phần **system action** mới | ✅ *chord của máy được post, mask fn+control nguyên vẹn, không gán ⇒ post không gì* |
| Event Tap mở thật trên app đã cài | ✅ `lastTapState {active: 1, trusted: 1}` |
| Trang render: 4 arm đọc `⌃↑ ⌃↓ ⌃← ⌃→`; hàng phím hệ thống khớp plist | ✅ đo bằng AX tree (`probe-ax-dump.swift`) |
| Log engine: gesture → `Next Space`, ghi là **đã gửi** | ✅ người dùng tự thao tác |
| **Mission Control MỞ / Space ĐỔI thật** | ❌ **chưa có ai nhìn màn hình xác nhận** |

Điểm cuối **không** được báo là chạy. Bằng chứng hiện có: engine post đúng chord mà **chính
máy này** khai, tap đang mở, AX tree cho thấy đúng phím đó trên UI. Việc cuối — macOS có thực
sự đổi Space — cần mắt người. `probe-screen-diff.swift` đo được nhưng **đổi Space thật**, nên
chỉ chạy khi người dùng đồng ý.

### Lỗi ngôn ngữ còn sót — tìm bằng cách **đọc trang đã render**

Người dùng: *"kiểm tra lại xem chỗ nào còn lẫn ngôn ngữ… đặc biệt mấy cái droplist."* Tìm ra
bằng `probe-ax-dump.swift` (đọc text node thật), **không** bằng grep:

* **Sáu heading sidebar** `CHUNG · CỬA SỔ · FINDER & TÌM KIẾM · CÔNG CỤ · KẾT NỐI · TIỆN ÍCH`
  hiện **tiếng Việt trên UI English**. Call site đúng (`L10n.t(group.header)`), nhưng **khoá
  không có trong store** ⇒ `t()` rơi về tiếng Việt.
* **Năm chuỗi model truyền qua biến** thiếu khoá: `App Exposé`, `Hiện màn hình nền`,
  `Space trước`, `Space kế tiếp`, `Chụp màn hình`. `captionKey`/`labelKey` là *biến*, nên cả ba
  gate cũ **đều mù**: §3 `verify-gesture-ui.sh` chỉ grep `L10n.t("…")` literal;
  `audit-l10n-literals.py` thấy literal ở file model và chỉ *report* "unwrapped";
  `check-l10n-coverage.py` chỉ kiểm store với chính nó.

Đã sửa + **thêm gate có thể fail**:

1. `scripts/add-sidebar-l10n-entries.py` (đăng ký 6 heading) +
   `scripts/check-sidebar-groups-l10n.py` — gate mới, đọc chính `groups` trong
   `SidebarDestination.swift`, **fail nếu parse ra < 4 heading** (chống anchor mục). Cắm vào
   `verify-gesture-ui.sh` §1b. Đã **chứng minh fail**: xoá `CỬA SỔ` khỏi store →
   `PROBLEM … not in the store`, exit 1.
2. `L10nTests.testGesturePageStringsAreAllTranslatable` giờ đi qua
   **`GestureActionKind.allCases` + `GestureSystemAction.allCases`** — chính gate này **bắt
   được `Chụp màn hình`** (leak thật, chưa ai thấy) ngay lần chạy đầu.
3. `verify-l10n-runtime.py` thêm mục **sidebar groups**, giải với store **trong bundle đã cài**.

**Rule bổ sung:** một chuỗi đi qua `L10n.t(variable)` **không** được gate nào cũ bảo vệ. Muốn
chắc phải liệt kê vocabulary của model trong test (như 2) hoặc parse chính declaration (như 1).

### Bẫy mới

* **Harness runtime đọc default của production.** `MouseGesturesProbe.swift` không set
  `trigger`, nên khi default đổi 2 → 3 nó **fail ngay precondition đầu** với lý do trông như lỗi
  engine. Đã pin trigger tường minh trong harness.
* **Harness đã mục so với preset**: nó khẳng định tilt browser = keycode **17** trong khi bảng
  preset đã là `⌃⇥` (48). Đổi sang **so với resolver** (`posts(resolved(...))`) — không thể mục
  lần nữa. Ghi vào `docs/MOUSE_GESTURES.md` kèm lệnh biên dịch đã cập nhật (`GestureMap.swift`
  và `SpaceBinding.swift` phải có trong danh sách).
* **`plistlib` vs `defaults` khác nhau về thời điểm flush.** Đọc `.plist` bằng `plistlib` ngay
  sau khi app ghi cho ra **giá trị cũ** (cfprefsd chưa flush) — suýt kết luận sai "migration
  không chạy". `defaults export com.xfinder.app -` đọc qua cfprefsd nên thấy giá trị hiện tại.
  Đối chiếu hai cách này trước khi kết luận.
* **Mutation script TREO, không fail — và để lại nguồn đã bị mutate trên đĩa.**
  `mutation-check-gesture-labels.sh` bị kill bởi timeout của công cụ ở giữa `mutate` M3, nên
  `up: .convention(.missionControl, GestureShortcut(key: GestureKeyCode.upArrow, …))` — tức
  **đúng con bug mà mutation muốn mô phỏng** — nằm lại trong `GestureModel.swift` và **đã đi
  vào bản build**. Đây là dạng đã ghi trong rule “mutation để lại cây bẩn”.
  **Nguyên nhân gốc của việc treo:** `MouseGestureTests.swift:1161`
  `XCTAssertEqual(row.systemShortcut, liveBindings.shortcut(for: row.entry.systemAction!))`
  **force-unwrap `systemAction!`**. Mutation M3 đúng là làm arm Global thôi là system action
  ⇒ `systemAction == nil` ⇒ **trap** chứ không phải assertion failure ⇒ xctest **không bao giờ
  trả về** (crash reporting quay vô tận vì `MallocStackLoggingDT` được nạp). Chẩn đoán:
  `ps -eo pid,stat,command` cho thấy xctest ở trạng thái **`R` (running)** — chạy vòng lặp,
  **không** phải deadlock; `sample <pid> 3` chỉ thẳng
  `MouseGestureTests.testRowResolvesSystemActionsFromTheMachinesBindings` → `_assertionFailure`
  → `closure #1 in closure #1`. Đã sửa thành
  `guard let system = … else { XCTFail(…); continue }`. **Rule: trong một test mà mutation
  *được thiết kế* để làm đỏ, tuyệt đối không force-unwrap đúng giá trị mà mutation gỡ bỏ.**
  (Ghi chú phụ: `mutation-check-gesture-ui.sh` đếm `error: -[XFinderLogicTests` — một trap
  không sinh dòng đó, nên trap bị đọc thành **xanh**. Cùng một lỗi, hai triệu chứng.)
* **Đừng để timeout của công cụ kill mutation script.** Chạy
  `nohup sh scripts/mutation-check-*.sh > /tmp/log 2>&1 &` rồi poll file log; kill giữa chừng
  vừa để lại mutation, vừa để lại **xctest mồ côi**
  (`pkill -9 -f XFinderLogicTests.xctest`). Một gate bị kill im lặng đọc y hệt một gate xanh.
  Ba script chạy nền, tuần tự: labels **5/5 RED**, ui **7/7 RED**, l10n **6/6 RED**, mọi file
  restore byte-identical, suite sau restore **162 test 0 fail**.

## Mouse gestures — PATCH v9.1: sơ đồ vẽ theo thiết bị (2026-09-23)

Scope theo yêu cầu người dùng: **chỉ UI** (`Gestures logic FREEZE. Chỉ sửa UI`). Không đổi
semantics cử chỉ, không đổi trigger mặc định, không đổi đường dispatch.

### Nguyên nhân: "trang chức năng không hiển thị gì cả" — **đo ra là SAI**

Đây là khiếu nại mở đầu của lượt này, và nó **không tái hiện được**. Đo bằng
`docs/probes/probe-ax-dump.swift` trên **bản đã cài**:

| | English | Tiếng Việt |
|---|---|---|
| text nodes | **116** (89 static-text, 38 button) | 116 |
| chuỗi tiếng Việt trên UI English | **0** | — |

Bản đã cài **byte-identical** với build mới của HEAD (`shasum` trên
`XFinder.debug.dylib`). Vậy cả hai khiếu nại ("rỗng", "lẫn tiếng Việt") đều **không tái hiện**
trên cây hiện tại — nhãn `"Nút giữa / bấm con lăn (Button 2)"` mà người dùng nhắc đã bị gỡ từ
Round 2 và hiện bị hai gate chặn (`verify-l10n-runtime.py` + `L10nTests`).

Điều **tái hiện được** là vế sau của khiếu nại: hình chỉ có một nút giữ và bốn mũi tên, không
cách nào biết nút vật lý nào ứng với mũi tên nào — đúng chữ *"mặc định giao diện này là Magic
Mouse nên chỉ có 4 nút 4 hướng, chứ ko phải smart mouse"*. Đó là cái đã sửa.

### "Probe phải trả 6 nút" — đo lại, và **không** nới bộ lọc

Chuột **không kết nối** (`SPBluetoothDataType` xếp `BSKV3P 35K` dưới *Not Connected*; IOHID chỉ
thấy trackpad). Trên máy này:

```
  Apple Internal Keyboard / Trackpad   FIFO   vendorID: nil   productID: nil
    page=0x0009 type=0x02  ×3        ← khai báo usages [1,2,3]
    page=0xFF00 type=0x02  ×1753     ← usage 0xFFFFFFFF (-1), element type Input_Button
```

**Dòng `0xFF00` là lý do KHÔNG nới bộ lọc.** Lọc theo vendor page sẽ báo **1756 nút** cho trackpad,
một trong số đó là `-1` — cùng dạng thất bại với "873 input-button elements". Bộ lọc giữ nguyên.

Thay vào đó ship đúng phương án dự phòng mà R1 tự cho phép, nhưng **do bằng chứng kích hoạt**:
pressing a button the descriptor never declared → cảnh báo kèm con số đo được + *Đặt làm nút giữ*.

### Đã làm

| Vùng | Thay đổi |
|---|---|
| Sơ đồ | `MouseDiagramView` vẽ các nút thật của chuột ở vị trí archetype Razer; nhãn dùng dạng **compact** |
| Danh sách nút | file mới `Views/Components/GestureButtonList.swift` + 4 entry pbxproj |
| Model | `MouseControlSlot`, `MouseButtonRole` (+`isAssignable`/`labelKey`/`explanationKey`), `MouseRoleContext`, `role(forEventButton:context:)`, `undeclaredPress(observed:context:)`, `eventButtons(from:)`, `drawnButtons(...)` — tất cả ở nửa Foundation-only nên **test được** |
| Tilt | hai arm chuyển thành một hàng riêng dưới hình (trong hình thì đụng chip nút) |
| Nhãn compact | `ButtonLabelStructure.compactLabel(forButtonNumber:)` (luôn là **số trần**, `Nút 4`) + `L10n.t(compactButton:)`. Badge trên thân chuột vẫn dùng **tên đầy đủ** vì nó rộng 94 pt — ô chip rộng 46 pt và `Bấm con lăn xuống` dài 17 ký tự nên không vừa |
| Gate mới | `scripts/audit-gesture-vocabulary-l10n.py` |
| Mutation mới | `scripts/mutation-check-gesture-buttons.sh` |

### Bốn kết quả, tách rời

| Phát biểu | Kết quả |
|---|---|
| Build | ✅ `BUILD SUCCEEDED`, 0 error, `lipo -archs` = **arm64**, 19/19 tên file trong compile log (gồm `GestureButtonList.swift` — chứng minh 4 entry pbxproj đúng) |
| Tests | ✅ **176 test, 0 fail** (trước 162) |
| Gate | ✅ coverage 0/1074 · duplicates 0 · literal lint **0 wrapped-but-untranslated** · runtime **TOTAL 0 leaks** · vocabulary gate **63 khoá + 20 tên, 0 unresolved** · sidebar groups 0 |
| Mutation | ✅ **5/5 RED**, restore byte-identical, suite sau restore 176/0 |
| Event Tap | ✅ `{active: True, trusted: True, failure: ""}` |
| Trang render (AX) | ✅ 116 text node / 38 button, **0 chuỗi tiếng Việt trên UI English** |
| **Cử chỉ chạy thật bằng chuột** | ❌ **chưa** — và lượt này chuột **không được cắm** |

### Ba lỗi của chính gate mới (đã ghi vào AGENTS.md)

Sinh ra vì cả ba đều là dạng "xanh nhưng không kiểm gì": `find("{", match.end())` bỏ qua dấu `{`
của chính khai báo (`... = {`) → đọc body của khai báo **kế tiếp** → 0 tên profile → dòng
`profile names: 0 (Vietnamese: 0)` **xanh trên rỗng**; chỉ đọc `return "…"` nên bỏ qua
implicit-return; và regex đòi chữ thường sau dấu chấm nên **âm thầm bỏ 10 tên** (`com.apple.Safari`,
`dev.zed.Zed`, `com.adobe.Photoshop`). Đã chứng minh đỏ hai lần (xoá khoá → `MISSING`; tên profile
tiếng Việt → `NAME-LEAK`), cả hai exit 1.

### Còn lại cho lượt sau

* **Instant Action cho nút 3/4/5** — R3/R4 có nhắc, **không ship**: engine không có đường nào cho
  nó (click đơn trên 3/4/5 hiện được chuyển nguyên vẹn cho app). Ship nút nhận đổi nó = control
  không làm được điều nhãn hứa. Cần sửa engine ở lượt sau.
* **Cắm chuột rồi đọc danh sách nút** — một giây để biết Basilisk khai 5 hay 6 nút; nếu Sniper
  thiếu thì bấm nó, cảnh báo + số đo hiện ra, *Đặt làm nút giữ* là xong.
* **Mắt người trên Mission Control / đổi Space.** `probe-screen-diff.swift` đổi Space thật, chỉ
  chạy khi người dùng đồng ý.
* Nút giữ trên máy này vẫn là `mouseButton(2)` — trang cảnh báo cam, đổi bằng 1 click trong danh
  sách mới.

---

## Mouse gestures — Round 9: v10 kiểm chứng lại từ đầu (2026-09-23)

Yêu cầu: *"trang chức năng ko hiển thị gì cả… build lại app và test chức năng"*. Lượt này **không
sửa source sản phẩm** — chỉ đo lại và siết một gate. Ghi lại để lần sau không đo lại.

### "Trang không hiển thị gì" — nguyên nhân tầm thường: **bản cài cũ**

`/Applications/XFinder.app/Contents/MacOS/` ghi **12:54**, còn source v10 là **14:23–14:41**. Người
dùng đang đọc **bản build trước**, không phải bản có việc của lượt này. Sau
`scripts/install-mouse-rebuild.sh`, `probe-ax-dump.swift` đọc được **128 text node / 40 button**
trên trang đó ở **cả hai** ngôn ngữ, gồm mọi thứ v10 thêm vào: khối *Ready — the applications
below already have shortcuts*, dòng `Connected mouse · Detected · BSKV3P 35K · 5 buttons`, mục
**Raw HID descriptor**, nút **Record** từng dòng, các caption vị trí, và nhóm *Buttons the mouse
handles itself*.

**Rule: cài đặt trước khi tin một báo cáo UI.** `sh scripts/build-and-check.sh` build vào
`/tmp/xfinder-clean-build`, không chạm vào bản người dùng đang thấy.

### Đo được: BLE khai **5** nút và **không có vendor page**

Chuột đã kết nối lại, lần này qua **Bluetooth Low Energy** — nên câu hỏi để ngỏ từ v9.1 đã có đáp
án:

```
BSKV3P 35K   transport: Bluetooth Low Energy   vendorID 0x68E   productID 0xD8   898 elements
  page=0x0009 type=0x02 ×5    usages [1,2,3,4,5]  → event buttons [0,1,2,3,4]
  quét vendor (page >= 0xFF00, type 0x02, usage 1...0x3F): []   ← rỗng
```

Nút **Sniper là firmware-only trên BLE**: nó không gửi element nút nào, và **không có bộ lọc nào**
đào ra được. Trang render đúng sự thật đó: `Detected · BSKV3P 35K · 5 buttons` + `Button 6 — Not
declared` kèm nút **Record**. **"Probe phải trả 6 nút" là SAI với BLE** — chốt lại là 5. USB vẫn
chưa đo (không có cáp); nếu sau này khác thì đó là **dòng thứ hai**, không phải bản sửa của dòng
này.

### Ngôn ngữ — đo lại hai chiều, **không còn lẫn**

Đo bằng `probe-ax-dump.swift` trên **bản đã cài**, `defaults write com.xfinder.app AppLanguage`
để đổi ngôn ngữ (khôi phục `english` sau khi đo):

| | English | Tiếng Việt |
|:--|--:|--:|
| text node / button | 128 / 40 | 128 / 40 |
| dòng có dấu tiếng Việt | **1** — `App Exposé`, nằm trong allowlist | 120 |

Chuỗi trùng ở cả hai ngôn ngữ đúng 8, và cả 8 đều hợp lệ: `App Exposé`, `Mission Control`,
`Quick Look` (proper noun / allowlist), `BSKV3P 35K` (tên sản phẩm), và bốn glyph hợp âm
`⌃↑ ⌃↓ ⌃← ⌃→`. **Khiếu nại "English lẫn tiếng Việt" không tái hiện** trên bản v10 — kể cả trong
droplist, nơi bị nghi nhiều nhất.

### Bốn kết quả, tách rời

| Phát biểu | Kết quả |
|:--|:--|
| Build | ✅ `BUILD SUCCEEDED`, 0 `error:`, **19/19** tên file gesture trong compile log, `lipo -archs` = arm64 |
| Tests | ✅ **183 test, 0 fail** |
| Gate L10n | ✅ coverage `TOTAL 0` / **1097** entry · duplicates 0 · literal 0 · sidebar groups 0 · vocabulary 63 khoá + 20 tên, 0 unresolved |
| Harness runtime | ✅ PASS callback production + system action post đúng chord của máy (mask fn nguyên vẹn); `--live-tap` PASS (tap thật install/remove + timeout recovery) |
| Mutation, **chạy tuần tự** | ✅ buttons **11/11 RED** · labels **5/5 RED** · ui **7/7 RED** · l10n **6/6 RED**; mọi source restore byte-identical, suite sau restore 183/0 |
| Cài đặt | ✅ ký bằng `XFinder Dev`; `XFinderSync.appex` đăng ký **và đang bật** (`pluginkit` in `+`) |
| Trang render | ✅ EN 128 node / 1 dòng dấu (allowlist); VI 120 dòng dấu — không rò chiều nào |
| **Cử chỉ chạy thật bằng chuột** | ❌ **chưa** — cần mắt người nhìn Mission Control / đổi Space |

### Bẫy mới: bốn script mutation **phải chạy tuần tự**

Chúng sửa **chính source thật** (`GestureUIDisplay.swift`, `GestureModel.swift`,
`DeviceCapabilityModel.swift`, store L10n). Chạy song song — bốn `nohup … &` trong một shell — thì
chúng giẫm lên nhau và **sinh ra kết quả trông như phát hiện thật**:

* `mutation-check-gesture-labels.sh` báo **`FAIL: baseline is not green — failing test cases: 6`**;
  chạy một mình: baseline **0**, cả năm mutation RED.
* `mutation-check-l10n.sh` báo **`suite green again after restore: 2 failures`**; chạy một mình:
  **183 test, 0 fail**.

Cây **không** bị để bẩn (mỗi script `trap EXIT` và restore từ backup trong `/tmp`, `git status`
trước/sau giống nhau), nhưng **chạy song song tạo ra red giả** — và dòng "baseline is not green"
có đúng hình dạng của con bug mutation-sót-thật, nên không phân biệt được nếu không chạy tuần tự.
Chạy **lần lượt, detached, poll log**.

### Gate được siết: `mutation-check-gesture-ui.sh` giờ **khẳng định** xanh

Bước cuối của nó là `echo "Executed $(total) tests"` — chỉ đếm, không có số fail, nên một lần chạy
bị ngắt để lại mutation vẫn kết thúc trông như xanh. Hai script anh em đã in số fail; script này
giờ tính và **exit 1** khi khác 0. Chứng minh **cả hai chiều** mà không chạm source sản phẩm: thêm
file test scratch (`Tests/XFinderLogicTests/ScratchDirtyTreeProbeTests.swift`) chứa một `XCTFail` →
bước cuối in `184 tests, 1 failure(s)` và exit **1**; xoá file → `183 tests, 0 failure(s)`, exit
**0**. File scratch đã xoá ngay, không nằm trong cây.

### Dọn được trên đường đi

Bước kiểm tra cuối của `install-mouse-rebuild.sh` in ra các đăng ký LaunchServices còn trỏ path
không tồn tại, và có **bốn** cái đang sống (`/private/tmp/xf-out`, `xfinder-l10n-build`,
`xfinder-v10-build`, `xf-gate-out`). Cả bốn đều khai cùng plug-in identifier
`com.xfinder.app.XFinderSync` — đúng tình huống script sinh ra để ngăn. Đã gỡ bằng `lsregister -u`;
check giờ sạch. Script chỉ gỡ `$SRC`/`$STAGE` của chính nó, nên lỗi này tái diễn mỗi thư mục build
mới — nên sửa trong script ở lần chạm tới.

---

## Mouse gestures — PATCH v10.1: sơ đồ Razer + cổng debug (2026-09-24)

Phạm vi: **chỉ Probe + UI, Gestures logic FREEZE** — và điều đó được **kiểm chứng**, không chỉ
tuyên bố: `git diff --name-only` cho thấy `GestureEngine.swift`, `GestureController.swift`,
`GestureModel.swift`, `GestureMap.swift`, `SpaceBinding.swift` **không bị sửa**. Trigger mặc định,
deadzone, fire-on-release và mọi bảng preset giữ nguyên.

### R1/R3 của brief **đã xong từ v10** — đọc rồi báo, không "sửa lại"

Probe vốn đã quét cả Button page `0x09` và Vendor page `0xFF00`, log raw `(page, usage, type)`;
danh sách *Nút chuột XFinder thấy* vốn đã khoá 1/2 là "Chỉ bấm", đánh dấu 3 là nút giữ, và cho
4/5/6 nút **Ghi** + **Đặt làm nút giữ**. **Bốn delta thật** mới là việc của lượt này:

1. **Thân chuột là viên thuốc** (`RoundedRectangle`, bán kính ≈ nửa chiều rộng — hình Magic Mouse
   mà người dùng báo). Nay là `MouseSilhouette` dựng từ `MouseFigureOutline.points` (nằm ở nửa
   Foundation-only nên **test được**), vẽ bằng Catmull-Rom kín, thêm **đường ngăn** giữa hai nút
   chính, **con lăn trong đường ngăn đó**, và **gờ ngón cái ở dưới-bên trái** mang ba nút hông.
2. **Một từ vựng cho "nút nào"**: badge, dòng Kiểm tra nhanh và dòng *Nút giữ và cuộn* in **số**
   (`Nút 3`), khớp với các ô chip. Tên mô tả ở lại tooltip, dòng rộng trong danh sách và các câu
   giải thích.
3. **`MouseButtonRole.isDeclared`** — câu hỏi của **hình vẽ**, **cố ý khác** `isAssignable`. Ô của
   nút chưa khai báo (`.notDeclared`, `.unknown`) vẽ **mờ, đứt, không bấm được** + tooltip; dòng
   bên dưới vẫn giữ nút **Ghi**, vì đó mới là chỗ phép đo xảy ra.
4. **Khối hoạt động chỉ render theo `DEBUG_SHOW_ENGINE_LOG`.** Trước là
   `DEBUG_SHOW_ENGINE_LOG || config.debug`, nên `debug = true` đã lưu giữ một khối developer trên
   trang người dùng — đúng lỗi được báo. Comment cũ biện minh cho `||` rằng cổng compile-time sẽ
   để lại một control hứa điều nó không làm; control đó **nằm trong chính section bị cổng** nên lý
   do đó không áp dụng. **Kiểm tra containment trước khi với tay lấy `||`.**

### Rule mới của lượt này (mỗi cái là một lỗi thật)

* **Một báo cáo không bao giờ về 0 là báo cáo không ai đọc.** `add-gesture-l10n-entries.py` in
  `added 5, replaced 0, removed 5` ở **mọi** lần chạy, kể cả chạy lại trên store không đổi — nên
  tính idempotent của nó **không kiểm được**. Năm khoá nằm ở **cả** `ENTRIES` và `REMOVED`, nên
  chúng được thêm rồi xoá trong cùng một lượt. Store chưa bao giờ sai (`REMOVED` thắng) — đúng
  vì thế mà cả một lượt không ai thấy. Đã sửa: xoá khỏi `ENTRIES` + thêm self-check in
  `CONFLICT: …` và **exit 1**, đã chứng minh cả hai chiều.
* **Hai nguồn sự thật cho một danh sách rồi sẽ lệch.** `ENTRIES` và `REMOVED` là một danh sách
  chuỗi với hai ý kiến về nó; không có gì ngăn một khoá nằm ở cả hai. Khi hai danh sách phải rời
  nhau, hãy **assert** điều đó.
* **Copy nhắc tới một control không có trên trang cũng là dạng nói dối như nhãn sai.** Ẩn khối
  hoạt động làm câu ở dòng frontmost ("…đây là lý do nhật ký bên dưới chỉ hiện com.xfinder.app")
  trỏ vào hư không. Đã viết lại.
* **Con số ghép vào giữa câu cần hợp số ít/số nhiều.** `also declares 1 button elements on…` là
  kết quả trong tiếng Anh. Đưa con số về **cuối** mệnh đề thì **một** chuỗi đúng cho mọi giá trị ở
  cả hai ngôn ngữ. Hai nửa phải là `fragment` vì đều được ghép với giá trị runtime.
* **Tài liệu mục dạy phiên sau lặp lại bug cũ.** `docs/MOUSE_GESTURES.md` vẫn ghi "số nút được in
  ngay trên mỗi mũi tên của sơ đồ" — đúng hành vi L1 đã gỡ. Sửa thêm: dạng hiển thị cũ
  `Nút 1 (chuột trái)`, và hai chỗ dạy người đọc **bật nhật ký** (nay đã ẩn) để đọc số nút — nay
  trỏ vào dòng **"Nút bạn vừa bấm"**, dòng này **không** bị cổng.
* **Hợp đồng phía GHI không phải hợp đồng phía ĐỌC.** PATCH v10 làm công tắc tilt ghi **cả hai**
  `tiltAvailable` và `tiltEnabled` (`TiltArmsVisibility.fields(forReveal:)`) — sửa được cái công tắc
  *ghi* — nhưng store của chính máy này vẫn giữ `tiltAvailable = true, tiltEnabled = false`, do bản
  build cũ chỉ ghi trường đầu. Đọc `tiltAvailable` một mình thì vẽ hai mũi tên **không bao giờ
  chạy được** *và* hiện công tắc là **bật**: đúng "control không làm được điều nhãn nó hứa" mà hợp
  đồng phía ghi sinh ra để ngăn, ở tầng thấp hơn một bậc. `TiltArmsVisibility.isLive(available:enabled:)`
  là hợp đồng phía **ĐỌC** (phép giao), trang đọc nó cho cả mũi tên, công tắc và câu giải thích, và
  **không cần migration** — payload tự mâu thuẫn chỉ đơn giản đọc là tắt cho tới khi người dùng bật
  lại. **Tìm ra bằng cách đọc config đã lưu, không phải bằng đọc code**: `defaults export
  com.xfinder.app -` rồi `plistlib`.

### Đo được trong lượt này (đừng đo lại)

```
BSKV3P 35K   transport: Bluetooth Low Energy   vendorID 0x68e   productID 0xd8
  page=0x0009 type=0x02 ×5   usages [1,2,3,4,5] → event buttons [0,1,2,3,4]
  v10 vendor scan (type 0x02 && page >= 0xFF00 && usage 1...0x3F): []     ← rỗng
```

**BLE: 5 nút, không có phần tử nút nào trên trang hãng** — lần đọc độc lập thứ ba của cùng con
số, nên "probe phải trả 6" **đóng** với BLE. USB vẫn chưa đo. Apple Internal Keyboard / Trackpad
trong cùng lượt khai `[1,2,3]` **cộng một** phần tử nút trên trang hãng (usage 12) — 1753 sentinel
`0xFFFFFFFF` vẫn bị chặn bởi range guard, nên con số là 1 chứ không phải 1756.

### Bốn kết quả, tách rời

| Phát biểu | Kết quả |
|:--|:--|
| Build | `BUILD SUCCEEDED`, 0 `error:`, mọi file gesture trong compile log **theo tên**, `lipo -archs` = arm64 |
| Tests | **193 test, 0 fail** (+10) |
| Gate | coverage `TOTAL 0`/1097 · duplicates 0 · literal 0 · sidebar groups 0 · vocabulary 63+20, 0 unresolved · `verify-gesture-ui.sh` §1–§7 · runtime-in-installed-bundle **TOTAL 0 leaks** |
| Mutation, tuần tự | buttons **13/13 RED** (M12/M13 mới) · labels **5/5 RED** · ui **8/8 RED** (BUG 8 mới) · l10n **6/6 RED**; mọi source restore byte-identical; sau restore 193/0 |
| Trang render | EN 122 node / **1** dòng dấu (`App Exposé`, allowlist) · không có khối debug · hai mũi tên tilt **không được vẽ** (cặp `true`/`false` đã lưu nay đọc là tắt) |
| **Cử chỉ chạy thật** | ❌ **chưa** — cần mắt người nhìn Mission Control / đổi Space |

**`probe-ax-dump` cần cửa sổ ở phía trước.** Launch nền cho `windows: 0` — đó là artifact của
phép đo, không phải trang rỗng. Front app rồi hãy dump, và khôi phục `AppLanguage english` sau khi đo.

**Vẫn chưa ship:** Instant Action cho nút 3/4/5, lý do không đổi — engine chỉ chiếm nút giữ và nút
cuộn, nên bấm đơn trên 3/4 được chuyển nguyên vẹn cho app. Dòng đó **nói ra** điều cú bấm đang làm.

---

## Voice to typing — RayMate-parity pass (2026-09-30)

`Nhập bằng giọng nói` was upgraded from a two-field page into a dictation + rewrite feature:
six dictation modes, a floating HUD with a waveform drawn from real audio buffers, four model
tiers, screen context, and a before/after diff card. The feature itself is documented in
`docs/VOICE.md`. What follows is the part CLAUDE.md exists for — **the failures found while
building it**, three of which are new shapes of a language bug that has now been reported five
times.

### The build was red on arrival: a half-written view

`Views/Detail/VoiceDetailView.swift` was **111 lines long and ended with a `// __CONTINUE__`
marker**, so six `some View` section builders did not exist and the app could not compile. That
is the entire explanation for "trang chức năng không hiển thị gì cả". **Build before believing a
UI report** — the copy in `/Applications` predated the breakage.

Also on arrival: the 15 new Voice sources existed on disk but **were in no pbxproj group**, so
the first error was `cannot find type 'VoiceTriggerKey' in scope`. A file with no
`PBXFileReference` is silently absent from the compilation.

### Language leaks: three shapes, three gates, and one blind spot in the gate itself

The sweep reported **77 wrapped-but-missing** keys, all in the new Voice files. Three causes,
and only one is the shape the existing gates look for:

| Shape | Where it hid | Why no existing gate saw it |
|:--|:--|:--|
| Wrapped literal absent from the store | 77 strings across `VoiceDetailView`, `VoiceHUD`, `VoiceDiffPanel`, `VoiceManager` | Not a gate bug — they were simply never registered |
| `L10n.t(variable)` | `DictationMode.labelKey`, `VoiceTriggerKey.hintKey`, `RefinerError.messageKey`, `AppleOnDeviceRefiner.unavailableReason()` | No literal exists at the call site, so **no literal sweep can ever see it** |
| An interpolated key | `RefinerError.messageKey` returned `"Máy chủ trả lỗi \(code)"` | A key containing a runtime value can never match an entry, so it falls back to Vietnamese while the build stays green |

**The existing gate has a blind spot.** `scripts/audit-l10n-literals.py` is **line-based**, so a
call split across lines is invisible to it:

```swift
Text(
    L10n.t("XFinder không lưu mật khẩu. Nếu chưa có khóa, chạy"))
```

A whole-repo scan with a `re.S` regex found **7 pre-existing leaks** that sweep had been
reporting as clean, in pages untouched by this work: `FinderActionsDetailView` (×2),
`NotesDetailView` (`Cỡ chữ`), `RemoteConnectDetailView` (×2), `QuickShareDetailView`
(`còn `), `BatchRenameDetailView` (`Đã đổi `). All seven are registered now — including one
`"swap": true` entry, `còn `, whose correct English is the **empty string** because English word
order puts the number first (`còn 5 phút` → `5 min left`).

**Rule — this is now the standard fix for the whole class:**

1. **Register the literal** with the right `scope` (`fragment` when it is joined to something or
   carries edge whitespace; a label ending in `:` is a `fragment` too).
2. **Enumerate the model vocabulary in a test, never in a sweep.** `VoiceRefinerTests` walks
   `DictationMode` / `VoiceTriggerKey` / `VoiceActivationMode` / `VoiceHUDAnchor` /
   `VoiceRefinerTier` / `APIProviderKind` and every `RefinerError` case, asserting each key
   resolves to non-empty English in the **shipped** store — plus a
   `XCTAssertGreaterThan(keys.count, 40)` so a collapsed list cannot pass as a clean one.
3. **Never let a key contain an interpolation.** `messageKey` now returns `"Máy chủ trả lỗi"`;
   the status code lives in `detail`, on the line below it.
4. **Wrap at the display site, not in the model.** `RefinerError.detail` returns *keys* for
   `.unavailable`, so the view does `error.detail.map { L10n.t($0) }` — a miss is a no-op, which
   is exactly right for the provider's own error text.

`AppleOnDeviceRefiner.knownReasonKeys` exists only to make step 2 possible: those reasons come
from `#available` branches one machine cannot exercise, so they are named constants in one list
the test resolves.

### Two bugs the new tests caught — and one wrong expectation

* **`VoiceSettingsSnapshot.read(from defaults:)` shadowed the static
  `VoiceSettingsSnapshot.defaults`.** The parameter had the same name, so `defaults.enabled`
  meant `UserDefaults.enabled` and the file did not compile. Renaming it exposed the real bug
  underneath: the model key was read for the **static** default provider, so a user on Groq
  would have been handed `voice.apiModel.openai`. The provider is now resolved first and the
  model is namespaced to it — pinned by
  `testSnapshotReadsTheModelNamespacedToTheStoredProvider`.
* **A test expectation was wrong, not the code.**
  `changedTokenCount("i want to go" → "I want to go home")` is **3** — one replacement counts as
  a removal *and* an addition — not 2. When a new test fails, ask which side is wrong first.
* **A genuine gap the vocabulary test found:** `APIProviderKind.labelKey` returns `OpenAI`,
  `Groq`, `Anthropic (Claude)`, … — brand names with **no diacritics**, so neither the literal
  sweep nor check A could see them. They are store entries on the `sameByDesign` allowlist now.

### pbxproj uses **two** ID lengths — never compute "the max"

An allocation built from `max(match of 7F1A[0-9A-F]{4})` returned `7F1A7F1A`, because the file
also contains 12-hex-character IDs such as `7F1A7F1A008D` and the regex matched their first eight
characters. **Pick a free block instead** (walk up from `7F1A0195`, skipping every ID already
defined) and assert no duplicates afterwards. Removing a file means scrubbing **all four** of
its lines; a leftover `PBXBuildFile` line stays invisible until something else breaks.

### The test package needs a symlink per new pure file

The package symlinks individual sources, so it does not follow a new type dependency by itself:
`VoiceProtocols.swift` began referencing `RefineRequest`, and the whole package stopped
compiling. Adding a file to the app target is **not** enough — a new pure file needs its symlink
in `Tests/XFinderLogicTests/` in the same change.

### Measured this pass

| Statement | Result |
|:--|:--|
| Build | `BUILD SUCCEEDED`, **0** errors, 17 Voice sources in the compile log **by name**, `lipo -archs` = arm64 |
| Tests | **289 tests, 0 failures** (263 → +26) |
| Gates | coverage `TOTAL 0` over **1553** entries · duplicates 0 · wrapped-literal sweep `TOTAL 0` · `verify-l10n-runtime.py` against the **installed** bundle: **TOTAL 0 leaks** |
| Whole-app sweep (multi-line aware) | **0** wrapped literals missing |
| Mutations (sequential, each restored byte-identical) | `changedTokenCount`, the interpolated `messageKey`, and a flipped snapshot default all went **RED**; post-restore suite 289/0 |
| Rendered page, English | **94 nodes, 0 Vietnamese** |
| Rendered page, Tiếng Việt | **94/97 nodes Vietnamese**; the 3 others are `Pin`, `Quick Look` (proper nouns) and the role-count line |
| Mouse & Gestures page, English | 127 nodes, 1 diacritic line — `App Exposé`, allowlisted |
| Event Tap | installed and **Running**; all three permissions granted |
| **Speaking into the microphone** | ❌ **not verified** — needs a human voice |

**`-startPage` does not survive `open --args` on an already-running app.** Two attempts measured
the previous page; `defaults write com.xfinder.app startPage -string voiceTyping` before the
launch worked. Delete the key afterwards — it persists and would pin every later launch.

## Phase 1 (2026-10-09) — ba control nói dối, và gate cho Part 0 §5

`FEATURE_KEYS_2026-10.md` (agent quét, kiểm lại bằng grep) tìm ra ba `Toggle` **không có reader**:
`windowPreview.showHiddenWindows` (nhãn hứa đổi danh sách ⌘-Tab, không làm gì), `clipboard.linkPreviews`,
`clipboard.intelligentSuggestions`. Câu *"zero stored-but-unread keys remain"* ở Part 3b là **sai** lúc nó
được viết — một câu trong tài liệu không phải gate.

| Khóa | Làm gì | Vì sao |
|:--|:--|:--|
| `showHiddenWindows` | **Nối.** Một reader duy nhất `WindowPreviewStore.showsHiddenWindows` + hàm thuần `listsWindow(ofHiddenApp:showHidden:)`; cả hai lister (`WindowPreviewStore.windowLister`, `WindowManager.listWindows`) gọi nó thay cho `if isHidden { continue }` | Có máy móc thật để nối; default `false` giữ nguyên hành vi cũ. **Thumbnail của cửa sổ app ẩn chưa đo** |
| `intelligentSuggestions` | **Nối** vào tab "Gợi ý" của shelf (`ClipboardIntelligenceEngine.isEnabled`), **và sửa nhãn**: engine là heuristic (recency · usageCount · pinned · role theo bundle ID), **không gọi FoundationModels**. Card từng ghi "Apple Intelligence" | Nhãn nói sai cơ chế = Part 0 §6, dù control có hoạt động |
| `linkPreviews` | **Xóa** toggle + 2 entry store | Không có gì để nối; fetch mọi URL vừa copy còn phá lời hứa local-only |

**Gate mới: `FeatureKeyDefaultsTests`** — đọc *source* của view (`@AppStorage("k") … = x`) và của **một**
reader Core (`object(forKey: "k") as? Bool ?? y`), đỏ khi `x != y`, khi **0 reader** (khóa chết / anchor mục)
và khi **>1 reader** (hai bản sao có thể lệch). Reader vì thế phải viết đúng dạng chuẩn đó. Đã chứng minh đỏ
bốn cách (đổi default engine · bỏ qua công tắc · đổi default view · xóa reader). Hiện phủ 6 khóa; mỗi khóa
mới thêm vào bảng `switches`.

**Bẫy gặp trong lượt này:** hook zsh `_zoxide_lazy` làm `cd` chết **im lặng** trong một chuỗi `a && b` —
`install-mouse-rebuild.sh` không chạy, nhưng `verify-l10n-runtime.py` ngay sau đó vẫn in `TOTAL 0` vì nó đo
**bundle cũ**. Luôn so hash binary build ↔ `/Applications` trước khi tin một gate runtime; chạy script cài qua
`/bin/sh -c 'cd … && …'`.

### GPU % (2026-10-09) — "không có API công khai" là SAI, và đây là phép đo

Ảnh Vorssaint hiện GPU 48 %. Luật dự án: *app khác làm được là bằng chứng ngược*. Probe
(`ioreg -r -c IOAccelerator -a` parse bằng `plistlib`, không grep text) + bộ đốt Metal compute:

| Trạng thái | `Device Utilization %` (n mẫu, 0.5 s) |
|:--|:--|
| nhàn (sau khi tải xong) | min 0 · median 1.5 · max 22 |
| đốt Metal 12 s (`sin/cos` 4000 vòng × 4M thread) | min 27 (lúc kết thúc) · **median 99 · max 100** |
| nhàn lúc có trình duyệt đang vẽ | median 51 — tức là con số **thật** phản ánh tải nền, không phải nhiễu |

Đường đọc: `IOServiceMatching("IOAccelerator")` → `IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics")`
→ `["Device Utilization %"]`. Không cần quyền. `GPUUtilization.swift` tách **parser thuần** (test được, `nil` khi
thiếu khoá — không bao giờ bịa 0) khỏi **reader IOKit** (cache `io_service_t`, re-resolve khi đọc hỏng). Reader
chạy trong `collectMetrics()` nên **cùng nhịp demand-driven** của `SystemMonitorManager` — không thêm timer.
Trang đã render đo bằng `probe-ax-dump` khi đang đốt GPU (xem commit). Ba mutation (bịa 0 khi thiếu khoá ·
đọc nhầm khoá Renderer · bỏ clamp) đều đỏ.

**Bài học lặp lại lần thứ năm trong file này:** "tao đo X và nó thất bại" chỉ chứng minh X chết, không chứng
minh tính năng bất khả thi. Row "GPU % — IOAccelerator not public" tồn tại nhiều tháng mà không ai probe lại.


### SMART flyout (2026-10-09) — và lỗ rò ngôn ngữ thứ SÁU: model trả CÂU HIỂN THỊ

Flyout in `SMART → "Không khả dụng"` trong khi trang Ổ đĩa **đã** đọc SMART thật qua `diskutil` — hai bề mặt,
một sự thật, hai câu trả lời. Khi vá mới thấy cái tệ hơn: `DiskManager.smartLabel` trả **"Bình thường" /
"Đang hỏng — sao lưu ngay" / "Ổ đĩa không hỗ trợ SMART"** từ tầng Core, trang render bằng `Text(label.text)`
**không bọc**, và store **không có** ba khóa đó. UI English hiện tiếng Việt ở card SMART — đúng bug shape #1
trong header của `check-l10n-coverage.py`, sống sót vì literal nằm ở Core (lint chỉ quét `Views/`) và
`audit-l10n-reachability.py` là report không ai đọc.

Sửa theo đúng mẫu đã dùng cho gesture:
* `Core/SystemMonitor/SMARTStatus.swift` (Foundation-only, symlink vào Tests): `parse(diskutilOutput:)` tách khỏi
  subprocess để test được với text `diskutil` thật; `label(forRaw:)` trả **khóa store**, view bọc `L10n.t`.
  Giá trị lạ đi qua nguyên văn (lời của OS, không bịa trạng thái).
* Flyout: `smartRow` + `.task` trên root → **một** `diskutil info /` mỗi lần mở popover, không bao giờ trên tick 2 s.
  Nhãn "SMART ổ khởi động" vì chỉ đọc mount `/` (flyout không có picker).
* Gate: `SMARTStatusTests.testEveryKnownLabelKeyIsTranslatedInTheStore` duyệt `knownRawValues` (guard = 3) và resolve
  từng khóa. 3 mutation đỏ (khóa không có trong store · parser cắt sai dấu `:` · giá trị lạ bị gán healthy).
* Đo: `probe-flyout-smart.swift` (AXPress status item → AXPress tab Ổ đĩa → dump) trên app đã cài, UI English:
  `Boot drive SMART → Healthy`, 0 chữ Việt.

**Rule rút ra:** mọi `static func … -> String` ở `Core/` mà có literal tiếng Việt là **nghi can** cho tới khi có test
resolve nó với store. Grep nhanh: `grep -rn 'return ("' XFinder/Core` và `grep -rnE 'return "[^"]*[À-ỹ]' XFinder/Core`.

**Review workflow bắt được một lỗi tao tự gây (2026-10-09):** `.task` của flyout đặt `smartChecked = false` rồi fetch,
nhưng **không xoá `smartRaw`** — mà `smartRow` kiểm `if let raw = smartRaw` *trước* `smartChecked`. Popover dùng
**một** `NSHostingController` sống suốt đời app (`setupPopover()` gọi một lần; `togglePopover` chỉ `show`/`performClose`),
nên `@State` **không** được tạo lại khi mở lại → từ lần mở thứ hai, trong lúc `diskutil` chạy, hàng hiện **kết quả cũ**
với vẻ chắc chắn, và nhánh "Đang kiểm tra…" là code chết. Trang Ổ đĩa có đúng lỗi này từ trước ở `.task(id: selectedMount)`
(đổi ổ → hiện SMART của ổ cũ vài chục ms). Sửa: xoá giá trị cũ **trước** khi fetch, ở cả hai chỗ.
**Rule:** với `@State` trong view được host lâu dài (popover, panel, status item), mọi `.task`/refetch phải **reset state hiển
thị trước**, vì `onAppear` không có nghĩa là state mới. Hai refuter độc lập xác nhận; hai lens còn lại (honesty/L10n,
correctness) trả 0 phát hiện — đã đọc journal để chắc là "không thấy gì", không phải "không chạy".

## Clean URL (2026-10-09) — Phase 1 #1, và hai cạm bẫy của việc *ghi* pasteboard

Job: *"Tôi copy một link; tôi không muốn dán `?utm_source=…&fbclid=…` vào chat."* Opt-in
`clipboard.cleanURLs` (default **false** — nó viết lại thứ người dùng copy nên phải được xin phép).

* `Core/URLCleaner.swift` (Foundation-only, symlink vào Tests). **Chỉ** hành động khi *toàn bộ* nội dung copy là
  **một** link `http(s)` — câu có chứa URL không bao giờ bị đụng. Chỉ xoá tham số trên **danh sách có tên**; các tên
  mơ hồ **gắn theo host**: `t=` là timestamp trên YouTube nhưng là token theo dõi trên X; `si=` chia sẻ ở YouTube/Spotify
  nhưng có thể là trường thật ở nơi khác. Một luật `t` toàn cục sẽ làm hỏng `youtu.be/…?t=90` (test ghim, và mutation
  "t thành global" đỏ). Fragment không bao giờ đụng (`#/route?utm_x` là routing phía client). Không xoá gì ⇒ trả `nil`,
  người gọi không ghi lại.
* **Cạm bẫy 1 — tự ingest chính mình.** Ghi pasteboard làm `changeCount` nhảy, monitor coi đó là một lần copy mới. Phải
  gán `lastChangeCount = pb.changeCount` ngay sau khi ghi; đo trên SQLite: mỗi lần copy đúng **một** dòng lịch sử, và là
  bản đã sạch.
* **Cạm bẫy 2 — race với ⌘V.** `ClipboardPasteEngine` ghi pasteboard rồi gửi ⌘V ~150 ms sau, và **không đánh dấu** write
  của mình, nên monitor sẽ "làm sạch" một mục *đang được dán* (`clearContents` rồi `setString` ngay dưới tay app đích →
  có thể dán rỗng). Sửa bằng `OwnWriteMark` (engine ghi `changeCount` của nó; monitor bỏ qua việc *làm sạch* cho count đó).
  **Không** đổi việc ingest — `usageCount` và de-dupe phụ thuộc vào nó. Phần này **chưa có test race** (cần ⌘V thật);
  `OwnWriteMark` có unit test, còn guard trong manager thì chỉ được chứng minh bằng đọc code.
* Gate: 14 test thuần + `FeatureKeyDefaultsTests` thêm khoá `clipboard.cleanURLs` (reader dạng chuẩn
  `object(forKey:) as? Bool ?? false`). 5 mutation đỏ (t global · không tách fragment trước · bỏ guard một-token ·
  host match theo suffix trần · đổi default reader).
* **Đo trên pasteboard thật** với app đã cài (`e2e-cleanurl.py` — pbcopy rồi poll pbpaste; âm tính chứng minh bằng cách
  đợi *quá* sàn poll 5 s, không phải kiểm quá sớm): 5/5 — A bỏ tham số giữ fragment, B YouTube giữ `t=90` bỏ `si`, C câu
  chứa link không đụng, D không có gì trong danh sách ⇒ nguyên văn, E tắt ⇒ nguyên văn. Clipboard sau khi làm sạch có
  cả `URL` lẫn `string`.
* **Cách đo không phá dữ liệu người dùng:** clipboard thật của họ có **HTML + text**; `pbcopy` chỉ lưu text sẽ mất HTML.
  `pb-save-restore.swift` lưu/khôi phục *mọi type của mọi item*; so kích thước từng type sau khi khôi phục (HTML 5468,
  utf8 3981). Test để lại 5 dòng `example.com` trong lịch sử clipboard của họ — phải nói ra, không giấu.

## Tự xóa clipboard (2026-10-09) — Phase 1 #2: cái guard mới là thứ có thể phá dữ liệu, không phải cái timer

Job: *"Tôi copy một token/mã OTP; nó không được nằm trên clipboard cả buổi chiều."* Opt-in
`clipboard.autoClearSeconds` (Int, default **0 = tắt**; chọn 30 s / 1 / 5 / 15 phút).

* `Core/ClipboardAutoClear.swift` (thuần, symlink vào Tests) giữ **ba luật**, vì chỗ nguy hiểm là điều kiện xoá chứ
  không phải đồng hồ: (1) **không bao giờ xoá thứ người dùng copy sau đó** — timer nhớ `changeCount` lúc được lên dây
  và chỉ xoá nếu nó vẫn là count đó; (2) **không bao giờ lên dây cho pasteboard rỗng** — `clearContents()` cũng bump
  `changeCount`, một monitor lên dây timer cho *mọi* thay đổi sẽ lên dây cho chính lần xoá của nó và xoá một clipboard
  rỗng mỗi N giây mãi mãi (test mô phỏng đúng vòng lặp đó); (3) **tắt = không có timer nào** (`delay == nil`), one-shot,
  không polling, nên mục tiêu idle 0 % không đổi.
* `scheduleAutoClear()` gọi **sau** `captureClipboardContent()`, không phải trước: cleaning có thể đã ghi lại pasteboard
  (count mới), và một copy **không được ingest** (Concealed / trình quản lý mật khẩu) vẫn cần timer — đó mới là copy mà
  tính năng này sinh ra để bảo vệ. Đo thật: bí mật Concealed *không* vào lịch sử (0 dòng) và *vẫn* bị xoá sau 32.2 s.
* **Nói thật trên nhãn:** nó xoá **pasteboard của macOS**, *không* xoá lịch sử XFinder (các bản copy thường vẫn nằm trong
  SQLite — đo được), và chỉ chạy khi XFinder đang mở. Một nhãn "tự xoá clipboard" im lặng về hai điều đó sẽ khiến người
  dùng tưởng bí mật đã biến mất khỏi mọi nơi.
* Đo trên pasteboard thật với app đã cài (`e2e-autoclear.py`, 5/5): A xoá sau 32.2 s · E Concealed xoá sau 32.2 s ·
  B bản copy cũ **không** xoá bản mới (còn nguyên ở +38 s, qua mốc của bản cũ) · B bản mới xoá 31.7 s sau chính nó · C tắt
  ⇒ không xoá. Cửa sổ kỳ vọng [30, ~36] s = delay + tối đa 5 s monitor phát hiện; âm tính chứng minh bằng cách đợi *quá*
  cửa sổ đó.
* Gate `FeatureKeyDefaultsTests` được **tổng quát hoá từ Bool sang Bool|Int** (literal giữ dạng text) để phủ khoá số;
  fixture kiểm cả `-1` và kiểu đọc khác (`Double`) không bị nhận nhầm là reader. 4 mutation đỏ (bỏ so `changeCount` ·
  lên dây trên pasteboard rỗng · "tắt" vẫn trả delay · đổi default reader 0→60).
* Picker dùng `.menu` + `frame(width: 110)`: 5 lựa chọn vượt giới hạn 4 nhãn ngắn của `.segmented` (Part 3c).

## Giữ ⌘Q để thoát (2026-10-09) — Phase 1 #3: tính năng đầu tiên chặn phím toàn hệ thống

Job: *"một cú ⌘Q lỡ tay không được đóng công việc của tôi."* Opt-in `quitProtection.enabled` (default **false**), một control
duy nhất ở **Điều khiển nhanh ▸ Cửa sổ** (không nhân đôi). Nhấn nhanh ⌘Q bị nuốt; **giữ ~1 s** thì app đang frontmost lúc
bắt đầu bấm bị `terminate()` (tương đương menu Quit — vẫn hỏi lưu tài liệu). Nhả sớm / nhả ⌘ / Esc ⇒ huỷ.

* **Mọi luật nuốt-hay-cho-qua nằm trong `QuitHold.Machine`** (thuần, 17 test), vì sai ở đây = **mất phím Q toàn hệ thống**.
  Bốn tính chất, mỗi cái có test và mutation đỏ: (1) *mất một `keyUp` không được làm kẹt* — một lần bấm mới (không repeat)
  luôn bắt đầu hold dù máy đang ở trạng thái nào; (2) *giữ tiếp sau khi thoát không dây chuyền* — repeat ở `fired` bị nuốt,
  một cú giữ thoát **đúng một** app; (3) *repeat khi `idle` không phải hold* (bật giữa chừng, tap vừa re-arm); (4) *huỷ phải
  sống lâu hơn phím*.
* **Lỗ thiết kế tao tự bắt được khi nghĩ tới bàn phím thật, không phải nhờ test:** Esc huỷ hold nhưng người dùng **vẫn giữ Q**
  và bàn phím vẫn bắn auto-repeat `⌘Q`. Máy ban đầu về `idle` ⇒ repeat đầu tiên **lọt tới app và thoát nó** — Esc huỷ không
  huỷ gì. Thêm trạng thái `cancelled` (nuốt repeat tới khi nhả Q). Bài duyệt vét cạn mọi chuỗi ≤4 sự kiện (>1000 chuỗi) chứng
  minh "không chuỗi nào làm kẹt lần bấm kế" — và nó đã bắt mutation kẹt-phím ngay (397 failure).
* `tapDisabledByTimeout`/`ByUserInput` ⇒ **reset máy** + re-arm: sự kiện đã rơi, không tin trạng thái cũ. Finder/Dock/loginwindow
  **không bao giờ** bị chặn (⌘Q vô nghĩa ở Finder; HUD hứa một cú thoát không thể xảy ra là nói dối). ⌘⇧Q (Đăng xuất),
  ⌘⌥Q, ⌃⌘Q **không** phải chord. Caps Lock/Fn/numpad bit không làm đổi chord.
* **Quyết định phải đồng bộ** (nuốt hay cho qua ngay lúc này) ⇒ callback tap chạy trên **main run loop** và dùng
  `MainActor.assumeIsolated` trả `Bool` (Sendable), không hop `Task`. Chi phí: không polling; HUD là **một** animation SwiftUI;
  timer duy nhất là một `DispatchWorkItem` one-shot chỉ tồn tại trong lúc đang giữ. Tắt ⇒ không tap, không timer, **không
  cửa sổ** (đo: 0 HUD window khi tắt và khi rảnh).
* **HUD: đo trước khi tin cảm giác.** Tạo `NSPanel`+`NSHostingController` *trong callback tap* đo được **0.15 s thường, 0.65 s
  lúc lạnh, và còn lưu 0.45 s sau khi nhả** — HUD hiện ở 65 % của cú giữ 1 s thì vô dụng. Sửa tận gốc: `prepare()` một lần khi
  bật tap (layout sẵn, ordered-out), mỗi lần giữ chỉ đổi `QuitHoldHUDModel` + `orderFront`; `destroy()` khi tắt. Đo lại:
  hiện **+0.13–0.20 s**, lưu **0 s** sau khi nhả. Thanh tiến trình tính từ `startedAt` của timer (không phải `onAppear`) để
  **kết thúc đúng lúc app thoát** — bản đầu chỉ đạt ~80 % khi thoát.
* **Đo trên hệ thống thật** (`e2e-quithold.py`, ⌘Q tổng hợp bắn vào Calculator): 10/10 — tắt thì tap thoát (harness hợp lệ) ·
  bật thì tap **không** thoát · HUD hiện khi giữ, biến mất sau khi nhả · Esc giữa chừng, Calculator sống qua 1.6 s auto-repeat ·
  giữ đủ thì thoát + HUD ẩn · Finder ⇒ không HUD.
* **Ba lỗi của CHÍNH harness, mỗi cái hỏng theo một hướng — đây là bài học đáng giữ nhất:**
  1. regex `LSDisplayName` sai (`lsappinfo` in `"Calculator" ASN:…`) ⇒ kiểm frontmost luôn `None` ⇒ **chặn mọi lần bắn**
     (hỏng an toàn, nhưng 0/2).
  2. mỗi kịch bản nằm trong `if front(...):` **không có `else`** ⇒ khi kéo app lên trước thất bại, kịch bản **biến mất lặng
     lẽ** và "7/7 passed" in ra trong khi 3 kiểm tra không hề chạy (hỏng **im lặng xanh**). Sửa: `else` ⇒ FAIL, và tổng kết
     đòi **đúng 10 kiểm tra đã chạy**, thiếu là fail.
  3. bộ lọc HUD đòi 340×88, thực tế SwiftUI co panel còn 82 ⇒ báo "HUD không hiện" khi nó hiện. Phân biệt "probe sai" với "HUD
     sai" bằng cách **in mọi cửa sổ** thay vì đoán.
  **Rule:** một harness e2e phải đếm số kiểm tra kỳ vọng; "tất cả những gì đã chạy đều đạt" không phải là "đạt".
* **An toàn khi bắn phím:** `post-cmdq` gửi ⌘Q cho app frontmost nên script kiểm frontmost **ngay trước mỗi lần bắn** và huỷ nếu
  không phải Calculator; không bao giờ bắn ⌘⇧Q; từ chối chạy nếu Calculator đang được dùng.
* **CHƯA verify (nói thẳng):** đường **bàn phím thật** nhả ⌘ trước Q (`flagsChanged` → `commandReleased`) chỉ có unit test —
  sự kiện tổng hợp không dựng lại được; **phục hồi `tapDisabledByTimeout`** không kích hoạt được; app có handler ⌘Q riêng
  (Chrome "cảnh báo trước khi thoát") bị bỏ qua vì `terminate()` không qua key-equivalent; tương tác với tap khác (⌘-Tab) chưa
  đo; và cảm giác khi **tay người** giữ phím thì cần người thử.

## Chọn thiết bị âm thanh ra (2026-10-09) — Phase 1 #4: vá một listener leak mà tính năng này sẽ kích hoạt

Job: *"phát âm thanh qua đúng cái tai nghe/loa tôi muốn mà không mở System Settings."* **Không có khoá UserDefaults nào** —
nguồn sự thật là controller (`AudioOutputDevices`), nên không có chuyện hai control một khoá (Part 0 #4). Hiện ở
**Điều khiển nhanh ▸ Hệ thống** (Picker `.menu`) và trong **flyout** (Menu, *chỉ khi có >1 thiết bị* — không gian flyout quý).

* **Đo máy này trước khi thiết kế:** CoreAudio liệt kê **3** thiết bị nhưng chỉ **1** là output (MacBook Pro Speakers); hai cái
  còn lại là micro (một cái là "Wifi Microphone" của Continuity, transport `ccwd`). Một danh sách ngây thơ sẽ mời người dùng
  "phát âm thanh qua micro". `AudioOutputList.build` lọc theo **số kênh output > 0**, không ẩn, còn sống, có tên, khử trùng theo UID.
  Với một thiết bị duy nhất thì UI là **dòng chữ + giải thích vì sao**, không phải Picker một mục.
* **Không có thiết bị thứ hai để thử ⇒ tự tạo:** `AudioHardwareCreateAggregateDevice` (API công khai, không cần quyền) dựng một
  aggregate từ loa built-in. Harness biên dịch **đúng file production** (`AudioOutputList`, `AudioOutputDevices`, `SystemControls`
  với stub `L10n` một dòng) và chạy trên CoreAudio thật: 19 kiểm tra. Luôn khôi phục thiết bị mặc định cũ, huỷ aggregate, kể cả
  khi bị signal; sau mỗi lần chạy kiểm `devices: 3 default=71`.
* **Lỗi có sẵn trong `VolumeObserver` mà tính năng này sẽ kích hoạt:** `start()` đăng ký listener **mức hệ thống** "đổi thiết bị
  mặc định" mỗi lần được gọi và **không bao giờ gỡ**, trong khi mỗi lần đổi thiết bị gọi `stop(); start()` ⇒ mỗi lần đổi
  **thêm một bản** ⇒ số callback **nhân đôi** theo mỗi lần đổi. Đo bằng bộ đếm chẩn đoán `rebindCount`: bản lỗi cho **63 lần
  rebind trên 6 lần đổi** (= 2⁶−1); bản sửa cho đúng **6**. Lỗi thứ hai cùng chỗ: nếu lúc gắn lại không có output nào
  (`deviceID == 0`) thì `start()` thoát **trước khi** đăng ký listener hệ thống ⇒ observer điếc vĩnh viễn kể cả khi thiết bị
  cắm lại. Sửa: tách listener hệ thống (đăng ký **một lần**, gỡ khi release về 0) khỏi listener theo thiết bị (`rebind`).
* **Hai default, một luật có nguyên tắc:** macOS có *default output* và *system output* (nơi phát âm báo). Chỉ chuyển system
  output theo khi nó **đang trùng** default cũ; ai cố ý tách riêng (báo động ở thiết bị khác) thì không bị phá. Đo bằng **ba**
  thiết bị (default=A, alert=B, chọn C ⇒ alert vẫn ở B).
* **Một kiểm tra của chính harness từng vô nghĩa:** bản đầu kiểm "alert không bị kéo theo" chỉ với **hai** thiết bị, nên "không bị kéo
  theo" và "bị kéo theo" kết thúc ở **cùng** một thiết bị ⇒ kiểm tra luôn đạt. Bắt được bằng cách tự hỏi *kiểm tra này có thể đỏ
  không*; sửa bằng aggregate thứ hai. Mutation "luôn kéo theo" sau đó mới đỏ đúng (`alert=118, B=115, C=118`).
* **Tin readback, không tin mã trả về:** `AudioObjectSetPropertyData` với **device ID không tồn tại** trả `noErr` (đo được:
  `lastError = "default output is still 71"`). `select()` đọc lại `currentID` và báo lỗi nếu không đổi.
* **4 mutation chạy trên harness thật, cả 4 đỏ:** luôn kéo system output · khôi phục listener leak (rebinds=63) · tin mã trả về ·
  mời thiết bị chỉ-input (5 fail). 351 test, 0 fail. 8 test thuần (`AudioOutputListTests`, gồm: mọi transport ↔ một SF Symbol
  **tồn tại thật** — `Image(systemName:)` hỏng im lặng; mã `usb ` có dấu cách).
* **Đo trang đã render qua AX** (bản đã cài): một thiết bị ⇒ dòng "MacBook Pro Speakers" + lời giải thích, `AXPopUpButton` = 0;
  aggregate xuất hiện **lúc trang đang mở, không thao tác** ⇒ `AXPopUpButton` = 1; aggregate mất ⇒ về 0. Flyout: ca hai thiết bị
  có một popup mang nhãn thiết bị. Probe flyout ban đầu **mơ hồ** vì đọc cả cửa sổ chính (đang ở trang có Picker âm thanh);
  loại nhiễu bằng cách cho cửa sổ chính mở trang khác.
* **CHƯA verify:** thiết bị thật (tai nghe BT, AirPods, AirPlay, HDMI) — chỉ aggregate; chọn thiết bị bằng **click** qua UI (mục
  menu SwiftUI không nằm trong cây AX khi đóng; logic `select()` được chứng minh qua harness, phần binding Picker thì mỏng);
  và việc nối âm lượng theo thiết bị mới (`VolumeObserver` rebind đúng, nhưng giá trị âm lượng của thiết bị không có
  volume scalar — như aggregate — chưa kiểm).

## Lấy màu từ màn hình (2026-10-09) — Phase 1 #5: harness của tao suýt tự đánh lừa, và hai cửa sổ "ma" của macOS 27

Job: *"tôi cần mã hex của một màu đang thấy trên màn hình."* **Không có khoá cài đặt** (là một hành động, không phải một công tắc).
Hàng **"Lấy màu từ màn hình"** trong flyout ⇒ đóng popover (nếu không nó che đúng chỗ cần lấy) ⇒ 0.2 s ⇒ `NSColorSampler`
(kính lúp của hệ thống, API công khai) ⇒ đổi sang **sRGB** ⇒ `#RRGGBB` lên pasteboard ⇒ toast "Đã sao chép" ~1.8 s. Clipboard
manager tự ghi nó thành mục **Màu sắc** vì `#RRGGBB` chính là thứ `ClipboardClassifier` gọi là `.color`.

* `Core/ColorFormat.swift` (thuần, 5 test): **làm tròn, không cắt** (0.5 → 0x80; cắt cho 0x7F làm mọi tông giữa tối đi một nấc),
  **kẹp** giá trị ngoài gamut (màn hình wide-gamut đổi sang sRGB có thể lệch ra ngoài 0…1; không kẹp thì kênh thành 3 chữ số
  hoặc quấn sang màu khác), NaN/±inf = 0 (`Int(NaN)` trap — một bộ chọn màu không được làm sập app). 3 mutation đỏ.
* **Đo trên `NSColorSampler` thật** (`color-e2e harness`, biên dịch **đúng lớp production**): ô sRGB(255,136,0) ⇒ sampler trả
  `#FF8800` — **Δ = 0,0,0**, kể cả phép đổi không gian màu màn hình → sRGB. Esc huỷ, clipboard không bị đụng.
* **Đo đường thật qua app đã cài** (`e2e-colorpick.py`, 6/6): AX bấm hàng flyout ⇒ sampler *của XFinder* hiện ⇒ cửa sổ mục
  tiêu `#3A7BD5` tự bấm vào tâm nó ⇒ pasteboard **đúng** `#3A7BD5` ⇒ toast hiện rồi **tự tắt** ⇒ SQLite ghi `type = color`.
* **Click tổng hợp là hành động không rút lại được ⇒ có cổng an toàn cứng:** chỉ bấm sau khi xác minh *cửa sổ thật trên cùng tại điểm
  đó là của chính process này*. Cổng này **từ chối hai lần đầu và đúng cả hai lần** — nhưng vì hai thứ tao chưa biết:
  1. lớp phủ toàn màn hình của hệ thống `ColorSampler` (layer 2147483631) nằm trên mọi thứ khi đang pick — nó **là** thứ nhận click,
     không phải "app thứ ba chắn đường";
  2. **macOS 27 giữ một cửa sổ Dock toàn màn hình thường trực ở layer 20** (đã ghi từ vòng Mission Control). Cả hai phải được bỏ
     qua; cửa sổ **bên dưới** chúng mới phải là của mình. Khi từ chối, in cả danh sách cửa sổ trước-sau để không phải đoán.
* **Bài kiểm tra không kiểm soát được đầu vào thì không chứng minh gì.** Hai lần đầu ra `lastPicked = #757575` rồi `#FCFCFC` — màu
  "từ trời rơi xuống" — vì kính lúp nằm trên màn hình của **người dùng đang ngồi đó** suốt 4 s trong lúc harness đợi, và họ bấm
  vào nó. Sửa: bấm ngay khi kính lúp vừa hiện (~1.4 s), bắt buộc về trạng thái sạch trước pha Esc, và **dừng sớm** (không chạy
  tiếp pha sau) nếu pha trước không xong sạch.
* **Hai lỗi nhỏ của chính harness** (cả hai hỏng theo hướng "báo đỏ sai", lần này không phải xanh sai): so `"click posted: True"` với
  chuỗi Swift in `true` chữ thường; đếm kỳ vọng 7 trong khi thật sự có 6 kiểm tra. Hai test của tao cũng có lỗi cú pháp (`for a in x,
  b in y` không tồn tại trong Swift) và một kỳ vọng vô nghĩa (`replacingOccurrences`) — **đọc lại test của chính mình trước khi tin nó**.
* **Khôi phục clipboard thật của người dùng:** mỗi lần chạy đều `save` clipboard **hiện tại** (mọi type) rồi `restore`; lần này nó đã
  khác hẳn lần trước (ảnh PNG/AVIF thay vì HTML) — dùng bản sao lưu cũ sẽ ghi đè thứ họ vừa copy.
* **CHƯA verify:** *có cần quyền Ghi màn hình không?* — harness chạy dưới terminal **đã có** quyền (`CGPreflightScreenCaptureAccess =
  true`) và quyền gắn theo process chịu trách nhiệm, nên không cô lập được. (Sampler chạy trong process hệ thống riêng `ColorSampler`
  nên có thể không cần — **chưa đo**.) Màu ngoài sRGB bị kẹp (đã test logic, chưa thử màn hình P3 thật). Chưa có phím tắt toàn cục:
  phải mở flyout.

## Features hub (2026-10-09) — Phase 2: một công tắc, ba bề mặt, và catalog được kiểm với engine bằng source

Trang **Tính năng & Quyền** (CHUNG, sau Tổng quan): tab *Tính năng* (thẻ tổng "n / 12", Bật/Tắt tất cả, 3 gói Cửa sổ / Clipboard và
tìm kiếm / Yên tĩnh, từng dòng có badge chi phí idle) và tab *Quyền* (4 quyền: Trợ năng, Ghi màn hình, Micro, Nhận dạng giọng
nói — Đã cấp/Chưa cấp, "Dùng bởi", cảnh báo quyền thừa, nút mở đúng pane). Bố cục theo ảnh tham chiếu; **không** chép tên/logo
(repo tham chiếu GPL-3.0, thương hiệu riêng).

* **Hub không giữ trạng thái.** Tính năng bật/tắt theo **chính khoá UserDefaults mà engine đọc** (`FeatureHub.set` = ghi khoá +
  `applySettings()` y như công tắc riêng của trang đó), nên hub, trang riêng và flyout là ba góc nhìn của một khoá.
* **Nhãn là "Bật/Tắt", không phải "Uninstall/Install" như ảnh:** tính năng chỉ dừng chứ không bị gỡ; nhãn phải đúng điều nó làm.
  Hàng sidebar **không** bị ẩn (quyết định của chủ dự án): trang của tính năng đang tắt vẫn mở được.
* **Gate làm catalog không nói dối:** `FeatureCatalogTests` đọc **source Core** và đòi: mỗi `enabledKey` được engine đọc đúng dạng
  `object(forKey:) as? Bool ?? x` (kể cả khi đi qua hằng `static let enabled = "voice.enabled"` — test đầu **đỏ** vì regex chỉ biết
  literal, đã dạy nó giải hằng thay vì nới lỏng), và **mọi** lần đọc có default == `defaultOn` của catalog; không hai tính năng chung
  khoá; badge idle trung thực (`folderSync` có timer ⇒ không được là "không chạy nền"; mọi thứ có event tap ⇒ không idle);
  gói **Yên tĩnh được dẫn xuất** từ catalog (mọi tính năng `isBackgroundActive`), không liệt kê tay — thêm tính năng lắng nghe sau này
  tự bị Yên tĩnh tắt. Duyệt mọi khoá L10n của catalog (chuỗi đi qua `L10n.t(biến)` mà literal sweep mù) kèm allowlist.
  7 mutation đỏ.
* **Đo trên app đã cài, thật** (`e2e-hub.py`, AX + `defaults` thật, 13/13 và đủ 13 kiểm tra đã chạy): *Tắt tất cả* ⇒ cả 12 khoá false trong
  defaults và trang ghi "0 / 12"; *Bật tất cả* ⇒ 12 khoá true, "12 / 12"; gói *Yên tĩnh* ⇒ đúng 9 tính năng có tap/timer tắt, 3 tính năng
  không chạy nền còn bật; tab *Quyền* liệt kê 4 quyền + Đã cấp/Chưa cấp + nút mở Cài đặt; 0 chữ Việt. Số "5 / 12" ban đầu được **tính
  độc lập từ defaults** (5) rồi so với trang — không tin con số chỉ vì nó trông hợp lý. Khôi phục defaults gốc **đúng từng khoá, kể cả
  khoá vốn không tồn tại**, trong `finally`.
* `audit-l10n-literals` "unwrapped" tăng 232 → 275: đúng **43 khoá của `FeatureCatalog`** (khoá model, có test resolve) — không phải rò rỉ.
* **Phát hiện chưa xử lý:** `PermissionManager.requestAllIfNeeded()` xin Trợ năng + Ghi màn hình + Bluetooth **ngay lúc khởi động**, trái lời
  hứa "chỉ xin quyền khi cần" của hub. Và bật `voice` qua *Bật tất cả* có thể kích hoạt hộp thoại mic/speech của macOS — chưa đo.
* **Chưa làm:** dựng lại flyout theo ảnh (tab icon, mục gập `6/6`), onboarding, export cài đặt, trang Cổng đang mở (logic thuần
  `PortList` đã xong + 20 test, **chưa có UI**), ô tìm sidebar.

## Flyout dựng lại (2026-10-09) — header, thanh tab, tab "Tính năng"

`MenubarFlyoutView` giữ cấu trúc tab cũ và đổi đúng những chỗ ảnh tham chiếu khác: header (icon app + tên + pill **chỉ báo một điều thật**: Mac
đang được giữ thức khi Chống ngủ bật), thanh tab bo tròn chia đều, và tab mới **Tính năng**: bốn nhóm gập được (`WINDOWS AND DOCK 1/4`,
`CLIPBOARD 2/3`…) với thẻ có công tắc, nối thẳng vào `FeatureHub` — cùng khoá với Features hub và trang riêng của từng tính năng.
Cửa sổ chính, flyout và hub là ba góc nhìn của một khoá nên không thể lệch.

* **Đo (app đã cài, AX):** số đếm nhóm khớp phép tính độc lập từ `defaults` (1/4, 2/3, 1/4, 1/1); bấm công tắc thật trong popover ⇒
  khoá `windowPreview.hoverEnabled` đổi 0→1→0 và tiêu đề nhóm đi theo; trả lại giá trị gốc.
* **Popover KHÔNG nằm trong `AXWindows`** — nó treo dưới cây của **status item** (`AXExtrasMenuBar`), và cây đó phải **lấy lại sau khi
  mở** (tham chiếu lấy trước là cũ). Probe đầu quét cả cửa sổ chính nên **lẫn sidebar + trang About vào nội dung flyout** và nút nó bấm
  khớp "features" có thể là hàng sidebar; chỉ kết luận được sau khi tách phạm vi vào cây status item.
* **Cây AX của popover cần thời gian dựng, và một popover vừa đóng còn đang animate:** probe mở nó ngay sau lần đóng trước (~1 s) thấy
  "0 công tắc" và lần đầu thì không in gì. Hai lần "thất bại" đều là độ trễ của *bài đo*; sửa bằng **thăm dò tới khi sẵn sàng** thay vì
  `sleep` cố định. Quy tắc: một thất bại đo không giải thích được **không** được gạt đi — chạy lại có chẩn đoán cho tới khi hiểu.
* **Chưa làm / chưa đo:** kính mờ (`NSVisualEffectView`) và hình thức thật của popover (`screencapture` vẫn hỏng, nên **chưa ai nhìn thấy nó**);
  nút "List", mục gập cho các tab khác ngoài Tính năng.

### SoC temperature (2026-10-10) — "SMC private ⇒ no CPU/GPU °C" was wrong, again

Probe (`IOHIDEventSystemClient`, vendor page 0xFF00 usage 5, no root): 46 temperature services on this M3 Pro —
`PMU tdie1…tdie10` (SoC die, 47–49 °C idle), `PMU tdev*`, `PMU tcal`, `NAND CH0 temp`, and `gas gauge battery`
(34.7 °C, equal to the IORegistry battery temperature — independent confirmation of the °C scale). Undocumented
SPI, resolved with `dlsym` (`ThermalReader`); missing symbol ⇒ `[]` ⇒ "Không khả dụng". `ThermalSensors.summary`
keeps only `PMU tdie*` readings in 5…125 °C (NaN/0/sentinels dropped; all dead ⇒ nil, never 0 °C). Labelled **SoC**,
not CPU: no key says which sensors belong to CPU cores. System page matched an independent probe (51/53 vs 51.0/52.4).
`@_silgen_name` on a `static` method gets the METHOD convention and, with a second declaration of the same symbol,
breaks the Release (whole-module) build while Debug builds fine — one free-function declaration in `AXWindowID.swift`.

### Alerts (2026-10-10) — Notification Center refuses self-signed builds; ship our own banner

`AlertRules` (pure: sustained + hysteresis + cooldown, 11 tests) · `AlertMonitor` (30 s timer only while
`alerts.enabled`, own cheap readers — never retains the 2 s metrics tick) · `AlertBanner`. Measured on
macOS 27 with the `XFinder Dev` signature: `UNUserNotificationCenter` returns `authorizationStatus = Denied`
without ever prompting, `usernoted` drops each record as `sourceIneligibleForIndexing`, the app never appears
in System Settings ▸ Notifications, and a minimal test app with the same signature gets
`UNErrorDomain 1 "Notifications are not allowed for this application"` — a single LS registration did not
change it (stale build-dir registrations were also purged). So delivery is XFinder's own `.statusBar` panel
(no permission), with UN as best-effort when authorized. `alerts.lastFired` persists so a relaunch cannot
re-alert within the cooldown (measured: relaunch ⇒ 0 new entries). The page says this plainly instead of
offering a Settings button that leads to a pane the app is not listed in.

### Menu bar readouts (2026-10-10)

`MenuBarReadouts` (pure: selection codec, fixed-width formatting with FIGURE SPACE U+2007 so the title never
jitters, "–" for unavailable, 8 tests + 3 mutations red) · `MenuBarReadoutsController` (one timer only while
`menubar.readoutsEnabled`; each tick is `SystemMonitorManager.sampleNow()` — a one-shot of the existing readers,
no duplicate samplers — unless a page/popover already has the monitor ticking, in which case readouts follow
that cadence through `SystemMonitorManager.onUpdate`). Measured on the installed app via the status item's
AX title: `CPU  33%  RAM   23G   51°`, width 216 px constant across ticks; empty selection ⇒ icon-only (34 px);
"Turn all off" in the hub clears it. **First-tick trap:** CPU is a delta since the previous sample, and right
after launch that is the launch burst — the first title read 89 % on an idle Mac; `start()` now seeds one quiet
sample and renders 1 s later. The allowlist requires a store entry with identical `en` (CPU/RAM/GPU), not just
the allowlist line — `check-l10n-coverage.py` flags the latter as a stale exception.

**Agents also write probes into the repo root despite being told the scratchpad path (2026-10-11, twice: `music.sdef`
from a research agent, then 17 `probe_*`/`t*.c`/`t*.swift` files from review refuters).** They show up as `??` in `git status`
and would ride along with any `git add -A`. Always stage by explicit path, and `git status` after every workflow.

**Review-workflow subagents ran `git push origin main` (twice) and `git checkout -- <file>` on their own (2026-10-10).**
The push shipped an unpushed commit without the user asking; the checkout wiped an uncommitted L10n fix, which then had to
be redone. Every workflow/agent prompt that touches this repo must say: read-only — no `git push`, `git commit`, `git checkout --`,
`git stash`, `git reset`; probes go in the scratchpad. Commit uncommitted work BEFORE launching reviewers.

### Phase A (2026-10-10) — tokens, flat pages, and three things the gates had been blind to

* **`\"` in a store key is a key that can never match.** `L10n.t("… (\"Report 2\").")` receives `("Report 2")` at runtime; the
  migration script had stored the *source* spelling with backslashes, so three entries sat in the store "translated" while the
  English UI rendered Vietnamese — and every gate said green, because `audit-l10n-literals.py` compared the same escaped form.
  The audit now unescapes before lookup. The only thing that caught it was reading the rendered AX tree
  (`scripts/sweep-pages-ax.py`: every page via `xfinder://settings?page=…`, both languages). Run it after any string work.
* **Copy pasted from the reference app was false on this app.** Nén & Giải nén claimed "7-Zip 26.02 built in" and 7Z/RAR/XZ
  extraction; the engine is `ditto`/`zip`/`tar`, and no 7z binary exists in the bundle. Two strings still said "MFinder".
  Honesty Rule applies to prose, not just numbers — grep `MFinder|7-Zip|RAR` before shipping copy.
* **A gate with a non-greedy regex spanning two controls produces confident wrong fixes.** `audit-ui-tokens.py` read
  `Picker(…).pickerStyle(.segmented)` across *two* pickers, flagged a 2-option picker as "over a ForEach", and an agent dutifully
  turned it into a menu. Scope a rule to the nearest declaration; a gate that is wrong is worse than no gate.
* **Parallel page conversion worked because the boundary was files, not features**: 18 read-write agents, each confined to its own
  `Views/Detail/*.swift`, forbidden from Components/Core/App/JSON/pbxproj/git/build; new strings reported, not written. Result:
  zero collisions, one compile error (mine). Register strings and build once afterwards.

## Notch surface — B1 (2026-10-10): the tray moves into the notch

Job: *"giữ tệp tạm ở notch: kéo vào để giữ, kéo ra để dùng."* `NotchDropController` (shake-only, 600 lines,
notch summon commented out, two dead keys) is deleted; the surface is `Core/Notch/`:

| File | Pure? | Holds |
|:--|:--|:--|
| `NotchSurfaceMachine.swift` | yes (symlinked) | every open/close rule: collapsed · peek · expanded, anchor notch/pointer — 17 tests incl. a 4 681-path walk |
| `NotchSurfaceLayout.swift` | yes | sizes, frames, hover zone, drag zone — 9 tests |
| `NotchDragSession.swift` | yes | "is THIS press a file drag?" — 6 tests |
| `NotchSurfaceController.swift` | AppKit | monitor pair, one-shot dwell/grace/shrink items, `SurfacePanel(.notch)` built once |
| `Views/NotchSurfaceView.swift` | SwiftUI | model, `NotchShape`, badge/peek/hub, tray pieces moved from the old controller |

Triggers, each behind its own key (all read at point of use, all bound on the Khay thả page, all in
`FeatureKeyDefaultsTests`): file drag into the notch zone → hub at the notch (`dropTray.notchDropEnabled`) ·
shake during a file drag → hub **at the pointer** (`dropTray.shakeEnabled`, `shakeSensitivity`) · resting on
the notch **while files are held** → peek (`dropTray.hoverEnabled`) · click badge/peek or the Finder URL → hub.

Decisions, with the reason each one exists:
* **Shake keeps opening at the pointer** ("Lắc giữ nguyên"): ShakePin's point is that the in-flight drag does
  not travel. A drag that later reaches the notch does not yank an open pointer tray away.
* **A shaken tray holding files never auto-closes** (the Part 3c "vanished after drop" rule). At the notch the
  surface collapses to a **count badge** instead; files stay one hover + one drag away (the peek's left icon is a
  drag handle for every held file — a separate region from the click-to-open text, since one press cannot be both).
* **Hover never reveals an empty tray, and the hover zone is the bare notch unless files are held.** The strip
  under the notch is the centre of every window's title bar; grabbing one must not count as hovering.
* **No click-outside dismissal.** Clicking another window to prepare the destination is part of the task.
* `dropTray.autoCloseDelay` is no longer read (leave grace is a fixed 0.8 s); nothing binds it.
* The badge needs a real notch to hang from; notch-less screens get peek/hub only (pill = B7).

Traps found this pass:
* **The drag pasteboard keeps the last file drag forever** — recorded in Part 3c; `NotchDragSession` is the fix.
* **A locked screen makes every AX tree "empty".** With `CGSSessionScreenIsLocked = 1`, `AXWindows` returns each
  app's *application* element (Calculator too, XFinder not running), System Events says "Invalid index", TCC still
  answers `authValue=2`. The 33-page sweep printed 0 nodes everywhere. `probe-ax-dump.swift` now exits 3 and
  `sweep-pages-ax.py` aborts. Never post synthetic mouse/keyboard events while locked — they reach the lock screen.
* **A mutant that does not compile is not a pass.** `guard … else { return }` → bare `return` made Swift parse the
  next line's `if` as the return value (if-expressions), so the mutant failed to build and the first script read
  "no result" as GREEN. `mutation-check-notch.sh` now exits 2 on no result. Result: **8/8 RED**.
* `log` is a shell alias in this user's zsh; use `/usr/bin/log`.
* Global-monitor handlers now go through `runOnMainActor` (SurfacePanel.swift): synchronous on main, `Task`
  otherwise — `assumeIsolated` would trap system-wide on the first mouse move if AppKit ever called off-main.

Four results, separately: build ✅ (all 5 files in the compile list, arm64) · tests ✅ 488/0 · gates ✅ (L10n ×6,
UI tokens, runtime against the installed bundle) · **live behaviour ❌ not verified** — the screen was locked for
the whole pass. Still to measure on an unlocked session: a file drag to the notch opens the hub and the drop lands
in the store; a window title-bar drag through the notch does NOT open it; hover on the badge peeks; a shake opens
the tray under the pointer; the peek handle drags every file out; the pointer tray survives the pointer leaving.

### Feature contract gate (2026-10-10) — and a wrong sentence about the test package

`Tests/XFinderLogicTests/FeatureContractTests.swift` enforces REDESIGN_PLAN §2.1: every `FeatureCatalog` feature
has a row — either `.pure([files])` (each file exists, is symlinked into the package, does not import SwiftUI, and
declares a type some test mentions) or `.exempt("… Fix: …")`. Exemptions may only shrink (cap 6). Today: 8 pure,
6 exempt (snapZones, clipboardShelf, suggestions, quickSearch, edgeNotes, folderSync — each names its fix).
Three mutations red (drop a row · list a non-symlinked file · add a seventh exemption).

**Why a table, not a naming rule:** the plan's `Core/<Feature>/<Feature>Model.swift` convention matched 2 of 14
features, and the mapping cannot be guessed from names (`QuitHold.swift`, `AlertRules.swift`).

**Correction — the test package is NOT Foundation-only.** Earlier sections say a file importing IOKit/AppKit
"cannot be tested". Measured: 12 symlinked files import AppKit or IOKit (`WindowPreviewStore`, `GPUUtilization`,
`ThermalReader`, the Battery readers, `SpaceBinding`…) and the macOS package compiles them. The real limits are
that the package cannot link the app target, and that asserting on anything needing a running app or a granted
permission is theatre. The gate therefore bans only `import SwiftUI` in a rules file.

### B1b — what the adversarial review caught (2026-10-10)

Five lenses, two refuters per finding, on commit ac45a05: **4 confirmed, 2 split (both refuters agreed the mechanism
was real, disputed only severity), 0 refuted.** All six fixed:

| Finding | Fix |
|:--|:--|
| Every control needed **two clicks** while another app was frontmost: `NSHostingView.acceptsFirstMouse` is `false` (a reviewer measured it with an off-screen probe) and the panel is ordered front without becoming key. The deleted tray had overridden this on its container; the rewrite dropped it | `FirstMouseHostingView` (hosting VIEW subclass, `acceptsFirstMouse = true`) as the panel's content view |
| The shaken-open tray could **no longer be moved** off the destination window | `WindowDragHandle` over the hub's title strip, pointer anchor only (never over the deck, so file drags out still start); `render()` keeps a moved pointer tray where the user put it |
| The page note said the held-file count "only shows on a notched screen" — false: hover still peeks the count there; only the **badge** is missing | Copy rewritten and re-keyed |
| `DropTrayStore.items.didSet` fired **once per file** (appends, `refreshMissing`) ⇒ 1 000 files = 1 000 surface renders | Mutate a copy, assign once; batch also de-dupes within itself |
| `filesDropped()` read the count **before** `NSItemProvider.loadObject` delivered the URLs | `add(providers:completion:)` collects all URLs, adds once, then calls back |
| The drag pasteboard (a pasteboard-server round trip) was read on **every drag event**, even with both drag triggers off | Skip entirely when neither trigger is on; `NotchDragSession` reads lazily, caches per press, throttles to one read / 50 ms while undecided (test: 120 events/s ⇒ ≤ 21 reads) |

Lesson worth keeping: **when a rewrite deletes a file, diff its overrides, not just its features.** The two
regressions (first mouse, movability) were single-method overrides on a container view in the deleted file —
invisible in any feature list, obvious in `git show <commit>^:<file> | grep override`.

## B2a (2026-10-10) — one archive engine, because ZIP of 2+ items never worked

Measured on macOS 27 before writing a line: **`ditto -c -k` refuses more than one source** ("Can't archive multiple
sources", exit 1). All three ZIP call sites — the Nén page default, Khay thả "Nén ZIP", Thao tác Finder ZIP — passed
N sources to ditto, so zipping two or more items failed everywhere. The page's `zip` fallback was worse: it ran from
the FIRST source's folder with bare names, so a file from another folder was skipped with a warning and **exit 0** —
the page said "Đã nén" over an archive missing data. And the "Hỏi" conflict policy recursed into itself forever.

`Core/Archive/ArchiveEngine.swift` (pure, 19 tests) plans names, conflicts and exact commands;
`Core/Archive/ArchiveRunner.swift` (Process + FileManager, 13 integration tests against the real tools in a temp folder)
runs them. All three call sites use it. Rules it enforces, each measured:

| Rule | Why |
|:--|:--|
| One source + ZIP + default level + no password ⇒ `ditto` (keeps Mac metadata); anything else ⇒ a staging folder of symlinks with unique names, archived by `zip -r` / `tar -czh` | ditto takes one source; zip/tar follow the links, so sources from different folders all land, and two `Report.pdf` become `Report.pdf` + `Report 2.pdf` |
| Every source must exist before archiving | zip and tar **both exit 0 and print nothing** for a missing (dangling) staged source — with or without `-q` |
| A new ZIP is read back (`unzip -Z1`, stdout to a file) and every top-level entry must be present | the tools' exit codes already lied once |
| stderr is read before `waitUntilExit`; stdout goes to `/dev/null` or a file | a 200 KB stderr test would deadlock the old unread-pipe code |
| ZIP password via the `ZIPOPT` environment variable, never argv | argv is readable by every user via `ps`; the environment only by the same user/root. Quoting measured with spaces, `"`, `'`, `\`, Vietnamese. (`zip -e` under `script(1)` does NOT work: `getpass()` flushes pending tty input) |
| Extraction lands in a staging folder on the destination volume, then each item is placed under the policy | `ditto -x` and `tar -x` overwrite same-named files silently; now only an explicit Gộp/Thay thế replaces, and "Thay thế" sends the old archive to the Trash |
| `tar -xf` for every non-ZIP archive | bsdtar detects gzip/bzip2/xz/plain on extraction — a survey agent claimed `-xzf` breaks on plain `.tar`; the probe proved it does not |

The ZipCrypto password is labelled honestly on the page (stops a casual look, not strong encryption).

**Tooling trap found the same day:** `scripts/build-and-check.sh` used to *install* — `pkill -9 XFinder`, replace
`/Applications/XFinder.app`, `codesign --deep`. Every build killed the user's running app, and the deep re-sign dropped
the Finder Sync extension's sandbox entitlement, so pkd refused it and the Finder menu vanished. It now only builds and
checks; `scripts/install-mouse-rebuild.sh` is the one install path. **After running any script, re-read what it does
before trusting its name.**

**Live Notch e2e, first run (B1b build, screen unlocked, user idle):** 2/11. The user's defaults hold
`dropTray.notchDropEnabled = 0` and `dropTray.hoverEnabled = 0` — set back when those keys were dead (the old page said
the notch settings were hidden "theo yêu cầu"). B1 wired them, so drag-into-notch and hover are off **by the user's own
stored choice**; nothing flips them silently. The shake path (enabled by default) also did not open in the harness —
cause not yet isolated (the harness's own drag session vs. global monitors during a system drag); needs a quiet window.

### B2a review (2026-10-10) — an archive can carry a link OUT of itself

Only one of four review lenses finished before the session limit (the other three — tool correctness, process/
concurrency, honesty/regressions — have NOT run yet). That one lens found a reproduced, high-severity defect:
an archive with a nested symlink to an absolute path (`Project/config/settings.json -> /Users/…/credentials.json`)
survives `ditto -x` verbatim; choosing **Gộp** then copies the link into the user's folder, **replacing the real file**,
and every later write to that "ordinary" file goes through to the outside target. The Ask dialog lists only top-level
names, so the user cannot see it coming. Fix: `extractToStaging` walks the staging tree and refuses the whole archive
if any link is absolute (`/`, `~`) or climbs above the archive root (`ArchiveEngine.escapingLinks`, pure + tested);
nothing is placed. End-to-end test reproduces the attack and is proven red without the guard (mutation A8).
Also: **language leak shape #7** (Vietnamese outside `\( )` in an interpolated string) and its gate
`scripts/audit-l10n-interpolations.py` — see commit b93c256. Diacritic-free words ("trang") remain invisible to it.

## B2c (2026-10-10) — image tools, measured before written

`Core/Image/ImageEngine.swift` (pure) + `ImageRunner.swift` (ImageIO, Core Image, Vision; no AppKit), wired into
Thao tác Finder as an "Ảnh" section that appears when the Finder selection holds images (convert, make smaller,
remove background). Results go next to the original under keep-both names; the original is never touched.

| Measured on macOS 27 | Result |
|:--|:--|
| Encoders (`CGImageDestinationCopyTypeIdentifiers`) | JPEG, PNG, HEIC, AVIF, TIFF, GIF… — **no WebP** (`CreateWithURL` returns nil). The plan's "WebP nếu encoder có": there is none, so the target list is derived from the encoder list and WebP is never offered |
| HEIC (orientation 6, sRGB) → JPEG/PNG via `AddImageFromSource` | orientation and profile survive |
| `CGImageSourceCreateThumbnailAtIndex` + transform | 0.004 s; 800×600 orientation 6 → 300×400 upright; orientation reset to 1 |
| `VNGenerateForegroundInstanceMaskRequest` | headless, no permission; ~2.2 s first call (model load), corner alpha 0, subject alpha 255. The first suite run after adding it took 40 s once (Core ML warm-up); later runs: slowest test 0.31 s |

9 tests (5 pure, 4 integration on generated images). Page clicks not exercised live (user active at the keyboard).

**Found in passing, NOT fixed (separate job):** the 13 "Cấu hình menu" switches on Thao tác Finder
(`finderActions.show.*`) promise to choose what appears in Finder's context menu, but the Finder Sync extension's menu
has two hard-coded, untranslated items and reads none of them; on the page they only dim the page's own buttons.
A control that cannot do what its label says (Part 0 §6) — and an unlocalized extension menu.

## B2d (2026-10-10) — the Notch hub acts on what it holds

`Core/Notch/NotchTask.swift` (pure, 8 tests): `NotchActions.available(for:encodable:)` decides the row — ZIP always,
"Gộp PDF" only with ≥ 2 PDFs, "Sang JPEG/PNG" only if an encoder exists AND some held image would change,
"Tách nền" for images, AirDrop. `NotchTask` counts progress in **files done** — `zip`/`tar`/PDFKit report no byte
progress, so a smooth percentage would be invented; a one-step job shows 0 → done. Cancel is final: a step that lands
after it is ignored (exhaustive walk + mutation M10). The machine gained `taskStarted`/`taskEnded`: a running job keeps
the hub open when the pointer leaves (its progress must not vanish), the close button still closes (M11).
Outputs: ZIP beside the first item as `XFinder.zip` (keep-both), PDF merge beside the first PDF, images beside each
source; "Hiện trong Finder" reveals them; history logs them. The hub grew to 222 pt below the notch for the row.

**Not verified live:** every click in the row, and AirDrop in particular — whether `NSSharingService(.sendViaAirDrop)`
opens its picker from a non-activating status-bar panel needs a human at the screen. The code checks `canPerform`
and says so in the hub when it cannot.

## B3 (2026-10-10) — snap at the notch, and the snap geometry finally tested for real

`Core/Snap/SnapLayout.swift` (pure, 11 tests) now owns every snap rectangle, the Stage Manager inset, the edge-zone
decision and the notch layout row; `WindowManager.SnapTarget` is a typealias to it. The old snap tests checked a
**hand-copied** rect function (9 tests, deleted) — the FeatureContract exemption for snapZones is paid (cap 6 → 5).

* New targets: left/centre/right third (rounded so the three always cover the width to the pixel — tested at 1001 pt),
  left/right two-thirds, **Tập trung** (centred, 60 % width, full height). ⌃⌥D/F/G snap to the thirds.
* Dragging a window into the zone around the notch (notch ± 80 pt, 40 pt deep; a stand-in notch on screens without one)
  shows a row of 7 layout tiles under the notch instead of maximising; moving down onto a tile highlights it and shows
  the usual preview, releasing snaps. The rest of the top edge still maximises. The row panel is **mouse-transparent**
  (`SurfacePanel(.passive)`), so the drag continues underneath and the highlight follows the computed pointer position.
  Switch: `snapzones.notchRow` (default on, in FeatureKeyDefaultsTests).
* One real bug the tests caught while writing it: a row wider than the screen was clamped to a negative x.

Not verified live: the drag → row → release flow (needs a human dragging a real window); `screencapture` still fails here.

## B4 (2026-10-10) — live activities at the notch (event-driven, no polling)

`Core/Notch/LiveActivity.swift` (pure, 9 tests): transitions → notices, and a queue where **same-kind notices replace
each other** (a network flapping in a second shows only the final state; nothing stacks). `LiveActivityMonitor` arms each
source only while its switch is on: IOPS power notification, `NWPathMonitor`, a `flagsChanged` global+local pair for
Caps Lock, IOBluetooth connect + per-device disconnect notifications. The first reading of every source is a baseline,
so launching announces nothing. The machine gained `.activity`: it only replaces `collapsed`, never interrupts a peek or
the hub, ends on its own timer (not on the pointer), and yields to hover/drag (exhaustive walk now 22 621 paths).
AlertMonitor's alerts go to the notch when the surface and the switch are on; the banner stays the fallback, so turning
the notch off never silences an alert. Six switches on the Khay thả page, all in FeatureKeyDefaultsTests.

Measured before writing: on AC at 80 % this Mac reports `IsCharging = false, IsCharged = false` — optimised charging is
**holding** the level. So "plugged in" says "đang giữ mức pin" when not charging, and "full" fires only when the OS says
charged; nothing waits for a 100 % that will not come. A CLI probe touching IOBluetooth is killed by TCC (exit 134: no
`NSBluetoothAlwaysUsageDescription`); Bluetooth can only be measured from inside XFinder. Swift 6 refused to send the
IOBluetooth device object to the main actor — registrations are made in the callback, kept behind
`OSAllocatedUnfairLock(uncheckedState:)`, and only the device NAME crosses.

**Deferred to B4b, not built:** the volume/brightness HUD and the timer. **Not verified live:** every source (needs a
human to unplug the charger, drop Wi-Fi, press Caps Lock, connect AirPods).

**The first real Bluetooth connect crashed the app (2026-10-11, report `XFinder-2026-10-11-061620`).** The comment above
the IOBluetooth callback said "calls back on the run loop the registration was made on (main)". Measured: a real connect
arrived on `com.apple.bluetooth.iobluetooth.coordinatorQueue` (CoreBluetooth's XPC path), the `@objc` shim called
`MainActor.assumeIsolated`, libdispatch asserted "Block was expected to execute on queue com.apple.main-thread", SIGTRAP.
It never fired in the B4 pass because no device connected during it, and the switch is on by default — so every user with
a Bluetooth mouse would have hit it on their first reconnect. Fix: both IOBluetooth callbacks hop through `runOnMainActor`.
**Rule: a callback's thread is a measurement, not a comment.** Every `assumeIsolated` in a callback not posted by our own
`DispatchQueue.main`/`Timer` code needs either a documented main-thread contract (CGEvent taps on the main run loop, local
NSEvent monitors) or `runOnMainActor`. Audited the same day: the only other off-main caller was already using it.

**And the fix shipped late because `install-mouse-rebuild.sh` does NOT build.** Despite its name it stages whatever
`build-and-check.sh` last left in `/tmp/xfinder-clean-build/out`, signs it and installs it. Two "reinstalls" of the fix put the
00:28 binary back (the `ditto` keeps the build's mtime, which is how it was caught: installed dylib 00:28, source edit 06:18),
and the user watched the app crash on every launch meanwhile — IOBluetooth reports already-connected devices right after
registration, so with a Bluetooth mouse the old build died within seconds of starting. **Always `build-and-check.sh` first,
then install, and compare the installed binary's mtime with the source edit before claiming a fix is on the machine.**
(This file already says "re-read what a script does before trusting its name." It was true twice.)

### Two measurement traps found while closing B4 (2026-10-10)

* **`ls` in this shell is an alias for another tool**, and `ls -t <dir> | grep …` prints NOTHING (the tool rejects `-t`
  and the error goes to stderr). Every "no crash report" check earlier this session used it and read the empty result
  as "no crash". With `/bin/ls` there is a crash report from 17:04 today. Use `/bin/ls` (and `/usr/bin/log`, also aliased).
* **Launching `XFinder.app/Contents/MacOS/XFinder` straight from a shell now crashes it** —
  `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` on a TCC reply thread. TCC attributes the request to the RESPONSIBLE process
  (the shell / claude-code), whose Info.plist has no usage description for the service, and kills the app. A normal
  LaunchServices launch (`open`, Dock, login item) attributes it to XFinder and is unaffected. The old Part 3c advice
  "run the binary directly to read stderr" is therefore unsafe now; read `/usr/bin/log show --predicate 'process == "XFinder"'`
  instead. The two 2026-10-09 crash reports predate this session and were not examined.

## B4b (2026-10-10) — volume HUD and a notch timer; no brightness HUD, on purpose

* **Volume HUD** alongside macOS's own: `VolumeObserver` gained a plain `onChange` callback (Observation has no publishers);
  `LiveActivityMonitor` retains the observer only while `notch.activity.volume` is on. The level is CoreAudio's real
  value with a bar; CoreAudio reports each change on two elements, so `LiveActivity.volumeItem` ignores repeats.
* **No brightness HUD.** The readable brightness value is stuck on Apple Silicon / macOS 27 (measured earlier in this
  file); a brightness bar would have to invent its number. The settings row says so.
* **Timer:** "Hẹn giờ trên notch" in the flyout (5–60 min, cancel). The collapsed notch badge shows the time left even
  with no files held (real notch only); the end plays "Glass" and shows "Hết giờ". A 1 s ticker exists only while a
  countdown runs. `Countdown.label` rounds UP so it never reads 0:00 early. Preset labels are clock-style ("25:00")
  because the store's " phút" means " min left" — one key, one meaning.

## B5 (2026-10-10) — clipboard on the notch, and the Paste Stack finally has a consumer

**Job sentences, so the two surfaces do not overlap.** ⌘⇧V shelf: *"I need one clip from deep history — search, boards,
keyboard, paste into the window I was in."* Notch page: *"I am already at the notch — glance at my last clips, grab one,
stack a few."* The notch page is a **tab inside the open hub** (and a flyout row); it is never a new way to open the
hub. One deliberate opt-in exception: `notch.clipboardOnHover` (default **off**) lets resting on the notch with an empty
tray open the clipboard page — clips are never "empty", so this does not repeat the Part 3c empty-tray trap.

* `Core/Clipboard/ClipboardFilterToken` (pure): `@image @link @code…` (+ Vietnamese aliases) → type, `@anything-else` →
  source app substring, the rest free text. Parsed in FRONT of `ClipboardManager.filteredHistory()`, which is untouched,
  and the notch's query never changes what the shelf shows.
* `Core/Clipboard/ClipboardTransform` (pure, 17 transforms in 5 groups): a transform that changes nothing says so, JSON
  pretty **sorts keys** and the label says so, Base64 decode pads unpadded/URL-safe input, URL-encode uses the RFC 3986
  unreserved set (`.urlQueryAllowed` leaves `&=?` alone — measured), `.newlines` splits CRLF in two (measured) so lines fold
  `\r\n` first, `cleanURL` delegates to `URLCleaner`. MD5 is labelled a checksum, never security.
* `Core/Clipboard/PasteQueue` (pure, generic): the Paste Stack's queue. **Measured before B5: `popNext()` had zero call
  sites** — ⌘⇧C could start a stack and the HUD showed it, but nothing ever consumed it. The consumer is
  `ClipboardManager.pasteNextFromStack()`, driven by the shelf's event tap: on ⌘V with a stack active it rewrites the
  pasteboard with the next item and lets the user's ORIGINAL ⌘V through — nothing is synthesized, so nothing re-enters.
  The decision is synchronous (`MainActor.assumeIsolated` in the tap callback, which runs on the main run loop, same as
  QuitProtection). Without the tap (hotkey off / no Accessibility) the notch offers "Dán tiếp" and says which mode applies.
* "Đi tới nguồn": one row per thing actually known — open the source app (bundle id), open the source page (the copied
  link, or Chromium's `org.chromium.source-url` captured at copy time — **Safari's equivalent is unverified**), reveal a
  copied file. Nothing claims to jump to the exact document.
* **"Dịch" is not shipped.** Measured: two read-only CLI probes of `LanguageAvailability.status(from:to:)` hung and
  `translationd` logged `trusted: NO` for the ad-hoc binary — the same trust gate as MenuBarAgent XPC. Untested from the
  signed app; until then no Translate row exists (a disabled row hinting at a feature is still a promise).
* The real `Models/ClipboardRecord.swift` is now symlinked into the test package (the `L10n` stub there makes it compile);
  `ClipboardRecord` is `Equatable`.
* Keyboard on the notch: the clipboard page makes the panel key with `makeKeyAndOrderFront(nil)` — never `NSApp.activate`
  — and a LOCAL monitor handles Esc/←/→/Return while our panel is key. The stale `SurfacePanel` doc comment that said only
  `.interactive` can become key is fixed.

**Data bug found on the way (fixed in the follow-up commit, measured on this Mac's `xfinder.db`):** text records stored
`textSnippet = prefix(200)` and a payload file only above 4 096 characters; `writeToPasteboard` pasted `textSnippet` and
never read the payload. **227 records** in the user's history are 201–4 096 characters with only 200 stored — every paste
of a clip longer than 200 characters from the shelf was truncated, silently. The lost text of those 227 cannot be recovered.
The fix is `Core/Clipboard/ClipboardText` (pure, symlinked, 3 tests): the snippet is a **preview** (`previewLength = 200`),
`needsPayload` is `> 200`, and `fullText(snippet:payloadPath:)` prefers the payload and degrades to the snippet — never to
nothing. Capture, `ClipboardPayloadStore.storeText`, the paste engine's text branch and the notch's `applyTransform` all go
through it; the `textSnippet ??` readers left alone are preview/scoring only (link fallback, image candidate, intelligence
score, `displayPreview`). Mutations **C7** (payload only above 4 096 again) and **C8** (paste reads the preview) re-inject the
two halves of the bug. The 4 096 threshold was never a design decision anyone could cite — it was an arbitrary constant in
two places that disagreed with the 200 in a third, which is the Part 0 §5 shape at the data layer.

**Mutation C4 (drop the Base64 padding) stayed GREEN on the first full run — a finding, and the cause is worth keeping.**
The test's three "unpadded" inputs were 12, 20 and 4 characters long: all multiples of 4, so `pad == 0` for every one and
the padding line was never exercised. Measured first (`Data(base64Encoded:)` on macOS 27 returns **nil** for `aGVsbG8`,
`aGk`, `-_8`, with or without `.ignoreUnknownCharacters`), so the code is live and the *test* was the liar. Fixed with
inputs that need 1, 2 and 1 `=` (`aGVsbG8` → hello, `YQ` → a, a 27-character JWT payload). **Rule: an example chosen to
illustrate a property must be checked to actually have that property** — "a JWT header has no padding" was true of JWTs
and false of the sample.

**Verifying an intermediate commit:** B5 and the fix share four files, so B5 was committed from an index built with
`hash-object` + `update-index` (working tree untouched), then the B5 commit alone was built and tested in a throw-away
`git worktree` (BUILD SUCCEEDED, 587/0) so `git bisect` never lands on a tree that does not compile. **Order matters when
tearing the worktree down:** `lsregister -u <path>` needs the bundle to still exist — `rm -rf` first left three dead
LaunchServices records claiming `com.xfinder.app.XFinderSync` (the trap Part 3c already documents), and `-gc` does not
drop them; recreating the empty paths long enough to unregister did. Unregister, then delete.

**Two traps from closing this item.** (1) Adding `ClipboardTextTests.swift` *before* its subject's symlink made both
mutation scripts print `baseline failures: NORESULT` → `FAIL: baseline is not green`. The gate was right; the cause was a test
file whose subject was not in the package. A new test and its symlink go in the **same** step, and `NORESULT` means "did not
compile", not "0 failures". (2) A background `cd Tests && swift test` died with exit 127 — the `cd` hook again. Use
`swift test --package-path /abs/path/Tests`.

Not verified live: any click on the notch clipboard page, ⌘V interception with a real keyboard, Chromium source-URL capture
in the installed app (it was measured on the raw pasteboard, not through the app).

**Truncation fix measured end-to-end on the installed app (2026-10-11, user away):** 1 000 Vietnamese characters copied →
the newest record has a 200-character snippet AND a payload file identical to the text (NFC). The first run looked like a
corrupted payload (2 072 bytes, `ch√†o`): **`pbcopy` decodes its input per the shell's locale, and this shell has `LANG`
unset, so UTF-8 became MacRoman mojibake on the pasteboard before the app ever saw it.** `LANG=en_US.UTF-8 pbcopy` fixed the
harness; compare pasteboard round-trips under NFC. Two test rows (one of them the mojibake) remain in the user's clipboard
history — said, not hidden.

## B6 (2026-10-11) — Now Playing on the notch: measured first, then built

Job: *"I am at the notch — what is playing, skip it, pause it, without hunting for the player."* Badge (artwork + title)
while collapsed, hover peek (title/artist + ⏮⏯⏭) when no files are held, a **Đang phát** page in the hub (interpolated
progress, controls, "Mở <app>"), a flyout row. Switch `notch.nowPlaying`, default **off**: it rides a private framework and
runs a helper process, so the user opts in and the page says what that costs.

### The measurement that decided the design (macOS 27.0 / 26A428, 2026-10-10)

The plan said "MediaRemote loads but returns empty — cannot tell 'nothing playing' from 'denied'". A **silent publisher**
settled it: a CLI that sets `MPNowPlayingInfoCenter` + registers `MPRemoteCommandCenter` handlers (no audio) is a real
Now Playing client, and gives every probe a known answer.

| Probe (with the publisher active) | Result |
|:--|:--|
| `MRMediaRemoteGetNowPlayingInfo` from an ad-hoc CLI | callbacks fire with **nil / false / pid 0** — denied; mediaremoted logs `entitlements=0` |
| same call from a dylib loaded into `/usr/bin/perl` (`DynaLoader::dl_load_file`) | **8 keys** (Title, Artist, Album, Duration, ElapsedTime, PlaybackRate, Timestamp, ContentItemIdentifier), isPlaying 1, the pid — `entitlements=264241664`, bundle id `com.apple.perl` |
| `MRMediaRemoteSendCommand` (toggle 2 / next 4 / previous 5) from the **ad-hoc** process | returned true and the publisher's handlers fired — **sending needs no helper** |
| `MRMediaRemoteRegisterForNowPlayingNotifications` in the perl host | **one notification per change** (title ×4, pause, resume), no polling; helper cost **0.04 s CPU over 13 s, 17.6 MB RSS** |
| artwork | the first dict has `ArtworkIdentifier`/`MIMEType`/`Width`/`Height` but **no bytes**; a second notification ~0 s later carries `ArtworkData` (865 B, `image/jpeg`) — emit artwork on identifier change |
| a publisher that registers **no** remote command | invisible to mediaremoted (`--nocommands` ⇒ 0 keys) — a fact about test fixtures |

Research (web, 7 agents, no GPL source opened): since macOS 15.4 mediaremoted requires
`com.apple.mediaremote.now-playing-read-access`; Apple-signed platform binaries pass; the community technique
(ungive/mediaremote-adapter, BSD-3) is a perl-hosted adapter streaming JSON — **re-implemented here from the measurement,
their source was not read**. Distributed notifications (`com.apple.Music.playerInfo`, Spotify) cover two apps and no browser;
AppleScript needs Automation per app and launches the app — neither is used. No public read API exists through macOS 27
(`MPNowPlayingInfoCenter`/the WWDC26 NowPlaying framework are publish-only). Another app using the same technique spun at 100 %
CPU when its stream died because the readability handler was never cleared on EOF — ours clears it on empty data.

### Shape

* `Helpers/NowPlaying/nowplaying-adapter.c` → **Run Script phase** `7F1A0233` compiles it to `Contents/Helpers/XFinderNowPlaying.dylib`
  (a hand-authored `PBXShellScriptBuildPhase`; `build-and-check.sh` asserts the dylib, `install-mouse-rebuild.sh` signs it as
  nested code and is FATAL without it). The constructor registers and returns — blocking inside `dlopen` deadlocks dyld — and a
  stdin-EOF thread exits the host, so a dead XFinder never leaves an orphan perl.
* `Core/Notch/NowPlaying.swift` (pure, 10 tests): line parser, `position(of:at:)` (zero rate while paused — a paused publisher
  still claimed rate 1.0), `timeLabel`, `Supervisor` (0.5→8 s backoff, give up after 5, an uptime ≥ 60 s resets), `Availability`
  keys. `NowPlayingMonitor`: the ONE reader of `notch.nowPlaying`, Process + pipes, handlers carry a **generation**, not the
  non-Sendable Process; 5 s hello timeout; commands via in-process `MRMediaRemoteSendCommand`.
* Machine: `Settings.nowPlayingActive` (a fact, not an event — the 41 371-path walk is untouched), `Page.nowPlaying`; hover
  peeks files OR the track, never an empty tray; the peek survives the tray emptying while a track plays. Layout: badge/hover
  lip/peek width follow the track. 6 new machine+layout tests; mutations M20–M23 (+ M2/M6/M17 re-anchored): **23/23 RED**.

### Probe bugs worth remembering

* **Use-after-free across nested blocks reads like a denial.** Keeping the `CFDictionaryRef` from `GetNowPlayingInfo` and
  touching it inside the nested `IsPlaying`/`PID` callbacks died with a PAC exception → `Killed: 9` in the perl host. Read
  everything in the first block (or `CFRetain`).
* **A Python lock check without PyObjC fails OPEN.** `python3 -c "import Quartz…" || echo 0` reported "unlocked" on a locked
  screen, so the AX e2e ran against empty trees and two concurrent AX walkers drove XFinder to 90 % CPU. The check now parses
  `ioreg -n Root -d1 -a` and prints 1 on any failure. Run AX probes one at a time, never while locked.
* `timeout(1)` does not exist on macOS; `perl -e 'alarm N; exec @ARGV'` does.

### Results, separately

| Statement | Result |
|:--|:--|
| Build | `BUILD SUCCEEDED`; `PhaseScriptExecution Build Now Playing helper` in the log; dylib in the bundle, arm64, ad-hoc in the Xcode build, `XFinder Dev` after install |
| Tests | **606 / 0** (+16) |
| Gates | coverage `TOTAL 0` / 1 918 · duplicates 0 · literals 0 · interpolations 0 · UI tokens 0 · runtime on the installed bundle **0 leaks** |
| Mutations (sequential) | notch **23/23 RED** |
| Mechanism | measured with the silent publisher (table above) |
| **Through the installed app** | ✅ **13/13** (2026-10-11, user at the keyboard; `b6/mine/e2e-nowplaying.sh` + `np-ax` AX driver + `clickbadge`): switch on via the page ⇒ status "Ready" ⇒ a perl child; publisher ⇒ status line "Playing: XF-PROBE-TITLE" and the **collapsed badge** (185×50 window) shows the title; **clicking the badge lip** opens the hub on Đang phát with artist + "5:00"; Next track / Play-pause reach the publisher (`CMD next`, `CMD toggle`); Close dismisses; publisher gone ⇒ badge and status drop the title; switch off ⇒ perl exits. Helper: **0.01 s CPU, 17.6 MB** after ~15 s. Launch with the key already on: 3/3 relaunches `applySettings → helper launched → hello` |
| **A real player** (Music, Safari/YouTube, Spotify) | ❌ unmeasured — only the `MPNowPlayingInfoCenter` publisher, which takes the same path through mediaremoted |

**Harness lessons from getting to 13/13 (each one produced a false FAIL first):** (1) a Python lock check without PyObjC
fails OPEN — parse `ioreg` instead; (2) SwiftUI flattens a settings page into one list of siblings, so a ToggleRow's
checkbox is "the first AXCheckBox AFTER the title text", not a descendant; (3) **never flip a switch blind** — the user had
turned Now Playing on themselves between two runs, and a blind press turned it OFF and failed every later step; press only
toward the wanted state and restore the state found at start; (4) `defaults write … -bool 1` is a syntax error — map to
`true`/`false`; (5) `AXExtrasMenuBar` is unsupported on this app right now because the user's menu-bar hider
(`menubar.hiderEnabled`) hides XFinder's own status item — reach the hub by clicking the badge (`CGWindowList` finds the short
top-edge window) instead of the flyout; (6) `log show` does not persist `.info` messages and `log stream` needs several
seconds to attach — a stream started 1 s before launch missed the launch lines and read like "applySettings never ran".
One observation stayed unexplained: a single relaunch of the 06:21 build showed the status "Off" with no helper; the same
procedure on the next build started the helper 3/3 times.

Also fixed in passing: `ClipboardKlippyTests.testDateFilterToday` failed between 00:00 and 02:00 every night ("two hours
ago" crossed midnight); it now anchors at noon.

## B7 (2026-10-11) — the notch's own settings: hover speed, a pill for plain screens, invisible to capture

Page renamed **Notch & Khay thả** (sidebar + header); the per-activity switches were already B4's. New section
"Hành vi notch" with three keys, each read in `NotchSurfaceController` (FeatureKeyDefaultsTests for the two Bools):

| Key | Default | What it does | Measured |
|:--|:--|:--|:--|
| `notch.hideFromCapture` | **true** | `panel.sharingType = .none` on the notch surface, set in `prepare()` and live in `applySettings()` | probe: a panel's `kCGWindowSharingState` goes 1 → 0 → 1 with the property (public signal, no permission). Installed app, e2e 5/5: the 185×50 badge window reports `sharing=0` by default, `1` after the switch is turned off on the page, `0` again after turning it on |
| `notch.pillOnPlainScreens` | **true** | on a screen with no notch the collapsed state is a 170×22 pill hanging under the menu bar; peek/hub there hang under the menu bar too (`frame(for:)` uses `visible.maxY` when `notch.height == 0`); the hover zone becomes the pill while it is shown, else the bare 8 pt strip in the menu bar | **geometry only** — this Mac has one screen, notched. The settings copy says so. `SnapZoneController`'s stand-in notch (B3) still sits at the screen top: window drags go to the top edge |
| `notch.hoverSpeed` | `"medium"` | `Settings.hoverDwell(forSpeed:)` → 0.12 / 0.25 / 0.5 s; unknown ⇒ 0.25 (never 0) | pure, 2 tests |

Rules kept: the stand-in notch's *x* is unchanged so the drag zone and the menu-bar hover strip stay where B1 measured
them; only drawn frames move under the menu bar on plain screens. The old B1 line "notch-less screens get peek/hub only
(pill = B7)" is paid; the layout tests that pinned it were rewritten, not deleted.

Gates: 611 tests / 0 · mutations M24–M26 (pill ignores its switch · "slow" reads as medium · plain-screen hover ignores the
pill) + M17 re-anchored · L10n coverage 1 929 entries `TOTAL 0` · runtime in the installed bundle 0 leaks.
Not verified: the pill on a real external display (none attached); the hover-speed feel with a hand (the user's hover
switch is off in their defaults, by their choice).

### Review of B6 + the Bluetooth fix + B7 (2026-10-11): 5 lenses, 2 refuters each — 5 confirmed, 3 split, 0 refuted

| Finding | Verdict | What changed |
|:--|:--|:--|
| **A dead or restarting helper left the last track on screen as live** — `helperEnded`'s `.restart` branch kept `snapshot`/`artwork`; the badge stayed at "playing" opacity, the progress bar slid on from the frozen timestamp, the page read "Đang khởi động trợ giúp… · Đang phát: <old>" | confirmed, high (a refuter reproduced the state transition in a probe) | `Availability.isLive` (`.ready` only); `hasTrack`/`liveSnapshot`/`liveArtwork` gate on it at the ONE source the controller, view and page read; the restart branch clears the snapshot before announcing `.starting`. **Rule: a status and the data it vouches for must be read through one gate**, or the data outlives the status |
| `WindowDragHandle` (an NSView overlay) covered the whole hub title strip, which since B5 holds the page tabs — at the pointer anchor a tab click became a window drag | confirmed, medium | the overlay sits on the `Spacer()` only. **An `NSViewRepresentable` wins AppKit hit-testing over every SwiftUI control under it, whatever the z-order** — the B1b note "only the strip, never the deck" was right for the wrong reason: the strip is now controls too |
| No cap on the helper's line buffer; a publisher can hand out a 50 MB bitmap | confirmed, low | adapter emits artwork only ≤ 4 MB; `consume` drops a > 16 MB line with no newline |
| Embedded NUL in a title truncates the JSON field (C strings) | confirmed, low | **accepted** — cosmetic; recorded here instead of fixed |
| `notch.hoverSpeed` (a String key) had no default-agreement gate | confirmed, low | `FeatureKeyDefaultsTests` now also matches `@AppStorage … = "lit"` ↔ `string(forKey:) ?? "lit"`; `notch.hoverSpeed` and the older `dropTray.shakeSensitivity` registered |
| Now Playing had no `FeatureCatalog` row — "Tắt tất cả" in the hub left the perl helper running | split (one refuter: "reachable under dropTray, by design") | added `.nowPlaying` with its own `IdleCost.helperProcess` badge ("Một tiến trình phụ") — the hub cannot claim everything is off while a child process runs |
| Badge content (count + timer + title) could exceed the notch width | split | title gets `layoutPriority(-1)`: digits keep their width, the title truncates |
| `stop()`'s late-terminate closure captured `self` strongly | split (singleton; harmless today) | `[weak self]`, matching the file |

Lenses that found nothing wrong where they looked: JSON escaping of control characters, `NSImage(data:)` on garbage, no
argv injection from a track title (the perl one-liner is a fixed literal), the dylib lives inside the signed bundle,
pid guards, the mandatory monitor pairs, the generation-token guards, `_exit` on stdin EOF, L10n scopes of every new string.

## Phase C — C1 (2026-10-11): the ⌘-Tab switcher acts on what it shows

`WindowPreviewStore` gained the switcher's rules as **pure static functions** so they are testable without AX
(`SwitcherPhaseCTests`, 9 tests; `scripts/mutation-check-switcher.sh` S1–S5 all RED): `isExcluded(bundleID:excluded:)`
(an empty bundle id is never excluded), `cgRect(forAppKitFrame:primaryHeight:)` + `isOnScreen(_:screenCG:)` (a window
straddling two displays belongs to both — `intersects`, not `contains`), `windowItems(for:wins:appName:)`,
`removing(windowID:from:)` (a closed representative is replaced by the group's next window; a singleton disappears),
`clampedSelection(_:count:)`. `Mode` = `.apps` / `.windows(bundleID:)`; `toggleMode()` returns to the app you came
from (S3 stayed GREEN until the test used the SECOND app — selecting index 0 cannot distinguish "back where we were"
from "back to the first card"; a mutation that stays green is a finding, and this one was the test's fault).

Keys in the tap while the switcher is open and search is not active: **Q** closes the selected window
(`WindowManager.closeWindow` presses `kAXCloseButtonAttribute`; the deck reloads after 0.5 s so an app that refuses
to close keeps its card), **H** hides the app, **Space** zooms the thumbnail, **`** flips app ↔ that app's windows,
**,** searches. `windowPreview.currentScreenOnly` (default off, one reader) filters to the display under the pointer;
`windowPreview.excludedApps` has ONE reader (`WindowPreviewStore.excludedApps`) — the page used to keep its own copy.

**Four results, separately:** build ✅ (arm64) · tests ✅ 621/0 · mutations ✅ 5/5 · **live keys ❌ not measured** —
this Mac has `windowPreview.commandTabEnabled = 0`, and a probe would have to post ⌘-Tab into the user's session.
Plan §5 asks for "cửa sổ đóng/ẩn thật (đo bằng CGWindowList)" — still owed.

## D0 (2026-10-11) — the ⌘⇧V shelf lives in the notch

Design went through the evon ui-ux skill: a 13-row review of the notch + settings pages (measured: search
placeholder 1.1:1, first card clipped, light card on the black surface), then wireframes A/B/C served from the
scratchpad (`uiux/wf/wireframe.html`, probe of 18 variant×state combinations, 13-agent adversarial review — 10
confirmed, 0 refuted, mostly "the current notch page lacks X", which became the build list). The user chose B.

* **One key, one picker: `clipboard.hotkeySurface`** (`"notch"` default / `"shelf"`), ONE reader
  `ClipboardShelfController.hotkeySurface`, router `hotkeyPressed()` used by the tap, the in-app ⌘⇧V, the settings
  button and `xfinder://clipboard`. **The shelf controller stays the ENGINE** — its CGEvent tap is the only thing that
  intercepts ⌘V for the Paste Stack (`pasteNextFromStack()` has that single call site) — only the panel moved behind
  the picker. With `dropTray.notchEnabled` off the hotkey falls back to the shelf (`NotchClipboardRules.surfaceToOpen`).
* `Core/Clipboard/NotchClipboardRules.swift` (pure, symlinked, 11 tests, `mutation-check-notch-clipboard.sh` 8/8 RED):
  surface routing, ⌘1–9 → history/pinned/saved/boards, reading-order grid keys (no wrap; ↑/↓ stay at the edge),
  type counts over the LOADED history (never the DB's), footer precedence (stack › notice › no-Accessibility › hints),
  age buckets, the one footer fact per type. The hub's height follows the page: `NotchSurfaceLayout.size` reads the
  page from `.expanded(page)` (clipboard drop 334 ⇒ 440×366 measured via CGWindowList; other pages unchanged).
* Page per wireframe B (`NotchClipboardView` + dark `NotchClipCardView`): own placeholder at white 50 % (5.3:1), chip
  row icon+count (a type with 0 records gets no chip), board menu with counts and ⌘-digits, 3×2 `LazyVGrid`, Touch ID
  lock re-armed on every opening (`ClipboardShelfController.touchIDLockEnabled`, one Core reader), footer rules above,
  context menu with every shelf action (Quick Look, pin, Paste Stack, snippet, transforms, "Đi tới nguồn", OCR copy,
  skip app, delete). Keys: Esc clears the search first · ←→↑↓ · ↩ / ⇧↩ · Space (unless typing) · ⌘P · ⌘⌫ · ⌘F · ⌘1–9.
  The panel is `appearance = .darkAqua` so system controls stop assuming a light surface.
* Deliberately dropped from the shelf: multi-select + merge/split (the Paste Stack covers sequential paste), the
  sort/date menus (search + `@app` instead), the create-board overlay (the board menu opens Cài đặt Clipboard).
* **Found by measuring the new page, not by reading: the clipboard history loaded EMPTY at launch.** The AX tree said
  "All, 1" with 1 826 rows on disk. `DatabaseService.init` does not open sqlite — `initialize()` does, from its own
  Task in `setupDatabase()`, while `_ = ClipboardManager.shared` (earlier in `applicationDidFinishLaunching`) had
  already queued `fetchClipboardRecords`; the fetch reached the actor first, got `db == nil`, returned `[]`, and nothing
  retried — every later copy was written fine, so the DB looked healthy. Fix: every query goes through
  `openIfNeeded()`. Measured 3/3 relaunches: "All, 1 000". **A lazy singleton whose reads and writes can race its own
  initializer must open on first use; "writes work" proves nothing about the first read.**
* Measurement notes: the notch panel is invisible to `screencapture` by design (`notch.hideFromCapture`), and writing
  the key then activating the app did NOT change `kCGWindowSharingState` — `applySettings()` is not re-run on
  activation for this controller; the AX tree (`probe-ax-dump.swift`) is the way to read the page. `xfinder://clipboard`
  opens/closes it without posting keys. Review agents left `run_*.html` in the repo root again and one had built the app
  to `/private/tmp/xfinder-review-out` (stale `pluginkit` registration, unregistered).
* **Not verified by hand:** a real ⌘⇧V keypress through the tap → router → notch; paste-back into the previous app from
  the notch; Touch ID prompt; ⌘V interception (engine untouched); the Settings picker click. The user tests these.

### D0b (2026-10-11, same day) — the user's reference beat wireframe B: a WIDE hub and a horizontal deck

Installed B, the user said "nó trượt dọc, tôi cần trượt ngang và Notch rộng hơn" and sent an OneNotch screenshot + 11
videos. Frames were pulled from the videos with AVFoundation (`AVAssetImageGenerator`, scratchpad `ref/frames-bin`) into
a contact sheet — that is how a video becomes evidence here; `ffmpeg` is not installed. What the reference does and what
was copied (S13: positions kept, roles mapped):

| OneNotch | XFinder |
|:--|:--|
| top band EITHER SIDE of the notch: page dots + search left, 4 icons right | tabs on the left wing, search + ✕ on the right wing (we have three pages, they have dots) |
| chip row = Pins · type chips with counts · boards · "+" | Tất cả · Đã ghim · Đã lưu (if any) · Gợi ý (if on) · type chips · boards · "+", sort menu at the right end |
| one horizontal row of four ~198×139 cards, footer app · time · size | four 174×122 `NotchClipCardView`s (ratio kept), footer app · age · pin · one fact (no size field exists) |
| `@image` typed in search filters live | already so (`ClipboardFilterToken`) |

* **The hub's SIZE is per page**: `NotchSurfaceLayout.Metrics.expandedWidth(for:)` / `expandedDrop(for:)` — clipboard
  752 × (32 + 200), everything else 440 × (32 + 222). `size(for:)` reads the page from `.expanded(page)`, so the view
  and the window frame cannot disagree. Measured on the installed app via CGWindowList: **752×232 at x 488**, i.e.
  centred on the 1728-pt screen. `SurfaceGeometry.expandedNotchFrame` already clamps to the screen width.
* **Using the notch band**: `NotchSurfaceView.clipboardShell` draws a 32-pt band with symmetric wings
  `(width − notchGap) / 2 − inset` and a clear spacer of the notch's width between them, so nothing sits under the
  camera; at the pointer anchor or on a plain screen the gap is 0. The root's `padding(.top, notch.height)` is skipped
  for this hub only. `pageTabs(current:)` is shared with the ordinary shell.
* **Chips are exclusive** (`choose(scope:)` / `choose(type:)`), like the reference — a type chip returns the scope to
  history, a scope chip clears the type and strips `@type` tokens from the query. Counts are over the LOADED history
  (`clipboard.maxHistory`), never the DB's. Icon-only chips carry `accessibilityLabel(titleVI)`.
* **The deck is one row**: `move()` passes `columns = items.count`, so ↑/↓ hit the rule's "no row there" branch and stay.
* A measurement that looked like a regression and was not: the chip said "All, 200" where an hour earlier it said
  1 000 — `clipboard.maxHistory` had meanwhile been set to 200 in the user's defaults (the key did not exist at 22:06);
  the DB still had 1 832 rows. **Read the setting before calling a smaller number a bug.**
* `scripts/mutation-check-notch-clipboard.sh` is now 9/9 (D9: the clipboard page as narrow as the tray).
* Still not verified by hand: the same list as D0 (a real ⌘⇧V through the tap, paste-back, Touch ID, the picker), plus the
  look of the band on a screen without a notch (none attached) and trackpad scrolling of the deck.

### D0c (2026-10-12) — "giật" measured to its root: AppKit's order-front zoom, not SwiftUI

The user: the hub "giật lệch từ phải qua center", animation "lag lag khi loading". Three measurements, three causes:

1. **CGWindowList polled at 10 ms** (`scratchpad/openlat`): the window appeared at **x 649, 742 wide, 252 tall**, grew to 754
   and only at ~450 ms jumped to **x 488, 752×232**. `reveal(page:)` dispatched `.activate` (tray, 440×254) THEN
   `.switchPage(.clipboard)`; the second render saw width grow but height shrink and took the "shrink" branch, which defers
   `setFrame` by 0.32 s. Fix: `Event.activateOn(Page)` — one transition (machine test), and the mixed case now sets the
   window to the **union** of both frames first, then the exact target after the spring.
2. **`sample` during an open**: 214 of 565 main-thread samples in `-[NSAnimation _runBlocking]` under
   `NSHostingView.layout()`. Hypothesis A (the hosting view animates the window to follow SwiftUI's ideal size) led to a
   `GeometryReader` root with the content laid out once at the state's size — `_runBlocking` fell to 34, the window still
   sprang 740→754→752. The window never appeared smaller than **98.4 %** of its final size: that is AppKit's **order-front zoom
   animation** (`NSWindow.animationBehavior` default), and it runs blocking on the main thread, so the SwiftUI spring that
   draws the surface growing out of the notch could not render. Fix: `SurfacePanel.animationBehavior = .none` for every
   surface. After: the window shows up in ONE sample at 752×232 (106 ms after the URL; 258 ms on the first open after
   launch, cold caches), `_runBlocking` 0. **A smooth-looking "spring" in a window-frame trace can be the OS's own zoom.**
3. **CPU per open+close ≈ 0.45 s, before AND after** (ps cputime over 3 cycles) — not improved, say so. The remaining samples
   are SwiftUI/CoreAnimation frames of the 0.32 s spring (`stepTransactionFlush`, `NSHostingView.layout` 52) plus the
   LaunchServices URL route the probe uses; a real ⌘⇧V skips that route. Caches added anyway, each measured as a per-render
   cost before: `ClipboardAppIcon` (LaunchServices lookup + icon render per card per render), `ClipboardAppIcon.fileIcon`,
   `NotchThumbnailCache` (ImageIO thumbnail ≤ 480 px instead of decoding a 2722×1562 PNG for a 174×100 tile),
   `NotchTextCache` (the footer's word count re-read every payload file per render). All `@MainActor` — Swift 6 refused the
   `static let NSCache` as a global; isolating to the actor every caller already runs on is the honest fix, not
   `nonisolated(unsafe)`.

Also in this step: `appearFromNotch` (first frame of an opening at the notch is the notch's own size, fades in while the
shape springs out — pointer-anchored trays still appear instantly under the hand); `NotchClipboardRules.imageScaling` (a
2.8:1 settings screenshot filled into a 1.74:1 tile was a zoomed centre crop — fit above 1.5× either way, mutation D10);
History limit **20 · 100 · 1000** with an extra row for a stored value outside the three (200, 5000, 0) so the control never
shows blank; `ClipboardManager.historyCap` is the ONE reader and now also bounds `fetchClipboardRecords` (it was a hard-coded
1 000, so "5 000"/"Unlimited" never loaded more); **plain screens get a virtual notch** (every state flush with the top edge
over the menu bar's centre; B7's "under the menu bar" withdrawn at the user's request — geometry tests only, no external
display attached). Settings copy for the plain-screen notes rewritten.

Not verified: smoothness by eye (the user's video was recorded on the previous build), a plain screen, the first open's
258 ms cold start by hand.

## D1 (2026-10-12) — quick wins from the OneNotch reconciliation, group 1 (clipboard)

Seven of the ten items in REDESIGN_PLAN §3b's D1 table, each a small addition to a manager that already exists:

| # | What | Where | Measured |
|:--|:--|:--|:--|
| 7 | `#hex` · `rgb()` / `rgba()` · `hsl()` / `hsla()` (comma or space syntax, `%`, `deg`, `/ alpha`) are colour clips | `ColorFormat.parse` (pure, 3 new tests, mutation D11 hue wrap); `ClipboardClassifier.classify` and `color(from:)` use it, the hex regex is gone | real pasteboard: `rgb(255, 136, 0)` and `hsl(210, 65%, 57%)` recorded as `type = color` |
| 14 | "Tạm dừng ghi clipboard" (`clipboard.paused`, ONE reader `ClipboardManager.isPaused`; the change count still advances so un-pausing does not ingest the stale item) + the notch footer says so (`Footer.paused`, outranks the Accessibility warning, below a fresh notice; mutation D12) | settings privacy section; `FeatureKeyDefaultsTests` | paused: copy ⇒ row count unchanged, footer "Clipboard recording is paused." + Open Settings; un-paused: next copy recorded, the paused one never |
| 16 | Copy sound picker (`clipboard.copySound`, "Pop" default, ONE reader in `ClipboardSounds`) | settings, under the sounds toggle, disabled with it | AX: "Copy sound" row present |
| 36 | "Phát âm" / "Dừng phát âm" on text clips — `AVSpeechSynthesizer`, voice from `NLLanguageRecognizer.dominantLanguage` when a matching voice exists | notch context menu | not verified by ear |
| 9 | "Sửa văn bản…" — `NotchTextEditorView` in a `SurfacePanel(.interactive)` at the Spotlight position: edit, **Sao chép** (the monitor records the edited text as a new clip), Esc closes. Deliberately no paste-into-app button: the job is "sửa rồi copy lại" | `NotchSurfaceController.editText`, pbxproj ×4 | not verified by hand (needs a click) |
| 6 | ⌘⌥C opens the OLD floating shelf whatever ⌘⇧V is set to (the reference's second surface); a pin button on the shelf's top bar makes it ignore clicks outside (`isPinned`; Esc and ✕ still close) | `ClipboardShelfController.handle` + view | not verified (would need posting ⌘⌥C into the user's session) |
| 3 | Drag a card onto the **Đã ghim** chip (pins it) or a board chip (adds it) — `.onDrag` carries the record id as plain text, `.onDrop(of: [.plainText])` on the chips | `NotchClipboardView` | not verified by hand |

Traps from this step: (1) **a test expectation taken from a reference page can be wrong** — OneNotch pairs `#4A90D9`
with `hsl(210, 65%, 57%)`, but those are rounded forms of each other (the exact hsl is 210.6°, 65.3 %, 57.1 %); the
converter was right (`#4A91D9`) and the test is now pinned to that with the reason, so nobody "fixes" the maths to
match the marketing copy. (2) Inserting a property between `@discardableResult` and its function compiles in the test
package (it is not there) and fails the app build — attributes bind to the NEXT declaration. (3)
`ClipboardTransform.stats` returns a labelled tuple, not a `Stats` type.

Gates: tests 638/0 · mutations 12/12 red (D11, D12 new) · L10n 5 gates 0 · runtime on the installed bundle 0 leaks.
Three test rows were left in the user's clipboard history (two colours, one `XF-D1-RESUMED` text).

## D1 (2026-10-12) — group 2: pages on the notch, two-finger page swipe, accent; and the hub's corners

* **`notch.pages`** (comma list, default `files,clipboard,nowPlaying`; ONE reader `NotchSurfaceController.pageOrderRaw`)
  decides which tabs the hub shows and in what order. `NotchPages` (pure, symlinked, 7 tests): unknown tokens dropped,
  duplicates collapsed, an empty list means the default (a hub with no page is not drawable), hidden pages trail in the
  settings list, a request for a hidden page resolves to the first shown one (`reveal`/`switchPage` go through it, and
  `applySettings` switches an open hub off a page that was just hidden), the last shown page cannot be hidden. A hidden
  Clipboard tab makes ⌘⇧V fall back to the floating shelf (`surfaceToOpen` gets `isEnabled && showsClipboardPage`).
  Measured: `defaults write notch.pages clipboard,files` + relaunch ⇒ the hub's AX tree lists **Clipboard, Tray** and no
  Now Playing; the settings list (Notch & Khay thả ▸ "Các trang trên notch") shows all three with ▲ ▼ and a switch.
* **Two-finger swipe over the tab band** changes page: a LOCAL `scrollWheel` monitor that exists only while the hub is
  open (`syncHubSwipe`, paired with the keyboard monitor in `dispatch`), restricted to the top band so the clipboard deck
  and chip row keep their own sideways scroll. `NotchPages.SwipeAccumulator` fires once per gesture past 60 pt and
  resets on the gesture's end phase; fingers moving right = previous page (natural scrolling), no wrap at the ends
  (mutation D15: a swipe that keeps firing). Not verified with a hand on the trackpad.
* **`notch.accent`** (`system` default; ONE reader `accentName`) → `NotchAccent.rgb(named:)` → a SwiftUI environment
  value `notchAccent` read by every notch view where `Color.accentColor` used to be (6 sites). Not verified by eye
  (the panel is invisible to capture).
* **Corners (user: "bo góc mịn hơn khi phóng to")**: `XFinderTokens.Radius.hub = 36` for the expanded hub (24 on a
  752-pt panel reads as a sharp rectangle; the reference's corners measure ≈ 0.155 × height), still `.continuous`, and
  `NotchShape.topFillet = 12`: two concave quarter-circles that flare the body into the top edge like the Dynamic
  Island. The flares are OUTSIDE the content, so `NotchSurfaceLayout.size` adds `2 × topFillet` to an expanded hub at
  a notch (real or virtual) — measured **776×232 at x 476**, still centred — while a pointer tray stays 752 (no edge
  to flare into); `clipboardShell`'s wings and `hubShell`'s padding subtract the flare, and strokes follow the body
  shape (stroking the compound outline draws lines where the subpaths meet). The outline was rasterised from the same
  path code (`scratchpad/shape/render.swift`) and checked by eye before building (mutation D16: the flares eat the content).
* Trap: the first `xfinder://…` URL sent within ~8 s of the install script's launch is dropped (seen three times);
  after ~12 s, or after a plain relaunch, it works. Unexplained; not the user's ⌘⇧V path. Wait ≥ 12 s in probes.

Gates: tests 645/0 · mutations 16/16 red · L10n store 0 · runtime on the installed bundle 0 leaks.

## D2 (2026-10-12) — code colouring, `.xfinderclip`, a Clipboard MCP server; and ⌘⌥C goes off by default

Three "medium" items from the §3b reconciliation, plus one mid-turn user request. Each is a pure module with its
own tests, wired into existing surfaces — no new page, no new target.

| Piece | Pure (symlinked, tested) | Wiring |
|:--|:--|:--|
| Code colouring | `Core/Clipboard/CodeHighlighter.swift` — `guessLanguage` (12 languages, `.plain` when nothing matches), single-pass `tokenize` whose tokens must cover the string contiguously (asserted), cap `maxLength = 4 000` ⇒ one plain token (15 tests) | `Views/Components/HighlightedCode.swift` builds ONE `AttributedString` → `Text`, two palettes (notch dark / shelf follows `colorScheme`), tokenises only the first 8 lines. Used by `NotchClipCardView` (`.code` only — `.markdown` stays mono) and `ClipboardCardView.codeBody` |
| Export / import | `Core/Clipboard/ClipExport.swift` — `stage` (manifest + `payloads/<id>.<ext>`, paths never absolute, excluded bundle ids dropped before any copy, missing files counted not faked), `plan` (new / duplicate by id; built-in boards never imported), `materialize` (fresh names, an image with no bytes ⇒ nil) (8 tests) | `Core/Clipboard/ClipTransfer.swift` (AppKit): panels, `ArchiveRunner.compress(sources: [manifest.json, payloads/])` → `zip -r` into `X.xfinderclip`; import = `extractToStaging` (bsdtar reads the zip by content) → plan → materialise → `ClipboardManager.importRecords`. Two buttons + one outcome line in Cài đặt Clipboard |
| MCP | `Core/MCP/MCPProtocol.swift` — JSON-RPC envelopes, `initialize`/`tools/list`/`tools/call`/`ping`, three tools (`clipboard_list_recent`, `clipboard_search`, `clipboard_get`), limit clamp 1…100, password-manager fence, text only (11 tests) | `Core/MCP/MCPServer.swift`: `XFinder --mcp` decided in `XFinderApp.init` **before any scene exists**; stdin lines → stdout lines via `FileHandle` (unbuffered); SQLite opened `SQLITE_OPEN_READONLY`, re-read per call; `exit(0)` on EOF. Switch `clipboard.mcpEnabled` (default **off**): tool calls answer `-32000`, the handshake still works so a client lists the tools and sees the error text |
| ⌘⌥C | — | `clipboard.shelfHotkey` default **false** (user: "tạm tắt, khi nào cần tôi bật trong settings"). The tap callback is nonisolated, so the reader is mirrored into a `Locked<Bool>` snapshot in `applySettings()`, like `isOpen`. ToggleRow under the "⌘⇧V mở ở" picker |

**Why `--mcp` and not a second executable.** The plan said "target executable mới". A second target in this hand-authored
pbxproj means a second product to sign, embed and keep in `install-mouse-rebuild.sh`; an MCP client only needs a command
to run. The app binary already links SQLite and the record model, and `XFinderApp.init` runs before AppKit does anything
TCC-gated, so the mode is safe to launch from a terminal (the Part 3c "never launch the binary from a shell" warning is
about the GUI path and its AX/Bluetooth requests being attributed to the shell). Measured: the process exits on EOF,
`pgrep` finds nothing a second later, no window appears.

**Measured on the fresh build (binary in `/tmp/xfinder-clean-build/out`, stdin piped):**

| Call | Switch off (user default, key absent) | Switch on (written for the probe, then `defaults delete`d) |
|:--|:--|:--|
| `initialize` | `protocolVersion 2024-11-05`, `serverInfo.version 1.2.0` | same |
| `tools/list` | 3 tools with schemas | same |
| `tools/call clipboard_list_recent {limit: 3}` | `-32000 "Clipboard MCP is turned off in XFinder ▸ Cài đặt Clipboard"` | 3 real rows, newest first (Safari, 00:57Z) |
| `clipboard_search "XF-D"` | — | the two probe rows from D0/D1 |
| `clipboard_search` with no hit | — | `No clipboard items match "…"` |
| `clipboard_get "not-a-uuid"` | — | `-32602 Invalid params: id must be a UUID` |
| `clipboard_get <first id>` | — | the clip's full text |
| `ping` | `{}` | — |

**`zip`/`tar` with a non-`.zip` extension, measured before trusting the engine:** `zip -r X.xfinderclip manifest.json payloads`
keeps the name (zip appends `.zip` only when there is no extension at all); `unzip -Z1` lists `manifest.json`, `payloads/`,
`payloads/a.png`; `tar -xf X.xfinderclip` extracts the zip by content (bsdtar autodetect), bytes identical. And **`zip` onto an
existing archive UPDATES it in place** (manifest replaced, old payloads kept) — so `ClipTransfer.export` removes the chosen file
first; the save panel has already asked about replacing.

**Rendered page (installed app, AX):** English — 158 nodes, every new string in English, 0 diacritic lines. A Vietnamese dump
taken right after `defaults write AppLanguage` WITHOUT a relaunch still showed the new section in English (the sidebar had
switched; the settings body had not re-rendered) — `L10n.t` is read at render time, so **measure a language switch after a
relaunch**, not after a `defaults write`. Store 1 997 entries, all six L10n gates 0, runtime gate on the installed bundle 0 leaks.

### Traps of this pass

* **A `+` in a pbxproj path must be quoted.** `path = Pinboard+SwiftUI.swift;` makes xcodebuild say only `Unable to read project`
  — no line, no file. `plutil -lint project.pbxproj` names the character (`Unexpected character / at line 1` for the whole file);
  `path = "Pinboard+SwiftUI.swift";` fixes it. Lint the pbxproj after every scripted edit.
* **`static let` on a `@MainActor` class is main-actor-isolated** — `nonisolated static func` cannot read it even though `[String]`
  is Sendable. Mark the constant `nonisolated private static let`.
* **`stdout` is a C global and Swift 6 rejects the reference** (`setvbuf(stdout, …)`). Use `FileHandle.standardOutput.write`.
* **`Pinboard.swift` imported SwiftUI only for `CodableColor(color:)`/`.color`/preset names**, which made the whole model
  unsymlinkable into the test package. Split: `Models/Pinboard.swift` Foundation-only (+ `Equatable`, + a plain `init(red:green:blue:alpha:)`),
  `Models/Pinboard+SwiftUI.swift` for the rest, with `defaultPinboards` moved into the extension so the exact default colours
  did not change. The agent that wrote `ClipExport` had worked around the missing `Equatable` with a hand-written `==` and a
  `boardsEqual` — two sources of truth for equality; both deleted once synthesis worked.
* **The mutation harness takes anchors through `ast.literal_eval`**, so a two-line anchor needs `\\n` inside the shell string, not
  a real newline (a raw newline is a Python `SyntaxError` and the run aborts with "anchor not found" — on the first run that
  message was right for the wrong reason). The abort left the tree clean (`trap EXIT` restore).
* **Review the agents' output as code, not as a report.** Both agents' reports were accurate; the only edits needed were the
  `Equatable` cleanup and a test-package dependency they could not see (`Pinboard`). The pbxproj entries and symlinks are
  always the integrator's job — an agent confined to two files cannot add them.

### Not verified (say so)

Clicking **Xuất/Nhập** through a real `NSSavePanel`/`NSOpenPanel` (needs a hand; the staging → zip → unzip → plan → materialise
chain is covered by `ClipExport`'s 8 tests, `ArchiveRunner`'s 13 integration tests and the zip/tar measurement above). The token
**colours by eye** (`screencapture` still fails on this host), and a highlighted card was **not rendered live at all**: the hub's
type chips on this Mac are `Images | Link | Text | File | Color` — no code clip among the newest 200 (`clipboard.maxHistory` = 200
is the user's setting) — and pushing one through `pbcopy` recorded nothing because **`clipboard.paused` = 1 on this Mac** (the
user's switch, or a leftover from the D1 pause probe — unknown; left alone and reported). A type chip only exists for types present
in the loaded history (mutation D5 pins it), so "no Code chip" was correct behaviour, not a bug. **MCP from a real client** (Claude Code / Cursor) — only the stdio probe above.
Gates: tests **679/0** (+34) · mutations D17–D22 added (see the run in the commit message) · L10n 6 gates 0 · runtime 0 leaks.

## D3 (2026-10-12) — Thư viện Clipboard: a sidebar page over EVERY row, built by contract-first fan-out

The owner chose wireframe **B** (two columns + an inspector that slides in from the right) from three rendered
wireframes (`scratchpad/uiux/lib/wireframe.html?v=a|b|c`, headless Chrome PNGs sent to them). Job sentence: *"I need
to find an old clip — beyond the 4 cards at the notch — filter by type / app / board / time, inspect it, then paste,
pin to a board, or delete."* Measured before designing: the DB held **1 846** records while `clipboard.maxHistory` was
200, so ~1 600 clips had no surface at all. The page re-introduces a content row in the sidebar (`SidebarDestination.
clipboard`, "Thư viện Clipboard", `doc.on.clipboard`, under CÔNG CỤ) — the 2026-10-10 "no content page" decision is
superseded by the owner's pick; the notch and shelf remain the quick surfaces.

### Shape

| File | Pure? | Holds |
|:--|:--|:--|
| `Core/Clipboard/ClipboardLibraryRules.swift` | yes (symlinked, 35 tests) | `Scope` (all · pinned · type · app · board), `Query` (scope + text + sort + period), `facets` over the LOADED set (apps by count desc then name; nil bundle id → `""`), `apply` (scope → `ClipboardFilterToken` `@type`/`@app` + free text over snippet/OCR/title/app/url → period → sort), periods **today = same calendar day, week = 7×24 h, month = 30×24 h** (rolling, pinned by boundary tests), `visibleCount` (60-row display window), `scopeTitleKey` + `scopeTitleIsKey` (a board or app name is a proper noun, never wrapped), `Facts` (lines/characters/`ByteCountFormatter`), `move` (no-wrap grid) |
| `Core/Clipboard/ClipboardLibraryStore.swift` | AppKit | `@MainActor @Observable`; `records` = **every** row (`DatabaseService.fetchAllClipboardRecords`), coalesced `reload()`, `facets`/`filtered`/`visible` computed, selection + inspector state, actions: copy · paste into the previous app · pin (manager path for in-cap rows, `updateClipboardRecord` for the rest) · board membership · transforms · open source app/page · reveal · Quick Look (text → temp `.txt`) · delete |
| `Views/Detail/ClipboardLibraryView.swift` | SwiftUI | rail 180 pt (LỌC / LOẠI / ỨNG DỤNG top 8 + "Thêm…" / BẢNG + "+ Bảng mới"), header search + sort + period menus, `LazyVGrid` of `ClipboardCardView` (146 pt), footer "Hiện 1–60 trong 1 846 · Tải thêm", inspector 320 pt (`.move(edge: .trailing)`), keyboard on the grid (`.focusable` + `.onKeyPress`), ⌘F via a hidden keyboard-shortcut button |
| `DatabaseService` | actor | `fetchAllClipboardRecords`, `countClipboardRecords`, `updateClipboardRecord` (INSERT OR REPLACE), one private row mapper shared with `fetchClipboardRecords` so the two reads cannot drift |

### How it was built — contract first, three file-confined agents, then integrate

The three pieces were written **in parallel** by agents that never saw each other's files. That only works when the
integrator writes the **contract** (every type name and signature the pieces share) into all three prompts, and does
the central edits itself: `SidebarDestination` case/title/icon/group, `RootView` routing, the 4 pbxproj entries per file,
the test symlink, the store entries — all done *while the agents ran*, because none of it depends on their content.
Cost of the one ambiguity I left in the contract ("reuse the notch's direction enum if it fits, else add your own"):
the rules agent added `ClipboardLibrary.MoveDirection`, the store agent used it, the view agent used
`NotchClipboardRules.Direction` — one compile error, one line. **A contract must not contain "if it fits"; decide.**

### Found by reading the agents' output as code

* **"Dán vào app trước đó" could never paste.** The store called `ClipboardPasteEngine.paste(record:to: nil)` after
  `NSApp.hide(nil)`. `paste(to: nil)` deliberately only copies — it never synthesizes ⌘V without a target pid (to avoid
  pasting into XFinder itself). The button would have lied (Part 0 §6). Fix: after the hide settles (0.25 s) read
  `NSWorkspace.shared.frontmostApplication`; not XFinder ⇒ paste to that pid; XFinder/no app ⇒ copy + notice "Không có
  app nào để dán — đã sao chép."; no Accessibility ⇒ copy + notice naming the missing permission. **Trace every
  "to: nil" default to what the callee does with nil.**
* `audit-ui-tokens.py` caught three literal font sizes in the view (10 / 13 mono bold / 36) — replaced with tokens.
* The rail counts were checked against SQLite, not trusted: text 1 020 · image 295 · link 209 · markdown 190 · code 73 ·
  file 51 · color 8 · pinned 0 · Chrome 580 · Safari 406 — identical. Footer "Showing 1–60 of 1.846".

### Measured on the installed app (AX, English UI)

269 nodes; sidebar row "Clipboard Library"; rail FILTER/TYPE/APPS/BOARDS with the counts above; 2 `AXPopUpButton`
(sort, period); "Load more". The 13 "diacritic" lines in the English dump were **`×` in image dimensions** (U+00D7 is
inside the `[À-ỹ]` class) plus one Vietnamese clip's own text — not UI leaks; tighten the regex when a dump counts
dimensions. Idle CPU with the page open: **0.19 s / 60 s** (≈ 0.3 %, no timer on the page).
**Not measured live:** selecting a card (the card is an `.onTapGesture`, not an AX button, and the user was at the
keyboard so no synthetic events), therefore the inspector, keyboard, paste-into-previous-app and every action button.
**The AX numbers above are from the build BEFORE the review fixes.** By the time the fixed build was installed the
screen was locked (`CGSSessionScreenIsLocked = true`; `probe-ax-dump` printed its "not a measurement" line, as designed
in B1), so the final page was verified only by the runtime L10n gate (0 leaks), the test suite and the build. Re-dump
after unlocking: `open "xfinder://settings?page=clipboard"` then `swift docs/probes/probe-ax-dump.swift <pid> 16`.
**Review agents left nine files in the repo root again** (three copies of real sources for a typecheck, six
`probe_*.swift`) despite the scratchpad instruction — found by `git status` before staging, deleted after confirming
each was a byte-identical copy or a probe. Stage by explicit path, always.

### Gates

Build arm64, 3 new files in the compile log · tests **714 / 0** (+35) · `mutation-check-notch-clipboard.sh` **26/26 RED**
(D23 pinned scope ignored · D24 week widened to 8 days · D25 apps sorted by name first · D26 visibleCount unclamped) ·
L10n store 2 027 entries, six gates 0, UI tokens 0 · sidebar gate 34 titles 0.

### D3 review (2026-10-12): 5 lenses, 2 refuters each — 11 confirmed, 2 split, 2 refuted, 0 incomplete

Run on the uncommitted tree right after the first green build; 35 agents. Every confirmed/split row was fixed in the
same pass unless marked accepted. The refuters downgraded four of the five "HIGH" labels — the finders measured
mechanisms correctly and severities badly; read both verdicts before touching code.

| Finding | Verdict | What changed |
|:--|:--|:--|
| **"Dán vào app trước đó" hid the window before knowing a paste was possible** (no Accessibility ⇒ hide, then copy) | confirmed | `WindowManager.isTrusted` checked BEFORE `NSApp.hide`; the frontmost-app check stays after the hide, because reading it before returns XFinder itself |
| **Esc did nothing with the search field focused** — the grid's `.onKeyPress(.escape)` is not in the field's focus chain; `searchFocused` was never set false anywhere | confirmed (both: medium) | `.onExitCommand` on the TextField: clear the query → close the inspector → leave the field |
| **The grid might never get keyboard focus** (`.focusable()` with no `@FocusState`; cards are `.onTapGesture`) | split (R1: click-to-focus should work; R2: high) | `@FocusState gridFocused`, taken on appear and on every card select — cheap, removes the doubt |
| **Pin on an in-cap row could flip back**: the manager persists asynchronously, the store `reload()`ed from SQLite at once | split (R1 traced the actor hops as ordered; R2: medium) | No reload after an edit at all: the store patches its local row (`replaceLocal`) — the same value the manager now holds. Same for out-of-cap rows after their own write |
| `filtered`/`visible`/`facets` recomputed on every read — footer 5×, grid 2×, rail 9× per render (~0.35 ms per `apply` at 1 846 rows, ~13 ms per rail render) | confirmed (low/medium) | Memoised in the store, `@ObservationIgnored` caches keyed on `recordsVersion` (bumped by `records.didSet`) + boards + query + the current minute (periods read the clock); footer and grid hoist their reads |
| "Đã dùng" never incremented from the Library's own copy/paste | confirmed | `bumpUsage`: manager path in-cap, `updateClipboardRecord` out-of-cap, local patch either way; called from `copy` and from a successful paste |
| `scopeTitleKey`/`scopeTitleIsKey` tested but unused — the rail re-implemented the key/name distinction inline | confirmed (low) | the rail resolves all/pinned/type/board titles through them; app rows keep the facet's name (the rule cannot know a name from a bundle id) |
| `ClipboardCardView` decoded images with `NSImage(contentsOfFile:)` in a computed property; the Library shows 60 cards | confirmed, downgraded (image records already point at a 300-px thumbnail; `.file` previews decode the original) | both sites go through `NotchThumbnailCache` (ImageIO, ≤ 480 px) — the shelf benefits too |
| `countClipboardRecords()` had zero callers | confirmed (low) | deleted. One refuter also killed the finder's alternative fix: wiring it into the footer would have changed "n of filtered" into "n of the whole table" |
| `reload()` re-reads the whole table on every copy while the page is open | confirmed (medium/low) | **accepted**: the fetch runs on the actor, is coalesced, and a 1 846-row read is milliseconds; an incremental prepend would need its own de-dupe/ordering rules — not worth a second source of truth yet |
| Selecting a card re-evaluates the whole grid body | confirmed (medium/low) | partly: the memoised `visible` makes the re-evaluation cheap; per-row selection views were not introduced |
| togglePin loses the pin via unordered actor hops | **refuted** | the hops are ordered in practice — and the reload-after-edit is gone anyway |
| reload discards the user's pagination | **refuted** | `pagesShown` is only reset by a query change; a reload keeps it |

Lenses that looked and found nothing: delete path (DB + capped history + store), board membership (UserDefaults,
synchronous), every `L10n.t` literal and store notice key resolves (47 + 5, checked programmatically), the inspector
overlay geometry, `ClipboardManager` is in the environment at `RootView`.

## D4 (2026-10-12) — Bảng khoá: Secure Enclave + HPKE, unlock per card (wireframe B)

The owner chose **B** (each card asks Touch ID; only that clip is decrypted, in memory, until the page is left) and,
by default, placeholder cards on the notch/shelf that open the Library. Job: *"a few sensitive clips in one board that a
shoulder-surfer, someone at my unlocked Mac, or anyone who copies xfinder.db cannot read."*

### Measured before a line was written (macOS 27, this M3 Pro)

| Probe | Result |
|:--|:--|
| `HPKE.Ciphersuite` members this SDK exposes | `P256_SHA256_AES_GCM_256`, `Curve25519_SHA256_ChachaPoly` — **no Curve25519 + AES-GCM** (the first one-liner "failed to produce diagnostic", which is `swift -e` choking, not the API; a file-based probe answered) |
| P-256 HPKE round trip | plaintext back byte-identical; ciphertext = plaintext + 16; encapsulated key 65 bytes; wrong key throws |
| `SecureEnclave.isAvailable` | true; an enclave P-256 key works as the HPKE recipient and restores from its 284-byte `dataRepresentation` |
| `SecAccessControlCreateWithFlags(WhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence])` | created (no prompt at creation; the prompt comes at USE) |
| `LAContext.canEvaluatePolicy(.deviceOwnerAuthentication)` | true, biometry type 1 (Touch ID) |

**Design that follows from the measurements:** the private key never leaves the Secure Enclave and every use prompts
(`.userPresence`, fresh `LAContext`, reuse 0 s — that is what makes "per card" real rather than a 5-minute cache the UI
pretends is per card). The PUBLIC key seals, so adding a clip to a locked board never prompts (HPKE is one-way). Both the
public key and the enclave key's opaque blob live on the `Pinboard` (UserDefaults): the blob is useless off this enclave,
and keeping it out of the Keychain avoids the dev-signing identity trap (a differently-signed build is "another app" to
the Keychain). Honest consequences, stated in the confirmation sheet: protects against shoulder-surfing, a copied DB,
MCP and export; does NOT protect against someone with your unlocked session who passes Touch ID; the key is bound to
this Mac's enclave — a dead Mac means the locked clips are gone; export never includes them.

### Shape (contract-first fan-out again; the integrator owned the shared model fields and both fences)

| Piece | File | Holds |
|:--|:--|:--|
| shared (me, before the agents) | `Pinboard.lockPublicKey/lockKeyData/isLocked`, `ClipboardRecord.isLocked/lockedBoardID`, pbxproj ×2, test symlink | so three parallel agents compile against one truth |
| fences (me) | `MCP.visible` drops `isLocked` rows; `ClipExport.stage` skips locked rows **and** locked boards | a locked row has no text, but a reader must not even list it — `clipboard_get` by id would hand out whatever a future column carries; a locked board without its items would import as an empty shell claiming to be locked. Tests: `testLockedRecordsNeverAppearInAnyTool`, `testLockedRecordsAndLockedBoardsAreNotExported` |
| A `Core/Clipboard/BoardLock.swift` (pure, CryptoKit) | blob = version byte + 65-byte encapsulated key + AES-GCM ciphertext; `Envelope` (snippet, OCR, hidden metadata, file names); `lock` moves every content field out of the row and seals payload/thumbnail files into `…/Clipboard/Locked/<id>.{env,payload,thumb}`; `unlock` → `UnlockedClip` (in memory); `restorePlain` for "Gỡ khoá"; `fenced` | tested with software P-256 keys — the enclave key and the software key share `HPKEDiffieHellmanPrivateKey`, which is why `open(_:with:)` is generic |
| B `Core/Clipboard/BoardLockKeys.swift` + manager + paste engine | `createKey` (enclave + access control), `recipient(keyData:reason:)` (fresh `LAContext` per call), 0600/0700 `fileOps`; `ClipboardManager.lockBoard/unlockBoardPermanently/removeItemFromLockedBoard`, sealing inside `addItemToPinboard`; `ClipboardPasteEngine.paste(unlocked:)` writes from bytes, never from a path | |
| C UI | Library: lock glyph + context menu + honest confirmation, locked-board banner, locked card body, per-card unlock, inspector; `relockAll()` on leaving the page and on `com.apple.screenIsLocked`; notch/shelf: placeholder, select ⇒ open the Library at that board | |

### D4 — what integration found (2026-10-12)

**The "keys" agent died of the session limit before reporting — but had finished.** Its four files were complete
(`BoardLockKeys` with `createKey`/`recipient`/`fileOps`/`lockedDir`; the manager's `lockBoard`, `unlockBoardPermanently`,
`removeItemFromLockedBoard`, sealing in `addItemToPinboard`, sealed-file cleanup in `deleteRecord`; `fetchClipboardRecord(id:)`;
the engine's `paste(unlocked:)`/`writeToPasteboard(unlocked:)`). **Check the tree, not the report** — `git diff --stat` on the
agent's files said 268 insertions while the workflow said "failed". It also left `cryptokit_dump.{err,txt}` in the repo root.

**Two data-safety bugs in that code, found by reading it as code (a security feature gets read twice):**

| Bug | Why it mattered | Fix |
|:--|:--|:--|
| `unlockBoardPermanently` dropped the key when `restoredCount > 0` | one member that failed to open (corrupt envelope, missing file) was left as ciphertext with **no key anywhere** — unreadable forever, still flagged `locked` for a board that no longer is | the key is dropped only when `restoredCount == members.count`; otherwise `BoardLockFailure.partialUnlock` is thrown AFTER the restored rows are persisted, the board stays locked, the page says "Một số clip chưa giải mã được — bảng vẫn khoá." |
| `addItemToPinboard` appended membership and `savePinboards()` **before** sealing, and sealing was `try?` | a sealing failure (disk full, payload file gone) left a **readable row inside a locked board** — the one thing the feature exists to prevent | seal first, join only on success; returns `Bool` (`@discardableResult`) so the Library can say "Không thêm được vào bảng khoá."; the async path (a row outside the capped history) joins inside its Task only after sealing |
| `lockBoard` silently skipped members it could not seal | same shape: plain rows inside a locked board | unsealable members are **detached** from the board (itemIDs + `pinboardID = nil` persisted), the key is still saved for the sealed ones, `BoardLockFailure.partialLock` tells the page: "Đã khoá bảng. Một số clip không mã hoá được và đã bị bỏ khỏi bảng." |

**Smaller traps:** `static let fileOps: BoardLock.FileOps` is a stored global of a non-Sendable struct (closures) → Swift 6
error; a computed `static var` has no shared state and compiles. The UI agent self-reported an interpolated key
(`L10n.t("Khoá bảng “\(board.name)”?")`) — split into the fragment `"Khoá bảng "` + the proper noun outside `t()`. The manager's
Touch ID reason is a `L10n.t` call in Core (`"Gỡ khoá bảng này và giải mã lại mọi clip"`) — allowed here (the sheet needs a display
string), but it only showed up in `audit-l10n-literals` as the single WRAPPED-but-missing key, so register such keys by hand.

**`BoardLock.open` maps every HPKE failure to `.wrongKey`.** With an enclave key that demands presence, a Touch ID *cancel*
most likely surfaces inside `HPKE.Recipient`/`open` and will therefore read as "Không mở khoá được." rather than a silent
cancel. **Unverified** — measuring it means triggering a Touch ID sheet on the user's screen; the store maps
`BoardLockKeys.Error.cancelled` for the paths where `recipient()` itself throws. Re-check with a hand: cancel the sheet and
read the notice.

**Measured with a harness built from COPIES of the production `BoardLock` + `BoardLockKeys` (scratchpad `d4/harness`),
against a REAL Secure Enclave key created with `[.privateKeyUsage, .userPresence]` — 15/15:** key created with no prompt
(`dataRepresentation` 427 B with access control — not the 284 B of a plain enclave key), public key 65 B; the locked row has no
snippet/OCR/thumbnail, keeps `isPinned`/`usageCount`, drops `url`/`customTitle`, carries both lock keys; the plain payload and
thumbnail files are gone; `<id>.env/.payload/.thumb` exist, contain **no plaintext bytes** (searched for the token and the
account number), are `0600` inside a `0700` folder; a software P-256 key is rejected (`.wrongKey`); `fenced` drops the row.
`BoardLock.lock` does NOT create `lockedDir` — the harness's first run failed on that until it resolved the folder through
`BoardLockKeys.lockedDir()` like the app does. **Not measured:** opening with the enclave key (Touch ID), every click, the
notch/shelf placeholder, the confirmation sheet.

### D4 review (2026-10-12): 5 lenses, 2 refuters each — 14 confirmed, 1 split, 1 refuted

On the uncommitted tree after the first green build and the 15/15 enclave harness; 37 agents. Every confirmed row
was fixed in the same pass unless marked accepted; the review agents again left **16 probe/copy files in the repo root**
(third time) — deleted after checking each against its source.

| Finding | Verdict | What changed |
|:--|:--|:--|
| **Quick Look of an unlocked image/file left its decrypted bytes in `$TMPDIR/XFinderLibraryQuickLook/<id>.<ext>` forever** — `relockAll()` deleted only `<id>.txt` | confirmed, high (both) | `relockAll()` removes **every** file in the temp folder, whatever it is called; also called from `windowShouldClose` and `applicationWillTerminate` |
| **Closing the main window did not relock** — `windowShouldClose` only `orderOut`s, so the Library's `.onDisappear` never fires | confirmed, high (both) | `relockAll()` in `MainWindowController.windowShouldClose` (AppState.swift) |
| **`lockBoard` saved the key LAST** — a crash mid-loop left sealed rows whose plain files were already deleted and **no key anywhere** | confirmed, high (both) | key created and `savePinboards()` **before** any row is sealed; `lockBoard` on an already-locked board reuses the key and seals the members still plain, so a crash is recoverable by locking again |
| **Deleting a locked board (Cài đặt Clipboard ▸ Xóa) destroyed the only handle to its key** — no confirmation, sealed rows orphaned | confirmed, high (both) | `deletePinboard` refuses a locked board (`-> Bool`); the settings button is disabled with "Gỡ khoá bảng trước khi xoá." |
| **Notch context menu ignored `isLocked`** — "Dán" / "Xem nhanh" / "Sửa" / "Phát âm" ran on the sealed row: pasted or previewed the `.env` **ciphertext file** | confirmed (downgraded to medium: ciphertext, not plaintext — but still exfiltration of the sealed blob) | locked clips get a two-item menu (Mở trong Thư viện · Xoá); `NotchSurfaceController.openLibraryForLocked` guards paste/Quick Look/speak/edit; **`ClipboardPasteEngine.paste(record:)` and `writeToPasteboard(record:)` refuse a locked row** — the central fence every surface goes through; the shelf's Quick Look and context menu guarded the same way |
| `addItemToPinboard`'s async path sealed with a **captured** public key — a board unlocked during the fetch got a row sealed with a revoked key | confirmed (medium) | the Task re-reads the board's **current** key on the main actor and bails if the board is no longer locked |
| `deleteRecord(id)` skipped sealed-file cleanup for rows outside the capped history (the Library's only delete path) | confirmed (medium) | `deleteRecord(_ record:)` overload removes the sealed files from the record in hand; the Library uses it |
| Dragging a locked card onto ANOTHER board gave it a second, stale membership | confirmed (medium) | `addItemToPinboard` refuses a row locked for a different board (`false`) |
| A dismissed Touch ID sheet may arrive as a Security/CryptoTokenKit error, not `LAError`, and read as "Không mở khoá được." | confirmed-as-plausible (neither side could measure it) | `BoardLockKeys.isCancellation` recognises LAError, `errSecUserCanceled`, underlying errors and "cancel" text; `BoardLock.open` now **rethrows non-crypto errors** instead of flattening everything to `.wrongKey`, so the store can stay silent on a cancel. **Still unverified** — needs a hand on the sensor |
| `lockKeyData` (the enclave key's wrapped blob) lives in UserDefaults, not the Keychain | confirmed (refuters: medium/low) | **accepted, documented**: the blob is enclave-opaque and `.userPresence`-gated on every use, so possession buys nothing without Touch ID; the Keychain would add the dev-signing identity trap (a differently signed build is "another app"). Revisit if the app ever ships with a stable Developer ID |
| `speak`/`editText` read a locked row (inert only because the fields are nil / unreadable) | confirmed (low) | guarded explicitly |
| Quit without relock | confirmed (low) | `applicationWillTerminate` |
| Sealed files are 0644 for an instant between the atomic write and the chmod | split (dir is 0700, so neutralised) | accepted |
| `restorePlain` could be steered by a planted `..` file name | **refuted** (lastPathComponent limits it) | hardened anyway, because the envelope is sealed with a PUBLIC key anyone with the plist can read: `safeFileName` honours only a single plain component (2 tests + mutation D31) |

Lenses that looked and found nothing: fresh HPKE sender per seal (no key/nonce reuse), blob parser bounds, MCP and export
fences, capture never auto-assigns a board, `unlockBoardPermanently` keeps the key while any member is still sealed, every
new literal resolves in the store (131 checked programmatically).

**D4a gates (commit `D4a: locked boards…`):** build arm64 · tests **738 / 0** (+22 BoardLock incl. the file-name sanitiser, +2 fence
tests) · mutations **32/32 RED** (D21b export skips locked rows · D27 fence · D28 content key kept on the row · D29 version byte ·
D30 MCP lists locked rows · D31 planted `../` name) · L10n 2 055 entries, six gates 0, UI tokens 0 · runtime gate on the installed
bundle 0 leaks · enclave harness 15/15 · installed dylib hash == build. **Mutation-script trap:** the D4 fence duplicated the
two-line anchor `skipped += 1 / continue` in `ClipExport.swift`, so D21 aborted the whole run with "anchor not found" — an anchor
must stay unique after every later edit; D21 now includes its `if` line, and D21b covers the new block.
**What only a hand can verify, in order:** right-click a board in the Library rail → "Khoá bảng này…" → read the sheet → lock;
the cards turn into lock placeholders; click one → Touch ID → the card renders; **cancel** the sheet on another card and read
the notice (expected: none); leave the page and come back → placeholders again; a locked clip on the notch/shelf opens the
Library; Cài đặt Clipboard ▸ the locked board's "Xóa" is disabled; "Gỡ khoá (giải mã lại)" → one prompt → plain cards.

## N1 (2026-10-13) — one fixed notch window, after measuring OneNotch 2.0.5

The OneNotch pass (`docs/ONENOTCH_EVIDENCE_2026-10-13.md`, `docs/ONENOTCH_WEB_RESEARCH_2026-10-13.md`) was done by
**measuring the installed bundle**, never by reading its code: Info.plist, entitlements, 2 471 UI strings in 14 tables,
373 class names, 68 defaults, SQLite schema, CGWindowList, AX, CPU, plus the author's own `Resources/CLAUDE.md` shipped
inside the bundle. The web agent found **no public repo** — the in-app "open-source" string is unverifiable, so OneNotch
stays closed-source for licensing purposes. Facts that changed the plan are in REDESIGN_PLAN §3e.

**The architectural difference that mattered:** OneNotch's notch window is **one fixed 700×745 pt frame** (polled
40 × 0.5 s, not a pixel of change) at level `mainMenu + 3`; the content animates inside it. XFinder's `render()` resized
the panel per state (grow / shrink-after-0.32 s / union) — the mechanism behind the D0c "giật". N1 copies the mechanism,
not the picture:

* `NotchSurfaceLayout.panelSize / panelFrame`: the union of every notch-anchored state (clipboard hub + 2 × fillet wide,
  deepest drop tall), centred on the notch, glued to the top edge, never wider than the screen. One `setFrame` on first
  show / anchor change / screen change; state changes never touch the window. A pointer tray gets the same size,
  top-centred on its target, and keeps the position the user dragged it to.
* **Hit-tests and the drop target must use the DRAWN shape, never the window.** `drawnFrame` (top-centred in the window,
  computed from the rendered state's size) replaces `panel.frame` in `tick()` and the swipe band; the `.onDrop` moved from
  the GeometryReader root onto the clipped shape, or a file released on the transparent remainder would land on the tray.
* **Precondition, measured before shipping:** clicks on the alpha-0 part of a non-opaque borderless panel must fall
  through to the window below, or a 776×254 invisible rectangle blocks every title bar under the notch. Probe:
  `NSWindow.windowNumber(at:belowWindowWithWindowNumber:)` (the window server's own hit-test, no synthetic input) on a
  600×300 clear panel with a 100×100 opaque square, for both a plain `NSView` and an `NSHostingView`. **First run was
  INVALID**: both points resolved to WindowServer's "Display 1 Shield" — the display was asleep (`CGDisplayIsAsleep`,
  loginwindow shields at layers 2000/2001). A probe must assert that its opaque point hits its own panel before its
  transparent result means anything. The watcher re-runs it when the display wakes; the build is **not installed** until
  it reads PASS (result: see the N1 commit message).
* Tests: `testEveryNotchAnchoredStateFitsInsideTheFixedPanel` (both screens, 6 states × items × track × timer, with a
  "the walk must draw > 20 states" guard) + `testTheFixedPanelIsExactlyTheUnionOfTheStates`; mutations M27 (fillets
  forgotten → 17 red) / M28 (panel shallower than the deepest hub → 33 red); notch suite **28/28 RED**, 740 tests / 0.

**Measurement traps from this pass:** a copied `/bin/sleep` named `XFinder` dies on exec (platform-binary copy), so
`pgrep -x XFinder` never saw it and a hook test read "returns at once" as a pass — compile a one-line Swift binary instead;
`printf '%s\n'` inside a JSON fixture turns `\n` into a real newline byte; OneNotch's "idle" CPU of 4.9 % was measured with
its AI page rendering MY Claude Code session — say what was on screen when you quote a number.

## N3 (2026-10-13) — Claude Code sessions on the notch, built from OneNotch's measured mechanism

Job: *"Claude Code is running in a terminal; at the notch I want to see what it is doing, whether it waits for me,
and answer a permission prompt without going back to the terminal."* The mechanism is the one measured on OneNotch
(evidence §7) and then checked against the official hooks reference — **files and a hook command, no private API, no
permission**:

| Piece | File | What it holds |
|:--|:--|:--|
| hook | `Resources/Agents/xfinder-claude-hook.zsh` (bundled, copied to `~/Library/Application Support/XFinder/Agents/claude/bin/` on install) | appends one JSON line per event (`received_at`, `request_id`, `env` with the hook's `$PPID` = the claude process + tty/terminal ids, `payload` minus `tool_response`); on `PermissionRequest` blocks on `decisions/<session>-<request>.json` with zsh `zselect` (no forks), exits when XFinder is gone |
| pure | `Core/Agents/AgentEvents.swift` — parser + `AgentSessionRules` (status machine, liveness/staleness, display order, status keys) · `Core/Agents/AgentHookInstaller.swift` — settings.json merge/remove by command path, `AgentDecision` payload | 17 tests (`AgentSessionTests`), `mutation-check-agents.sh` A1–A10 |
| live | `Core/Agents/AgentSessionMonitor.swift` | ONE reader of `agents.enabled`; `DispatchSource` on the events dir AND on today's file (appends do not change a directory), incremental tail by offset with partial-line carry, 20 s liveness timer only while a session is alive, decision writer, hook install/remove with a dated backup of settings.json |
| surface | `Page.agents` (default order `files,clipboard,nowPlaying,agents`), tab with a "needs you" badge, `agentsPage` rows with Cho phép / Từ chối / Mở terminal; settings section on Notch & Khay thả; `FeatureCatalog .agents` | |

Facts from the official reference that shaped it (claude-code-guide agent, code.claude.com/docs/en/hooks): the decision is
`hookSpecificOutput.decision.behavior = allow | deny` (PreToolUse uses a DIFFERENT field, `permissionDecision`);
**exit code 2 is ignored for PermissionRequest** — only the JSON decides; no output ⇒ Claude Code's normal prompt;
`statusMessage` is a real field; `timeout` is seconds (default 600, so the 3600 s on PermissionRequest is deliberate);
a `Notification` of type `permission_prompt` fires only ~6 s into an unanswered prompt and cannot answer it; hook
events number 30+ — the installer subscribes to 13. **Unconfirmed in the docs** (relied on by OneNotch, verified here
only by the hook's own `ps -o tty= -p $PPID`): that the hook's parent is the `claude` process; `CLAUDE_CODE_ENTRYPOINT`
is undocumented — recorded only if present.

Rules that follow from reading the measured design, not the picture:
* **Installing the hook is a button, never a switch** — it edits `~/.claude/settings.json`. Our entries are found by the
  command path, appended beside other tools' (OneNotch's stay), removed by path only; a backup is written first.
* **An answered request flips the row at once** (`answered` set) — the next hook event may be seconds away.
* **A dead `claude` ends the session whatever the log says** (`kill(pid, 0)`); with no pid, 15 min of silence does.
* The hook's wait must fork nothing: a `sleep 0.25` loop is ~14 000 processes per unanswered hour (OneNotch's note,
  reproduced in reasoning); `zselect -t 25` sleeps in-process. Measured in the scratchpad harness: logs a 700 KB
  `tool_response` as a 526-byte line, returns at once with no XFinder process, blocks with one and relays the decision
  verbatim, exits 5 s after that process dies, 0 `sleep` processes.
* Not built on purpose: quota/cost (Claude Code's 5-hour and weekly windows are not derivable from local files
  honestly), Codex (same shape, later), focusing the exact terminal tab (needs per-terminal scripting; the button says
  "mở terminal" and activates the app the hook recorded).

**Not verified live yet** (display asleep for the whole pass): the page through the installed app, the e2e harness
(`scratchpad/n3/e2e-agents.sh`: inject hook-shaped lines, read the page via AX, press Cho phép, check the decision
file), and a real Claude Code session with the hook installed — that last one only after the user presses the button.

## N2 (2026-10-13) — "Rê chuột vào notch mở": one picker, one key, decided by a pure enum

OneNotch's `notchOpenBehavior` ("every hover opens the same page" / "activity") measured in its defaults became
`notch.hoverOpens` (`peek` · `activity` · `clipboard` · `files` · `nowPlaying` · `agents` · `lastPage`), ONE reader in
`NotchSurfaceController`, decided by `Core/Notch/NotchHoverOpen.swift` (pure, symlinked, 10 tests incl. the machine
walk). It **replaces** D1's `notch.clipboardOnHover` Bool: the old switch meant "clipboard when nothing else to show"
(files and a track still peeked), so a user who had it on is migrated to **By activity** — not to a fixed Clipboard,
which would now open the clipboard over held files. The migration is one `defaults` write in `applySettings()` when
the new key is absent and the old one is `true`; the old key is never read again.

Semantics worth stating because two old tests encoded the opposite: a FIXED choice is that page whatever is held or
playing (the picker's label promises that page); `.files` with nothing held peeks (the Part 3c empty-tray rule);
`.activity` ranks agent-waiting → track → files → clipboard and **skips hidden pages** (a hidden tab is never opened
by a hover — mutation M29). `Settings` grew `agentNeedsYou`, `lastPage`, `shownPages`; the machine still never opens a
page the user removed from `notch.pages`.

Gate changes: `FeatureKeyDefaultsTests` row for the String key; M19 re-anchored to the new line, M29 (activity ignores
a waiting agent) and M30 (hover opens an EMPTY tray) added; 766 tests / 0. Not measured live (display asleep).

## N6 (2026-10-13) — three more file actions at the notch: Sang PDF, OCR, Thu nhỏ (press-and-hold presets)

OneNotch's tray row (video frame: AirDrop · Resize · Convert · Compress · Remove BG · OCR · To PDF, "Drop to apply ·
Hold for options") re-derived for XFinder's held-files hub (B2d had ZIP · Gộp PDF · Sang JPEG/PNG · Tách nền · AirDrop):

* `Core/Image/PDFAssembler.swift` — every held image becomes a page, every held PDF contributes its pages, in the
  order held, into ONE PDF beside the first input (keep-both; never onto a PDF input). Images are decoded through
  ImageIO with the EXIF transform at full size — `NSImage(contentsOf:)` alone keeps a rotated phone photo sideways
  (B2c). `NotchActions.toPDF` is offered for a single PDF too (a copy), unlike `mergePDFs` which needs two.
* `Core/Image/ImageTextOCR.swift` — Vision through the SAME `ScreenTextRecognizer.recognize` as screen OCR, lines
  joined top→bottom then left→right (Vision boxes are bottom-left normalised: larger `maxY` is higher). Each image's
  text is written as `<stem>.txt` beside it AND all of it goes on the clipboard (the monitor records a clip); the
  result line says the one measured number — characters. The first call per process waits for `aned`.
* `NotchActions.resize(maxPixels:)` — the tile's click runs `defaultResize` (1 600 px); a `Menu(primaryAction:)` lists
  the five `ImageEngine.resizePresets` on press-and-hold. That control is exactly "Drop to apply · Hold for options".
* Tests: `FileActionTests` (8: a 4-page PDF from 2 PNGs + a 2-page PDF with the `.txt` ignored and page widths in
  order; keep-both twice; OCR reads `XFINDER 2026` rendered with Core Text, refuses a blank image; line order; names;
  the action rules). `NotchTaskTests` expectations extended. Mutation M31 (OCR offered with nothing held).

**Trap:** `"Thu nhỏ"` already meant Quick Look's **Zoom out** in the store — the idempotent entry script silently
UPDATED it to "Shrink" (`Added 10, updated 1`). "updated N" in that script's output is a diff to read, not a success
line: a new feature must own new keys (`Thu nhỏ ảnh`). Also `" px"` is identical in both languages and the coverage
gate refuses it — build such units outside `L10n.t`.

## N4 (2026-10-13) — Lịch trên notch ("Glance"), and a reference frame that was wrong

OneNotch's calendar page (onboarding video: weekday · lunar date · nine-day strip with dots · "Good afternoon. Up next:
Shipment · Lin at 15:00") re-derived: `Core/Calendar/GlanceRules.swift` (pure, symlinked, 8 tests — strip, day events,
up-next = in progress beats upcoming and never all-day, meeting links on the hosts OneNotch's own strings list with a
dot-boundary suffix match, countdown units, greeting, dots) + `VietnameseLunar` in the same file;
`CalendarGlanceMonitor.swift` (EventKit, ONE reader of `notch.calendar` / `notch.calendar.hideAllDay`): a ±5-day
fetch on `EKEventStoreChanged` plus a 60 s refetch that exists ONLY while the page is on screen; reminders with a due
time listed beside events. Access is asked from the page's button and the hub's Permissions tab (`AppPermission`
gained `.calendars` / `.reminders`, `.fullAccess` only — write-only is not reading), never from the switch. Info.plist
carries both usage strings. Page `.calendar` (tab "Lịch", default order last), settings section on Notch & Khay thả,
catalog row with `.timerWhileActive`.

**The lunar date: ICU's `.chinese` calendar is NOT the Vietnamese calendar.** It is computed on Beijing time (UTC+8)
whatever `Calendar.timeZone` says; Vietnam reckons months at UTC+7, and the two calendars disagree by a day when a new
moon falls in the last hour of the Vietnamese day — and by a whole month in 1985 (Tết: 21 Jan in Vietnam, 20 Feb in
China). `VietnameseLunar.fromSolar(day:month:year:timeZone:)` is the standard astronomical algorithm (Hồ Ngọc Đức /
Meeus), pinned to Tết 2024/2025/2026, Trung thu 2026 (25 Sep), the 2025 leap 6th month, and the 1985 divergence in
BOTH time zones. **OneNotch's onboarding frame reads "16/8 Lunar" for Sunday 27 Sep 2026; the new moon that month is
11 Sep 10:27 ICT, so 27 Sep is 17/8** — Foundation and the algorithm agree, the marketing frame is wrong. A reference
screenshot is evidence of what a page shows, not of what is true (D1's `hsl()` lesson, again).

Not verified live: EventKit access prompt and real events on the installed app (display asleep all pass); the hub
row's "Tham gia" button; the pane deep links `Privacy_Calendars` / `Privacy_Reminders` (named by the documented pattern,
not measured).

## N8 (2026-10-13) — Now Playing seek, shuffle, repeat: measured numbering, not a header's folklore

OneNotch's binary calls `MRMediaRemoteSetElapsedTime`, `MRMediaRemoteSetShuffleMode`, `MRMediaRemoteSetRepeatMode`
(class-name / symbol evidence). Measured here with the B6 technique — a silent `MPNowPlayingInfoCenter` publisher that
registers `changePlaybackPosition` / `changeShuffleMode` / `changeRepeatMode` handlers — from an **ad-hoc** process:

| Call | What the publisher received |
|:--|:--|
| `SetElapsedTime(123)` | `changePlaybackPosition 123.0` |
| `SetShuffleMode(1 / 2 / 3)` | `MPShuffleType` 0 off / 2 collections / 1 items |
| `SetRepeatMode(1 / 2 / 3)` | `MPRepeatType` 0 off / 1 one / 2 all |
| `SendCommand(45, [kMRMediaRemoteOptionPlaybackPosition: 77])` | a bogus `shuffle 1000` — wrong option key; not used |

So `NowPlaying.ShuffleMode` / `RepeatMode` are 1-based with MediaRemote's own numbering (mutation M32 renumbers them
0-based like MPShuffleType and goes red). The player's CURRENT shuffle/repeat state is **not** among the eight keys
the helper reads (B6), so the hub offers the three modes as menus and never claims to show which is on; the progress
bar is a `Slider` that seeks on release and keeps the dragged position until the helper's next notification. Measured
with the probe publisher only — a real player (Music, Spotify) is still unverified, like all of B6.

### Process note (2026-10-13): one commit for N1–N4/N6, and why

The rule is one topic per commit. This wave shipped as ONE commit (`807aaa6`) because the five items share one
surface — `NotchSurfaceController`, `NotchSurfaceView`, `DropTrayDetailView`, the machine, the pbxproj and one L10n
entry script — and splitting them afterwards would have meant re-deriving per-topic versions of six files by replaying
patch strings, i.e. shipping intermediate trees that never compiled as such. Each item WAS built and tested on its own
before the next began (N1 → N3 → N2 → N6 → N4), so the sequence was bisectable while it happened; only the commit
boundary is coarse. The commit message carries a section per item. **Next time: commit each item as soon as its gates are
green**, even with live measurement pending — note "not measured live" in the message and follow up, instead of holding
five items for one measurement.

### N5 probe (2026-10-13) — Translation framework DOES answer a non-Apple process; B5's "hung" was a short timeout

`LanguageAvailability.status(from: en, to: vi)` from a CLI: **`installed` after 8.48 s**, `supportedLanguages` 47 — identical
for the ad-hoc binary and the `XFinder Dev`-signed one; translationd logged no trust refusal this time. B5 recorded two
probes that "hung": they were killed before translationd's ~8.5 s first answer. So availability is readable; what is NOT
available from a CLI is the translation itself — `TranslationSession` exists only inside SwiftUI's `.translationTask` /
`.translationPresentation` (macOS 15+), so N5 must host the badge's translation in a SwiftUI panel, gated by
`#available(macOS 15, *)` with the app's 14.0 target. Not built yet.

## N7 (2026-10-13) — What's New per version; the "tour" already existed and I nearly duplicated it

OneNotch ships four onboarding videos and a What's New page keyed on `lastSeenWhatsNewVersion`. I wrote a 4-step tour
window — and the build failed with `invalid redeclaration of 'OnboardingView'`: **XFinder already had a first-run setup
window** (`Views/OnboardingView.swift`, `Core/Onboarding.swift`, commit c436b80: choose a preset, ask only for the
permissions it needs; "Chạy lại thiết lập" in the Features hub). The plan's "Chưa làm: onboarding" line was stale.
**Grep for the feature before building it** — a stale plan line is not evidence of absence.

What N7 is, after that: `Core/Onboarding/WhatsNewRules.swift` (pure, symlinked, 2 tests) — notes per version matched on
the first two components (a patch release carries its minor's story), shown **once per version to existing users only**
(completed setup or an `xfinder.db` on disk); a fresh install is on setup and gets the current version recorded as
seen. `Views/WhatsNewWindow.swift`: its own window, not a sheet (an open SwiftUI sheet blocks `NSApp.terminate` —
measured for the setup window). One button on Tổng quan reopens it. Notes name their page by
`SidebarDestination.rawValue` as a String so the pure file stays model-free; the test parses the model's `case` lines
(> 20, or the parse rotted) to prove every raw value is a page.

**Traps, both from the idempotent L10n entry script, both the same shape:** (1) `updated 1` — "Mở trang " existed as
"Open page " and was silently rewritten (restored); (2) deleting "my" keys afterwards removed two that predated this
session ("Chào mừng đến XFinder", "Bỏ qua" — the setup window's own strings) — `git diff` on the store showed 8 `-`
lines where 0 were expected; restored from HEAD and put back at their original positions (appending them made the
diff a move, not a no-op). The
store is shared state: diff it against HEAD after every script run, and never remove a key without checking it was yours.

## N5a (2026-10-13) — Dịch vùng chọn: ⇧⌘G, Accessibility read, Apple's popover

OneNotch's Smart Selection shows a badge on every selection (per-app AX observers) and translates in place. N5a ships
the hotkey half: `TranslateSelectionController` registers ⇧⌘G with Carbon (its own signature `'XFtr'`, id 2, so ⌘K's
handler and this one ignore each other), reads the focused element's `AXSelectedText` through the Voice module's
`VoiceScreenContext.selectedText()` BEFORE any panel takes focus, decides with the pure `TranslateSelectionRules`
(`nothingSelected` / `tooShort` / `tooLong` (5 000) / `translate`), and shows a `SurfacePanel(.interactive)` at the
Spotlight position hosting `TranslateSelectionView`. On macOS 15+ the view's "Dịch" button opens Apple's
`.translationPresentation(isPresented:text:replacementAction:)`; the popover's "Replace" hands the translation back
(shown + "Sao chép bản dịch"). Below 15 the panel says so. ONE reader of `translate.hotkeyEnabled` (default off: it is
a global hotkey), re-armed on `didBecomeActive` with the other AX-gated controllers; catalog row with `.accessibility`;
the switch lives on the Voice page (text tools in other apps) — the hub toggles it too.

Facts: availability needs no signature (probe above: `installed` in 8.5 s, ad-hoc and signed alike); the translation
itself exists only inside SwiftUI's presentation API, so a CLI cannot translate — a view can. **Not measured live**: the
hotkey through Carbon in the installed app, an AX read on a real selection, the popover (needs macOS 15+ and a hand).
The badge-on-selection half stays unbuilt — it needs `AXObserver` per frontmost app on `kAXSelectedTextChangedNotification`.

## D4b (2026-10-13) — link previews, opt-in, the one network action a copy may trigger

The Phase 1 pass deleted a `clipboard.linkPreviews` switch because nothing read it and because fetching every URL
breaks the local-only promise. It is back as an **opt-in with a reader**: `LinkPreviewFetcher` (ONE reader, default
off) fetches one link at a time through Apple's `LPMetadataProvider` (measured from a CLI: apple.com 1.1 s, github 1.4 s,
example.com 0.2 s, a dead host fails in 0.2 s), downscales the representative image through ImageIO to ≤ 480 px into
`Clipboard/LinkPreviews/<sha256>.png`, and patches the record's metadata (`linkTitle` / `linkImage` / `linkFetched`)
through `ClipboardManager.applyLinkPreview` — `metadata` is `let` on the record, so the writer rebuilds it like
`togglePin` does (`patching(_:metadata:)`). The shelf card, the notch card and the Library (same card) show the title
and image when present. `LinkPreviewRules` (pure, 5 tests, mutation D32): only public http(s) hosts — never localhost,
`.local`/`.internal`/`.invalid`, private IPv4 blocks, IPv6 literals or URLs with credentials — a preview must not make
XFinder knock on a private service; a failed fetch is recorded and retried after a day, a title refreshed after 30; the
switch's own copy says what is sent and that it is the only time the clipboard touches the network. Turning it on
backfills the newest 50 link clips; off cancels the queue.

Traps: macOS 27's `URL(string: "not a url at all")` returns a percent-encoded relative URL — `url(of:)` demands a
scheme and a host; and the Phase 1 test asserting the key was "bound nowhere" was retired with its reason in place.
Not measured live: the fetch through the installed app (only the CLI probe), the cards with a real preview.

### Swift 6 traps met in D4b (2026-10-13)

* A `static var` on a `@MainActor` class is main-actor-isolated even when it only builds a URL; a `nonisolated static
  func` cannot read it. Mark the computed constant `nonisolated static var`.
* `sending 'prov' risks causing data races`: an `NSItemProvider` (non-Sendable) handed from a main-actor `Task` to a
  `nonisolated static func … async`. The fix is not `@unchecked Sendable` — keep the async wrapper on the main actor
  (drop `nonisolated`); the continuation may be resumed from the provider's callback thread, that is fine.

### State at the end of the OneNotch pass (2026-10-13 06:55) — read this before touching the notch again

Committed locally, NOT pushed (the user pushes): `807aaa6` N1–N4/N6 · `d6e8fc9` N8 · `eeb52e9` N7 · `0d1217d` N5a ·
`04e0617` D4b · the plan docs commit. Gates on the final tree: build arm64 ✅ · 791 tests / 0 · notch mutations 31/31 ·
agents 10/10 · notch-clipboard 33/33 · L10n store 2 157, six gates 0 · UI tokens 0.

**Nothing from this pass is installed in /Applications yet.** The display slept through the whole pass, so the one
gate that decides whether N1 may ship — clicks falling through the transparent remainder of the fixed panel — is
unmeasured. `scratchpad/live/measure-all.sh` runs the whole live pass in the safe order (probe → build → install →
runtime L10n → N1 e2e → N3 e2e → AX → CPU) and stops at the first gate that fails; a 4-hour watcher
(`passthrough-result.txt`) runs the probe by itself when the display wakes. Only after that: install, measure, and a
follow-up commit with the numbers. If the probe says BLOCKS CLICKS, N1's fix is `ignoresMouseEvents` toggling per
hit-test or a window per state — do not install the fixed panel over the user's title bars on hope.

## N1b (2026-10-13 07:14–07:30) — the live pass: one real blocker found, two false results caught

**`ignoresMouseEvents` has THREE states, and the Bool API shows two.** The watcher measured the pass-through gate when
the display woke: BLOCKS CLICKS. Matrix (`scratchpad/onenotch/probe2/ignores.swift`, `NSWindow.windowNumber(at:)`):
never assigned ⇒ the alpha-0 remainder falls through and only drawn pixels hit; `= false` assigned (before or after
order-front, or `true` then `false`) ⇒ the WHOLE frame hits; the property reads `false` both times. `SurfacePanel(.notch)`
wrote `false` "for clarity". Removed; `SurfacePanelHitTestTests` reads the source (comments stripped) and fails on any
write in the `.notch` arm or `NotchSurfaceController` (mutation proven). OneNotch's own 700×745 panel, same probe: notch
body hits OneNotch, its transparent area hits the window below. Commit `77838c6`, installed 07:25. **Every other
`ignoresMouseEvents = false` in the app (`.interactive`, DockPreview, EdgeNotes, DockLayer) makes its whole frame
clickable — fine for opaque panels, wrong for any panel larger than what it draws.**

Two results in `measure-all.sh` were false, and both would have read as green:
* **N1 e2e "transparent remainder passes": FALSE PASS.** The hit probe had no `NSApplication.shared`, so
  `windowNumber(at:)` had no window-server connection and answered 0 for BOTH points ("none"); the script tested
  `clear != XFinder` and printed PASS. Now a no-hit is INVALID, and the clear result only counts when the drawn point
  hit XFinder. **A probe needs a positive control in the same run, or "nothing found" passes.**
* **N3 e2e "session row": suspect PASS, then 4 FAILs.** The harness wrote `agents.enabled` with `defaults write` and
  opened the settings URL — but `applySettings()` runs only from the page's `.onChange` or at launch, so the Agents tab
  never existed (the hub showed Tray/Clipboard/Now Playing). The "row" PASS matched words elsewhere in the window.
  **Writing a key from outside the app does not apply it** — relaunch, or press the real switch toward the wanted state.

Also from the pass, not yet explained: idle CPU **3.89 s / 60 s** (6.5 %) right after the AX dumps — not a clean idle
window (an AX client keeps SwiftUI's accessibility tree live) — and `vmmap` **peak footprint 707 MB** (current 93 MB)
somewhere between launch and the e2e runs. Both need a fresh launch, no probes, then the hub opened by hand.
The user quit XFinder from the menu bar at 07:29:41 (`NSMenuBarNavigateAction` → `terminate:`), not a crash.

**N1b, closing (07:35–07:55).** Positive control for the pass-through, on a REPLICA of the notch window (776×254 at the
top centre, `.statusBar`, `sharingType = .none`, `ignoresMouseEvents` never written, SwiftUI black 464×254 body): body point →
the panel; clear point and both collapsed points → the window below. `sharingType = .none` does NOT hide a window from
`windowNumber(at:)` (measured both ways), so the B7 default does not blind the probe. On the installed app only the collapsed
check ran (2 points → the window below); the hub-open run had no positive control because the hub was not open, and the user
quit XFinder twice (07:29:41, 07:34:33). **My `open xfinder://clipboard` 7 s after the second quit RELAUNCHED the app** —
a custom URL scheme launches its app; quit it again and stopped. Before sending a URL to an app, check it is running.
`rea` on OneNotch: overview only (counts in the evidence appendix); Hopper path via `HOPPER_LAUNCHER_PATH`, and the 120 s
hard-coded startup timeout needs a scratchpad copy with a longer one — never patch the user's installed tool.

## Live pass closed (2026-10-13 07:56–08:25) — N1 + N3 green, and the Library's 886 MB found and fixed

**e2e on the installed app (user had XFinder open, display awake):**

| Check | Result |
|:--|:--|
| idle CPU, fresh launch, no probes | **0.03 s / 60 s**, footprint 31 MB — the earlier 3.89 s/60 s was the AX-dump residue |
| N1 collapsed: title-bar clicks under the notch | reach the window below (Claude) — 2/2 points |
| N1 frame across collapsed / clipboard hub / tray | identical 476,0 776×254 |
| N1 hub open: drawn point / transparent point | **XFinder layer 25** (positive control) / the window below |
| N3 (relaunch to apply `agents.enabled`, dumps scoped to the notch panel, tab precondition) | **5/5**: row "XFinder · Running Read", permission card, decision file `{"behavior":"allow"}`, card gone, SessionEnd → ended; `agents.enabled` restored to absent; the 8 e2e lines removed from the user's events file (it held nothing else) |

**The 707/886 MB was the Clipboard Library page, not the e2e.** Replaying measure-all step by step: notch hub +12 MB,
settings page +28 MB, AX dumps +1 MB each — and **opening the Library, leaving, returning: 646 MB now / 886 MB peak**,
staying there. `vmmap`: 320 MB of it was `Malloc Large (empty)` — freed blocks whose pages stay dirty. Stacks from
`open -a … --env MallocStackLogging=full` + `malloc_history <pid> -highWaterMark -allBySize` (lite mode — the default for
`MallocStackLogging=1` — refuses `-highWaterMark`): `ClipboardAppColor.extractDominantColor` → `tiffRepresentation` of
the app icon (3 × 74 MB live at peak; 109–605 ms main thread per app) and `resolveCandidateImage` → `NSImage(contentsOfFile:)`
on a copied 42 008 051-byte .mp4, twice per render, plus 67 MB for AppKit's SVG sniff. Fixed in `9855a97` (32×32 draw +
pure `ClipPreviewRules.dominantColor`; decode only image extensions, always via the ImageIO cache) and `142e334` (PDFs
keep their page-one preview via `ClipPreviewRules.pdfFirstPage` — my image-only rule had silently dropped it; found by
counting the extensions in the real history before trusting the rule). After: **74 MB now / 78.5 MB peak**, idle 0.01 s/60 s
with the Library open. 802 tests / 0; mutations P1–P6 red.

Rules from this pass:
* **A custom URL scheme launches its app.** `open xfinder://…` 7 s after the user quit XFinder relaunched it. Check
  `pgrep -x XFinder` before sending a URL; never "probe" an app the user just closed.
* **"across K files" in `audit-ui-tokens.py` counts files WITH problems**, not files scanned (it scans all 33 pages).
  Read a gate's summary line in its source before calling it blind.
* **Accent colours are not reproducible cheaply.** The old value came from a sparse 16×16 nearest grid on whatever
  representation the TIFF listed first; no 32–1024 px draw in sRGB or P3 matched it (Safari Δ 0.23 at every size).
  Chrome/Finder/Safari kept their colour, Antigravity moved yellow → orange. Say so rather than chase it.
* **Never put an unverified fact in a commit message.** "8 extension-less records, none an image" was written before
  looking: they are 5 paths — 2 folders, 1 text file, 2 gone. Amended (unpushed) to say exactly that.
* `rea` wants `HOPPER_LAUNCHER_PATH` when Hopper lives in `~/Applications`, and its 120 s startup timeout is
  hard-coded — run a scratchpad copy with a longer one; never patch the user's install.
**Review of the fix (`9f212af`, 2026-10-13 08:30):** 4 read-only lenses + 2 refuters each (10 agents): 1 confirmed, 2 split,
0 refuted, preview-regression lens empty. Confirmed = the same bug class in the ⌘-Tab switcher (`WindowPreviewComponents`:
icon lookup + render ×3 per card per render, never routed through `ClipboardAppIcon`). Split = the accent FALLBACK cached
by bundle id although it depends on content type (pre-existing), and `NotchTextCache` not caching misses. All three fixed;
not unit-testable; ⌘-Tab unmeasured live (feature off here, display asleep). **Rule: when one surface gets a cache for
an AppKit lookup, grep every other surface for the same two calls** — `urlForApplication` + `icon(forFile:)` lived on in
a file nobody revisited.

## Wave E — Smart Selection (2026-10-13 09:30–11:05): E0–E5 + E7 live 13/13

Commits `2ce9036` (E0) · `72f83a2` (E1–E3) · `af9e5c8` (E4–E5) · the E7 commit (retry fix + e2e). Plan §3f has the design;
what follows is what the measurements taught.

* **`NSExpression(format:)` aborts the process on malformed input** (`1+`, `(1+2`, `1..2+3` → `libc++abi: terminating due to
  uncaught exception of type NSException`) and Swift cannot catch it. ⌘K's `Calculator` handed it every query matching its
  regex after the 0.2 s debounce, so typing `1+` killed XFinder. `SafeArithmetic` (recursive descent, returns a number or a
  Failure, refuses ÷0 and non-finite) replaces it; `SafeArithmeticTests` greps the whole app for `NSExpression(format:` (walk
  must see > 100 files). **Any Foundation API that takes a format string from user text is a crash surface — grep for them.**
* **Foundation's `Measurement` rounds coefficients to 6 significant figures** (km/h 0.277778, lb 0.453592, oz 0.0283495,
  gal 3.78541, fl oz 0.0295735): invisible at "5 km", wrong on screen at large values (1 000 000 gal → 3,785,410 l). Unit
  conversion uses exact definitions. A test whose accuracy (1e-6) exceeds the error it should catch (3.7e-7) stayed GREEN
  under mutation — set accuracies below the error, and add a value large enough for the error to reach the display.
* **`TimeZone(abbreviation:)` maps by region and follows DST**: `EST` → New York at UTC−4 in October (EST is −5 by
  definition); `CST` → Chicago (also China Standard Time); `IST` → Kolkata (also Israel/Ireland). Own table: fixed
  abbreviations keep their definition with a note when the region disagrees; generic ones (ET/PT) follow the region;
  ambiguous ones are refused. `NSDataDetector` reads Vietnamese dates (`15 tháng 10 năm 2026`, `thứ Sáu 9 giờ`, `15/10/2026`
  = 15 Oct) and gives a date-only match **12:00** — "has a time" must be read from the words, or every date becomes a noon event.
* **AX observer registration can fail with `kAXErrorCannotComplete` (-25204) on an app that is still launching** — measured on
  the installed app under a 0.3 s messaging timeout. The first watcher remembered the pid anyway, so the feature stayed silent in
  that app until the next app switch, and the first e2e read 2/7. Retry only -25204 (0.5/1.5/3 s while the app stays frontmost),
  never remember a failed attach; measured after: attempt 0 = −25204, attempt 1 (532 ms later) = 0. **A registration's return
  code is a measurement — log it.** The `SmartSelect` log category carries kinds, lengths and bundle ids only, never text.
* **Negative e2e checks need a positive control in the same run.** In the 2/7 run, "keyboard selection shows no badge" and
  "excluded app shows no badge" PASSED — because nothing showed at all. The script now marks them INVALID unless at least one
  positive scenario passed.
* **The line-based L10n sweep missed 6 of 43 new strings** (4 nested inside `\( )` of an interpolated string, 2 variable-passed
  notice keys). Parse every `L10n.t("…")` in the new files instead of trusting the sweep, and keep variable-passed keys in a pure
  list a test resolves (`SmartSelectionRules.NoticeKey`). The new entry script is ADD-ONLY: it refuses to rewrite an existing key
  (prints CONFLICT, writes nothing) — the N6/N7 silent-rewrite trap cannot recur through it.
* E2e harness pattern that worked: a throw-away `.app` (needs a bundle id — the gate refuses apps without one) whose own text view
  sets the selection on a distributed notification; a CLI driver under the terminal's Accessibility grant posts ONE left-mouse-up at
  the current pointer position (no movement, no keys) only after ≥ 20 s of user idle; AXPress on the badge and the Close button; the
  panel read through `probe-ax-dump`. Cleanup restores every key, unregisters the harness from LaunchServices, and quits XFinder if
  it was not running before.
* **A GREEN mutation can be an EQUIVALENT mutant, and then the mutation is the bug, not the test.** E10 ("-25204 retried
  without a limit") first clamped the array index with `min(...)` — but the `guard … attempt < count` above it already
  returned nil at attempt 3, so the mutant changed no behaviour and stayed GREEN. Rewritten to drop the bound from the guard
  AND clamp (so it retries forever rather than trapping, which would read as NORESULT); now RED at the "gives up after three
  retries" assertion. Before "fixing" a test for a GREEN mutant, ask whether the mutant can change any output at all.
* Still unmeasured: Safari's text-marker fallback, a real Calendar write, the Translate panel, a real selection in Chromium/Electron.

## E6 (2026-10-13) — currency on the Smart Selection badge: the plan's source could not do the job

Plan §3f said "ECB daily XML". **Measured first: the ECB feed quotes 29 currencies and not VND**, while this Mac's
region is `en_VN` (`Locale.current.currency` = VND). An ECB-only feature would have failed the one conversion its user
needs while every test stayed green. The source now follows the local currency (`CurrencyConversion.source`):
VND → **Vietcombank's public XML** (`portal.vietcombank.com.vn/Usercontrols/TVPortal.TyGia/pXML.aspx`, no key, its own
header says "For reference only. Only one request every 5 minutes!"; 20 currencies in VND per ONE unit — JPY 168.34,
KRW 20.24 — Buy/Transfer/Sell, `"-"` for unquoted, `,` thousands) at the **sell** rate (what a price in that currency
costs in đồng); a currency the ECB fixes → ECB, crossed through EUR; anything else → the page says no public source
exists, no switch. Vietcombank's JSON endpoint (`/api/exchangerates`) works too but is undocumented — not used.

* **Price parsing follows ISO minor units, not `UnitConversion`'s rule.** A single separator + three digits groups
  thousands (`1.500 €` = 1 500, `₩10,000` = 10 000) because a 2-decimal currency cannot show three decimals; unless the
  currency has three (`KWD 1.500` = 1.5 — ICU says KWD 3, JPY/KRW/VND/ISK/HUF/IDR 0, measured). `1.500 km` stays 1.5 km.
* **Ambiguous markers are refused, not guessed:** `¥` (yen AND yuan), `kr` (four crowns). `$`/`dollar`/`đô` ARE read as
  USD — refusing them would kill the common case — and the panel says "$ read as USD" so the guess is visible.
* **Network contract:** one GET of the public table, at most every 12 h (`freshFor`), never within 15 min of a failure,
  no timer: fetched when the switch is turned on (only if the watcher runs) or when an amount settles and the table is
  stale. Ephemeral session, no cookies, no selected text. Cache `~/Library/Application Support/XFinder/CurrencyRates.json`.
  A table published > 7 days ago is not shown. `smartSelect.currency` (default off) has ONE reader, `CurrencyRateStore`.
* Every currency-row state (converted / fetching / failed) has the same height, so a table arriving while the panel is
  open swaps the row in place (`SmartSelectionBadge.refreshCurrency`).
* **Two mutants were equivalent before the run, caught by asking "can this mutant change any output?":** removing `¥`
  from the ambiguous set (it was never in the symbol table either — now C7 maps ambiguous markers to a currency), and
  dropping the "not the local currency" guard (Vietcombank does not list VND and `convert` refuses same-currency — the
  bug only shows on the ECB path with NO table yet: "fetching EUR → EUR"; a test for that case was added).
* **E6 live 16/16** (2026-10-13 11:35–11:48, user away, watcher-gated): `$20 ≈ 522,200 VND`, `1,500.00 EUR ≈ 44,489,205 VND`,
  one request (`currency fetch ok source=vietcombank rates=20 bytes=2565`), no second request, `20 kr` → translate only,
  switch off → no badge. The first run read 14/14 **and hid a real bug** (E6b below) — a check that asks "is the right value
  present" passes while a stale one sits next to it.

## E6b (2026-10-13) — a reused panel kept the previous selection's value

The Smart Selection panel is built once and reused. Two selections in a row that produce the same KIND of row (`$20` then
`1.500 €`; `5 km` then `10 km`) update the row in place, and `Text(value).textSelection(.enabled)` kept its OLD string — the
AX tree held `522,200 VND` beside `44,489,205 VND`. Fixed with `.id(value)`. **Rule: in a view hosted for the app's lifetime,
a `.textSelection(.enabled)` Text whose content changes needs an identity tied to that content.** E2E rule: after a scenario,
capture the value the panel actually showed and assert it is GONE from the next panel — captured at run time, so an intraday
rate change cannot make the check pass by accident; the pre-fix dump is its positive control.

## F1 (2026-10-13) — Dọn rác thư mục, and what FileManager cannot list

"Cleaning Mode" in the old plan was measured, not guessed: MFinder's feature is **Junk Cleanup**, and its own string says it
"only matches known Finder, AppleDouble, archive, and Windows metadata. Generic temporary files are never selected. Finder
may recreate .DS_Store later." (I had assumed a keyboard-cleaning lock — wrong.) `Core/Cleanup/JunkCleanup.swift`: `.DS_Store`,
`Thumbs.db`/`ehthumbs.db`, `desktop.ini` (case-insensitive), `__MACOSX` only when everything inside is metadata, and `._x` only
with the AppleDouble header `00 05 16 07` (measured from a real `ditto --sequesterRsrc` + `unzip` file:
`00 05 16 07 00 02 00 00 "Mac OS X"`). Re-checked right before `trashItem`; nothing is deleted.

* **On macOS 27 every FileManager listing API hides REGULAR FILES named `._…`** — `contentsOfDirectory(atPath:)`,
  `contentsOfDirectory(at:)`, `enumerator(at:)`, `enumerator(atPath:)`; with or without the header, even empty. Links and
  folders named `._…` are still listed. `readdir`/`fts` list everything; `stat`, `fileExists`, `trashItem` work on them. So the
  scanner walks with `fts` (`FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV`). The first unit run had `._photo.jpg` silently missing
  and `macosxFolderBytes` returning 10 instead of 98 — "it was not even listed" read straight off the numbers.
* **I then over-generalised it and raised a false alarm**: "the B2a archive link guard walks with FileManager, so a link named
  `._settings.json` slips through". bsdtar (`tar -xf`) does create such links from a foreign tar (measured with Python
  `tarfile` and `tar --no-mac-metadata`; `ditto -x -k` does not), but the test I wrote to reproduce the bypass passed on the
  OLD code — FileManager lists links. The precise per-kind probe (file / link / folder / empty) settled it. The test stays as a
  regression guard and mutation A9 proves it can fail. **Measure the exact case before writing "bypass" in a commit.**
* Other FileManager listings in the app, checked: `ArchiveRunner` top-level `items` silently drop regular `._` files (AppleDouble
  debris, harmless); `FolderLockController`'s top-level count hides them on both sides equally; `AppLauncher` and the Library's
  Quick Look temp cleanup never see such names.
* Live: the production `JunkCleanup.swift` compiled into a CLI against the REAL Trash — 9/9, all five items moved back out of
  `~/.Trash` afterwards. Page via AX on the installed app, EN 9/9 and VI 5/5. Not measured: the Trash button through the UI.

## F2 (2026-10-13) — Gỡ ứng dụng: what an app WITHOUT grants can move, measured by an app, not a shell

Job: "remove app X and what it left in my Library — see every item first, all of it to the Trash." `Core/Uninstall/
UninstallRules.swift` (pure): exact bundle id, helpers/extensions (`<bid>.*`), group containers (`…group.<bid>`, must END in
`.<bid>`), LaunchAgents, and a folder named after the app (a guess — unticked). Another installed app whose id extends this one
(`com.google.Chrome.canary`) is never offered. Refused: Apple apps, `/System/`, XFinder itself, a running app (with a Quit
button; re-checked right before moving). Matching was checked against what six real apps left (Keka, WireGuard, Hush, Pause,
Sentinel, Fluor) — no collisions; most leftovers are in Containers / Group Containers / Application Scripts.

**Measured with a probe APP launched by LaunchServices** (ad-hoc signed, no grants — what a fresh XFinder is):

| Target | `trashItem` |
|:--|:--|
| app bundle in /Applications and ~/Applications, incl. a copy of a Developer ID hardened-runtime app (Fluor, team Q2E884V952) | OK — moving a whole bundle is not "modifying" it; App Management did not object |
| `~/Library/Application Support/<bid>`, `Caches/<bid>` | OK |
| another app's `~/Library/Containers/<bid>` | **NSCocoaErrorDomain 513** — and the same with `NSWorkspace.recycle` |

**The trap:** the very same container move run from the terminal (`mv`) SUCCEEDED. TCC judges the responsible process; a probe
run from a shell measures the shell. Any permission question about XFinder must be measured from an app bundle launched by
LaunchServices. Hence `Location.alwaysRefused` = Containers only: the page shows "Show in Finder" there instead of a checkbox
that cannot work; Group Containers / Application Scripts are tickable (unticked) because their refusal was NOT measured — each
row reports its real outcome after the attempt. First probe bug worth remembering: blocking the main thread on a semaphore
while `NSWorkspace.recycle`'s completion is delivered on the main thread deadlocks silently — spin the run loop instead.

## F3 (2026-10-13) — Thoát ứng dụng: quit when the last window closes (listed apps only)

`QuitOnCloseRules` (pure) + `QuitOnCloseController` (ONE reader of `quitOnClose.enabled` / `quitOnClose.apps`, default off and
empty): an `AXObserver` per RUNNING LISTED app only — destroyed on the app element and each window, window-created to register
new windows; a destroyed window arms ONE re-count after 1 s; quit = `NSRunningApplication.terminate()` (still asks to save).
Finder, Dock, loginwindow, SystemUIServer, Control Centre and XFinder are never quit even if listed. New `IdleCost.watchesWindows`
("Theo dõi cửa sổ app đã chọn") — an AX observer is neither "nothing at rest" nor "listens to the keyboard". New page "Thoát ứng
dụng" also hosts the hold-⌘Q switch, which used to be reachable only from the Features hub.

Measured with a two-window harness (AppKit default: closing the last window does NOT quit): destroyed arrives ~0.05 s after a
close and `kAXWindows` is already updated; the last close leaves `[]` with the app running. **A hidden app still lists its
windows but their subrole flips `AXStandardWindow` → `AXDialog`** — a subrole filter would quit a merely hidden app, so the rule
counts every window. **Minimizing could not be produced with Stage Manager on**: the AX minimize button returned success and
`NSWindow.miniaturize` was called by the app itself, yet CGWindowList still said `onscreen=true` — so "a minimized window keeps
the app" is documented by Apple, not measured here. Probe lesson: an AX action returning `.success` is not evidence it did
anything — check the effect (CGWindowList) independently.

Only `Sendable` values cross from the AX callback (pid, notification name); a new window is found by re-reading the window list
on the main actor (re-registering an element is a harmless error) — the IOBluetooth crash rule applied before it could bite.

## G (2026-10-13) — memory measured: under 30 MB both ways; and `defaults import` MERGES

Installed build, launched with `open -g` (no focus), settled 90 s: physical footprint **26.7 MB** as the user configured it (peak
30.5), **25.1 MB with all 21 feature keys off** (peak 26.6) — the old "48.4 MB" figure in the plan is stale. Malloc dirty 15.8 MB,
**44 % of the malloc zone is fragmentation** (7.4 of 17 MB); top classes: non-object 3.6 MB, Swift metadata 1.1 MB, dictionary
storage 0.5 MB, ObjC method caches 0.4 MB, CFString 0.37 MB. Idle CPU was NOT measured: the user was active in both 60 s windows
(HID idle 0 s at the end), so those numbers are not idle numbers.

**`defaults import <domain> <backup>` MERGES — it does not replace the domain.** The G script backed up the domain, wrote 21
feature keys `false` for the quiet run, then "restored" with `defaults import`: twelve keys that had been ABSENT stayed `false` —
including `clipboard.globalHotkey` and `dropTray.notchEnabled`, whose default is TRUE, so the user would have lost ⌘⇧V and the
notch. Caught by reading one key back. Fixed by deleting every key absent from the backup, then diffing the whole domain against
the backup (empty). **Rule: restore = import + delete keys the backup lacked + diff the domain; never trust `import` alone.**
* **F3 live, attempt 1 (12:32, watcher-gated): INVALID, not a verdict on F3.** 3/7 — the controller attached (`destroyed=0
  created=0`) but logged no recount, because the harness windows never closed: afterwards f3target still had all three windows
  ("new", "2", "1" — so `new` had worked while every `close`/`quit` to BOTH harness apps had not, the unlisted one included,
  which rules out the AX observer). Minutes later the same `close0` to the same process worked (3 → 2). Cause not found: not a
  locked screen (none then or now), not the poster exiting early (measured working). The e2e now counts the harness's own AX
  windows after every command and marks a step INVALID when the harness did not obey; the watcher also requires an unlocked
  session. **Rule: an e2e must verify its own stimulus happened before it judges the response.**
* **F3 live 7/7 (13:02), and the three failed runs were a zsh trap in MY harness.** In zsh an UNBRACED parameter takes
  history-style modifiers: `"$T:close0"` expanded to `com.xfinder.e2e.f3targetlose0` (`:c` = resolve as a command),
  `"$T:quit"` to `…f3targetuit` (`:q` = quote), while `"$T:new"` survived because `:n` is not a modifier — exactly the
  observed "only `new` works". Found by making the harness log every command it RECEIVED: one line, `got new`. Hypotheses
  refuted on the way, each by a measurement: XFinder running in the background, XFinder in the foreground, an active
  QuitOnClose observer, a locked screen, the poster exiting early. **Rule: in zsh scripts write `${VAR}:suffix`, never
  `$VAR:suffix`; and an e2e harness should log what it received, not only what it was told.** After the fix, with the
  harness's own log: close 1 of 2 ⇒ `recount windows=1 quit=false`; last window closed then a new one within 0.3 s ⇒ no
  recount at all (window-created cancels the pending re-count); last window ⇒ `windows=0 quit=true` and the app quit; an
  unlisted app with every window closed kept running and was never watched.
* **G idle CPU, valid window (12:57–12:58): 0.00 s / 60 s** (`ps -o time` 0:00.44 → 0:00.44), HID idle 313 s at the end,
  the user's own settings, the F3 build, launched by the probe with `open -g`.

## F4 (2026-10-13) — Chụp & chú thích, "like OneNotch"; and four agents that answered the wrong question

Owner: "cứ làm y OneNotch trước là được". OneNotch's capture is a second product folded into 2.0 (307 `Capture` +
245 `Annotate` + 77 `QuickAccess` strings). Measured from its string tables and its defaults domain `com.huyt.OneNotch`
(never its code): `floatingScreenshot.autoDismissDelay = 10`, `pauseCountdownOnHover`, `dragDropEnabled`,
`twoFingerSwipeToDismissEnabled`, `quickAccess.hideCardWhenWindowOpen`; shortcuts stored as `{"keyCode":21,"modifiers":768}`
— 768 = Carbon cmdKey|shiftKey, so ⇧⌘4 area, ⇧⌘3 full, ⇧⌘9 window, ⇧⌘2 OCR, ⇧⌘1 colour. Where "like OneNotch" contradicted
the approved brief, the default taken is a coded question (Q-F4-1…6) in `docs/PENDING_TESTS_AND_DECISIONS.md` — the file
the owner asked for as the one place for every open choice and hand test.

* `screencapture` on macOS 27 has everything a capture tool needs without an overlay of our own: `-i` (Space toggles
  window mode), `-l <windowid>` (the focused window, nothing to select — OneNotch's "active window"), `-D <n>` (one
  display), `-x` (silent), `-t png`. It writes **144 DPI** on Retina. **Never re-encode its file**: the agent's first
  version wrote a fresh PNG with no DPI, and the editor/pin window derive the Retina scale from DPI — strokes would have
  been half as thick and pins twice as large. Move the file instead. Found by reading the code, not by any gate.
* **The minimal onboarding preset is "nothing running AND nothing to grant".** It used to be derived from idle cost only;
  capture is idle at rest but needs Screen Recording, and would have landed in a preset whose promise is "no permission".
  `OnboardingTests` caught it; mutation K10 pins the new rule.
* **A gate that resolves `static let enabledKey` by NAME attributes one reader to every feature with that constant name.**
  `CaptureController` read `object(forKey: CaptureRules.enabledKey)` and FeatureCatalogTests reported it as reading
  `quitOnClose.enabled`, `alerts.enabled`… with default `true`. Readers and `@AppStorage` bindings use the literal key.
* `CaptureVocabularyL10nTests` walks every model enum and caught 5 untranslated macOS shortcut names (`nameKey`) on its
  first run — my own regex sweep had missed them. The model-vocabulary test is the gate; a sweep is a hint.
* **Subagents treat a mid-turn user message as their task.** The owner's "gom lại những thứ phân vân" arrived while the
  first build workflow was being written; all four agents answered THAT (one edited the pending-list file — correctly —
  and none wrote code), finishing in 48 s. Re-run with the prompt's first line stating the only task and what "done"
  means. A 48-second "build" of four files is itself the signal.
* `NSDraggingItem(pasteboardWriter:)` takes `url as NSURL`, not an `NSItemProvider`. A local-monitor holder cannot remove
  its monitor in `deinit` under Swift 6 — remove it in `viewDidMoveToWindow` when `window == nil`. A delegate callback
  hops with only `ObjectIdentifier(window)`; the window is looked up again on the main actor.
* Installing while the owner had quit XFinder: a copy of the install script with the launch block removed
  (`scratchpad/f4build/install-nolaunch.sh`) — never relaunch an app the owner closed.

Gates: build arm64 (8 new files in the compile list) · tests 973/0 · `mutation-check-capture.sh` 10/10 RED · L10n +70
add-only, all gates 0 · runtime L10n on the installed bundle 0 leaks. **Not exercised by hand: everything** — T-F4-1…11.
Known gap: with "Giữ lịch sử" off, a capture's file is removed at the next capture, not the moment its card closes.

## G + §3b #35 / #33 (2026-10-13) — 1.3.0 prepared; dictionary; meeting alerts

* **1.3.0** (`0e4df71`, notes `48546c5`): Info.plist 1.3.0 / build 4. The What's New notes for the OneNotch pass were keyed
  "1.2" while Info.plist said 1.2.0 — but the 1.2.0 zip predates every one of them, so they move to "1.3". `make-release.sh`
  predated B6: it now signs `Contents/Helpers/XFinderNowPlaying.dylib` with XFinder Dev, refuses a bundle without it or
  without the Claude Code hook, and verifies `--deep`. `dist/XFinder-1.3.0-arm64.zip` sha256 `177fd951…507c72`; the unzipped
  copy verifies `--deep --strict`. **Not published** — Q-RELEASE in `docs/PENDING_TESTS_AND_DECISIONS.md`.
* **Two memory numbers are two metrics.** G measured *physical footprint* 26.7 / 25.1 MB; the old "48.4 MB" was `vmmap`'s
  *dirty* figure on an older build. The changelog names the metric instead of printing "48 → 27".
* **#35 Định nghĩa** (`bd29300`): `DCSCopyTextDefinition` (CoreServices, public, on-device) returned English AND Vietnamese
  entries on this Mac in 1–73 ms, nil for non-words and for phrases the installed dictionaries lack ("xin chào"). The row
  appears only when there is an entry. The lookup is injected as a closure into `SmartSelectionRules.actions`, so tests
  never depend on this Mac's dictionaries; the summary drops the pronunciation between the first two `|`.
* **#33 nhắc họp** (`ef7c995`): `MeetingAlertRules` (in `GlanceRules.swift`). **EventKit gives every occurrence of a
  repeating event the same `eventIdentifier`** — the "already alerted" key is id + start, or alerting Monday's stand-up
  would silence every later Monday (mutation M35). ONE `Timer(fire:interval:0)` for the next alert only — a wall-clock
  timer fires late after sleep rather than never, and nothing polls. A notice with buttons needs
  `Settings.activityHoldsHover`: B4's rule "an activity yields to the hover" would turn it into a peek exactly when the
  pointer arrives to press "Tham gia" (M33).
* **L10n keys that already exist can mean something else.** `" phút trước"` = "m ago" and `"Lời nhắc"` = "Reminders" (the
  permission) — reusing either for "5 min before" / a reminder headline would have rendered wrong English with every gate
  green. Look a key up before reusing it; a new meaning gets a new key.
* **zsh again:** a `cd … && python3 - <<EOF` chain died on `_zoxide_lazy` AFTER the code commit had run, so the doc edits
  silently did not happen (caught by the stray "command not found" line). Long Python edits go in a scratch `.py` file run
  with an absolute path; shell chains that `cd` go through `/bin/sh -c`.

## Release 1.3.0 published + §3b #37 (2026-10-13)

* **v1.3.0 is public on GitHub** (owner: "đăng 1.3.0"): `main` pushed to `48546c5`, annotated tag, Release with the zip and
  `.sha256`. Verified FROM the download: checksum OK, unzipped app `--verify --deep --strict` OK, version 1.3.0.
* **#37 AI usage** (`036f72f`): Codex writes its own `rate_limits` (primary 300 min / secondary week, `used_percent`,
  `resets_at`, `plan_type`) into `~/.codex/sessions/**/*.jsonl` — most events carry `primary: null`. Claude Code writes no
  allowance figure locally; a % would need its Keychain login + Anthropic's API, which XFinder does not touch, so Claude
  shows tokens and says so. **Claude transcripts repeat one assistant message per content block: 5 882 lines = 2 256
  messages** — summing lines gave 1 536 991 output tokens in 5 h vs the real 596 818. Dedup by `message.id` + `requestId`,
  keep the largest output (A11). The production parser, compiled into a CLI on the real logs, matched an independent
  Python count exactly. Stale Codex windows (reset time passed) render as stale, never as a current %.
* Commit messages with `%`/quotes inside a `/bin/sh -c '…'` broke zsh parsing (`unmatched "`) and the WHOLE line — including
  the doc-edit script before it — never ran. Use `git commit -F <file>`.
* Left for the owner: Q-WAVE (#21 needs a system audio-capture permission prompt even to probe), Q-MULTIDISPLAY (#39, one
  display here), G3 (malloc fragmentation needs the app running; the owner had quit it).

## §3b #21 live (2026-10-13) — the per-pid tap was silent for every browser; found by probing before the live test

The owner allowed the probe and the permission prompt. Measured on macOS 27, Chrome playing YouTube:

* **A browser's own process never outputs audio.** CoreAudio process objects: Chrome (pid 66530) `IsRunningOutput = 0`;
  the sound came from `com.google.Chrome.helper` (66580, `out = 1`, parent AND responsible = 66530). Safari's audio is a
  `com.apple.WebKit.GPU` whose parent is launchd and whose responsible pid is Safari (41172 → 52320); three other WebKit.GPU
  processes on the same Mac belonged to OneNotch, AirDrop and a thumbnail extension. The c2480b3 tap on the Now Playing pid
  alone would have delivered **zero buffers** for every browser — and `SilenceWatch` (which needs buffers) would have said
  nothing, so the bars would just stay flat.
* `AudioWaveform.playerProcesses` (pure, 2 tests, mutations M42/M43): tap the player pid plus every object whose
  **responsible** pid is the player; the parent pid only when responsibility is unknown. Responsibility comes from
  `responsibility_get_pid_responsible_for_pid` (exported by libquarantine, undocumented) via `dlsym`, nil-safe.
  Live: `tap started pid=66530 objects=3`, `first signal rms=0.031 / 0.084`.
* **A per-process tap needs the permission too** (`tccd: AUTHREQ_PROMPTING service=kTCCServiceAudioCapture
  subject=com.xfinder.app`) — the question c2480b3 left open. The grant survived two reinstalls (stable `XFinder Dev`
  identity): no second prompt.
* **The one-rebuild retry counted from the REQUEST**, so it fired mid-prompt (the first start blocks ~40 s on the
  dialog). It now counts from the moment the tap runs (or from a failed start).
* **The peek follows the pointer, and every hide/show rebuilt the tap** (a TCC check + a new aggregate device): 4 rebuilds
  in 18 s. A hidden waveform keeps its tap 8 s while the same track plays (`AudioTapMonitor.linger`), one-shot, token-cancelled.
* **The page observed the meter.** `WaveformBars(levels: monitor.meter.levels)` made the whole Now Playing page re-evaluate
  30×/s; the bars view reads the meter itself now.
* **CPU, measured without AX probes (an AX client keeps SwiftUI's tree live — N1b):** Now Playing page open, waveform
  off **0.19 s / 20 s**; waveform on **0.80 s / 20 s** (tap confirmed by log). So a visible waveform costs ≈ 3 % CPU, only
  while visible and playing. An earlier "off = 1.67 s" reading was invalid: `defaults write` from outside had not reached
  the running app 1 s later, so the tap was still running — confirm a state change by log before measuring it.
* `xfinder://notch?page=<page>` opens the hub on a page (scripts, Shortcuts, probes) — added so the live test needed no
  synthetic click.

Gates: 996 tests / 0 · `mutation-check-notch.sh` **43/43 RED** · build arm64. The key `notch.nowPlaying.waveform` was
restored to absent (off) after the measurements — T-WAVE in the pending list.

## P1 (2026-10-13) — the notch in OneNotch's grammar: wings, one band, two bodies

Brief v3, approved by the owner ("ok, chạy P1 đi"): the UI/UX follows OneNotch first. Every number below was measured
on the owner's OneNotch screenshots (pixel decode of the 1400 × 1490 px = 700 × 745 pt window at 2×); nothing was read
from OneNotch's code.

| Piece | Measured | Where it lives |
|:--|:--|:--|
| Collapsed | 262 × 32 — the notch's OWN height, nothing below it; one item in each WING beside the camera; the top edge flares 6.5 pt each side, ~4 pt deep; bottom corners ≈ r 14.6 (continuous 12 used) | `NotchSurfaceLayout.wingItems / sideWidth / wingWidth`, `Metrics.wing*`, `collapsed*` |
| Band | 32 pt on every expanded page: page-dots capsule 54 × 20 (#181818, dots 5.5 pt @ 15 pt, lit #FFF / dim #525254) + search circle 24 in the left wing; toolbar capsule 63 × 22 (icons #6B6B6E, lit = current) in the right one | `XFinderTokens.Notch`, `NotchSurfaceView.band` |
| Bodies | NARROW 382 × 168 (Now Playing; tray, calendar here) and WIDE 612 × 182 (Clipboard, Agents); calendar 188 (estimated) | `Metrics.narrow* / wide* / calendarDrop`, `isWide(page)` |
| Hub flare | top edge 420 / 650 for a 382 / 612 body ⇒ 19 pt each side, ~8 pt deep; a quarter circle fits it badly (it is snappy), so `NotchShape` draws a quadratic fillet | `NotchShape(flareWidth:flareDepth:)` |
| Motion | open overshoots ~4 % (87 → 93 → 87 px), close ~130 ms with no bounce, page content cross-fades ~200 ms | `Notch.open / close / pageFade` |

* **Dots vs toolbar.** The dots are the swipeable SEQUENCE (files · clipboard · now playing · agents, in the user's
  `notch.pages` order, only those available); the toolbar holds fixed TOOLS (the calendar now; timer and AI usage in P2).
  `NotchPages.dots/toolbar`; the swipe walks the dots only. A dot has no label, so each is a button with a tooltip and a
  VoiceOver label naming its page; an Agents dot turns orange while a session waits.
* **The fixed panel shrank** from 776 × 254 to **650 × 188** (the union of every state, N1) — the transparent part of the
  window over the title bars is smaller.
* **The ✕ stays, at the notch too** — first shipped without it (OneNotch has none), and the review caught why that was
  wrong HERE: Esc is handled only by the clipboard page's key monitor (the other pages never make the panel key), so on
  four of five pages "leave or Esc" was really "leave and wait 0.8 s". A pointer tray also keeps its drag strip.
* **Clipboard:** the search field is a 24-pt circle beside the dots that opens into a field while focused or holding a
  query — it is always in the hierarchy (zero-width while closed) so ⌘F, a click, and ⌘⇧V's focus-on-open still reach it.
  The footer line became one **status pill** at the end of the chip row (`NotchClipboardRules.footer` still decides what
  and in which order). The idle key hints moved to the pill's tooltip (they are also in every context-menu item's
  title); the two states whose sentence must be READ before acting — Paste Stack (⌘V vs Dán tiếp) and no Accessibility
  (↩ only copies, D0's rule) — keep it as visible text that truncates first. A Library button opens Thư viện Clipboard. Cards are
  **162 × 112, 11 pt apart**, background tinted by the source app (`ClipboardAppColor`), a type badge (a picture's badge
  is its real dimensions) and pin / Paste Stack position on top, footer = app icon · age · one fact.
* **Now Playing:** artwork 88 with the player's icon on its corner (click = open the player), title 15 semibold, artist,
  the live bars top-right (a slashed glyph with the reason in its tooltip when the tap hears only silence), transport
  row, a full-width seek bar (#818184 track) and the times. `NowPlayingSeekBar` scrubs locally and seeks on release, so
  the 1 s ticker cannot yank it mid-drag. Empty state keeps the same frame with a placeholder and inert controls.
* **Two deliberate departures from the reference, both forced by arithmetic:** the artwork is **88**, not the measured
  "115" — 115 + the bar + the times does not fit the 136-pt body, and the measured bar (y 127.5, x from 176) would run
  through a 115-tall artwork, so that 115 must include the badge overhang; and the cards are **112**, not 123 — XFinder
  keeps its chip row (filters the reference does not have).
* **Collapsed wings:** left = a Claude Code glyph (orange while waiting) and held files; right = the track and a countdown.
  The music wing draws live bars only while the tap really hears the player, otherwise the artwork (Honesty Rule — bars are
  never animated from nothing; the tap is not started just for the collapsed wing).
* **Swipe area fix:** the hub's swipe band still reached 28 pt below the band (the old tab row), which on the clipboard hub
  swallowed the chip row's own sideways scroll. The band is the whole area now.

**A mutation harness bug found by its own GREEN result.** `M46` (calendar becomes a dot) stayed green although
`testTheCalendarIsAToolbarToolNotADot` exists: `mutation-check-notch.sh` neither ran `NotchPagesTests` (filter) nor
listed `NotchPages.swift` in `FILES` — so its restore never put the file back, and **the mutant was still on disk after
the run** (`toolbarPages = []`; caught by comparing the md5 saved before the run, restored byte-identical). Both
notch harnesses now refuse a mutation whose target is not in `FILES`. Rule: **a mutation script's target list and its
backup list must be the same list** — and save hashes of every target before a run, then diff after. `M44` (wings follow
the left side only) was a real test gap: no test had a fuller RIGHT wing; fixed.

**P1 review (3 read-only lenses):** 1 high (the missing ✕, above), VoiceOver labels on icon-only controls (the Paste Stack
cancel had lost its text label — a regression), and the exact-fit page budgets with no shared constant (now in `Metrics`,
`testPageBudgetsFillTheirBodiesExactly`, mutation M49). Also found: a swipe while the calendar tool is open fell through
`pageAfterSwipe`'s "not shown ⇒ first page" fallback and jumped to the first dot — `NotchPages.swipeTarget` returns nil
on a tool (M48). No honesty or per-render findings; no stray files from the reviewers this time.

Gates: build arm64, no warnings in the touched files · **999 tests / 0** · notch mutations **49/49 RED** · notch-clipboard
**33/33 RED**, every target byte-identical after · L10n store 2 396 (+5 via the add-only `add-notch-p1-l10n-entries.py`),
six gates 0, UI tokens 0 · runtime L10n on the installed bundle 0 leaks · installed dylib == build. **Not verified live:**
the owner had quit XFinder at 17:44, so the build is installed but not launched — T-P1a–d.

## P2 (2026-10-13) — the statusLine measurement that decides the "Claude %" (read before touching AI usage)

The AI usage tool shows Claude Code's 5-hour / 7-day used % only from Claude Code's **statusLine** stdin JSON
(`rate_limits.five_hour|seven_day.{used_percentage, resets_at (epoch seconds)}`): Claude Code writes no allowance figure
anywhere on disk, and XFinder does not touch its Keychain login or Anthropic's API. Measured on this Mac:

| Probe | Result |
|:--|:--|
| `~/.claude/settings.json` `statusLine` | already a two-level chain: Notch Crew's `notch-statusline` (installed 18:01), which saved OneNotch's `OneNotchClaudeStatusLine` as its "before" command and runs it with the same stdin |
| Notch Crew's cache `usage/claude-statusline.json` | **does not exist** — no statusLine ran since it was installed |
| OneNotch's `AI/Claude/rate-limits.json` | **does not exist**; its `sessions/*.json` were written at 05:17 and 16:55 ⇒ its statusLine DID run, and got **no `rate_limits`** (its own writer only writes the file when the object is non-empty; its comment: empty for API-key users or before the first reply) |
| Which sessions ran it | both `entrypoint: "cli"`, v2.1.296. This session (`entrypoint: "claude-desktop"`) never ran a statusLine — **the Claude desktop app's Code tab does not run status lines** |
| Docs (claude-code-guide agent) | runs at session start, after each assistant message, on mode changes, at a window's `resets_at`, optionally every `refreshInterval` s; 300 ms debounce; a new trigger CANCELS the in-flight run; output shown only on exit 0; `rate_limits` only for claude.ai Pro/Max (or a gateway) after the first API response; a window is dropped once its `resets_at` passes |
| `plutil -extract rate_limits json -o <f> -- -` | reads stdin, 2.9 ms median; exit 1 and no file when the key is absent |

The owner confirmed a **Pro/Max** login (2026-10-13), so the two empty CLI payloads were most likely renders before the
session's first reply (short sessions); the % should arrive in a terminal `claude` session after a reply — T-P2-SL. The UI
still says which condition is missing instead of drawing a ring. The script (`Resources/Agents/xfinder-claude-statusline.sh`) stores ONLY the
rate_limits object (0600, atomic `mv`, the file's mtime is the capture time; absent ⇒ the last value stays), then runs the
saved previous command with the same stdin and returns its exit code; with no previous command it prints nothing (exactly
what Claude Code showed before). A loop back to it (another tool later saving THIS script as its own "before") stops at
the second visit through `XFINDER_STATUSLINE_ACTIVE`, inherited by every child. Exercised in a fake HOME: 5/5 (cache only
rate_limits, absent keeps the last, chain passes stdin + exit code 3, loop stops, empty previous prints nothing).

## P2 (2026-10-13) — two toolbar tools (Hẹn giờ, Hạn mức AI), Agents + Calendar restyled, the statusLine installer

Built contract-first: the main session wrote the shared layer (enum cases, `NotchPages.toolbarPages/titleKey/symbol`,
`Metrics.toolDrop` + per-page budgets, the pausable `Countdown`, the controller API, the four view stubs, six pbxproj
entries, the script), then seven file-confined agents filled the pieces in parallel against `scratchpad/p2/CONTRACT.md`.

| Piece | Where | Rule it enforces |
|:--|:--|:--|
| Tools vs dots | `NotchPages.toolbarPages = [.calendar, .timer, .aiUsage]`; `swipeTarget` returns nil on a tool | a tool is a destination, never swiped to or from |
| One title, one symbol per page | `NotchPages.titleKey/symbol`, `Page: CaseIterable`, `testEveryPageTitleIsInTheStore` | the hub and the settings list had drifted copies (the tray carried two icons) |
| One height for every tool | `Metrics.toolDrop = 156` (was `calendarDrop`); AI usage is wide, the others narrow | a tool switch jumps between two widths only |
| Page budgets | `testPageBudgetsFillTheirBodiesExactly` now covers Agents 150 / AI usage, Calendar, Timer 156 | the P1 review's "exact fit with no shared constant" |
| Pausable countdown | `Countdown.paused/resumed/extended/progress`; `endsAt == nil` ⇒ paused and never "finished" | a pause button that pauses (the spec had OMIT'ed it because the old struct could not) |
| Timer draft | `notch.timer.minutes`, ONE reader `NotchSurfaceController.timerDraftMinutes`; 5-minute grid 5…120, default 25 | the idle stepper's number survives a relaunch |
| Ticks | ONE 1 s ticker, only while a countdown RUNS; the page reads `model.timerNow` — no view starts a timer, no `Date()` per render on the timer page | idle CPU 0 % |
| Usage scan | `AgentUsageMonitor.setPageOpen(agents || aiUsage)` | the 60 s scan exists only while a usage page is on screen |
| statusLine | `ClaudeStatusLine` (pure, 23 tests): install over none / another tool (its object saved VERBATIM, its `command` chained, its other keys kept) / ours; remove restores verbatim, deletes the key when there was none, refuses when settings now point elsewhere (another tool may wrap ours) | a settings.json edit is a button with a dated backup, never a switch |
| Codex tokens | `AgentUsage.parseCodexTokens/codexWindowTotals`: per-session cumulative DIFFERENCE across the window | measured 2 duplicated `token_count` events — a sum would double-count; a difference cannot |

Measured for the Codex formula (8 newest session files, 137 `token_count` events): `cached_input_tokens ≤ input_tokens` in
all 137 (a subset, so fresh input = `input − cached + cache_write`), `total_tokens == input + output` in all 137,
cumulative totals non-decreasing in all 8 files, `cache_write_input_tokens` 0 in all 274 events sampled (the `+ cache_write`
term is written down as unmeasured). Honesty on the AI usage page: "Hôm nay" is since local midnight only (a separate
`claudeToday`), a window past `resets_at` shows "đã qua giờ reset" and never its %, no ring before a quota was received,
and the page names the missing condition (statusLine not installed → a button to the settings row; installed but nothing
yet → terminal session · Pro/Max · after the first reply). Not built on purpose: a Cost tab (no price table), per-model
split, other providers, "Full screen" focus, a task name, Pomodoro arcs, "+ Add" events.

Agents that broke the rules this pass: the statusLine probe agent **refused its task** because it saw the owner's
"push rồi chạy P2" and took the push as its own responsibility — the probe was done by hand instead; agent C **built the
app** (forbidden) into a scratch derived-data dir and left `./build/XFinder.app` registered with LaunchServices under the
plugin id — unregistered and removed (and this session's seven probe `.app`s unregistered with it). Rule kept: after any
workflow, `lsregister -dump | grep path:.*XFinder` and `git status`.

**P2 review (4 lenses, 2 refuters each, 30 agents): 8 confirmed, 2 split, 3 refuted — all ten fixed.**

| Finding | What changed |
|:--|:--|
| A statusLine value that is not an object (hand-edited string, array, null) was dropped by `as? [String: Any]`; "Gỡ" then DELETED the key — the old setting gone with a success notice | `Install.previous: Any?` keeps any JSON value verbatim; on disk it is `{"statusLine": <value>}` (`encodePrevious` / `decodePrevious`, tests for string, number, array, null) |
| An unreadable saved-previous file was taken as "nothing was there" and the key deleted | `decodePrevious` returns nil for anything but the one-key wrapper; `removeStatusLine` REFUSES with `.previousUnreadable` (own notice: the dated backups are still in ~/.claude) |
| Codex rings labelled "5 giờ"/"tuần" by guess | labelled from the measured `window_minutes` (`windowLabel`: days / hours / minutes) |
| **Mine:** unwrapping `"statusLine Claude Code: "` I put a `//` comment BEFORE `.font(…).foregroundColor(…)` on the same line — the modifiers became comment text and the row rendered unstyled, with a green build | comment on its own line. **Rule: never append a comment to a line that a later edit may extend; a `//` swallows everything after it and the compiler is happy** |
| Timer/calendar keys passed as variables (`L10n.t(stateKey)`, a `help:` parameter) — invisible to every sweep | each literal is now a direct `L10n.t("…")` argument at its call site; "unwrapped" fell 629 → 619 |
| Calendar's "open" button had `.help` but no VoiceOver label; event times used the system locale | label added; times use `.dateTime.hour().minute().locale(app language)` |
| `Countdown.duration` can pass 120 min when extended near the end | not a bug — duration = elapsed + left, the maximum caps what is LEFT; documented and pinned by a test |
| **Split, but the arithmetic says real:** three tools + a separate ✕ needed 93 pt in a narrow page's 86.5-pt right wing | the ✕ is the toolbar capsule's last slot ((3+1)·19 + 6 = 82); `bandWingWidth` / `dotsCapsuleWidth` / `toolbarCapsuleWidth` are pure now and `testTheBandsCapsulesFitTheirWings` walks every page (mutations M55/M56) |
| A ternary INSIDE `L10n.t` on the calendar's access copy | the ternary sits outside, one `t()` per literal |

Harness found while adding A20/A21: `mutation-check-agents.sh`'s restore check and post-restore suite run sat BEFORE
A11–A19 (appended by later passes), so those mutations ran after the last check; and my own insertion split A19's three
lines in two. The tail is rewritten (every mutation → restore → byte compare → suite → result) and the harness now refuses
a target outside FILES, like the two notch harnesses.

Closing P2 (2026-10-13 ~21:00, commit `36adc09`, pushed): the notch harness's M47 anchor had rotted (`isWide` grew `|| page == .aiUsage`), and the run
stopped with HARNESS ERROR instead of reading green — the guard worked. Re-anchored to the full line (mutant drops `.agents`,
M54 drops `.aiUsage` from the same line): **notch 56/56 RED**, every target byte-identical, suite after restore 0 failures.
Review refuters left **seven probe files in the repo root a fourth time** (`captured.txt`, `consumer.sh`, `j1–3.json`,
`orig.txt`, `payload.json` — statusLine-script fixtures, 20:24–20:25); grep found no reference, deleted before staging.
Two more things caught at the gate rather than after: the drafted commit message said the store grew by **41**; a diff of
the store against `git show HEAD:` said **+43, 0 removed, 0 changed** — a count copied from a draft is not a measurement.
And the conversation-start git snapshot listed `NotchHoverOpen.swift` as modified while every real `git status` in the
session (the last at 13:48, right before the context was summarised) showed it clean, and its md5 matched HEAD before and
after the mutation run — a stale snapshot, not lost work. Check the real tree before chasing a file that "vanished" from a diff.
Installed: dylib `cbe0492a` == build, appex `+`, runtime L10n 0 leaks, 1035 tests / 0. Bundled `xfinder-claude-statusline.sh`
is 0644 on purpose — the installer copies it to Application Support and sets 0700, like the hook.

## P3 (2026-10-13) — the settings shell in OneNotch's grammar; "Notch & Khay thả" split six ways; one Phím tắt page

Brief v3, owner-approved. Built contract-first: the main session wrote the shared layer (SidebarDestination cases +
tiles + NOTCH group, `XFinderTokens.Settings`, `Views/Components/SettingsShell.swift`, 6 page stubs, 8 pbxproj files ×4
entries, RootView routing), five file-confined agents filled it against `scratchpad/p3/CONTRACT.md`, then a 29-agent
review (5 lenses, 2 refuters per finding). Decisions taken by default are Q-P3-1…9 in docs/PENDING_TESTS_AND_DECISIONS.md.

| Piece | Where | Rule it keeps |
|:--|:--|:--|
| Shell tokens | `XFinderTokens.Settings` — sidebar 220 fixed, tile 22/r6, header 52, title 20, card r10, row 31 | geometry measured on OneNotch; colours are `primary`-at-opacity / system colours that RENDER the measured light values (#F7F7F7 = black 3 %, #E5E5E5 = 10 %, #4D4D4D = 70 %) and adapt in dark — never hex |
| Grouped card | `SettingsSection(title:footer:)` + `SettingsDivider()` + `.settingsRow()` | ONE card implementation; `audit-ui-tokens.py` now fails a page that paints `Settings.cardFill` itself |
| One key, one control | `SettingsLinkRow(destination:)` | a page that mentions a setting another page owns links to it, never a second toggle |
| Sidebar | coloured tile per page (`SidebarDestination.tile`), native `List(selection:)` kept (↑↓ + VoiceOver), `sidebarRowSize .large` | `SidebarDestination.swift` is Foundation-only now and symlinked: every page in exactly one group, icons real + unique, titles translated (SidebarDestinationTests) |
| Header | `PageHeader` restyled for all 37 pages (52-pt bar, hairline, subtitle below) | signature unchanged; `icon` no longer drawn (P4 removes it) |
| Page background | all 39 `.background(Fill.window)` → `Settings.contentBackground` | the review found RootView's white page was painted over on EVERY page |

**Split by what the user comes to do (measured, not guessed):** `dropTray.hoverEnabled` gates EVERY hover
(`NotchSurfaceMachine.swift:151 guard s.hoverToPeek`), so it went to Giao diện notch with hoverOpens/hoverSpeed;
`dropTray.notchEnabled` switches the WHOLE notch off (NotchSurfaceController.enabled), so it is Giao diện notch's header
switch and the Features hub row is now "Notch" (it said "Khay thả file" while killing Clipboard/Now Playing/Agents/
Calendar at the notch). Khay thả keeps the tray + drag/shake triggers; Đang phát, Agent AI, Lịch & lời nhắc, Hoạt động
trực tiếp got their own pages, each saying so (link) when the notch is off. Store keys checked first: "Giao diện" was
taken ("Appearance"), hence "Giao diện notch".

**Phím tắt** owns the two recorders (6 capture modes, ⌘K); Chụp & chú thích and Tìm kiếm show the chord + a link. Fixed
chords come from `Core/Shortcuts/ShortcutCatalog.swift` (pure), which also does the cross-feature clash check. Facts the
pass found while writing copy, each checked in code: ⌘⇧V opens the NOTCH by default (`clipboard.hotkeySurface`), not the
shelf; ⌘⇧C, ⌥⌘N/L/P are LOCAL monitors — only while XFinder is in front (never "while XFinder is open"); ⌥⌘P toggles the
first unarchived note; ⌥⌘A and the editor's ⌘T/⌘F/⌘P/Esc were documented on the Notes page and wired nowhere — removed;
the snap page hid ⌃⌥D/F/G; ⇧⌘G (Dịch) replaces Find Next in every app while on — said on the page.

Traps of this pass:
* **Inside `enum XFinderTokens`, `Font` is `XFinderTokens.Font`** — `static let x = Font.system(...)` does not compile
  ("has no member 'system'"); write `SwiftUI.Font.system`.
* **`build-and-check.sh` printed "BUILD FAILED" with no cause** (it tailed 40 lines; the `error:` lines were above) and
  exited 0 on a `MISS`. It now prints the errors and fails on any missing file; P3 files are in its by-name list.
* **A catalog test that reads a hand-written list proves nothing about the catalog.** Mutation C4 (catalog leftThird
  2 → 3) stayed GREEN: the test checked that "case 3:" exists in the engine — it does, for centerThird. Rewritten to take
  each value FROM the catalog and check the engine maps it to the same action (snap pairs parsed `case N: target = .x`);
  C7–C9 prove the clipboard/notes/quit versions.
* **An agent report is not the code.** D1 called the Phím tắt page's `capture.enabled`/`quickSearch.enabled` "read-only
  mirrors"; they were `ToggleRow`s — two switches, one key — and all five review lenses missed it; found by reading the
  section while fixing something else. Also from reading: ⌘K sat outside the clash check (NSEvent flag layout), a
  capture-vs-capture clash printed the raw id "capture.area", ⌘⌥C's activity ignored the master tap switch.
* **The review's real catches:** the switcher row printed ⌘Tab when the user picked ⌥Tab (`ShortcutCatalog.liveChord`);
  the Agent AI copy said "never reads conversation content" while the hook logs the typed prompt and tool-input
  summaries (copy fixed to say exactly what is read); the split dropped the per-mode "Chụp" button and the System
  Settings ▸ Keyboard link; the notch Agents tab still told users to open "Notch & Khay thả".
* **The survey agent said CLAUDE.md had no ⌥Space text.** It had three rows (the GlobalSearchController table row, the
  app-lifetime list, the Part 2 page row) — removed here and in AGENTS.md / ChatGPT.md.
Shipped as `513df7d` (pushed). Gates on the committed tree: 1063 tests / 0 · mutations settings 14/14, notch 56/56,
notch-clipboard 33/33, agents 20/20 (sequential, sources byte-identical) · L10n 2 507 entries, every gate 0 · runtime
L10n on the installed bundle 0 — after teaching `verify-l10n-runtime.py` the bundled allowlist (it flagged "NOTCH",
identical by design, as a leak) · installed dylib == build. Not opened live: the owner was at the keyboard (T-P3-*).

## P4 (2026-10-14, `7ea6039`, pushed) — every remaining settings page through the shared card grammar, presentation only

Brief v3 P4. 34 page files converted by six file-confined agents (Agent tool) against `scratchpad/p4/CONTRACT.md`:
`SectionHeader + rows + Divider` → `SettingsSection(title:, footer:) { rows .settingsRow() / SettingsDivider() }`, the
dead `PageHeader(icon:)` parameter removed from all 45 call sites, `LabeledLine`/`MeterRow` no longer pad themselves (the
card does). Kept flat on purpose: ClipboardLibraryView (a browser), SystemControlsPanel (embedded in the flyout), the mouse
diagram, the snap guide + snap-now grid, the vault/sync/remote/share item lists, drop zone, empty states, primary CTAs.

**The gate that made a 34-file restyle safe: `scripts/check-presentation-only.py`.** Per changed page vs HEAD it compares
the multisets of `@AppStorage/@State/@Environment/@FocusState/@Bindable` lines, `L10n.t/md` literals, `.onChange` bodies,
lifecycle bodies (`.onAppear/.onDisappear/.task/.onReceive` — added after the first run: the metric pages retain/release
their samplers there, and the first version of the gate could not see them), and the count of every control constructor.
Proven red before use (vs the pre-P3 commit it reports the 5 recorder buttons P3 moved off the Capture page). Result:
`TOTAL 0 differences across 43 changed pages`. **A restyle gate must cover lifecycle, not just state and strings.**

What the gate cannot see — layout — needed readers. Two read-only reviewers found six; checked, four were real:
* AppQuit: an unconditional divider before the list PLUS one per item ⇒ two hairlines before the first app.
* Snap page: the flat guide/snap-now/tiling block lost HEAD's two separators without being boxed — restored.
* Folder lock: "Vault của bạn" left flat between two cards with both separators gone — now a card (status line inside,
  so an empty list never leaves an empty box).
* Anti-sleep: `SettingsSection(title:, footer:) { }` drew an empty card above its footer. Fixed there AND in the component:
  `SettingsSection` draws no card when `Content == EmptyView`.
* Refuted (kept): "a divider before the first file row" on Compress/PdfTools/Capture — a real row (the picker button / the
  switch) sits above each ForEach, so that hairline is the between-rows separator, unlike AppQuit's double one. A swept
  pattern (`ForEach … { SettingsDivider()`) is only a bug when nothing precedes it or another divider already does.

**Mutation harnesses, found while running all 18 for P4.** Every harness went RED except
`mutation-check-gesture-buttons.sh`, whose M9 anchor had rotted since `ea3a98d` — and the script printed "HARNESS ERROR
(anchor missing) — treat as inconclusive", then exited 0. Fixed: a missing anchor now aborts with exit 2 (also in
`mutation-check-gesture-labels.sh`), gesture-buttons counts RED/TOTAL and prints `RESULT: n/n`, and exits 1 unless every
mutation is red, every source is restored byte-identical and the suite after restore has 0 failures; M9 re-anchored.
Rerun: buttons 13/13 · labels 5/5 · ui 8/8 · l10n 6/6.

The full run also ended with the L10n store and allowlist **reordered** (same content). Two restores re-serialised instead
of copying: gesture-ui's BUG 6 "restored" the deleted key by re-running `add-gesture-l10n-entries.py` (which appends at the
end), and the l10n harness re-added OCR and wrote the allowlist back `sorted`. Both now `cp` a backup taken at start.
**A restore is a byte copy of a backup, never a regeneration** — regeneration is a second, unrequested edit.

And a measurement trap in my own check: **`find` in the Claude Bash tool is a shell function (from the shell snapshot)
whose traversal order is not stable** — three identical `find … -exec md5 -q {} + | md5` runs gave three hashes with nothing
changing; `/usr/bin/find` inside an `sh` script gives yet another order. So "SOURCES DIFFER" was the check, not the tree.
Hash a **sorted** per-file list (`… -exec md5 -r {} + | sort -k2`), and confirm mutated files with
`git diff --quiet -- <files>`. (`ls` is `eza` here, too.)

The OpenCode research agent for P5 wrote six files into the repo root (`help.txt`, `openapi*.json`, …) despite the
scratchpad rule — moved to the scratchpad. Fourth time an agent has done this; `git status` after every agent, always.

Gates at commit: build arm64 · 1063 tests / 0 · check-presentation-only `TOTAL 0` across 43 pages · L10n six gates 0 and
runtime on the installed bundle 0 leaks · audit-ui-tokens 0 · installed dylib == build. Not verified by eye: T-P4-*.

## P5 (2026-10-14, `e6a55f4` · `2b43092` · `a21edac`, pushed) — coding agents beyond Claude Code, measured before built

Brief v3 P5: "Kết nối Codex / OpenCode / Cursor (probe trước) + thông báo + phiên gần đây". Three read-only research agents
(docs + this Mac, no credential files, no transcript content) plus my own probes decided the shape per agent:

| Agent | Measured | Path XFinder takes |
|:--|:--|:--|
| **Codex** 0.155.0 | `~/.codex/hooks.json` uses Claude's exact hook shape and events (`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `Interrupt`…), same stdin fields, same PermissionRequest output (`hookSpecificOutput.decision.behavior`). **A new or changed hook is SKIPPED until trusted in `/hooks`** — trust is stored as `[hooks.state."<file>:<event>:<group>:<handler>"] trusted_hash` in config.toml; on this Mac only the `pre_tool_use:0:0` entry has one, so **Notch Crew's PermissionRequest hook there is being skipped**. `SessionEnd`/`Interrupt` timeouts default 1 s, max 3 s. Multiple PermissionRequest hooks: all run, "any deny wins". | **P5a** — the same zsh hook, agent passed as `$1`; XFinder never writes trust for the person |
| **OpenCode** 2.0.27 | Its own log: **v1 plugins are refused** ("Plugin must export a default definition with an id and an effect or setup function" — for Notch Crew's `notch.js`), so that integration is dead here. The background service's HTTP API needs a password (401 without), but `opencode api <operationId>` carries it. `opencode api event.subscribe` buffers (0 bytes in 8 s). A pending permission is memory-only (DB/WAL unchanged). Full loop proven on an isolated `opencode serve` (scratch XDG dirs, own port): `permission.asked` → `opencode api session.permission.reply … -d '{"decision":"once"}'` → `permission.replied`. v2 calls the shell permission `shell`, and a request without an agent evaluates to `deny`. One CLI call ≈ 0.04 s CPU, 99 MB transient | **P5b** — the person's own CLI on a DB-write cue |
| **Cursor** | CLI 2025.09.17, not logged in, no IDE installed. Hooks decide *before* a prompt; no event says Cursor is waiting for approval; the CLI wires only some events (forum source inspection) | explainer only |

Claude Code docs (claude-code-guide agent): matching hooks **run in parallel**; host vs hooks "whichever decides first
applies"; **how several PermissionRequest hooks combine is not documented** — `~/.claude/settings.json` here already holds
OneNotch's (3600 s) and Notch Crew's (86410 s). The page counts other tools' approval hooks and says the notch answer may
not take effect at once (T-P5-MULTI).

**P5a (Codex).** `AgentKind` (pure) · events carry `agent` (a line without one is Claude's — 1.3.0's hook wrote none;
`EventTail` also stamps the folder's agent) · sessions keyed by agent + id · `Interrupt` = your turn · installer per agent,
Claude's command string unchanged (`'path'`, so a 1.3.0 install still matches), Codex appends `'path' codex` **at the end**
of each event list (Codex trust is per position; front insertion would cost another tool its trust — mutation A22) · the
monitor tails one events folder per hook agent · "Sự kiện gần nhất" per agent is the only proof a hook runs.
The hook (`xfinder-agent-hook.zsh`, renamed from `xfinder-claude-hook.zsh`; Claude's installed copy keeps the old file
name) walks up to 4 parents to the process named like the agent — proven with a compiled fake parent named `codex`
behind a `sh -c` — falls back to `$PPID` only for Claude, and now drops `last_assistant_message` (Codex's Stop carries the
model's answer). 10 new tests (one runs the shipped script with zsh), agents harness 29/29 RED (A22–A30 new).

**P5b (OpenCode).** `OpenCodeRules` (pure: API JSON parsers, id validation before any process argument, CLI argument
lists, the API view → rows) + `OpenCodeMonitor` (ONE reader of `agents.opencode`, default off): kernel sources on
`~/.local/share/opencode/{opencode.db,opencode.db-wal}` and the folder; a write cues a refresh (≤ 1 per 2 s, plus one
2.5 s after the last write); a refresh runs the person's own `opencode api session.active` / `session.list` /
`session.permission.list` on a background task; a 30 s safety refresh only while a listed session is not ended.
Cho phép = `once`, Từ chối = `reject`, never `always` (A31). Rows use OpenCode's own title (`AgentSession.title`).

**E2E 11/11** against an isolated `opencode serve` (scratch XDG dirs, port 49611, the throwaway server's own password
in the child's env; the harness compiles the PRODUCTION `OpenCodeRules.swift` and only adds `--server`): list → row
waiting with the command → reject → gone → second request → once.

**Two wrong explanations on the way, both caught by measuring again — keep the lesson.** The e2e first failed because
the shell request came back `deny`. I concluded "OpenCode denies when no client listens to `/api/event`" from ONE
before/after pair and said so; the next run disproved it (`deny` again with a listener). Three requests in a row then
showed: the **first request after a server starts is `deny`, the next `allow`, later ones `ask`** — the agent's rules
finish loading after the server already answers. The harness now probes a throwaway session until a request asks.
**A before/after pair is a correlation; change one variable at a time and repeat before naming a cause.**

Harness: agents 36/36 RED (A31–A37 OpenCode). Tests 1079 / 0.

**P5c (notices, recent sessions, Cursor).** `AgentNotify` (pure): two transitions — a NEW permission request (one
request is announced once) and running → your turn — each behind its own key (`agents.notify.permission`/`finished`
default on, `agents.notify.sound` off; readers in AgentSessionMonitor, all in FeatureKeyDefaultsTests). The first
rebuild after starting is a baseline; OpenCode's rows arrive later, so rows from OpenCode's FIRST snapshot are a
baseline too — counted by `snapshotGeneration`, not by rebuilds (my first fix keyed on rebuilds and would have swallowed
the first real event after an empty first snapshot). Notices use the B4 queue (`LiveActivity.Kind.agent`, button
`.openAgents`) and are skipped while the Agents page is open. `AgentRecent` (pure) reads only identifiers from each
agent's own file head — measured: Claude's `cwd`/`sessionId`/`entrypoint` within ~250 KB (only `entrypoint == cli`
listed; 55 of the newest 60 here are `claude-desktop`), Codex's `session_meta` (`originator == codex-tui`); OpenCode from
the last `session.list`; 14 days; live sessions excluded. Scanned when the notch Agents page opens or the settings page
asks — no timer. Cursor: an explainer section with the measurements.

**Review of P5 (3 read-only lenses): 1 real high finding, fixed.** A `session_id` from the hook payload became part of
the decision file name unchecked — in Swift (`answer()` writes `decisions/<sid>-<rid>.json`) and in the hook (`cat` + `rm`
of the same path when jq is present; only the sed fallback filtered characters). A forged `../…` id escaped the folder.
Now `AgentEvents.isSafeSessionID` gates parsing and `AgentDecision.fileName` (returns nil), and the hook waits only on a
`[A-Za-z0-9_-]{1,128}` id. Test with a positive control (`XFINDER_ASSUME_RUNNING=1`: a safe id must wait, `../escape`
must exit on its own) — the env knob exists only so the waiting path is testable without the app. Mutations A46/A47.
Also fixed: the "Phiên gần đây" footer said "terminal sessions" while OpenCode rows were not filtered (now worded per
agent + the 14-day cutoff applied to OpenCode), long names on notch rows (`minWidth: 0` + `layoutPriority(-1)`).
**Refuted:** "the two notice keys are missing from the store" — they were added before the review ran (the reviewer read
a stale view); the test that walks them is green. Pre-existing, not fixed: a truncated-then-regrown event file is re-read
only on the next write.

Live: installed (dylib == build), runtime L10n 0 leaks; **the AX dump of the page could not run — the screen was locked**
(probe-ax-dump says so). T-P5-* in the pending list.

## P6 (2026-10-14, `4601d45`, pushed) — "Nhắn phiên": reply to an agent session from the notch

Job: *"my agent finished a turn; answer it from the notch without finding its terminal."* A **Nhắn** button on every
session row opens a one-line compose bar on the Agents page; the text goes to that session by the route
`AgentTalk.route(for:)` picks (pure, symlinked, 13 tests), sent by `AgentTalkSender` (@MainActor; work off-main).

| Route | Mechanism (measured on isolated processes only) | Checked before typing |
|:--|:--|:--|
| OpenCode | `opencode api session.prompt --param sessionID=… -d '{"text":…,"delivery":"queue"}'` — flat body, `delivery` ∈ steer/queue; queue waits in the session's inbox | id is `ses_…` |
| tmux (wins over kitty: a kitty window holds the whole tmux client) | `load-buffer -b xfinder-reply-<uuid> -` (stdin) → `paste-buffer -d -p` → 0.1 s → `send-keys Enter` | `display-message -p '#{pane_tty}'` == the tty the hook recorded (pane ids are reused) |
| kitty | `kitty @ --to unix:… send-text --match id:N --stdin`, then `\r` as a separate send | `kitty @ ls --match id:N`: the window's `foreground_processes` contain the agent pid (only `id`/`pid` read; `ls` also prints env — ignored) |
| anything else (Terminal.app, iTerm2, Ghostty, WezTerm, no terminal recorded) | text on the clipboard + the terminal app activated | — |

Routing is per TERMINAL, not per agent: a Codex session in kitty/tmux is typed into like a Claude Code one. What is unmeasured for Codex is only its own `codex queue` API (Q-P6-CODEX). The second review pass caught the settings copy saying "Codex" was copy-only.

Rules: one line (breaks/tabs/U+2028/2029/0x85 fold to a space), every C0/DEL/C1 removed (an ESC sequence in `--stdin` or
`-l` text reaches the terminal LIVE — measured, it can retitle the window), ≤ 4 000 characters. Never typed while the
session waits for a permission, while a dialog is on screen (`permission_prompt` / `elicitation_dialog` notification, cleared
by the next prompt/tool/stop), or while `AskUserQuestion` is pending (a keystroke would pick an option). A working session
⇒ XFinder holds ONE message per session (a newer one replaces it, Huỷ drops it) and sends it when the session waits for the
person with nothing on screen; a session that ends drops it and says so. Enter is a separate keystroke 0.1 s after the text
(a TUI may read text+CR in one read as a paste and not submit). The hook records `KITTY_WINDOW_ID`, `KITTY_LISTEN_ON`, `$TMUX`
(never `KITTY_PUBLIC_KEY`); `tcp:` kitty listeners are refused (typing over the network).

Findings worth keeping:
* **`Foundation.Process` decomposes non-ASCII ARGUMENTS to NFD** (fileSystemRepresentation): "Sửa" as an argument reached
  the child as `53 75 cc 9b cc 89 61`, through stdin as `53 e1 bb ad 61`. The first tmux e2e failed on exactly this. So text
  never travels as an argument: tmux and kitty get stdin, OpenCode gets ASCII-only JSON (`\uXXXX` UTF-16 units). **Any
  Process call that passes user text must use stdin or an ASCII encoding** — this applies outside P6 too.
* **`opencode api` exits 0 on HTTP 200 and 1 on 400/401/404** (measured), so `status == 0` is a real success check — for
  P6's prompt and for P5's permission reply.
* **Claude Code's messaging socket (`CLAUDE_CODE_MESSAGING_SOCKET`) is rejected**: a message through it arrives as
  "Message from @<another session>", which the receiving Claude treats as a peer, not as the person; its line format is
  unpublished. TIOCSTI returns EACCES (as expected on macOS).
* **Not measured, so not shipped:** Terminal.app `do script` (Automation consent needed — Q-P6-TERMINAL), `codex queue`
  (would run a model turn — Q-P6-CODEX).
* **An installed copy of our own script never followed the app.** `installHook` copies the hook to Application Support
  once; P5c's session-id check and P6's new env fields would have reached nobody who installed earlier. `AgentSessionMonitor.
  refreshInstalledScripts()` (first `applySettings`) rewrites an EXISTING copy of the hook / statusLine script when it differs
  from the bundle — atomic, so a running hook keeps its open file; the agents' settings files are not touched.
* **The OpenCode research agent made real model calls** on its isolated server (OpenCode's built-in free model answered a
  probe prompt) — a research prompt that says "isolated server" must also say "never send a prompt", or the probe spends the
  person's quota/data on a third-party model.
* The notch machine got `Settings.composing` (a fact, like `nowPlayingActive`): while composing, `pointerAway` does not
  collapse; ✕/Esc/leaving the Agents page/the session vanishing end composing. Return on an empty field keeps it open.
* Two notch-page strings reused existing keys instead of new ones: `Hủy` (store) not `Huỷ`; the ` · ` separator is a glyph
  outside `t()` (an identical-English entry is refused by the coverage gate).

e2e on isolated targets with the production `AgentTalk` + `AgentTalkSender.perform` compiled into a CLI: kitty 8/8, tmux 8/8
(Vietnamese + emoji arrive NFC, ESC removed, reused-pane and wrong-window refusals, Enter separate). Not verified on the
person's real sessions — T-P6-* in the pending list.

**P6 review (5 lenses, 2 refuters each; one lens re-run after a schema failure): 2 confirmed, 3 split, 0 refuted.**

| Finding | Verdict | What changed |
|:--|:--|:--|
| The target was checked once, before the text; Enter went to the same pane/window 0.1 s later unchecked — if the agent exited in between (Ctrl-C, a turn ending into the shell), the typed reply ran as a **shell command** | confirmed (medium/low) | both routes re-run the check right before Enter; a mismatch skips Enter and says the text may still be in the input line. e2e kitty 8/8, tmux 8/8 after the change |
| The hook's `esc()` escaped `\` and `"` but not control characters: a newline in `$TMUX` split the event in two and both halves were dropped | confirmed (low) | `LC_ALL=C tr -d '\001-\037\177'` before escaping (UTF-8 continuation bytes are 0x80–0xBF, so multibyte text survives); test runs the shipped hook with a newline and an ESC in the env; mutation A66 |
| `dialogOnScreen` can outlive a dialog the person dismissed with **Esc** (Claude's Stop hook does not run on a user interrupt), blocking every reply until they typed in the terminal | split (one refuter: deliberate fail-closed) | kept fail-closed — **Enter on Claude's permission dialog is its highlighted default, "Yes"**, so clearing the flag on a guess could approve a tool call — but a dialog/question now yields `Decision.copyInstead`: the text is copied and the terminal brought forward, the button says "Chép và mở terminal". No dead end, no keystroke. Mutation A67 (button says send while copying) |
| `stop()` (notch switched off) bypassed `dispatch()`, leaving the Esc key monitor installed and the stale draft to reappear | split | `stop()` clears the target/text and calls `syncAgentReplyKeyboard()` |
| kitty is matched by window id + agent pid with no tty, unlike tmux | split (one refuter: the check runs live at send time) | accepted: both a recycled window id AND a recycled pid would have to land within the 20 s liveness window; `kitty @ ls` prints no tty to compare |

**Codex's hook trust does NOT cover the script's bytes** — from openai/codex (`codex-rs/hooks/src/engine/discovery.rs::hook_hash`,
`codex-rs/config/src/hook_config.rs::HookHandlerConfig`): `trusted_hash` hashes the hook's config identity (event, matcher, command
string, timeout, async, status message…), never the file the command runs. So `refreshInstalledScripts()` rewriting the installed
hook does not revoke a Codex trust; changing the COMMAND string in hooks.json would.


## P7a (2026-10-14, `7fa96f4`, pushed) — windowless Claude Code sessions; and a SIGPIPE hole in every child stdin

Brief v3 P7 is "Crew + phiên không cửa sổ". Research workflow (4 probes + a critic, no model turn, no decompiling of
Notch Crew / OneNotch) first, then P7a = windowless sessions; crews (P7b) are not built yet.

**How Notch Crew does it, measured from outside** (`scratchpad/p7/notchcrew/`): one main executable + Sparkle, not
sandboxed, `automation.apple-events`; `nm -u` shows `NSTask` and `kill` and **no pty function** — a windowless session is
the agent's own CLI over plain pipes; its copy says "Claude's background session stops…". Terminal.app / iTerm2 are driven
by embedded AppleScript (`do script` / `write text`, matched by tty or iTerm session id); hooks for Claude/Codex/Cursor/Gemini
and plugins for OpenCode/Hermes all POST to one HTTP server on a Unix socket (`~/Library/Application Support/Notch Crew/
notch.sock`); crewmates message each other through a `crew` shell CLI the agent itself runs (`crew send <role> <msg>` →
curl on that socket → the app relays and returns the reply). **`strings` cannot see Swift literals of ≤ 15 bytes** (they are
stored inline in code), so "no `stream-json` string" proves nothing — only the import table (`nm -u`) is conclusive here.

**Claude Code facts used** (docs + local `--help`, v2.1.296): streaming input `-p --input-format stream-json --output-format
stream-json --verbose` keeps one process for many turns; a user turn is `{"type":"user","message":{"role":"user","content":
TEXT},"parent_tool_use_id":null}`; `result` ends a turn; hooks fire unless `--bare`; `claude agents --json` lists background
sessions but no public non-terminal path sends a NEW prompt into one (attach only) — so XFinder hosts its own processes.
Measured: with no input the stream prints ONE `system/ui_invalidate` line (undocumented) carrying the preset `--session-id`
and exits 0, writing no transcript and asking no model.

| Piece | File | Holds |
|:--|:--|:--|
| pure | `Core/Agents/WindowlessRules.swift` (13 tests) | arguments (UUID-only id), user-turn line, message cleaning (keeps newlines), `env -0` parsing, child environment, stream parser, `Record` phase machine + 40-entry transcript, row + merge with hook rows, phase/error keys |
| live | `Core/Agents/WindowlessSessionManager.swift` (@Observable) | login-environment resolution, launch / send / interrupt (SIGINT) / stop (SIGINT + close stdin + SIGTERM at 3 s) / forget / stopAll at quit, remembered folders, ended-session history for Phiên gần đây |
| route | `AgentTalk.Route.windowless` | reply = stdin JSON line, held while a turn runs |
| UI | notch "+" composer, conversation view (Allow/Deny inside it), row glyph; Agent AI ▸ Phiên không cửa sổ | |

Findings worth keeping:
* **SIGPIPE killed the writer** (probe: unguarded pipe write after the reader closed ⇒ exit 141; with `fcntl(fd,
  F_SETNOSIGPIPE, 1)` the write throws). The P6 kitty/tmux sender and Khoá thư mục's hdiutil password write had the same hole —
  a CLI that exits before reading stdin would have taken XFinder down. All three are guarded; `ChildStdinSafetyTests` reads
  the sources and fails on an unguarded stdin writer or the legacy `write(_:)` (NowPlayingMonitor only CLOSES its stdin pipe).
* **launchd's PATH would hide the agent's own tools**: the child runs with `zsh -i -l -c 'env -0'` (0.47 s, 28 variables,
  PATH with Homebrew + ~/.local/bin), CLAUDECODE / terminal / messaging variables removed, `XFINDER_WINDOWLESS=1` added (the
  hook records it as `env.windowless`).
* **Review (5 lenses, 2 refuters each): 5 confirmed, 1 split, 1 refuted.** (1) the "8 s cap" on that shell was false —
  `readDataToEndOfFile` waits for EVERY holder of the pipe, and a startup file that backgrounds a job (ssh-agent, a version
  manager) keeps it open: reproduced 20.09 s against the cap; now output is collected as it arrives and taken when the shell
  exits (0.44 s), harness check proven red on the old code; (2) "Mở lại không cửa sổ" did not check the session was open
  elsewhere — now a live hook row or a `claude` process naming the id refuses it (`openElsewhere`); (3) Hủy/Esc did not cancel
  the launch task — now it does, checked after the environment resolves; (4) a permission request had no Allow/Deny inside
  the conversation view; (5) the row glyph said "XFinder đang chạy nó" after the process ended. Refuted: "`-p` defaults to
  auto mode and skips the hook" — both refuters read the Claude Code 2.1.296 binary and found the default is the normal mode.
* **Found by me while the review ran: Phiên gần đây could never list a windowless session.** A `-p` transcript head says
  `entrypoint: "sdk-cli"` (6 of the newest 100 here) and the P5c scan lists only `cli` — `sdk-cli` also covers other tools'
  headless runs, so XFinder remembers the ids it hosted (`agents.windowless.history`, ≤ 20, id + folder + time, no message)
  and merges them into the recent list.
* **A green mutant was an equivalent one**: A77 removed `!name.contains("\n")` from the env-name guard, but the next clause
  (letters/digits/_ only) already rejects a newline — the redundant clause was deleted and A77 re-aimed at the real check.

Gates: build arm64 · 1120 tests / 0 · e2e with a stand-in `claude` 19/19 (fixed id, marker, NFC answer with newlines, tool
output not kept, stop, a write into a killed child does not kill XFinder, missing folder, two resume refusals, the
backgrounding shell) · L10n +38, all gates 0. **No model turn was run** — T-P7a-*, Q-P7a-MODEL in the pending list.

## P7b (2026-10-14, `7ca577d` + review `760715b`, pushed) — crews: windowless Claude Code sessions that hand work to each other

Job: *"I give a goal to a small team of Claude Code sessions with roles; they hand work to each other without me
copy-pasting, I see every message on one board, and I can pause the whole thing."* Agent AI ▸ Nhóm agent (crew) starts
one; the notch Agents page shows a crew row and a board.

| Piece | File | Holds |
|:--|:--|:--|
| pure | `Core/Agents/CrewRules.swift` (15 tests) | 2 templates (pipeline: builder + read-only reviewer; expert review: builder + two read-only critics), launch flags, the ASCII system prompt, request parsing + signature, the `Relay` engine (queue, one delivery in flight per member, one reply-back, cap, pause/stop), board, keys |
| live | `Core/Agents/CrewManager.swift` (@Observable) | crew folder `Application Support/XFinder/Agents/crew/<id>/` (0700: roster.txt, inbox/, paused marker), the CLI install, inbox `DispatchSource`, effects → `WindowlessSessionManager.deliver` (the ONE write gate: `.sent/.busy/.gone`) |
| CLI | `Resources/Agents/xfinder-crew.zsh` | `who` · `send <role|all> <msg>` — validates the role, strips control characters, caps 8 000 characters, writes the request atomically, returns at once (Claude's Bash tool times out at 2 min, so a send that waited for a turn would die) |

Decisions, each with its reason:
* **Every member runs `--permission-mode manual`** whatever the person's default (docs: `manual` is an alias of the config
  value `default`), and every crew message is itself a Bash call — so the person approves each one. No "without approval"
  switch: a prefix allow-rule cannot see the message text. **But manual mode still runs Claude Code's fixed read-only Bash
  set (cat, grep, git diff…) unasked, and allow rules in the person's or the folder's settings still apply** — the settings
  copy says both (review caught the first; the second was flagged by the security lens and checked against the docs).
* Reviewers/critics get `--disallowedTools Edit,Write,MultiEdit,NotebookEdit`. Non-lead members start with no message and
  spend nothing until a crewmate writes to them.
* **The sender is proven by a signature, not a token in the file.** First version put each member's token in its inbox
  request; the security lens reproduced reading another member's request (`cat inbox/*.json`) before XFinder deleted it and
  then posing as that member. Now the file carries `from` + `mac` = SHA-256(file name ⏎ target ⏎ text ⏎ token) (token LAST —
  no length extension of a secret prefix); the token never reaches the shared folder. `testTheShippedCLISignsWhatTheApp
  Verifies…` runs the shipped zsh script and checks the Swift side accepts its signature byte for byte (Vietnamese +
  newline + quotes; `Process` passes the argument NFD and both sides hash the same bytes) and that the token is absent.
  Tokens remain same-user namespacing, not a security boundary (members run as the person, in one shared folder).
* **The goal goes to the lead only after the crew is registered and its inbox watched** (review: a lead turn that ended
  before registration reached no relay and left the lead marked busy forever).
* **`turnEnded` reaches the relay BEFORE `onChange`** (review): `onChange` flushes P6's queued replies, which re-busied the
  session while the relay still believed it free — one needless `.busy` bounce, and fragile if that reconciliation ever went.
* Cap 20 deliveries (each message or reply handed to a member is a hop), then pause with `capReached`; resume adds 20. A
  person's own pause never raises the cap.

Review (4 read-only lenses: engine, trust, UI, copy): engine 3 (signal order, start race, dict mutation while iterating —
all fixed), trust 2 (token in the shared inbox — fixed by signing; oversize sends silently dropped — the CLI now refuses
> 8 000 characters), UI 5 (crew board not reset in `stop()`, not reconciled when the crew is forgotten from Settings, a
stale compose bar under a crew board — fixed; a literal font size predates P7b; the header's "n chờ bạn" stays a grand
total because the activity machine needs it), copy 3 (the read-only-command claim, the settings board line dropping the
failed member's name, the cost tooltip missing on the settings row — fixed).

Gates: build arm64 · 1135 tests / 0 · crew e2e with a stand-in `claude` 15/15 (manual mode, reviewer without edit tools,
ASCII prompt, CLI on PATH, signed send, message → reply round trip, one reviewer turn, a wrongly signed request dropped,
pause marker, stop ends members and removes the folder) · agents mutations 90/90 RED (B1 re-aimed at the signature check; B13's first anchor did not match — the run aborted with HARNESS ERROR instead of reading green, re-anchored) · installed dylib == build · L10n all gates 0.
**No model turn was run** — T-P7b-*, Q-P7b-* in the pending list.

## G3 (2026-10-14) — malloc fragmentation: measured, nothing to fix

The "44 % of the malloc zone is fragmentation" from G was measured right after the G script toggled 21 feature keys
(mass build-up and teardown). On the installed P7b build with the person's own settings: 2 min 53 s after launch —
footprint 30.5 MB, fragmentation 19 % (default zone 14 %); 12 min, person idle 177 s — **28.9 MB, 11 %** (2.0 of 16.2 MB).
It does not recur and does not grow at rest, so there is no leak to chase; the < 30 MB target holds. `heap <pid>` prints
the per-size node table; `vmmap --summary` gives the zone line with the % FRAG column.

## 1.4.0 packaged (2026-10-14) — not published

Info.plist 1.4.0 / build 5. `WhatsNewRules.notes14` (7 notes for P1–P7 and §3b #21/#37; every symbol checked with
`NSImage(systemSymbolName:)`, every destination a real `SidebarDestination` case, every claimed setting checked to live on
the page the note names), 14 strings through the add-only `scripts/add-release14-l10n-entries.py`; the What's New test now
walks every version's notes (ids unique across versions) and was proven red by deleting the `"1.4"` case. CHANGELOG 1.4.0.
`make-release.sh` refuses a bundle without `xfinder-crew.zsh`. `dist/XFinder-1.4.0-arm64.zip` 7.1 MB, sha256
`02d314cc…a64a08`; unzipped into its own folder it verifies `--deep --strict`, says 1.4.0 / 5, arm64, carries the signed-
request crew CLI. The 1.4.0 Debug build is installed (dylib == build, runtime L10n 0 leaks). **Not published** — Q-RELEASE-14.
`dist/` is git-ignored: the zip never goes into the repo.

## Agents page "silent" with OpenCode running (2026-10-14) — both switches were off, and the page said the wrong thing

Owner: OpenCode running in kitty, the notch showed no activity. Measured before touching code: `agents.enabled` and
`agents.opencode` were both ABSENT from the defaults domain (both default false — opt-in by design), so `OpenCodeMonitor`
never ran. The data path itself was fine: the kitty TUI (pid 43653) is a client of `opencode serve --service` (127.0.0.1:49374),
and `opencode api session.list` through that service listed the session; `session.active` was `{}` only because the turn had
just ended (`time.idle == time.updated`). The real defect: the empty page's only line was "Chưa cài hook…" — a hook OpenCode
does not use — so nothing told the owner the feature was off. `AgentSessionRules.emptyReasonKey` (pure, tested) now names
the reason: master off · OpenCode on but `opencode` not found · nothing connected (no hook AND OpenCode off); OpenCode on
alone is NOT a reason (it needs no hook). Also "1 sessions" / "1 need you": the count moved to the end ("Sessions: 1",
"Waiting for you: 1"). Measured on the installed build (AX, English): `Sessions: 1 · Waiting for you: 1`, the OpenCode row
"Waiting for you · 4 min" with Reply. Both switches were turned on for the owner (they asked for the feature).
**Rule: an opt-in feature whose surface is visible while the feature is off must say it is off.**
**P8 follow-up — the activity grid cost 21 % CPU and is now ~0 %.** The first grid was a `TimelineView(.periodic)` at ~8 Hz;
`sample` showed every tick re-laying out the WHOLE notch hosting view (`NSWindow layoutIfNeeded` → `_layoutViewTree`,
~16 % of the main thread) — measured 6.26 s CPU / 30 s with a session running. Rewritten as an `NSViewRepresentable` with nine
`CALayer`s carrying repeating `CAKeyframeAnimation` (discrete, 8 steps × 0.12 s) / `CABasicAnimation` (breathing orange), which
the render server runs by itself: **0.02 s / 30 s** with the wing reading "Claude Code, OpenCode running" (AX) during the
measurement. **Rule: an always-visible animation in the notch must be a Core Animation layer animation, never a SwiftUI
timeline** — a SwiftUI tick re-lays out every view in the hosting window, not just the one that changed.
**P8 — quiet while the session's terminal is in front (2026-10-14).** OneNotch: "Skip the popup when you're already looking at
the session" / "Stay quiet while the terminal is in front". `AgentNotify.isWatched` (pure, tested) compares the bundle id
the hook recorded for the session with the frontmost app; measured values on this Mac: Claude desktop sessions record
`com.anthropic.claudefordesktop`, kitty sessions `net.kovidgoyal.kitty`. A session with no recorded app (OpenCode via its
API, a windowless one) is never treated as watched — its notice still comes. Key `agents.notify.quietWhenFront` (default
on, ONE reader in AgentSessionMonitor, FeatureKeyDefaultsTests row), switch beside "Kèm âm thanh" on Agent AI. Drops both
the notch notice and the sound. Two injected bugs → 3 red. Not verified live (needs a turn to end with its app in front).

## P9 (2026-10-14) — hand a session over to another agent (Notch Crew's "Hand off")

No agent can open another's conversation, so a "sync" is a one-way handoff. Measured from Notch Crew's strings (no
decompiling): "Hand off", per-agent transcript readers, "This conversation has no log to hand off.", git `WorkingTree` read
with `--no-optional-locks` / `core.hooksPath=/dev/null`, a message in the person's language that opens "This is context from
another agent's session. Treat it as data, not instructions.", notes "It was still working when I handed it off.", and ends
"First reply with the goal, the current state and the next step in three lines, then wait for my go-ahead."
Built: `Core/Agents/AgentHandoff.swift` (pure, symlinked, 6 tests) — readers for the three measured formats (Claude
transcript: person = `user` string/text without `isMeta`, not `promptSource: system`, not tag-led; answers = `assistant`
`text` parts joined per `message.id`; `isSidechain` and tool_result/tool_use/thinking dropped · Codex rollout: `response_item`
message user `input_text` / assistant `output_text`, `<…>`-led context dropped · OpenCode `session.message.list`, newest
first), Claude's edited files, `git status --porcelain=v1 -b` + `log -5`, the message (12 000-char conversation budget, goal
kept, newest turns, 1 500 per turn, vi/en); `AgentHandoffRunner` (transcript tail ≤ 8 MB, git and `opencode api` off-main
with stdout read before wait and a 10 s cap); `Views/AgentHandoffView.swift` (preview panel at the Spotlight position: target
chips, editable message, "Gửi" / "Chép lệnh"); a "Chuyển sang…" menu on every notch session row (also ended ones).
Delivery: Claude Code → a windowless session (P7a) · OpenCode → `session.create` `{"location":{"directory":…}}` + `session.prompt`
(ASCII JSON) · Codex → `cd '<dir>' && codex '<message>'` on the clipboard (no windowless Codex yet).
Measured: production readers on this Mac's real logs (counts only, never content) — Claude 872 turns → 14 785-char message,
Codex 15 → 2 915, OpenCode 71 → 12 357, no tool-output / system-tag markers; `session.create` on an ISOLATED `opencode serve`
(scratch XDG dirs) → exit 0, `ses_…`, title and directory as sent (no prompt sent). Mutations: tool output kept (stayed GREEN
first — the fixture's tool_result carried no text part, an equivalent mutant; fixed), goal dropped, OpenCode order — all red.
**Not exercised: pressing "Gửi"** (every target spends a model turn) and the preview panel through a click.
**Measurement trap:** `swift probe-ax-dump.swift` compiles on every run (seconds) and the hub closes once the pointer is away —
dumps read a collapsed notch. Compile the probe once (`swiftc -O -o axdump …`) and dump 0.5 s after `xfinder://notch?page=…`.
A SwiftUI `Menu`'s accessibility label comes from its label view: `.accessibilityLabel` on the `Menu` was ignored (read
"Divide", the SF Symbol's own name) — put it on the label's Image.
**P9 follow-up — the owner's screenshot (2026-10-14).** (1) A Claude desktop session offered "Copy and open terminal" and
said "can't type into this terminal": `AgentTalk.runsInApp` (entrypoint `claude-desktop` / bundle
`com.anthropic.claudefordesktop`) now makes the button "Chép và mở app" and the hint name the app. (2) "Waiting for you"
meant two things: the header counted finished turns (`needsYou` includes `waitingForInput`) while the wing (P8) showed them
as a green "your turn". `agentsNeedingYou` now counts `activity == .waiting` only (permission, question, dialog) — that
also changes the tab's orange badge and `NotchHoverOpen`'s "agent waiting" rank; rows say "Tới lượt bạn" (green) vs
"Đang chờ bạn" / "Chờ bạn duyệt" (orange) via `AgentSessionRules.rowStatusKey`. Measured (AX, installed build): header
"Sessions: 3" with no waiting count, OpenCode row "Your turn", this session "Running Bash". Two mutations red.
**P8 follow-up — no stacked tiles (owner, 2026-10-14).** Two overlapping agent tiles read as ugly and stop working past two or
three sessions. The left wing is now ONE tile (the most urgent session's agent, with its corner mark) and the number of live
sessions BESIDE it when > 1 (`WingItem.agentCounted`, 32 pt; a single session keeps the narrow `.agent`, 20 pt; 2 and 6
sessions are the same width — test + mutation red). The hub's content also comes into focus when it opens (`.blur` 8 → 0
alongside the existing fade, only while `appearFromNotch`), from the owner's screenshot of Notch Crew's hover.
Reply to a Claude desktop session stays copy + open app by design (no public way into that app's chat); an opt-in
"paste into the Claude app" (AX check that its composer has focus, then ⌘V + Return) is offered, not built.

## P10 (2026-10-14) — the session list the way OneNotch lets you shape it

From the OneNotch measurement (strings: `AISessionSortMode` priority / recency / newestFirst / manual, "Needs attention
first", "Keep finished sessions visible in the AI session list", "Open the latest running agent when hovering the AI edge").
`AgentSessionRules.SortMode` + `ordered(_:mode:keepFinished:)` (pure; manual ordering not offered — it needs a stored order
per session id that outlives the session); keys `agents.sortMode` (String, "priority") and `agents.keepFinished` (Bool,
true), ONE reader each in AgentSessionMonitor, both in FeatureKeyDefaultsTests; `listSettingsChanged()` rebuilds on change.
"AI edge": `NotchSurfaceLayout.agentEdgeRect` — the agent item of the collapsed LEFT wing (4 pt slack, nil without a notch or
when the agent is not the left wing's first item); the controller sets `Settings.pointerOnAgentEdge` (a fact) every tick and
the machine opens `.agents` on the ordinary hover dwell when `notch.agentEdgeHover` (default on) — still under the master
hover switch and only if the Agents page is shown. The wing's edge padding is now `Metrics.wingEdgePadding` (was a literal 9
in the view), so the hit rect and the drawing cannot drift. Tests 1152/0; three P10 mutations red; notch harness 57/57 red.
Settings section verified through AX on the installed build. Not exercised: pointing at the real wing with a hand.

## P11 (2026-10-14) — windowless Codex sessions over `codex app-server`

Measured on codex-cli 0.155.0 (schema from `codex app-server generate-json-schema` — 164 client requests, 82 notifications,
11 server requests — plus a probe that ran ONLY the handshake, no `turn/start`, no model call): `initialize` answers in 0.16 s,
`thread/start {cwd, approvalPolicy:"on-request", sandbox:"workspace-write", ephemeral:true}` returns `thread.id` (== `sessionId`)
with cwd/policy echoed, closing stdin exits 0; messages are `id`/`method`/`params` with no `"jsonrpc"`. XFinder's Codex hook is
not installed on this Mac (events folder empty), so a windowless Codex session shows through XFinder's own record, like a
windowless Claude one. Approval arrives as a SERVER REQUEST on the same pipe (`item/commandExecution/requestApproval`,
`item/fileChange/requestApproval`; v1 `execCommandApproval`/`applyPatchApproval` → approved/denied), so it is answered directly:
`Record.pendingApproval` → the row's `.waitingForPermission` → the notch's Allow/Deny → `AgentSessionMonitor.answer` →
`WindowlessSessionManager.answerApproval` writes the reply with the request id echoed in its own JSON type. Every other server
request gets a JSON-RPC error (`-32601`) — unanswered, the server would wait forever.
Shape: `Core/Agents/CodexAppServer.swift` (pure, symlinked, 4 tests): builders, line parser, binary candidates
(`~/.local/bin/codex` is the standalone installer's link — measured). `WindowlessRules.Record` gained `agent`, `threadID`,
`activeTurnID`, `pendingApproval` and `applyCodex(_:)` (a Codex turn is counted once — by `sent` — not again on completion;
mutation proved it). `WindowlessSessionManager`: `spawn(...)` shared by both agents, `startCodex` (the first message is held
until the thread exists, then becomes the first `turn/start`), Codex branch in `deliver` (no new turn while an approval is open),
`interrupt` over the protocol (`turn/interrupt` with the turn id — a SIGINT would end the whole app-server), `consumeCodex`.
Codex sessions are not added to the windowless history (no windowless reopen for Codex yet).
Wired: the notch "+" composer picks Claude Code or Codex; handing off to Codex now opens a windowless Codex session (P9 copied a
command before). E2E with a stand-in app-server through the PRODUCTION manager 17/17 (handshake order, policy, first message
after the thread with Vietnamese + newline intact, unsupported request answered, approval card, decline on the pipe, one turn
counted, second turn, interrupt with the turn id, stop ends the process). Mutations (decision flipped, double count, server
requests unrecognised) red. **No real Codex turn was run** — T-P11-*.

## P12 research (2026-10-14) — continuing work when an agent runs out of quota; the agent-mail-kit audit

Proposal: `docs/P12_PROPOSAL_2026-10-14.md` (Vietnamese, for the owner). Not built yet; Q-P12-1…6 in the pending list.
* **There is no "sync" between agents** — only a handoff (new session primed with a digest). Neither Notch Crew nor OneNotch
  switches agents on a limit (strings measured): Notch Crew's hand-off is manual per session; OneNotch sells reset credits.
* **The owner's downloaded `agent-mail-kit` fails on its first task**: `codex exec --full-auto` does not exist in codex 0.155.0
  (`error: unexpected argument`), and the worker mails the error to the Boss as a "report" and archives the task. Also
  reproduced in a fake HOME: branch checkout inside the person's own tree sweeps uncommitted work into the AI commit; `|| true`
  lands commits on main; worker and verifier race one tree; the verifier is told, not sandboxed, not to write; `/bin/bash`
  3.2 with LANG unset splits Vietnamese mid-character. Correct flags: worker `-s workspace-write` (`--approve-for-me` only by
  choice), verifier `-s read-only`; never `--dangerously-bypass-approvals-and-sandbox` (one review agent proposed it — it
  turns the sandbox off).
* **Measured with no model turn: `codex sandbox [-c sandbox_mode=…] -- <cmd>` runs a command under the seatbelt policy.**
  read-only (also the default) ⇒ `touch` gets "Operation not permitted"; workspace-write ⇒ the write lands (positive control).
  Use it to prove a sandbox claim before shipping a read-only Codex role.
* Quota signals that mean "blocked", not "slow": Claude `StopFailure` hook matcher `rate_limit` (docs; XFinder's hook does
  NOT subscribe it yet), transcript lines `isApiErrorMessage` + `error: "rate_limit"` + `apiErrorStatus: 429` (16 here, keys
  only); Codex `turn/completed` `failed` + `codexErrorInfo` `usageLimitExceeded` (schema; XFinder reads only the message
  today). A `system/api_retry` rate_limit is retryable and must never trigger a "quota" notice. Claude Code has its own
  auto-resume after reset (Notification `quota_auto_resume_*`, docs). Today a quota-failed windowless turn shows as
  "Tới lượt bạn" — `session(for:)` ignores `lastError`.
* Review-agent output that read "test" in every field came from one design agent; the workflow kept going and the judges
  scored the junk. Read the journal before trusting a panel: one placeholder answer silently skews every later stage.

## Notch "open" buttons dead (2026-10-14, `203b158`) — `NSRunningApplication.activate` is ignored from the notch

Owner: the agent row's open button did nothing. The hook had the right bundle id (`com.anthropic.claudefordesktop`) and the
app was running; the call was the failure. Since macOS 14 activation is cooperative — `activate(options:)` from an app
that is not itself active is ignored, and the notch is a non-activating panel, so XFinder is never active. Same bug in
"Copy and open app", the clip's "Go to source" and Now Playing's "open player". All four now go through
`AgentSessionMonitor.bringForward(bundleID:)` = `NSWorkspace.openApplication(at:configuration:)` with `activates = true`.
**Rule: from any non-activating panel, bring another app forward through LaunchServices, never `activate(options:)`.**
**Verified by the owner by hand (2026-10-14): the agent row's open button now brings the Claude app forward.**
Still using `activate`: WindowManager / CommandTabController (⌘-Tab switcher, AX raise first) and ClipboardPasteEngine
(re-activating the previous app before ⌘V) — same hazard, not changed in this fix, not measured.

## P12.1–5 (2026-10-14) — a session that stopped at a usage limit, and the handoff it offers

Owner chose Q-P12-1 = (a). Defaults taken for Q-P12-2…5 as proposed; Q-P12-7 new (the limit notice ignores "quiet when the
terminal is in front": the terminal shows the error, not the way out).
* **`StopFailure` runs INSTEAD of `Stop`** when a turn ends on an API error (docs, hooks.md; fields `error`,
  `error_details`, `last_assistant_message`). The rules treated it as a no-op, so such a session stayed "running" until the
  15-minute staleness rule. Now any StopFailure ends the turn; `error == "rate_limit"` sets `AgentSession.limitStop`.
  `quota_auto_resume_fired` (Claude Code continued by itself) and `_stale` lift it; `_disabled` keeps it. The installer
  appends `("StopFailure", 10)` LAST — existing installs read "partial" until the person presses Install/Update.
  Measured: the real hook script with HOME in the scratchpad keeps `error`/`error_details` and drops `last_assistant_message`.
* **Codex:** `CodexAppServer.Event.turnCompleted` gained `code` = `codexErrorInfo` (plain string, or the key of the one-key
  object); `Record.lastErrorCode` only on a failed turn, cleared by `sent`/`turnStarted`; `usageLimitExceeded` ⇒ limitStop
  in `session(for:)`, kept through `merged` when the hook row has none. `rateLimitExceeded` is not a stop (Q-P12-2).
* `AgentQuotaRules` (pure, symlinked): `Headroom` available/exhausted/unknown from the usage snapshot only while it is
  ≤ 10 min old and only from current windows; figures are never compared across agents — `suggestTarget` excludes the
  stopped agent, a known-100 % agent and an agent not installed, prefers known room over unknown, else AgentKind order.
* `AgentNotify.limitStopped` once per stop (keyed on `since`), never also "finished"; `LiveActivity.Button.handOff`
  opens the existing `beginHandoff(_:to:)` preview — nothing is sent until the person presses Gửi. Key
  `agents.notify.quotaBlocked` (default on, ONE reader in AgentSessionMonitor, FeatureKeyDefaultsTests row).
* `AgentHandoff.SourceState` replaces `wasWorking: Bool` (a finished turn and a pending approval used to read the same):
  working / finishedTurn / waitingForAnswer / waitingForApproval(tool, summary cut at 300) / limitStop / ended, plus
  "still open — leave the files below alone" for a non-ended source and a "Full log" path section (Notch Crew's shape).
Gates: 1166 tests / 0 (+10) · agents mutations Q1–Q16 added · L10n +5 add-only (`add-p12-l10n-entries.py`), every gate 0 ·
runtime L10n on the installed bundle 0 leaks · installed dylib == build. **No real limit hit was observed** — T-P12-*.
**P12 review (4 lenses, 2 refuters each, 16 agents): 6 findings, all confirmed by both refuters, all fixed.**
| Finding | Fix |
|:--|:--|
| A `PermissionRequest` after a limit stop was hidden: row "Chạm giới hạn", handoff state `.limitStop`, and `AgentNotify` took the limit branch and `continue`d — no approval notice, the hook blocks Claude Code up to 3600 s (high) | `.permissionRequest`/`.permissionDenied` clear `limitStop`; every reader goes through `AgentSession.isLimitStopped` (= stop AND `.waitingForInput`). Test + Q17 |
| A Codex `turn/start` the server refuses (`requestFailed`) never gets `turn/completed`: row "working" forever, `deliver` refuses every later message (high, P11-era) | `applyCodex(.requestFailed)` moves `.working` with no active turn to `.waiting`; the manager tells the crew relay the turn ended. A refused request while a turn runs leaves it alone. Test + Q18 |
| The Codex stop's `since` was `updatedAt`, which any later event moves: the same stop was announced again on every rebuild | `Record.lastErrorAt` set with the code; `since` uses it. Test + Q19 |
| `LiveActivity.Queue` replaces a same-kind notice: a "finished" notice wiped a limit-stop notice before it was seen | for `.agent` notices a higher-urgency tint (bad > warning > good) is not replaced by a lower one — the lower one queues. Other kinds keep "newest wins". Test + Q20 |
| The settings subtitle promised the button always targets an agent "còn hạn mức" — false when no other agent is installed or all room is unknown | reworded: "if another agent is installed… one known to have room first" (new key; the old one, added in this pass, removed from the store) |
**Trap: never edit a source file while a mutation harness runs** — its EXIT/restore copies the backup taken at its start over
the working tree. This time the harness had already aborted on its own (my first P12 edit had moved the A64/Q8 anchors —
it stopped with HARNESS ERROR instead of reading green), so nothing was lost; the fix edits were checked by grep before the
re-run. Reviewers were given a clean snapshot built from the harness backup (`scratchpad/p12/review/`), never the live tree.

## P13 (2026-10-14, `3116e8f` · `ba27c89`) — snap drags qualified by the window server; one System Monitor page; the menu-bar popover is a native menu

* **Snap by drag was dead, only the hotkeys worked.** The press-time AX qualification walked 4 parents looking for
  AXWindow/AXToolbar; measured on 8 apps, the window is 5–7 parents up in 6 of them, so every title-bar drag was
  rejected. Widening the walk re-opens the text-selection/file-drag trap. Now `SnapLayout.DragQualifier` (pure): at press
  remember the layer-0 window under the pointer (CGWindowList, not ours, not the menu bar/Dock strip) and its origin; a
  window move once that origin shifts ≥ 1 pt, rejected after 40 pt of pointer travel with the window still. Mutations
  S5–S7 red. **Not verified by hand** (T-P13-1/2).
* **Theo dõi hệ thống** (owner pointed at MFinder's System Monitor): Hệ thống / Mạng / Ổ đĩa / Pin are tabs of one row.
  `SidebarDestination.monitorTabs/monitorRow/tabTitleKey/searchAlsoKeys`, `AppState.monitorTab` + `select()` (a deep
  link to `.network` opens the page on Mạng; `List(selection:)` only ever holds `.system`), `pageHeaderHidden` env so the
  tab pages keep their own code. C10 in mutation-check-settings.
* **The menu-bar popover is now a plain NSMenu rebuilt on open** (owner: one page like OneNotch's menu, system figures in
  Settings only, better performance). The old popover retained the metrics sampler, the battery store, the volume
  observer and the audio-device list on EVERY open and ran `diskutil` for SMART. Rows read one value when the menu is
  built; a chord is drawn only while it fires (`ClipboardShelfController.tapIsLive`, `CaptureController.isEnabled`,
  Translate's switch); screen actions wait 0.2 s so the fading menu is not in the picture.
* **Restart, measured:** a detached `/bin/sh` waits ≤ 30 s for the pid to exit, then `open`s the bundle; a throw-away
  LaunchServices app relaunched itself 0.84 s after quitting (pid 28625 → 28992) — the child survives the parent's
  terminate. A cancelled quit opens nothing.
* Readouts config moved to Tổng quan (switch via FeatureHub, cadence + figures via MenuBarReadoutsController); the catalog
  subtitle that pointed at the popover's eye button was rewritten. `FlyoutLayout` + tests removed.
* **Commit trap:** `git rm` staged the FlyoutLayout deletions BEFORE the first (snap) commit, so the snap commit took
  them while its pbxproj still listed the file — a commit that cannot build. Caught by `git show --stat`, redone with
  `reset --soft HEAD~2` (unpushed), and the snap commit was then built alone in a worktree (BUILD SUCCEEDED).
  **Rule: run `git diff --cached --stat` before every commit when earlier commands staged anything.**
* Review agents left 5 probe files in the repo root again (`axprobe`, `dump1.txt`, `probe.swift`, `probe_ax_point*`) —
  moved to the scratchpad. Untracked root files from 12:30 (`assets_info.json`, `binary_strings.txt`, `defaults_dump.txt`,
  `full.plist`, `strings/`) are of unknown origin and were left alone, never staged.

### P13b (2026-10-14) — OneNotch comparison (17 screenshots) and the duplicates merge

* **Comparison**: 3 workflows, one agent per OneNotch screen + one adversarial verifier per screen. Result table with codes
  OC-1…OC-77 in `docs/ONENOTCH_COMPARE_2026-10-14.md`; the owner picks codes (Q-OC). Nothing from it is built yet except the
  duplicates merge. Facts worth keeping: XFinder has NO bulk "clear clipboard history" anywhere (OC-4); the volume HUD bar is
  hard-coded `.tint(.white)` and ignores `notch.accent` (OC-47, a real inconsistency); `screencapture -C` (cursor) and `-o`
  (no window shadow) are one-flag gaps (OC-18/OC-20); XFinder can hide its Dock icon but not its own status item (OC-65).
* **Two agents returned the literal placeholder "test"** (the menu map, and the Quick Look merge verifier) — the same junk
  shape as in P12. A verify step that returns "test" is not a pass: those two were redone by hand. Read every agent's result,
  never only the aggregate.
* **Duplicates merge** (owner: "gộp cái nào duplicates"). Key-level scan first: no settings key has two WRITING controls
  (only `capture.annotate.color/width`: settings default + the editor remembering the last choice — both read live). Then a
  page-level audit (7 clusters, each change verified): Tìm kiếm + Tìm kiếm AI and Quick Look + Tương thích media became
  tabbed rows; Tổng quan's two permission rows (a thinner copy of the Quyền tab) became one row that opens the hub ON the
  Quyền tab (`AppState.hubShowsPermissions`); Tiện ích Finder lost its prose section that restated three other pages; the
  page "Biểu tượng thanh menu" (hides OTHER apps' icons) and the Tổng quan row of the same name (XFinder's own glyph) were
  renamed apart. Kept on purpose: Clipboard Library (a full-width browser — rail + grid + inspector — cannot live in a tab),
  Cảnh báo, the six NOTCH pages, every CỬA SỔ/CÔNG CỤ/KẾT NỐI page.
* The tab mechanism is general now: `SidebarDestination.tabGroups` (first member = the row), `hostRow`, `tabTitleKey`,
  `tabbedSubtitleKey`, `searchAlsoKeys`; `AppState.openTab[row]`; `Views/Detail/TabbedPage.swift` (renamed from
  SystemMonitorPage); `DetailHostView.page(for:)` builds any page so a tab row reuses the same routing. Test: every group has
  2–4 members (segmented picker), each page in at most one group, tabs absent from the sidebar groups, titles in the store.
  Mutation C10 re-anchored on `hostRow` (11 failing). Settings harness 15/15 RED.

### P13c (2026-10-14) — a four-corner tile on the notch snap row; a tap per clipboard card

* `SnapLayout.RowItem` (`.single(Target)` / `.quarters`) replaces `rowTargets`; `rowItems` has 8 tiles (halves, **four
  corners**, thirds, focus, maximize). `rowTarget(item:tile:point:)`: inside the four-corner tile the quadrant under the
  pointer picks the corner — AppKit space, so the upper half (larger y) is "top". `Decision.row(tile:target:)` carries the
  layout, the controller taps on every target change (existing `snapzones.haptic`, `.alignment`), so moving between corners
  taps too; the tile draws all four corners and fills the live one. Tests + S8 (quadrant upside down) / S9 (tile gone): 9/9.
* Card haptic: `clipboard.cardHaptic` (default on, ONE reader `ClipboardSounds.cardHapticOn`), `.scrollPosition(id:)` +
  `.scrollTargetLayout()` (macOS 14) on the notch deck and the floating shelf; `NotchClipboardRules.cardChanged` (pure) taps
  only when one listed card gives way to another — not on first appearance, not when a filter replaces the list. D33.
  **`.scrollTargetLayout()` must sit directly on the LazyHStack**, before any padding — it configures the OUTERMOST layout of
  the view it is applied to. Haptics are felt only on a Force Touch trackpad under a finger; nothing here can measure that.

## Chẩn đoán & báo lỗi (2026-10-14) — local-first, nothing leaves the Mac by itself

Owner asked whether the plan had crash/feedback analytics "theo luật hiện tại". It did not: the plan said "0 telemetry"
and there was NO crash or feedback channel at all. Built the local half; automatic sending is Q-DIAG (needs the owner's
vendor account + a consent screen). Plan §3g has the table.

* `Core/Diagnostics/DiagnosticsRules.swift` (pure, symlinked, 11 tests): safe-word events (`[A-Za-z0-9._-]{1,48}` for
  area/code — a path or sentence is refused, not stored), redaction (home → `~`, `/Users/<x>` → `/Users/…`, e-mail,
  UUID), a 300-event ring, unclean-exit detection (last `app/launch` with no `app/quit` after it), `.ips` → `CrashSummary`
  built FIELD BY FIELD from an allowlist, the report text (English, technical), and a GitHub new-issue URL that carries
  only version numbers (the report travels by clipboard).
* `DiagnosticsLog` (nonisolated enum, one serial utility queue): ONE reader of `diagnostics.localLog` (default **on**:
  codes only, 0600 file in a 0700 folder, trimmed past 64 KB). `record(..., waitUntilWritten: true)` for the quit
  marker — an async write queued in `applicationWillTerminate` would be lost at exit and every next launch would read as
  a crash.
* `DiagnosticsCenter` (@MainActor): MetricKit subscriber (`MetricKitSink`, a stateless `NSObject, Sendable` — the one
  allowed superclass for a Sendable class) that converts payloads to summaries on MetricKit's queue; reads the newest 3
  `XFinder*.ips` (30 days, < 4 MB) from `~/Library/Logs/DiagnosticReports`; system info (versions, `hw.model`, arch, UI
  language, `AppPermission.rawValue: granted`, `FeatureID.rawValue`s on). `ArchiveRunner.Failure.diagnosticCode` lives
  here, not in ArchiveRunner — ArchiveRunner is in the test package, and a test exercising failure paths must never
  write to the person's real log.
* Record sites: 6 event-tap timeouts (`.tapDisabledByTimeout` only — user-input disables are normal), Now Playing helper
  not run / gave up, capture tool not run, snap `noWindow` / `axError` (AX error numbers only), archive failures on the
  Nén page and the notch ZIP, app launch/quit/uncleanExit, MetricKit received. **Not** GestureEngine: a standalone
  harness compiles its callback with a fixed file list.
* UI: Giới thiệu ▸ Hỗ trợ & báo lỗi (preview the exact text in a 220-pt selectable box, then Sao chép / Lưu tệp… /
  Mở GitHub Issues / Đóng; switch + Xoá nhật ký). Menu ▸ Trợ giúp ▸ Báo lỗi… sets `AppState.aboutShowsReport` and
  navigates (same pattern as `hubShowsPermissions`). AboutView is now a ScrollView (it was a fixed 400×470 frame). An
  inline preview, not a sheet: an open SwiftUI sheet blocks `NSApp.terminate` (measured in N7).
* Measured before writing: macOS 27 `.ips` = one header JSON line + a body; this Mac's three XFinder reports are
  launch-constraint kills (`CODESIGNING`, "Launch Constraint Violation") from old probe copies, with EMPTY `app_version`
  in the header — the summary falls back to `bundleInfo`. Image entries carry a `path` (may be under `/Users/<name>`)
  and frames may carry a `sourceFile` path: the summary keeps the image NAME and the file's last component only.
* Law, researched 2026-10-14: VN PDPL 91/2025/QH15 (in force 2026-01-01) + Decree 356/2025 — behaviour-tracking/usage
  data is SENSITIVE personal data (specific, withdrawable consent per purpose; cross-border transfer needs a prior impact
  assessment filed with A05; de-identified data is out of scope). EU ePrivacy 5(3): opt-in for any read/send from the
  device; legitimate interest does not replace it; an IP address is personal data. Apple does not forward crash reports
  to developers of apps distributed outside the App Store — without this feature the developer saw NOTHING.
* Harness trap: in a shell double-quoted mutation anchor, `$0` in Swift closure syntax (`{ $0.area … }`) is expanded by
  the shell to the script's name — the run aborted with "anchor not found" (correctly, not green). Escape as `\$0`.
* Shipped as `d1df509` (pushed). Measured on the installed app: clean quit (AppleScript) ⇒ `app/quit`, next launch adds
  nothing; `kill -9` ⇒ next launch records `app/uncleanExit`; folder 0700 / file 0600; the rendered report (AX dump) has
  0 occurrences of the username or `/Users/`. This Mac's three XFinder `.ips` are launch-constraint SIGKILLs with an empty
  frames array (the process never ran) — the report lists them with their reason, honestly, as "crash · report".
* Two harness bugs of my own before 9/9: `$0` expanded by the shell (above), and a Swift `"\n"` in an anchor needs FOUR
  backslashes in the shell string (shell halves them, then `ast.literal_eval` halves them again). Both aborted with
  "anchor not found" — never read green.
* My slip: the AX press of "Report a bug…" ran while HID idle was 0 s (I printed idle but did not gate on it), so the
  owner's window jumped to Giới thiệu with the preview open. Gate UI actions on idle ≥ 20 s BEFORE acting, not after.

## Opt-out analytics + reviewing another agent's work (2026-10-14 evening)

Owner: "Q-DIAG để mặc định… thêm option cho user từ chối gửi analytics… mặc định dòng đó luôn là tắt, và tự gửi analytics".
So: anonymous analytics ON by default, ONE switch "Từ chối gửi phân tích ẩn danh" (`analytics.optOut`, default false, ONE
reader `AnalyticsCenter.isOptedOut`). Research (workflow, 4 web researchers): VN PDPL 91/2025 Art. 2 — de-identified data is
not personal data; GDPR Recital 26; ePrivacy 5(3) still applies to reading device info, CNIL's audience-measurement
exemption is the closest consent-free route (narrow purpose, anonymous stats, no cross-referencing, notice + easy objection);
Homebrew/VS Code/Firefox precedents (notice BEFORE the first send). TelemetryDeck v2 ingest measured from its docs:
`POST https://nom.telemetrydeck.com/v2/namespace/<namespace>/`, JSON ARRAY of signals `{appID, clientUser, type,
isTestMode?, payload: flat primitives}`; App ID and namespace are public dashboard values; IP not stored (privacy FAQ);
cold-storage retention "7–10 years" (FAQ) — Q-DIAG-5. No SDK (hand-written pbxproj): a plain ephemeral URLSession POST.

* `Core/Diagnostics/AnalyticsRules.swift` (pure, symlinked, 11 tests, harness N1–N9): `Report` with a PINNED field set
  (`testTheReportCarriesExactlyTheseFields` — a new field needs `schemaVersion + 1`, which re-shows the notice), tokens only
  (`isToken`: letters/digits/`. _-,:+()` space, ≤80, NO `/`; frames get their own set incl. `#<>[]$&?!'=*` but never `/ \ ~ @`),
  error codes counted since the last report, crash frames stripped of offset and source location, `nextAction` (opt-out →
  not configured → notice → 24 h grace → 1/day → 1 h retry after a failure; a "future" stamp counts as elapsed),
  `telemetryDeckBody` (`Report.daily` + one `Report.crash` per crash, no sessionID, caller's fresh clientUser).
* **The planted-identifier test caught my own leak**: `isToken` first allowed `/` (for "area/code"), so `model =
  "/Users/alice"` passed. Fixed by building the `area/code` key from two separately checked words.
* `AnalyticsCenter` (@MainActor): receiver from Info.plist `XFAnalyticsTelemetryDeckAppID` / `…Namespace` (EMPTY ⇒ nothing
  sent or announced, page says so — Q-DIAG-4), one-time NSAlert (Đã hiểu / Từ chối gửi / Xem dữ liệu…), SHA-256 of a fresh
  UUID per send as clientUser, `isTestMode` = DEBUG, evaluated 5 s after launch and on every didBecomeActive — no timer.
* Privacy copy that said "100% cục bộ / không tự gửi gì" (About description, support line, clipboard note, README) rewritten:
  the sentences now say what is true in every configuration.

**Another agent (Antigravity/Gemini) worked while I was out of quota (20:38–22:30), and committed my uncommitted work.**
The owner pasted its transcript with no instruction; I reviewed it like a PR. Its commit `42a9578` held my analytics code
byte-identical to my pre-harness snapshot plus one useful test line (it closed mutation N6, GREEN in my run → 18/18 after),
but also three untracked owner docs; it was redone with `reset --soft` and those docs went back to untracked. Its own
four changes, judged one by one:
* **Page jump (Library, System monitor): right root cause.** `.pageWidthSafe()` ended with `fixedSize(horizontal: false,
  vertical: true)`, forcing a page to its IDEAL height (~1 100 pt) in a ~630 pt window; the split view centred it — header
  and tabs above the window, sidebar search y −28/−75 instead of 196 (its AX measurement). Kept, plus `minHeight/idealHeight
  0` frames. Its `hosting.sizingOptions = []` is right too — measured: the default is `standardBounds` (raw 7: min +
  intrinsic + max), so the window followed SwiftUI's ideal size — but it also dropped the 900×600 minimum: added
  `win.contentMinSize = 900×600` (the old 760×500 frame minimum was always overridden by SwiftUI's).
* **Chống ngủ page removed: claimed a hub "card" that did not exist** — the hub only embeds SystemControlsPanel's
  indefinite switch, so the duration presets and the countdown were gone. Folded both into that row
  (`SystemControlsPanel.antiSleepRow`: menu picker Vô hạn/15 phút/1 giờ/2 giờ, disabled while on, "Còn mm:ss" in orange);
  the unreachable `AntiSleepDetailView.swift` deleted with its 4 pbxproj lines; `.antiSleep` stays as a route to `.features`.
* **Notch showed a limited Claude session as running: real.** Measured in today's hook log: no `StopFailure` event all day;
  the desktop session's limit (13:41:29Z) left only a `UserPromptSubmit` carrying the subagents' failure text. Its fix
  matched "hit your session limit" in the PROMPT — a false positive the moment the owner pasted text quoting it (22:32,
  measured in the same log), plus an invented notification type `quota_auto_resume_waiting` (the docs list only
  fired/stale/disabled). Replaced: Claude writes the refusal into the transcript — `type: assistant, isApiErrorMessage:
  true, error: "rate_limit", apiErrorStatus: 429, apiError: "usage_limit_reached", quotaLimits {status: "rejected",
  resetsAt: <epoch>, rateLimitType: "five_hour"}`. `AgentSessionRules.transcriptLimit(tail:)` (last verdict wins; a real
  answer lifts it; sidechains and other API errors ignored) + `applyingTranscriptLimit` (only a running Claude row whose
  last hook event is not after the refusal) + `shouldReadTranscript` (silent ≥ 3 s, path must be a `.jsonl` under
  `~/.claude/projects`); the monitor reads the last 64 KB, cached by size+mtime, on rebuild (event or 20 s liveness tick).
  8 tests incl. "a prompt quoting the limit text is not a limit stop"; harness Q21–Q25.
* Its `docs/AGENT_HANDOFF.md` is left untracked: it claims the hub card, a test that does not exist and wrong hook paths.
* Desktop app facts (claude-code-guide, docs): the session-limit card has an **Auto-continue when limits reset** checkbox;
  the CLI continues automatically by default (`autoContinueAtUsageLimit`, v2.1.234+); Claude Code reads AGENTS.md only when
  no CLAUDE.md exists.
* For other agents: `docs/AGENT_QUICKSTART.md` (short current rules), `docs/KHI_CLAUDE_HET_QUOTA.md` (owner guide),
  `docs/AGENT_WORKLOG.md` (they log there), and a pointer at the top of AGENTS.md. Measured rules-file order: Zed uses the
  FIRST of `.rules … AGENTS.md, CLAUDE.md, GEMINI.md`; OpenCode reads AGENTS.md (CLAUDE.md only as fallback); Antigravity
  combines AGENTS.md + GEMINI.md + `.agents/rules` and never reads CLAUDE.md. A research claim that "Zed's DeepSeek has no
  tool use" was NOT in the current docs (which list DeepSeek V4, 1 M context) — checked before repeating it.
* Process: the review workflow died on the session limit (5 lenses × "You've hit your session limit"); a workflow
  verifier without WebFetch marked everything "unverifiable" and argued with the owner's request — read verifier output
  critically, and re-fetch load-bearing facts yourself.
* **Shipped (pushed) as six topic commits:** `9e509b3` analytics (the other agent's commit redone) · `8420a5e` layout ·
  `ea7bbcc` Chống ngủ row · `f1e822b` usage limit from the transcript · `b0526c5` harness signal fix · `974359c` docs.
  The two intermediate commits (layout, Chống ngủ) were each built alone in a throw-away worktree (both SUCCEEDED),
  LaunchServices unregistered before deleting. Gates on the final tree: 1195 tests / 0; harnesses diagnostics 18/18,
  agents 115/115 (+ Q21–Q26 6/6 after the review fixes), settings 15/15; L10n 2 777 entries, every gate 0; installed dylib
  == build; runtime L10n 0 leaks. Review (4 lenses × 2 skeptics): 4 confirmed + 1 split, all fixed — crash summaries
  bypassed the local-log switch (high), the receiver's claims stated as ours, a later different API error kept an old
  refusal, a symlink escape in the transcript path check, VoiceOver missing the anti-sleep state. The layout lens returned
  nothing (one agent came back empty) — that is not evidence the layout is clean; T-LAYOUT-1 is a hand test.
* **Live measurement was impossible**: the owner was away and the screen LOCKED (ioreg `CGSSessionScreenIsLocked`) — AX
  probes return nothing valid then. My `open xfinder://settings?page=…` calls ran before I checked; they only switched the
  page. Check the lock BEFORE sending any URL or AX probe.
* **Harness trap, fixed in 14 scripts:** `trap 'restore' EXIT INT TERM` made sh restore the files on SIGTERM and then
  CONTINUE — `pkill` on a harness did not stop it, and a second copy started meanwhile read the first one's mutants as
  "baseline failures: 3". Now `trap 'restore' EXIT` + `trap 'exit 143' INT TERM`; proven by TERM-ing a run after its first
  mutation (exited, sources byte-identical). Note sh runs a trap only after the current foreground child (swift test)
  returns — to stop at once, kill the child too.
* Review agents littered the repo root again (`t/probe*.swift`, `victim/secrets.txt` — a fake fixture for the symlink
  test) despite the scratchpad rule; moved to the scratchpad. Two LaunchServices records from September
  (`XFinderSync 2026-09-21 20-05-27/XFinder.app`, `~/Desktop/XFinder-build/out/XFinder.app`) are pre-existing, not touched.

## Analytics receiver configured (2026-10-15 00:2x)

Owner: App ID `EDD21AF7-EFBA-4AF9-A3C0-E3B424F36B62`, namespace `com.xfinder` → Info.plist. The validator accepted only
`[a-z0-9-]`, so the dotted namespace would have read as "not configured" and nothing would ever be sent — widened to
`[a-z0-9.-]` with no leading dot and no `..` (tests + mutation N10; diagnostics harness 19/19). **Measured: TelemetryDeck's
ingest answers HTTP 200 "OK" even for a made-up namespace** (one test-mode `Setup.verify` signal to `com.xfinder` and one to
`zz-no-such-namespace-probe`, both 200) — a 2xx proves nothing about the namespace; only the dashboard does (T-ANALYTICS-5).
The installed app is a Debug build ⇒ its reports are `isTestMode: true`. After install the one-time notice appeared at once
(XFinder window at layer 8, 520×279 = the NSAlert); `analytics.noticeShownAt` is written only when a button is pressed.
Correction: AnalyticsRulesTests has 10 tests, not 11 as the earlier commit message said. `docs/AGENT_HANDOFF.md` moved to
the Trash at the owner's request.

## Agent task board (2026-10-15, `8a87712`) — how other agents work while Claude is out of quota

`docs/AGENT_TASKS.md` is the ONE place another agent takes work from: §1 a measurable "small" rubric (≤3 source files + 1
test, ≤~150 lines, no new file under `XFinder/` — a new test file in the package is fine —, verifiable without opening the
app, no forbidden area, no product decision; one-line test: *if you must open the app, grant a permission or look at the
screen to know it is right, it is not small*), §2 forbidden files, §3 the 8-step procedure (branch `agent/<tool>-<ID>`,
status in the board, acceptance + build-and-check + swift test, explicit-path commit, worklog, stop — never push/merge),
§4 Claude's review procedure, §5 state, §6 the queue (T01–T12), §7 items waiting for the owner (OC-47/18/20), §8 Claude-only.
The quota guide, the quickstart and AGENTS.md point at it. **When Claude returns: read the worklog, `git branch --list
'agent/*'`, review per §4, then refresh §5/§6 before ending the session.**

How the queue was built: a 22-agent workflow (finders per area, one adversarial checker per candidate), then every
accepted site re-read by hand. Two checker drafts were wrong and are corrected in the board: a VoiceOver label on a SwiftUI
`Menu` must sit on the `Image` inside `label:` (P9 measured the Menu's own label ignored) — the checker had put it after
`.help` on the Menu; and warning counts from `build-and-check` are not an acceptance test (its derived-data dir is
incremental, so only recompiled files report warnings) — use source greps. Two checkers caught real drafting errors of
their own finders: `.item` as a stand-in UTType (opens the panel to every file) and a fabricated "12 → 9 warnings" count.
`audit-l10n-literals.py` cannot see diacritic-free Vietnamese ("Ghim") — the EdgeNotes leak (T05) is checked by reading the diff.

## Agent board without a size limit (2026-10-15, `97fe8ab`)

Owner: "Không giới hạn việc nhỏ nữa". The board now follows the split the sources agree on — Claude Code best practices
(code.claude.com/docs/en/best-practices: explore → plan → code; writer/reviewer sessions because "a fresh context improves
code review"; after two failed corrections, start fresh; worktrees for parallel sessions) and Aider's architect/editor split
(aider.chat 2024-09-26: o1-preview + o1-mini/DeepSeek editor 85 %, DeepSeek "surprisingly effective as an Editor model").
Claude writes specs and reviews; other agents implement any size; size only adds gates (M: plutil -lint + compile-log check
per new file + named harness; L: M steps, one commit each). Parallel agents use worktrees but builds/harnesses run one at a
time (shared /tmp/xfinder-clean-build; harnesses edit sources). Forbidden list trimmed to data/privacy/release risks.
AGENTS.md (148 KB, loaded by OpenCode/Zed/Antigravity every session) moved to docs/PROJECT_NOTES_2026-10-13.md; AGENTS.md is a
1.4 KB pointer. The Reddit MCP server failed for every subreddit during the research (server-side), so the Reddit-flavoured
claims came second-hand through blogs — say so when quoting them.
Mouse & Gestures redesign is at gate 1 (brief sent); its 7 view files are marked off-limits in the board's §5. Found while
auditing it: the "Ghi nút" next to "Nút cuộn" records the HOLD button (engine only writes `configuration.trigger`).

## Gesture presets keyed by the wrong bundle ids (2026-10-15)

Found by the wireframe data pass, then measured with `mdfind` + Info.plist: 8 of 20 presets used ids no installed app has
(Claude `com.anthropic.claude` → `com.anthropic.claudefordesktop`, VS Code → `com.microsoft.VSCode`, Cursor →
`com.todesktop.230313mzl4w4u92`, Antigravity → `com.google.antigravity`, CapCut → `com.lemon.lvoverseas`, AyuGram →
`one.ayugram.AyuGramDesktop`, Obsidian → `md.obsidian`, Notion → `notion.id`), so those apps silently used Global.
Fixed in `GestureProfiles.all`; `renamedBundleIDs` + `validate()` move overrides saved under an old id. Unit tests cannot
see this class (a fact about the Mac, not the code) — `scripts/check-gesture-bundle-ids.py` measures it (8 WRONG / exit 1
on the old table, 0 on the new). **Behaviour change:** Claude/VS Code/Cursor/Antigravity now get the Dev & AI preset (up/down
Unassigned, left/right ⌘[ ⌘]) instead of Global's Mission Control/Spaces — Q-MG-4. The installed app's gesture page lists
those apps in the installed group now (AX, measured). **Rule: a preset keyed by an external id is a claim about another
app — measure it on a real install before shipping it.**

## End of session 2026-10-15 — state for the next Claude

- `63bc3c3` Dev & AI up = Mission Control; `f9b8d5d` eight preset bundle ids; board refreshed (T14–T19) for DeepSeek.
- **Stopping a mutation harness with `pkill -TERM` (wrapper + xctest) left a mutant on disk** (`GestureLabelStructure.swift`,
  labels M1) even with the 2026-10-14 trap fix — the restore did not run. Always `git status` after stopping one and restore
  only files you never edited; better: let harnesses finish before committing.
- Mouse & Gestures redesign: gate 1 passed; wireframes A/B/C/D in `~/github/XFinder-design/mouse-gestures-2026-10-15/`
  (also the scratchpad `mg/wf/`), contract + data + inventory there. Phase-2/D workflows were still fixing when the
  session ended — check the variant files' state, re-run review if needed, then gate 2.

## Review of DeepSeek's run while Claude was out of quota (2026-10-15 afternoon)

DeepSeek (Zed + OpenCode) ran the §6 queue (T01–T06, T08–T13, T15, T16, T18, T19) and, on the owner's direct request, built
a feature that was on no board: **"Chỉ dùng notch cho độ sáng và âm lượng"** — a `.cghidEventTap` on NX system-defined keys
(type 14, subtype 8) that swallows brightness/volume keys and applies them itself so macOS draws no square
(`Core/Notch/SystemKeyInterceptor.swift`, `LiveActivity.HUDSuppression`, brightness via the private DisplayServices).
The owner forbade commits, so everything sat in 29 uncommitted files on `main`; Claude split it into topic commits.

**DisplayServices DOES read and write from an ordinary process — two earlier claims in this file were wrong.**
Measured by Claude (probe from a terminal, macOS 27, M3 Pro built-in panel): `DisplayServicesCanChangeBrightness` true,
`DisplayServicesGetBrightness` 0 / 1.0 in 0.86 ms; `SetBrightness(0.95)` returns 0 and **a separate process** then reads
0.95 — so it is system state, not a per-process cache; restored to 1.0. The "Độ sáng %" notes above ("registry kẹt, không
đọc lại được", "DisplayServicesGet/Set trả false cho process thường") are superseded: the IOKit `IODisplayParameters` read
is what is frozen. `ScreenBrightness` now reads/writes DisplayServices first, IOKit then NX keys as fallbacks.

**Six real bugs in the agent's HUD feature, each a missing answer to a failure case** (fixed in the HUD commit):

| Bug | Fix |
|:--|:--|
| DOWN and UP decided independently: release ⌥ mid-press (down passed, up swallowed) or flip the switch mid-press (down swallowed, up passed) ⇒ macOS sees a half key | `HUDSuppression.Pairing` — the UP follows its DOWN; mutation M57 |
| ⌥⇧+volume (quarter steps) and ⌥+key (open Sound/Displays settings) swallowed and replaced by a plain 1/16 step | `modifiersHeld` ⇒ pass through (from `CGEvent.flags`; whether NX events carry the flags is NOT verified live); M58 |
| An output with no settable volume (HDMI, aggregate) ⇒ key swallowed, nothing happens, no feedback | `SystemControls.canSetVolume/canSetMute` (`AudioObjectIsPropertySettable`) ⇒ pass through so macOS shows its own "not available"; M59 |
| A press at 0 % / 100 % showed nothing (both items returned nil on "no change") — the key looked dead | `volumeItem(_:)` / `brightnessItem(level:)` unconditional; the interceptor presents when CoreAudio will not |
| Brightness stepped from `ScreenBrightness.level`, which only refreshes while a page retains it — after Control Centre / auto-brightness it was stale and the first press jumped | `refresh()` (live DisplayServices read) before stepping |
| The "Độ sáng" switch promised a notch readout that only exists while the HUD takeover is on | disabled unless the takeover is on, and its subtitle says so |

Also: the tap callback duplicated four readers (`notch.activities`, `notch.activity.volume/brightness`,
`dropTray.notchEnabled` as a stand-in for `canPresentActivities`). The tap's source is on the MAIN run loop, so the callback
now uses `MainActor.assumeIsolated` and the app's own readers (`LiveActivityMonitor.master/volumeOn/brightnessOn` made
internal, the real `canPresentActivities`). The page disabled the switch without saying why when Accessibility was missing;
the note now shows whenever trust is missing and refreshes on `didBecomeActive`. The agent's code comments said "measured on
this Mac" for a terminal probe — rewritten to say where it was measured (TCC judges the responsible process).
**T15** (scroll-button Picker): filtered on `declaredEventButtons ?? false`, i.e. an EMPTY menu whenever no mouse had been
measured, and dropped the stored value (a menu Picker with no matching tag renders blank) — fixed with `scrollButtonChoices`.
One false alarm of mine: the notch sort button's VoiceOver label uses `ClipboardSortOrder.titleVI`, which already calls
`L10n.t` — not a leak. Check a `titleVI` before calling it raw.

**Process changes from this review** (docs/AGENT_QUICKSTART.md rules 10–11, `scripts/gate-all.sh`, Q-PROC-1/2):
one command (`gate-all.sh`) whose output the agent pastes and Claude re-runs; a failure-case list written before coding any
feature; provenance on every measurement; per-task file lists in the worklog when commits are not allowed. The biggest
token cost of the review was untangling 17 tasks + a feature from one uncommitted tree — Q-PROC-1 asks the owner to allow
commits on `agent/*` branches.

## T14a review + Q-PROC-1 (2026-10-15 afternoon)

Owner approved **Q-PROC-1**: other agents commit on their own `agent/<tool>-<ID>` branch, one commit per task/step; a
multi-step task (T14) uses ONE branch (`agent/<tool>-T14`); never commit on `main`, push, merge, rebase or amend. Written
into AGENT_TASKS §0/§3, the quickstart's Git section, the owner's quota guide and the pending list.

DeepSeek did **T14a** (Mouse & Gestures body as variant B's nine blocks, each holding the old section; header switch
`.toggleStyle(.switch)`; a recording state on the status line; add-only `scripts/add-mouse-redesign-l10n-entries.py`)
uncommitted on main — committed as-is (`3ed7f13`), then reviewed by a 16-agent workflow (4 lenses, 2 refuters each).
Clean: every builder reachable before is reachable exactly once, the 13 moved builders byte-identical, block order right.
**One real defect (2 lenses, 4/4 refuters confirmed):** `GestureController.recording` is ONE Bool for both
`recordTrigger()` and `recordShortcut(bundle:direction:)` (shared `ensureRecordingEngine()`), so the new sentence "bấm nút
trên chuột" showed while a KEYBOARD shortcut was being recorded. Fixed by `GesturePageStatus` (pure, appended to
GestureLabelStructure.swift so the package can test it) — `recordingDirection != nil` ⇒ shortcut sentence. The engine's
shortcut recorder accepts ANY key (no modifier required; GestureEngine `.shortcut` case), so the Phím tắt page's
"phải có ⌘/⌥/⌃" sentence would have been false here. Esc (key 53) cancels both modes before the mode switch — the
"Esc để hủy" claim holds. Also: the app list (a 240-pt column inside the old HStack) became a full-width shaded box in
block 3 → capped at 360 pt until T14b; the header switch got the VoiceOver label wireframe B names ("Bật/tắt cử chỉ").
**Moving a sentence choice from a view into Core turns literal keys into variable-passed keys** — every literal sweep goes
blind to them, so the test resolves each `textKey` against the shipped store (the pattern used for gestures and P2).
**`mutation-check-gesture-labels.sh` had no restore trap and always exited 0** — the reason a pkill left labels M1 on disk
this morning, and why its verdicts were advisory. It now has `trap 'restore…' EXIT` + `trap 'exit 143' INT TERM`, counts
RED/TOTAL, and exits 1 unless every mutation is red, both sources are restored byte-identical and the suite is green.

## HUD takeover on by default (2026-10-15, `59d1b52`) — the "bug" was a switch nobody turned on

Owner, second time: "khi hoạt động thì tôi muốn ẩn HUD mặc định của macOS; brightness chưa lên notch". Measured before
touching code: `notch.activity.hideSystemHUD` ABSENT from the defaults domain (default false), and `CGGetEventTapList`
listed no XFinder tap on NX system-defined events (only universalaccessd's). So macOS kept drawing its square, and the
brightness notch bar never appeared because by design it exists only while XFinder takes the keys. Not a code defect.

**The OSD's signature on macOS 27:** a `MenuBarAgent` window, layer 101, 352×152 at the top right, appears within 1.5 s of
a volume key (probe posting `NSEvent.otherEvent(.systemDefined, subtype 8, data1 = key<<16 | 0xA<<8)` then 0xB at
`.cghidEventTap`, diffing CGWindowList every 50 ms). With the takeover ON in the installed app: XFinder's tap is listed
(location 0 = HID, mask 0x4000), 0 MenuBarAgent windows for volume up/down and brightness up/down, each step exactly 1/16,
and the notch's AX tree reads "Brightness 94%" 0.25 s after the key. Values restored after every probe. Real hardware keys
take the same HID path but no person has pressed them yet (T-HUD-1). Probe: `scratchpad/hud/hudprobe` (taps | state |
watch <keytype>).

Shipped: default ON (reader `?? true`, view `= true`), part of the "Hằng ngày" preset, and a `FeatureCatalog` row
`.systemHUD` (Accessibility, listensToKeyboard) — **a default-on event tap must be in the catalog or the hub's "Tắt tất cả"
reports everything off while it runs** (same rule as Now Playing's helper in the B6 review). Writing the key from a shell
does not arm the tap; activating XFinder does (`didBecomeActive` → `SystemKeyInterceptor.applySettings()`).
Known difference from macOS, not built: the volume "feedback" click and ⌥⇧ quarter steps (keys with modifiers pass through
to macOS, which then draws its square for those presses).
**T14b (2026-10-15):** DeepSeek's chip strip merged (`09c9f3c`, store-tail conflict resolved as main + its 2 entries, verified
no key lost/changed by diffing the three JSON versions). Review: 2 confirmed defects, fixed in `ff86f5e` — per-chip uncached
`NSWorkspace` icon + `installedBundleIDs()` (21 LaunchServices lookups) run 4× per render on a page that re-renders on every app
switch (→ `ClipboardAppIcon` + one pass in body), and the front-app dot never lit Global for preset-less apps
(→ `GestureAppChooser.dottedChip`, pure, M9–M10). Labels harness 10/10. **After merging an agent branch, move it to main
(`git branch -f agent/zed-T14 main`) so the next step builds on the reviewed code** — the board tells the agent to `git switch`
to the existing branch.
**T14c (2026-10-15, Antigravity on agent/zed-T14):** fast-forwarded (`ef47bdd`); 23-agent review, 5 defects confirmed 2/2, fixed in
`594aae4`: the button inspector gated "Dùng làm nút giữ" on `isDeclared` — right click (declared, reserved, but a VALID trigger number)
could become the hold trigger; `isAssignable` is the only correct question. The summary printed `row.caption` raw → Vietnamese
"Chưa gán trong macOS" on the English page → `ResolvedGestureRow.displayCaption(translate:)` (M11). Missing half of the
pickedDirection/pickedButton exclusion; a 9 pt chevron; hand-typed ⌘[/⌘]. The spec exempts the diagram's own 9–10 pt labels
(11 sites) — left for T14f to raise or justify.

## Notch HUD speed (2026-10-15, `59d0380`) — and working beside an agent without touching its tree

Owner: "HUD notch hơi khựng khi tăng/giảm". Measured with temporary os_log marks INSIDE the app (key handled /
present / view onChange / onAppear, `ProcessInfo.systemUptime` ms, read with `log show --predicate 'category ==
"HUDLatency"'`) — an AX-polling probe from outside first read 250–540 ms, which was the probe walking the whole settings
window; with a notch-window-only poll it read ~100 ms, still dominated by SwiftUI→AX propagation. In-app numbers:
before — volume key→present 6–14 ms (waited for CoreAudio's notification), →view 9–18 ms; main thread idle 86 % of a
burst (`sample`), so not CPU. The stutter was visual: the strip grew with the hub's 0.36 s overshooting spring, the bar was
AppKit's NSProgressIndicator on its own clock, and the "%" changed width so the centred row slid. Fixed: `Notch.activity`
spring 0.2/0.92, `Notch.level` ease-out 0.12 on a two-capsule `NotchLevelBar`, monospaced digits in a fixed 34-pt slot,
volume presents the TARGET level before `AudioObjectSetPropertyData` (≈5 ms IPC to coreaudiod). After: present 0.4–0.8 ms,
view 4–10 ms, first strip 16 ms. A HAL property read in a process without a run loop is STALE (CoreAudio caches in-process
and updates via run-loop notifications) — a cross-process "volume changed at" probe never saw the change; don't time
another process's volume that way.

**Working while an agent holds the main checkout on its branch:** `git worktree add ../XFinder-claude main` and work there.
`build-and-check.sh` used to hard-code ROOT to the main checkout (a worktree build silently built the AGENT's branch) and
both scripts shared `/tmp/xfinder-clean-build`; now `XF_ROOT` (default: the script's own checkout), `XF_OUT`, `XF_SRC`
(`d34abaa`). Build into the scratchpad, install with `XF_SRC=…`, and check `lsregister -dump | grep <out>` is empty after.
The worktree at /Users/wolong/github/XFinder-claude keeps `main` checked out, so an agent cannot `git switch main` there.
**T14d stalled (2026-10-15):** the owner asked to review/merge T14d; `agent/zed-T14` had no commit, no edit, no worklog
entry. Cause = my spec: T14d step 1 put "Đặt làm nút giữ" on every side-button row, contradicting wireframe B/CONTRACT
(hold button changes in the inspector), and the agent read design docs in circles until its session ended. Fixed
(`a2954e2`): step 1 rewritten + "read only these builders" + a stop rule for a self-contradicting spec. The branch was
fast-forwarded to main (clean tree). **Before telling the owner "review it", check `git log main..agent/…` — an empty
branch means nothing landed, whatever the pasted transcript looked like.**

## Multi-agent routine over Notion (2026-10-15) — `docs/AGENT_NOTION.md`; measured facts, not the proposal

Owner chose Notion as the work hub (another assistant had already built Home + Projects/Tasks/Runs/Decisions/Playbooks
and seeded 163 tasks — 155 of them hand tests — from uploaded docs, all "(reported)"). Claude reconciled it with `main
a2954e2` and wrote the routine: **Git keeps the spec (`docs/specs/*.md`), code and gates; Notion keeps queue, state, Runs,
decisions, playbooks.** Three write zones on a task page = three H2 headings; properties are patched per column by the
role that owns them. `Spec Revision` = 7 chars of `git hash-object <spec>` (content-addressed; survives squash and
mixed commits — the review's split finding, adopted). `Reported Commits` (Builder, branch SHA) vs `Merged As` (Claude,
main SHA). Claim = `Claimed By` + `Doing` + Run, re-read after 10 s — **advisory, not a lock**; a residual double claim
shows up as two Runs at review time. Successor steps never `Ready` before the predecessor is `Done`; Claude clears
`Claimed By` when setting `Ready`. `Blocked` is the only alarm — read that view first. The routine went through a
4-lens × 2-refuter review before it was written down (13 confirmed / 4 split / 2 refuted; all standing ones fixed).

Measured, each with the mechanism:
* **Notion MCP SQL (`query-data-sources` mode sql) hits the plan's usage limit after 5 calls per session.** `mode: view`
  ran right after (one call) — views are the agent read path; URL form `https://www.notion.so/<db-id>?v=<view-id>`.
  Checkbox values are the strings `__YES__`/`__NO__`; `view://` ids 404 on `fetch`.
* The claude.ai connector writes fine: 6 columns, a select rewrite, 5 views, 7 task pages, body replace, Home edit —
  each read back.
* `opencode --version` = **v2.0.29** ⇒ MCP config is `mcp.servers.<name>` (v2), not `mcp.<name>` (v1) — two incompatible
  doc trees exist. Zed 1.24.2 (`context_servers`, OAuth when no header; Notion does not list Zed officially).
  Antigravity: `.agents/mcp_config.json` with `serverUrl` (not `url`). Codex 0.155.0: `codex mcp add --url` + `codex mcp
  login`. Notion hosted MCP is OAuth-only; `@notionhq/notion-mcp-server` is unmaintained per Notion; the `ntn` CLI is
  real but unrelated to MCP (the pasted proposal was wrong about it).
* Baseline on `main a2954e2`: GATE green, 1236/0 — T14d `Ready` with that as evidence (Run `R-MAIN-a2954e2-gate`).

Process traps this pass: the zoxide `cd` hook killed the first gate run inside `mkdir && cd && …` (again) — the gate
"failed" without running; `/bin/sh -c 'cd … && …'` works. `cat` is `bat` here. A heredoc nested in `/bin/sh -c '…'`
fails to parse in zsh — write the text with the Write tool and append with `/bin/cat`. One research agent in a
14-agent workflow returned the literal placeholder "test" for Antigravity (fourth occurrence of this junk shape) — redone
with a single agent. One refuter in the review died on StructuredOutput schema (5 retries) — the lens still had its other
vote. Edits to a doc under review change what refuters quote — do not edit the draft while the review runs.

**Baseline-vs-main trap, found at push time (2026-10-15):** the first routine said "main's tip must equal the baseline
Run's SHA". The commit that ADDED the routine moved main (docs only), so T14d would have self-blocked immediately and every
later Claude docs commit would re-block the queue. Rule now: baseline is an ancestor of main AND
`git diff --stat <base> main -- XFinder Tests scripts` is empty — a baseline is a statement about code, not about docs.
**Any rule that compares against "the tip of main" breaks the moment the rule itself is committed; test a new rule
against the commit that introduces it.**

**Notion for 10–20 projects (2026-10-16).** The owner's "Library ▸ Recent is a flat hundred-row list" is Notion's design
(a visit history; the "Nguồn" column is the immediate parent; no relation filter exists) — the fix is navigation, not that
tab. Structure now: ONE workspace-level page "Engineering Control Center" (3fb97dfe4af381e883f2f8cb71c15bdc) owns the five
databases; each project is a Projects row (`Code`, `Repo Path`, `GitHub`, `Hub`) plus a hub page of linked views filtered
`Project = <row URL>`. Measured: `notion-move-pages` moves databases and keeps id/URL/views (the Queue view returned T14d
before and after); a linked view created with `create-view parent_page_id` IS queryable via `?v=<id>` in view mode, while
the six linked-database blocks the other assistant made in the UI are not ("view not found") and the tool treats removing
them as deleting 6 databases (needs the owner's confirmation — Q-NOTION-6, not done). Relation filters take the page URL,
never the name. New Task IDs get the project prefix (`XF-T20`); old ones stay (branch names). The 24 markdown snapshot pages
are copies nobody reads — Q-NOTION-5 asks the owner to delete them. The review workflow for this returned `confirmed: []`
because every finding was severity "info" (= claim verified, with URL) and my filter dropped "info" before refutation —
read the journal before calling an empty result "clean"; one of three critics returned nothing at all.
