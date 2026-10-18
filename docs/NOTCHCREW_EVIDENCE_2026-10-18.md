# Notch Crew 1.8.4 — bằng chứng đo được (2026-10-18) và đối chiếu với Agent AI của XFinder

Nguồn: 7 video chủ dự án đưa (`feature-start/talk/glance/answer/crew/nowindow.mp4`, `notchcrew-film-1.5.mp4`) — rút
khung hình bằng AVFoundation (12–20 khung/video, scratchpad `notchcrew/*.png`); bundle `/Applications/Notch Crew.app`
(`com.tastedev.notchcrew` 1.8.4 build 25): `Resources/changelog.json`, `strings` của binary, tên lớp Swift, `nm -u`,
`THIRD_PARTY_NOTICES.md`, ba script trong `~/Library/Application Support/Notch Crew/bin/`. **Không dịch ngược hàm** —
app closed-source, chỉ đo. `rea`/Hopper không còn trên máy này (2026-10-18), nên không có bước Hopper.

## 1. Notch Crew làm gì (nhìn thấy trong video)

| Video | Thấy gì | Số đo trong khung |
|:--|:--|:--|
| **start** — "New Crew from a Goal" | Menu `+`: *New Empty Crew*, *From Running Sessions*, "New sessions with no windows, from a template": **Pipeline** (lead, plan, build, test, review) · **Expert Review** (lead, build-1, build-2, review-sec, review-perf) · **Competing Drafts** (lead, build-1, build-2, review) · **From a Goal**. Nhập goal "Add share links to notes, with tests." → seat card (Role · Agent · Model · Thinking, "Keep my changes as these roles' settings on this Mac") → lead chạy `crew propose` → "lead proposes these crewmates" với 4 seat **khác agent** (build-1 Gemini, build-2 Codex GPT-5.6-Terra/high, review-sec Antigravity, review Pi/xhigh) + đoạn kế hoạch: *"Builders in parallel… each on its own branch. Once both reply Done, review-sec checks the tokens and review reads both branches; I merge after both approve and npm test passes."* → Don't Open / **Open These** → board 5 thành viên, mỗi builder có nhánh `crew/notes-build-1`, `crew/notes-build-2` | lead 12 % · 41k · sonnet 5.5 |
| **crew** — crew chạy | Roles **lead / frontend / backend / security / reviewer**; builders trên `crew/notes-frontend`, `crew/notes-backend`, `crew/notes-security`; reviewer "Waiting for a branch to review". Người gửi "To: lead ▾": *"Add share links to notes. Split it by role; ask me before touching schema"*. Messages: `9:41 AM lead → frontend UI: a Share button, copy link, a page for expired links · working`, `lead → backend API: share links that expire in 7 days, with tests`, `lead → security Check: token strength, expiry, rate limits`. Lead hỏi lại người: *"schema.js needs a shareToken field (random, expires in 7 days). Approve?"*. Thẻ duyệt lệnh ngay trong board: **`Bash git commit -m "Add share links"` · backend · Codex · Yes / No / Terminal**. Kết: backend "Done: committed 5de0c49", frontend "Done…", security "Done: tokens can't be guessed; added a rate-limit test.", reviewer "**Approve: all three branches pass npm test.**", lead "**Merged API, UI and the checks. npm test: 9 passed.**"; mỗi message có ✓ | — |
| **talk** — nói chuyện với phiên | Feed hội thoại ngay trong notch (không mở terminal): lệnh → trả lời → **diff** (`auth/session.ts` 42/43) → **comment một dòng diff** (`> auth/session.ts:43 … Keep the page they were on in ?next=.`) → **kéo ảnh** vào ô nhắn (`Read login-fixed.png`, xem trước ảnh) → với Codex đang bận: *"Goes in once Codex can take it"* (xếp hàng) | fix-login 10 % · 96k · opus 5.5 · max · Plan; api-tests 72 % · 722k · gpt-6-luna |
| **glance** — nhìn một phát | Header **Needs approval 1 · Working 1 · Idle 4**; mỗi hàng: *nơi chạy › tên · tag · role*, việc đang làm (`Bash: npm test -- auth`, `Shell: npm run test:e2e`, `Shell: ./scripts/deploy.sh staging · 2 shell tasks`), % context · tokens · model. **Usage**: Claude "Current session (5 hours) 13 % used · resets in 1 h 45 min / This week 15 % · resets in 2 days", Codex Free "30 days 3 % · resets in 21 days", Gemini "keeps its quota in memory only: run /stats model", OpenCode "Today: 36k tokens · $0.04. Its limits depend on your provider." | 6 phiên: iTerm, Terminal, cmux, tmux, Ghostty, herdr |
| **answer** — duyệt tại chỗ | Terminal hỏi "Do you want to proceed? 1. Yes 2. Yes, and don't ask again for: npm test * 3. No" → notch hiện **thẻ duyệt trong dòng** của phiên: `Bash npm test -- auth · 12s · [Yes] [Yes, and don't ask again for npm test] [No] [Terminal]` → bấm Yes → terminal in `Bash(npm test -- auth) └ Allowed by PermissionRequest hook · 41 passed, 0 failed` | — |
| **nowindow** | Hàng "new-session · **No window · opened from the notch** · Working · 2 % · 4k"; thẻ công suất: *"Terminal window 26–77 mW · This session 0.1 mW · The notch itself, 20 agents open: under 100 MB, 1–2 % CPU"* | số của họ, chưa đo lại |
| **film** | "Six agents. One is waiting." · "Every agent, one notch." · "Answer where you are." · "Talk to it." · "Even mid-task." · "Make them a crew." · "No window. 0.1 mW." | — |

## 2. Cơ chế (đo từ bundle, không đoán)

- **CLI `crew`** (POSIX sh, 1 727 byte): `who` · `send <role|all> <message>` · `add <role> [claude|codex|gemini|opencode|antigravity|pi|hermes|cursor]` ("a builder gets a worktree of its own") · `propose < proposal` · `models [agent]`. Tất cả `curl --unix-socket ~/Library/Application Support/Notch Crew/notch.sock`.
- **Hook bridge `notch-hook`** (462 byte): `curl -sf --max-time ${2:-5} --unix-socket … -H "X-Agent: $1" -H "X-Wait: …" --data-binary @- http://localhost/hook`; app không chạy ⇒ in rỗng, agent hỏi ở terminal như thường. **Mọi agent dùng cùng một cầu**; Hermes qua plugin `pre_approval_request`.
- **Lớp Swift** (tên, không nội dung): `CrewRelay`, `ApprovalBridge`, `Postbox`, `GitWorktree`, `WorkflowBranch`, `ConversationFeed`, `CommandCatalog`, `InstalledAgents`, `ModelLists`, `OnDemandUsage`, `MemoryWatch`.
- **Chuỗi brief vai**: *"Review for security only: injection (shell, SQL, paths), missing auth or access checks, secrets in code or logs, unsafe deserialization, input not checked where it crosses a trust boundary. For each problem give the file and line and how it would be exploited."* · *"to compare the two branches and pick one, with reasons; merge only the pick"* (Competing Drafts) · *"count a problem as real only when its reviewer names the file and line… merge only after both reviewers approve"* (Expert Review) · *"%@ work in the same folder: their edits can collide. Builders the crew opens (a template, Add Builder) get worktrees of their own."* · `.notchcrew/roles` (cài đặt vai theo repo) · Gemini `--approval-mode auto_edit`.
- **Changelog** (trích): 1.6.0 templates là "team patterns" + *Start a crew from a goal* · 1.7.0 *builders' worktrees are trusted as their repository is*, comment dòng diff, Recent có tìm kiếm, attachments, alerts · 1.8.0 Cursor CLI = agent thứ 9, lưu crew thành template, sửa seat trước khi mở, đọc iTerm2/Terminal · 1.8.1 notch mở **62–71 MB** (trước 156–163), folded **1.10–1.18 % một core** · 1.8.3 "Failures you used to miss show now".
- Thư viện: DynamicNotchKit, Sparkle, RevenueCat (StoreKit). Không `forkpty`/`openpty` trong import (windowless = pipe, như đã đo ở P7a).

## 3. XFinder hôm nay (Agent AI) so với từng mục — và với prompt "Lead Architect" của chủ dự án

| Mục | Notch Crew | XFinder (đã ship) | Thiếu |
|:--|:--|:--|:--|
| Thấy mọi phiên một chỗ + đang làm gì + context % | có, 9 agent | có cho Claude/Codex (hook), OpenCode (API), windowless; hàng nói *đang chạy Bash/đợi bạn/chờ duyệt* | Gemini/Pi/Hermes/Cursor; % context/tokens trên hàng (P2 có usage toàn cục, không per-session) |
| Duyệt lệnh tại notch | thẻ trong dòng, có "don't ask again for X" | Cho phép / Từ chối (N3, P5a, P11) | nút "không hỏi lại cho `npm test`" (= `updatedPermissions`, xem tài liệu Claude Code) |
| Nói chuyện với phiên trong notch | feed hội thoại, diff, comment dòng, ảnh, xếp hàng khi bận | Nhắn phiên (P6, một dòng, xếp hàng khi bận), conversation view **chỉ** cho windowless (P7a) | feed cho phiên terminal; diff + comment dòng; ảnh |
| Không cửa sổ | có | có (Claude P7a, Codex P11) | — |
| Crew từ **goal**, lead đề xuất seat, người duyệt rồi mới mở | có | **không** — 2 template cố định, Claude-only, mở ngay | toàn bộ luồng *propose → seat card → Open These* |
| **Mỗi builder một git worktree / nhánh** `crew/<crew>-<role>` | có (1.7.0) | **không** — mọi thành viên cùng cwd (đúng cái họ cảnh báo "edits can collide") | `git worktree add` + nhánh, trust, dọn khi crew kết thúc |
| Vai Frontend/Backend/Security/Reviewer, brief vai | có (`.notchcrew/roles`, brief security nguyên văn ở trên) | builder / reviewer / critic, read-only qua `--disallowedTools` | vai theo miền + brief, cấu hình theo repo |
| Schema tin nhắn `[TIME] [FROM] -> [TO] TASK | CRITERIA | BRANCH` | hiển thị `9:41 AM lead → frontend …`; nội dung tự do | relay ký HMAC, nội dung tự do (P7b) | schema bắt buộc + validator ở relay |
| Rào phê duyệt: Security **và** Reviewer "Approved" ⇒ lead merge | là **văn bản brief** cho lead ("merge only after both reviewers approve"), lead tự làm bằng git | brief tương tự (pipeline/expert review), không trạng thái Approved | trạng thái `Approved` đọc được từ message, lead chỉ được merge khi relay thấy đủ hai |
| Lệnh đổi trạng thái (commit/push/npm install/deploy) phải qua hook duyệt | `manual mode` của mỗi agent + hook bridge | mọi thành viên `--permission-mode manual` ⇒ mọi lệnh không allowlist hỏi ⇒ notch (P7b) | ép **luôn hỏi** cho prefix nguy hiểm kể cả khi người dùng có allow rule (PreToolUse `permissionDecision: ask`) |
| Tiết kiệm | 62–71 MB mở, 1.1 % folded (số của họ) | 26.7 MB footprint, 0 % idle (đo G) | — |

Kết luận trung thực: XFinder có **hạ tầng** (hook, windowless, relay ký, notch) nhưng **chưa có bốn thứ** prompt của bạn
đòi: cô lập nhánh/worktree theo thành viên, vai theo miền, schema tin nhắn, và rào Approved→merge có máy kiểm. Notch
Crew có cả bốn (ở mức UI/brief + worktree) và thêm luồng *From a Goal*. Spec XF-T23 (`docs/specs/XF-T23-crew-v2.md`)
đưa đủ bốn vào, theo kiểu đo được, không chép code.
