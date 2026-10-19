#!/usr/bin/env python3
"""Remote Connect empty state (2026-10-19): says where the Upload button is, and that the feature is off. ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Thêm máy chủ để tải lên từ XFinder. Mỗi kết nối có nút Tải lên… ngay trên hàng của nó.":
        ("Add a server to upload from XFinder. Each connection has its Upload… button right on its row.", S),
    "Kết nối từ xa đang tắt — bật ở trên để kiểm tra hay tải lên.":
        ("Remote Connect is off — turn it on above to test or upload.", S),
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
