#!/usr/bin/env python3
"""P13 (2026-10-14) — one "Theo dõi hệ thống" page with tabs; fixes for pages that only looked finished. ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "Theo dõi hệ thống": ("System Monitor", S),
    "Máy Mac đang chạy thế nào: bộ xử lý, bộ nhớ, mạng, ổ đĩa và pin.": ("How this Mac is doing: processor, memory, network, storage and battery.", S),
    # The menu-bar menu (a plain NSMenu since P13) and the readouts section that moved to Tổng quan.
    "Mở Clipboard trên notch": ("Open Clipboard on the notch", S),
    "Cài đặt…": ("Settings…", S),
    "Kiểm tra cập nhật…": ("Check for Updates…", S),
    "Khởi động lại XFinder": ("Restart XFinder", S),
    "Hiện số liệu cạnh biểu tượng": ("Show figures beside the icon", S),
    "CPU, bộ nhớ, nhiệt độ… hiện cạnh biểu tượng XFinder; chọn số liệu ở trang Tổng quan.": ("CPU, memory, temperature… beside the XFinder icon; pick the figures on the Overview page.", S),
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
