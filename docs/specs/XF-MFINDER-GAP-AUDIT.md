# XF-MFINDER-GAP-AUDIT — check every item of the owner's MFinder spec against main, then build Settings first

Owner (2026-11-07): "Gửi toàn bộ đặc tả để Minion kiểm tra lại cái chưa làm. Báo changelog rõ ràng. Settings không có gì thay đổi."
Builder: GPT-Minion (Codex). Rules: `BUILDER.md` (commit on your `agent/codex-<ID>` branch only; no push, merge or install).

## 0. Why this task exists (measured on main `e55da25`)

- The owner gave you **two Markdown spec files** (MFinder feature prompts + the OneNotch-derived 28-group product spec). Neither
  original is in the repo. Only your derived summaries are: `docs/MFINDER_XFINDER_ROADMAP.md` (12 capability rows) and
  `docs/MFINDER_XFINDER_NOTCH_COVERAGE.md` (28 groups). A summary cannot show which concrete requirement is still missing.
- Everything shipped from the MFinder work so far (`11c0e31..e55da25`):

  | ID | What changed for the user | Commits |
  |:--|:--|:--|
  | XF-T35 | Hệ thống ▸ tab Ổ đĩa ▸ "Phân tích thư mục": scan one chosen folder, cancel, logical bytes, top 50 files | `1c92dc5` + Boss `768dc83` `ef669cb` `74fb3c7` `8cbfc2f` |
  | XF-T36 | Notch ▸ choose which page opens on click (fixed / last used / current activity) | `3ea38e4` + Boss `0709dc9` |
  | XF-T36B | Notch ▸ visibility over fullscreen apps (always / hide in fullscreen / hide while media plays) | `7d79dfa` + Boss `9e31196` `022ee0d` |

  UI files touched: only `StorageDetailView.swift` and `NotchInterfaceDetailView.swift`. **No Settings structure changed** —
  that is exactly what the owner noticed. Group 28 ("Settings, automation, permissions") is still "Partial".
- Untracked draft in worktree `xf-settings-voice`: `docs/specs/XF-SETTINGS-VOICE-PERMISSIONS.md` (Settings landing page + voice
  permission fix). Not committed, not reviewed.

## 1. Deliverables, in order (one commit each)

1. **Originals — done by Boss.** The owner re-sent them: `docs/reference/MFINDER_PROMPT_SYSTEM.md` (12 features + global
   privacy rules; byte-identical copy of `~/Documents/Craft Anything/mfinder/app/PROMPT_SYSTEM.md`) and
   `docs/reference/MFINDER_PROMPT_TEACHING.md` (8 teaching topics — engineering background, not requirements). The spec has **no
   separate Settings chapter**: "Settings" = the per-feature options and keys it names (`storage.chartStyle`, `storage.chartFraction`,
   `settings.aiSearch.*`, `settings.dropTray.shake*`, archive `newFolderNextToArchive`/`sameFolder`, sync schedule/conflict policy,
   capture format/shortcuts, snap custom zones, clean-mode timer…). Audit every one of them.
   Items that contradict measured XFinder rules (e.g. `CGWindowListCreateImage` is unavailable on 27, "Full Disk Access
   entitlement", bundled `7zz`, cloud upload, ⌘⇧3/4 interception) are **Rejected** or **Partial** with the measured reason — never
   copied blindly.
2. **Gap table** `docs/MFINDER_GAP_AUDIT_2026-11-07.md`: one row per requirement (every heading / bullet that states a behavior or a
   setting), columns `Spec ref (file § line)` · `Requirement (short)` · `Status` · `Evidence` · `Next task ID`.
   Status values only: **Done** (file:line on `main` + commit) · **Partial** (what exists, what is missing) · **Missing** ·
   **Rejected** (reason: no public API measured / data-loss risk / owner decision — cite it). "Code exists" without a reachable UI
   path is Partial, not Done.
   - **Settings section first and complete**: every settings group/row/control in the spec vs the XFinder page that owns it today
     (`SidebarDestination.groups`, `Views/Detail/*`). Owner's earlier 17 MFinder 2.2.69 settings screenshots are summarised in
     `docs/PENDING_TESTS_AND_DECISIONS.md` (Q-REF-1…6) and `docs/CLAUDE_HISTORY_2026-10-18.md` (grep "MFinder" / "ứng dụng tham chiếu").
3. **Changelog** `docs/MFINDER_CHANGELOG.md`: newest first, per task ID: what the user sees, where to click, commit, status
   (merged / installed / hand-tested). Start from the table in §0 and keep it updated by every later task.
4. **Plan**: add a "Kế hoạch" section to the gap audit — ordered task list, each with ID, job sentence ("Người dùng vào đây để ___"),
   files, risk. **Settings first.** One spec file per task in `docs/specs/` (template: `docs/specs/XF-T35-storage-analyzer-v01.md`).
5. **Then build the first Settings task** on `agent/codex-XF-SETTINGS` (move the `xf-settings-voice` draft there; split the
   voice-permission fix into its own task — one topic one commit). Report with the template in `BUILDER.md`.

## 2. Hard limits

- **Merging or moving pages needs the owner's approval of the exact list first.** A landing page of *links* to existing owner pages
  is allowed; removing/merging a page or moving a control to another page is not — put that list in the plan as a `Q-*` question.
- One key one control; view default == reader default; every string through `L10n.t` (add-only scripts); gate with
  `sh scripts/gate-all.sh` in your worktree and paste the result.
- Do not mark anything Done that you have not opened in the source on `main`. Do not claim live behavior — the owner tests by hand.
