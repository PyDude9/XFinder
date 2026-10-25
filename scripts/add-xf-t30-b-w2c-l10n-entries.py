#!/usr/bin/env python3
"""XF-T30 W2 builder w2c — shared context menu, drag-drop, View Options panel (2026-10-25). ADD-ONLY: a key already
present with another meaning is a CONFLICT. Run to test, then `git checkout -- XFinder/Resources/L10n.strings.json`
before committing (integrator applies the real entries)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # BrowserContextMenu
    "Mở bằng": ("Open With", S),
    "Đang tải…": ("Loading…", S),
    "Không có ứng dụng nào": ("No Applications", S),
    "Thẻ…": ("Tags…", S),
    "Hiện trong thư mục chứa": ("Show in Enclosing Folder", S),
    "Sao chép ": ("Copy ", F),
    " dưới dạng đường dẫn": (" as Pathname", F),
    " mục dưới dạng đường dẫn": (" Items as Pathname", F),
    "Xem dạng": ("View As", S),
    "Sắp theo": ("Sort By", S),
    "Nhóm theo": ("Group By", S),
    # ViewOptionsPanel
    "Tuỳ chọn xem": ("View Options", S),
    "Cỡ biểu tượng": ("Icon Size", S),
    "Cỡ chữ": ("Font size", S),   # already present with this meaning (reused, not a new key)
    "Cột hiện": ("Visible Columns", S),
    "Luôn mở theo kiểu này": ("Always Open in This View", S),
    "Dùng làm mặc định": ("Use as Defaults", S),
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
