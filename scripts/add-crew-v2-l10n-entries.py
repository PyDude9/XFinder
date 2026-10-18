#!/usr/bin/env python3
"""XF-T23 Crew v2 (2026-10-18). ADD-ONLY: an existing key is never rewritten (CONFLICT and exit 1).
Keys handed to L10n.t through a variable (CrewRules.boardKindKey / Template.titleKey) — CrewRulesTests resolves each of them."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    # board lines read "<from> <kind> <to>: <text>" — the kind words are fragments
    "báo xong": ("reported done to", F),
    "duyệt": ("gave a verdict to", F),
    "gộp nhánh": ("merge notice to", F),
    "Tin bị từ chối — sai mẫu hoặc sai vai.": ("A message was refused: wrong format or wrong role.", S),
    "Lead Architect — lead · frontend · backend · security · reviewer": ("Lead Architect: lead, frontend, backend, security, reviewer", S),
}
# UI + start errors + stop note (v2b). The long footer key is read from the view so it cannot drift from the literal.
_view = (Path(__file__).resolve().parent.parent / "XFinder/Views/Detail/AIAgentsDetailView.swift").read_text(encoding="utf-8")
import re as _re
_m = _re.search(r'L10n\.t\("(Lead Architect: lead ở[^"]*)"\)', _view)
if _m:
    ENTRIES[_m.group(1)] = (
        "Lead Architect: the lead works in the folder you choose; each builder (frontend, backend) works on its own git branch and "
        "worktree (crew/<goal>-<role>); security and reviewer share an integration worktree and cannot edit files. Messages between "
        "roles follow a signed TASK / CRITERIA / BRANCH format. The lead may merge a branch only when security AND reviewer both "
        "approved it after the builder's last done report; the git merge command still shows a card on the notch for you to press. "
        "State-changing commands (git commit/push/merge, installing packages, deleting, sudo…) always ask, even where you allowed them "
        "elsewhere, and editing files outside a member's own worktree is blocked. This is a safety net, not a security boundary: other "
        "programs running as your user are not restricted. The folder must be a git repository with at least one commit; uncommitted "
        "changes in the main folder are not in the builders' worktrees. When the crew stops, the branches are kept; a worktree with "
        "uncommitted changes is moved aside instead of deleted. The approval cards on the notch need the Agent AI hook to be installed.", S)
ENTRIES.update({
    "Mẫu này cần một thư mục là kho git.": ("This template needs a folder that is a git repository.", S),
    "Kho git chưa có commit nào — tạo commit đầu tiên rồi bắt đầu lại.": ("The git repository has no commit yet. Make the first commit, then start again.", S),
    "Không đặt được tên nhánh cho crew.": ("Could not choose branch names for the crew.", S),
    "git không tạo được worktree cho crew.": ("git could not create the crew's worktrees.", S),
    "Nhánh còn lại: ": ("Branches kept: ", F),
    " · Worktree còn thay đổi chưa commit, đã chuyển sang: ": (" · Worktrees with uncommitted changes were moved to: ", F),
    " · Không dọn được: ": (" · Could not clean up: ", F),
    "Xong": ("Done", S),
    "Duyệt bảo mật": ("Security", S),
    "Người duyệt": ("Reviewer", S),
    "Đã gộp": ("Merged", S),
})

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); e = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in e and e[k].get("en") != en]
    for k in bad: print(f"CONFLICT: {k!r} = {e[k].get('en')!r}")
    if bad: return 1
    added = sum(1 for k in ENTRIES if k not in e)
    for k, (en, sc) in ENTRIES.items(): e.setdefault(k, {"en": en, "scope": sc})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}"); return 0
if __name__ == "__main__": sys.exit(main())
