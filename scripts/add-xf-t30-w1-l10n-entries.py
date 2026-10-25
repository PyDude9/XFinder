#!/usr/bin/env python3
"""XF-T30 W1 — pane tabs, window tabs, toolbar, bars (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Builders append the keys their views need to ENTRIES (one key, one meaning)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # BrowserCommands.titleKey (reach the screen through L10n.t(variable) — BrowserVocabularyL10nTests)
    "Tab cửa sổ mới": ("New Window Tab", S),
    "Tab ngăn mới": ("New Pane Tab", S),
    "Tab ngăn kế tiếp": ("Next Pane Tab", S),
    "Tab ngăn trước": ("Previous Pane Tab", S),
    "Đóng tab ngăn": ("Close Pane Tab", S),
    "Chuyển tab sang ngăn kế": ("Move Tab to Next Pane", S),
    "Chuyển tab sang ngăn mới bên phải": ("Move Tab to New Pane on Right", S),
    "Chuyển tab sang ngăn mới bên dưới": ("Move Tab to New Pane Below", S),
    "Đổi chỗ với ngăn kế": ("Swap with Next Pane", S),
    "Chuyển tab ra cửa sổ mới": ("Move Tab to Window", S),
    "Ngăn bên trái": ("Pane on Left", S),
    "Ngăn bên phải": ("Pane on Right", S),
    "Ngăn phía trên": ("Pane Above", S),
    "Ngăn phía dưới": ("Pane Below", S),
    "Làm ngăn rộng hơn": ("Make Pane Wider", S),
    "Làm ngăn hẹp hơn": ("Make Pane Narrower", S),
    "Làm ngăn cao hơn": ("Make Pane Taller", S),
    "Làm ngăn thấp hơn": ("Make Pane Shorter", S),
    "Hiện hoặc ẩn thanh vị trí": ("Show or Hide Location Bar", S),
    "Hiện hoặc ẩn thanh đường dẫn": ("Show or Hide Path Bar", S),
    "Hiện hoặc ẩn thanh trạng thái": ("Show or Hide Status Bar", S),
    "Hiện hoặc ẩn thanh công cụ": ("Show or Hide Toolbar", S),
    "Tuỳ biến thanh công cụ…": ("Customize Toolbar…", S),
    "Hiện hoặc ẩn sidebar": ("Show or Hide Sidebar", S),
    "Mở trong tab mới": ("Open in New Tab", S),
    "Mở trong cửa sổ mới": ("Open in New Window", S),
    "Dùng nhóm": ("Use Groups", S),
    # GroupBy.titleKey
    "Không nhóm": ("None", S),
    "Tên": ("Name", S),
    "Loại": ("Kind", S),
    "Ứng dụng": ("Application", S),
    "Ngày mở gần nhất": ("Date Last Opened", S),
    "Ngày thêm": ("Date Added", S),
    "Ngày sửa": ("Date Modified", S),
    "Ngày tạo": ("Date Created", S),
    "Cỡ": ("Size", S),
    "Các thẻ": ("Tags", S),
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
