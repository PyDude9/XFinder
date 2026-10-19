#!/usr/bin/env python3
"""Capture: countdown and window shadow (2026-10-19). ADD-ONLY. " giây" and "Không" already exist and are reused as is."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Đếm ngược": ("Countdown", S),
    "Chỉ cho Toàn màn hình và Cửa sổ đang mở; kiểu chụp có bước chọn vùng không đếm.":
        ("Only for Full screen and the front window; modes with a selection step do not count down.", S),
    "Bóng đổ cửa sổ": ("Window shadow", S),
    "Tắt để ảnh chụp cửa sổ không kèm viền bóng của macOS.": ("Off: window shots come without the macOS shadow border.", S),
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
