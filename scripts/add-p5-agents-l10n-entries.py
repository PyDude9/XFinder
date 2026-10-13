#!/usr/bin/env python3
"""P5 (2026-10-14) — coding agents beyond Claude Code: Codex through the same hook (P5a), OpenCode through its own CLI
(P5b), notifications and recent sessions (P5c), and the Cursor explainer.

Idempotent, ADD-ONLY (same contract as add-p3-settings-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # P5a — Agent AI page
    "Các phiên Claude Code và Codex đang chạy trong terminal: đang làm gì, chờ bạn nhập hay chờ bạn duyệt quyền — duyệt ngay tại notch.":
        ("Claude Code and Codex sessions running in a terminal: what they are doing, whether they wait for your input or your approval — approve right at the notch.", S),
    "Phiên agent trên notch": ("Agent sessions on the notch", S),
    "Hiện phiên agent ở notch": ("Show agent sessions on the notch", S),
    "Đọc nhật ký do hook của XFinder ghi (Claude Code, Codex): tên sự kiện, công cụ, thư mục, câu lệnh bạn gõ và tóm tắt việc công cụ làm (lệnh, đường dẫn tệp) để hiện trên notch. Không đọc câu trả lời của agent, không gọi mạng. Mặc định tắt.":
        ("Reads the log XFinder's hook writes (Claude Code, Codex): event names, tools, folders, the prompts you type and a summary of what a tool does (command, file path) to show on the notch. Does not read the agent's answers, no network. Off by default.", S),
    "Sự kiện gần nhất: ": ("Last event: ", F),
    "Chưa nhận sự kiện nào trong hai ngày qua.": ("No event received in the last two days.", S),
    "Tệp này còn ": ("This file has ", F),
    " hook duyệt quyền của công cụ khác. Agent chạy tất cả cùng lúc — nếu nút trên notch không có tác dụng ngay, hãy tắt app kia hoặc gỡ hook của nó.":
        (" approval hook(s) from other tools. The agent runs them all at once — if the notch buttons do not take effect right away, quit that app or remove its hook.", F),
    "Cài hook = thêm các mục \"Managed by XFinder\" vào cuối ~/.codex/hooks.json (có bản sao lưu đặt cạnh) và chép cùng script zsh vào Application Support. Codex chỉ chạy một hook sau khi bạn duyệt nó: mở Codex, gõ /hooks và chọn tin cậy các hook của XFinder — XFinder không tự duyệt thay bạn. Codex ghi nhận việc duyệt theo vị trí của hook trong tệp, nên gỡ hook của XFinder có thể khiến Codex hỏi duyệt lại các hook đứng sau nó. Câu trả lời của Codex (last_assistant_message) không được ghi lại.":
        ("Installing adds \"Managed by XFinder\" entries at the end of ~/.codex/hooks.json (a backup is written beside it) and copies the same zsh script into Application Support. Codex runs a hook only after you review it: open Codex, type /hooks and trust XFinder's hooks — XFinder never trusts them for you. Codex records that trust by the hook's position in the file, so removing XFinder's hook can make Codex ask you to review the hooks after it again. Codex's answers (last_assistant_message) are not logged.", S),
    "Trạng thái hook: ": ("Hook status: ", F),
    "Cài hook vào ~/.codex/hooks.json": ("Install the hook into ~/.codex/hooks.json", S),
    "Đã cài hook. Mở Codex, gõ /hooks và chọn tin cậy các hook của XFinder — trước đó Codex bỏ qua chúng.":
        ("Hook installed. Open Codex, type /hooks and trust XFinder's hooks — until then Codex skips them.", S),
    # P5a — Features hub row
    "Phiên Claude Code và Codex đang chạy trong terminal: trạng thái và duyệt quyền tại notch; đọc nhật ký hook cục bộ.":
        ("Claude Code and Codex sessions running in a terminal: status and approvals at the notch; reads a local hook log.", S),
    # P5a — notch Agents page
    "Chưa có phiên agent nào.": ("No agent sessions yet.", S),
}


def main() -> None:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data.get("entries", data)
    added, conflicts = 0, []
    for vi, (en, scope) in ENTRIES.items():
        cur = entries.get(vi)
        if cur is None:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        elif cur.get("en") != en or cur.get("scope") != scope:
            conflicts.append((vi, cur, en, scope))
    if conflicts:
        for vi, cur, en, scope in conflicts:
            print(f"CONFLICT {vi!r}: store has {cur!r}, script wants {{'en': {en!r}, 'scope': {scope!r}}}")
        print("Nothing written."); sys.exit(1)
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Added {added} entries (0 rewritten). Total in store: {len(entries)}")


if __name__ == "__main__":
    main()
