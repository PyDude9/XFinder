#!/usr/bin/env python3
"""Add-only Vietnamese strings for XF-T33 image pipeline failures."""
import json
import sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
ENTRIES = {
    "Ảnh động nhiều khung hình chưa được hỗ trợ; tệp gốc được giữ nguyên: ": ("Animated images are not supported; the original file was left unchanged: ", "fragment"),
    "Ảnh động nhiều khung hình chưa được hỗ trợ; tệp gốc được giữ nguyên.": ("Animated images are not supported; the original file was left unchanged.", "sentence"),
    "Ảnh đã thay đổi sau khi xem trước; chưa tạo bản mới: ": ("The image changed after preview; no new copy was created: ", "fragment"),
    "Không thể áp dụng thông số ảnh: ": ("The image settings could not be applied: ", "fragment"),
    "Tạo bản mới; ảnh động nhiều khung hình được giữ nguyên và không xử lý.": ("Create a new copy; animated images with multiple frames are left unchanged.", "sentence"),
    "Xuất bản ảnh mới": ("Export a new image", "sentence"),
    "Định dạng xuất": ("Output format", "sentence"),
    "Cạnh dài đích": ("Long edge", "sentence"),
    "Giữ kích thước": ("Keep original size", "sentence"),
    "Vùng cắt — chiều rộng": ("Crop width", "sentence"),
    "Vùng cắt — chiều cao": ("Crop height", "sentence"),
    "Chất lượng": ("Quality", "sentence"),
    "Phóng lớn ảnh nhỏ": ("Enlarge small images", "sentence"),
    "Xem trước kích thước": ("Preview dimensions", "sentence"),
    "Tạo bản mới": ("Create copy", "sentence"),
    " × ": (" × ", "fragment"),
    " → ": (" → ", "fragment"),
    " px": (" px", "fragment"),
    "Ảnh nhỏ hơn kích thước đích; sẽ bỏ qua nếu không bật phóng lớn.": ("The image is smaller than the target; it will be skipped unless enlargement is enabled.", "sentence"),
    "Kích thước đích sẽ phóng lớn ảnh nhỏ; hãy bật Phóng lớn ảnh nhỏ.": ("The target would enlarge this small image; enable Enlarge small images to continue.", "sentence"),
    "Xem trước xử lý ảnh": ("Image transform preview", "sentence"),
    "Đang xem trước ảnh…": ("Previewing images…", "sentence"),
    "Không có bộ ghi phù hợp để tạo bản ảnh.": ("No compatible image encoder is available.", "sentence"),
    "Không có ảnh nào đủ điều kiện xuất.": ("No images are eligible for export.", "sentence"),
    "Mục không đủ điều kiện hoặc bị lỗi: ": ("Items skipped or failed: ", "fragment"),
}

data = json.loads(STORE.read_text(encoding="utf-8"))
entries = data.get("entries", data)
conflicts = [(vi, entries[vi]) for vi, value in ENTRIES.items()
             if vi in entries and entries[vi] != {"en": value[0], "scope": value[1]}]
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
