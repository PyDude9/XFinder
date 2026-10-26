#!/usr/bin/env python3
"""2026-10-26 — XF-T32 W2 sidebar parts: Space header menu + name sheet, Space pager, Live Groups section. ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
ENTRIES = {
    "Xoá Space": ("Delete Space", "sentence"),
    "Thanh bên của Space này sẽ mất. Tệp và thư mục trên đĩa không bị đụng tới.": ("This Space's sidebar will be lost. Files and folders on disk are not touched.", "sentence"),
    "Space mới…": ("New Space…", "sentence"),
    "Đổi tên Space…": ("Rename Space…", "sentence"),
    "Đổi Space": ("Switch Space", "sentence"),
    "Ẩn/hiện thanh bên": ("Show/hide sidebar", "sentence"),
    "Xoá Space “": ("Delete Space “", "fragment"),
    "”?": ("”?", "fragment"),
    "Cá nhân": ("Personal", "sentence"),
    "Tên Space": ("Space name", "sentence"),
    "Đã có Space tên này.": ("A Space with this name already exists.", "sentence"),
    "Space mới": ("New Space", "sentence"),
    "Đổi tên Space": ("Rename Space", "sentence"),
    "Space trước": ("Previous Space", "sentence"),
    "Space sau": ("Next Space", "sentence"),
    "Trống": ("Empty", "sentence"),
    "Bỏ khỏi thanh bên": ("Remove from Sidebar", "sentence"),
}
def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); e = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in e and e[k].get("en") != en]
    for k in bad: print(f"CONFLICT: {k!r} = {e[k].get('en')!r}")
    if bad: return 1
    added = sum(1 for k in ENTRIES if k not in e)
    for k, (en, sc) in ENTRIES.items(): e.setdefault(k, {"en": en, "scope": sc})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}"); return 0
if __name__ == "__main__": sys.exit(main())
