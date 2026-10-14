#!/usr/bin/env python3
"""1.4.0 (2026-10-14) — the What's New notes for everything after the 1.3.0 zip (P1–P7, §3b #21/#37).

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that exists with different English stops the script
and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES: dict[str, tuple[str, str]] = {
    "Notch mới theo phong cách OneNotch": ("A new notch in OneNotch's style", S),
    "Cánh hai bên notch khi thu gọn, một dải chấm trang và công cụ, hai cỡ thân cho từng trang; Clipboard và Đang phát vẽ lại.": ("Wings beside the notch when collapsed, one band of page dots and tools, two body sizes per page; Clipboard and Now Playing redrawn.", S),
    "Hẹn giờ và Hạn mức AI trên notch": ("Timer and AI usage on the notch", S),
    "Hẹn giờ tập trung tạm dừng được; hạn mức Codex đọc từ log của Codex, % của Claude Code qua statusLine (bật ở trang Agent AI).": ("A focus timer you can pause; Codex limits read from Codex's own log, Claude Code's % through its statusLine (opt in on the AI agents page).", S),
    "Cài đặt gọn lại": ("Settings, tidied", S),
    "Thanh bên có ô màu, mỗi trang là các thẻ nhóm; mọi phím tắt của XFinder ở một trang, có báo trùng phím.": ("A sidebar with coloured tiles, every page in grouped cards; all of XFinder's shortcuts on one page, with clash warnings.", S),
    "Codex và OpenCode trên notch": ("Codex and OpenCode on the notch", S),
    "Phiên Codex qua cùng hook với Claude Code, phiên OpenCode qua lệnh opencode của bạn; thông báo khi agent hỏi quyền hoặc xong lượt.": ("Codex sessions through the same hook as Claude Code, OpenCode sessions through your own opencode command; a notice when an agent asks for permission or finishes a turn.", S),
    "Nhắn phiên từ notch": ("Reply to a session from the notch", S),
    "Gõ trả lời một phiên agent ngay trên notch: vào kitty, tmux hay OpenCode; terminal khác thì chép tin và mở terminal.": ("Answer an agent session right at the notch: typed into kitty, tmux or OpenCode; other terminals get the text copied and brought forward.", S),
    "Phiên không cửa sổ và nhóm agent": ("Windowless sessions and agent crews", S),
    "XFinder chạy Claude Code không cần terminal; một nhóm builder + người duyệt nhắn nhau qua XFinder, bạn duyệt từng tin.": ("XFinder runs Claude Code without a terminal; a builder + reviewer crew messages each other through XFinder, and you approve every message.", S),
    "Sóng âm thật trên trang Đang phát": ("A real waveform on the Now Playing page", S),
    "Vạch sóng lấy từ chính âm thanh của trình phát (bật trong trang Đang phát; macOS hỏi quyền thu âm hệ thống).": ("Bars drawn from the player's own audio (turn it on in Now Playing; macOS asks for system audio recording).", S),
}

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data["entries"]
    conflicts = [k for k, (en, _) in ENTRIES.items() if k in entries and entries[k].get("en") != en]
    if conflicts:
        for k in conflicts:
            print(f"CONFLICT: {k!r} already means {entries[k].get('en')!r}")
        return 1
    added = 0
    for k, (en, scope) in ENTRIES.items():
        if k not in entries:
            entries[k] = {"en": en, "scope": scope}
            added += 1
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
