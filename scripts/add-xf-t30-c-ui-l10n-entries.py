#!/usr/bin/env python3
"""XF-T30 W5b builder "ui" — search bar wired onto SearchCoordinator, scope bar, saved searches, index "Nơi chứa"
column (2026-10-25). ADD-ONLY: a key already present with another meaning is a CONFLICT. Builders append the keys
their views need to ENTRIES (one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # SearchBarView — index-updating note, scope bar, Save Search popover
    "Đang cập nhật chỉ mục…": ("Updating index…", S),
    "Thư mục hiện tại": ("Current Folder", S),
    "Các ngăn đang mở": ("Open Panes", S),
    "Lưu tìm kiếm…": ("Save Search…", S),
    # FileListView — "Nơi chứa" column + source label words (fragments: joined with ", "/" · " at the call site)
    "Nơi chứa": ("Location", S),
    "tên": ("name", F),
    "nội dung": ("content", F),
    # BrowserMainMenu — Go ▸ Tìm kiếm đã lưu submenu
    "Không có tìm kiếm đã lưu nào": ("No saved searches", S),
    "Đổi tên tìm kiếm đã lưu": ("Rename Saved Search", S),
    "Xoá tìm kiếm đã lưu": ("Delete Saved Search", S),
    "Sao chép câu tìm": ("Copy Search Text", S),
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
