#!/usr/bin/env python3
"""Local diagnostics (2026-10-14): Giới thiệu ▸ Hỗ trợ & báo lỗi, and the menu's Trợ giúp submenu.

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that exists with different English stops the script
and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES: dict[str, tuple[str, str]] = {
    "Trợ giúp": ("Help", S),
    "Báo lỗi…": ("Report a bug…", S),
    "Sao chép thông tin hệ thống": ("Copy system info", S),
    "Hỗ trợ & báo lỗi": ("Support & bug reports", S),
    "XFinder không tự gửi gì đi. Báo cáo lỗi chỉ rời máy khi bạn tự sao chép, lưu hoặc dán nó — sau khi đã đọc toàn bộ.":
        ("XFinder sends nothing by itself. A bug report leaves this Mac only when you copy, save or paste it — after reading all of it.", S),
    "Đã sao chép thông tin hệ thống.": ("System info copied.", S),
    "Ghi lỗi kỹ thuật của XFinder trên máy này": ("Keep a technical error log on this Mac", S),
    "Chỉ mã lỗi, phiên bản và crash của chính XFinder — không tên tệp, không nội dung clipboard, không tên cửa sổ hay tài khoản. Lưu trên máy, không bao giờ tự gửi.":
        ("Only error codes, versions and XFinder's own crashes — no file names, no clipboard content, no window titles or accounts. Stored on this Mac, never sent by itself.", S),
    "Xoá nhật ký": ("Clear log", S),
    "Đã xoá nhật ký chẩn đoán.": ("Diagnostic log cleared.", S),
    "Đây là toàn bộ nội dung sẽ được chia sẻ. Đọc trước, bớt dòng nào tuỳ bạn sau khi dán.":
        ("This is everything that would be shared. Read it first; remove any line you like after pasting.", S),
    "Đã sao chép báo cáo.": ("Report copied.", S),
    "Lưu tệp…": ("Save as file…", S),
    "Đã lưu báo cáo.": ("Report saved.", S),
    "Mở GitHub Issues": ("Open GitHub Issues", S),
    "Đã sao chép báo cáo — dán vào ô mô tả trên GitHub.": ("Report copied — paste it into the description on GitHub.", S),
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
