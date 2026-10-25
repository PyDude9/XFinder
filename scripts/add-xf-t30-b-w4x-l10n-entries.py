#!/usr/bin/env python3
"""XF-T30 W4 builder w4x — FileBrowserDetailView's reduced shortcut-list footer (2026-10-25). ADD-ONLY: a key
already present with another meaning is a CONFLICT. Builders append the keys their views need to ENTRIES
(one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # FileBrowserDetailView.swift — "Phím tắt trong cửa sổ" section footer
    "Mọi lệnh cũng có trong bảng lệnh: ⌃⇧⌘P, hoặc gõ > trong ⌃⌘P. Đổi phím ở cửa sổ Cài đặt trình duyệt ▸ Bàn phím.":
        ("Every command is also in the command palette: ⌃⇧⌘P, or type > in ⌃⌘P. Change keys in Browser Settings ▸ Keyboard.", S),
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
