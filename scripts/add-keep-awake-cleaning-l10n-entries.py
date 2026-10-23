#!/usr/bin/env python3
"""XF-T27 Chống ngủ + Lau bàn phím (2026-10-23). ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Đã tắt Chống ngủ vì pin yếu.": ("Keep Awake turned off: the battery is low.", S),
    "Giữ cả màn hình sáng khi Chống ngủ": ("Keep the screen on too while Keep Awake runs", S),
    "Lần trước đã tự tắt vì pin yếu (≤ 10 %, đang chạy pin).": ("Last time it turned itself off for a low battery (≤ 10 %, on battery power).", S),
    "Chống ngủ tự tắt khi chạy pin và còn ≤ 10 %.": ("Keep Awake turns itself off on battery power at ≤ 10 %.", S),
    "Lau bàn phím": ("Clean the keyboard", S),
    "Lau bàn phím…": ("Clean the Keyboard…", S),
    "Khoá bàn phím để lau; chuột vẫn dùng được. Esc 5 lần hoặc nút Mở khoá để thoát.":
        ("Locks the keyboard so you can wipe it; the mouse still works. Esc five times or the Unlock button to leave.", S),
    "Bắt đầu lau": ("Start", S),
    "Cần quyền Trợ năng để khoá bàn phím.": ("Locking the keyboard needs the Accessibility permission.", S),
    "Đang lau bàn phím": ("Cleaning the keyboard", S),
    "Bàn phím đang khoá. Bấm Esc 5 lần hoặc Mở khoá.": ("The keyboard is locked. Press Esc five times or Unlock.", S),
    "Mở khoá": ("Unlock", S),
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
