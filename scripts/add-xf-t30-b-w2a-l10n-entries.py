#!/usr/bin/env python3
"""XF-T30 W2 builder w2a — GroupBy.sections headers (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Builders append the keys their views need to ENTRIES (one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # GroupBy.sections date-group headers (relative dates not already in the store)
    "7 ngày trước": ("Previous 7 Days", S),
    "30 ngày trước": ("Previous 30 Days", S),
    "Chưa có ngày": ("No Date", S),
    # GroupBy.sections size-group headers
    "Không byte": ("Zero Bytes", S),
    "Dưới 100 KB": ("Under 100 KB", S),
    "Từ 100 KB đến 1 MB": ("100 KB to 1 MB", S),
    "Từ 1 đến 100 MB": ("1 to 100 MB", S),
    "Từ 100 MB đến 1 GB": ("100 MB to 1 GB", S),
    "Trên 1 GB": ("Over 1 GB", S),
    # GroupBy.sections tags-group header (untagged)
    "Không có thẻ": ("No Tags", S),
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
