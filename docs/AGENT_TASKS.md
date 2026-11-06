# Bảng việc cho agent khác — khi Claude hết quota

Tệp này do Claude giữ. Cách chia việc: **Claude lên kế hoạch, viết đặc tả và review; agent khác làm theo đặc tả.** Đây là
cách nhiều người dùng nhiều model cùng làm (Aider tách model "architect" và "editor"; tài liệu Claude Code khuyên tách
"khám phá → kế hoạch → code" và tách người viết với người review). **Không giới hạn cỡ việc nữa**: cỡ việc quyết định
quy trình phải theo (mục 1), không quyết định ai được làm.

**Từ 2026-10-15 hàng đợi và trạng thái việc nằm ở Notion** — `docs/AGENT_NOTION.md`: view *Queue — Ready* quyết định
việc kế, nhận việc bằng `Claimed By`, kết quả ghi vào một Run. Tệp này giữ **quy tắc** (mục 1–3) và **chỉ mục đặc tả**
(mục 6); đặc tả luôn là file trong `docs/specs/`. Agent không nối được Notion thì đi đường dự phòng ở `AGENT_NOTION.md` §7
(chủ dự án dán ID + Spec Path + Spec Revision, kết quả ghi vào `docs/AGENT_WORKLOG.md`).

## 0. Cách giao việc (cho bạn)

Mở agent ngay trong thư mục repo (`cd ~/github/XFinder && opencode`, hoặc File ▸ Open Folder trong Zed / Antigravity).
**Prompt chuẩn (Builder / Reviewer / Claude) ở `docs/AGENT_NOTION.md` §10.** Bản dự phòng khi agent đó **không có**
Notion MCP — bạn mở view *Queue — Ready*, chép ID, Spec Path, Spec Revision vào chỗ trống:

```
Đọc docs/AGENT_QUICKSTART.md, rồi docs/AGENT_TASKS.md. Làm ĐÚNG MỘT việc: <ID>, đặc tả <Spec Path>, Spec Revision
<blob> (kiểm bằng git hash-object <Spec Path> | cut -c1-7; khác thì dừng). Theo đúng quy trình mục 3 cho cỡ của việc đó,
không làm thêm gì ngoài đặc tả. Không có Notion nên ghi tiến trình và kết quả vào docs/AGENT_WORKLOG.md theo mục 3 bước 7.
Gặp bất kỳ điều kiện dừng nào ở mục 3 thì dừng và ghi vào worklog, không tự xoay xở.
```

- **Một việc một phiên** cho việc cỡ M/L. Xong thì mở phiên MỚI cho việc kế (OpenCode `/new`, Zed tạo thread mới,
  Antigravity tạo cuộc trò chuyện mới). **Việc cỡ S được chạy nhiều việc trong một phiên** (bạn nói "chạy hết hàng đợi"),
  miễn mỗi việc một dòng worklog có danh sách file của việc đó (mẫu ở mục 3, bước 7).
- **Agent được commit trên nhánh riêng của nó** (bạn chốt Q-PROC-1, 2026-10-15): nhánh `agent/<công-cụ>-<ID>`, mỗi việc
  (hoặc mỗi bước của việc nhiều bước) **một commit**. Agent **không** commit lên `main`, **không** push, **không** merge,
  **không** rebase hay sửa lại commit đã có. Claude review từng commit rồi mới gộp vào `main`.
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
- **file đặc tả đang được một task `Ready`/`Doing` tham chiếu** (`docs/specs/*`, ô `Spec Path` trong Notion) — Builder
  đọc, không sửa; đặc tả MỚI theo mục 3c là file mới
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
2. Tạo nhánh từ `main`: `git switch main && git switch -c agent/<công-cụ>-<ID>`. **Việc nhiều bước (cỡ L, như T14):
   MỘT nhánh cho cả việc** (`agent/<công-cụ>-T14`), mỗi bước một commit trên nhánh đó. Bước kế tiếp mở phiên mới nhưng
   làm tiếp trên **cùng nhánh** (`git switch agent/<công-cụ>-T14`), vì bước sau dựa trên bước trước và Claude có thể chưa
   kịp gộp. Nhánh đã có sẵn thì `git switch` sang, đừng tạo nhánh mới.
   **Chạy song song nhiều agent** thì mỗi agent một thư mục riêng (worktree):
   `git worktree add ../XFinder-<ID> -b agent/<công-cụ>-<ID> main` rồi mở agent trong `../XFinder-<ID>`.
   Sửa code song song được, nhưng **build (`build-and-check.sh`) và harness mutation chỉ một cái chạy một lúc** trên toàn máy:
   build luôn ghi vào cùng `/tmp/xfinder-clean-build`, harness sửa tạm file nguồn.
3. Nhận việc trong Notion theo `docs/AGENT_NOTION.md` §4: `Claimed By`, `State = Doing`, `Branch`, một Run mới; chờ
   ~10 s rồi đọc lại — không còn là mình thì bỏ. Không nối được Notion: mở mục worklog của việc với dòng
   `ĐANG LÀM (<công cụ>, <giờ>)` (không sửa tệp này nữa).
4. Làm **đúng** các bước của đặc tả. Không sửa thêm file nào khác, không "tiện tay" dọn dẹp. Việc cỡ L: từng bước một.
5. Chạy **mọi** lệnh nghiệm thu của việc, cộng `sh scripts/gate-all.sh` (build + toàn bộ test + 7 cổng chuỗi/UI, in
   `GATE: green`), cộng các cổng của cỡ M/L (mục 1) và vùng (mục 2). Harness mutation chạy riêng, lần lượt, sau cùng.
6. Commit trên nhánh, chỉ stage đúng file mình sửa: `git add <file1> <file2>` (**không bao giờ** `git add -A` hay
   `git add .` — thư mục có file chưa track của chủ dự án); kiểm `git diff --cached --stat` trước khi commit; message mở
   đầu bằng ID (`T14b: …`), ghi kết quả từng lệnh nghiệm thu và điều gì chưa kiểm được. **Kiểm `git branch --show-current`
   trước khi commit: phải là nhánh `agent/…`, không bao giờ là `main`.**
7. Trong Notion: `Reported Commits` = SHA, `State = Awaiting Claude`; Run của bạn ghi Outcome, "chưa kiểm", và dán
   **nguyên văn** output của `gate-all.sh` (`docs/AGENT_NOTION.md` §4 bước 7). Không có Notion thì ghi vào
   `docs/AGENT_WORKLOG.md` **gọn**, mỗi việc một dòng, cuối mục ghi `CHỜ REVIEW (nhánh agent/…)`:

   | Việc | File đã sửa | Nghiệm thu riêng của việc | Chưa kiểm live |
   |:--|:--|:--|:--|

   rồi dán nguyên văn 9 dòng của `gate-all.sh` một lần cho cả lượt. Chỉ viết dài cho điều kiện dừng và chỗ đặc tả không
   khớp code. Ghi đo ở đâu: "probe từ terminal" khác "đo trong app đã cài". Commit cùng nhánh.
8. **Dừng.** Để repo đứng trên nhánh của mình (không `git switch main`, không push, không merge). Việc kế: phiên mới.

**Điều kiện dừng ngay** (ghi vào worklog rồi dừng):

- **Sửa hai lần mà cùng một lỗi vẫn còn** (build, test, nghiệm thu). Không thử lần ba: ghi lại hai cách đã thử và lỗi
  nguyên văn. Phiên mới với mô tả rõ hơn thường làm tốt hơn một phiên dài vá chồng vá.
- Việc cần đụng vùng cấm, hoặc cần file ngoài danh sách của đặc tả.
- Đặc tả không khớp code thật (dòng đã đổi, hàm không còn): code đã đổi từ khi Claude viết đặc tả.
- **Đặc tả tự mâu thuẫn** (hai câu nói ngược nhau, hoặc đặc tả ngược với wireframe/CONTRACT): đừng tự gỡ bằng cách
  đọc thêm tài liệu thiết kế. Chép hai câu đó vào worklog và dừng — Claude sửa đặc tả. (Lượt T14d đầu tiên đọc vòng
  CONTRACT/inventory/wireframe tới hết phiên mà không viết dòng code nào.)
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

**Bạn giao thẳng một tính năng giữa phiên** (như tính năng HUD độ sáng/âm lượng ngày 15/10): trước khi viết code, agent
viết một đặc tả ngắn vào `docs/specs/<tên>.md` gồm mục tiêu, file sẽ đổi, và **danh sách tình huống hỏng** của
`AGENT_QUICKSTART.md` luật 11 (thiếu quyền · máy/OS không làm được · giá trị ở đầu mút · ngữ cảnh đổi giữa chừng ·
giá trị cũ trong cache · mỗi công tắc khi TẮT). Tính năng HUD bỏ qua bước này và mang 6 lỗi, lỗi nào cũng là một dòng
thiếu trong danh sách đó. Việc lớn hơn thì theo các bước dưới:

1. Agent A (chế độ chỉ đọc / plan): viết đặc tả vào `docs/specs/<ID>.md`: mục tiêu, file sẽ đổi, file mới (và 4 dòng
   pbxproj), các bước, lệnh nghiệm thu, cái gì nằm ngoài phạm vi, cái gì chưa kiểm live được.
2. Một công cụ khác đọc đặc tả, ghi lỗ hổng vào cuối file đặc tả.
3. Bạn đồng ý thì thêm việc vào mục 6 (trỏ tới file đặc tả), rồi giao như mục 0.

## 4. Quy trình của Claude khi có quota lại

1. Mở view **Review — Awaiting Claude** và **Blocked** trong Notion (`docs/AGENT_NOTION.md` §5), rồi
   `docs/AGENT_WORKLOG.md` (mục mới nhất — đường dự phòng), `git branch --list 'agent/*'`, `git worktree list`. Chạy
   `sh scripts/gate-all.sh` trước tiên: đỏ thì chưa cần đọc diff.
2. Với mỗi nhánh: `git log main..<nhánh>`, `git diff main...<nhánh>`. Kiểm đúng phạm vi (file nào, bao nhiêu dòng), vùng
   cấm, từng bước có đúng không, và **thay đổi ngoài đặc tả** (model rẻ hay sửa lan ra ngoài phạm vi).
3. Tự chạy lại nghiệm thu, harness mutation liên quan, và đo live phần agent ghi "chưa kiểm live" nếu đo được.
4. Đúng → merge vào `main` (giữ commit của agent, hoặc squash thành một commit theo chủ đề). Sai → sửa hoặc bỏ, và ghi
   lý do vào worklog.
5. Trong Notion: `State = Done` (hoặc `Awaiting live` khi còn T-* chờ tay chủ dự án), `Reported Commits` = SHA trên
   `main`, một Run `Kind = claude-review`; nếu kết quả tới qua worklog (đường dự phòng) thì chép nó thành Run; push;
   đưa nhánh `agent/…` về `main`; xoá worktree đã gộp (`git worktree remove ../XFinder-<ID>`).
6. Cuối phiên: cập nhật mục 5; đặc tả việc kế vào `docs/specs/`, trang task Notion trỏ tới nó (`Spec Path`,
   `Spec Revision`), chạy `gate-all.sh` trên `main` mới và ghi Run `gate-baseline`, tích ba ô, đặt `Ready`
   (`docs/AGENT_NOTION.md` §5).

## 5. Trạng thái hiện tại (Claude cập nhật cuối mỗi phiên)

Cập nhật 2026-10-15 chiều. Số liệu đổi theo từng commit, nên đây chỉ ghi điều không tự suy ra được; trạng thái thật lấy
bằng `git log --oneline -5` và `sh scripts/gate-all.sh`.

- Lượt DeepSeek 15/10 (T01–T06, T08–T13, T15, T16, T18, T19 + tính năng HUD) đã được Claude review, sửa và tách thành
  commit theo chủ đề trên `main`. Xem bảng "Đã xong" ở đầu mục 6.
- **Trạng thái sống của từng việc: Notion** (`docs/AGENT_NOTION.md`) — view *Queue — Ready* / *Doing* / *Review —
  Awaiting Claude* / *Blocked*. Dòng dưới chỉ là ảnh chụp lúc Claude viết.
- **Kế tiếp: T14d** (T14a–T14c đã gộp; nhánh `agent/<công-cụ>-T14` đã được Claude đưa về `main` sau mỗi lần gộp) — dựng trang Chuột & cử chỉ theo phương án **B** (bạn đã chọn), trên MỘT nhánh
  `agent/<công-cụ>-T14` cho mọi bước còn lại, mỗi bước một commit. Đặc tả từng bước:
  `docs/specs/T14-mouse-gestures-B.md`. Cho tới khi T14 xong, chỉ agent làm T14 được sửa
  `XFinder/Views/Detail/MouseGesturesDetailView.swift` và 6 file
  `XFinder/Views/Components/{MouseDiagramView,GestureButtonList,GestureDetailPanel,GestureArmView,GestureActionPicker,GestureActivityPanel}.swift`.
- **Bạn còn nợ tay:** T-HUD-1…5 (mới), T-ANALYTICS-5, T-ANALYTICS-6, T-LAYOUT-1, T-SLEEP-1, T-LIMIT-1, T-MG-BID.
- **Câu hỏi đang chờ bạn:** Q-RELEASE-14, Q-OC, Q-DIAG-5, Q-MG-1…3. (Q-PROC-1: bạn đã cho agent commit trên nhánh riêng.)

## 6. Chỉ mục đặc tả (hàng đợi sống ở Notion — `docs/AGENT_NOTION.md`; mục này là ảnh chụp và chỉ mục)

- `docs/specs/XF-T35-storage-analyzer-v01.md` — Storage Analyzer v0.1: quét thư mục do người dùng chọn, chỉ đọc, có thể huỷ; chờ review đặc tả và baseline trước khi Ready.
- `docs/MFINDER_XFINDER_ROADMAP.md` — Đối chiếu 12 nhóm tính năng MFinder với hiện trạng XFinder và lộ trình theo mức rủi ro.
- `docs/specs/SNAPMEM-window-layout-memory.md` — Nhớ bố cục cửa sổ theo bộ màn hình (Claude dựng 2026-10-18; chờ test tay T-SNAPMEM-1…5).
- `docs/specs/XF-T21-connect-catalog.md` — Chia sẻ nhanh + Kết nối từ xa vào FeatureCatalog (Builder; Ready sau khi chủ dự án gật).
- `docs/specs/XF-T23-crew-v2.md` — Crew v2 Lead Architect: worktree/nhánh mỗi builder, schema TASK/CRITERIA/BRANCH, rào Approved→merge, hook luôn-hỏi (v2a thuần Claude đã dựng; v2b/v2c theo Q-CREW-1).
- `docs/specs/XF-T22-menubar-explainer.md` — Biểu tượng thanh menu về explainer + ẩn icon XFinder (Builder, cỡ L; Ready sau khi chủ dự án gật).

Mỗi việc dưới đây đã được Claude và một agent soát lỗi độc lập đọc lại trên code thật ngày 2026-10-15. Số dòng có thể lệch
vài dòng khi code đổi: **tìm theo đoạn code được trích**, không theo số dòng. Đoạn trích không còn ⇒ điều kiện dừng.

Không việc nào cần mở app. Việc nào thêm nhãn VoiceOver thì phần "VoiceOver đọc đúng" là **chưa kiểm được**: ghi rõ như vậy
trong worklog, đừng viết là đã xong.

---

### Đã xong (review 2026-10-15, đặc tả cũ xem `git log -p docs/AGENT_TASKS.md`)

| Việc | Commit | Ghi chú review |
|:--|:--|:--|
| T01 README số test | (commit tài liệu) | |
| T02, T03 `onChange` hai tham số | `c19dc73` | |
| T04, T13 `allowedContentTypes` | `05693fa` | chưa kiểm live bộ lọc của bảng mở/lưu |
| T05, T06, T08, T09, T10 nhãn VoiceOver + "Ghim" | `e0ee021` | chưa kiểm live VoiceOver |
| T11, T12 test | `293cabc` | lớp test T12 tên `TimeZoneConversionEdgeCaseTests` (tên kia đã có) |
| T15 Picker nút cuộn | `2c26eb0` | Claude sửa: menu rỗng khi chưa đo được chuột, giá trị đang lưu không có trong menu |
| T16 tên phím chữ/số | `6c8ee2c` | |
| T18 chạy lại harness cử chỉ | — | labels 5/5, ui 8/8 đỏ |
| T19 mở wireframe | — | bạn chọn **B** |
| (ngoài bảng) HUD độ sáng/âm lượng chỉ trên notch | `bf8798f` | Claude sửa 6 lỗi (mục 3c); chưa kiểm live: T-HUD-1…5 |
| T07 | HOÃN | gộp vào T14 |
| T14c sơ đồ + inspector (Antigravity) | `ef47bdd` + `594aae4` | Claude sửa: "Dùng làm nút giữ" mở cho cả chuột phải (`isDeclared` → `isAssignable`); dòng tóm tắt in thẳng "Chưa gán trong macOS" lên UI tiếng Anh (`displayCaption`, test + M11); bấm mũi tên không bỏ chọn chip; mũi tên menu 9 pt; `⌘[`/`⌘]` gõ tay |
| T14b dải chip app (DeepSeek) | `51c0162` (gộp `09c9f3c`) + `ff86f5e` | Claude sửa: icon tra NSWorkspace mỗi lần vẽ → cache `ClipboardAppIcon`, danh sách app đã cài tính 4 lần/lần vẽ → 1; chấm "app phía trước" không sáng ở Toàn cục (`GestureAppChooser`, test + M9–M10) |
| T14a khung 9 khối (DeepSeek) | `3ed7f13` + commit sửa sau review | Claude sửa: câu trạng thái lúc ghi phím tắt bảo "bấm nút chuột" (`GesturePageStatus`, test + M6–M8), danh sách app tạm giới hạn 360 pt, nhãn VoiceOver công tắc đầu trang |

---

### T14 · Dựng trang Chuột & cử chỉ theo phương án B — ĐANG LÀM: T14a–T14c đã gộp vào `main`; kế tiếp **T14d** trên nhánh `agent/<công-cụ>-T14` (đặc tả: `docs/specs/T14-mouse-gestures-B.md`)

- **Làm theo `docs/specs/T14-mouse-gestures-B.md`, từng bước T14a, T14b… một phiên một bước.** Phần dưới là tóm tắt cũ;
  chỗ nào khác đặc tả thì đặc tả thắng.
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

## XF-T32 W2/W3 (Sol)

Jobs: `docs/specs/XF-T32-w23-handoff-sol.md` (B1 metadata, B2 tree, B3 menus, B4 chrome, S1 spaces fix, V1/V2 verify). One line per finished job below.

- 2026-10-26 · B1 metadata · `agent/sol-T32-B1` (Codex, base `7e479fd`) · **BLOCKED before implementation: contract/API mismatch**. Contract §A requires loading emoji for child folders represented in the emoji table, including emoji-only children; `MetadataStore.swift:171–189` exposes only `emoji(for:)`/`setEmoji`, and repo search found no enumeration API or extension. A persisted emoji at `/parent/child` with no nickname cannot be discovered by `load(folder: "/parent")` using the available store API. Fix requires an integrator-owned API such as `emoji(in:)` (or an explicit contract revision); B1 owns only BrowserMetadata + its tests. Next action: Claude supplies the enumeration API and releases B1 again. Contract blob `9ef263b`; handoff blob `14d15d4`. Notion Blocked/Doing/Ready views read successfully but contain no XF-T32 task, so no unrelated task was claimed or changed; reporting here as the handoff explicitly directs. Build: NOT RUN; tests: NOT RUN; gates/mutation: NOT RUN; live: NOT VERIFIED. No source edits, install, launch, push, or merge.

- 2026-10-26 · **B1 metadata — CHỜ REVIEW** · `agent/sol-T32-B1` · source commit `5f7c4e3` · build: `** BUILD SUCCEEDED **` (arm64, own `/tmp/xfinder-sol-b1-build`; BrowserMetadata + MetadataStore present in compile list) · tests: `Executed 2800 tests, with 0 failures (0 unexpected) in 24.154 (24.351) seconds` · 7 B1 tests green; emoji-cache mutant RED by assertion, source restored byte-for-byte and 7/7 green again. Previous blocker resolved by the owner's “tiếp tục đi”: added only the missing read-only `MetadataStore.emoji(in:)` API, no schema changes. Changed BrowserMetadata.swift, MetadataStore.swift, BrowserMetadataTests.swift; this report is the handoff-requested reporting file. No new L10n keys or UI changes. Contract/handoff blobs unchanged (`9ef263b` / `14d15d4`). Notion views have no XF-T32 task to update. Live NOT VERIFIED; no install, app launch, push or merge. B2 onward left for separate sessions per the one-job rule.

B1 failure cases checked: empty/missing metadata and invalid emoji clear safely; Unicode NFD/NFC and literal SQL wildcard characters agree; duplicate in-flight folder loads are dropped and unchanged data does not bump revision; queued writes preserve order and stale loads retry after edits; bootstrap-time edits preserve existing catalog/pins/relations; move/removal rewrites descendants but leaves similarly named siblings alone; memory pressure retains the last eight loaded folders. Permission/disk failures still follow MetadataStore's existing fallback behavior (no new success UI); write-failure injection was NOT tested. No new switch or OS API. All measurements above are tests/builds from terminal processes, not measurements in the installed app.

Initial `gate-all.sh` stdout (verbatim; hook test assumes no `codex` ancestor, contradicted by this session's real process ancestry):

```text
build (arm64, compile list)        OK
tests                              Executed 2800 tests, with 1 failure (0 unexpected) in 25.810 (26.026) seconds
check-l10n-coverage                TOTAL 0 problems across 3534 entries (3534 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3534 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             3
GATE: RED
```

Re-run `gate-all.sh --no-build` in a detached process, reparented outside Codex, same restored source (verbatim; build above was not repeated):

```text
tests                              Executed 2800 tests, with 0 failures (0 unexpected) in 24.154 (24.351) seconds
check-l10n-coverage                TOTAL 0 problems across 3534 entries (3534 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3534 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             3
GATE: green
```

Additional checks: `plutil -lint XFinder.xcodeproj/project.pbxproj` → `OK`; `git diff --check` clean; `verify-l10n-runtime.py` → `TOTAL 0 leaks in the resolved English UI` (existing installed bundle, not a B1 live test). Mutation logs: `/tmp/xfinder-sol-b1-mutant.log` (discarding the loaded emoji dictionary causes the emoji-only child test to fail), `/tmp/xfinder-sol-b1-restored.log` (7 tests / 0 failures).

- 2026-10-27 · **B2 tree — CHỜ REVIEW / L10n integration pending** · `agent/sol-T32-B2` · `101527e` · build: `** BUILD SUCCEEDED **` (arm64, `/tmp/xfinder-sol-b2-build`; FileListView in compile list; final incremental compile also succeeded) · tests: `Executed 2793 tests, with 0 failures (0 unexpected) in 574.421 (574.620) seconds` (detached from Codex; this is test wall time, not a UI-performance measurement). Gate RED only for one deliberately pending L10n key, detailed below. Source files: FileListView.swift only; add-only script `scripts/add-xft32-tree-l10n-entries.py` prepared, NOT RUN. No edits to pbxproj, symlinks, FeatureCatalog, L10n store or other units. Based independently on `main 7e479fd`; Claude must integrate B1 (`5f7c4e3`) and B3 before metadata/hover menus can work end to end. Contract/handoff blobs unchanged (`9ef263b` / `14d15d4`). No install, XFinder launch, events/keys to other apps, push or merge.

B2 contract §E / design §3b mapping:
- Name-only, non-search List uses the existing 31-point token, no table header or alternating backgrounds; multi-column/search keeps the existing table. Column chooser logic is retained. Per-cell content remains inside the outline, with no hit-testing overlay or ancestor tap recognizer.
- `PinRules.split` creates a distinct, unselectable pinned header and moves pinned entries out of the regular sections; stale pins are ignored without toggling/deleting them. A self pin uses a synthetic entry + localized “Thư mục này”; its placeholder timestamps/size are never displayed. Self pins do not expand/start a second watcher on the current pane. Pinned row backgrounds use the existing 10-point radius token, first/last corners, zero inter-row gaps and the dynamic gray fill token. Remaining groups continue through the original section path.
- Tree Name cell keeps an editable, middle-truncating name; shows folder emoji or cached icon, secondary nickname, colored property chips using PropertyTint, hover ellipsis wired to RowActionsMenu, folder chevron. Cloud badges, Finder tag dot and cut fade are retained. Passive chip content does not receive mouse hits.
- Reads metadata revision during representable update; metadata-only changes reload visible rows and exclude the field editor/renaming path. Pin structural changes defer until rename ends. ListingDiff remains for regular entry rows plus the unique pinned header; group headers retain the full-reload path. Existing rename, drag/drop, spring-load, PaneActivating and watcher teardown remain. Expanded children request their folder metadata.

Failure cases addressed in code: empty listing or all entries pinned; missing/stale pins; root/self folder pin; similarly named real group header; changed pins while renaming; metadata changes while scrolling/editing; switching tree/table/search; many or long property/nickname labels (name uses middle truncation and lower compression priority); collapsed/gone child folders release watchers. Missing metadata produces the existing icon/name; no fabricated values or dead new toggles. These are code-path checks, NOT live verification.

New L10n key: `còn gọi là ` → `aka `, scope `fragment` (trailing space retained). The handoff explicitly assigns the store to Claude and says not to run the add-only script. Therefore the untranslated-key gate is intentionally reported RED, not waived or represented as green. Next integration action: run `python3 scripts/add-xft32-tree-l10n-entries.py`, rebuild, and rerun gate-all after combining the units.

Final detached `gate-all.sh --no-build` stdout (verbatim; build ran separately):

```text
tests                              Executed 2793 tests, with 0 failures (0 unexpected) in 574.421 (574.620) seconds
check-l10n-coverage                TOTAL 0 problems across 3534 entries (3534 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3534 unique keys
audit-l10n-literals                TOTAL 1 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             1
GATE: RED
```

Other checks: `plutil -lint XFinder.xcodeproj/project.pbxproj` → `OK`; `git diff --check` clean; add-only script AST parses (not executed). Build logs: `/tmp/xfinder-sol-b2-build.stdout`, `/tmp/xfinder-sol-b2-build/build.log`, `/tmp/xfinder-sol-b2-incremental.log`.

**Chưa kiểm live:** tree/table column switching, inline rename during watcher/pin changes, pinned-card rendering with expanded folders, narrow-window chip layout, selection/drag/drop/spring-load, hover-menu behavior after B3, keyboard/VoiceOver, scrolling performance and memory. The requested screenshot sheets were absent; read-only `orca computer get-app-state --app com.blazegreenhalgh.FileExplorer` returned `window_not_found` (“Tilde has no on-screen window”). No app was opened or restored and no input was sent. Visual match is based on the contract, not a claimed screenshot comparison. Existing pure tests do not exercise this AppKit view. B3 onward remains for separate sessions.

## XF-T32 B1/B2 integration — owner-requested, 2026-10-27

The owner explicitly requested “tích hợp luôn đi”, authorizing integration rather than leaving these units for Claude. Integration branch: `agent/codex-T32-integration`, based on `main 7e479fd`. Preserved the complete B1 and B2 branch histories; the sole merge conflict was the appended report section in this file, resolved by retaining both reports. Included completed worker branch `xf-t32-w23-menus` (`54b61ab`) as B2's required RowActionsMenu/property-editor dependency. Other W2/W3 worker branches were not integrated. Final wiring/translation commit: `6218ccc`. The earlier B1/B2 “Awaiting Claude” and pending-localization reports above are historical; their code and translations are now combined and validated here.

Integration changes: shared selection and background context menus expose metadata/property actions, including the synthetic self-pin menu; property grouping updates when metadata changes, with a dedicated section revision and structural changes deferred during rename; successful queue rename/move/trash, merge moves and move undo/redo notify BrowserMetadata without changing filesystem operations or their decisions. Memory-pressure relief now reaches the metadata cache. Added 29 L10n keys via the add-only tree/integration scripts, including dynamically referenced property/color labels; neither script rewrites an existing translation. Changed the sheet callback to an explicit main-actor task. Existing clipboard/agent/privacy/release code and other worktrees' uncommitted changes were left alone.

Build: `XF_ROOT=<this checkout> XF_OUT=/tmp/xfinder-t32-integration-final-build sh scripts/build-and-check.sh` (through gate-all) succeeded for arm64; compile-list checks passed. The built bundle's L10n JSON was read from `/tmp/xfinder-t32-integration-final-build/out/XFinder.app/Contents/Resources/L10n.strings.json` and compared with the source: equal. This is a build/resource check, not installed-app runtime verification.

Full `gate-all.sh` stdout, detached outside the Codex process ancestry (verbatim):

```text
build (arm64, compile list)        OK
tests                              Executed 2800 tests, with 0 failures (0 unexpected) in 23.778 (23.980) seconds
check-l10n-coverage                TOTAL 0 problems across 3563 entries (3563 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3563 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             9
GATE: green
```

`plutil -lint XFinder.xcodeproj/project.pbxproj`: OK. `git diff --check`: clean. No new Swift files, project registrations or test symlinks. Existing B1 regression tests run in the full 2800-test suite (the AppKit views and queue wiring are validated by the app build, not exercised by those pure tests). Earlier B1 emoji mutant evidence remains recorded above; no mutation harness was rerun during integration.

**Chưa kiểm live:** installed-app clicks, menus/popovers, VoiceOver, narrow layouts, metadata during real file moves/trash/conflict replacement/undo/redo, scrolling performance and idle/memory behavior. External filesystem changes are not newly instrumented by this integration. No installation, app launch, synthetic input, signing/release action or push. Main is updated only by fast-forward to the validated integration branch, with all commits created on `agent/codex-T32-integration` (no commit created on main).

## XF-T32 W2/W3 completion — owner request, 2026-10-27

Owner requested all remaining handoff work, including integration. Branch `agent/codex-T32-finish` starts at validated `main 0bd315e`; integrates the existing Spaces/sidebarparts/sidebar/chrome worker commits and retains the earlier B1/B2/menu integration. Before fixes, failure cases recorded: missing/corrupt Space or mirror data; default SidebarLayout creates fresh UUIDs; clean relaunch must not save/reset favorites; only one Space; empty/duplicate/deleted Space names; Space switch during rename/drag; same-Space sidebar edits in another window or settings; stale/missing/file/package Live Group paths; large Space count; missing folder permissions; cancelled related-folder picker; narrow panes; path bar and focus-style switches in both states. V1/V2 source findings are in docs/reviews (worker branches left unchanged). Live behavior remains a separate acceptance item.

### Final result — all remaining handoff jobs complete in source

Source fix commit `4d6acf4`, branch `agent/codex-T32-finish`. Preserved worker histories: spaces `713847a`, sidebarparts `cd3699a`, sidebar `22ef1e1`, chrome `903b04a`. B1/B2/B3 were already integrated at `main 0bd315e`. Resolved the chrome merge conflicts by retaining the metadata observer, one geometry observer/no ancestor tap gesture, and the union of added translations (existing keys unchanged).

| Job | Result | Evidence / limits |
|:--|:--|:--|
| B4 chrome | Complete | Bottom 24 pt breadcrumb with default on in both views/reader, 28 pt related-items strip, dim/outline focus setting and opacity-only dimming. Existing path-bar choices retained; matching defaults covered by tests. Related-item label may compress in narrow panes. No live layout/click verification. |
| S1 Spaces | Fixed | Explicit presence/validity check for the sidebar mirror, seed missing mirror from persisted active Space, semantic comparison before saving. Missing-mirror and first-launch tests were RED before the fix, as was the equivalent-JSON-format test; all now GREEN. 19 SpaceController tests + 2 default-key tests pass. The additive `hasLegacyLayout` initializer argument defaults false and is explicitly backed by the real stored-data check in BrowserSettings. |
| V1 sidebar parts | Reviewed, rebuilt, fixed | `docs/reviews/XF-T32-w23-sidebarparts-sol.md`. Exact worker build GREEN. Composite group identity; folder/package/missing-path facts fetched off-main on metadata/Space events, loading distinct from empty; one scrollable dot per Space. Added a menu to select/unselect Live Groups so the feature is reachable. |
| V2 sidebar | Reviewed, rebuilt, fixed | `docs/reviews/XF-T32-w23-sidebar-sol.md`. Exact worker build GREEN. Every external sidebar mirror writer forwards to the active Space; all same-Space windows/settings observe active.sidebar. Pending edits cancel on Space change; asynchronous drops check the target Space/group before applying. Existing eject, groups, rename, drag/drop, spring-load, Pro and provider behavior retained in source. |
| B3 final contract check | Complete | Value menus now list all catalog properties; folder visibility is independent. No property is silently omitted because it is not yet shown in the folder. |

V1 and V2 exact worker builds ran sequentially with their own XF_ROOT/XF_OUT, leaving both checkouts clean. Final integrated clean build ran via gate-all with `XF_OUT=/tmp/xfinder-t32-finish-build`; all seven Spaces/sidebar/chrome source files are in the app compile list, and the built L10n JSON equals the source (3587 entries). A final incremental app build then compiled the all-catalog menu correction successfully. `plutil -lint` and `git diff --check` pass.

Full clean build + gate stdout (verbatim, before the final one-line menu scope correction; no new package sources changed afterward):

```text
build (arm64, compile list)        OK
tests                              Executed 2819 tests, with 0 failures (0 unexpected) in 24.115 (24.317) seconds
check-l10n-coverage                TOTAL 0 problems across 3587 entries (3587 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3587 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             14
GATE: green
```

Final gate stdout after the menu correction, using `--no-build` because the final incremental arm64 build had just succeeded (verbatim):

```text
tests                              Executed 2819 tests, with 0 failures (0 unexpected) in 23.830 (24.029) seconds
check-l10n-coverage                TOTAL 0 problems across 3587 entries (3587 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3587 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             14
GATE: green
```

Logs: `/tmp/xfinder-t32-s1-red.log` (2 regression tests RED on original implementation); `/tmp/xfinder-t32-s1-format-red.log` (format regression RED); `/tmp/xfinder-t32-s1-final-green.log` (21 tests GREEN); `/tmp/xfinder-t32-finish-status.json` (V1, V2, final pipeline exit codes all zero); `/tmp/xfinder-t32-finish-incremental.log` (final app build). Localization scripts sidebarparts/chrome/finish are add-only and were applied; no missing wrapped translations remain. No new Swift source files or project/test registrations were needed.

**Chưa kiểm live:** visual comparison with Tilde (reference sheets absent; prior Tilde probe had no on-screen window), accessibility/VoiceOver, physical click/drag/eject flows, multi-window switching while editing, related-folder picker under real permissions, runtime persistence across installed-app relaunches, pane layout at narrow sizes, scrolling/idle CPU/memory. Live Group directory facts refresh on metadata/Space changes; arbitrary external changes elsewhere on disk do not get a new global watcher here. The original handoff's no-install/no-launch restriction remains respected. No install, app launch, input to other apps, release/signing action or push. All measurements above are terminal builds/tests, not installed-app measurements.

The owner explicitly authorized finishing and integrating all remaining jobs; main is advanced only by fast-forward from the validated agent branch, with no commits created directly on main. Other worktrees' uncommitted changes were not touched.

## XF-T32 installed-app verification — 2026-10-27

Owner explicitly authorized installation and live tests, superseding the earlier handoff's no-install/no-launch restriction for this verification. Installed validated `69e9b9b` using the existing signing/install script; dylib SHA-256 matched `ce3896c74720bec03144c57a19984e9ca41372a4fafbe56d49f82c0faa15ba6a`; stable designated requirement retained; installed English runtime gate TOTAL 0. Fixtures and prior-app/preferences backup are under `/tmp/xfinder-live-20261027` (private task directory).

Live bug reproduced before fix: switching List columns caused the installed app to exit. Unified log: `NSOutlineView cannot remove outlineTableColumn with removeTableColumn:. Use setOutlineTableColumn: instead.` followed by `Swift/NativeDictionary.swift:823: Fatal error: Duplicate values for key: 'NSUserInterfaceItemIdentifier(_rawValue: name)'`. Cause: rebuildColumns removes all columns without first detaching the Name outline column. Native AppKit probe from terminal reproduces one leftover column with the original sequence. Assigning nil does not permit its removal on this OS, so that initial attempted fix was rejected before installation. The corrected native probe passes 20 rebuilds by retaining Name, removing only auxiliary columns and never re-adding Name; the production fix follows that sequence, normalizes columns to one Name first and reloads visible cells while excluding a rename. Failure cases for retest: multi-column→Name-only tree and back; repeated toggles; row selection and inline rename after rebuild; no duplicate columns, no crash, selection preserved. Live physical click of item-03.txt selected the row in 41 ms once XFinder was verified frontmost. The earlier click while Chrome was frontmost is invalid latency evidence and is excluded.

Additional installed-app findings: pinning succeeded (SQLite read-only verification and a single moved row), but its group header rendered blank because AppKit requests spanning group cells with tableColumn=nil and the delegate rejected nil. Screenshot `tree-pinned.png` and AX dump show an empty group row. In Name-only mode AXColumn remained 292 pt in a 1309 pt outline; row actions/folder chevrons stayed near the old column edge. Fix accepts nil for group cells, fits the tree Name column to the viewport, and restores its saved table width/resize behavior when returning to multiple columns. These are visible live defects, not inferred from a green build.

Final visual-fix build: `/tmp/xfinder-t32-live-visual-build`; full gate 2819 tests / 0 failures, all string/UI gates TOTAL 0, GATE green. Installed with the existing stable signing script. Installed-app AX confirms the Pinned header now has text. Pin and owned Space favorite survived reinstall; switching Spaces isolated the favorite in the earlier installed build. Final Name-only width and repeated-toggle live checks remain unverified: another XFinder window retained keyboard focus and the attempted click did not select the row; excluded as evidence. Native 20-cycle column probe passed; this is terminal probe evidence, not installed-app behavior. Owned test Space XF Live 20261027 and fixture pin remain for follow-up cleanup; no user's files changed. Inline rename, properties, related links, split focus and watcher changes not live verified in this run.

```text
build (arm64, compile list)        OK
tests                              Executed 2819 tests, with 0 failures (0 unexpected) in 24.240 (24.451) seconds
check-l10n-coverage                TOTAL 0 problems across 3587 entries (3587 checked, 31 allowlisted)
check-l10n-duplicates              TOTAL 0 duplicates across 3587 unique keys
audit-l10n-literals                TOTAL 0 wrapped-but-untranslated, 1320 unwrapped
check-sidebar-groups-l10n          TOTAL 0 problems across 7 sidebar group headers and 47 page titles
audit-gesture-vocabulary-l10n      TOTAL 0 unresolved gesture strings
audit-l10n-interpolations          TOTAL 0 interpolated strings with Vietnamese outside L10n.t
audit-ui-tokens                    TOTAL 0 problems across 0 files
modified tracked files             2
GATE: green
```

Follow-up live verification (2026-10-27): after closing the obstructing XFinder dashboard and foregrounding the browser, an actual click selected item-05.txt in 54 ms. Name-only mode had 31 pt file rows, a visible Pinned header and one 1304 pt column in the 1324 pt row viewport. Three consecutive multi-column/tree transitions retained 24 rows (23 items + pin header), column counts 4 → 1 → 4, with no crash. Unpinned the owned item via UI and deleted only XF Live 20261027 via UI. Read-only SQLite confirms no owned pins; preferences contain only the baseline Personal Space and five original favorites. This supersedes the earlier pending column checks/cleanup; inline rename and other noted live checks remain unverified.
