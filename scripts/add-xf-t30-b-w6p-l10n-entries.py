#!/usr/bin/env python3
"""XF-T30 W6 builder "b-w6p" — Operations panel/model (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Builders append the keys their views need to ENTRIES (one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    "Không tạm dừng được ở bước cuối": ("Can't pause at the final step", S),
    "Đang chuẩn bị": ("Preparing", S),
    "Đang chép": ("Copying", S),
    "Sự cố": ("Problems", S),
    "Hiện trong XFinder": ("Show in XFinder", S),
    "Không có gì để thao tác": ("Nothing to do this with", S),
    "Không tạo được thư mục mới": ("Couldn't create the new folder", S),
    "Không thể chép một thư mục vào chính nó": ("Can't copy a folder into itself", S),
    "Gộp…": ("Merge…", S),
    "Khi trùng tên": ("When names match", S),
    "Giữ bản mới hơn": ("Keep the newer one", S),
    "Sẽ chép": ("Will copy", S),
    "Sẽ thay": ("Will replace", S),
    "Sẽ bỏ qua": ("Will skip", S),
    "Sẽ đổi tên": ("Will rename", S),
    "Bỏ qua (không hợp lệ)": ("Skipped (not valid)", S),
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
