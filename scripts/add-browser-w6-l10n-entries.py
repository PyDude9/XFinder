#!/usr/bin/env python3
"""Unified palette: idempotent ADD-ONLY translations; refuses conflicting existing keys."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {'Hiện nút Học sử dụng': ('Show Learn button', 'sentence'), 'Khay Tải về': ('Downloads Tray', 'sentence'), '20 mục mới nhất theo ngày sửa đổi': ('20 most recent items by modification date', 'sentence'), 'Chưa có mục nào trong thư mục Tải về.': ('No items in the Downloads folder yet.', 'sentence'), 'Mở thư mục Tải về': ('Open Downloads Folder', 'sentence'), 'Mở khay Tải về': ('Open Downloads Tray', 'sentence'), 'Mở khay Tải về bằng ⌃⌥⌘D': ('Open Downloads Tray with ⌃⌥⌘D', 'sentence'), 'Không đăng ký được phím tắt. Một ứng dụng khác có thể đang dùng tổ hợp này.': ('Could not register the shortcut. Another app may be using this key combination.', 'sentence')}

ENTRIES.update({
    'Phím tắt mở trình duyệt': ('File Browser shortcut', S),
    'Đưa cửa sổ trình duyệt hiện có lên trước, hoặc mở nếu chưa có.': ('Bring an existing browser window forward, or open one if none exists.', S),
    'Tổ hợp mở trình duyệt': ('Browser shortcut keys', S),
    'Nhóm cài đặt': ('Settings category', S),
    'Mọi lệnh cũng có trong bảng lệnh: ⌃⇧⌘P, hoặc gõ > trong ⌃⌘P. Chọn nhóm Bàn phím trên trang này để đổi phím.': ('All commands are also in the command palette: ⌃⇧⌘P, or type > in ⌃⌘P. Choose the Keyboard category on this page to change shortcuts.', S),
    'Ngăn thông tin': ('Inspector', S),
    'Hiện ngăn xem trước': ('Show preview pane', S),
    'Hiện thêm thông tin': ('Show additional information', S),
    'Áp dụng trong thẻ Thông tin của ngăn xem trước.': ('Applies to the Information tab of the preview pane.', S),
})

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
