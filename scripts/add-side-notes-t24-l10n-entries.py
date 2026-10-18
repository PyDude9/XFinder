#!/usr/bin/env python3
"""XF-T24 (2026-10-18) — side-notes preview, global hotkey, automatic backup. ADD-ONLY: an existing key with another meaning is
a CONFLICT (exit 1), never rewritten. "còn " is reused as is (fragment, English empty: "còn 12 dòng nữa" → "12 more lines")."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "dòng nữa — bấm để mở": ("more lines — click to open", F),
    "Tự sao lưu mỗi ngày": ("Back up automatically every day", S),
    "Lần lưu đầu tiên mỗi ngày ghi một bản JSON (Nhập lại được) và một bản Markdown vào thư mục sao lưu trên máy này; giữ 14 ngày gần nhất, bản cũ hơn vào Thùng rác.":
        ("The first save of each day writes a JSON copy (it can be imported again) and a Markdown copy to the backup folder on this Mac; the newest 14 days are kept, older ones go to the Trash.", S),
    "Bản gần nhất: ": ("Latest backup: ", F),
    "Không sao lưu được: ": ("Backup failed: ", F),
    "Sao lưu ngay": ("Back up now", S),
    "Mở thư mục sao lưu": ("Open backup folder", S),
    "Phím tắt ⌃⌥N mở ghi chú từ mọi app": ("Shortcut ⌃⌥N opens notes from any app", S),
    "Mở ghi chú đầu dải (ghim trước, rồi mới sửa gần nhất) để viết ngay; chưa có thì tạo ghi chú mới; bấm lại để đóng. Không cần quyền, nhưng ⌃⌥N sẽ không còn tới app khác.":
        ("Opens the first note of the strip (pinned first, then the most recently edited) ready to type; with no notes it creates one; press again to close. No permission needed, but ⌃⌥N no longer reaches other apps.", S),
    "Không đăng ký được ⌃⌥N — có app khác đang giữ tổ hợp này.": ("Could not register ⌃⌥N — another app holds this shortcut.", S),
    "Mở ghi chú mép từ mọi app": ("Open edge notes from any app", S),
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
