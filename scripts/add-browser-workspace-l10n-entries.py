#!/usr/bin/env python3
"""XF-T39 — Workspaces after FileOctopus 1.0.10: save every window, ask before replacing a name, open adds windows,
inspect what each saved workspace holds. ADD-ONLY.

Also adds "Một số thư mục của Workspace này không còn tồn tại", which the workspace opener already showed with no store
entry (it leaked at runtime).

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
    "Xem các workspace đã lưu…": ("Inspect Saved Workspaces…", S),
    "Lưu mọi cửa sổ đang mở, cùng tab, ngăn, thư mục và kiểu xem. Mở lại sau sẽ thêm các cửa sổ này; không tệp nào bị đổi.": (
        "Saves the open windows, their tabs and panes, folders and views. Opening it later adds these windows; no files are changed.", S),
    "Workspace cần có tên.": ("A workspace needs a name.", S),
    "Không có cửa sổ trình duyệt nào để lưu.": ("There are no browser windows to save.", S),
    "Thay thế workspace “": ("Replace the workspace “", F),
    "Bố cục đã lưu của nó sẽ được thay bằng các cửa sổ đang mở.": ("Its saved layout will be replaced by the open windows.", S),
    "Các workspace đã lưu": ("Saved Workspaces", S),
    "Mỗi workspace chứa gì. Xem hay xuất không mở workspace và không đổi tệp nào.": (
        "What each saved workspace holds. Inspecting or exporting doesn’t open a workspace or change any file.", S),
    " cửa sổ · ": (" windows · ", F),
    " tab · lưu ": (" tabs · saved ", F),
    "Workspace này không còn nữa.": ("That workspace no longer exists.", S),
    "Đã có workspace tên này. Chọn tên khác.": ("A workspace with this name already exists. Choose a different name.", S),
    "Không đọc được tệp workspace đã lưu nên không ghi đè.": ("The saved workspaces file couldn’t be read, so it isn’t changed.", S),
    "Một số thư mục của Workspace này không còn tồn tại": ("Some folders of this workspace no longer exist", S),
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
