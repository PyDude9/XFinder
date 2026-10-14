#!/usr/bin/env python3
"""P7a (2026-10-14) — "Phiên không cửa sổ": Claude Code sessions XFinder hosts itself (no terminal window), their rows,
the conversation view on the notch and the settings section.

Idempotent, ADD-ONLY (same contract as add-p5-agents-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # WindowlessRules.phaseKeys ("Tới lượt bạn" already exists: "Your turn")
    "Đang chờ tin đầu tiên": ("Waiting for the first message", S),
    "Đang làm": ("Working", S),
    "Đã dừng": ("Stopped", S),
    # WindowlessRules.errorKeys / AgentTalk
    "Không tìm thấy lệnh claude.": ("The claude command was not found.", S),
    "Thư mục không còn.": ("The folder is gone.", S),
    "Không chạy được claude.": ("Could not start claude.", S),
    "Phiên không cửa sổ đã dừng — tin chưa được gửi.": ("The windowless session has stopped — the message was not sent.", S),
    "Gửi tin": ("Send", S),
    "Đã gửi tin.": ("Sent.", S),
    # UI (filled from the UI agents' reports)
    "Phiên mới không cửa sổ": ("New windowless session", S),
    "Mở lại không cửa sổ": ("Reopen windowless", S),
    "Phiên không cửa sổ — XFinder đang chạy nó": ("Windowless session — XFinder is running it", S),
    "Xem hội thoại": ("View conversation", S),
    "Việc đầu tiên cho Claude Code (không bắt buộc)…": ("First task for Claude Code (optional)…", S),
    "Chưa có thư mục nào — chọn thư mục ở trang Agent AI.": ("No folders yet — choose one on the Agent AI page.", S),
    "Chọn thư mục": ("Choose folder", S),
    "Mỗi tin là một lượt dùng gói Claude của bạn.": ("Every message is a turn on your Claude plan.", S),
    "Quay lại danh sách": ("Back to the list", S),
    "Ngắt lượt": ("Interrupt the turn", S),
    "Dừng phiên": ("Stop the session", S),
    "Xoá khỏi danh sách": ("Remove from the list", S),
    "Chưa có tin nào — gửi việc đầu tiên.": ("No messages yet — send the first task.", S),
    "Nhắn": ("Message", S),
    "Phiên đã dừng — hội thoại vẫn lưu trong Claude Code.": ("The session has stopped — the conversation is still saved in Claude Code.", S),
    "Sao chép lệnh mở lại": ("Copy the reopen command", S),
    "Phiên không cửa sổ": ("Windowless sessions", S),
    "XFinder chạy claude -p ở chế độ luồng trong thư mục bạn chọn, không mở terminal. Mỗi tin bạn gửi là một lượt dùng gói Claude của bạn. Phiên dừng khi bạn dừng nó hoặc thoát XFinder; hội thoại vẫn nằm trong Claude Code và mở lại được ở Phiên gần đây, hoặc bằng claude --resume trong terminal. XFinder chỉ giữ ~40 tin gần nhất trong bộ nhớ để hiện ở notch.": ("XFinder runs claude -p in streaming mode in the folder you choose, with no terminal window. Every message you send is a turn on your Claude plan. The session stops when you stop it or quit XFinder; the conversation stays in Claude Code and can be reopened from Recent sessions, or with claude --resume in a terminal. XFinder keeps only the last ~40 messages in memory to show at the notch.", S),
    "Bắt đầu một phiên mới trong thư mục đã chọn.": ("Start a new session in the chosen folder.", S),
    "Bắt đầu phiên": ("Start session", S),
    "Chưa cài hook Claude Code của XFinder: lệnh cần duyệt quyền trong phiên không cửa sổ không hỏi được qua notch (cài ở mục Claude Code bên dưới).": ("XFinder's Claude Code hook is not installed: a command that needs your approval in a windowless session cannot be asked at the notch (install it in the Claude Code section below).", S),
    "Đã bắt đầu — xem ở trang Agents trên notch.": ("Started — see the Agents page on the notch.", S),
    "Codex và OpenCode": ("Codex and OpenCode", S),
    "Chưa có phiên không cửa sổ cho hai agent này: Codex cần giao thức app-server của nó, XFinder chưa dựng; phiên OpenCode đã chạy trên server của chính bạn — tạo bằng lệnh opencode.": ("No windowless sessions for these two agents yet: Codex needs its app-server protocol, which XFinder has not built; OpenCode sessions already run on your own server — create one with the opencode command.", S),
    "Mở không cửa sổ": ("Open windowless", S),
    " tin": (" messages", F),
    # P7a review
    "Phiên này đang mở ở nơi khác — đóng nó trước rồi mở lại.": ("This session is open somewhere else — close it first, then reopen it.", S),
    "Phiên không cửa sổ — đã dừng": ("Windowless session — stopped", S),
    "Cài hook = thêm các mục \"Managed by XFinder\" vào ~/.claude/settings.json (có bản sao lưu đặt cạnh) và chép một script zsh vào Application Support. Hook của app khác giữ nguyên. Mỗi sự kiện của Claude Code chạy script đó vài mili-giây. Khi Claude Code xin quyền, script chờ bạn bấm Cho phép hoặc Từ chối trên notch; XFinder không chạy thì Claude Code hỏi ở terminal như thường. Claude Code trong terminal và phiên không cửa sổ do XFinder chạy dùng hook này — app Claude để bàn không chạy hook.": ("Installing the hook adds \"Managed by XFinder\" entries to ~/.claude/settings.json (with a backup beside it) and copies a zsh script into Application Support. Other apps' hooks stay as they are. Each Claude Code event runs the script for a few milliseconds. When Claude Code asks for permission, the script waits for you to press Allow or Deny at the notch; with XFinder not running, Claude Code asks in the terminal as usual. Claude Code in a terminal and the windowless sessions XFinder runs use this hook — the Claude desktop app runs no hooks.", S),
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
