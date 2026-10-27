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
