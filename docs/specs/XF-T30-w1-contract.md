# XF-T30 W1 — contract (tab trong ngăn + tab cửa sổ + khung cửa sổ)

Spec tổng: `docs/specs/XF-T30-fileoctopus-parity.md` (§1 quyết định Q-T30-*, §2 hàng W1). Hành vi tham chiếu:
`scratchpad/claude/t30/spec-panes-tabs-workspaces.md`, `spec-window-views-sidebar.md`, `spec-settings-keyboard.md` §6
(bảng phím). Cơ chế: `docs/FILEOCTOPUS_MECHANISMS_2026-10-25.md` §2.

Mọi chữ ký dưới đây **đã có trên main dưới dạng stub biên dịch được** (commit "XF-T30 W1 contract stubs"). Builder chỉ
sửa file của mình (§6), không đổi chữ ký dùng chung; cần thêm chữ ký ⇒ ghi vào báo cáo, người tích hợp quyết.

## 1. Mô hình

- `PaneState` = **một tab** của một ngăn (không đổi tên lớp để view cũ chạy nguyên). `id: PaneID` = ngăn đang chứa tab
  (model đổi khi tab chuyển ngăn), `tabID: TabID` cố định.
- `BrowserWindowModel` giữ `tabLists: [PaneID: PaneTabList]` + `tabStates: [TabID: PaneState]` (tên nội bộ tuỳ builder);
  `panes: [PaneID: PaneState]` vẫn tồn tại cho view cũ = **tab đang chọn của mỗi ngăn** (computed hoặc stored đồng bộ —
  builder chọn, miễn mọi đường ghi đi qua một chỗ).
- Một ngăn luôn có ≥ 1 tab. Ngăn hết tab (tab cuối chuyển đi) ⇒ ngăn đóng (`tree.close`).
- Tab cửa sổ = tab macOS gốc (mỗi tab là một `BrowserWindow` riêng, chung `tabbingIdentifier`).

## 2. Thuần (builder A — `PaneTabs.swift`, `PaneTree.swift`, `PaneHistory.swift`, `BrowserWorkspace.swift`, `BrowserCommands.swift`, test)

- `PaneTabList`: đúng như doc-comment trong stub (add sau tab chọn và chọn nó; remove từ chối tab cuối, chọn hàng xóm phải
  rồi trái; insert kẹp chỉ số, id có sẵn thì di chuyển; move giữ tab chọn; next/previous vòng).
- `PaneTabRules.dropTarget`: dải mép = `min(edgeZoneMax, edgeZoneFraction × cạnh)`; trên dải tab ⇒ `.strip(index)` theo
  trung điểm các tab (sau tab cuối ⇒ `count`); góc ⇒ mép gần hơn; còn lại `.center`.
- `PaneTree.neighbor(of:toward:in:divider:)`, `resize(_:axis:grow:step:)`, `currentPreset` (doc-comment trong stub).
  `.horizontal` = hai con cạnh nhau (xem `split`: trái/phải ⇒ `.horizontal`). Wider/Narrower ⇒ `.horizontal`,
  Taller/Shorter ⇒ `.vertical`. Pane ở con thứ hai: grow ⇒ fraction giảm.
- `PaneHistory.goBack(steps:)`/`goForward(steps:)`: tương đương gọi `goBack()` `steps` lần, nhưng nguyên tử (thiếu mục ⇒
  nil, không đổi gì).
- `BrowserWorkspace`: `PaneSnapshot.allTabs` (v1 ⇒ một tab từ trường cấp trên), `selectedTabIndex` (kẹp), `init(id:tabs:
  selectedTab:)` (trường cấp trên phản chiếu tab chọn). `SessionRestore.restored` **v2**: thư mục hiện tại của tab đã mất
  ⇒ **giữ nguyên đường dẫn** (tab chết, PaneState báo lỗi + "Thử lại"), vào `missing`; lịch sử bỏ mục mất; sửa
  tree/pane lệch như cũ (ngăn thiếu ⇒ một tab Home); `selectedTab` kẹp. Không bao giờ mount gì.
- `BrowserCommands` bảng phím (FileOctopus §6): `newWindowTab` ⌘T · `newPaneTab` ⌃⌥⌘T · `nextPaneTab` ⌥⌘] ·
  `previousPaneTab` ⌥⌘[ · `moveTabToNewPaneRight` ⌥⇧⌘→ · `moveTabToNewPaneBelow` ⌥⇧⌘↓ · `paneLeft/Right/Above/Below`
  ⌃⇧⌘←/→/↑/↓ · `togglePathBar` ⌥⌘P · `toggleStatusBar` ⌘/ · `toggleToolbar` ⌥⌘T · `toggleSidebar` ⌥⌘S ·
  `useGroups` ⌃⌘0 · **`find` ⌘F, `filter` không phím** (Q-T30-2). Không phím: `closePaneTab`, `moveTabToNextPane`,
  `swapWithNextPane`, `moveTabToWindow`, `makePane*`, `toggleLocationBar`, `customizeToolbar`, `openInNewTab`,
  `openInNewWindow`. Test "một phím một lệnh" phải còn xanh; "/" là ký tự của ⌘/.
- Test mới: `PaneTabsTests` (mọi luật list + dropTarget kể cả góc và tab rỗng), mở rộng `PaneTreeTests` (neighbor trong
  lưới 2×2 và bố cục lệch 3 ngăn, resize kẹp, currentPreset cho cả 4 preset + custom), `PaneHistoryTests` (steps),
  `BrowserWorkspaceTests` (v1 → một tab; v2 round-trip; tab chết giữ đường dẫn — sửa test cũ "opens Home"), 
  `BrowserCommandsTests` (phím mới, ⌘F = find).

## 3. Model (builder B — chỉ `BrowserWindowModel.swift`)

- Lưu trữ tab (§1), API trong extension stub: `tabs(of:)`, `selectTab`, `newTab(in:path:)`, `closeTab` (Q-T30-4),
  `moveTab(_:toPane:at:)`, `moveTabToNewPane(_:beside:_:)` (qua cổng chia ngăn như split), `moveTabToWindow`
  (`BrowserWindowController.shared.openRestoredWindow` với một ngăn một tab, khung lệch 24 pt, rồi đóng tab ở đây),
  `pane(containing:)`, `dropTab(_:onto:target:)` (`.strip` ⇒ moveTab tại chỉ số; `.edge` ⇒ moveTabToNewPane; `.center`
  ⇒ moveTab cuối). Kéo tab về chính ngăn của nó ở `.edge` khi ngăn chỉ có một tab ⇒ không làm gì.
- `PaneState.goBack(steps:)` / `goForward(steps:)`; `restoreSelectionNames` áp sau lần tải đầu (chỉ tên còn tồn tại).
- `perform`/`canPerform` cho MỌI lệnh mới (bảng ở spec tổng §2 W1 + Q-T30-4/6):
  `moveTabToNewPane*` cần ngăn nguồn ≥ 2 tab; `moveTabToNextPane`/`swapWithNextPane` cần ≥ 2 ngăn; `moveTabToWindow`
  xám khi là tab duy nhất của ngăn duy nhất; `pane*` dùng `tree.neighbor` với rect 1000×1000, nil ⇒ false;
  `toggle*Bar`/`toggleSidebar` đảo khoá `fileBrowser.show*` (giá trị hiện tại đọc qua `BrowserSettings`);
  `toggleToolbar`/`customizeToolbar`/`find` đi qua `chrome` (find không có chrome ⇒ hành vi cũ); `filter` ⇒
  `filterFocusRequest = activePane`; `openInNewTab` ⇒ mỗi thư mục chọn một tab mới (tab cuối được chọn);
  `openInNewWindow` ⇒ `BrowserWindowController.shared.openWindow(path:)` mỗi thư mục; `useGroups` đảo `active.useGroups`;
  `newWindowTab` ⇒ `BrowserWindowController.shared.openWindowTab(besideWindowOf: self)`.
- `split`, `applyPreset`, `closePane`, `openWorkspace`, `init(snapshot:)`, `snapshot(frame:)`, `tearDown` viết lại theo tab:
  ngăn mới = một tab copy thư mục + kiểu xem của tab đang chọn; đóng ngăn/preset bỏ ngăn ⇒ dừng watcher của **mọi** tab
  trong ngăn; snapshot ghi v2 (`PaneSnapshot(id:tabs:selectedTab:)`, `selectedNames` ≤ `TabSnapshot.selectionLimit`,
  `groupBy`). Quick Open thêm thư mục của mọi tab (bỏ trùng).

## 4. View (builder D — `PaneTabStripView`, `PaneView`, `PaneGridView`, `BrowserRootView`, `PathBarView`, `StatusBarView`, `SearchBarView`)

- **Thanh tab** mỗi ngăn, luôn hiện (ảnh FileOctopus): tab = biểu tượng thư mục (qua `FileIconCache`) + tên, nút đóng khi
  rê/chọn; tab chọn nổi bật; cuộn ngang khi chật; cuối dải: **+** (tab mới), **chia phải**, **chia xuống** (focus ngăn rồi
  `perform`, xám theo `canPerform`). Kéo tab: kiểu UT riêng `com.xfinder.browser.tab`, payload mang id model + id tab
  (thả sang cửa sổ khác bị bỏ qua); thả lên dải ⇒ chèn tại chỉ số; chuột phải: Đóng tab · Đóng các tab khác · Chuyển tab
  sang ngăn mới bên phải / bên dưới · Chuyển tab ra cửa sổ mới.
- **PaneView**: vạch nhấn màu nhấn dày `XFinderTokens.Space.hairline` trên đỉnh ngăn đang chọn khi có ≥ 2 ngăn (cue duy
  nhất); thanh tab; Location Bar nếu `fileBrowser.showLocationBar`; thanh tìm/lọc (hiện cả khi `filterFocusRequest ==
  pane.id`); nội dung; Path Bar nếu `showPathBar`; Status Bar nếu `showStatusBar` (thay `statusLine` cũ — bỏ `statfs`
  trong `body`).
- **PaneGridView**: thả tab lên vùng ngăn ⇒ `PaneTabRules.dropTarget` + vùng tô sáng (nửa ngăn cho `.edge`, viền cả ngăn
  cho `.center`) ⇒ `model.dropTab`.
- **BrowserRootView**: bỏ hàng toolbar SwiftUI (chuyển sang `NSToolbar`, builder C); sheet Workspace theo `model.sheet`;
  ẩn sidebar khi `fileBrowser.showSidebar` = false. Banner, bảng lệnh, các sheet khác giữ.
- **StatusBarView**: "N mục, X còn trống"; có chọn ⇒ "M trên N mục được chọn, X còn trống"; Thùng rác không có Full Disk
  Access ⇒ "Cần quyền Full Disk Access". Dung lượng trống qua cache `@MainActor` đọc nền (≥ 10 s mới đọc lại một volume).
- **PathBarView**: `NSPathControl` của thư mục tab, bấm đoạn ⇒ điều hướng tab đó; cao cố định một dòng.
- Mọi chuỗi qua `L10n.t("literal")`, chuỗi nội suy tách fragment giữ khoảng trắng mép; không số/màu literal (token).

## 5. Khung (builder C — `BrowserWindowController.swift`, `BrowserToolbar.swift`, `BrowserMainMenu.swift`)

- Cửa sổ: `tabbingMode = .preferred`, `tabbingIdentifier = "com.xfinder.browser"`, `toolbarStyle = .unified`, tiêu đề =
  thư mục của tab đang chọn ở ngăn đang chọn. `openWindowTab(besideWindowOf:)` (thư mục Home như ⌘N, tới khi W4 có "Cửa
  sổ mới hiện"); `BrowserWindow.newWindowForTab(_:)` gọi nó.
- Phiên: ghi `tabGroup`/`tabIndex`/`selectedInGroup` từ `window.tabbedWindows` / `tabGroup.selectedWindow`; khôi phục
  gom nhóm bằng `addTabbedWindow(_:ordered:)` theo `tabIndex`, chọn lại tab đã ở trước. Thư mục mất ⇒ banner như cũ.
- `BrowserToolbarController` (một mỗi cửa sổ, controller giữ strong): mặc định Back/Forward · View · Group · Pane Layout
  · flexible space · Share · Action · Search; thêm được Thư mục cha · Đến thư mục · Workspace · Shelf · Thao tác (badge số
  việc). `allowsUserCustomization`, `autosavesConfiguration`, identifier `XFinderBrowserToolbar.v1`.
  - Back/Forward: hai segment momentary, `setMenu(_:forSegment:)` = lịch sử tab đang chọn (gần nhất trên cùng) ⇒
    `goBack(steps:)`/`goForward(steps:)`; bật/tắt theo lịch sử (theo dõi bằng `withObservationTracking`).
  - View: nhóm 4 lựa chọn (⌘1–4), theo `active.viewMode`. Group: menu `GroupBy.allCases` + "Dùng nhóm"; ở Gallery là
    "Sắp theo" (các `SortKey`). Pane Layout: biểu tượng theo `tree.currentPreset` (nil ⇒ biểu tượng "tuỳ chỉnh"), menu 4
    preset + Chia phải/trái/xuống/lên + Bằng nhau + Phóng ngăn. Share: `NSSharingServicePickerToolbarItem` với URL đang
    chọn. Action "…": menu dựng lại khi mở, các lệnh của mục chọn lọc theo `canPerform`. Search: `NSSearchToolbarItem`,
    Return ⇒ `model.runSearch(text, scope: .folder)`, xoá ⇒ `active.endSearch()`; `focusSearchField()` đưa con trỏ vào.
  - Workspace / Thao tác dùng `model.sheet` / `NSPopover(OperationsPanelView)`.
- `BrowserMainMenu` (Q-T30-13): **probe trước** — chèn mục (gắn tag riêng) vào menu File/View/Window có sẵn + một menu "Đi",
  kích hoạt khi cửa sổ trình duyệt thành key, gỡ khi không còn; đo xem SwiftUI có ghi đè không (đổi qua lại cửa sổ Cài đặt
  XFinder ↔ trình duyệt 5 lần). Phím tắt hiển thị chỉ cho chord có ⌃ hoặc ⌥ hoặc không thuộc nhóm sửa chữ (⌘C/V/X/A/Z,
  ⌘⌫, Return) — để menu không cướp phím của ô chữ. Không giữ được ⇒ để trống, ghi lý do vào báo cáo.

## 6. Quyền sở hữu file

| Builder | File (chỉ những file này) |
|:--|:--|
| A thuần | `Core/Browser/PaneTabs.swift`, `PaneTree.swift`, `PaneHistory.swift`, `BrowserWorkspace.swift`, `BrowserCommands.swift`, `Tests/XFinderLogicTests/{PaneTabsTests(mới),PaneTreeTests,PaneHistoryTests,BrowserWorkspaceTests,BrowserCommandsTests}.swift` |
| B model | `Core/Browser/BrowserWindowModel.swift` |
| C khung | `Core/Browser/BrowserWindowController.swift`, `BrowserToolbar.swift`, `BrowserMainMenu.swift` |
| D view | `Views/Browser/{PaneTabStripView,PaneView,PaneGridView,BrowserRootView,PathBarView,StatusBarView,SearchBarView}.swift` |
| Tích hợp | pbxproj, symlink, L10n (`scripts/add-xf-t30-w1-l10n-entries.py`), `FeatureKeyDefaultsTests` (4 khoá `fileBrowser.show*`), `FeatureContractTests`, harness browser, docs |

## 7. Ca hỏng

Đóng tab đang tải ⇒ huỷ tải + watcher · kéo tab của ngăn một-tab ra mép chính nó ⇒ không gì · chuyển tab cuối của ngăn
⇒ ngăn đóng, focus sang ngăn nhận · phiên v1 mở được · phiên có tab trỏ ổ đã tháo ⇒ tab chết "Thử lại", không mount ·
16 ngăn × nhiều tab ⇒ không watcher thừa (chỉ tab đang chọn cần watcher? **không**: mọi tab giữ watcher như XF-T28 —
builder B ghi lại chi phí nếu đổi) · ô tìm toolbar luôn chạy cho ngăn đang chọn tại lúc bấm Return · ⌘F trong ô sửa tên
không mở tìm.

## 8. Nghiệm thu W1 / T-T30-W1

Build xanh, test 0 lỗi (test mới ở §2), gate L10n/token, harness browser thêm mutant cho PaneTabList/dropTarget/neighbor/
resize/restore v2, cài + hash. Tay: T-T30-1 tab ngăn (⌃⌥⌘T, ⌥⌘]/[, + trên dải, đóng tab cuối), T-T30-2 kéo tab sang ngăn
khác và ra mép ⇒ chia, T-T30-3 ⌘T tab cửa sổ + thoát/mở lại giữ đủ năm tầng, T-T30-4 toolbar (giữ Lùi để xem lịch sử,
Bố cục ngăn đổi biểu tượng, Tuỳ biến thanh công cụ), T-T30-5 ⌥⌘P / ⌘/ / ⌥⌘S, T-T30-6 ⌃⇧⌘← → ↑ ↓ trong lưới 2×2.
