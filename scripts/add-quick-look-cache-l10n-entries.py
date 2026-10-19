#!/usr/bin/env python3
"""Quick Look maintenance: thumbnail cache refresh (2026-10-19). ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Bảo trì": ("Maintenance", S),
    "Khi Finder vẫn hiện ảnh thu nhỏ cũ hoặc Quick Look không nhận tiện ích mới: xoá bộ nhớ đệm ảnh thu nhỏ và nạp lại các tiện ích (qlmanage của macOS).":
        ("When Finder still shows an old thumbnail or Quick Look ignores a new extension: empty the thumbnail cache and reload the extensions (macOS's qlmanage).", S),
    "Làm mới bộ nhớ đệm Quick Look": ("Refresh the Quick Look cache", S),
    "Đã xoá bộ nhớ đệm ảnh thu nhỏ và nạp lại các tiện ích Quick Look.": ("Thumbnail cache emptied and the Quick Look extensions reloaded.", S),
    "qlmanage báo lỗi — đóng cửa sổ Quick Look đang mở rồi thử lại.": ("qlmanage reported an error — close any open Quick Look window and try again.", S),
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
