#!/usr/bin/env python3
"""Unified palette: idempotent ADD-ONLY translations; refuses conflicting existing keys."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {'Chọn thư mục đích để di chuyển': ('Choose a destination folder to move to', 'sentence'), 'Tìm thư mục, biệt danh hoặc lệnh…': ('Find folders, nicknames, or commands…', 'sentence'), 'Không có kết quả phù hợp.': ('No matching results.', 'sentence'), '↵ Mở · ⌘↵ Tab mới · ⌥↵ Chia ngăn': ('↵ Open · ⌘↵ New Tab · ⌥↵ Split', 'sentence'), '↵ Di chuyển vào thư mục đã chọn': ('↵ Move to selected folder', 'sentence'), '⌘K Lệnh · esc Đóng': ('⌘K Actions · esc Close', 'sentence'), 'Di chuyển đến…': ('Move to…', 'sentence'), 'Chọn thư mục đích': ('Choose destination folder', 'sentence'), 'Không mở được mục này. Tệp có thể đã bị xoá hoặc thiếu quyền truy cập.': ('Cannot open this item. It may have been deleted or access is denied.', 'sentence'), 'Hãy chọn một thư mục thật làm đích di chuyển.': ('Choose a real folder as the move destination.', 'sentence'), 'Không thể tạo thêm ngăn trong bố cục hoặc gói hiện tại.': ('Cannot create another pane with the current layout or plan.', 'sentence')}

ENTRIES.update({'Các lệnh': ('Commands', 'sentence')})

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data["entries"]
    conflicts = [k for k, (en, _) in ENTRIES.items() if k in entries and entries[k].get("en") != en]
    if conflicts:
        for k in conflicts:
            print(f"CONFLICT: {k!r} already means {entries[k].get('en')!r}")
        return 1
    added = 0
    for k, (en, scope) in ENTRIES.items():
        if k not in entries:
            entries[k] = {"en": en, "scope": scope}
            added += 1
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
