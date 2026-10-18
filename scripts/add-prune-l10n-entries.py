#!/usr/bin/env python3
"""Q-PRUNE (2026-10-18) — strings rewritten when the dead "Cấu hình menu" block left Thao tác Finder. ADD-ONLY: an
existing key is never rewritten (CONFLICT and exit 1)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "Thao tác trên các mục đang chọn trong Finder — từ trang này hoặc từ hai mục XFinder trong menu chuột phải.":
        ("Act on the items selected in Finder — from this page or from XFinder's two items in the right-click menu.", S),
    "macOS không có API công khai cho phép một ứng dụng thường thêm mục vào menu chuột phải của Finder. XFinder đi đường Apple hỗ trợ: một Finder Sync Extension với hai mục — Thêm vào Khay thả và Hiện trong Finder. Muốn thêm thao tác khác, dùng Quick Action (Shortcuts/Automator).":
        ("macOS has no public API that lets an ordinary app add items to Finder's right-click menu. XFinder takes the path Apple supports: a Finder Sync Extension with two items — Add to Drop Tray and Show in Finder. For other actions, use a Quick Action (Shortcuts/Automator).", S),
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
