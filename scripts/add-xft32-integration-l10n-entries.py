#!/usr/bin/env python3
"""XF-T32 integration: row menus, property editor and dynamic property labels. ADD-ONLY.

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that exists with different English stops the script
and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {'Thuộc tính này không còn nữa': ('This property no longer exists', 'sentence'), 'Thuộc tính': ('Property', 'sentence'), 'Tên thuộc tính': ('Property name', 'sentence'), 'Hiện trong danh sách': ('Show in list', 'sentence'), 'Lựa chọn': ('Options', 'sentence'), 'Xoá lựa chọn': ('Delete option', 'sentence'), 'Thêm lựa chọn': ('Add option', 'sentence'), 'Sửa thuộc tính': ('Edit property', 'sentence'), 'Xoá thuộc tính': ('Delete property', 'sentence'), 'Tên lựa chọn': ('Option name', 'sentence'), 'Bỏ ghim khỏi': ('Unpin from', 'fragment'), 'Ghim vào': ('Pin in', 'fragment'), 'Xoá giá trị': ('Clear value', 'sentence'), 'Nhiều giá trị': ('Mixed values', 'sentence'), 'Thêm thuộc tính': ('Add property', 'sentence'), 'Thuộc tính mới…': ('New property…', 'sentence'), 'Đặt biệt danh…': ('Set nickname…', 'sentence'), 'Biệt danh': ('Nickname', 'sentence'), 'Đặt emoji…': ('Set emoji…', 'sentence'), 'Biểu tượng emoji': ('Emoji', 'sentence'), 'Lọc': ('Filter', 'sentence'), 'Tăng dần': ('Ascending', 'sentence'), 'Giảm dần': ('Descending', 'sentence'), 'đang hiện': ('visible', 'fragment'), 'Nhóm': ('Group', 'sentence'), 'Chưa đặt': ('Unset', 'sentence'), 'Lục': ('Green', 'sentence'), 'Lam': ('Blue', 'sentence')}

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
