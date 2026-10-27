
## 2026-10-27 — Codex: XF-T32 Learn, direct owner request

Branch `agent/codex-T32-Learn`, based on live crash fix `511f82a`. Spec: `docs/specs/XF-T32-learn-contract.md`. Added bottom-right book button, reuses Learn tab in active pane, six localized lessons, explicit per-lesson completion persisted in `fileBrowser.learn.completed`. Virtual location survives tab/session encoding; no directory watcher/Spotlight request for Learn. Folder controls are hidden and relevant dispatcher commands disabled. New Swift files have four pbx entries each and pure progress source is symlinked into test package.

Build: clean full app build passed, both new files compiled; final incremental build after localized window title/book tab icon passed; plutil/diff checks passed. Installed app dylib matches final build SHA-256 `1ad274946da22c47f2fc10980cdd4e4ea2d5b9e4324e51ff32d922da3135fb1b`; stable signing requirement retained. Runtime English L10n TOTAL 0.

Tests: four new progress/path tests cover corrupt/empty data, completion/uncheck, preserving unknown IDs, bounded count and virtual-path round trip. Injected broken uncheck behavior: one test RED; restored source: GREEN. Initial full gate had one existing AgentCodexTests failure because its assumption of no codex ancestor is false under this runner. Detached run (no Codex ancestor) passed all 2823 tests. No unrelated hook/test code changed. Detached gate stdout (verbatim):

```text
tests                              Executed 2823 tests, with 0 failures (0 unexpected) in 24.040 (24.248) seconds
check-l10n-coverage                TOTAL 0 problems across 3603 entries (3603 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3603 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1332 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             9
GATE: green
```

Live in installed app: book button opens real Learn tab; six checkboxes and progress indicator exposed to AX; checking first lesson changes progress to 1/6; completion retained after closing/recreating tab and after app reinstall/relaunch. Uncheck works. Final localized window title is Learn; inspected screenshot `/tmp/xfinder-live-20261027/learn-final.png`. The browser window was no longer present when the final tab-close command ran, so that command did not execute; button presence was verified before opening Learn. Owned test lesson is unchecked. Full VoiceOver speech, keyboard-only traversal, all locales, simultaneous multi-window edits and session restoration of a Learn tab not live verified. W4 Inspector and remaining W6 features are outside this change. No push.

# Agent worklog

Every agent other than the main Claude Code session appends here (newest first): what it changed, the result of each
gate it ran, and what it could NOT verify. Claude reviews these entries before merging anything. See
`docs/AGENT_QUICKSTART.md` for the rules.

## 2026-10-25 (Antigravity) — T14f: Soát chuỗi lần cuối, 6 cổng L10n + 3 harness mutation

**Lệnh của chủ:** Thực hiện nghiệm thu cuối cùng cho chuỗi T14 (`docs/specs/T14-mouse-gestures-B.md` §T14f) trên nhánh `agent/zed-T14`: soát toàn bộ diff chuỗi, chạy tuần tự 6 cổng L10n và 3 harness mutation, dán kết quả nguyên văn vào worklog.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14f** — Nghiệm thu toàn diện T14 (Chuỗi, 6 cổng L10n, 3 harness mutation) | `docs/AGENT_WORKLOG.md` | Cả 6 cổng L10n in `TOTAL 0`; 3 harness mutation chạy tuần tự đạt đủ 100% RED (labels: 11/11, ui: 8/8, buttons: 13/13); `gate-all.sh` in `GATE: green` (2508 tests, 0 failures; modified tracked files: 0) | Xem mục "Chưa kiểm live" của T14a–T14e (thao tác trực tiếp trên app đang chạy với các thiết bị chuột vật lý khác nhau) |

### Kết quả 6 cổng L10n (nguyên văn)
1. `python3 scripts/check-l10n-coverage.py`: `TOTAL 0 problems across 3504 entries (3504 checked, 31 allowlisted)`
2. `python3 scripts/check-l10n-duplicates.py`: `TOTAL 0 duplicates across 3504 unique keys`
3. `python3 scripts/audit-l10n-literals.py`: `TOTAL 0 wrapped-but-untranslated, 1304 unwrapped`
4. `python3 scripts/audit-l10n-interpolations.py`: `TOTAL 0 interpolated strings with Vietnamese outside L10n.t`
5. `python3 scripts/check-sidebar-groups-l10n.py`: `TOTAL 0 problems across 7 sidebar group headers and 47 page titles`
6. `python3 scripts/verify-l10n-runtime.py`: `TOTAL 0 leaks in the resolved English UI`

### Kết quả 3 harness mutation chạy tuần tự (nguyên văn)
- `scripts/mutation-check-gesture-labels.sh`: `RESULT: 11/11 mutations RED` (post-restore suite: Executed 2508 tests, 0 failures)
- `scripts/mutation-check-gesture-ui.sh`: 8/8 bugs RED as expected (`post-restore suite: Executed 2508 tests, 0 failure(s)`)
- `scripts/mutation-check-gesture-buttons.sh`: `RESULT: 13/13 mutations RED` (post-restore suite: Executed 2508 tests, 0 failures)

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)
```
build (arm64, compile list)        OK
tests                              Executed 2508 tests, with 0 failures (0 unexpected) in 16.209 (16.332) seconds
check-l10n-coverage                TOTAL 0 problems across 3504 entries (3504 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3504 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1304 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             0
GATE: green
```


## 2026-10-25 (Antigravity) — T14e: Khối 8 (Chẩn đoán), Khối 9 (footer), xoá GestureButtonList và code chết

**Lệnh của chủ:** Thực hiện đúng đặc tả T14e (`docs/specs/T14-mouse-gestures-B.md` §T14e) trên nhánh `agent/zed-T14`, commit trên nhánh đó, dán kết quả `sh scripts/gate-all.sh` vào worklog.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14e** — Khối 8 (Chẩn đoán), Khối 9 (footer), xoá GestureButtonList và code chết | `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder/Views/Components/GestureButtonList.swift` (xoá) · `XFinder.xcodeproj/project.pbxproj` (-4 dòng) · `XFinder/Resources/L10n.strings.json` (+1 khoá / +4 dòng) · `scripts/add-mouse-redesign-l10n-entries.py` · `scripts/build-and-check.sh` · `scripts/verify-gesture-ui.sh` · `docs/AGENT_WORKLOG.md` | `gate-all.sh` in `GATE: green`; `swift test` 2508 tests / 0 failures; `audit-ui-tokens` 0; `plutil -lint project.pbxproj` sạch (OK); không còn `GestureButtonList.swift` trên đĩa và trong compile list; không còn `private var`/`private func` chết | Mở/đóng `DisclosureGroup` "Chẩn đoán chuột" trên app đang chạy; kiểm tra lazy load của "Mô tả HID thô" khi mở disclosure con trên máy thật |

### Đã làm — đúng 3 điểm của §T14e
1. **Khối 8 — Chẩn đoán chuột (`diagnosticsSection`):**
   - Đặt trong một `DisclosureGroup` đóng mặc định (`diagnosticsExpanded = false`), nhãn "Chẩn đoán chuột" kèm icon `wrench.and.screwdriver`.
   - Chứa 4 thành phần:
     - Hàng "Thiết bị" (`deviceRow`) S13-S23.
     - Hàng "Nút chuột XFinder thấy" (`buttonsDeclarationRow`) S29-S33 chuyển từ `GestureButtonList` sang với đầy đủ cảnh báo vendor/consumer counts và `declarationSummary`.
     - `DisclosureGroup` con "Mô tả HID thô" (`hidDumpRow`) F19/S24-S25 (lazy-load khi mở).
     - Hàng "Nút bạn vừa bấm" (`observedButtonRow`) S26 khi có `observedButton`.
2. **Khối 9 — Footer (`footerNote`):**
   - Giữ nguyên logic F26 + S53 (`footerNote` gồm link "Mở Phím tắt" và câu giải thích khi không hoạt động).
3. **Dọn sạch code chết và xoá `GestureButtonList.swift`:**
   - Xoá hoàn toàn `mappingSection`, `profileSidebar`, `profileRow`, `appPickerRow`, và computed property `orderedProfiles` không tham số.
   - Xoá `XFinder/Views/Components/GestureButtonList.swift` trên đĩa.
   - Dọn sạch đủ 4 dòng liên quan trong `XFinder.xcodeproj/project.pbxproj` (`plutil -lint` xác nhận OK).
   - Cập nhật danh sách kiểm tra biên dịch trong `scripts/build-and-check.sh` và `scripts/verify-gesture-ui.sh`.
   - Giữ nguyên `GestureActivityPanel.swift` vì vẫn cần cho `DEBUG_SHOW_ENGINE_LOG`.

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 2508 tests, with 0 failures (0 unexpected) in 16.105 (16.226) seconds
check-l10n-coverage                TOTAL 0 problems across 3504 entries (3504 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3504 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1304 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             7
GATE: green
```


## 2026-10-25 (Antigravity) — T14d: Khối 5 (Nút hông), Khối 6 (Nút giữ & cuộn), Khối 7 (Nghiêng con lăn)

**Lệnh của chủ:** Tiếp tục hoàn thiện pending jobs, thực hiện đúng đặc tả T14d (`docs/specs/T14-mouse-gestures-B.md` §T14d) trên nhánh `agent/zed-T14`, commit trên nhánh đó, chạy đầy đủ 7 cổng gate và 3 harness mutation, dán kết quả `sh scripts/gate-all.sh` vào worklog.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14d** — Khối 5 (Nút hông), Khối 6 (Nút giữ & cuộn), Khối 7 (Nghiêng con lăn) | `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder/Resources/L10n.strings.json` (+9 khoá / +36 dòng) · `scripts/add-mouse-redesign-l10n-entries.py` · `docs/AGENT_WORKLOG.md` | `gate-all.sh` in `GATE: green`; `swift test` 2508 tests / 0 failures; `audit-ui-tokens` 0; 3 harness mutation (labels, ui, buttons) toàn bộ RED; không còn `triggerRecording()` ngoài Khối 6 và F7 hold-badge; `GestureButtonList.swift` giữ nguyên trên đĩa tới T14e | Cảm giác bấm click-action menu trên các hàng nút hông thật; bấm "Ghi nút" ở Khối 6 với chuột vật lý thật; bật/tắt switch nghiêng con lăn trên chuột MX Master thật |

### Đã làm — đúng đặc tả §T14d + các luật §4 & §5
1. **Khối 5 — Nút hông (`sideButtonsSection`):**
   - Lọc `drawnButtons` theo `role.isAssignable` và loại bỏ nút giữ hiện tại (`!case .holdTrigger`, `!case .holdTriggerWithAction`).
   - Mỗi hàng hiển thị tên `Nút N` (`L10n.t(compactButton:)`) + vị trí (`positionKey`) làm caption, chip vai trò (`roleChip`), và `Menu` gán click action (Không làm gì / Lùi / Tiến).
   - Tuyệt đối không có nút "Đặt làm nút giữ" hay "Ghi" trong Khối 5 per CONTRACT.
   - Nút chưa khai báo (`!role.isDeclared`): hiển thị hàng mờ màu `.secondary`, nhãn "Chưa khai báo" và dòng chú thích "Bấm “Ghi nút” ở mục Nút giữ & cuộn rồi bấm nút này để XFinder đo.".
   - Xử lý trạng thái rỗng (`khong-chuot`): hiển thị hàng "Chưa đọc được nút nào — Cắm chuột có nút hông để xem và gán ở đây.".
   - Giữ nguyên `hardwareExclusionNote` (S39) ở cuối khối.
2. **Khối 6 — Nút giữ & cuộn (`switchesSection`):**
   - Hàng 1: Tiêu đề "Nút giữ", subtitle "Giữ nút này rồi kéo bốn hướng. Bấm chip trên hình bên trên để đổi.", giá trị hiện tại (`L10n.t(compactButton: config.trigger.key)`), và nút "Ghi nút" (`triggerRecording()`). Vô hiệu khi `controller.recording`.
   - Toggle F17 ("Bấm nhanh = Tiến") tích hợp ngay hàng 1 khi nút giữ là `holdTriggerWithAction`.
   - Hàng 2: Switch F22 ("Giữ nút cuộn rồi kéo để cuộn").
   - Hàng 3: Picker "Nút cuộn" sử dụng `scrollButtonChoices`.
3. **Khối 7 — Nghiêng con lăn (`tiltSection`):**
   - Đặt `tiltRow` vào `SettingsSection(title: L10n.t("Nghiêng con lăn"))` độc lập, giữ nguyên logic `TiltArmsVisibility.fields(forReveal:)`.
4. **Chuỗi và Token:**
   - Bổ sung 9 chuỗi mới qua `scripts/add-mouse-redesign-l10n-entries.py`.
   - Chuẩn hoá toàn bộ font sizes sang `XFinderTokens.Font.rowValue` và `XFinderTokens.Font.caption`.
   - Đảm bảo `triggerRecording()` chỉ xuất hiện ở 2 nơi: Khối 6 và F7 hold-badge.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu quyền Trợ năng** (`trusted == false`): Status line hiện đúng S2/S6; các khối 5, 6, 7 vẫn xem và cấu hình bình thường qua controller.
2. **Không có chuột / chưa khai báo nút nào**: Khối 5 hiển thị honest "Chưa đọc được nút nào — Cắm chuột có nút hông để xem và gán ở đây.", không bịa số nút. Dải chip app vẫn hoạt động bình thường.
3. **Công tắc chính tắt** (`config.enabled == false`): Status line phản ánh đúng; Khối 5–7 vẫn xem và cấu hình bình thường.
4. **Một giá trị ở biên**: `drawnButtons` rỗng thì Khối 5 hiện hàng rỗng honest. `scrollButtonChoices` luôn bảo đảm có ít nhất `config.scrollButton` nên Picker không rỗng.
5. **Ngữ cảnh đổi giữa chừng**: Đang ghi mà đổi `profile`, `onChange(of: profile)` huỷ `recordingDirection` nhưng giữ `controller.recording` đúng hành vi gốc.
6. **Giá trị cache cũ**: `hidDump` chỉ lazy-load khi mở disclosure group (bảo lưu cho T14e).
7. **Control hứa điều không làm được**: Đã dọn sạch toàn bộ "Ghi nút" gây nhầm lẫn; `triggerRecording()` chỉ gọi ở Khối 6 và F7 hold-badge.

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 2508 tests, with 0 failures (0 unexpected) in 16.612 (16.738) seconds
check-l10n-coverage                TOTAL 0 problems across 3503 entries (3503 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3503 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1304 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             3
GATE: green
```

### Kết quả 3 harness mutation (nguyên văn)
- `scripts/mutation-check-gesture-labels.sh`: `RESULT: 11/11 mutations RED`
- `scripts/mutation-check-gesture-ui.sh`: `post-restore suite: Executed 2508 tests, 0 failure(s)` (8/8 mutations RED)
- `scripts/mutation-check-gesture-buttons.sh`: `RESULT: 13/13 mutations RED`

## 2026-10-15 (Claude) — the queue moved to Notion; this file is now the fallback path

`docs/AGENT_NOTION.md` is the routine (roles, write zones, claim handshake, Runs, view URLs, schema, payloads, three
prompts). Measured today on the Notion workspace: schema extended (Spec Path · Branch · Claimed By · Pre-reviewed ·
Block Reason · Merged As), import-era States removed, five views created and the Queue view read back via `mode: view`
(returns exactly T14d), T14a–T14c = Done, T14d = Ready (spec blob `53e3659`, baseline gate green on `main a2954e2`,
Run `R-MAIN-a2954e2-gate`), T14e/T14f waiting. **SQL queries of the Notion MCP hit the plan's usage limit after 5
calls** — agents must use views and `fetch`, never SQL. The routine went through an adversarial review (4 lenses × 2
refuters: 13 confirmed, 4 split, 2 refuted) before being written down; every standing finding is addressed in the doc.

**Write here only when you cannot reach Notion** (AGENT_NOTION §7); Claude copies such an entry into a Run on return
after checking for a duplicate claim. Not verified live yet: a real Builder claiming through Notion (T-NOTION-1…4).

## 2026-10-15 (Claude) — T14d never landed; the spec was the reason; fixed

The first T14d session ended without a commit, an edit or a worklog entry: its transcript shows it re-reading
CONTRACT.md, inventory.md and variant-b.html to resolve a contradiction in the spec — T14d step 1 told it to add
"Đặt làm nút giữ" to every side-button row, while wireframe B / CONTRACT say the hold button changes in the inspector
(done in T14c). That was Claude's spec bug. Step 1 is rewritten: block 5 rows carry only the click-action menu (no hold
button, no record button); the hold button changes in the inspector and in block 6's "Ghi nút". A new stop condition in
AGENT_TASKS §3: a self-contradicting spec is copied into the worklog and the session stops.

`agent/zed-T14` was fast-forwarded to `main` (it also carries Claude's notch HUD speed-up and the worktree-safe build
scripts). Next: **T14d**, same branch.

## 2026-10-15 (Claude review of T14c) — merged; five defects fixed; branch moved to main

For the next agent: read this, not the long T14c entry below it. T14c was done by Antigravity on `agent/zed-T14` —
that is fine; the branch name stays the same whichever tool works on it.

| Item | Verdict |
|:--|:--|
| Card with diagram + inspector, never-blank summary, button inspector, F7/F8 kept, font bumps, picker label | **correct and in scope** — fast-forwarded as `ef47bdd` |
| "Dùng làm nút giữ" | **defect (2/2)**: gated on `isDeclared`; left/right click are declared but RESERVED, so right click could become the hold trigger. Fixed in `594aae4`: `if role.isAssignable`. **Rule: "may this be the hold button?" is always `isAssignable`; `isDeclared` is only a drawing question** (see the doc comment in DeviceCapabilityModel) |
| Direction summary caption | **defect (2/2)**: raw `row.caption` printed "Chưa gán trong macOS" on the English page. Fixed: `row.displayCaption(translate:)` — **use it wherever a caption is printed** |
| Arm click left a button chip highlighted | **defect (2/2)**: added `.onChange(of: pickedDirection)` clearing `pickedButton` |
| 9 pt chevron, hand-typed `⌘[`/`⌘]` | **defects (2/2)**: 11 pt; `InstantAction.*.shortcut.label` |

Known and left alone: the diagram's own arm/chip labels are 9–10 pt (11 sites in MouseDiagramView/GestureArmView/
GestureButtonList/MouseGestureAppStrip). The spec (line 101) exempts the figure; if T14f's sweep can raise them without
breaking the geometry, do it, otherwise write in the worklog why not.

**`agent/zed-T14` now points at `main` (`594aae4` or later).** Next: **T14d** — `git switch agent/zed-T14`, check `git log -1`,
work and commit there.

## 2026-10-15 (Antigravity) — T14c: sơ đồ chuột + inspector bên phải trong cùng card (Khối 4)

**Lệnh của chủ:** đọc `AGENT_QUICKSTART.md` + `AGENT_TASKS.md` + mục mới nhất của worklog, switch branch `agent/zed-T14` (không tạo nhánh mới), kiểm `git log -1` là `6577c86` hoặc mới hơn, làm ĐÚNG bước T14c (`docs/specs/T14-mouse-gestures-B.md`), commit trên nhánh đó, dán kết quả `sh scripts/gate-all.sh` vào worklog rồi dừng.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14c** — Khối 4: 2 cột trong 1 card (sơ đồ chuột + inspector) | `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder/Views/Components/GestureDetailPanel.swift` · `XFinder/Views/Components/GestureActionPicker.swift` · `XFinder/Resources/L10n.strings.json` (+4 khoá / +16 dòng) · `scripts/add-mouse-redesign-l10n-entries.py` · `docs/AGENT_TASKS.md` · `docs/AGENT_WORKLOG.md` | `gate-all.sh` in `GATE: green`; `plutil -lint project.pbxproj` sạch; `swift test` 1233 tests / 0 failures; `audit-ui-tokens` 0; không font size < 11pt (§3.1); `GestureActionPicker`, `GestureActionCatalog.choices()`, `GestureMap.row`, `resolved(_:)`, `resolvedName(_:)` vẫn được gọi nguyên vẹn (grep ✓) | Cảm giác click trực tiếp mũi tên trên sơ đồ chuột để chọn hướng và click chip nút để mở inspector nút trên app thật. Bấm nút "Dùng làm nút giữ" trong app thật có cập nhật trigger chuột tức thì không. Font 11pt so với tỉ lệ hiển thị tổng thể trên màn hình Retina/non-Retina. |

### Đã làm — đúng 6 điểm của §T14c + 3 luật §4
1. **Bố cục 2 cột trong 1 card (§T14c.1):** Khối 4 được bọc trong một `RoundedRectangle(cornerRadius: XFinderTokens.Radius.tile)` card duy nhất. Cột trái (~310pt) chứa `MouseDiagramView` (284pt) + `TiltArmsRow` (khi `tiltArmsLive`). Cột phải (linh hoạt, minWidth ~280pt) chứa inspector panel, ngăn cách bởi `Divider()`.
2. **Định tuyến inspector & hai lựa chọn song song (§T14c.2, §T14c.3):**
   - Routing: `if let direction = pickedDirection { GestureDetailPanel(...) } else if let button = pickedButton { buttonInspector(button) } else { directionSummaryView }`.
   - Mặc định panel không bao giờ trống (sửa Lỗi #7): khi chưa chọn gì, hiển thị `directionSummaryView` tóm tắt 4 hướng cơ bản (Lên / Xuống / Trái / Phải) với tên hành động (`resolvedName`) và chord keycaps (`resolved.shortcutDisplay`); mỗi hàng có thể click để chọn ngay hướng đó; giữ nguyên 2 câu giải thích của S28 ở chân bảng (`emptySelectionHint`).
   - Thêm `.onChange(of: pickedButton)` để xoá `pickedDirection` khi người dùng bấm chip nút, đảm bảo ưu tiên hướng khi bấm mũi tên nhưng chuyển đổi mượt sang nút khi bấm chip nút.
3. **Chi tiết hướng đã chọn (§T14c.4):** Tái dùng `GestureDetailPanel` nguyên vẹn logic bindings (`onPick`, `onRecord`, `onReset`). Nâng toàn bộ font size 10pt lên 11pt ở `GestureDetailPanel.swift` (lines 94, 142, 214, 217) và `GestureActionPicker.swift` (line 57) theo chuẩn §3.1 / §T14c.4.
4. **Cải tiến `GestureActionPicker` (F9):** Thay nút menu `ellipsis.circle` bằng nhãn hành động hiện tại (`currentActionLabel`) với `menuStyle(.borderedButton)` và `.controlSize(.small)`, hiển thị rõ hành động đang gán.
5. **Inspector theo nút (§T14c.5 / F8 / F15):** Dựng `buttonInspector(_ button: Int)`:
   - Header: tên `Nút N`, phụ đề vị trí/chức năng, pill trạng thái vai trò (`rolePill`).
   - Hàng click-action ("Bấm nhanh"): chỉ hiển thị read-only (ví dụ `Lùi (⌘[)`), menu gán click-action giữ ở Khối 5 theo §3.9.
   - Nhánh nút giữ: nếu là nút giữ hiện tại (`role == .holdTrigger || role == .holdTriggerWithAction`), hiện `Đây là nút giữ hiện tại`. Nếu không: hiện `Nút giữ cử chỉ hiện tại là Nút <X>` kèm nút `Dùng làm nút giữ` (`controller.update { $0.trigger = .mouseButton(button) }`, vô hiệu khi `!role.isDeclared`).
   - Chú thích: hiển thị `passthroughNoteKey` hoặc `role.explanationKey`.
6. **Chuỗi mới và L10n:** Thêm 4 chuỗi mới vào `scripts/add-mouse-redesign-l10n-entries.py` (`Đây là nút giữ hiện tại`, `Nút giữ cử chỉ hiện tại là `, `Dùng làm nút giữ`, `Bấm nhanh`) và chạy script cập nhật `L10n.strings.json` (+16 dòng). Toàn bộ 6 cổng L10n đều báo `TOTAL 0`.

### Quyết định đã chốt
- **`buttonInspector` đặt inline trong `MouseGesturesDetailView.swift`:** dung lượng ~150 dòng kết hợp chặt chẽ với state và controller của detail view, tránh phân mảnh file không cần thiết và không phải thêm file vào `project.pbxproj`.
- **Đồng bộ lựa chọn hướng và nút:** `MouseDiagramSelection` trong Core không tự động xoá `pickedButton` khi chọn hướng, nên việc định tuyến ưu tiên `pickedDirection` trước kết hợp `.onChange(of: pickedButton) { if $1 != nil { pickedDirection = nil } }` giúp chuyển đổi hai chế độ inspector chuẩn xác mà không cần sửa Core models.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu quyền Trợ năng** (`trusted == false`): Khối 2 hiện `permissionBanner` + status S2/S6; Khối 4 (sơ đồ + inspector) vẫn xem và sửa phím tắt/hành động bình thường vì inspector đọc và ghi qua `GestureController`/`config` (cử chỉ chỉ không nhận diện được khi di chuyển chuột thật). ✓
2. **Không có chuột / chưa khai báo nút**: `drawnButtons` rỗng hoặc chỉ có các nút mặc định; `buttonInspector` xử lý an toàn cho mọi role (`.notDeclared`, `.unknown`, `.unassigned`), hiển thị đúng nhãn và vô hiệu nút "Dùng làm nút giữ" khi `!role.isDeclared`. Tóm tắt 4 hướng vẫn hoạt động độc lập không phụ thuộc chuột. ✓
3. **Công tắc chính tắt** (`config.enabled == false`): status line hiện S3; Khối 4 vẫn xem, bấm chọn hướng/nút và sửa cấu hình bình thường (đúng S3). ✓
4. **Một giá trị ở biên**: Nếu `drawnButtons` rỗng, không có chip nút nào để click vào `buttonInspector`, inspector mặc định hiển thị tóm tắt 4 hướng; nếu `pickedButton` mang giá trị nút bất kỳ, `buttonRole(button)` trả về `.unknown` hoặc `.notDeclared` an toàn, không crash. `scrollButtonChoices` luôn chứa `config.scrollButton` nên không bao giờ rỗng. ✓
5. **Ngữ cảnh đổi giữa chừng**: Khi đang ghi (`controller.recording == true`), người dùng đổi app chip thì `onChange(of: profile)` xoá `pickedDirection`, `pickedButton`, `recordingDirection`, nhưng không hủy `controller.recording`/`recordingTrigger`/`recordingButton` — giữ nguyên hành vi gốc. ✓
6. **Giá trị cache cũ**: Khối 4 không liên quan tới `hidDump` (sẽ được T14e xử lý với `.onChange(of: hidDumpExpanded)`). ✓
7. **Control hứa điều không làm được**: Nút "Dùng làm nút giữ" trong `buttonInspector` gọi đúng `controller.update { $0.trigger = .mouseButton(button) }` và disable khi `!role.isDeclared`. Menu click action chỉ nằm ở Khối 5, Khối 4 chỉ hiện read-only "Bấm nhanh". Bấm hold-badge trên diagram ghi nút giữ ngay (F7), bấm chip nút chỉ mở inspector (F8). ✓

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 1233 tests, with 0 failures (0 unexpected) in 6.500 (6.574) seconds
check-l10n-coverage                TOTAL 0 problems across 2795 entries (2795 checked, 20 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 2795 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 850 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 45 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             7
GATE: green
```

## 2026-10-15 (Claude review of T14b) — merged; two defects fixed; branch moved to main

For the next agent: read this, not the long T14b entry below it.

| Item | Verdict |
|:--|:--|
| T14b chip strip, F5 "Xem" dedup, F24 "+", F25 move, 4 pbxproj entries, strings | **correct and in scope** — merged as `09c9f3c` (the only conflict was the tail of L10n.strings.json; resolved as main + your 2 entries) |
| Icons and installed apps per render | **defect (2/2 refuters)**: `appIcon(for:)` asked NSWorkspace per chip per render, uncached, and `installedBundleIDs()` (21 LaunchServices lookups) ran 4× per render. Fixed in `ff86f5e`: icons through `ClipboardAppIcon`; the body computes `installed` and the chip list once and passes them on. **Rule for T14c+: never call NSWorkspace/LaunchServices inside a view builder; reuse `ClipboardAppIcon`** |
| The "app in front" dot | **defect (2/2 refuters)**: it only lit a chip equal to the front bundle, so apps without a preset (governed by Global) dotted nothing. Fixed: `GestureAppChooser.dottedChip` (pure, tested, M9–M10) |

**The branch `agent/zed-T14` now points at `main` (`ff86f5e`)** — it contains your T14b, the fixes above, and an
unrelated notch HUD commit. For T14c: `git switch agent/zed-T14` (no new branch), check `git log -1` shows `ff86f5e` or later,
then work and commit there. Next: **T14c**.

## 2026-10-15 (Zed / DeepSeek V4.1 Flash, Viber Bedrock) — T14b: dải chip ứng dụng (Khối 3) thay sidebar 240pt

**Lệnh của chủ:** đọc `AGENT_QUICKSTART.md` + `AGENT_TASKS.md` + mục mới nhất của worklog, làm ĐÚNG bước T14b
(`docs/specs/T14-mouse-gestures-B.md`), tạo nhánh `agent/zed-T14`, commit đúng file của T14b, dán nguyên văn
`sh scripts/gate-all.sh` rồi **dừng** (không push/merge/T14c). Không có điều kiện dừng nào xảy ra.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14b** — Khối 3 thành dải chip ngang (F4/F5/F24/F25) | `XFinder/Views/Components/MouseGestureAppStrip.swift` (**mới** + 4 dòng pbxproj) · `XFinder/Views/Detail/MouseGesturesDetailView.swift` · `XFinder.xcodeproj/project.pbxproj` · `XFinder/Resources/L10n.strings.json` (+2 khoá) · `scripts/add-mouse-redesign-l10n-entries.py` · `docs/AGENT_TASKS.md` (đổi trạng thái T14) · `docs/AGENT_WORKLOG.md` | `plutil -lint project.pbxproj` → `OK`; `grep -c MouseGestureAppStrip.swift /tmp/xfinder-clean-build/build.log` → `4` (>0 ✓); `orderedProfiles`/`installedBundleIDs`/`appIcon` vẫn được gọi (grep ✓); `.frame(width: 240` chỉ còn trong `mappingSection` chết; script L10n → `added 2, already present 3` | Dải chip có thật sự cuộn chip đang chọn vào khung khi mở trang (ScrollViewReader vs `.onAppear`) — cần mắt người. Cỡ icon 16pt / viền accent 1.5pt / chấm 7pt so với `variant-b.html`. Giá mỗi lần render: ~1 lookup `NSWorkspace` (`urlForApplication` + `icon(forFile:)`) cho MỖI chip trên main thread — chưa đo bằng Instruments. Trackpad cuộn ngang dải chip trên app thật. |

### Đã làm — đúng 3 điểm của §T14b + 3 luật §4
1. **F4:** `MouseGestureAppStrip` (file mới, `Views/Components/` — miễn audit token) là `ScrollView(.horizontal)` các chip: `Toàn cục` **ghim đầu** (luôn ở index 0, có dải phân cách 1×20 như wireframe) → preset theo `orderedProfiles` (đã cài trước, chưa cài vẽ `b-ghost-chip` = viền nét đứt + nền mờ) → chip của bundle người dùng tự nhập (`customProfiles`) → nút “＋”. Mỗi chip: icon thật 16pt (`NSWorkspace.icon(forFile:)`), tên ngắn (`Font.caption` 11pt ≥ 11 ✓), viền accent 1.5pt khi `id == selected`, chấm 7pt góc trên-phải khi `showsDot`. `ScrollViewReader` cuộn chip đang chọn vào giữa trong `.onAppear` + `.onChange(of: selected)` (bản SwiftUI của `scrollIntoView`). Chọn chip chỉ ghi `profile = id`; `onChange(of: profile)` sẵn có lo phần xoá chọn (đúng lối `customBundleRow`/`Xem` đang dùng).
2. **F5 (Lỗi #15):** `frontmostHint` giữ nguyên câu S8-S12, chỉ bọc nút “Xem” trong `if !frontHasChip`. `frontHasChip` đọc **danh sách chip thật** (`appChips`), không chỉ `orderedProfiles`, nên app trước mặt là bundle tự nhập cũng tính (quyết định 6 — nêu rõ ở đây).
3. **F25:** chuyển nút “Khôi phục toàn bộ ứng dụng này về mặc định” từ cuối Khối 4 sang **ngay dưới dải chip/dòng phụ** trong Khối 3, `.disabled(config.overrides[profile] == nil)` y như cũ (§T14b bước 3).
4. **F24:** nút “＋” set `@State showAdvancedApps = true`; `customBundleRow` đổi thành `DisclosureGroup(isExpanded: $showAdvancedApps)` — **chỉ đổi vị trí kích hoạt**, logic ghi `profile = id.trimmed` giữ nguyên byte-for-byte.
5. **Luật 1 (chuỗi mới vào store ngay trong bước):** +2 khoá vào `scripts/add-mouse-redesign-l10n-entries.py` rồi chạy: `"Thêm ứng dụng khác bằng Bundle ID"` (help + VoiceOver của nút “＋”), `"Chưa cài — đang xem preset dựng sẵn"` (help của chip ghost). Cả hai `scope: sentence`. Diff `L10n.strings.json` đúng **+8 dòng**, không format lại. Nút “Xem”/`Ứng dụng đang dùng`/`Mặc định toàn cục`/… đã có sẵn → tái dùng khoá cũ.
6. **Luật 2 (không placeholder):** Khối 3–9 khác giữ nguyên khối cũ đang chạy; `profileSidebar`/`appPickerRow`/`mappingSection` **để nguyên trên đĩa, chỉ ngừng gọi từ `body`** (T14e mới xoá — theo §T14e bước 3). Trang vẫn dùng được trọn vẹn sau bước này.

### Quyết định đã chốt (ghi để Claude biết chỗ lệch đặc tả)
- **Khối 3 giữ PHẲNG, không dùng card** (quyết định 7 của handoff). Wireframe vẽ Khối 3 trong `xf-card` + tiêu đề “Ứng dụng”, nhưng §T14b chỉ đòi thay sidebar bằng dải chip; `frontmostHint` + `customBundleRow` mang sẵn `.padding(.horizontal, 20)` và đặc tả bảo tái dùng **“y hệt”**, nên bọc `SettingsSection` sẽ thụt lề đôi (cardInset 10 + page 20). Hệ quả: **cuối T14 không bước nào dựng card cho Khối 3** — nếu Claude muốn đúng wireframe, đây là một dòng việc mới.
- **Không thêm chip riêng cho app đang chạy trước** khi nó không có preset (sidebar cũ có một hàng như vậy). §T14b bước 2 giả định đúng trường hợp đó ⇒ giữ nút “Xem”.
- **Quy tắc chấm** theo nguyên văn đặc tả: `!front.isEmpty && chip.id == front && profile != front` với `front = controller.lastExternalBundle` (giá trị **thô**; `frontmostBundle` thay “không có gì ở trước” bằng `Toàn cục` nên không dùng được — sẽ chấm nhầm chip Toàn cục). Hệ quả: app trước mặt không có preset thì **không có chấm**; dòng phụ + nút “Xem” gánh thông tin đó.
- **`.frame(width: 240…)` vẫn còn 1 dòng** ở dòng 432 — bên trong **`mappingSection` chết** (T14e xoá). Đọc diff: không thêm/sửa cột 240 nào; Khối 3 không còn cột app riêng.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu Trợ năng** (`trusted == false`): Khối 2 hiện `permissionBanner` + status; dải chip **không đọc `trusted`** (icon lấy từ `NSWorkspace`, không cần quyền) nên vẫn chọn app được. ✓
2. **Không chuột / chưa khai báo nút**: `appChips` chỉ phụ thuộc `GestureProfiles.all` + đã cài + `overrides`, không đọc `declaredEventButtons` ⇒ dải chip render bình thường. Không có preset nào đã cài → mọi preset là ghost, vẫn bấm được. ✓
3. **Công tắc chính TẮT**: Khối 2 hiện S3; dải chip + disclosure + F25 vẫn xem/sửa được (đúng S3). ✓
4. **Giá trị biên**: `chips` **luôn** chứa chip Toàn cục ⇒ không bao giờ rỗng; nếu rỗng thì vẫn chỉ vẽ nút “＋”, không crash. `drawnButtons`/`scrollButtonChoices` không bị T14b đụng tới. ✓
5. **Ngữ cảnh đổi giữa chừng**: bấm chip khi `controller.recording == true` → `profile` đổi → `onChange(of: profile)` chỉ xoá `recordingDirection`/`pickedDirection`/`pickedButton`, **không** hủy `controller.recording`/`recordingTrigger`/`recordingButton` — tôi không sửa modifier này (hành vi cũ nguyên vẹn). ✓
6. **Cache cũ**: không đụng `hidDump`/`hidDumpExpanded` (Khối 8, T14e). Dải chip **không cache** icon: tra `NSWorkspace` mỗi lần render — chấp nhận được vì trùng lối `orderedProfiles`/`installedBundleIDs` sẵn có, nhưng **chưa đo** (xem cột “Chưa kiểm live”).
7. **Control hứa điều không làm được**: “＋” mở đúng disclosure có ô Bundle ID + “Chọn” ghi thật; F25 gọi `controller.resetProfile(profile)` và disable đúng khi `overrides[profile] == nil`; help chip ghost “đang xem preset dựng sẵn” đúng vì bấm ghost chip chỉ đổi `profile` và resolver trả preset dựng sẵn cho bundle có preset. Không thêm control nào mới ngoài 2 thứ trên. ✓

### Kết quả `sh scripts/gate-all.sh` (nguyên văn)

```
build (arm64, compile list)        OK
tests                              Executed 1230 tests, with 0 failures (0 unexpected) in 6.582 (6.642) seconds
check-l10n-coverage                TOTAL 0 problems across 2790 entries (2790 checked, 20 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 2790 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 848 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 45 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             6
GATE: green
```

(`modified tracked files 6` lúc chạy gate = 4 file code (`MouseGesturesDetailView.swift`, `project.pbxproj`, `L10n.strings.json`, `scripts/add-mouse-redesign-l10n-entries.py`) + 2 file tài liệu (`docs/AGENT_TASKS.md`, `docs/AGENT_WORKLOG.md`) — file strip mới còn untracked nên không tính. `1230` test = `1226` của T14a + 4 `GesturePageStatusTests` mà review T14a thêm. `848 unwrapped` là số thông tin; tổng của cổng là 0.)

## 2026-10-15 (Claude review of T14a) — merged; one real defect fixed; agents now commit on their branch

For the next agent: read this, not the long T14a entry below it.

| Item | Verdict |
|:--|:--|
| T14a skeleton (9 blocks, header switch, recording state, add-only script) | **correct and in scope** — committed as `3ed7f13`. Review (4 lenses, 2 refuters per finding): every builder reachable before is reachable exactly once, the 13 moved builders are byte-identical, the block order matches the spec |
| Status line during recording | **defect, confirmed by both refuters on two lenses**: `controller.recording` is one Bool for BOTH recording modes, so recording a keyboard shortcut for a direction showed "bấm nút trên chuột". Fixed: `GesturePageStatus` (pure, in GestureLabelStructure.swift) picks the sentence; `GesturePageStatusTests` (4); labels harness M6–M8. The engine takes any key for a shortcut (no ⌘/⌥/⌃ needed), so the Phím tắt page's sentence could not be reused |
| App list full width in block 3 | interim until T14b; capped at 360 pt so its shaded box does not span the page |
| Header switch had no VoiceOver label | pre-existing; added `Bật/tắt cử chỉ` (wireframe B names it) |
| Status `ĐANG LÀM … T14a xong` | fine for a multi-step task |

**Process from now on (owner approved Q-PROC-1):** commit on your branch. T14 uses ONE branch for all remaining
steps: `git switch -c agent/zed-T14 main` for T14b, then each later step continues on that same branch
(`git switch agent/zed-T14`) with one commit per step. Never commit on `main`, never push, never merge. Next: **T14b**.

## 2026-10-15 (Zed / DeepSeek V4.1 Flash, Viber Bedrock) — T14a: dựng khung trang Chuột & cử chỉ theo B (chưa commit)

**Lệnh của chủ:** *“Đọc docs/AGENT_QUICKSTART.md, rồi docs/AGENT_TASKS.md. Làm ĐÚNG bước T14a trong
`docs/specs/T14-mouse-gestures-B.md`, theo quy trình mục 3. Dán kết quả sh scripts/gate-all.sh vào
`docs/AGENT_WORKLOG.md`. Gặp điều kiện dừng thì dừng.”* → **chỉ T14a**, không sang T14b. **Không commit**
(chủ cấm); mọi thứ nằm nguyên trong working tree, nhánh vẫn `main`. Không có điều kiện dừng nào xảy ra.

| Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
|:--|:--|:--|:--|
| **T14a** — khung 9 khối của phương án B | `XFinder/Views/Detail/MouseGesturesDetailView.swift` (toàn bộ `body` + `readinessRow` + 2 doc comment; `permissionBanner` giữ nguyên) · `XFinder/Resources/L10n.strings.json` (+1 khoá) · `scripts/add-mouse-redesign-l10n-entries.py` (mới) · `docs/AGENT_TASKS.md` (đổi trạng thái T14) | `build-and-check.sh` → BUILD SUCCEEDED, 0 lỗi, mọi file tên `OK`, tài nguyên đã bundle, `arm64` · `grep -c MouseGesturesDetailView.swift /tmp/xfinder-clean-build/build.log` → `4` (>0 ✓) · `swift test` → **1226 tests, 0 failures** · script L10n → `added 1, already present 0` | Hình dạng thật của trang (khung 9 khối, công tắc F1 kiểu `.switch`, dòng “đang ghi” màu accent) — app **chưa build-cài-chụp**. VoiceOver thứ tự Khối 1→9 + trạng thái đang ghi. Ba trạng thái permission / no-mouse / recording trên máy thật. |

### Đã làm — đúng 5 điểm của §4 T14a
1. **F1 (Lỗi #11):** `Toggle(...).labelsHidden()` ở trailing `PageHeader` nay thêm `.toggleStyle(.switch).controlSize(.small)`.
2. `permissionBanner` (F2/F3/S2) **giữ y nguyên byte-for-byte**, gọi ngay dưới header khi `!trusted`.
3. `readinessRow` thêm nhánh `controller.recording` lên **đầu** (tint `.accentColor`, icon `record.circle`, câu “Đang ghi — bấm nút trên chuột (Esc để hủy).”); 4 nhánh S3–S6 cũ giữ nguyên logic, vẫn nền `tint.opacity(0.12)` + `Capsule`.
4. Khung 9 khối: `body` viết lại thành 9 `VStack`, mỗi khối có comment `// ── Khối N — …`, đúng thứ tự CONTRACT (1 header · 2 status · 3 app chooser · 4 gesture map · 5 side buttons · 6 hold & scroll · 7 tilt · 8 diagnostics · 9 footer). Khối 3–9 là **các section cũ đang chạy đặt vào đúng vị trí khối** của B (luật 2: không placeholder). `activitySection` (`DEBUG_SHOW_ENGINE_LOG` = `false`) vẫn ở cuối, vẫn bị gate. Giữ `.padding(.vertical,20)` + `.pageWidthSafe()`.
5. Chuỗi mới vào store ngay trong bước (luật 1): “Đang ghi — bấm nút trên chuột (Esc để hủy).” → EN “Recording — press a button on the mouse (Esc to cancel).”, `scope: sentence`, khớp `variant-b.html` dòng 107. Chưa có trong store → tạo `scripts/add-mouse-redesign-l10n-entries.py` (mẫu `add-system-hud-l10n-entries.py`, chỉ-thêm) rồi chạy. Diff `L10n.strings.json` đúng **+4 dòng**, không format lại.

### Trả lời 7 việc-cạnh (§5) — đọc code, không mở app
1. **Thiếu Trợ năng** (`trusted == false`): Khối 2 hiện `permissionBanner` (S2) rồi `readinessRow` nhánh S6; panel bên phải (Khối 4) không đọc `trusted` nên vẫn dùng được. ✓
2. **Không chuột / chưa khai báo nút** (`declaredEventButtons == nil`): `drawnButtons` rơi về slot nguyên mẫu; `buttonListSection` (Khối 5) hiện placeholder trung thực; Khối 3 không phụ thuộc chuột. ✓
3. **Công tắc chính TẮT**: Khối 2 hiện S3; Khối 3–8 vẫn render (xem/sửa được), đúng câu S3 “sơ đồ bên dưới đã có sẵn phím tắt”. ✓
4. **Giá trị biên**: `drawnButtons` rỗng → nhánh `GestureButtonList` cũ, không crash. `scrollButtonChoices` **luôn** thêm `config.scrollButton` (đã đọc hàm) nên không bao giờ rỗng thật. ✓
5. **Ngữ cảnh đổi giữa chừng**: `onChange(of: profile)` vẫn chỉ xoá `recordingDirection`/`pickedDirection`/`pickedButton`, **không** hủy `controller.recording`/`recordingTrigger`/`recordingButton` — hành vi cũ, tôi không đụng modifier này. ✓
6. **Cache cũ**: `hidDumpRow` vẫn lazy `.onChange(of: hidDumpExpanded){ if expanded && hidDump.isEmpty { loadHIDDump() } }` (chỉ dời vị trí vào Khối 8). ✓
7. **Control hứa điều không làm được**: control Lỗi #1 (“Ghi nút” cạnh “Nút cuộn” mà thực ra ghi nút giữ) đã bị thay bằng `Picker` ở T15 đã commit (`2c26eb0`); T14a không đưa nó trở lại. ✓

### Hai điều cần Claude biết
- **`mappingSection` + `appPickerRow` để nguyên trên đĩa, chỉ ngừng gọi từ `body`** — đúng câu §T14a: *“KHÔNG xoá các hàm khác chưa dùng tới trong bước này (ví dụ `mappingSection` cũ) — chỉ ngừng gọi chúng từ `body`”*. Hệ quả: `HStack` sơ đồ+bảng tạm **trùng lặp** giữa `mappingSection` (chết) và Khối 4 (mới); sẽ hết ở T14c/T14e. Không xoá vội.
- **Lệch §3 bước 2 và 7 (vì chủ cấm commit):** không tạo nhánh `agent/zed-T14a`, không commit, nên bước 7 không thể ghi `CHỜ REVIEW (nhánh agent/…)`. Thay vào đó trạng thái T14 trong `AGENT_TASKS.md` là `ĐANG LÀM (Zed, 2026-10-15) — T14a xong, T14b–T14f còn` (theo §3 bước 3). Các phiên trước cố ý không đổi trạng thái (“đó là việc của Claude”). Nếu Claude không muốn, đây là revert một dòng.

### Kết quả `sh scripts/gate-all.sh` (nguyên văn, chạy sau khi sửa 2 file tài liệu)

```
build (arm64, compile list)        OK
tests                              Executed 1226 tests, with 0 failures (0 unexpected) in 6.308 (6.367) seconds
check-l10n-coverage                TOTAL 0 problems across 2786 entries (2786 checked, 20 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 2786 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 843 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 45 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             4
GATE: green
```

(`modified tracked files 4` = `AGENT_TASKS.md`, `AGENT_WORKLOG.md`, `L10n.strings.json`, `MouseGesturesDetailView.swift` — khớp cây cuối. Dòng `843 unwrapped` là số thông tin, không phải lỗi: tổng của cổng là 0. `audit-ui-tokens` in “across 0 files” là bình thường ở đây.)

## 2026-10-15 (Claude review of the three entries below) — merged as topic commits, six HUD bugs fixed

For the next agent: read this entry, not the long ones below it.

| Item | Verdict | Commit |
|:--|:--|:--|
| T02 T03 · T04 T13 · T05 T06 T08 T09 T10 · T11 T12 · T16 · T01 | correct as written | `c19dc73` · `05693fa` · `e0ee021` · `293cabc` · `6c8ee2c` · docs commit |
| T15 | two gaps: the menu was EMPTY whenever no mouse had been measured (`declaredEventButtons ?? false`), and the stored value could be missing from the list (a menu Picker then renders blank). Fixed with `scrollButtonChoices` | `2c26eb0` |
| HUD takeover (no spec) | the DisplayServices claim is RIGHT — re-measured from a terminal: a write from one process is read back by another. But six failure cases were missing: DOWN/UP decided separately, ⌥⇧ quarter steps swallowed, HDMI/aggregate outputs swallowed with no effect, no feedback at 0/100 %, brightness stepped from a stale cache, the "Độ sáng" switch promising a readout that cannot appear. All fixed, mutations M57–M59 added (notch harness 60/60 RED) | `bf8798f` |
| T18 / T19 | fine. The T18 "clean tree" precondition was a spec bug given the no-commit instruction | — |

Process changes that follow (read them in `docs/AGENT_QUICKSTART.md` rules 10–11 and `docs/AGENT_TASKS.md` §0, §3, §3c):
`sh scripts/gate-all.sh` is the one gate to run and paste; a feature asked for mid-session gets a short spec with the
failure-case list BEFORE code; say where a measurement ran (terminal ≠ installed app); without commits, list the files of
each task. Next task: **T14** from `docs/specs/T14-mouse-gestures-B.md`, one step per session.

## 2026-10-15 (later, 3) — Zed (DeepSeek V4.1 Flash, Viber Bedrock): HUD-suppression feature built (uncommitted) · a stale notch mutation anchor repaired · **T14 not started**

**Owner's instruction:** `Ok làm đủ luôn đi` plus *“Trong tính năng Brightness, Volume khi tôi sử dụng báo tình trạng thực trên Notch thì tôi muốn ẩn luôn cái Status Brightness, Volume mặc định popover mặc định của MacOS, chỉ dùng trong Notch là đủ.”* — while XFinder reports brightness/volume on the notch, macOS must not draw its own square as well; the notch is the only readout. **Nothing was committed** (owner forbade it); everything below is in the working tree.

### 1. Probe first (two rounds, delegated to a sub-agent) — two documented project beliefs were wrong

Read-only reconnaissance + standalone `swiftc` probes in `/tmp` (no repo build, so no contention). Raw evidence in the sub-agent's reports; the decisive findings:

| Question | Measured answer |
|:--|:--|
| Does a `.cghidEventTap` tap on `systemDefined` see the brightness/volume keys? | **Yes.** Type 14, subtype 8, `data1` = keytype in bits 16+, phase in bits 8–15 (0xA down, 0xB up). |
| Does `return nil` hide the native OSD? | **Yes** — the layer-101 `MenuBarAgent` window never appears; the change we apply still lands. True for volume **and** brightness. |
| Does a bare programmatic change draw the OSD? | **No** (CoreAudio and `DisplayServices` both). |
| Can XFinder read/write brightness itself? | **Yes, through the private `DisplayServices`** — `GetBrightness` returns a live 0…1, `SetBrightness` really moves the panel (WindowServer logs the swap). `IODisplaySetFloatParameter` returns `kIOReturnUnsupported` (-536870201), as the code already said. |
| What is actually frozen? | **The IOKit `IODisplayParameters` snapshot** under the new backlight architecture — i.e. the premise of `LiveActivity.swift`'s old “brightness has NO HUD on purpose” comment was wrong, and `ScreenBrightness.readLevel()` was returning a boot-time value (a live bug). |
| Is the drawer `OSDUIHelper`? | **No.** `pgrep -fl OSDUIHelper` → nothing; the square is drawn by `com.apple.MenuBarAgent` (pid 465, layer 101). Killing/OSDUIHelper is not a route. |

Consequence for design: **volume** pairs with the notch HUD that already existed; **brightness** had *no* notch HUD, so swallowing its key would have left zero feedback. Per the owner's wording (“chỉ dùng trong Notch là đủ”) the brightness HUD was therefore built too, rather than shipping a switch that hides a HUD with nothing to replace it.

### 2. What was built (files)

| File | Change |
|:--|:--|
| `XFinder/Core/Notch/SystemKeyInterceptor.swift` **NEW** | The one `.cghidEventTap` (type 14, `.defaultTap`, head insert). Swallows a media key when `LiveActivity.HUDSuppression.decide` says so, then applies it: volume/mute via the existing CoreAudio HAL (so `VolumeObserver.onChange` shows the notch HUD), brightness via `ScreenBrightness.setLevel` + `LiveActivityMonitor.brightnessChanged(from:to:)`. Re-arms on `tapDisabledByTimeout`, passes through our own posted events (`srcPID == getpid()`), and is armed only while the switch is on **and** Accessibility is granted. |
| `XFinder/Core/Notch/LiveActivity.swift` | `Kind.brightness`; `BrightnessState` + `brightnessItem(old:new:)`; the pure `MediaKey` / `HUDSuppression` rules (`phase(data1:)`, `decide(keyType:phase:context:)`); the old “no brightness HUD” comment corrected with the probe evidence. |
| `XFinder/Core/Notch/LiveActivityMonitor.swift` | `brightnessOn` reader + `brightnessChanged(from:to:)` (takes the real before/after, so the **first** press is never silent). |
| `XFinder/Core/Services/ScreenBrightness.swift` | Private `DisplayServices` dlopen shim (read/write/can-change) + `nonisolated static canSetDirectly`; read now prefers the live value, IOKit stays as fallback; `setLevel` writes via DisplayServices and only falls back to NX keys when it cannot. |
| `XFinder/Views/Detail/LiveActivitiesDetailView.swift` | New rows: **Độ sáng** (brightness activity) and a new section **Hộp điều chỉnh của macOS** → **Chỉ dùng notch cho độ sáng và âm lượng** (`notch.activity.hideSystemHUD`, default **false**, disabled without Accessibility, with the grant `InlineNote`). The volume row's subtitle no longer repeats the now-false “no brightness HUD” claim. |
| `XFinder/App/XFinderApp.swift` | `SystemKeyInterceptor.shared.applySettings()` at launch and on `didBecomeActive`. |
| `Tests/…/FeatureKeyDefaultsTests.swift` | Two new rows (`notch.activity.brightness`, `notch.activity.hideSystemHUD`). |
| `Tests/…/LiveActivityTests.swift` | 5 new tests: brightness HUD (baseline/no-change/clamp/symbols), `phase(data1:)`, and the suppression decision (swallow vs pass-through for every reason to refuse). |
| `scripts/add-system-hud-l10n-entries.py` **NEW** | Add-only; 8 new keys. |
| `XFinder.xcodeproj/project.pbxproj` | 4 hand-written entries for `SystemKeyInterceptor.swift`. |

`notch.activity.hideSystemHUD` is a **new** key with default `false`, so nothing changes for anyone who does not ask; no existing key's meaning or default was touched (§2 forbids that).

### 3. Every command run, and its result

| Command | Result |
|:--|:--|
| `plutil -lint XFinder.xcodeproj/project.pbxproj` | `OK` |
| `python3 scripts/add-system-hud-l10n-entries.py` | `added 8, already present 0` |
| `swift test --package-path Tests` | **1224 tests, 0 failures** (was 1219; +5 new). One intermediate failure — `FeatureKeyDefaultsTests` wants exactly ONE canonical reader per key and the interceptor had two — fixed by folding both reads into one `nonisolated static` property. |
| `sh scripts/build-and-check.sh` | `OK` (all named files compiled, resources bundled, arm64). Two compile errors fixed on the way: `CGEventType.systemDefined` does not exist in this SDK (compared by raw value 14 instead) and `subtype` is `NSEvent.EventSubtype`, not `Int16`. |
| `SystemKeyInterceptor.o` present + `strings` on `XFinder.debug.dylib` | `hideSystemHUD` ×3, `DisplayServices` ×5, `notch.activity.brightness` ×1 — the new file really is in the app target. (The app's code lives in `XFinder.debug.dylib`, not the 40 KB launcher — a first grep of the launcher read as “missing”.) |
| `sh scripts/mutation-check-notch.sh` | **57/57 mutations RED, 0 GREEN, 0 harness errors, restored tree green** — see §4. |
| `sh scripts/mutation-check-l10n.sh` | every mutation RED, store restored byte-identical, suite green again. |
| `check-l10n-coverage` / `-duplicates` / `audit-l10n-interpolations` / `check-sidebar-groups-l10n` / `verify-l10n-runtime` | `TOTAL 0` each. |
| `audit-l10n-literals.py` | `TOTAL 0 wrapped-but-untranslated, 843 unwrapped` — the gate's own total is 0; the informational unwrapped count rose **842 → 843** because a new notice kind needs a new title key (`titleKey: "Độ sáng"`), the same kind of literal the other 15 keys in that file already are, and it **is** in the store and translated. |
| `audit-ui-tokens.py` | `TOTAL 0`. |
| Manual mutation of the new pure rules | Removed the `hideSystemHUD` guard from `decide` → `LiveActivityTests` went **RED** (1 failure); reverted → green. The new tests really bite. |
| `git --no-pager diff --shortstat` | 29 files changed, 633 insertions(+), 75 deletions(-) — **includes the owner's/earlier agents' pre-existing uncommitted work**, not only mine. |

### 4. Found and repaired: `mutation-check-notch.sh` had been aborting at M12 (pre-existing, not mine)

`mutation-check-notch.sh` aborted with `HARNESS ERROR: anchor not found in XFinder/Core/Notch/LiveActivity.swift`. Evidence it is pre-existing and unrelated to my edits: the anchor text `if current?.kind == item.kind { current = item; return true }` **does not exist in `HEAD` either** (`git show HEAD:… | grep -c` → 0); the P12 `outranks` change restructured that block into `if let c = current, c.kind == item.kind { … }`, and my diff never touches `push`/`outranks` (verified). Because the harness aborts on the first broken anchor, **M12 onward had never been verified** — a broken gate that read like a passing one.

Repaired M12's anchor to the current code (mutation = always `enqueue` on a same-kind notice, i.e. “stack instead of replace”) and re-ran: **57/57 RED**, including the 45 mutations after M12 that had never run. This is a change to a gate script, so it is flagged for Claude's review.

### 5. T14 — NOT started (honest statement)

I read the full input chain (`CONTRACT.md` including the 11 defects and the card grammar, `inventory.md` F1–F29 / S1–S68 / §3 duplicates / §4 the 15 confirmed defects / §5 “must keep”, the variant-B essentials, `data.json`/`stored-config.json` notes) and the current code (`MouseGesturesDetailView.swift`, its 6 components, `DeviceCapabilityModel`, `GestureController`'s public API). **No mouse/gesture file was edited.**

Reason: T14 is a layout *replacement* of a 969-line view plus 6 components with a full mutation-gate acceptance suite. The spec's step 1 (“khung trang theo phương án”) cannot be done partially without leaving the page half-restructured, and the project's rule is to stop at a green state rather than ship a half-page. The budget this session went to the HUD feature (probe → implementation → build → two harnesses) and to the M12 repair. A partial rewrite would have been worse than none.

Ready for the next session, in the spec's order: (1) replace the 240-pt `profileSidebar` (`MouseGesturesDetailView.swift:392-417`) with variant B's **app chip strip** — this alone fixes Defect #8 (two sidebars) and Defect #2 (real icons), and `appPickerRow` (`:478-512`) is dead code that already shows the intended “one control” shape; (2) the **two-column card** (figure + never-blank inspector) replacing the diagram/detail-panel pair; (3) move `hidDumpRow` (`:313`, currently near the top) into one collapsed **Chẩn đoán chuột** disclosure at the bottom; (4) new strings via a new add-only `scripts/add-mouse-redesign-l10n-entries.py`; (5) the 13 góp ý from the T19 entry above, of which the **false “Claude (preset)” chip (#9)** and the **contrast failures #1–#3** are the ones with measured evidence. Every `GestureController` binding must be kept (inventory §5); `GestureModel`/`GestureEngine` must not change.

### 6. What I could NOT verify (for Claude)

* **No live run.** The interceptor has never executed inside XFinder: I did not build-and-install, launch, or press a physical brightness/volume key. Every claim about its behaviour rests on the standalone probe plus reading the code. `sh scripts/install-mouse-rebuild.sh` was deliberately not run (it installs).
* **No harness covers the new code.** `mutation-check-notch.sh` covers `LiveActivity.swift` (and passed 57/57 with my changes), but nothing mutates `SystemKeyInterceptor.swift` or the `DisplayServices` shim — their behaviour is guarded only by the pure rules' tests. Adding a harness is a new gate; I did not invent one.
* **macOS 14 is untested.** The app targets macOS 14+, and `DisplayServices` symbol availability, the frozen-IORegistry behaviour and the `MenuBarAgent`-draws-the-OSD fact were measured **only** on this Mac (macOS 27). The code degrades honestly (`canSetDirectly` false → brightness keys pass through), but that path was not measured either.
* **Physical keys vs synthesised keys.** The probe's keys were synthesised (`NSEvent.otherEvent`); the `srcPID == getpid()` discriminator was measured for synthetic events only. For real HID events `srcPID` is *expected* to be 0, but that was not observed.
* **The untrusted (no-Accessibility) case** was never measured (`AXIsProcessTrusted` was true throughout); I could not revoke TCC. The code passes through when untrusted, but that is reasoning, not measurement.
* **Brightness read/write quality**: I did not look at the panel, so “the screen really dims when XFinder sets 0.3” is unconfirmed (only the WindowServer log shows the swap). The `SystemControlsPanel` brightness slider now routes through `DisplayServices` — that panel was not opened.
* **Whether the native OSD stays hidden with the tap installed by the app** (as opposed to a standalone probe) is the single most important thing to measure live.
* **Known limitation, by choice:** if the Mac has no default output device, `SystemControls.setVolume` no-ops, so a swallowed volume key would change nothing and show no notch HUD either. Gating on that needs either a `nonisolated` CoreAudio probe or a main-actor snapshot published into a `Locked<Bool>`; both are more machinery than a degenerate case (no audio at all) justifies, so it is left as-is and recorded here. The same shape applies to `notchEnabled` standing in for `canPresentActivities` on the tap thread (documented in the code): the only divergence is the brief window before the surface panel exists.

## 2026-10-15 (later, 2) — Zed (DeepSeek V4.1 Flash, Viber Bedrock): T19 gate 2 closed — owner picked variant **B**, review written

**Owner's instruction:** `B, góp ý` — i.e. **choose wireframe variant B** and give design feedback on it. That is T14's
gate-2 input. **Nothing was committed** (owner forbade it); this entry only records the decision + the review.

### What was run, and the result of each command

| Step | Command | Result |
|:--|:--|:--|
| Server still up | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8766/wireframe-a-b-c-d.html` · `lsof -ti :8766` | **`200`** · PID **3894** ✅ (unchanged) |
| Read the spec chain | `cat` of `CONTRACT.md` (18 KB), `variant-b.html` (45 KB), `inventory.md` §2–§5 (F1–F29 / S1–S68), `data.json`, `stored-config.json` | read via terminal (all outside the repo, `read_file` cannot reach them) |
| Render B | `sh render.sh "v=b&tt=du-lieu&mau=mau&frame=1&win=s" /tmp/xf-b/b-du-lieu-s.png 1181 611 wireframe-b.html` | `rendered` ✅ |
| Probe B (measured) | `node .agents/skills/ui-ux/scripts/probe.mjs "…/wireframe-b.html?v=b&mau=mau&frame=1&win=s" --quick --widths 1181 --pw <prebuilt evon-probe> --out /tmp/xf-b/probe` | 2 real contrast fails (`P1` `Nút 6` 2.58:1; `P2` `.b-row-hint` 2.66:1); `truncatedCount 0`, `overflowingElements 0`, `hasHorizontalScroll false` ✅ (defects #3/#4 clear at 1181×611) |
| Probe B, other states | same, `tt=thieu-quyen` · `tt=dang-ghi` · `tt=khong-chuot` | `khong-chuot` → **0 P** ✅; `thieu-quyen` → same 2 P as `du-lieu`; `dang-ghi` → **12 P**, all from B's own `opacity:.4` dimming of blocks 3/5/6/7/8/9 (1.42–1.92:1) |
| `grep` evidence for the gaps | `grep -c` for `Khôi phục` / `Mở Phím tắt trong Cài đặt` / `chưa gán phím tắt` / `Bấm nhanh` / `Bấm thử` in `variant-b.html` | `Khôi phục` **0**, `Mở Phím tắt trong Cài đặt` **0**, `chưa gán phím tắt` **0**, `Bấm nhanh` 4, `Bấm thử` 1 |
| Probe screenshots served | `nohup python3 -m http.server 8767 -d /tmp/xf-b &` · `curl …` | `200` ✅ · PID **7237** (temporary, for the review links only; `kill 7237` to stop) |

### Decision + review (this is T14's input)

* **Chosen variant: B · “Sơ đồ chuột + bảng bên”** (it is also the one `CONTRACT.md` marks `data-recommended`). Link:
  `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=b`.
* **B fixes all 11 defects** in `CONTRACT.md` “What is wrong today” — verified against the file, not taken on trust:
  #1 scroll button now has its own picker (block 6), #2 real app icons, #3 no truncation at 1181 (probe-measured),
  #4 hold badge removed from the figure, #5 one vocabulary “Nút N”, #6 hold button changes in ONE place, #7 action
  names visible without a click, #8 chip strip instead of a second sidebar, #9 diagnostics collapsed, #10 short copy +
  tags, #11 switches + card grammar.
* **Open problems found (ranked; full text in the chat reply):**
  1. **Hỏng (đo)** — `assets/mouse.js:99-100` still fades the *figure’s* undeclared chip (`opacity:0.42` + `--text3`) →
     `Nút 6` 2.58:1. B already fixed the same class of bug for `.b-ghost-chip`; this sibling was missed.
  2. **Hỏng (đo)** — `.b-row-hint` uses `--text3` → 2.66:1.
  3. **`dang-ghi` (đo)** — the recording dim (`opacity:.4; filter:saturate(.5)`) drops 12 labels to 1.42–1.92:1;
     intentional per contract (“dimmed/inert”) but far too strong — recommend ~0.55–0.6 + `aria-disabled`.
  4. **Thiếu** — `F25` (reset whole profile) has **no home** in B (`grep` → 0).
  5. **Thiếu** — `F12`+`S56` (unbound-system-action warning + “Mở Phím tắt trong Cài đặt”) have **no home** (`grep` → 0).
  6. **Thiếu** — `F17` (hold-button “Bấm nhanh”) has no slot in block 6 (currently N/A in the data, but inventory §5 keeps it).
  7. **Thiếu** — no path from a measured undeclared button (“Bấm thử…”) to “Dùng làm nút giữ”, although B’s own `dang-ghi`
     copy promises XFinder will use the pressed button; inventory §5 requires keeping the record-a-real-press mechanism.
  8. **Chữ** — chord written two ways: `Lùi (Cmd+[)` (block 5) vs `Lùi (⌘[)` (inspector/figure).
  9. **Chữ** — the dashed **“Claude (preset)”** chip contradicts `data.json` (`frontmost` = `com.anthropic.claudefordesktop`,
     `hasPreset:false`; the preset key `com.anthropic.claude` is `knownAppBugs[0]` — a bundle id that “never applies”).
  10. **Chữ** — “thường là nút hông trên/dưới” is invented; `data.json` gives no side-position hint for `Nút 4`/`Nút 5`.
  11. **Trùng** — `F16` (side-button click action) lives in both block 5 and the inspector’s button view.
  12. **Cần xác nhận** — the stored scroll button is `Nút 6`, which `data.json` marks `declared:false`; B shows it under
      “CHƯA KHAI BÁO”, which deviates from CONTRACT defect #1 (“popup of the mouse’s **declared** buttons”). Honest, but
      confirm with Claude whether declared-only is the rule.
  13. **Nhỏ** — `.xf-tag` renders 10.5px (shell), just under the contract’s ≥ 11px floor; 33 texts < 12px at 1181 (mostly the
      shell sidebar + 11px captions, which the contract allows).

### What was NOT verified (for Claude)

* **No live app run.** All of the above is the wireframe only; nothing was built, launched, or measured inside XFinder.
* Probe ran `--quick` (no tab/hover/popup pass) and only at **1181×611**. The 1440×900 window, both themes, and every
  popup/overflow case were **read statically, not measured**. `dang-ghi`/`thieu-quyen`/`khong-chuot`/`du-lieu` were probed;
  the tilt-on state, the master-switch-off copy, and the named-tap-failure copy were **not** rendered.
* The probe’s console 404 is `favicon.ico` (every referenced asset returns `200`; `favicon.ico` → `404`) — benign.
* The probe’s “MỤC LẶP DÀY CHỮ” row is the **shell sidebar** (“CÔNG CỤ”, 10 lines), not variant B.
* **T14 has not been started** — it needs this gate-2 input plus the owner’s go-ahead; its file scope is
  `MouseGesturesDetailView.swift` + the six `XFinder/Views/Components/Gesture*.swift` files.

### Process note

The probe needs Playwright; it was **not** installed into the repo — the pre-built harness at
`/private/tmp/claude-502/…/scratchpad/evon-probe` (the one `CONTRACT.md` names) was reused via `--pw`. Nothing was written
outside `/tmp/xf-b` and the design folder.

---

## 2026-10-15 (later) — Zed (DeepSeek V4.1 Flash, Viber Bedrock): ran the whole §6 queue, T01–T19 except T07 and T14

Owner asked, explicitly and twice, to **run every remaining TODO in `docs/AGENT_TASKS.md` §6** and log it here so Claude
can decide the next move. **Nothing was committed** — the owner forbade commits, so every change sits uncommitted in the
working tree on `main` (`HEAD = 07f16af`). The board's own rule is "one task per session"; the owner overrode it, so the
run happened in one session and no task status in §6 was flipped (that is Claude's call).

**T07 was skipped on purpose** (status `HOÃN` — folded into the Mouse & Gestures redesign). **T14 is blocked at gate 2**
(the owner has not picked wireframe A/B/C/D yet) and was not started.

### Environment / baselines measured before any edit

| Step | Command | Result |
|:--|:--|:--|
| Swift / Xcode | `swift --version` · `xcodebuild -version` | Swift 6.4, Xcode 27 |
| Tests (baseline) | `swift test --package-path …/Tests` | **1199 tests, 0 failures** (this is the number that must not drop) |
| Build (baseline) | `sh scripts/build-and-check.sh` | OK, ≈ 28 s |
| L10n gates + UI tokens | the 6 gates below + `audit-ui-tokens.py` | all `TOTAL 0` |
| Literal audit (the number that must not rise) | `python3 scripts/audit-l10n-literals.py` | **`842 unwrapped`** |

### What each task changed, and the exact commands run

| Task | Change | Commands run and result |
|:--|:--|:--|
| **T01** | `README.md:213` `(399 test)` → `(~1199 test)` | `git diff --stat` = 1 file / 1 line ✅ |
| **T02+T03** | old 1-param `.onChange(of:)` → 2-param, 4 files / 6 lines | acceptance `grep` → 0 hits ✅ · build OK ✅ |
| **T04+T13** | `allowedFileTypes` → `allowedContentTypes` + `import UniformTypeIdentifiers`, 3 files | `grep -rn "allowedFileTypes" XFinder --include='*.swift'` → **empty** ✅ · build OK ✅ |
| **T05, T06, T08, T09, T10** | VoiceOver `.accessibilityLabel`s + one bare `"Ghim"` → `L10n.t("Ghim")` | 6 L10n gates `TOTAL 0` ✅ · ui tokens 0 ✅ · `842 unwrapped` unchanged ✅ · build OK ✅ · tests 1199/0 ✅ |
| **T11** | added `testUsagePageNameCoversEveryBranch()` to `Tests/XFinderLogicTests/DeviceCapabilityTests.swift` | **proved red**: flipped `>=`→`>` in `DeviceCapabilityTypes.swift`, saw `("Other") is not equal to ("Vendor")`, reverted **by hand**, `git diff --quiet -- …DeviceCapabilityTypes.swift` → `SẠCH` ✅ · tests **1200/0** ✅ |
| **T12** | new `Tests/XFinderLogicTests/TimeZoneConversionTests.swift` (16 tests) | `swift test --filter TimeZoneConversionEdgeCaseTests` → 16/0 ✅ · **proved red**: changed one expectation (`offsetLabel(-18000)` `"UTC−5"`→`"UTC-5"`), saw 1 failure, reverted ✅ · full suite **1216/0** ✅ |
| **T16** | `GestureShortcut.label` names table gains the ANSI letter/digit codes + `⌫`/`⎋`; new `Tests/XFinderLogicTests/GestureShortcutLabelTests.swift` (3 tests) | **proved red**: deleted `18:"1"`, saw `("⌘Key 18") is not equal to ("⌘1")`, added it back ✅ · `sh scripts/mutation-check-gesture-labels.sh` → **5/5 RED**, source restored byte-identical, post-restore **1219/0** ✅ · build OK ✅ · `git diff --stat` = 2 files ✅ |
| **T15** | `MouseGesturesDetailView.swift` `switchesSection`: the "Nút cuộn" `Button("Ghi nút") { triggerRecording() }` → a `.menu` `Picker` (max width 140) over `drawnButtons`; removed the number `Text` | build OK ✅ · tests **1219/0** ✅ · 6 L10n gates `TOTAL 0` ✅ · `grep -n triggerRecording` → only lines 331/733/840 (all outside the block) ✅ · **no new strings** ✅ |
| **T18** | run-only, no source edits | `sh scripts/mutation-check-gesture-labels.sh` → **5/5 RED**, restored byte-identical, post-restore **1219/0** ✅ · `sh scripts/mutation-check-gesture-ui.sh` → **8/8 RED**, 4 files restored byte-identical, post-restore **`Executed 1219 tests, 0 failure(s)`** ✅ · re-`git status --short` → **no leftover mutant** ✅ |
| **T19** | open the wireframes (no repo edits) | `python3 build.py a b c d` → `wireframe-a-b-c-d.html` (207 066 bytes) ✅ · `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8766/wireframe-a-b-c-d.html` → **`200`** ✅ · server PID 3894 |
| **T14** | **not started** | blocked at gate 2 = the owner picks A/B/C/D |
| **T07** | **skipped on purpose** | status `HOÃN` |

**Final state:** `swift test` → **1219 tests, 0 failures**; `build-and-check.sh` → OK; the 6 L10n gates → `TOTAL 0`;
`audit-ui-tokens.py` → `TOTAL 0`; `audit-l10n-literals.py` → `842 unwrapped` (unchanged). `git diff --stat` = 19 tracked
files, +119/−30, plus 2 new untracked test files.

### The T19 links for the owner (gate 2 — please pick one)

- A — list layout: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=a`
- B — diagram + side table (recommended in the brief): `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=b`
- C — table grouped by app: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=c`
- D — the reference-image layout: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=d`

The server is still running (`python3 -m http.server 8766 -d ~/github/XFinder-design/mouse-gestures-2026-10-15`).
**The owner has not chosen yet** — that choice plus their comments is the input for T14.

### What could NOT be verified (do not read any of this as "done")

- **No live app test at all.** The app was never launched, so **every VoiceOver label** (T05/T06/T08/T09/T10) is
  **unverified**: whether VoiceOver reads the right thing is not measurable from here. Same for the `L10n.t("Ghim")` swap.
- **T04/T13** — the open/save panels' type filtering is **unverified live** (needs a real panel).
- **T15** — picking a scroll button on the page is **unverified live**; only the code path and the gates were checked.
- **T16** — the labels are unit-tested, but what the settings page actually renders is **unverified live**.
- **T18** — the harnesses ran on the **current working tree**, not on the commit `63bc3c3` they name, because the tree now
  carries this session's edits (the owner forbade committing). The numbers are still the acceptance numbers.
- **T19** — nothing to verify beyond the 200; the owner's choice is still outstanding.

### Stop-condition / spec-vs-code conflicts hit (Claude should decide)

1. **T18 step 1 is unsatisfiable as written.** It requires `git status --short` to show **no `M` file** before running. With
   the owner's "do not commit" instruction the tree necessarily holds this run's edits. Read as "no *leftover mutant* before
   starting" — which was true. Recorded rather than stopping.
2. **T12's class name already existed.** A `final class TimeZoneConversionTests` lives in
   `Tests/XFinderLogicTests/SmartSelectConversionTests.swift` (it drives the code through `convert`). The new file the spec
   named (`TimeZoneConversionTests.swift`) therefore could not declare the same class, so its class is
   **`TimeZoneConversionEdgeCaseTests`** and it drives the **table and parsers directly** (`zone(for:)`, the whole
   `ambiguous` set, offset syntax, the `maxLength` boundary) — coverage the existing class does not have. The file name is
   as the spec wrote it.
3. **T15 number convention — verified, not guessed.** The spec's parenthetical said `scrollButton` is 0-based; confirmed
   against `GestureConfiguration.validate()` (`(1...31)`) and `DeviceCapabilityModel.role(forEventButton:)` (compares
   `context.scrollButton` to the **0-based event button number**), and `L10n.t(ButtonKey.index(n))` renders
   `ButtonLabelStructure.displayNumber` = `n + 1`. The Picker therefore tags items with the same 0-based number it stores.
4. **T12 offset expectations** were derived from the code and a real `TimeZone(identifier:)!` measurement
   (New York = UTC−4 in July 2026, UTC−5 in January), not copied from a guess.

### Stale docs found (not fixed — Claude's call)

- `AGENT_TASKS.md` §5 says `main = 63bc3c3`; actual HEAD is `07f16af`.
- `AGENT_TASKS.md:149` says "~1196" tests; measured **1199** before T11 and **1219** after T16.
- **T01's acceptance grep can never be empty**: `AGENT_TASKS.md` itself quotes the string `(399 test)` at lines 149 and 153,
  so `grep -rn '(399 test)' README.md docs/*.md` keeps matching spec text. README is fixed; the residue is the board.
- `docs/PENDING_TESTS_AND_DECISIONS.md` header says "Cập nhật: 2026-10-13" but it contains 14/10 and 15/10 entries.
- `docs/UPGRADE_PLAN_2026-10.md` (09/10) is stale: it says the notch was removed, proposes `UserDefaults` keys that do not
  match the code, and has opposite defaults for `EdgeNotes`/`MenuBarHider`/`Voice`.
- `BUILDING.md` is ~1 year behind (`Last Updated: 2025-09-12`; claims no unit tests, macOS 12+ / Swift 5.8).
- There is no `T17` in the board (numbering skips it).

### Process note

The earlier part of this same session (before a context compaction) opened by wrongly claiming it had no tool access and
refused to list the repo three times. The tools were there. No work was lost, but a session that cannot tell whether it can
act will stall on its own — the same note the "setup only" entry below records.

## 2026-10-15 — Zed (DeepSeek V4.1 Flash, Viber Bedrock), setup only — no task assigned

Asked by the owner to read `docs/AGENT_QUICKSTART.md`, `docs/AGENT_TASKS.md`, `AGENTS.md` and
`docs/PENDING_TESTS_AND_DECISIONS.md` before doing anything, then to write this entry. **No item from `AGENT_TASKS.md` §6 was
assigned, so no code was changed, no branch was created, nothing was committed.**

| Step | Command | Result |
|:--|:--|:--|
| List repo root | `list_directory` on the repo root | 20 folders, 24 files. The root also holds obvious scratch/foreign files: `a.c`, `b.c`, `prog1`, `prog2`, `full.plist`, `defaults_dump.txt`, `binary_strings.txt`, `package.json`, `skills-lock.json`, `testdir/`, `tmp-review-b-visual/`, `tmux-502/`, `tools1/`. Not touched — owner's, and the quickstart says scratch belongs in `/tmp` |
| Read quickstart | `read_file docs/AGENT_QUICKSTART.md` | Read whole (75 lines) |
| Read task board | `read_file docs/AGENT_TASKS.md` | Outline + lines 1–145 only (§0–§5 and the head of §6). **Task specs T01–T19 were NOT read** |
| Read pending list | `read_file docs/PENDING_TESTS_AND_DECISIONS.md` | Lines 1–80 only — **partial**; the file continues past `Q-OC` |
| Read this worklog | `read_file docs/AGENT_WORKLOG.md` | Read whole (18 lines) |
| Read AGENTS.md | — | Not read with a tool; its text arrived through the editor's project-rules injection. Content matches the quickstart |
| Repo state | `git --no-optional-locks status --short` | No modified tracked file. 11 untracked entries: the expected owner files (`.agents/`, `assets_info.json`, `binary_strings.txt`, `strings/`, `docs/*_2026-10.md` ×3) **plus four that are not in the quickstart's list** — `defaults_dump.txt`, `full.plist`, `package.json`, `skills-lock.json` |
| Branch | `git rev-parse --abbrev-ref HEAD` | `main` |
| Head | `git --no-pager log -1 --oneline` | `07f16af Docs: hand the remaining work to other agents while Claude is out of quota` |
| Agent branches | `git branch --list 'agent/*'` | none |
| Worktrees | `git worktree list` | only the main checkout |

**Discrepancy found, not fixed:** `AGENT_TASKS.md` §5 says "`main` = `63bc3c3`", but HEAD is `07f16af` — the status block is
stale by at least one commit.

**Could NOT verify:** nothing about the app. No build (`scripts/build-and-check.sh`), no `swift test`, none of the six L10n
gates, no UI-token audit, no mutation harness, no live behaviour. No acceptance command applies — no task was assigned. The
two partial reads above (the §6 task specs and the tail of the pending list) are the only doc content not covered.

**Process note:** the first three turns of this session claimed it had no tool access and refused to list the repo. That was
false — the tools were there and a retry worked. Recorded so Claude knows the session did not start clean: no work was lost,
but a session that cannot tell whether it can act will stall on its own.

## 2026-10-14 22:18 — Antigravity (Gemini), reviewed by Claude at 22:40

Asked by the owner while Claude was out of quota: (1) page jumping on Thư viện Clipboard and Theo dõi hệ thống, (2) remove the
separate Chống ngủ page, (3) the notch kept showing a Claude session as running after it hit the usage limit, (4) a handoff note.

| Item | Claude's review |
|:--|:--|
| Page jumping | **Right root cause** — `.pageWidthSafe()` forced pages to their ideal height (`fixedSize(vertical:)`), the split view centred a ~1 100 pt page in a ~630 pt window. Kept. One regression fixed: `sizingOptions = []` also dropped the window's 900×600 minimum → now `contentMinSize` |
| Chống ngủ page | Removing the page dropped the duration presets and the countdown (the hub only had an indefinite switch, despite the note saying a "card" existed). Folded both into the Chống ngủ row of the controls panel on Tính năng & Quyền; the dead page file removed |
| Limit not detected | **Real** (measured: the desktop app runs no `StopFailure` hook). The fix matched "hit your session limit" in the PROMPT text — it flagged this session as stopped when the owner pasted a message quoting it, and invented an undocumented notification type. Replaced by reading the `rate_limit` line Claude writes into its transcript |
| Handoff note `docs/AGENT_HANDOFF.md` | Left untracked: it claims a hub card, a test (`testAntiSleepRowRetiresInFavorOfFeaturesHub`) and hook/event paths that do not exist |
| Process | It committed Claude's uncommitted analytics work plus three untracked owner docs, and launched the XFinder binary straight from a shell. Its one-line test addition closed a real gap (mutation N6 was GREEN in Claude's run; 18/18 RED after it, re-measured). The commit was redone; the docs went back to untracked |
