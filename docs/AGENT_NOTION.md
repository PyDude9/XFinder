# Routine nhiều agent qua Notion — XFinder

Viết 2026-10-15, đã qua một vòng review đối kháng (4 lăng kính × 2 người phản bác; 13 phát hiện xác nhận, 4 chia đôi,
2 bác bỏ — tất cả phát hiện đứng được đã sửa ở dưới). Áp dụng từ T14d. **(đo)** = đã đo trên máy này hoặc trên
workspace Notion này, có ngày; **(chưa kiểm)** = chưa ai đo, đừng coi là đã có.

Notion, hai tầng (từ 2026-10-16):
* **Engineering Control Center** — https://app.notion.com/p/3fb97dfe4af381e883f2f8cb71c15bdc — trang cấp workspace giữ
  **một** bộ 5 database cho **mọi** dự án: Projects (registry: `Code`, `Repo Path`, `GitHub`, `Hub`) · **Tasks** · **Runs**
  · Decisions · Playbooks. Dự án = một dòng Projects + một trang hub; không bao giờ tạo bộ database riêng.
* **XFinder** (hub) — https://app.notion.com/p/3fa97dfe4af381fca7f2d30a967805f0 — chỉ gồm các linked view lọc
  `Project = XFinder` (`XF · …`) + trang Quy trình. Trợ lý khác đã dựng bản đầu và nạp 163 task (155 là test tay T-*), 42
  quyết định, 4 Run lịch sử; Claude đối chiếu các dòng T14 với `main a2954e2` (2026-10-15), thêm cột, thêm view, gỡ ba State
  "(reported)", rồi (2026-10-16) chuyển 5 database lên trang gốc — **id, URL và mọi view giữ nguyên (đo: view Queue trả
  T14d trước và sau khi chuyển)**.
* `Task ID` của việc **mới** mang tiền tố dự án (`XF-T20`); 163 ID cũ giữ nguyên vì nhánh git và docs đang trỏ vào chúng.

## 1. Hai nguồn sự thật, chia theo bản chất dữ liệu — không chọn một

| Ở Git (theo commit) | Ở Notion (theo trạng thái) |
|:--|:--|
| **Đặc tả** `docs/specs/<ID>.md` — vì đặc tả phải `git diff` được, grep được từ shell của agent, và đi cùng code nó mô tả. Một đặc tả nằm ngoài repo sẽ lệch với code mà không ai thấy | **Hàng đợi + trạng thái** của từng việc (Tasks): ai đang làm, nhánh nào, bị chặn vì sao |
| Code, test, gate, harness, script | **Nhật ký chạy** (Runs): mỗi phiên một dòng, append-only, kết quả gate dán nguyên văn |
| Quy tắc kỹ thuật: `docs/AGENT_QUICKSTART.md`, `docs/AGENT_TASKS.md` §1–§3 (cỡ việc, vùng cấm, quy trình, điều kiện dừng) | **Quyết định** (Decisions): câu hỏi Q-* và mặc định đang áp dụng; chủ dự án trả lời ở đây |
| `CLAUDE.md` (bài học, chỉ Claude đọc) | **Playbooks**: quy trình đã được dùng thật ít nhất một lần |

Hệ quả: **`docs/AGENT_TASKS.md` §6 không còn là hàng đợi** — nó là chỉ mục đặc tả và ảnh chụp; hàng đợi là view
*Queue — Ready*. `docs/AGENT_WORKLOG.md` chỉ còn là đường dự phòng (mục 7). **Hai bề mặt "đặc tả" là hai thứ khác
nhau:** file `docs/specs/*.md` trong Git (nội dung) và vùng *Spec* trên trang task Notion (con trỏ + tóm tắt). Cả hai
chỉ Claude sửa khi task đã `Ready`/`Doing`; agent viết đặc tả MỚI theo `AGENT_TASKS.md` §3c thì tạo file mới, không
sửa file đang được một task tham chiếu.

## 2. Vai trò, vùng ghi, và cách ghi

| Vai trò | Công cụ hiện có | Đọc | Ghi ở Notion | Ghi ở Git |
|:--|:--|:--|:--|:--|
| **Chủ dự án** | Notion (điện thoại cũng được) | Home, các view | Decisions (trả lời), `Execution Allowed`, `Priority`; đặt `Claimed By` hộ khi đi đường dự phòng (mục 7) | — |
| **Claude** (lên kế hoạch · tích hợp · review cuối) | Claude Code | tất cả | vùng **Spec**; `Spec Approved` · `Spec Revision` · `Spec Path` · `Baseline Verified`; `Merged As`; State `Draft → Ready`, `Awaiting Claude → Done/Awaiting live`, `Blocked → Ready` (và xoá `Claimed By` khi đặt Ready); Playbooks; Decisions (mặc định) | `docs/specs/*`, `main`, gộp nhánh, `CLAUDE.md` |
| **Builder** (làm theo đặc tả) | OpenCode + DeepSeek; Antigravity; Zed | **một** trang task + file đặc tả trong repo | vùng **Execution**; `Claimed By` · `Branch` · `Reported Commits`; State `Ready → Doing → Awaiting Claude` hoặc `→ Blocked` + `Block Reason` + `Next Action`; **Run của chính mình** | commit trên `agent/<công-cụ>-<ID>` |
| **Reviewer** (đọc chéo, công cụ **khác** Builder) | Antigravity (Gemini), hoặc OpenCode với model khác | trang task + `git diff main...<Branch>` | vùng **Review** (phát hiện), `Pre-reviewed` ✓, một Run `Kind = pre-review` | không gì cả |
| **Surveyor** (khảo sát, chỉ đọc) | Antigravity / OpenCode | repo + web | một Run `Kind = research`, hoặc phần "Bối cảnh và bằng chứng" của một Decision | không gì cả |

**Ba vùng trên một trang task là ba heading H2 trong body** (xem trang T14d làm mẫu):
`## Spec — Claude giữ (Builder không sửa mục này)` · `## Execution — Builder ghi` · `## Review / Acceptance`.
Ghi vào vùng = `notion-update-page` với `command: "update_content"` và `old_str` là **đúng dòng bullet** dưới heading đó
(ví dụ `- Active Run ID:` → `- Active Run ID: R-T14d-20261015-2140`). **Không bao giờ `replace_content` một trang task**
(nó ghi đè cả ba vùng), và thuộc tính thì luôn `update_properties` **chỉ với các cột của vai mình** — một bản vá
từng-cột, không phải đọc-cả-trang-rồi-ghi-lại.

**Từ vựng cho `Claimed By`:** `<công-cụ>/<model> <ISO 8601 có giây và múi giờ>`, trong đó `<công-cụ>` là **một từ
thường** trùng tiền tố nhánh: `opencode` · `antigravity` · `zed` · `cursor` · `codex` · `claude`. Ví dụ
`opencode/deepseek-v4.1-flash 2026-10-15T21:40:12+07:00`. Reviewer chỉ so **token đầu** (trước dấu `/`) với công cụ
của mình; model hay giờ khác không có nghĩa là công cụ khác.

Builder không bao giờ sửa vùng Spec hay file `docs/specs/*` đang được tham chiếu. Claude không viết vào vùng Execution
của một Run đang chạy. Reviewer không sửa file, không đổi State. Vi phạm vùng ghi = điều kiện dừng cho người phát hiện
(ghi vào Run, dừng).

## 3. Vòng đời một việc (State trong Tasks)

```
Draft ──► Waiting predecessor/spec ──► Ready ──► Doing ──► Awaiting Claude ──► Awaiting live ──► Done
                                        ▲          │                                 (test tay T-*)
                                        │          ▼
                                        └──── Blocked (+ Block Reason + Next Action)
                                              ◄── bất kỳ điều kiện dừng nào ở AGENT_TASKS §3
```

**Cổng vào `Ready` — ba ô, chỉ Claude tích, view Queue lọc trên cả ba (đo: view chỉ trả T14d):**

| Ô | Nghĩa chính xác | Bằng chứng |
|:--|:--|:--|
| `Spec Approved` | đặc tả đã nằm trên `main`, không tự mâu thuẫn, có danh sách tình huống hỏng (QUICKSTART luật 11) | `Spec Path` + `Spec Revision` |
| `Baseline Verified` | `sh scripts/gate-all.sh` xanh trên đúng SHA `main` mà Builder sẽ rẽ nhánh từ đó | một Run `Kind = gate-baseline` trỏ tới task, ô `Commit or Reference` ghi SHA |
| `Execution Allowed` | chủ dự án (hoặc Claude thay mặt, theo Q-PROC-1) cho phép làm | — |

Hai quy tắc đi kèm: **(a) bước sau của một việc nhiều bước không bao giờ `Ready` khi bước trước chưa `Done`** — Claude
chỉ tích ba ô cho T14e sau khi T14d đã gộp (vì cùng một nhánh); **(b) khi đặt `Ready` (kể cả từ `Blocked`) Claude xoá
`Claimed By`**, nên "`Claimed By` rỗng" luôn có nghĩa là "chưa ai giữ", không cần suy luận theo thời gian.

**`Spec Revision` = 7 ký tự đầu của blob hash file đặc tả** — `git hash-object docs/specs/<file> | cut -c1-7`
(T14: `53e3659`). Blob hash chỉ đổi khi **nội dung** đổi, không đổi khi `main` bị squash/rebase hay khi một commit vừa
sửa đặc tả vừa sửa code — nên nó so được trên bất kỳ checkout nào. Commit đụng file lần cuối
(`git log -1 --format=%h -- <file>`) chỉ để người đọc lần ra lịch sử. Claude đổi đặc tả ⇒ commit ⇒ sửa ô này cùng lúc.
Builder đọc lại hash **lúc bắt đầu và lúc commit**; khác với ô trong Notion ⇒ `Blocked` / `spec-drift`.

**Hai SHA, hai cột:** `Reported Commits` = SHA trên nhánh agent lúc bàn giao (Builder ghi); `Merged As` = SHA trên
`main` sau khi gộp (Claude ghi). Không bao giờ ghi đè cột của nhau.

## 4. Nhận việc (claim) — vì Notion không có khoá nguyên tử

Notion ghi theo kiểu "ai ghi sau thắng". Claim ở đây là **tư vấn, không phải khoá**: nó thu hẹp cửa sổ đụng nhau xuống
vài giây mạng, và phần còn sót (hai Builder cùng vượt qua) được Claude bắt ở `Awaiting Claude` dưới dạng hai Run cho một
task — tốn công, không mất dữ liệu. Quy ước:

1. Đọc **ba** view, theo thứ tự: **Blocked** và **Doing** trước — nếu có task nào cùng `Branch` (ví dụ `agent/*-T14`)
   hoặc cùng tiền tố `Task ID` với việc định nhận đang `Blocked`/`Doing`, **không nhận**: bước sau của việc đó không
   được chạy khi bước trước đang kẹt trên cùng nhánh. Rồi **Queue — Ready**: lấy dòng đầu (đã sắp theo `Priority`,
   `Task ID`), hoặc đúng ID chủ dự án ghi trong prompt. URL ba view ở mục 6; truy vấn bằng
   `notion-query-data-sources` `mode: "view"` — **không dùng SQL** (mục 6).
2. `fetch` trang task **ngay trước khi ghi** (một lần đọc cũ hơn ~30 giây là vô giá trị — đọc lại). Điều kiện:
   `State = Ready` **và** `Claimed By` rỗng. Không đủ ⇒ dòng kế.
3. Ghi **một lệnh `update_properties`** với đúng ba cột: `Claimed By` (từ vựng ở mục 2), `State = "Doing"`,
   `Branch = "agent/<công-cụ>-<ID>"` (việc nhiều bước: nhánh đã có trong ô `Branch`, giữ nguyên tên đó dù công cụ khác).
   Rồi tạo Run (payload mẫu ở mục 6): `Run ID = R-<ID>-<yyyymmdd-hhmm>`, `Task` = URL trang task, `Kind = build`, các ô
   `Build/Tests/Gate/Mutation/Live` = chuỗi `NOT RUN`.
4. Chờ ~10 giây (`sleep 10` trong shell là đủ), `fetch` lại trang task. `Claimed By` **không còn là đúng chuỗi của mình**
   ⇒ người khác đã nhận: **không ghi gì thêm**, ghi vào Run của mình `Outcome = "lost claim to <chuỗi kia>"`, quay lại
   bước 1.
5. Trong repo, với `<base>` = SHA trong ô `Commit or Reference` của Run baseline (Run `Kind = gate-baseline` trỏ tới
   task; T14d: `a2954e2`): `git merge-base --is-ancestor <base> main` phải thoát 0 **và**
   `git diff --stat <base> main -- XFinder Tests scripts` phải **rỗng** — tức `main` chỉ trôi vì commit docs của Claude
   (bình thường; chính commit tạo ra tệp này đã làm vậy), còn nguồn/test/script y như lúc đo gate. Có khác ⇒ Claude phải
   đo lại baseline: `Blocked` + `acceptance-mismatch`, dán output `git diff --stat` vào Run, dừng.
   `git hash-object <Spec Path> | cut -c1-7` phải bằng `Spec Revision`; khác ⇒ `Blocked` + `spec-drift`. **Không
   `git pull`** trừ khi chủ dự án bảo — repo này không đẩy lên remote giữa phiên.
6. Làm theo `docs/AGENT_TASKS.md` §3 (nhánh, commit, gate). Kết quả `gate-all.sh` dán **nguyên văn** vào Run (mục
   "Gate stdout nguyên văn"), không tóm tắt; bảy việc-cạnh của đặc tả trả lời trong Run.
7. Xong: `Reported Commits = <sha nhánh>`, `State = "Awaiting Claude"`; Run: `Outcome`, "Chưa kiểm". Dừng — không push,
   không merge, không gộp bước kế, không xoá `Claimed By`.

**Dừng giữa chừng** vì điều kiện dừng ⇒ `State = "Blocked"`, `Block Reason`, `Next Action` = một câu Claude cần biết;
Run ghi lệnh đã chạy và lỗi nguyên văn. **Không** xoá `Claimed By` (Claude cần biết ai dừng ở đâu). Ghi `Blocked` **chính
là** tín hiệu báo động: không có gì khác bắn thông báo (mục 8). Chủ dự án mở Notion (điện thoại được) thì nhìn view
**Blocked** trước; Claude khi về đọc view **Blocked** trước view Review.

## 5. Review và tích hợp

- **Reviewer** (tuỳ chọn, trước khi Claude có quota): lấy view **Review — Awaiting Claude** với `Pre-reviewed` trống và
  token đầu của `Claimed By` **khác** công cụ của mình. Đọc `git diff main...<Branch>` và trang task. Ghi phát hiện
  vào vùng Review theo bốn câu hỏi của `AGENT_TASKS.md` §3b (đủ bước chưa · có đổi ngoài đặc tả · đụng vùng cấm ·
  chuỗi không qua `L10n.t`), tích `Pre-reviewed`, một Run `Kind = pre-review`. **Không sửa file, không đổi State.**
  Builder có thể sửa theo phát hiện trên cùng nhánh (commit mới) trước khi Claude tới — ghi vào Run của mình.
- **Claude khi có quota** (`AGENT_TASKS.md` §4): view **Blocked** → gỡ chặn (sửa đặc tả / trả lời / đổi phạm vi), xoá
  `Claimed By`, đặt lại `Ready` hoặc `Draft`. View **Review — Awaiting Claude** → mỗi task: `git log main..<Branch>`,
  `gate-all.sh` chạy lại ở checkout đúng, so với đặc tả và vùng cấm, đo live phần "chưa kiểm" nếu đo được → gộp vào
  `main` (giữ commit của agent) hoặc sửa/bỏ với lý do → `Merged As` = SHA trên main → State `Done` (hoặc `Awaiting
  live` nếu còn T-* chờ tay chủ dự án) → một Run `Kind = claude-review` → đưa nhánh về `main`; xoá nhánh và worktree đã
  gộp khi việc (mọi bước) đã xong (`git worktree remove ../XFinder-<ID>`; nhánh T14 chỉ xoá sau T14f) → viết đặc tả +
  Run baseline cho việc kế → tích ba ô → `Ready` (và `Claimed By` rỗng).
- **Trước khi chép một mục `CHỜ REVIEW` từ worklog (đường dự phòng) thành Run:** kiểm trang task — đã có `Claimed By`
  hoặc Run khác cho cùng ID trong cùng khung giờ ⇒ ghi **xung đột (hai lần thực thi)** vào cả hai Run và quyết định
  bản nào gộp; không gộp im lặng.
- Một nhánh **không có commit mới** không bao giờ là "sẵn sàng gộp", dù Run hay transcript nói gì.

## 6. Dùng Notion MCP cho đúng — địa chỉ, schema, payload

### 6.1 Hạn mức (đo 2026-10-15, gói Notion hiện tại của workspace này)

- **(đo)** `query-data-sources` chế độ **SQL** chạm *usage limit* sau **5 lệnh** trong một phiên. Vì vậy agent không
  dùng SQL.
- **(đo một lần)** ngay sau khi SQL bị chặn, một lệnh `query-data-sources` chế độ **view** vẫn chạy và trả đúng dòng.
  Mô tả của công cụ nói chế độ view không có hạn mức riêng; **chưa đo** nhiều lệnh view liên tiếp trong một phiên —
  coi là rủi ro còn mở cho tới khi đo (T-NOTION-4).
- **(đo 2026-10-15)** Claude trong app desktop nối qua connector claude.ai và **ghi được**: thêm 6 cột và sửa select
  `State` (schema), tạo 5 view, sửa thuộc tính 7 trang task, `replace_content` body T14d, `update_content` trang Home —
  mỗi lần đều `fetch` đọc lại thấy giá trị mới.
- Các công cụ khác nối qua Notion MCP có host `https://mcp.notion.com/mcp` bằng OAuth (bắt buộc, không có đường API
  key cho server host — developers.notion.com/docs/get-started-with-mcp); **chủ dự án đăng nhập một lần cho mỗi công
  cụ** (Q-NOTION-4). Claude không đụng cấu hình của công cụ khác. Trên máy này **chưa công cụ nào được đăng nhập**
  (chưa kiểm — Claude không đọc các file cấu hình đó theo quy tắc); cho tới lúc đó đường dự phòng (mục 7) là đường
  chính.

### 6.2 Địa chỉ

| Thứ | Địa chỉ |
|:--|:--|
| Database Tasks | `https://app.notion.com/p/7e911ae9ba9347c395c5d63bc2cc966f` — data source `collection://d76c9572-6ae9-4d62-ae64-8876a7ec064b` |
| Database Runs | `https://app.notion.com/p/044ddc6bf7164fea9ff064221e826ee5` — data source `collection://1b6ccecf-745a-4f93-8519-d8f09c61be21` |
| Project XFinder (relation) | `https://app.notion.com/p/3fa97dfe4af381e4b2b9fe4509beccb4` |
| View **Queue — Ready** | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fa97dfe4af381ae9996000c6cb9f378` |
| View **Doing** | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fa97dfe4af38144967c000cc2cd3db4` |
| View **Review — Awaiting Claude** | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fa97dfe4af38129b35d000cdf1e41f1` |
| View **Blocked** | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fa97dfe4af381c192eb000c1a4b9549` |
| View **Hand tests (T-*)** | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fa97dfe4af381f19464000c870d28a9` |
| Trang gốc **Engineering Control Center** | `https://app.notion.com/p/3fb97dfe4af381e883f2f8cb71c15bdc` |
| Hub **XFinder** · `XF · Queue — Ready` (lọc theo dự án — **Builder dùng view này**) | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fb97dfe4af3818b8f5d000c04e18446` |
| Hub · `XF · Doing + Awaiting Claude` | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fb97dfe4af381bdbdbb000c279d94d9` |
| Hub · `XF · Blocked` | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fb97dfe4af3819b8b9c000ce1fa94d0` |
| Hub · `XF · Waiting / Draft (spec queue)` | `https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fb97dfe4af38117927c000cd71e4f43` |
| Hub · `XF · Runs (newest first)` | `https://www.notion.so/044ddc6bf7164fea9ff064221e826ee5?v=3fb97dfe4af38171bd54000c5bc116b8` |
| Hub · `XF · Decisions waiting for the owner` | `https://www.notion.so/10b4e7a3762a48bd92d8e5100331a596?v=3fb97dfe4af38166be0c000c1d0821b7` |

Năm view đầu (tab của database Tasks) là **toàn cục** — mọi dự án, có *Quick filter* `Project` để lọc tay trong UI; đó là
view của Claude khi review chéo dự án. Các view `XF · …` trên hub **đã lọc sẵn theo dự án** và **(đo 2026-10-16)** truy vấn
được bằng `mode: view` y như view toàn cục (trả đúng T14d). Builder của một dự án đọc view hub của dự án đó; dự án thứ hai có
bộ `<Code> · …` riêng với URL riêng (tạo theo "Thêm một dự án mới" trên trang gốc).

Đọc một view (tên tool có thể mang tiền tố server tuỳ công cụ, ví dụ `notion_query-data-sources`):
```json
{"data": {"mode": "view", "view_url": "https://www.notion.so/7e911ae9ba9347c395c5d63bc2cc966f?v=3fa97dfe4af381ae9996000c6cb9f378", "page_size": 20}}
```

### 6.3 Schema Tasks (đúng tên cột, đúng cách mã hoá)

| Cột | Kiểu | Giá trị |
|:--|:--|:--|
| `Name` | title | `<ID> — <một kết quả nghiệm thu được>` |
| `Task ID` | text | `T14d` |
| `Kind` | select | `Workflow proposal` · `Epic` · `Implementation` · `Manual verification` |
| `State` | select | `Draft` · `Waiting predecessor/spec` · `Ready` · `Doing` · `Awaiting Claude` · `Blocked` · `Awaiting live` · `Done` · `Manual backlog` · `Archived` |
| `Priority` | select | `P0` … `P3` |
| `Size` · `Spec Path` · `Spec Revision` · `Branch` · `Claimed By` · `Reported Commits` · `Merged As` · `Next Action` · `Owner Role` · `Evidence Level` · `Live State` · `Source Ref` · `Depends On ID` | text | chuỗi; xoá = `null` |
| `Spec Approved` · `Baseline Verified` · `Execution Allowed` · `Pre-reviewed` · `Focus` | checkbox | **`"__YES__"` / `"__NO__"`** (chuỗi, không phải boolean) |
| `Block Reason` | select | `spec-conflict` · `spec-drift` · `two-failed-fixes` · `forbidden-area` · `acceptance-mismatch` · `needs-owner` · `other` |
| `Depends On` · `Project` | relation | mảng URL trang |

Claim (Builder ghi đúng ba cột):
```json
{"page_id": "<id trang task>", "command": "update_properties",
 "properties": {"Claimed By": "opencode/deepseek-v4.1-flash 2026-10-15T21:40:12+07:00", "State": "Doing", "Branch": "agent/zed-T14"}}
```

### 6.4 Schema Runs và payload tạo Run

Cột: `Name` (title) · `Run ID` · `Kind` (`build` · `pre-review` · `research` · `gate-baseline` · `claude-review` ·
`incident`) · `Tool` · `Model` · `Build` · `Tests` · `Gate` · `Mutation` · `Live` · `Commit or Reference` ·
`Evidence Level` · `Outcome` · `Source Ref` — tất cả text; `Task` và `Project` là relation.

```json
{"parent": {"type": "data_source_id", "data_source_id": "1b6ccecf-745a-4f93-8519-d8f09c61be21"},
 "pages": [{"properties": {
   "Name": "T14d build — opencode/deepseek 2026-10-15",
   "Run ID": "R-T14d-20261015-2140", "Kind": "build",
   "Tool": "OpenCode", "Model": "deepseek-v4.1-flash",
   "Build": "NOT RUN", "Tests": "NOT RUN", "Gate": "NOT RUN", "Mutation": "NOT RUN", "Live": "NOT RUN",
   "Commit or Reference": "base main a2954e2; branch agent/zed-T14",
   "Evidence Level": "measured in the repo checkout by the Builder", "Outcome": "in progress",
   "Source Ref": "docs/specs/T14-mouse-gestures-B.md §T14d",
   "Task": ["https://app.notion.com/p/3fa97dfe4af3814bb501e2ab553d81fa"],
   "Project": ["https://app.notion.com/p/3fa97dfe4af381e4b2b9fe4509beccb4"]},
   "content": "## Gate stdout nguyên văn\n(dán sau)\n## Việc-cạnh (spec §5)\n1. …\n## Kết luận\nChưa kiểm: …"}]}
```

Khi xong, `update_properties` trên trang Run (`Build`, `Tests`, `Gate`, `Outcome`, `Commit or Reference` = head SHA)
và `update_content` thay dòng `(dán sau)` bằng output thật trong code block.

## 7. Khi agent không nối được Notion (đường dự phòng — hiện là đường chính cho tới khi Q-NOTION-4 xong)

1. **Claim vẫn phải nằm trong Notion trước khi agent bắt đầu**, nếu không hai agent có thể làm cùng một việc mà không
   ai thấy: chủ dự án (điện thoại) hoặc Claude ghi `Claimed By = "<công-cụ>/manual <giờ>"`, `State = Doing`, `Branch`
   trên trang task **trước khi dán prompt**.
2. Chủ dự án dán vào prompt: `ID`, `Spec Path`, `Spec Revision` (blob), SHA `main` của Run baseline — bản mẫu ở
   `docs/AGENT_TASKS.md` §0.
3. Agent làm y mục 4 bước 5–7 nhưng ghi Run dưới dạng một mục trong `docs/AGENT_WORKLOG.md` (mẫu ở `AGENT_TASKS.md` §3
   bước 7), kết thúc bằng `CHỜ REVIEW (nhánh …)` hoặc `DỪNG (<lý do>)`.
4. Claude khi về **chép** mục đó thành một Run trong Notion (sau khi kiểm xung đột — mục 5) và đổi State. Đường này chậm
   hơn một nhịp và phụ thuộc chủ dự án — nói rõ như vậy, không giả vờ nó tương đương.

## 8. Không có gì tự khởi động

Notion không chạy daemon, không mở phiên agent, không bắn thông báo cho ai. Chuỗi Builder → Reviewer → Claude **phụ
thuộc một người đọc State rồi mở phiên kế và dán đúng prompt vai đó** (mục 10); cái routine này đổi là mỗi vai biết
chính xác view nào để đọc và State nào để ghi, nên người đó không phải nghĩ. Tự động hoá (một tiến trình đọc view
*Review — Awaiting Claude* theo lịch) là Q-NOTION-3 — chưa làm, chưa đo.

## 9. Công cụ nào nối được Notion MCP (đọc từ tài liệu chính thức 2026-10-15; chưa công cụ nào đăng nhập trên máy này)

| Công cụ (bản trên máy) | Cách nối | OAuth tới `mcp.notion.com` | Nguồn | Chưa kiểm |
|:--|:--|:--|:--|:--|
| **OpenCode** — máy này **v2.0.29** (đo `opencode --version` 2026-10-15) ⇒ dùng dạng **v2** | `opencode.json`: **v2** `"mcp": {"servers": {"notion": {"type": "remote", "url": "https://mcp.notion.com/mcp"}}}` (tài liệu v2 ghi rõ "V2 does not place server names directly under mcp"); dạng **v1** `"mcp": {"notion": {…}}` không áp dụng cho bản này | có: phát hiện 401 → tự mở OAuth (Dynamic Client Registration), hoặc `opencode mcp auth notion`; tắt bằng `"oauth": false` + header | opencode.ai/v2/docs/mcp-servers · opencode.ai/docs/mcp-servers | tài liệu không nói rõ MCP có sẵn cho subagent và trong `opencode run` hay không (chỉ suy ra từ cờ `--attach` "tránh cold-boot MCP") |
| **Zed** — máy này 1.24.2 | `settings.json` → `"context_servers": {"notion": {"url": "https://mcp.notion.com/mcp"}}`; hoặc Settings ▸ AI ▸ MCP Servers ▸ Add Remote Server | có: không có header `Authorization` ⇒ Zed tự mở OAuth | zed.dev/docs/ai/mcp | Notion **không** liệt kê Zed trong danh sách client chính thức; cặp Zed-OAuth ↔ Notion chưa ai xác nhận. Extension `mcp-server-notion` trên zed.dev là của bên thứ ba |
| **Antigravity** | `~/.gemini/config/mcp_config.json` (toàn cục) hoặc `.agents/mcp_config.json` (workspace): `{"mcpServers": {"notion": {"serverUrl": "https://mcp.notion.com/mcp"}}}` — phải là `serverUrl`, `url`/`httpUrl` không được nhận; có MCP Store trong app | có: Notion ghi "Antigravity will prompt you to complete the OAuth flow" | antigravity.google/docs/mcp · developers.notion.com/docs/get-started-with-mcp | subagent có kế thừa MCP của phiên chính không, và headless `agy -p` có dùng được MCP không — tài liệu không nói |
| **Codex CLI** — máy này 0.155.0 | `codex mcp add notion --url https://mcp.notion.com/mcp` → `[mcp_servers.notion]` trong `~/.codex/config.toml`; `codex mcp login notion` | có (`--oauth-client-registration auto`) | developers.openai.com/codex/mcp · learn.chatgpt.com/docs/extend/mcp | MCP dùng được trong `codex exec` (tài liệu ghi "MCP tool calls" trong JSONL) — chưa thử với Notion |
| **Cursor** | Notion liệt kê là client chính thức | có | developers.notion.com/docs/get-started-with-mcp | không khảo sát thêm (Cursor không phải công cụ chính ở đây) |
| **Claude Code (desktop)** | connector claude.ai (đã nối) | — | — | (đo) ghi/đọc đều chạy — mục 6.1 |

Sự thật về server (developers.notion.com): endpoint `https://mcp.notion.com/mcp` (Streamable HTTP) và `/sse`; OAuth 2.0
+ PKCE bắt buộc, không có API key cho server host; access token ~8 giờ, refresh token tối đa 180 ngày / 30 ngày không
dùng. Gói open-source `@notionhq/notion-mcp-server` (token `ntn_…`) **không còn được bảo trì** theo chính Notion. CLI
`ntn` (github.com/makenotion/cli) có thật nhưng là công cụ cho Workers + API thô, **không liên quan MCP** — lời đề xuất
ban đầu dùng nó thay MCP là sai.

Lưu ý repo: `.agents/` ở gốc repo là thư mục chưa track của chủ dự án — Antigravity đọc `.agents/mcp_config.json` ở
đó; Claude không tạo hay sửa file nào trong đó.

## 10. Ba prompt để dán

**Builder (OpenCode/DeepSeek, Antigravity, Zed — đã đăng nhập Notion MCP):**
```
Đọc docs/AGENT_QUICKSTART.md, rồi docs/AGENT_NOTION.md mục 2, 4 và 6 (địa chỉ view, schema, payload). Nhận ĐÚNG MỘT
việc theo mục 4: đọc view Blocked và Doing trước (cùng nhánh thì không nhận), rồi view XF · Queue — Ready của hub
XFinder (hoặc việc <ID> nếu tôi ghi ở đây: ___). Ghi Claimed By theo từ vựng mục 2, chờ 10 giây, đọc lại. Làm theo file đặc tả ở ô Spec Path,
đúng bước ghi trong tên việc, theo docs/AGENT_TASKS.md §3. Ghi tiến trình chỉ vào vùng Execution của trang task và Run
của bạn (update_properties từng cột, update_content theo dòng — không replace_content). Gặp điều kiện dừng: State =
Blocked + Block Reason + một câu Next Action, rồi dừng.
```

**Reviewer (công cụ khác Builder):**
```
Đọc docs/AGENT_QUICKSTART.md và docs/AGENT_NOTION.md mục 5–6. Lấy một việc ở view "Review — Awaiting Claude" có
Pre-reviewed trống và token đầu của Claimed By KHÁC công cụ của bạn. Chạy git diff main...<Branch>. Chỉ đọc, không sửa
file, không commit, không đổi State. Ghi phát hiện vào vùng "Review / Acceptance" của trang task bằng update_content
(đủ bước chưa · đổi ngoài đặc tả · vùng cấm · chuỗi không qua L10n.t), tích Pre-reviewed, tạo một Run Kind = pre-review.
```

**Claude khi có quota:**
```
Đọc docs/AGENT_NOTION.md mục 5, rồi view Blocked trước, view "Review — Awaiting Claude" sau. Với từng việc: kiểm nhánh,
chạy lại gate-all ở checkout đúng, so đặc tả, gộp hoặc sửa, ghi Merged As, đổi State, một Run claude-review, xoá
Claimed By khi đặt Ready. Chép mục CHỜ REVIEW trong worklog (nếu có) thành Run sau khi kiểm xung đột. Xong thì viết đặc
tả + Run baseline cho việc kế, tích ba ô, đặt Ready; cập nhật CLAUDE.md.
```

## 11. Đã kiểm / chưa kiểm (2026-10-15)

| Phát biểu | Kết quả |
|:--|:--|
| Schema Tasks mở rộng, State dọn, 5 view tạo, 7 trang T14 đối chiếu với `main a2954e2`, Run baseline ghi | ✅ (đo — đọc lại từng thứ) |
| View Queue — Ready trả đúng T14d qua `mode: view` ngay sau khi SQL bị chặn | ✅ (đo một lần) |
| Gate xanh trên `main a2954e2` (1236 test, 7 cổng 0) | ✅ (đo, Run `R-MAIN-a2954e2-gate`) |
| Một Builder thật nhận việc qua Notion theo mục 4 | ❌ chưa — T-NOTION-1 |
| Hai Builder cùng lúc, đúng một bên giữ claim | ❌ chưa — T-NOTION-2 |
| Reviewer chỉ ghi vùng Review | ❌ chưa — T-NOTION-3 |
| Nhiều lệnh view liên tiếp không chạm hạn mức | ❌ chưa — T-NOTION-4 |
| Công cụ nào trên máy này đã OAuth Notion MCP | không biết — Q-NOTION-4 (Claude không đọc cấu hình công cụ khác) |
| Chuyển 5 database lên trang gốc giữ nguyên id/URL/view; view Queue toàn cục trả T14d sau khi chuyển | ✅ (đo 2026-10-16) |
| View lọc theo dự án tạo trên trang hub truy vấn được bằng `mode: view` | ✅ (đo 2026-10-16, `XF · Queue — Ready` trả T14d) |
| 6 linked-view cũ của trợ lý trước trên hub: filter không đọc được qua API, xoá cần xác nhận của chủ dự án | ❌ còn đó — Q-NOTION-6 |
