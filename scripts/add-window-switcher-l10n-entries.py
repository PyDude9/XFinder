#!/usr/bin/env python3
"""Add the Window Switcher Liquid Glass strings to the L10n store."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

ENTRIES: dict[str, tuple[str, str]] = {
    "Nhấn , để tìm kiếm cửa sổ": ("Press , to search windows", "sentence"),
    "Không có cửa sổ": ("No windows", "sentence"),
    "Chuyển cửa sổ bằng phím tắt": ("Window Switcher Shortcut", "sentence"),
    "Bật bộ chuyển cửa sổ Liquid Glass": ("Enable Liquid Glass window switcher", "sentence"),
    "Khi bật, XFinder xử lý chuyển cửa sổ thay cho bộ chuyển ứng dụng của macOS. Giữ phím tắt để duyệt danh sách, nhấn dấu phẩy (,) để tìm kiếm, thả phím để mở hoặc nhấn Escape để hủy.": ("When enabled, XFinder manages window switching instead of macOS App Switcher. Hold hotkey to navigate, press comma (,) to search, release to open, or press Escape to cancel.", "sentence"),
    "Phím tắt chuyển cửa sổ": ("Window switcher shortcut", "sentence"),
    "Hiệu ứng chuyển động": ("Motion animation", "sentence"),
    "Mượt mà với hoạt cảnh co giãn và bóng mờ Liquid Glass.": ("Smooth scaling spring animation and Liquid Glass blur.", "sentence"),
    "Dải Dock Liquid Glass": ("Liquid Glass Dock", "sentence"),
    "Hiện dải ứng dụng Dock thay thế ở cạnh dưới màn hình": ("Show replacement Dock strip at bottom of screen", "sentence"),
    "Tự động ẩn Dock của macOS": ("Auto-hide macOS Dock", "sentence"),
    "Ứng dụng loại trừ": ("Excluded apps", "sentence"),
    "Các ứng dụng này sẽ không xuất hiện trong bộ chuyển cửa sổ.": ("These applications will not appear in the window switcher.", "sentence"),
    "Chưa có ứng dụng nào bị loại trừ.": ("No applications excluded yet.", "sentence"),
    "Thêm ứng dụng...": ("Add app...", "sentence"),
    "Thêm": ("Add", "sentence"),
    "Cần quyền Tự động hóa để đọc tab trình duyệt": ("Needs Automation permission to read browser tabs", "sentence"),
    "Tab đang mở": ("Open tabs", "sentence"),
    "Sự kiện sắp tới": ("Upcoming events", "sentence"),
    "Thời tiết hiện tại": ("Current weather", "sentence"),
    "XFinder cần quyền Trợ năng để nhận cử chỉ": ("XFinder needs Accessibility permission for gestures", "sentence"),
    "Hiện thiết bị đã ngắt kết nối": ("Show disconnected devices", "sentence"),
    "Không có thiết bị kết nối": ("No connected devices", "sentence"),
}

def main() -> None:
    with open(STORE, "r", encoding="utf-8") as f:
        data = json.load(f)

    entries = data.get("entries", data)
    added = 0
    updated = 0
    for vi, (en, scope) in ENTRIES.items():
        if vi not in entries:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        else:
            if entries[vi].get("en") != en or entries[vi].get("scope") != scope:
                entries[vi]["en"] = en
                entries[vi]["scope"] = scope
                updated += 1

    with open(STORE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Added {added}, updated {updated} entries. Total in store: {len(entries)}")

if __name__ == "__main__":
    main()
