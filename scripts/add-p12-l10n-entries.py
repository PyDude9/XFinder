#!/usr/bin/env python3
"""P12 (2026-10-14) — a session that stopped at a usage limit, and the handoff it offers. ADD-ONLY: an existing key is
never rewritten (a key that already exists may mean something else — CONFLICT and exit 1)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "Chạm giới hạn": ("Hit a limit", S),
    "Phiên dừng vì chạm giới hạn": ("Session stopped at a usage limit", S),
    "Chuyển sang ": ("Hand off to ", F),
    "Khi một phiên dừng vì chạm giới hạn sử dụng": ("When a session stops at a usage limit", S),
    "Báo cả khi bạn đang nhìn phiên đó. Nếu máy có agent khác, thông báo kèm nút mở sẵn bảng chuyển việc sang agent đó — ưu tiên agent biết chắc còn hạn mức. Bạn vẫn tự đọc và bấm Gửi.":
        ("Shown even while you are looking at that session. If another agent is installed, the notice has a button that opens the handoff to it — one known to have room first. You still read it and press Send.", S),
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
