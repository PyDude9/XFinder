#!/usr/bin/env python3
"""XF-T30 W7 builder "w7v" (PreviewPaneView.swift, BrowserWindowModel+Preview.swift) — 2026-10-25. ADD-ONLY: a key
already present with another meaning is a CONFLICT. Builder appends the keys this file's view needs to ENTRIES
(one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    "Chọn một mục để xem trước": ("Select an item to preview", S),
    "Thông tin": ("Information", S),
    "Hiện thêm": ("Show More", S),
    "Hiện bớt": ("Show Less", S),
    "Không có thẻ": ("No tags", S),
    "Tệp chỉ có trên đám mây — xem trước không tải tệp về.": (
        "This file is cloud-only — the preview does not download it.", S),
    "Không xem trước được loại tệp này.": ("This file type can't be previewed.", S),
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
