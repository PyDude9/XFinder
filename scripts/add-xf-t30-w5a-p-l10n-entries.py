#!/usr/bin/env python3
"""XF-T30 W5a builder "pure" — index root status keys (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Builders append the keys their views need to ENTRIES (one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    # SearchIndexRules.statusKey (reach the screen through L10n.t(variable) — SearchIndexRulesTests)
    "Đang đánh chỉ mục…": ("Indexing…", S),
    "Đang cập nhật…": ("Updating…", S),
    "Sẵn sàng": ("Ready", S),
    "Đã tạm dừng": ("Paused", S),
    "Ngoại tuyến": ("Offline", S),
    "Không có quyền truy cập": ("No Access", S),
    "Đã di chuyển hoặc thay thế — thêm lại": ("Moved or Replaced — Add It Again", S),
    "Thất bại": ("Failed", S),
    # SavedSearchStore.add default name
    "Tìm kiếm đã lưu": ("Saved Search", S),
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
