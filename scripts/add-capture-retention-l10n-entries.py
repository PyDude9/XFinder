#!/usr/bin/env python3
"""Capture history retention by age (2026-10-23). ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Xoá ảnh chụp sau": ("Delete captures after", S),
    "Ảnh cũ hơn được đưa vào Thùng rác — vẫn khôi phục được.": ("Older captures go to the Trash — you can still restore them.", S),
    "1 ngày": ("1 day", S), "1 tuần": ("1 week", S), "1 tháng": ("1 month", S), "1 năm": ("1 year", S),
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
