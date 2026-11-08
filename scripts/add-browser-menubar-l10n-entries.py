#!/usr/bin/env python3
"""XF-T38 — the file browser's menu bar and toolbar after FileOctopus 1.0.10 (owner screenshots, 2026-11-08). ADD-ONLY.

Menu, submenu and link titles from BrowserMenuLayout, the workspace submenus' prompts, and the palette's fallback
subtitle. Existing keys are reused as they are ("Tệp", "Xem", "Đi", "Mở bằng", "Nhóm theo", "Sắp theo", …).

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
    "XFinder": ("XFinder", S),
    "Shelf": ("Shelf", S),
    "Ngăn": ("Panes", S),
    "Mở workspace": ("Open Workspace", S),
    "Đổi tên workspace": ("Rename Workspace", S),
    "Nhân bản workspace": ("Duplicate Workspace", S),
    "Xoá workspace": ("Delete Workspace", S),
    "So sánh thư mục…": ("Compare Folders…", S),
    "Tìm tệp trùng…": ("Find Duplicates…", S),
    "Kết nối máy chủ từ xa…": ("Connect to Remote Server…", S),
    "Xuất các workspace…": ("Export Saved Workspaces…", S),
    "Chưa có workspace đã lưu": ("No Saved Workspaces", S),
    "Không xuất được các workspace": ("Couldn’t export the workspaces", S),
    "Xoá workspace “": ("Delete the workspace “", F),
    "Chỉ xoá bản lưu của workspace. Tệp và thư mục của bạn không đổi.": (
        "Only the saved workspace is deleted. Your files and folders aren’t changed.", S),
    "Trình duyệt": ("Browser", S),
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
