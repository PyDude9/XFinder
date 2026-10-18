# XF-T23 — Crew v2: Lead Architect, vai theo miền, worktree riêng, schema tin nhắn, rào Approved → merge

Nguồn: prompt "LEAD ARCHITECT & CREW ORCHESTRATOR" của chủ dự án (2026-10-18) + bằng chứng Notch Crew
(`docs/NOTCHCREW_EVIDENCE_2026-10-18.md`) + đối chiếu code XFinder (agent đọc-chỉ-đọc, file:line dưới) + tài liệu Claude
Code (claude-code-guide, URL dưới). Mọi câu "Claude Code làm X" đều có URL; mọi câu "XFinder đang làm Y" đều có file:line.

## 0. Câu việc

"Tôi đưa một mục tiêu. Một **lead** tách nó theo miền (frontend / backend / security / reviewer), mỗi builder làm trên
**nhánh và worktree riêng**, họ nói chuyện với nhau theo **một mẫu tin nhắn cố định**, **Security và Reviewer đều phải
Approved** thì lead mới được merge vào main, và **mọi lệnh đổi trạng thái** (git commit/push/merge, npm install,
deploy.sh) phải qua tôi trên notch trước khi chạy. Tôi theo dõi tất cả trên bảng crew ở notch."

## 1. Hiện trạng đo được (vì sao v1 chưa đủ)

| Nguyên tắc của prompt | XFinder v1 (P7b) | Notch Crew 1.8.4 |
|:--|:--|:--|
| 1 Cô lập nhánh/worktree | **Mọi thành viên cùng một cwd**: `CrewManager.start` truyền một `folder` cho mọi `WindowlessSessionManager.startClaude` (`CrewManager.swift:82,111-114`; `WindowlessSessionManager.swift:241`); không có `git`/`worktree`/`branch` nào trong `Core/Agents` ngoài `AgentHandoff*` (chỉ đọc) | "a builder gets a worktree of its own" (`crew add`), nhánh `crew/<crew>-<role>`, 1.7.0 "builders' worktrees are trusted as their repository is" |
| 2 Schema tin nhắn | JSON ký `{from,to,text,mac}` (`CrewRules.swift:90-123`), `text` tự do, giao cho thành viên là một chuỗi `[crew] Message from X: …` (`:203`) | hiển thị `9:41 AM lead → frontend …`; nội dung tự do |
| 3 Rào phê duyệt | critic/reviewer **read-only** (`--disallowedTools Edit,Write,…`, `CrewRules.swift:48-52`), `BoardEntry.Kind` không có `approved`, không có bước merge (`:152,265-273`) | là **văn bản brief** cho lead ("merge only after both reviewers approve"); reviewer trả "Approve: all three branches pass npm test." |
| 4 Hook duyệt lệnh | **có**: mọi thành viên `--permission-mode manual` ⇒ mọi lệnh ngoài allowlist đọc-chỉ-đọc hỏi ⇒ `PermissionRequest` ⇒ thẻ Cho phép/Từ chối trên notch (`AgentHookInstaller.swift:20,26`; `xfinder-agent-hook.zsh:88-108`). Nhưng không ép **luôn hỏi** cho prefix nguy hiểm khi người dùng có allow rule | cùng cơ chế (`notch-hook` → socket), thẻ có "Yes, and don't ask again for npm test" |
| Vai | builder / reviewer / critic-correctness / critic-safety (2 template, Claude-only) | lead · frontend · backend · security · reviewer; seat = agent + model + thinking; `.notchcrew/roles` theo repo |

## 2. Sự thật Claude Code quyết định thiết kế (URL)

- **Worktree ngoài**: cách được tài liệu hoá là `git worktree add ../x -b <branch>` rồi chạy `claude` với cwd ở đó
  (`worktrees.md#manage-worktrees-manually`). `--worktree/-w` là cơ chế **Claude tự tạo** (`.claude/worktrees/<name>`,
  nhánh `worktree-<name>`) và chỉ cơ chế đó mới được Claude Code **chặn** edit ra ngoài checkout
  (`worktrees.md#how-claude-code-enforces-isolation`). ⇒ Với worktree do XFinder tạo, **XFinder phải tự chặn** (mục 3.4).
  `--add-dir` chỉ mở quyền đọc/ghi thêm thư mục, không đổi cwd (`cli-reference.md`).
- **Hook**: `matcher` chỉ lọc theo **tên tool** (`"Bash"`); nội dung lệnh đọc trong script từ stdin `tool_input.command`
  hoặc qua trường `if: "Bash(git *)"` (best-effort). PreToolUse trả
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"|"deny"|"allow","permissionDecisionReason":…}}`;
  PermissionRequest trả `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"|"deny"}}}`,
  exit 2 **không** có tác dụng với PermissionRequest. Hook chạy y hệt trong `-p`. Chế độ Manual đến hook dưới tên
  `permission_mode: "default"` (`hooks.md`).
- **Luật quyền**: `Bash(git push *)` ≡ `Bash(git push:*)`; deny chặn `git push origin main` nhưng **không** chặn
  `git -C . push …` hay `git 'push' …` — "không phải ranh giới bảo mật" (`permissions.md#bash-rule-limits`). Manual mode
  hỏi mọi lệnh ngoài tập đọc-chỉ-đọc cố định (ls, cat, grep, find, git read-only…), không cấu hình được.
- **System prompt chỉ lúc khởi động**: `--append-system-prompt`, `--append-system-prompt-file` có; không đổi được giữa
  phiên qua stream-json (`cli-reference.md#system-prompt-flags`).
- **Subagent trong `-p`**: `--agents '{"reviewer":{"tools":["Read","Grep","Glob"],…}}'` và `.claude/agents/*.md` chạy được
  (`sub-agents.md`, `cli-reference.md`).
- **Nhắn giữa hai phiên Claude Code**: `SendMessage`/`ListAgents` có trong `-p` (không `--bare`), cần
  `crossSessionInbound: "accept"` qua `--settings` cho phiên không giao diện (`cross-session-messaging.md`). **Agent Teams
  không chạy trong `-p`** (`agent-teams.md`). ⇒ Relay của XFinder vẫn là kênh chính (ký, có bảng, có rào); SendMessage là
  tuỳ chọn sau.

## 3. Thiết kế

### 3.1 Vai và seat

`CrewRules.Role` thành dữ liệu: `name` (một từ thường, chữ/số/-, ≤ 20 — như Notch Crew), `domain` (frontend | backend |
security | reviewer | lead | custom), `editsCode: Bool`, `brief` (append-system-prompt), `agent` (claude | codex), `model`,
`effort`. Template v2 "**Lead Architect**": lead (Claude) · frontend · backend · security (read-only) · reviewer
(read-only + chạy test). Security brief viết **bằng lời của XFinder**, cùng nội dung chuẩn ngành (injection shell/SQL/path,
auth thiếu, bí mật trong code/log, deserialization, kiểm tra đầu vào ở ranh giới tin cậy, entropy token, SameSite/cookie
flags) — không chép câu của Notch Crew.

**From a Goal**: lead khởi động trước, một mình, với brief "đề xuất seat"; nó chạy `xfinder-crew propose < json`
(`{"goal":…, "seats":[{"role":"frontend","agent":"claude","task":…}, …]}`); XFinder hiện **seat card** trên notch (vai ·
agent · model · việc), người bấm **Mở** mới spawn. Không bấm ⇒ không có gì chạy, không tốn token.

### 3.2 Git isolation (nguyên tắc 1)

`CrewManager.start`: với mỗi vai `editsCode`, chạy `git -C <repo> worktree add "<crewDir>/wt/<role>" -b
"crew/<goal-slug>-<role>" <base>` (base = HEAD của checkout chính; nếu nhánh đã tồn tại ⇒ hậu tố `-2`); cwd của member =
worktree đó. Vai read-only (security, reviewer) được một worktree **integration**: `wt/integration` nhánh
`crew/<goal-slug>-integration` từ base — nơi reviewer merge-preview và chạy test tích hợp. Lead chạy ở checkout chính
(chỉ nó được merge). `stop()` ⇒ `git worktree remove --force` mọi `wt/*`, **giữ nhánh** (không xoá việc); thư mục crew
0700 như v1.

**Hai agent không sửa cùng file**: mỗi builder một worktree ⇒ xung đột chỉ xuất hiện lúc merge vào integration, và reviewer
báo lại lead bằng tin `conflict` (3.3). Thêm **chặn cứng**: PreToolUse (3.4) từ chối `Edit/Write/MultiEdit/NotebookEdit`
có `tool_input.file_path` nằm **ngoài** worktree của member (XFinder ghi đường worktree vào env `XFINDER_CREW_ROOT` của
process) — vì Claude Code không chặn cho worktree ngoài (mục 2).

### 3.3 Schema tin nhắn (nguyên tắc 2)

Phong bì JSON ký **giữ nguyên** (v1: SHA-256(file ⏎ to ⏎ text ⏎ token), token không vào thư mục chung) và thêm trường:
`kind` ∈ {task, status, done, question, verdict, conflict}, `task`, `criteria`, `branch`, `verdict` ∈ {approved, rejected}.
**Mọi trường đi vào MAC** (gap analysis: `branch` không ký = giả mạo được). CLI:

```
xfinder-crew send <role|all> --task "<việc>" --criteria "<nghiệm thu>" [--branch crew/x-frontend] [<ghi chú>]
xfinder-crew done --branch crew/x-frontend --tests "npm test: 12 passed" [<ghi chú>]
xfinder-crew verdict approved|rejected --branch crew/x-frontend --note "<file:line + vì sao>"
xfinder-crew conflict --branch crew/x-backend --note "<file>"
xfinder-crew merge --branch crew/x-frontend          # chỉ lead; XFinder từ chối nếu chưa mergeable (3.5)
```

Relay **từ chối** (in usage, không giao) một `send` từ lead tới builder thiếu `--task`/`--criteria`; `verdict` chỉ được chấp
nhận từ vai read-only (security/reviewer) và chỉ `rejected` phải có `--note` chứa `file:line`. Chuỗi **giao cho người nhận**
và **hiện trên bảng** đúng mẫu của chủ dự án:

```
[2026-10-18T14:41:02+07:00] [FROM: lead] -> [TO: frontend]
TASK: Share button, copy link, trang link hết hạn | CRITERIA: npm test xanh, không đụng schema | BRANCH: crew/notes-frontend
```

`send` vẫn **trả về ngay** (Bash tool của Claude Code timeout 2 phút — `xfinder-crew.zsh:4-6`).

### 3.4 Hook quyền (nguyên tắc 4)

`xfinder-agent-hook.zsh` nhận thêm `PreToolUse` cho `Bash` (`matcher: "Bash"`): phân loại `tool_input.command` bằng luật
thuần `CrewRules.StateChanging.classify` (tách theo `&&`, `||`, `;`, `|`, `$(`): prefix {git commit, git push, git merge,
git rebase, git reset --hard, git checkout -- / restore, npm|pnpm|yarn|bun install|add|publish, brew install, pip install,
deploy, rm -rf, sudo, launchctl, defaults write, chmod/chown ngoài worktree} ⇒ trả `permissionDecision: "ask"` (kể cả khi
người dùng có allow rule) ⇒ Claude Code hỏi ⇒ `PermissionRequest` ⇒ thẻ trên notch với **lệnh nguyên văn, vai, nhánh**.
Lệnh khác ⇒ không trả gì (giữ hành vi thường). `Edit/Write/…` ngoài `XFINDER_CREW_ROOT` ⇒ `deny` kèm lý do. Thẻ notch có
nút **"Cho phép và không hỏi lại `npm test` trong crew này"** = XFinder nhớ prefix theo crew và tự `allow` ở PermissionRequest
lần sau — là **bộ nhớ phía XFinder**, không phải `updatedPermissions` của Claude (chưa xác minh trường đó — ghi là chưa đo).

Giới hạn nói thẳng trên trang: luật prefix "không phải ranh giới bảo mật" (`git -C . push` lách được) — nó là lưới an toàn
cho lệnh Claude thường sinh; ranh giới thật là manual mode + worktree riêng + token ký.

### 3.5 Rào Approved → merge (nguyên tắc 3) — máy trạng thái thuần

`CrewRules.Gate` (symlink test): mỗi nhánh builder đi `building → done(tests) → awaitingVerdicts → mergeable | rejected`;
`mergeable` **chỉ khi** có `verdict approved` từ **cả** `security` **và** `reviewer` cho đúng `branch` đó, sau `done`; một
`rejected` ⇒ về `building` (ghi note cho builder); `done` mới sau đó **huỷ** verdict cũ (code đổi thì duyệt lại). Reviewer
chạy test tích hợp trong `wt/integration` (`git merge --no-ff crew/x-frontend` → `npm test`/`npm run test:e2e`; lệnh merge
ở đó cũng qua hook 3.4). `xfinder-crew merge --branch X` của lead: relay kiểm `Gate.state(X) == .mergeable` mới trả về
"OK, merge đi"; lead chạy `git merge` ở checkout chính ⇒ hook ⇒ **thẻ "Merge crew/x-frontend → main" trên notch** — người
bấm Cho phép mới merge. Bảng crew hiện checklist mỗi nhánh: Done · Security ✓/✗ · Reviewer ✓/✗ · Merged.

### 3.6 Cái không làm trong v2

Seat Gemini/Pi/Hermes/Cursor (chỉ Claude + Codex windowless đã có); feed hội thoại + comment dòng diff + kéo ảnh (Notch Crew
"talk") — việc riêng; Agent Teams (không chạy `-p`); SendMessage giữa phiên (tuỳ chọn sau khi relay v2 chạy).

## 4. Ca hỏng phải có câu trả lời

| Ca | Trả lời |
|:--|:--|
| `git worktree add` thất bại (repo không phải git, nhánh đã có, tên bẩn) | crew không mở, thẻ lỗi nói lý do; nhánh có sẵn ⇒ hậu tố `-2`; slug chỉ `[a-z0-9-]` |
| Builder sửa file ngoài worktree của nó | PreToolUse `deny` theo `XFINDER_CREW_ROOT`; ghi board `blocked` |
| Hai builder đụng nhau | chỉ lộ ở merge vào integration ⇒ `conflict` ⇒ lead quyết, hỏi người nếu cần |
| Builder giả `verdict approved` | token theo vai, verdict chỉ nhận từ vai read-only; MAC phủ mọi trường |
| Lead merge khi chưa đủ Approved | relay từ chối `merge`; và `git merge` vẫn qua hook ⇒ người thấy thẻ, từ chối được |
| `done` rồi code đổi tiếp | `done` mới huỷ verdict cũ ⇒ duyệt lại |
| Người từ chối thẻ merge | lead nhận "denied", ghi board, không retry tự động |
| Crew dừng giữa chừng | `worktree remove --force`, **nhánh giữ**, thư mục crew xoá; bảng ghi "dừng, nhánh còn: …" |
| Lệnh lách prefix (`git -C . push`) | nói rõ trên trang: lưới an toàn, không phải ranh giới; manual mode vẫn hỏi lệnh không allowlist |
| `send` chờ trả lời | **không bao giờ** — trả về ngay (Bash tool 2 phút) |
| Hook của Codex | cùng shape; trust theo vị trí mảng (P5a) — hook mới chèn **cuối** |
| Người đang gõ ở terminal khác | thẻ notch không chiếm phím; Return không tự duyệt |
| Member `-p` không nhận SendMessage | không dùng SendMessage trong v2 |

## 5. Nghiệm thu

- Thuần: `CrewRulesTests` cho Envelope v2 (MAC phủ mọi trường, mutation "branch ngoài MAC" đỏ), `Gate` (walk toàn bộ chuỗi
  ≤ 6 sự kiện: không đường nào tới `mergeable` thiếu một trong hai verdict; `done` mới huỷ verdict), `StateChanging.classify`
  (bảng lệnh + lệnh ghép `a && git push`), render schema đúng mẫu.
- e2e với `claude` giả (như P7b 15/15): worktree per builder tạo đúng nhánh; edit ngoài worktree bị deny; `send` thiếu
  `--task` bị từ chối; `verdict` từ builder bị bỏ; `merge` trước Approved bị từ chối; sau 2 Approved thẻ merge hiện; stop
  gỡ worktree giữ nhánh.
- Live: một crew thật trên repo thử (không phải XFinder) với **một** lượt model mỗi member, chỉ khi chủ dự án gật
  (Q-P7b-MODEL còn treo).

## 6. Giai đoạn

1. **v2a (thuần, Claude làm ngay 2026-10-18)**: Envelope v2 + MAC, `Gate`, `StateChanging.classify`, render schema; test
   + mutation. Không đổi hành vi app.
2. **v2b**: `xfinder-crew.zsh` lệnh mới + relay kiểm; hook PreToolUse (ask/deny); worktree per builder trong
   `CrewManager.start/stop`; template Lead Architect; board checklist.
3. **v2c**: From a Goal (propose → seat card → Mở); "không hỏi lại" theo crew; trang Agent AI nói rõ giới hạn.

## 7. v2b — đã dựng (2026-10-18), và chỗ lệch spec

Đo bằng `scripts/e2e-crew-v2.sh` (33 kiểm tra, git thật + `claude` giả cho từng vai, `CrewManager`/`CrewRules`/`CrewGate`/`CrewGit`
và `xfinder-crew.zsh` thật) và `Tests/…/CrewV2bTests.swift` + `CrewGateTests.swift`. **Chưa chạy model thật** (T-CREW-1).

| Mục §3 | Đã làm | Lệch spec |
|:--|:--|:--|
| 3.1 vai | template **Lead Architect**: lead · frontend · backend · security · reviewer (`CrewRules.Template.leadArchitect`, `Role.domain`) | `agent`/`model`/`effort` theo vai và seat card (From a Goal) **chưa** — v2c |
| 3.2 git | `CrewGit` (hooks của repo tắt, `currentDirectoryURL` thay `-C`, stdout/stderr ra file); mỗi builder `wt/<role>` nhánh `crew/<slug>-<role>`, judge chung `wt/integration`, lead ở thư mục đã chọn; cả họ nhánh nhảy sang `-2` nếu một tên bị chiếm; crew bắt đầu trong thư mục con của repo thì member chạy ở thư mục con tương ứng trong worktree; `XFINDER_CREW_ROOT` / `XFINDER_CREW_BRANCH` trong env | **Dừng không `--force`**: worktree có file chưa commit được `worktree move` sang `Application Support/XFinder/Agents/crew-kept/<crew>-<role>`; sạch thì remove; nhánh luôn giữ. Spec ghi `remove --force`, sẽ xoá mất việc chưa commit |
| 3.3 schema | CLI mới `send --task --criteria [--branch]`, `status`, `done`, `verdict`, `conflict`, `merge`; chữ ký phủ **mọi** trường; relay từ chối (và báo lại người gửi bằng `[crew] REFUSED: …`) khi thiếu TASK/CRITERIA, verdict từ builder, branch không phải của mình, rejection thiếu `file:line`; lead→builder chỉ nhận `--task` | `question` = `send` thường (có trả lời); thêm động từ `status` (không trả lời) |
| 3.4 hook | `XFinder --crew-guard` (một cài đặt duy nhất, `CrewGuard.decide`, đo **15 ms/lần**) nằm trong `--settings` của từng thành viên: PreToolUse cho `Bash\|Edit\|Write\|MultiEdit\|NotebookEdit` ⇒ `ask` cho lệnh đổi trạng thái (kể cả `git -C . push`), `deny` cho sửa ngoài worktree (kể cả đường vòng symlink — `realpath` của tổ tiên tồn tại sâu nhất); cộng `permissions.ask` | Không sửa `xfinder-agent-hook.zsh` toàn cục: guard chạy cả khi bạn chưa cài hook Agent AI. Thẻ duyệt trên notch vẫn cần hook đó (đã nói trên trang). Nút "không hỏi lại" **chưa** (Q-CREW-3 → v2c) |
| 3.5 rào | `Gate` nối vào relay: `done` ⇒ XFinder **tự** gửi JUDGE REQUEST cho security và reviewer; hai Approved sau `done` cuối ⇒ báo lead "mergeable"; `merge` chỉ từ lead, từ chối nếu chưa; bảng checklist Xong · Bảo mật · Người duyệt · Đã gộp theo từng nhánh | Judge được nhờ **tự động** (spec để lead nhờ) — mạnh hơn nguyên tắc "cả hai phải Approved", đổi lại mỗi `done` tốn 2 lượt model. `merged` được ghi lúc lead **xin** merge (Gate.requestMerge), không phải lúc `git merge` xong; nếu bạn từ chối thẻ, lead không xin lại được (bị từ chối vì đã `merged`) — an toàn, hơi vụng. Sửa ở v2c bằng `merge-base --is-ancestor` |
| trần chặng tin | `Template.relayCap` = **60** (+30 mỗi lần Resume) cho Lead Architect; v1 vẫn 20 | e2e đo: một vòng task→done→judge→verdict→merge với 2 builder + 2 judge, **không** retry/câu hỏi, đã tốn 20 (21 sau khi thêm `status`) — trần 20 sẽ dừng crew giữa lúc merge |

Hai lỗi thật tìm ra **nhờ e2e**, không phải nhờ test thuần: (1) CLI in `parameter not set` ra stderr khi một trường rỗng (`$(esc $x)` không
ngoặc ⇒ 0 đối số dưới `setopt no_unset`) — đầu ra vẫn đúng nên unit test không thấy; nay mọi chỗ gọi đều có ngoặc và test khẳng định stderr rỗng;
(2) `resolvingSymlinksInPath` của Foundation đổi `/private/var` về `/var` (ngược với `git rev-parse`), nên thư mục con tính sai khi thư mục crew nằm
dưới symlink — thay bằng POSIX `realpath` (`CrewGit.realPath`).
