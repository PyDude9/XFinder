#!/usr/bin/env python3
"""P9 (2026-10-14) — handing a session over to another agent. ADD-ONLY: an existing key is never rewritten."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "Cần chú ý trước": ("Needs attention first", S),
    "Hoạt động gần nhất": ("Most recent activity", S),
    "Mở mới nhất": ("Newest first", S),
    "Danh sách phiên trên notch": ("Sessions on the notch", S),
    "Sắp xếp phiên": ("Sort sessions by", S),
    "Giữ phiên đã kết thúc trong danh sách": ("Keep ended sessions in the list", S),
    "Tắt thì phiên vừa kết thúc biến khỏi notch ngay; bật thì nó ở lại tối đa một giờ.": ("Off: a session disappears from the notch as soon as it ends. On: it stays for up to an hour.", S),
    "Rê chuột vào biểu tượng agent để mở trang Agents": ("Point at the agent icon to open the Agents page", S),
    "Dừng con trỏ trên ô agent ở cánh trái notch là mở danh sách phiên, dù “Rê chuột vào notch mở” đang chọn gì.": ("Resting the pointer on the agent tile in the notch's left wing opens the session list, whatever “Resting on the notch opens” is set to.", S),
    "Chép và mở app": ("Copy and open app", S),
    "App Claude chưa nhận tin tự động — XFinder chép tin, mở app để bạn dán.": ("The Claude app can't take messages yet — XFinder copies it and opens the app.", S),
    "Đang chờ bạn": ("Waiting for you", S),
    "Gửi": ("Send", S),
    "Chuyển phiên sang agent khác": ("Hand the session over to another agent", S),
    "Phiên mới của ": ("New session of ", F),
    "Chuyển phiên": ("Hand off", S),
    "Đang đọc phiên gốc…": ("Reading the original session…", S),
    "Codex chưa có phiên không cửa sổ: XFinder chép lệnh mở Codex kèm tin này, bạn dán vào terminal.": ("Codex has no windowless session yet: XFinder copies a command that opens Codex with this message, for you to paste in a terminal.", S),
    "Gửi sẽ dùng một lượt của ": ("Sending uses one turn of ", F),
    ". Chỉ có lời bạn gõ và câu trả lời của agent — không có output của công cụ.": (". Only what you typed and the agent's answers — no tool output.", F),
    "Lượt đọc được: ": ("Turns read: ", F),
    "Chép lệnh": ("Copy command", S),
    "Đã chuyển phiên": ("Session handed off", S),
    "Đã chép lệnh mở Codex": ("Copied the command that opens Codex", S),
    "Dán vào terminal để bắt đầu.": ("Paste it in a terminal to start.", S),
    "Tin chuyển giao đang trống.": ("The handoff message is empty.", S),
    "Phiên gốc không ghi thư mục.": ("The original session recorded no folder.", S),
    "OpenCode không tạo được phiên mới.": ("OpenCode could not create a new session.", S),
    "OpenCode không nhận tin chuyển giao.": ("OpenCode did not take the handoff message.", S),
}
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
