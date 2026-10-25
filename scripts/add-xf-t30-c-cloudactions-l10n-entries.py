#!/usr/bin/env python3
"""XF-T30 W8 cloud actions (builder "cloudactions", 2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Run then `git checkout -- XFinder/Resources/L10n.strings.json` before committing."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # BrowserWindowModel+Cloud.swift — Google Drive trash confirmation (NSAlert)
    "Bạn có chắc muốn xoá mục này khỏi Google Drive?": ("Are you sure you want to remove this item from Google Drive?", S),
    "Bạn có chắc muốn xoá các mục này khỏi Google Drive?": ("Are you sure you want to remove these items from Google Drive?", S),
    "Mục này cũng sẽ chuyển vào thùng rác của Google Drive, không chỉ Thùng rác trên máy.": (
        "This also moves the item into Google Drive's own trash, not just the Trash on this Mac.", S),
    "Chuyển vào Thùng rác": ("Move to Trash", S),
    "Một số mục chỉ có trên đám mây — bấm \"Tải về ngay\" trước khi chép ra ngoài": (
        "Some items are cloud-only — click \"Download Now\" before copying them out", S),

    # BrowserSettingsWindow.swift — CloudSettingsTab (per-provider status, contract §4)
    "Nhà cung cấp đám mây khác": ("Other Cloud Providers", S),
    "Chưa phát hiện nhà cung cấp đám mây nào khác.": ("No other cloud providers detected.", S),
    "Tải ": ("Download ", F),
    "…": ("…", F),
    "Mở ": ("Open ", F),
    "Hiện": ("Show", S),
    "Ẩn trong XFinder": ("Hide in XFinder", S),
    "Kiểm lại": ("Check Again", S),
    " chưa được cài.": (" isn't installed.", F),
    "đang chạy": ("running", F),
    "chưa chạy": ("not running", F),
    " đã cài, ": (" is installed, ", F),
    ", chưa thấy thư mục đồng bộ.": (", no synced folder found yet.", F),
    " — ": (" — ", F),
    " (đang ẩn trong XFinder)": (" (hidden in XFinder)", F),
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
