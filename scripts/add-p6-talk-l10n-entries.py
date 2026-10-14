#!/usr/bin/env python3
"""P6 (2026-10-14) — "Nhắn phiên": replying to an agent session from the notch (kitty / tmux / OpenCode, else copy +
bring the terminal forward), the queue for a working session, and the outcome lines.

Idempotent, ADD-ONLY (same contract as add-p5-agents-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # AgentTalk.reasonKeys
    "Phiên đã kết thúc.": ("The session has ended.", S),
    "Phiên đang chờ bạn duyệt quyền — dùng Cho phép / Từ chối.": ("The session is waiting for your approval — use Allow / Deny.", S),
    "Trên terminal đang có một hộp thoại — trả lời nó ở terminal trước.": ("A dialog is open in the terminal — answer it there first.", S),
    "Agent đang hỏi bạn một câu có lựa chọn — trả lời ở terminal.": ("The agent is asking you a multiple-choice question — answer it in the terminal.", S),
    # AgentTalk.labelKeys
    "Gửi vào kitty": ("Send to kitty", S),
    "Gửi vào tmux": ("Send to tmux", S),
    "Gửi qua OpenCode": ("Send via OpenCode", S),
    "Chép tin nhắn": ("Copy message", S),
    "Chép và mở terminal": ("Copy and open terminal", S),
    # AgentTalk.statusKeys (AgentTalkSender outcome lines)
    "Cửa sổ kitty của phiên không còn chạy agent — không gõ vào đâu cả.": ("The session's kitty window no longer runs the agent — nothing was typed.", S),
    "Không tìm thấy lệnh kitty.": ("The kitty command was not found.", S),
    "Không tìm thấy lệnh opencode.": ("The opencode command was not found.", S),
    "Không tìm thấy lệnh tmux.": ("The tmux command was not found.", S),
    "OpenCode không nhận tin.": ("OpenCode did not accept the message.", S),
    "OpenCode đã xếp tin vào hàng đợi của phiên.": ("OpenCode queued the message for the session.", S),
    "Phiên đã kết thúc — tin đang chờ chưa được gửi.": ("The session ended — the waiting message was not sent.", S),
    "Sẽ gửi khi phiên rảnh.": ("Will send when the session is free.", S),
    "kitty không cho điều khiển từ xa (cần allow_remote_control và listen_on trong kitty.conf).": ("kitty refused remote control (it needs allow_remote_control and listen_on in kitty.conf).", S),
    "kitty không nhận chữ.": ("kitty did not accept the text.", S),
    "kitty không nhận phím Enter.": ("kitty did not accept the Enter key.", S),
    "tmux không nhận chữ.": ("tmux did not accept the text.", S),
    "tmux không nhận phím Enter.": ("tmux did not accept the Enter key.", S),
    "Ô tmux của phiên không còn — không gõ vào đâu cả.": ("The session's tmux pane is gone — nothing was typed.", S),
    "Đang gửi…": ("Sending…", S),
    "Đã chép — dán (⌘V) vào terminal rồi bấm Enter.": ("Copied — paste it (⌘V) into the terminal and press Enter.", S),
    "Đã chép — mở terminal của phiên, dán (⌘V) rồi bấm Enter.": ("Copied — open the session's terminal, paste (⌘V) and press Enter.", S),
    "Đã gửi qua OpenCode.": ("Sent via OpenCode.", S),
    "Đã gửi vào kitty.": ("Sent to kitty.", S),
    "Đã gửi vào tmux.": ("Sent to tmux.", S),
    "Đã huỷ tin đang chờ.": ("Cancelled the waiting message.", S),
    "Đã thay tin đang chờ — sẽ gửi khi phiên rảnh.": ("Replaced the waiting message — it will send when the session is free.", S),
    # P6 review
    "Đã chép — trả lời hộp thoại ở terminal trước, rồi dán (⌘V) và bấm Enter.": ("Copied — answer the dialog in the terminal first, then paste (⌘V) and press Enter.", S),
    "Cửa sổ kitty thôi chạy agent trước khi bấm Enter — chữ có thể còn ở dòng nhập, chưa gửi.": ("The kitty window stopped running the agent before Enter — the text may still be in the input line, unsent.", S),
    "Ô tmux đã đổi trước khi bấm Enter — chữ có thể còn ở dòng nhập, chưa gửi.": ("The tmux pane changed before Enter — the text may still be in the input line, unsent.", S),
    "XFinder không gõ vào hộp thoại: tin được chép và terminal được đưa lên trước.": ("XFinder never types into a dialog: the message is copied and the terminal brought forward.", S),
    # UI (filled from the UI agents' reports)
    "Nhắn phiên này": ("Reply to this session", S),
    "Tin đang chờ — gửi khi phiên rảnh": ("Message waiting — sends when the session is free", S),
    "Nhắn cho phiên…": ("Message the session…", S),
    "Phiên đang chạy — tin sẽ được gửi khi phiên rảnh.": ("The session is working — the message will send when it is free.", S),
    "Terminal này chưa gõ được tự động — XFinder chép tin và mở terminal.": ("XFinder can't type into this terminal yet — it copies the message and opens the terminal.", S),
    "Nhắn phiên": ("Reply to sessions", S),
    "Mỗi tin chỉ một dòng; ký tự điều khiển bị bỏ trước khi gõ. Khi phiên đang hỏi quyền hay hỏi một câu có lựa chọn, XFinder không gõ gì (phím gõ vào sẽ trả lời hộp thoại). Phiên đang chạy thì tin được giữ lại và gửi khi phiên rảnh. Socket nhắn tin của Claude Code không được dùng: tin qua đó hiện là tin của một phiên khác, không phải của bạn.": ("Each message is a single line; control characters are removed before typing. While a session is asking for a permission or a multiple-choice question, XFinder types nothing — a keystroke would answer the dialog. A message for a working session is held and sent once it is free. Claude Code's messaging socket is not used: a message sent through it shows up as coming from another session, not from you.", S),
    "Gõ thẳng vào đúng cửa sổ của phiên. Cần allow_remote_control yes và listen_on unix:… trong kitty.conf; XFinder kiểm tra cửa sổ vẫn chạy agent trước khi gõ.": ("Types straight into the session's own window. Needs allow_remote_control yes and listen_on unix:… in kitty.conf; XFinder checks the window still runs the agent before typing.", S),
    "Gõ thẳng vào đúng ô của phiên; XFinder kiểm tra ô vẫn là của phiên (cùng tty) trước khi gõ.": ("Types straight into the session's own pane; XFinder checks the pane still belongs to the session (same tty) before typing.", S),
    "Gửi qua chính lệnh opencode của bạn; khi phiên đang chạy, OpenCode xếp tin vào hàng đợi của phiên.": ("Sent through your own opencode command; while the session is working, OpenCode queues the message for it.", S),
    "Terminal khác": ("Other terminals", S),
    "Terminal.app, iTerm2, Ghostty và WezTerm chưa được đo để gõ tự động, nên XFinder chép tin vào clipboard và đưa terminal lên trước để bạn dán. Phiên Claude Code hay Codex chạy trong kitty hoặc tmux thì vẫn được gõ thẳng.": ("Terminal.app, iTerm2, Ghostty and WezTerm have not been measured for typing, so XFinder copies the message to the clipboard and brings the terminal forward for you to paste. A Claude Code or Codex session running inside kitty or tmux is still typed into directly.", S),
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
