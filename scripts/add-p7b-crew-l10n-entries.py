#!/usr/bin/env python3
"""P7b (2026-10-14) — "Crew": a few windowless Claude Code sessions with roles that hand work to each other through
XFinder; the board, the cap, the notch crew row and the settings section.

Idempotent, ADD-ONLY (same contract as add-p5-agents-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # CrewRules.templateKeys
    "Builder → người duyệt": ("Builder → reviewer", S),
    "Builder + hai người duyệt": ("Builder + two reviewers", S),
    # CrewRules.boardKeys ("nhắn"/"trả lời" join two role names: fragments)
    "nhắn": ("to", F),
    "trả lời": ("replied to", F),
    "Không gửi được — thành viên đã dừng.": ("Not delivered — the member has stopped.", S),
    "Crew tạm dừng.": ("Crew paused.", S),
    "Crew chạy tiếp.": ("Crew resumed.", S),
    "Đã tới giới hạn chặng tin — crew tạm dừng, chờ bạn.": ("The message-hop limit was reached — the crew is paused and waiting for you.", S),
    "Crew đã dừng.": ("Crew stopped.", S),
    # CrewManager / controller
    "Không tạo được crew.": ("Could not create the crew.", S),
    "Crew tạm dừng — chờ bạn": ("Crew paused — waiting for you", S),
    " chặng tin": (" message hops", F),
    # UI (filled from the UI agents' reports)
    " chặng tin để hỏi bạn.": (" message hops to ask you.", F),
    " phiên Claude Code. Người dẫn đầu dùng một lượt ngay với mục tiêu; mỗi tin giữa các thành viên cũng là một lượt. XFinder tạm dừng crew sau ": (" Claude Code sessions. The lead uses a turn right away on the goal; every message between members is a turn too. XFinder pauses the crew after ", F),
    "Sẽ chạy ": ("This runs ", F),
    "Bắt đầu crew trong thư mục đã chọn.": ("Start a crew in the chosen folder.", S),
    "Bắt đầu crew": ("Start crew", S),
    "Chưa cài hook Claude Code của XFinder: tin giữa các thành viên và lệnh cần duyệt không hỏi được qua notch (cài ở mục Claude Code bên dưới).": ("XFinder's Claude Code hook is not installed: crew messages and commands that need approval cannot be asked at the notch (install it in the Claude Code section below).", S),
    "Chạy tiếp": ("Resume", S),
    "Crew là vài phiên Claude Code không cửa sổ có vai trò, nhắn nhau qua XFinder bằng lệnh xfinder-crew. Các thành viên luôn chạy ở chế độ hỏi quyền: bạn duyệt từng tin giữa họ và từng lệnh cần duyệt. Người duyệt không có công cụ sửa tệp. Claude Code vẫn tự chạy một nhóm lệnh chỉ đọc mà không hỏi (như cat, grep, git diff); lệnh nhắn thành viên khác và lệnh có thể thay đổi máy thì vẫn hỏi bạn. Quy tắc cho phép sẵn trong cài đặt Claude Code của bạn hoặc của thư mục đó vẫn có hiệu lực: lệnh nào đã được cho phép ở đó sẽ không hỏi lại. Mọi thành viên làm chung một thư mục — chưa có nhánh git riêng cho từng người. Thành viên dừng khi crew dừng hoặc khi thoát XFinder. Người gửi được nhận ra bằng token riêng của từng thành viên; chương trình nào chạy dưới tài khoản của bạn cũng đọc được token đó.": ("A crew is a few windowless Claude Code sessions with roles that message each other through XFinder with the xfinder-crew command. Members always run in ask-first mode: you approve every message between them and every command that needs approval. Reviewers have no file-editing tools. Claude Code still runs a fixed set of read-only commands without asking (such as cat, grep, git diff); a message to another member and any command that can change the machine still ask you. Allow rules already in your Claude Code settings, or in that folder's, still apply: a command allowed there is not asked again. All members work in one folder — there are no per-member git branches yet. Members stop when the crew stops or when XFinder quits. A sender is recognised by each member's own token; any program running under your account can read that token.", S),
    "Mẫu crew": ("Crew template", S),
    "Mục tiêu cho cả crew…": ("A goal for the whole crew…", S),
    "Nhóm agent (crew)": ("Agent crew", S),
    "Đã bắt đầu crew — xem ở trang Agents trên notch.": ("Crew started — see the Agents page on the notch.", S),
    "Cho crew chạy tiếp": ("Resume the crew", S),
    "Chưa có tin nào giữa các thành viên.": ("No messages between the members yet.", S),
    "Dừng crew": ("Stop the crew", S),
    "Tạm dừng crew": ("Pause the crew", S),
    "Ước tính của Claude Code, không phải hoá đơn": ("Claude Code's own estimate, not a bill", S),
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
