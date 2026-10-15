# Bảng việc cho agent khác — khi Claude hết quota

Tệp này do Claude giữ. Cách chia việc: **Claude lên kế hoạch, viết đặc tả và review; agent khác làm theo đặc tả.** Đây là
cách nhiều người dùng nhiều model cùng làm (Aider tách model "architect" và "editor"; tài liệu Claude Code khuyên tách
"khám phá → kế hoạch → code" và tách người viết với người review). **Không giới hạn cỡ việc nữa**: cỡ việc quyết định
quy trình phải theo (mục 1), không quyết định ai được làm.

## 0. Cách giao việc (cho bạn)

Mở agent ngay trong thư mục repo (`cd ~/github/XFinder && opencode`, hoặc File ▸ Open Folder trong Zed / Antigravity), dán:

```
Đọc docs/AGENT_QUICKSTART.md, rồi docs/AGENT_TASKS.md. Làm ĐÚNG MỘT việc: việc đầu tiên trong mục 6 có trạng thái TODO
(hoặc việc <ID> nếu tôi ghi ở đây: ___). Theo đúng quy trình mục 3 cho cỡ của việc đó, không làm thêm gì ngoài đặc tả.
Gặp bất kỳ điều kiện dừng nào ở mục 3 thì dừng và ghi vào docs/AGENT_WORKLOG.md, không tự xoay xở.
```

- **Một việc một phiên.** Xong một việc thì mở phiên MỚI cho việc kế (OpenCode `/new`, Zed tạo thread mới, Antigravity tạo
  cuộc trò chuyện mới). Phiên dài chứa đủ thứ không liên quan làm model kém đi và tốn token.
- **Chọn công cụ theo việc:**

| Việc | Dùng | Vì sao |
|:--|:--|:--|
| Làm theo đặc tả trong mục 6 (mọi cỡ) | **OpenCode + DeepSeek** | agent terminal, tự chạy build và test được |
| Review nhánh của agent khác (chỉ đọc, mục 3b) | **Antigravity (Gemini)** | người review khác người viết; đọc nhiều file một lúc |
| Sửa nhỏ khi đang đọc code, hỏi về code | Zed + DeepSeek | nhanh, không cần agent chạy lệnh |
| Kế hoạch, đặc tả, đo trên máy, phát hành, review cuối, gộp vào `main` | **Claude** | |

- **Việc chưa có trong mục 6** (bạn nghĩ ra lúc đó): dùng quy trình mục 3c. Một agent viết đặc tả, một công cụ khác đọc lại,
  bạn đồng ý rồi mới làm.

## 1. Cỡ việc — quyết định quy trình

| Cỡ | Nhận ra | Phải làm thêm |
|:--|:--|:--|
| **S** | ≤ 3 file nguồn (+ 1 file test), không tạo file mới trong `XFinder/` | quy trình mục 3 |
| **M** | nhiều file, hoặc có file mới (cần 4 dòng tay trong `project.pbxproj`), một chủ đề | thêm: `plutil -lint XFinder.xcodeproj/project.pbxproj`; với mỗi file mới, `grep -c "<Tên>.swift" /tmp/xfinder-clean-build/build.log` phải > 0 (file có thật sự được biên dịch); chạy harness mutation mà đặc tả nêu tên |
| **L** | một tính năng, nhiều chủ đề | đặc tả chia thành các bước cỡ M; **mỗi bước một commit**, build và test xanh rồi mới sang bước sau; ghi worklog sau từng bước |

- **Không có đặc tả thì không làm.** Agent làm theo đặc tả, không tự lên kế hoạch cho việc lớn (trừ mục 3c).
- **Thứ chỉ kiểm được khi mở app, cấp quyền hay nhìn màn hình** (hiệu ứng, VoiceOver đọc gì, quyền hệ thống, hành vi thật)
  thì vẫn làm được phần code, nhưng phải ghi **"chưa kiểm live"** trong commit và worklog, không viết là xong.

## 2. Vùng cấm và vùng cần cẩn thận

**Cấm (chỉ Claude làm)**, vì sai ở đây là mất dữ liệu, lộ quyền riêng tư hoặc hỏng bản phát hành:

- `XFinder/Info.plist`, entitlements, `scripts/install-mouse-rebuild.sh`, `scripts/make-release.sh`, ký và phát hành
- thứ ghi vào cấu hình của agent khác: `AgentHookInstaller.swift`, `ClaudeStatusLine.swift`, mọi thứ ghi vào `~/.claude`, `~/.codex`
- mã hoá `BoardLock*`; schema và migration của `DatabaseService.swift`
- thứ di chuyển hay xoá tệp của người dùng: `ArchiveRunner`, `JunkCleanup`, `Uninstall*`
- `Core/Diagnostics/*` (phân tích ẩn danh, quyền riêng tư)
- đổi nghĩa hay đổi mặc định của một khoá `UserDefaults`
- **file đang được Claude làm dở** (mục 5)

**Được làm khi đặc tả nói rõ, kèm cổng thêm:**

| Vùng | Cổng thêm |
|:--|:--|
| `project.pbxproj` | 4 dòng cho mỗi file mới (PBXBuildFile, PBXFileReference, dòng trong group, dòng Sources); `plutil -lint`; kiểm tên file trong build log |
| `Core/Notch/NotchSurfaceMachine.swift` | `sh scripts/mutation-check-notch.sh` phải đỏ hết |
| Controller có event tap (`QuitProtection`, `ClipboardShelf`, `SnapZone`, `CommandTab`, `FinderKeyboard`, `GestureEngine`, `VoiceHotkey`) | chỉ đổi code; hành vi thật luôn ghi "chưa kiểm live" |
| Chuỗi giao diện | qua `L10n.t`, thêm vào store bằng script chỉ-thêm; 6 cổng L10n ở `AGENT_QUICKSTART.md` phải in `TOTAL 0` |

## 3. Quy trình cho agent (làm theo thứ tự, không bỏ bước)

1. `git status`: chỉ được có các file chưa track sẵn của chủ dự án (`assets_info.json`, `strings/`, `.agents/`…). Có file
   đã sửa mà không phải của mình → **dừng**.
2. Tạo nhánh từ `main`: `git switch main && git switch -c agent/<công-cụ>-<ID>`.
   **Chạy song song nhiều agent** thì mỗi agent một thư mục riêng (worktree):
   `git worktree add ../XFinder-<ID> -b agent/<công-cụ>-<ID> main` rồi mở agent trong `../XFinder-<ID>`.
   Sửa code song song được, nhưng **build (`build-and-check.sh`) và harness mutation chỉ một cái chạy một lúc** trên toàn máy:
   build luôn ghi vào cùng `/tmp/xfinder-clean-build`, harness sửa tạm file nguồn.
3. Trong tệp này, đổi trạng thái việc thành `ĐANG LÀM (<công cụ>, <giờ>)`.
4. Làm **đúng** các bước của đặc tả. Không sửa thêm file nào khác, không "tiện tay" dọn dẹp. Việc cỡ L: từng bước một.
5. Chạy **mọi** lệnh nghiệm thu của việc, cộng: `sh scripts/build-and-check.sh` và
   `swift test --package-path /Users/wolong/github/XFinder/Tests`, cộng các cổng của cỡ M/L (mục 1) và vùng (mục 2).
6. Commit trên nhánh, chỉ stage đúng file mình sửa: `git add <file1> <file2>`; message mở đầu bằng ID (`T03: …`), ghi kết
   quả từng lệnh nghiệm thu và điều gì chưa kiểm được.
7. Đổi trạng thái thành `CHỜ REVIEW (nhánh agent/…)`; ghi một mục vào `docs/AGENT_WORKLOG.md` (đã làm gì, kết quả từng
   lệnh, điều gì chưa kiểm được). Commit hai thay đổi này cùng nhánh.
8. **Dừng.** Không push, không merge vào `main`. Việc kế: phiên mới.

**Điều kiện dừng ngay** (ghi vào worklog rồi dừng):

- **Sửa hai lần mà cùng một lỗi vẫn còn** (build, test, nghiệm thu). Không thử lần ba: ghi lại hai cách đã thử và lỗi
  nguyên văn. Phiên mới với mô tả rõ hơn thường làm tốt hơn một phiên dài vá chồng vá.
- Việc cần đụng vùng cấm, hoặc cần file ngoài danh sách của đặc tả.
- Đặc tả không khớp code thật (dòng đã đổi, hàm không còn): code đã đổi từ khi Claude viết đặc tả.
- Lệnh nghiệm thu cho kết quả khác kỳ vọng.

### 3b. Review chéo (tuỳ chọn, trước khi Claude quay lại)

Một công cụ **khác** công cụ đã viết (ví dụ Antigravity review nhánh của OpenCode) đọc nhánh và chỉ ghi nhận xét, không sửa:

```
Đọc docs/AGENT_QUICKSTART.md và việc <ID> trong docs/AGENT_TASKS.md. Chạy git diff main...agent/<công-cụ>-<ID>.
Chỉ đọc, không sửa file nào, không commit. Kiểm: mọi bước của đặc tả đã làm chưa, có đổi gì NGOÀI đặc tả không,
có đụng vùng cấm không, có chuỗi giao diện nào không qua L10n.t không. Chỉ báo lỗi ảnh hưởng tính đúng hoặc đặc tả,
không báo chuyện khẩu vị. Ghi kết quả vào docs/AGENT_WORKLOG.md dưới mục của việc đó.
```

### 3c. Việc chưa có trong bảng

1. Agent A (chế độ chỉ đọc / plan): viết đặc tả vào `docs/specs/<ID>.md`: mục tiêu, file sẽ đổi, file mới (và 4 dòng
   pbxproj), các bước, lệnh nghiệm thu, cái gì nằm ngoài phạm vi, cái gì chưa kiểm live được.
2. Một công cụ khác đọc đặc tả, ghi lỗ hổng vào cuối file đặc tả.
3. Bạn đồng ý thì thêm việc vào mục 6 (trỏ tới file đặc tả), rồi giao như mục 0.

## 4. Quy trình của Claude khi có quota lại

1. Đọc `docs/AGENT_WORKLOG.md` (mục mới nhất), `git branch --list 'agent/*'`, `git worktree list`.
2. Với mỗi nhánh: `git log main..<nhánh>`, `git diff main...<nhánh>`. Kiểm đúng phạm vi (file nào, bao nhiêu dòng), vùng
   cấm, từng bước có đúng không, và **thay đổi ngoài đặc tả** (model rẻ hay sửa lan ra ngoài phạm vi).
3. Tự chạy lại nghiệm thu, harness mutation liên quan, và đo live phần agent ghi "chưa kiểm live" nếu đo được.
4. Đúng → merge vào `main` (giữ commit của agent, hoặc squash thành một commit theo chủ đề). Sai → sửa hoặc bỏ, và ghi
   lý do vào worklog.
5. Đổi trạng thái trong mục 6 thành `XONG (<commit>)` hoặc `BỎ (<lý do>)`; push; xoá nhánh và worktree đã gộp
   (`git worktree remove ../XFinder-<ID>`).
6. Cuối phiên: cập nhật mục 5, viết đặc tả cho việc kế tiếp vào mục 6 (mọi cỡ).

## 5. Trạng thái hiện tại (Claude cập nhật cuối mỗi phiên)

Cập nhật 2026-10-15, cuối phiên (Claude hết quota).

- `main` = `63bc3c3` trên GitHub. Bản cài trên máy khớp bản build của commit đó. Không nhánh `agent/*` nào.
- **Vừa xong:** 8 preset cử chỉ chuột sai bundle ID đã sửa (`f9b8d5d`); preset Dev & AI kéo lên = Mission Control (`63bc3c3`).
- **Đang dở: thiết kế lại trang Chuột & cử chỉ.** Đã qua cổng 1 (brief). Wireframe 4 phương án (A danh sách, B sơ đồ + bảng
  bên — khuyên dùng, C bảng theo app, D theo ảnh tham chiếu của bạn) gần xong; bản sao bền ở
  `~/github/XFinder-design/mouse-gestures-2026-10-15/` (ngoài repo). **Cổng 2 = bạn chọn phương án** (việc T19 giúp bạn xem).
  Cho tới khi T14 bắt đầu, không agent nào sửa `XFinder/Views/Detail/MouseGesturesDetailView.swift` và 6 file
  `XFinder/Views/Components/{MouseDiagramView,GestureButtonList,GestureDetailPanel,GestureArmView,GestureActionPicker,GestureActivityPanel}.swift`.
- **Bạn còn nợ tay:** T-ANALYTICS-5, T-ANALYTICS-6, T-LAYOUT-1, T-SLEEP-1, T-LIMIT-1, T-MG-BID (`docs/PENDING_TESTS_AND_DECISIONS.md`).
- **Câu hỏi đang chờ bạn:** Q-RELEASE-14, Q-OC, Q-DIAG-5, Q-MG-1…3. Agent khác không trả lời thay bạn.

## 6. Hàng đợi việc (mọi cỡ, mỗi việc có đặc tả)

Mỗi việc dưới đây đã được Claude và một agent soát lỗi độc lập đọc lại trên code thật ngày 2026-10-15. Số dòng có thể lệch
vài dòng khi code đổi: **tìm theo đoạn code được trích**, không theo số dòng. Đoạn trích không còn ⇒ điều kiện dừng.

Không việc nào cần mở app. Việc nào thêm nhãn VoiceOver thì phần "VoiceOver đọc đúng" là **chưa kiểm được**: ghi rõ như vậy
trong worklog, đừng viết là đã xong.

---

### T01 · README ghi sai số test — TODO

- **Cỡ:** S · 1 file (`README.md`), 1 dòng
- **Vì sao:** README dòng ~213 ghi `| Test logic (399 test) | ✅ |`; thật là ~1196.
- **Các bước:**
  1. Đếm: `grep -c "func test" Tests/XFinderLogicTests/*.swift | awk -F: '{s+=$2} END {print s}'` (ngày viết: 1196).
  2. Đổi đúng ô đó thành `| Test logic (~<số vừa đếm> test) | ✅ |`. Không sửa dòng nào khác của bảng.
- **Nghiệm thu:** `grep -rn '(399 test)' README.md docs/*.md` ra rỗng · `git diff --stat` = 1 file, 1 dòng.

---

### T02 · `onChange` kiểu cũ ở Tổng quan và Hệ thống — TODO

- **Cỡ:** S · 2 file, 3 dòng
- **Vì sao:** macOS 14 bỏ kiểu closure một tham số của `.onChange(of:)`; ba chỗ này còn dùng, mỗi lần build sinh cảnh báo.
- **Các bước** (chỉ đổi chữ ký closure, thân giữ nguyên):
  1. `XFinder/Views/Detail/DashboardDetailView.swift`: `.onChange(of: launchAtLogin) { LoginItemController.apply($0) }`
     → `.onChange(of: launchAtLogin) { _, newValue in LoginItemController.apply(newValue) }`
  2. Cùng file: `.onChange(of: showDockIcon) { DockController.apply($0) }`
     → `.onChange(of: showDockIcon) { _, newValue in DockController.apply(newValue) }`
  3. `XFinder/Views/Detail/SystemDetailView.swift`: `.onChange(of: updateInterval) { _ in`
     → `.onChange(of: updateInterval) { _, _ in`
- **Nghiệm thu:**
  - Lệnh dưới, trước khi sửa ra 6 dòng, sau khi sửa còn đúng 3 dòng (DockPreviewController ×2, PreviewOverlayWindow ×1):
    `grep -rn "onChange(of:" XFinder --include='*.swift' | grep -E '\{ *(_|\$0|[a-zA-Z_][a-zA-Z0-9_]*) +in\b|\$0'`
  - `build-and-check` thành công; `git diff --stat` = 2 file, 3 dòng đổi.

---

### T03 · `onChange` kiểu cũ ở xem trước Dock và cửa sổ ⌘-Tab — TODO

- **Cỡ:** S · 2 file, 3 dòng
- **Các bước** (chỉ đổi chữ ký closure, thân giữ nguyên; không đụng phần event monitor của file):
  1. `XFinder/Core/DockPreviewController.swift`: `.onChange(of: pid) { newPID in` → `.onChange(of: pid) { _, newPID in`
  2. Cùng file: `.onChange(of: store.activeBrowserTabs) { _ in` → `.onChange(of: store.activeBrowserTabs) { _, _ in`
  3. `XFinder/Core/WindowPreview/PreviewOverlayWindow.swift`: `.onChange(of: store.selectedIndex) { newIndex in`
     → `.onChange(of: store.selectedIndex) { _, newIndex in`. **Không** đụng chỗ `.onChange(of: store.selectedIndex)` thứ
     hai trong file (đã đúng kiểu).
- **Nghiệm thu:** lệnh grep của T02 ra 0 dòng nếu T02 đã gộp, hoặc chỉ còn 3 dòng của T02 nếu chưa · `build-and-check` thành
  công · `git diff --stat` = 2 file, 3 dòng đổi.

---

### T04 · `allowedFileTypes` (đã bỏ) ở Nén và Công cụ PDF — TODO

- **Cỡ:** S · 2 file, ~4 dòng
- **Các bước:**
  1. Thêm `import UniformTypeIdentifiers` dưới các dòng `import` sẵn có của `XFinder/Views/Detail/CompressDetailView.swift`
     và `XFinder/Views/Detail/PdfToolsDetailView.swift`.
  2. Compress: `panel.allowedFileTypes = ["zip", "gz", "bz2", "tar"]` → đúng nguyên văn:
     `panel.allowedContentTypes = [.zip, .gzip, UTType(filenameExtension: "bz2"), UTType(filenameExtension: "tar")].compactMap { $0 }`
     **Không** dùng `.item` hay `.data` thay cho bz2/tar: chúng mở hộp chọn cho gần như mọi tệp, là đổi hành vi.
  3. PDF: `panel.allowedFileTypes = ["pdf"]` → `panel.allowedContentTypes = [.pdf]`.
  4. **Không** đụng 4 chỗ trong `NotesDetailView.swift` (có hộp lưu với đuôi tính lúc chạy — việc khác).
- **Nghiệm thu:** `grep -rn "allowedFileTypes" XFinder --include='*.swift'` chỉ còn 4 dòng của NotesDetailView · đọc diff:
  dòng Compress đúng nguyên văn ở bước 2 · `build-and-check` thành công.

---

### T05 · Ghi chú mép: chữ "Ghim" lọt tiếng Việt + 3 nút chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/EdgeNotesViews.swift`), ~4 dòng
- **Vì sao:** `.help(note.isPinned ? L10n.t("Bỏ ghim") : "Ghim")` — nhánh sau không qua `L10n.t`, nên UI tiếng Anh hiện
  "Ghim". Lint `audit-l10n-literals.py` **không thấy** được lỗi này (nó chỉ bắt chữ có dấu) — kiểm bằng đọc diff.
- **Các bước:**
  1. Đổi `.help(note.isPinned ? L10n.t("Bỏ ghim") : "Ghim")` thành
     `.help(note.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim")).accessibilityLabel(note.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))`
  2. Sau `.help(L10n.t("Thêm ô đánh dấu (⌘T)"))` nối thêm `.accessibilityLabel(L10n.t("Thêm ô đánh dấu (⌘T)"))`.
  3. Sau `.help(L10n.t("Xóa ghi chú"))` thêm dòng `.accessibilityLabel(L10n.t("Xóa ghi chú"))`.
- **Nghiệm thu:** `python3 scripts/check-l10n-coverage.py` TOTAL 0 (cả bốn khoá đã có sẵn trong store) · đọc diff: không còn
  chuỗi trần nào trong `.help(...)` của file · `build-and-check` thành công.

---

### T06 · Thẻ clipboard: nút ghim và sao chép lại chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/ClipboardCardView.swift`), 2 dòng
- **Các bước:**
  1. Sau `.help(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))` thêm dòng
     `.accessibilityLabel(record.isPinned ? L10n.t("Bỏ ghim") : L10n.t("Ghim"))`.
  2. Sau `.help(L10n.t("Sao chép lại vào clipboard"))` thêm dòng `.accessibilityLabel(L10n.t("Sao chép lại vào clipboard"))`.
- **Nghiệm thu:** `grep -c accessibilityLabel XFinder/Views/ClipboardCardView.swift` = 2 (trước là 0) ·
  `python3 scripts/audit-l10n-literals.py` không tăng · `build-and-check` thành công.

---

### T07 · Cử chỉ chuột: menu "…" và nút về mặc định chưa có nhãn VoiceOver — HOÃN (gộp vào đợt thiết kế lại trang Chuột & cử chỉ, mục 5)

- **Cỡ:** S · 1 file (`XFinder/Views/Components/GestureActionPicker.swift`), 2 dòng
- **Lưu ý (đã đo ở P9):** nhãn đặt trên **`Menu`** bị VoiceOver bỏ qua — nó đọc tên biểu tượng. Với `Menu`, nhãn phải nằm
  trên `Image` bên trong `label:`. Với `Button` thì đặt trên Button như thường.
- **Các bước:**
  1. Trong `label:` của Menu có `Image(systemName: "ellipsis.circle")`, nối vào Image đó (sau `.font(.system(size: 14))`):
     `.accessibilityLabel(L10n.t("Đổi hành động cho hướng này"))`.
  2. Sau `.help(L10n.t("Đưa hướng này về preset — không đụng các hướng khác"))` của nút `arrow.uturn.backward`, thêm dòng
     `.accessibilityLabel(L10n.t("Đưa hướng này về preset — không đụng các hướng khác"))`.
- **Nghiệm thu:** đọc diff: đúng 2 dòng thêm, dòng đầu nằm **trong** khối `label:` của Menu · `build-and-check` thành công ·
  `audit-l10n-literals.py` không tăng.

---

### T08 · Trang Pin: 3 nút biểu tượng chưa có nhãn VoiceOver — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/Components/BatteryViews.swift`), 3 dòng
- **Các bước:** sau mỗi dòng dưới đây thêm một dòng `.accessibilityLabel(...)` cùng chuỗi:
  `.help(L10n.t("Làm mới pin"))` · `.help(L10n.t("Chế độ danh sách"))` · `.help(L10n.t("Chế độ lưới"))`.
- **Nghiệm thu:** `grep -c accessibilityLabel XFinder/Views/Components/BatteryViews.swift` = 3 (trước là 0) ·
  `git diff --stat` = 1 file, 3 dòng thêm · `build-and-check` thành công.

---

### T09 · Nút xoá ô tìm kiếm (sidebar, Ghi chú, Thư viện Clipboard) không có nhãn — TODO

- **Cỡ:** S · 3 file, 6 dòng
- **Các bước:** ở ba nút dưới đây, ngay sau `.buttonStyle(.plain)` của nút đó, thêm hai dòng
  `.help(L10n.t("Xoá tìm kiếm"))` và `.accessibilityLabel(L10n.t("Xoá tìm kiếm"))` (khoá đã có trong store):
  1. `XFinder/Views/Sidebar/SidebarView.swift`: `Button { query = "" } label: { Image(systemName: "xmark.circle.fill")…`
  2. `XFinder/Views/Detail/NotesDetailView.swift`: `Button { searchText = "" } label: {`
  3. `XFinder/Views/Detail/ClipboardLibraryView.swift`: `Button { store.query.text = "" } label: {`
  **Không** đụng nút `xmark.circle.fill` thứ hai trong ClipboardLibraryView (`store.closeInspector()` — nút đóng, không phải
  xoá tìm kiếm).
- **Nghiệm thu:** `grep -n -A4 'xmark.circle.fill' <3 file>` — mỗi nút xoá tìm kiếm có đủ hai dòng · `build-and-check`
  thành công · `audit-l10n-literals.py` không tăng.

---

### T10 · Notch: nút Đang phát và menu sắp xếp không có nhãn VoiceOver — TODO

- **Cỡ:** S · 2 file, ~9 dòng
- **Lưu ý:** như T07 — `Button` thì nhãn trên Button; `Menu` thì nhãn trên `Image` trong `label:`.
- **Các bước** trong `XFinder/Views/NotchSurfaceView.swift`:
  1. Hàm `nowPlayingControls(size:)` và hàm `transportRow(enabled:)`: mỗi nút có `.help(L10n.t("Bài trước"))`,
     `.help(L10n.t("Phát hoặc tạm dừng"))`, `.help(L10n.t("Bài tiếp"))` (3 nút × 2 hàm = 6 chỗ) — nối
     `.accessibilityLabel(L10n.t("<cùng chuỗi>"))` ngay sau `.help(...)` đó.
  2. `transportRow`: `label: { Image(systemName: "shuffle").font(.system(size: 12)) }` → nối
     `.accessibilityLabel(L10n.t("Xáo trộn"))` vào Image; `label: { Image(systemName: "repeat").font(.system(size: 12)) }`
     → nối `.accessibilityLabel(L10n.t("Lặp lại"))` vào Image. Giữ nguyên `.help(...)` trên Menu.
  3. `XFinder/Views/NotchClipboardView.swift`, `sortMenu`: nối vào cuối chuỗi modifier của
     `Image(systemName: "arrow.up.arrow.down")` (sau `.background(Circle().fill(N.capsule))`):
     `.accessibilityLabel("\(L10n.t("Sắp xếp")) · \(model.sort.titleVI)")`. Giữ nguyên `.help` và `.accessibilityLabel` đang
     có trên Menu (giống mẫu đã sửa ở `NotchAgentsPage.swift`, chỗ `arrow.triangle.branch`).
- **Nghiệm thu:** đọc diff: chỉ thêm, không xoá dòng nào; hai nhãn Menu nằm trong khối `label:` · `build-and-check` thành
  công · `check-l10n-coverage.py` và `audit-l10n-literals.py` không đổi.

---

### T11 · Test cho nhánh "Other" của `usagePageName` — TODO

- **Cỡ:** S · 1 file test (`Tests/XFinderLogicTests/DeviceCapabilityTests.swift`), ~10 dòng thêm, không đụng code app
- **Vì sao:** `DeviceCapabilityProbe.usagePageName(_:)` có 4 kết quả; chưa test nào gọi tới "Other" và mốc `>=` của "Vendor".
- **Các bước:** thêm một hàm `testUsagePageNameCoversEveryBranch()` vào class test sẵn có, gọi thẳng `usagePageName` (dùng
  hằng có tên, không viết số trần):
  `usagePageButton` → "Button" · `usagePageConsumer` → "Consumer" · `usagePageVendorDefined` và `usagePageVendorDefined + 1`
  → "Vendor" · `usagePageGenericDesktop` và `usagePageVendorDefined - 1` → "Other".
- **Nghiệm thu:** `swift test` tăng đúng 1 test, 0 lỗi · **chứng minh test đỏ được**: tạm đổi `>=` thành `>` trong
  `DeviceCapabilityTypes.swift`, chạy lại thấy đỏ, sửa tay về `>=`, rồi
  `git diff --quiet -- XFinder/Core/MouseGestures/DeviceCapabilityTypes.swift && echo SẠCH` phải in `SẠCH` (không dùng
  `git checkout`/`git stash`) · `git diff --stat` cuối cùng = chỉ file test.

---

### T12 · Test riêng cho `TimeZoneConversion` — TODO

- **Cỡ:** S · 1 file test **mới** `Tests/XFinderLogicTests/TimeZoneConversionTests.swift` (gói test tự nhận file mới, không
  cần pbxproj; `TimeZoneConversion.swift` đã được symlink), ~110 dòng
- **Các bước:**
  1. Đọc hết `XFinder/Core/SmartSelect/TimeZoneConversion.swift` trước (181 dòng): tên hàm, tên trường, tập `ambiguous`.
  2. Viết test cho từng hàm, mỗi kỳ vọng suy từ code + phép đo, không đoán:
     - `zone(for:)`: `EST` cố định −5h kèm vùng New York; `PT` đi theo vùng; mọi phần tử của tập `ambiguous` trả nil;
       `UTC+7`, `GMT-5:30` đúng offset; `UTC+5:07` trả nil (chỉ phút 0/15/30/45 hợp lệ); chữ thường và dấu "−" được chuẩn hoá.
     - `parseClock(_:)`: `3pm`, `3:30pm`, `9:30 a.m.`, `15:00`, `15h30`, `15h` đúng; `13pm`, `3:99pm`, `25:00`, `hello` → nil.
     - `convert(_:now:to:)`: một ca offset cố định; ca có ghi chú vùng (EST khi New York đang giờ mùa hè) — **tính offset thật
       bằng `TimeZone(identifier: "America/New_York")!.secondsFromGMT(for: ngày_chọn)` rồi mới viết kỳ vọng**, kèm một ngày giờ
       mùa đông để thấy ghi chú biến mất; chuỗi dài quá giới hạn và vùng lạ → nil.
     - `Result.isSameAsLocal`, `RegionNote.city`, `offsetLabel`, `clockLabel`.
  3. Một test chạy xanh chưa chứng minh gì: chọn một kỳ vọng, cố ý đổi sai, thấy đỏ, đổi lại.
- **Nghiệm thu:** `swift test` tăng đúng số test mới, 0 lỗi · `git status --short` chỉ thêm đúng file test mới, không file app
  nào đổi · ghi trong worklog kỳ vọng nào đã được làm đỏ thử.

---

### T13 · `allowedFileTypes` (đã bỏ) trong Ghi chú: nhập/xuất Markdown, văn bản, JSON — TODO

- **Cỡ:** S · 1 file (`XFinder/Views/Detail/NotesDetailView.swift`), ~5 dòng
- **Đã kiểm trên máy:** `UTType(filenameExtension:)` trả về `net.daringfireball.markdown` cho cả `md` và `markdown`,
  `public.plain-text` cho `txt`, `public.json` cho `json`.
- **Các bước:**
  1. Thêm `import UniformTypeIdentifiers` dưới `import AppKit`.
  2. `pickImport`: `panel.allowedFileTypes = types` → `panel.allowedContentTypes = types.compactMap { UTType(filenameExtension: $0) }`
  3. `saveText`: `panel.allowedFileTypes = [(name as NSString).pathExtension]` →
     `panel.allowedContentTypes = [UTType(filenameExtension: (name as NSString).pathExtension)].compactMap { $0 }`
  4. `exportJSON` và `importJSON`: `panel.allowedFileTypes = ["json"]` → `panel.allowedContentTypes = [.json]`
- **Nghiệm thu:** `grep -rn "allowedFileTypes" XFinder --include='*.swift'` ra rỗng (sau khi T04 đã gộp; nếu chưa thì chỉ còn 2
  dòng của T04) · `build-and-check` thành công · ghi "chưa kiểm live: hộp mở/lưu tệp lọc đúng loại".

---

### T18 · Chạy lại hai harness cử chỉ cho commit `63bc3c3` — TODO

- **Cỡ:** S · không sửa file nào (chỉ chạy và ghi worklog)
- **Vì sao:** commit `63bc3c3` sửa `GestureModel.swift` nhưng hai harness bị dừng giữa chừng để kịp commit trước khi hết quota.
  Lần dừng đó để lại một mutant trong `GestureLabelStructure.swift` (đã khôi phục bằng `git checkout`).
- **Các bước** (chạy lần lượt, KHÔNG chạy song song, không sửa file nào trong lúc chạy, không dừng giữa chừng):
  1. `git status --short`: không được có file `M` nào ngoài file chưa track của chủ dự án.
  2. `/bin/sh -c 'cd ~/github/XFinder && sh scripts/mutation-check-gesture-labels.sh' > /tmp/mut-labels.log 2>&1`
  3. `/bin/sh -c 'cd ~/github/XFinder && sh scripts/mutation-check-gesture-ui.sh' > /tmp/mut-ui.log 2>&1`
  4. `git status --short` lại: phải giống bước 1. Nếu có file `M` (mutant sót) → ghi tên file vào worklog, chạy
     `git diff <file>` để chép phần khác, rồi DỪNG (không tự `git checkout`).
- **Nghiệm thu:** labels in 5 dòng "RED as expected", ui in 8 dòng "RED as expected" và "post-restore suite: … 0 failure(s)";
  ghi hai con số vào `docs/AGENT_WORKLOG.md`.

---

### T16 · Tên phím chữ và số trong nhãn phím tắt (đang hiện "⌘Key 18") — TODO

- **Cỡ:** S · 1 file nguồn + 1 file test mới
- **Vì sao:** `GestureShortcut.label` (`XFinder/Core/MouseGestures/GestureModel.swift`, khoảng dòng 147) chỉ có tên cho vài mã
  phím, nên "Vừa khung" hiện `⌘Key 18` thay vì `⌘1`, "Chụp màn hình" hiện `⇧⌘Key 20` thay vì `⇧⌘3`.
- **Các bước:**
  1. Trong `var label`, thêm vào bảng `names` các mã phím ANSI của macOS (giữ nguyên các mục đang có):
     `1:"S", 2:"D", 4:"H", 5:"G", 7:"X", 8:"C", 11:"B", 12:"Q", 14:"E", 15:"R", 16:"Y", 31:"O", 32:"U", 34:"I", 37:"L",
     38:"J", 39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 18:"1", 19:"2", 20:"3", 21:"4",
     23:"5", 22:"6", 26:"7", 28:"8", 25:"9", 51:"⌫", 53:"⎋"`
     (mã 29 đã là "0", 24 "=", 27 "-", 30 "]", 33 "[" — không đổi).
  2. Tạo `Tests/XFinderLogicTests/GestureShortcutLabelTests.swift` (gói test tự nhận file mới; `GestureModel.swift` đã có
     symlink): kiểm `GestureShortcut(key: 18, flags: GestureShortcut.command).label == "⌘1"`,
     `GestureShortcut(key: 20, flags: GestureShortcut.command | GestureShortcut.shift).label == "⇧⌘3"`, và với mọi mã từ 0
     tới 53 có trong bảng mới thì `label` không chứa chữ "Key ".
- **Nghiệm thu:** `swift test` tăng đúng số test mới, 0 lỗi · chứng minh test đỏ được: tạm xoá `18:"1"` khỏi bảng, thấy đỏ,
  thêm lại, `git diff --stat` chỉ còn 2 file · `build-and-check` thành công · `sh scripts/mutation-check-gesture-labels.sh`
  vẫn 5/5 RED (chạy riêng, không song song).

---

### T15 · Nút "Ghi nút" cạnh "Nút cuộn" thật ra ghi NÚT GIỮ — TODO (chỉ khi chưa bắt đầu T14)

- **Cỡ:** S · 1 file (`XFinder/Views/Detail/MouseGesturesDetailView.swift`, hàm `switchesSection`, khoảng dòng 859–866)
- **Vì sao:** nút đó gọi `triggerRecording()`, mà engine chỉ ghi `configuration.trigger` (`GestureEngine.swift:527`); không có
  đường nào đổi `scrollButton`. Control làm khác điều nhãn của nó hứa.
- **Lưu ý:** nếu T14 đã bắt đầu thì BỎ việc này (T14 làm lại cả khối). File này đang bị khoá ở mục 5 — T15 là ngoại lệ
  duy nhất được phép sửa nó, và chỉ đúng khối dưới đây.
- **Các bước:** thay `Button(L10n.t("Ghi nút")) { triggerRecording() }.buttonStyle(.link)…` (khối "Nút cuộn") bằng một
  `Picker` kiểu `.menu` (rộng tối đa 140) liệt kê các nút trong `drawnButtons` mà `buttonRole($0)` không phải nút giữ và
  `roleContext.declaredEventButtons` có chứa; nhãn mỗi mục `L10n.t(ButtonKey.index(n))`; chọn thì
  `controller.update { $0.scrollButton = n }` (n là chỉ số 0-based như `scrollButton` đang lưu — đọc `GestureModel.swift`
  `validate()` để chắc). Bỏ `Text` hiển thị số nút đứng trước nút cũ (Picker đã hiện giá trị). Không thêm chuỗi mới.
- **Nghiệm thu:** `build-and-check` thành công · `swift test` 0 lỗi · 6 cổng L10n `TOTAL 0` · đọc diff: không còn
  `triggerRecording()` nào trong khối "Nút cuộn" · ghi "chưa kiểm live: chọn nút cuộn trên trang".

---

### T19 · Mở wireframe Chuột & cử chỉ cho bạn chọn (cổng 2) — TODO

- **Cỡ:** S · không sửa repo
- **Các bước:**
  1. `/bin/ls ~/github/XFinder-design/mouse-gestures-2026-10-15/` phải có `shell.html`, `variant-a.html` … `variant-d.html`,
     `build.py`. Nếu thư mục scratchpad cũ
     `/private/tmp/claude-502/-Users-wolong-github-XFinder/ec69d774-f3f3-4e1f-91f8-7b0e4b40a2f7/scratchpad/mg/wf/` còn và có
     `variant-*.html` MỚI hơn bản sao, chép đè các `variant-*.html` mới sang thư mục bền.
  2. `/bin/sh -c 'cd ~/github/XFinder-design/mouse-gestures-2026-10-15 && python3 build.py a b c d'` → `wireframe-a-b-c-d.html`.
  3. Chạy server nền: `/bin/sh -c 'nohup python3 -m http.server 8766 -d ~/github/XFinder-design/mouse-gestures-2026-10-15 >/dev/null 2>&1 &'`
     (cổng 8766 bận thì dừng tiến trình cũ đang giữ nó: `lsof -ti :8766`).
  4. Đưa bạn các link: `http://127.0.0.1:8766/wireframe-a-b-c-d.html?v=a` (đổi `v=b`, `v=c`, `v=d`; thanh trên cùng đổi
     trạng thái, cửa sổ 1181×611 / 1440×900, sáng/tối). Nếu thanh trên cùng không có nút D thì gõ `v=d` vào link.
- **Nghiệm thu:** `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8766/wireframe-a-b-c-d.html` in `200`. Ghi vào
  worklog phương án bạn chọn và mọi góp ý của bạn — đó là đầu vào của T14.

---

### T14 · Dựng trang Chuột & cử chỉ theo phương án bạn chọn — CHỜ BẠN CHỌN PHƯƠNG ÁN (cổng 2)

- **Cỡ:** L · nhiều file trong `XFinder/Views/Detail/MouseGesturesDetailView.swift` và `XFinder/Views/Components/*Gesture*`,
  `MouseDiagramView.swift`; có thể thêm file view mới (4 dòng pbxproj mỗi file).
- **Đầu vào (đọc hết trước khi sửa dòng nào):** `~/github/XFinder-design/mouse-gestures-2026-10-15/CONTRACT.md` (brief đã
  duyệt, 11 lỗi hiện trạng phải sửa, ngữ pháp card), `CONTRACT-D.md` nếu chọn D, `inventory.md` (F1–F29 chức năng, S1–S68
  trạng thái — **không được rơi mục nào**), `variant-<x>.html` của phương án được chọn, góp ý của bạn trong worklog (T19).
- **Bước (mỗi bước một commit, build + test xanh mới sang bước sau):**
  1. Khung trang theo phương án: thay bố cục cũ, giữ nguyên mọi binding tới `GestureController` (đọc `inventory.md` cột
     "writes/calls"); không đổi `GestureModel`/`GestureEngine`.
  2. Sửa đúng 11 lỗi ở `CONTRACT.md` "What is wrong today" (gồm T15 nếu chưa làm: nút cuộn chọn bằng Picker).
  3. Chuỗi mới: thêm bằng một script chỉ-thêm mới `scripts/add-mouse-redesign-l10n-entries.py` (mẫu:
     `scripts/add-analytics-l10n-entries.py`), không sửa entry cũ. Một vốn từ: "Nút N".
  4. Chẩn đoán HID gom vào một disclosure "Chẩn đoán chuột" ở cuối.
- **Cổng:** `build-and-check` (tên file mới có trong build log) · `swift test` 0 lỗi · `sh scripts/mutation-check-gesture-labels.sh`,
  `mutation-check-gesture-ui.sh`, `mutation-check-gesture-buttons.sh` (lần lượt) đều đỏ hết · 6 cổng L10n `TOTAL 0` ·
  `python3 scripts/audit-ui-tokens.py` 0 · ghi "chưa kiểm live" cho mọi phần cần mở app.
- Claude sẽ review, đo trên app (AX + ảnh chụp cửa sổ) và so với wireframe trước khi gộp.

## 7. Việc cần bạn duyệt trước (agent KHÔNG làm khi chưa duyệt)

Đã kiểm là có thật và nhỏ, nhưng đổi thứ người dùng thấy, nên chờ bạn trả lời Q-OC. Bạn duyệt mã nào thì Claude chuyển nó
xuống mục 6 kèm các bước.

| Mã | Việc | Vì sao cần bạn |
|:--|:--|:--|
| OC-47 | Thanh âm lượng và thanh tiến trình tác vụ trên notch theo màu nhấn (`notch.accent`) thay vì luôn trắng (`NotchSurfaceView.swift`, 2 chỗ `.tint(.white)`) | Mặc định "Theo hệ thống" ⇒ hai thanh đổi từ trắng sang màu nhấn của macOS cho mọi người |
| OC-18 | Tuỳ chọn có con trỏ trong ảnh chụp (`screencapture -C`) | Thêm một công tắc và một khoá cài đặt mới |
| OC-20 | Tuỳ chọn bỏ bóng cửa sổ khi chụp cửa sổ (`screencapture -o`) | Như trên; test hiện đang ghim "không bao giờ có `-o`" |

## 8. Việc chỉ Claude làm

- Review + đo live T14 trước khi gộp (so trang thật với wireframe đã chọn bằng AX và ảnh chụp cửa sổ).
- Mọi mã OC bạn chọn ở mục 7: Claude viết đặc tả rồi đưa xuống mục 6.
- Q-MG-1…3 (cử chỉ theo phím bổ trợ, vòng cho nhiều nút, tuỳ biến cuộn) nếu bạn muốn: sửa engine, Claude viết đặc tả trước.
- Đăng 1.4.0 (Q-RELEASE-14): script phát hành, ký, GitHub.
- Theo dõi T-LIMIT-1: nếu lần chạm giới hạn thật cho kết quả khác, đo lại transcript và sửa `AgentEvents.swift`.
- Mọi việc trong vùng cấm (mục 2) và mọi phép đo trên máy (quyền, Accessibility, dữ liệu thật).
