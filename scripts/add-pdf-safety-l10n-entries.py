#!/usr/bin/env python3
"""Add-only Vietnamese labels for XF-T33 PDF safety failures and recovery notice."""
import json
import sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
ENTRIES = {
    "Hủy thao tác PDF": ("Cancel PDF operation", "sentence"),
    "Đã hủy thao tác PDF; tệp nguồn vẫn được giữ nguyên.": ("PDF operation cancelled; source files were left unchanged.", "sentence"),
    "Tệp PDF vượt giới hạn kiểm tra an toàn: ": ("The PDF exceeds the safety inspection limit: ", "fragment"),
    "PDF được mã hóa hoặc khóa; chưa tạo bản mới: ": ("The PDF is encrypted or locked; no copy was created: ", "fragment"),
    "Quyền của PDF không cho phép thay đổi trang: ": ("The PDF permissions do not allow page changes: ", "fragment"),
    "PDF có chữ ký hoặc chính sách chứng nhận; không thể viết lại an toàn: ": ("The PDF has a signature or certification policy and cannot be safely rewritten: ", "fragment"),
    "PDF có cấu trúc chưa được kiểm tra; chưa tạo bản mới: ": ("The PDF contains an uninspected structure; no copy was created: ", "fragment"),
    "Không thể xác minh cấu trúc PDF bị lỗi để phục hồi an toàn: ": ("The damaged PDF structure could not be verified for safe recovery: ", "fragment"),
    "Bản PDF mới không vượt qua kiểm tra cấu trúc; tệp gốc được giữ nguyên: ": ("The new PDF did not pass structural validation; the original was left unchanged: ", "fragment"),
    "PDF nguồn đã thay đổi trong lúc xử lý; chưa công bố bản mới: ": ("The source PDF changed during processing; no new copy was published: ", "fragment"),
    "Đã viết lại bản sao sau khi xác minh cảnh báo cấu trúc PDF có thể phục hồi.": ("A copy was rewritten after a recoverable PDF structure warning was verified.", "sentence"),
    "Sắp xếp trang": ("Reorder pages", "sentence"),
    "Thứ tự trang mới": ("New page order", "sentence"),
    "Liệt kê đủ mỗi trang đúng một lần; ví dụ: 3,1,2": ("List every page exactly once; example: 3,1,2", "sentence"),
    "Thứ tự trang": ("Page order", "sentence"),
    "Tổng số trang cần liệt kê: ": ("Pages to list: ", "fragment"),
    "Đã sắp xếp lại ": ("Reordered ", "fragment"),
    " trang → ": (" pages → ", "fragment"),
}

data = json.loads(STORE.read_text(encoding="utf-8"))
entries = data.get("entries", data)
conflicts = [(key, entries[key]) for key, (value, scope) in ENTRIES.items()
             if key in entries and entries[key] != {"en": value, "scope": scope}]
if conflicts:
    for key, current in conflicts:
        print(f"CONFLICT {key!r}: {current!r}")
    print("Nothing written.")
    sys.exit(1)
added = 0
for key, (english, scope) in ENTRIES.items():
    if key not in entries:
        entries[key] = {"en": english, "scope": scope}
        added += 1
STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Added {added} entries (0 rewritten). Total in store: {len(entries)}")
