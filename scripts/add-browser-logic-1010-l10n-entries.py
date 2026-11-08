#!/usr/bin/env python3
"""XF-T37 — file browser logic aligned with FileOctopus 1.0.10: name rules, batch rename (Replace Text / Add Text /
Format), search filter warnings and date forms, "Warn before quitting (⌘Q)". ADD-ONLY.

Also adds two keys the code already used without a store entry (they leaked at runtime): "Không đổi được tên" (the
inline-rename failure banner) and "Cũ hơn " (the "older than N days" search chip).

Idempotent: an existing key is never rewritten; a key that exists with different English stops the script and writes
nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # L1 — name rules
    "Tên này được dành riêng.": ("This name is reserved.", S),
    "Tên không được chứa ký tự điều khiển.": ("The name can’t contain control characters.", S),
    "Tên quá dài: tối đa 255 ký tự, mỗi dấu (sắc, huyền, mũ…) tính thêm một.": (
        "The name is too long: up to 255 characters, and each accent mark counts as one more.", S),
    "Chỉ đổi chữ hoa/thường.": ("Only the capitalization changes.", S),
    "Tên bắt đầu bằng dấu chấm sẽ bị ẩn.": ("Names beginning with a dot are hidden.", S),
    "Đổi đuôi:": ("Changes the extension:", F),
    "Bỏ đuôi:": ("Removes the extension:", F),
    "Thêm đuôi:": ("Adds the extension:", F),
    "Không đổi được tên": ("Couldn’t rename", S),
    # L2 — batch rename
    "Một mục khác trong lô cũng ra tên này.": ("Another item would get the same name.", S),
    "Đã có mục khác cùng tên trong thư mục này.": ("An item with this name already exists in this folder.", S),
    "Nằm trong một mục khác cũng đang đổi tên.": ("It’s inside another item being renamed.", S),
    "Mục không còn ở chỗ cũ.": ("The item is no longer there.", S),
    "Mục đang bị khoá.": ("The item is locked.", S),
    "Không có quyền đổi tên trong thư mục này.": ("You don’t have permission to rename items in this folder.", S),
    "Thay chữ": ("Replace Text", S),
    "Thêm chữ": ("Add Text", S),
    "Chữ thêm vào": ("Text to add", S),
    "Kiểu tên": ("Name Format", S),
    "Tên và chỉ số": ("Name and Index", S),
    "Tên và bộ đếm": ("Name and Counter", S),
    "Tên và ngày": ("Name and Date", S),
    "Tên tuỳ chỉnh": ("Custom Format", S),
    "Gồm cả đuôi tệp": ("Include extension", S),
    "Đặt ở": ("Where", S),
    "Sau tên": ("after name", S),
    "Trước tên": ("before name", S),
    "Không đổi": ("Unchanged", S),
    " mục sẽ được đổi tên.": (" items will be renamed.", F),
    " mục có lỗi — sửa hết mới đổi được.": (" items can’t be used — fix them all to rename.", F),
    "Không đổi tên được: ": ("Couldn’t rename: ", F),
    "Mọi mục đã trở về tên cũ.": ("Every item is back at its old name.", S),
    " mục chưa trả về được tên cũ: ": (" items couldn’t be put back: ", F),
    "Tệp ": ("File ", F),
    # L4 — search warnings and date chips
    "không phải bộ lọc, được tìm như chữ.": ("isn’t a search filter, so it is searched as text.", F),
    "không phải ngày. Dùng <7d, >2w, <3m, <1y, today, yesterday, 2026-10-01 hoặc 2026-10-01..2026-10-10.": (
        "isn’t a date. Use <7d, >2w, <3m, <1y, today, yesterday, 2026-10-01 or 2026-10-01..2026-10-10.", F),
    "không phải cỡ tệp. Dùng dạng >5MB, <=200KB hoặc =0.": ("isn’t a size. Use a form like >5MB, <=200KB or =0.", F),
    "không phải loại đã biết. Thử pdf, image, video, audio, archive, document, code hoặc folder.": (
        "isn’t a known kind. Try pdf, image, video, audio, archive, document, code or folder.", F),
    "không phải đuôi tệp.": ("isn’t a file extension.", F),
    "cần một giá trị.": ("needs a value.", F),
    "Thiếu dấu ngoặc kép đóng; phần còn lại được tìm như một cụm.": (
        "Missing closing quote; the rest of the search is treated as one phrase.", S),
    "Ô tìm dài quá — chỉ dùng ": ("The search is too long — only the first ", F),
    " ký tự đầu.": (" characters are used.", F),
    "Quá nhiều từ — chỉ dùng ": ("Too many terms — only the first ", F),
    " từ đầu.": (" terms are used.", F),
    "Trong ": ("In the last ", F),
    " ngày qua": (" days", F),
    " tuần qua": (" weeks", F),
    " tháng qua": (" months", F),
    " năm qua": (" years", F),
    "Cũ hơn ": ("Older than ", F),
    " ngày": (" days", F),
    " tuần": (" weeks", F),
    " tháng": (" months", F),
    " năm": (" years", F),
    # L5 — warn before quitting
    "Cảnh báo trước khi thoát (⌘Q)": ("Warn before quitting (⌘Q)", S),
    "Bật: trong cửa sổ trình duyệt, bấm ⌘Q hai lần hoặc giữ ⌘Q mới thoát — ⌘Q tắt cả XFinder (notch, clipboard, "
    "agent…), không chỉ cửa sổ. Đóng cửa sổ cuối không bao giờ thoát.": (
        "When on, in a browser window press ⌘Q twice or hold it to quit — ⌘Q quits all of XFinder (notch, clipboard, "
        "agents…), not just the window. Closing the last window never quits.", S),
    "XFinder vẫn đang chạy.": ("XFinder is still running.", S),
    "Bấm ⌘Q lần nữa hoặc giữ ⌘Q để thoát.": ("Press ⌘Q again or hold it to quit.", S),
}


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
