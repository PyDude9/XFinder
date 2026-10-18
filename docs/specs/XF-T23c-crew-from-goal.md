# XF-T23c — Crew v2c: From a Goal (seat card), "không hỏi lại" theo crew, Đã gộp theo merge-base, trang Agent AI nói rõ giới hạn

Nối tiếp `docs/specs/XF-T23-crew-v2.md` (v2a + v2b đã ship, commit `4a2c898`). Dành cho **Builder** trên nhánh
`agent/<tool>-XF-T23c`; Claude review. Mọi câu "v2b làm X" dưới đây là đọc từ code ở `4a2c898` (file:line); mọi câu
"Claude Code làm Y" có URL ở §2 — câu nào §2 ghi *chưa xác minh* thì thiết kế **không được dựa vào nó**.

## 0. Câu việc

"Tôi gõ một mục tiêu. **Lead** đọc repo rồi đề xuất ai làm gì; tôi xem **thẻ seat** trên notch và bấm **Mở** — lúc đó mới
có builder, worktree, nhánh. Khi crew chạy, lệnh an toàn lặp lại (`npm test`, `swift test`) tôi chỉ duyệt **một lần cho
crew đó**. Bảng crew chỉ ghi **Đã gộp** khi nhánh thật sự đã nằm trong nhánh chính, không phải khi lead *xin* gộp."

## 1. Hiện trạng v2b (đọc code `4a2c898`)

| Việc | v2b | Vấn đề |
|:--|:--|:--|
| Khởi động | `CrewManager.start` spawn **đủ 5 vai** ngay, tạo worktree + nhánh cho frontend lẫn backend trước khi lead đọc repo (`CrewManager.swift`, `prepareWorktrees`) | Mục tiêu chỉ cần backend vẫn mở 2 worktree + 2 nhánh + 4 tiến trình `claude`; "Bỏ" không có — chỉ Dừng |
| Thẻ duyệt | `NotchAgentsPage.permissionLine`: Từ chối / Cho phép; mỗi lệnh ngoài tập chỉ-đọc của Claude Code là một thẻ | reviewer chạy `npm test` 5 lần = 5 thẻ y hệt nhau |
| Đã gộp | `CrewV2.Gate.requestMerge` ghi `.merged` **lúc lead xin** (`CrewGate.swift`); checklist hiện "Đã gộp ✓" | Nếu bạn **từ chối** thẻ `git merge`, bảng vẫn ghi Đã gộp ✓ (sai sự thật — vi phạm Honesty Rule) và lead xin lại bị REFUSED vì "đã merged" |
| Trang Agent AI | footer dài một đoạn (`AIAgentsDetailView.crewSection`) | không nói Bash vẫn ghi được file ở bất kỳ đâu; không nói judge merge vào nhánh tích hợp cũng hỏi (Q-CREW-6) |

## 2. Sự thật Claude Code quyết định thiết kế (tài liệu chính thức, đọc 2026-10-18)

| Sự thật | Nguồn | Hệ quả cho v2c |
|:--|:--|:--|
| PermissionRequest hook trả `decision.behavior` allow/deny; với allow có thêm `updatedInput` và **`updatedPermissions`** = mảng entry `{type: addRules, rules: [{toolName, ruleContent}], behavior, destination}` với `destination` ∈ `session` (RAM, hết phiên là mất) / `localSettings` / `projectSettings` / `userSettings`; với deny có `message` (nói cho model vì sao) và `interrupt` | code.claude.com/docs/en/hooks, mục PermissionRequest decision control | Cơ chế "nhớ" của Claude Code **có thật** — nhưng theo **phiên** (một thành viên), không theo crew, và không hiện trên bảng ⇒ §3.2 dùng bộ nhớ phía XFinder; `updatedPermissions destination: session` ghi lại là phương án B nếu người dùng muốn nhớ cả sau khi XFinder đóng |
| Thứ tự luật: **deny → ask → allow**, "first match in that order", độ cụ thể không đổi thứ tự; một `ask` khớp vẫn hỏi dù có `allow` cụ thể hơn ở scope khác | code.claude.com/docs/en/permissions, "Settings precedence" | Câu trên trang "hỏi kể cả khi bạn đã cho phép ở nơi khác" **đúng theo tài liệu** (`permissions.ask` của `--settings` thắng `allow` của user settings) |
| `--settings <file>` là scope #2 (sau managed): key có mặt **đè** key cùng tên ở project/user, key vắng giữ giá trị file; `permissions.allow` merge qua các scope; **hooks merge** qua các scope (không thay nhau), hook từ file settings được gắn nhãn `[settings]` | docs/en/settings "Settings precedence", docs/en/cli-reference `--settings`, docs/en/hooks | Guard trong `--settings` của v2b là đường hợp lệ; chỉ `allowManagedHooksOnly` (managed) mới chặn — không áp cho máy cá nhân |
| PreToolUse `permissionDecision: "ask"` **ép hỏi** kể cả khi có allow rule ("Deny and ask rules are still evaluated regardless of what the hook returns"); `permissionDecisionReason` với `ask` hiện cho **người** trong prompt, với `deny` hiện cho **model** | docs/en/hooks "PreToolUse decision control" | Lý do deny của guard ("edits only inside its own worktree") đến đúng chỗ: model đọc được và sửa hành vi |
| `-p` không có host/`--permission-prompt-tool`: PermissionRequest hook vẫn chạy; **không hook nào trả quyết định ⇒ tool call bị từ chối** (không treo); từ chối hiện trong stream là system message `permission_denied`, kết quả cuối có `permission_denials` | docs/en/hooks (PermissionRequest), docs/en/headless | Khi XFinder tắt giữa chừng, hook thoát không in gì ⇒ lệnh bị **từ chối**, member không treo — đúng thiết kế P7a; v2c không cần timeout riêng |
| Không có message stream-json nào báo "đang chờ quyền" trong CLI thuần; `control_request`/`pending_permission_requests` chỉ có ở Agent SDK | docs/en/agent-sdk/typescript | Thẻ trên notch tiếp tục đến từ hook (events file), không từ stream của member |

## 3. Thiết kế

### 3.1 From a Goal — lead đề xuất, bạn Mở

- Picker trên trang Agent AI khi template = Lead Architect: **"Lead đề xuất seat trước"** (mặc định mới, Q-CREW-7) /
  **"Mở đủ 5 vai ngay"** (= v2b). Khoá `crew.fromGoal` (Bool, default `true`, ONE reader `CrewManager`), có hàng
  `FeatureKeyDefaultsTests`.
- Chế độ đề xuất: `start` chỉ spawn **lead**, ở thư mục đã chọn, với brief thêm: *"First, read the repository and propose
  seats: run `xfinder-crew propose --seat <role> --task \"…\" --criteria \"…\"` once per seat (roles: frontend, backend;
  security and reviewer are always seated), then `xfinder-crew propose --done`. Nothing else runs until the person opens
  the seats."* Không worktree, không nhánh nào được tạo ở bước này.
- CLI: `propose --seat <role> --task … --criteria …` (một seat một envelope `kind: propose`, chỉ lead, ký đủ trường) và
  `propose --done`. `CrewV2.Kind` thêm `.propose`; `Envelope` thêm `seatRole` (vào MAC — **thêm trường = thêm vào
  `canonical` VÀ vào `fld` của CLI cùng lúc**, test `testTheShippedCLISignsEveryV2VerbAndTheAppVerifiesIt` phải phủ).
  `validate`: `propose` chỉ từ `.lead`, `seatRole` ∈ builder roles của template, task+criteria bắt buộc; `propose --done`
  là envelope `kind: propose` không `seatRole`.
- `CrewManager.Crew.proposal: [Seat]` (role, task, criteria) + `proposalClosed: Bool`. Khi `--done` tới: board ghi
  `proposed` và notch hiện **seat card** trong `CrewBoardView`: một hàng mỗi seat (role · task một dòng · criteria một
  dòng, `truncationMode(.tail)`), nút **Mở** và **Bỏ**. Chưa bấm = không tốn gì thêm (lead đang chờ tin).
- **Mở**: `CrewManager.openSeats(crewID)` chạy `prepareWorktrees` chỉ cho các builder được đề xuất (+ integration), spawn
  các vai đó, rồi **XFinder tự giao TASK/CRITERIA/BRANCH** cho từng builder dưới tên lead (render như `send --task`, board
  kind `.message`, có trả lời) và báo lead `[crew] Seats opened: frontend (crew/…-frontend), …`. Lead không tốn một lượt
  để gửi lại. **Bỏ**: `stop` crew (lead dừng), không có nhánh/worktree nào để dọn; board ghi `stopped` với note "Bạn bỏ
  đề xuất".
- `xfinder-crew who` trước Mở liệt kê lead + dòng `proposed: frontend (chưa mở)`. Một `send` tới vai chưa mở bị từ chối
  `REFUSED: that seat is not open yet` (Refusal mới `.seatNotOpen`).
- Lead đề xuất **không có** security/reviewer ⇒ XFinder tự thêm (rào §3.5 cần cả hai); đề xuất vai lạ ⇒ REFUSED;
  `--done` không có seat nào ⇒ REFUSED `.emptyProposal`; đề xuất lần hai sau khi đã Mở ⇒ REFUSED.

### 3.2 "Cho phép, không hỏi lại … trong crew này"

- Trên thẻ duyệt của **thành viên crew** (cả `permissionLine` của `AgentRow` và của `CrewBoardView`): nút thứ ba
  **"Không hỏi lại `<prefix>`"** chỉ khi `CrewRemember.prefix(command:)` trả giá trị: lệnh là Bash, **không** phải
  `StateChanging.classify == .stateChanging`, **không** bắt đầu bằng `xfinder-crew` (mỗi tin phải được thấy), và
  `tool_name` không phải Edit/Write/MultiEdit/NotebookEdit. Prefix = hai từ đầu sau khi bỏ `env`/`VAR=` (`npm test`,
  `swift test`, `git diff`, `pytest -q`→`pytest -q`); một từ nếu lệnh một từ (`ls`).
- Bộ nhớ: `Crew.autoAllow: Set<String>` **trong RAM**, chết cùng crew (không persist — Q-CREW-8). Áp ở
  `AgentSessionMonitor.answer` **trước** khi tạo thẻ: PermissionRequest tới cho một session thuộc crew
  (`CrewManager.membership`), `prefix ∈ crew.autoAllow` ⇒ ghi decision allow ngay, board ghi
  `autoAllowed` ("tự cho phép `npm test` cho reviewer") — bạn vẫn **thấy** nó chạy, chỉ không phải bấm. Phần quyết định
  là hàm thuần `CrewRemember.decide(toolName:command:autoAllow:) -> .allow | .ask`, symlink test.
- Không dùng `updatedPermissions` của Claude Code (có thật, §2): nó nhớ theo **phiên** của một thành viên, không theo crew, và không hiện trên bảng; bộ nhớ phía XFinder áp cho mọi thành viên của crew và mất khi crew dừng. Nếu Q-CREW-8 chọn persist, phương án là `addRules` với `destination: localSettings` của **repo thử** — không bao giờ `userSettings`.
- Trang nói rõ: chỉ áp cho prompt của manual mode; tập chỉ-đọc của Claude Code vốn chạy không hỏi; lệnh đổi trạng
  thái **không bao giờ** có nút này.

### 3.3 Đã gộp theo merge-base

- `Gate.BranchState` thêm `.mergeRequested`; `requestMerge` chuyển `.mergeable → .mergeRequested` (vẫn chỉ lead, vẫn chỉ
  từ mergeable). `Checklist.merged` chỉ `true` ở `.merged`; `.mergeRequested` hiện "Đang gộp…" (Mark mới `.pending` +
  cột riêng, hoặc text — Builder chọn, test ghim).
- `Crew.baseBranch` = `git symbolic-ref --short HEAD` của checkout lead lúc start (`CrewGit.currentBranch`; detached HEAD
  ⇒ ghi SHA và **không bao giờ** tới `.merged` tự động — board nói "không xác định được nhánh chính").
- Sau `.mergeRequested`: ở **mỗi** `turnEnded` của lead và một one-shot 30 s, `CrewGit.isAncestor(branch, of: baseBranch,
  in: repo)` (`git merge-base --is-ancestor`, off-main) ⇒ `.merged` + board `merge` "đã gộp vào main". Lead xin merge lại
  khi đang `.mergeRequested` và **chưa** là ancestor ⇒ **cho phép lại** (bạn có thể đã từ chối thẻ) thay vì REFUSED.
  `done` mới sau `.mergeRequested` ⇒ về `awaitingVerdicts` như hiện nay (code đổi thì duyệt lại).

### 3.4 Trang Agent AI — "Giới hạn" nói thẳng

Một `DisclosureGroup`/hàng "Giới hạn" dưới footer, 5 gạch đầu dòng (mỗi câu đúng theo code): (1) lưới prefix, không
phải ranh giới — `git -C . push` bắt được, `bash -c "…"`/alias thì không; (2) rào sửa tệp chỉ áp cho tool Edit/Write/
MultiEdit/NotebookEdit — Bash vẫn ghi được file ở bất kỳ đâu, nhưng manual mode **vẫn hỏi bạn** mọi lệnh ngoài tập
chỉ-đọc; (3) judge gộp vào nhánh tích hợp để chạy test cũng hỏi (Q-CREW-6 giữ); (4) "Đã gộp" đo bằng `merge-base`, chỉ
nhánh chính lúc start; (5) token thành viên là namespacing cùng user, chương trình khác của bạn đọc được.

### 3.5 Không làm trong v2c

Seat Gemini/Pi/Hermes/Cursor; model/effort theo seat (chờ `--model` per member có test); persist autoAllow; vai tuỳ ý
ngoài frontend/backend; SendMessage giữa phiên; Agent Teams.

## 4. Ca hỏng phải có câu trả lời

| Ca | Trả lời |
|:--|:--|
| Lead không bao giờ `propose --done` (hết lượt, quên) | sau 2 lượt lead kết thúc mà chưa `--done`: board nhắc, thẻ "Nhắc lead đề xuất" gửi lại brief; không tự Mở |
| Lead đề xuất rồi crew bị Dừng trước Mở | không có nhánh/worktree — `stop` v2b bỏ qua bước git khi `worktrees` rỗng |
| Mở thất bại ở `prepareWorktrees` (repo đổi, nhánh bị chiếm) | crew **vẫn sống** với lead; board ghi lỗi git; nút Mở hiện lại; không tiến trình builder nào được spawn khi git fail |
| Bấm Mở hai lần nhanh | `openSeats` idempotent: guard `proposalOpened` trên main actor trước mọi `await` |
| Đề xuất thiếu judge | tự thêm security + reviewer, board nói rõ |
| `autoAllow` chứa prefix mà lệnh sau đó là `npm test && git push` | `classify` chạy trên **cả dòng** trước prefix ⇒ `.stateChanging` ⇒ hỏi; test ghim |
| `npm test` của builder A được nhớ, builder B chạy `npm test` | áp cho **mọi** thành viên crew đó (nhãn nút nói "trong crew này") — test ghim |
| Người từ chối thẻ `git merge` của lead | `.mergeRequested` không đổi; 30 s sau vẫn không ancestor ⇒ board "chưa gộp"; lead xin lại được |
| Lead gộp bằng tay vào nhánh khác (không phải baseBranch) | không bao giờ `.merged`; board nói nhánh chính là X |
| Detached HEAD ở checkout lead | baseBranch = nil ⇒ không `.merged` tự động, trang/board nói vậy |
| Hai builder cùng seat role trong một đề xuất | REFUSED `.duplicateSeat` |
| Envelope `propose` giả từ builder | `validate`: chỉ `.lead` — như `merge` |

## 5. Nghiệm thu

- Thuần: `CrewRemember` (prefix, decide — mutation: state-changing được nhớ ⇒ đỏ); `Gate` thêm `mergeRequested` (walk
  cũ phải vẫn xanh: không đường nào tới `.merged` không qua `.mergeRequested` + ancestor); `propose` validate; checklist
  với `mergeRequested`.
- e2e `scripts/e2e-crew-v2.sh` mở rộng (fake claude): lead propose 1 builder → seat card (model) → `openSeats` → đúng 1
  worktree; builder chạy `npm test` 2 lần — lần 2 không thẻ (board `autoAllowed`); `git merge` thật trong repo thử ⇒
  `.merged` chỉ sau khi ancestor; Bỏ ⇒ 0 nhánh `crew/*`.
- Gate thường (`gate-all`, L10n 6 gate, mutation agents harness với target trong `FILES`, `DRY=1` trước khi chạy).
- Live: T-CREW-1 (model thật) — chỉ khi chủ dự án gật.

## 6. Giai đoạn / phân công

Builder (một nhánh `agent/<tool>-XF-T23c`, commit theo bước): (1) `mergeRequested` + merge-base (nhỏ, tách được);
(2) `CrewRemember` + nút trên thẻ; (3) propose/seat card/Mở; (4) trang Giới hạn + L10n (add-only script
`scripts/add-crew-v2c-l10n-entries.py`). Claude: §2 facts, review từng bước, Notion.

**File Builder được sửa**: `Core/Agents/CrewGate.swift`, `CrewRules.swift`, `CrewManager.swift`, `CrewGit.swift`,
`Resources/Agents/xfinder-crew.zsh`, `Views/NotchAgentsPage.swift`, `Views/Detail/AIAgentsDetailView.swift`,
`Tests/XFinderLogicTests/Crew*.swift`, `scripts/e2e-crew-v2/*`, `scripts/mutation-check-agents.sh` (chỉ **thêm** mutation),
file L10n script mới. **Không sửa**: `xfinder-agent-hook.zsh`, `AgentHookInstaller`, `WindowlessSessionManager`,
`FeatureCatalog` (trừ khi thêm khoá `crew.fromGoal` — khi đó đủ 8 thứ của một tính năng), pbxproj (báo Claude nếu cần
file mới).

## 7. Chờ chủ dự án

Q-CREW-7 mặc định "Lead đề xuất trước" (đề xuất: **có**); Q-CREW-8 persist autoAllow theo repo (đề xuất: **không**).
