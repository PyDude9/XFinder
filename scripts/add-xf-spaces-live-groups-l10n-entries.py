#!/usr/bin/env python3
"""2026-10-28 — Spaces and folder Live Groups L10n entries. ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"

ENTRIES = {
    "Kéo thư mục vào đây hoặc ghim từ menu của thư mục.": ("Drag folders here or pin from folder menu.", "sentence"),
    "Đã có nhóm tên này.": ("A group with this name already exists.", "sentence"),
    "Live Group mới…": ("New Live Group…", "sentence"),
    "Thêm nhóm hoặc Space": ("Add group or Space", "sentence"),
    "Live Group": ("Live Group", "sentence"),
    "Live Group mới": ("New Live Group", "sentence"),
    "Chỉnh sửa Live Group": ("Edit Live Group", "sentence"),
    "Chỉnh sửa Live Group…": ("Edit Live Group…", "sentence"),
    "Live Group tự động đồng bộ với thư mục nguồn, chỉ hiển thị các mục khớp với bộ lọc của bạn.": (
        "A Live Group stays in sync with its source folder, showing only the items that match your filters.",
        "sentence",
    ),
    "Thư mục nguồn": ("Source folder", "sentence"),
    "Đường dẫn thư mục": ("Folder path", "sentence"),
    "Phần mở rộng": ("Extension", "sentence"),
    "Chứa": ("Contains", "sentence"),
    "Bắt đầu bằng": ("Begins with", "sentence"),
    "Kết thúc bằng": ("Ends with", "sentence"),
    "Là": ("Is", "sentence"),
    "Tệp": ("File", "sentence"),
    "Thêm bộ lọc": ("Add filter", "sentence"),
    "Xoá bộ lọc": ("Delete filters", "sentence"),
    "Tên (A đến Z)": ("Name (A to Z)", "sentence"),
    "Tên (Z đến A)": ("Name (Z to A)", "sentence"),
    "Không có mục nào khớp bộ lọc.": ("No items match your filters.", "sentence"),
    "Thêm ít nhất một bộ lọc để lưu Live Group này.": ("Add at least one filter to save this Live Group.", "sentence"),
    "Thư mục nguồn không hợp lệ.": ("Invalid source folder.", "sentence"),
}

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in entries and entries[k].get("en") != en]
    for k in bad:
        print(f"CONFLICT: {k!r} = {entries[k].get('en')!r}")
    if bad:
        return 1
    added = 0
    for k, (en, sc) in ENTRIES.items():
        if k not in entries:
            entries[k] = {"en": en, "scope": sc}
            added += 1
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
