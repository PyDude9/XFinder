#!/usr/bin/env python3
"""P2 (2026-10-13) — the Agents / Calendar restyle, the Hẹn giờ and Hạn mức AI tools, the Claude Code statusLine
installer.

Idempotent, ADD-ONLY (same contract as add-smartselect-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # page titles (NotchPages.titleKey)
    "Hẹn giờ": ("Timer", S),
    "Hạn mức AI": ("AI usage", S),
    # Agents page
    " phiên": (" sessions", F),
    " chờ bạn": (" need you", F),
    # Hẹn giờ
    "Chọn thời gian": ("Pick a duration", S),
    "Tạm dừng": ("Pause", S),
    "Bắt đầu hẹn giờ": ("Start timer", S),
    "Dừng hẹn giờ": ("Stop timer", S),
    "Bớt 5 phút": ("5 min less", S),
    "Thêm 5 phút": ("5 min more", S),
    "Giảm": ("Decrease", S),
    "Tăng": ("Increase", S),
    "Thước thời gian hẹn giờ": ("Timer ruler", S),
    # Hạn mức AI
    "Hạn mức": ("Quota", S),
    "Token": ("Tokens", S),
    "Cập nhật ": ("Updated ", F),
    "5 giờ": ("5 h", S),
    "tuần": ("week", S),
    "lúc ": ("at ", F),
    "đã qua giờ reset": ("past its reset", S),
    "đã qua giờ reset — số mới có sau lần dùng Codex kế tiếp": ("past its reset — a new figure comes with the next Codex use", S),
    "Chưa có dữ liệu Codex trên máy này.": ("No Codex data on this Mac.", S),
    "Chưa đọc % hạn mức Claude.": ("Claude's usage % is not being read.", S),
    "Bật trong Cài đặt": ("Turn on in Settings", S),
    "Chưa nhận được % — Claude Code chỉ gửi nó cho phiên claude trong terminal, tài khoản Pro/Max, sau câu trả lời đầu.":
        ("No % received yet — Claude Code sends it only to a claude session in a terminal, on a Pro/Max account, after the first reply.", S),
    "5 giờ: ": ("5 h: ", F),
    " token": (" tokens", F),
    "Không có hoạt động trong 7 ngày.": ("No activity in the last 7 days.", S),
    "vào ": ("in ", F),
    "Đặt lại sau ": ("Resets in ", F),
    " phút nữa": (" min", F),
    " giờ nữa": (" h", F),
    " ngày nữa": (" d", F),
    # Settings ▸ Agent AI ▸ statusLine
    "Không đọc được bản lưu statusLine cũ, nên XFinder không gỡ — gỡ bây giờ sẽ làm mất cài đặt cũ của bạn. Các bản sao lưu settings.json có ngày giờ vẫn nằm trong ~/.claude.":
        ("XFinder cannot read the saved previous statusLine, so it did not remove anything — removing now would lose your old setting. The dated settings.json backups are still in ~/.claude.", S),
    "Bản cài XFinder thiếu script statusLine — hãy cài lại XFinder.": ("This copy of XFinder is missing the statusLine script — reinstall XFinder.", S),
    "Gỡ statusLine": ("Remove statusLine", S),
    "Cài statusLine": ("Install statusLine", S),
    "Cài đặt đang trỏ sang lệnh khác": ("Settings point at another command", S),
    "Không đổi được statusLine: ": ("Could not change the statusLine: ", F),
    "Đã cài statusLine. Phiên Claude Code mới sẽ ghi % hạn mức vào bộ nhớ đệm của XFinder.":
        ("statusLine installed. New Claude Code sessions will write the usage % into XFinder's cache.", S),
    "Đã gỡ statusLine.": ("statusLine removed.", S),
    "Cài đặt statusLine hiện đang trỏ sang một lệnh khác (có thể là của một công cụ khác bọc quanh statusLine của XFinder). Gỡ ở đây sẽ làm đứt chuỗi lệnh đó — hãy gỡ statusLine ở công cụ kia trước, rồi quay lại đây.":
        ("The statusLine setting now points at another command (possibly another tool wrapping XFinder's statusLine). Removing it here would break that chain — remove the statusLine in that tool first, then come back here.", S),
    "Claude Code chỉ đưa % hạn mức 5 giờ / 7 ngày cho dòng trạng thái (statusLine) của chính nó. statusLine của XFinder chỉ lưu lại đúng con số đó rồi chạy tiếp dòng trạng thái bạn đang có — những gì bạn thấy ở terminal không đổi. Cài sẽ ghi bản sao lưu ~/.claude/settings.json có ngày giờ trước khi sửa; Gỡ statusLine khôi phục đúng lệnh cũ. Chỉ có số khi: đang ở phiên Claude Code trong terminal (app Claude để bàn không chạy statusLine), tài khoản Pro/Max đăng nhập bằng claude.ai, và sau câu trả lời đầu tiên của phiên đó.":
        ("Claude Code gives the 5-hour / 7-day usage % only to its own status line. XFinder's statusLine stores just that number, then runs the status line you already had — what you see in the terminal does not change. Installing writes a dated backup of ~/.claude/settings.json first; Remove statusLine restores the exact previous command. There is a number only when you are in a Claude Code session in a terminal (the Claude desktop app does not run status lines), on a Pro/Max account signed in with claude.ai, after that session's first reply.", S),
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
