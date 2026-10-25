#!/usr/bin/env python3
"""XF-T30 W6 builder w6f — folder merge, Problems list, persistent Undo, Cut board, zip/new-folder naming
(2026-10-25). ADD-ONLY: a key already present with another meaning is a CONFLICT. Builders append the keys their
views need to ENTRIES (one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # ProblemReason.titleKey (spec R51 canonical vocabulary)
    "Không có quyền": ("No Permission", S),
    "Ổ đĩa đầy": ("Disk Full", S),
    "Tệp đang được dùng": ("File In Use", S),
    "Ổ đĩa hoặc máy chủ mất kết nối": ("Disk or Server Disconnected", S),
    "Lỗi đọc hoặc ghi": ("Read or Write Error", S),
    "Ổ đĩa chỉ đọc": ("Read-Only Disk", S),
    "Tên quá dài": ("Name Too Long", S),
    "Mục không còn tồn tại": ("Item No Longer Exists", S),
    # UndoStep.titleKey (verb fragment; caller appends the item count)
    "Hoàn tác Chuyển": ("Undo Move", F),
    "Hoàn tác Sao chép": ("Undo Copy", F),
    "Hoàn tác Nhân bản": ("Undo Duplicate", F),
    "Hoàn tác Chuyển vào Thùng rác": ("Undo Move to Trash", F),
    "Hoàn tác Đổi tên": ("Undo Rename", F),
    "Hoàn tác Tạo thư mục mới": ("Undo New Folder", F),
    "Hoàn tác Gộp thư mục": ("Undo Merge", F),
    "Hoàn tác Nén": ("Undo Compress", F),
    "Hoàn tác Sửa thông tin": ("Undo Info Change", F),
    # UndoJournal.availability reason keys
    "Không còn mục nào để hoàn tác": ("Nothing left to undo", S),
    "Một mục không còn ở chỗ cũ": ("An item is no longer where it was", S),
    "Mục đã bị đổi từ bên ngoài, không thể hoàn tác": ("The item was changed from outside the app and can't be undone", S),
    # FolderMerge exclusion reasons (spec R27)
    "Gói ứng dụng — không gộp bên trong": ("App bundle — not merged inside", S),
    "Liên kết tượng trưng — không gộp bên trong": ("Symbolic link — not merged inside", S),
    "Thư mục đám mây — không gộp bên trong": ("Cloud folder — not merged inside", S),
    "Khác kiểu mục — tệp và thư mục cùng tên": ("Mismatched kind — a file and a folder share this name", S),
    # FileOperationRules.newFolderWithSelectionName default base name
    "Thư mục mới chứa mục": ("New Folder With Items", S),
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
