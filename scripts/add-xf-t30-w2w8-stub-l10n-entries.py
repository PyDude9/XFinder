#!/usr/bin/env python3
"""XF-T30 W2–W8 stub vocabulary (command titles, tag colours) (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    "Tạo bí danh": ("Make Alias", S),
    "Hiện bản gốc": ("Show Original", S),
    "Thêm vào sidebar": ("Add to Sidebar", S),
    "Chia sẻ…": ("Share…", S),
    "Hiện tuỳ chọn xem": ("Show View Options", S),
    "Mục gần đây": ("Recents", S),
    "Tài liệu": ("Documents", S),
    "Màn hình nền": ("Desktop", S),
    "Thư mục Tải về": ("Downloads", S),
    "Thư mục nhà": ("Home", S),
    "AirDrop": ("AirDrop", S),
    "Mạng": ("Network", S),
    "iCloud Drive": ("iCloud Drive", S),
    "Các ứng dụng": ("Applications", S),
    "Tiện ích hệ thống": ("Utilities", S),
    "Máy tính": ("Computer", S),
    "Kết nối máy chủ…": ("Connect to Server…", S),
    "Đẩy ra": ("Eject", S),
    "Xoá menu": ("Clear Menu", S),
    "Cài đặt trình duyệt…": ("Browser Settings…", S),
    "Hiện cửa sổ Chào…": ("Show Welcome Window…", S),
    "Thư mục mới chứa mục chọn": ("New Folder with Selection", S),
    "Cắt tệp": ("Cut", S),
    "Làm lại": ("Redo", S),
    "Xoá lịch sử thao tác": ("Clear File Operation History", S),
    "Hiện hoặc ẩn xem trước": ("Show or Hide Preview", S),
    "Trình chiếu": ("Slideshow", S),
    "Không màu": ("No Color", S),
    "Xám": ("Gray", S),
    "Xanh lá": ("Green", S),
    "Tím": ("Purple", S),
    "Xanh dương": ("Blue", S),
    "Vàng": ("Yellow", S),
    "Đỏ": ("Red", S),
    "Cam": ("Orange", S),
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
