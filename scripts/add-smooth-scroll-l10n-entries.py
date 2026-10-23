#!/usr/bin/env python3
"""XF-T25 smooth mouse scrolling (2026-10-22). ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    "Cuộn chuột mượt": ("Smooth mouse scrolling", S),
    "Bánh xe chuột trôi như trackpad; trackpad và Magic Mouse giữ nguyên.":
        ("The mouse wheel glides like a trackpad; the trackpad and the Magic Mouse stay as they are.", S),
    "Chỉ bánh xe chuột được làm mượt. Trackpad và Magic Mouse giữ nguyên cách cuộn của macOS.":
        ("Only the mouse wheel is smoothed. The trackpad and the Magic Mouse keep macOS's own scrolling.", S),
    "Làm mượt bánh xe chuột": ("Smooth the mouse wheel", S),
    "Bánh xe trôi như trackpad thay vì nhảy từng nấc.": ("The wheel glides like a trackpad instead of jumping notch by notch.", S),
    "Tốc độ": ("Speed", S),
    "Quãng cuộn của mỗi nấc bánh xe.": ("How far each wheel notch scrolls.", S),
    "Độ mượt": ("Smoothness", S),
    "Thời gian dàn một nấc ra thành chuyển động — cao hơn là trôi lâu hơn.":
        ("How long one notch is spread over — higher glides longer.", S),
    "Đảo chiều bánh xe": ("Reverse the wheel", S),
    "Chỉ áp cho chuột. Trackpad giữ cài đặt Cuộn tự nhiên của macOS.":
        ("Mouse only. The trackpad keeps macOS's Natural scrolling setting.", S),
    "Khôi phục mặc định": ("Restore defaults", S),
    "Đang tắt — bánh xe cuộn như macOS gốc.": ("Off — the wheel scrolls as plain macOS does.", S),
    "Đang làm mượt bánh xe chuột.": ("Smoothing the mouse wheel.", S),
    "Cần quyền Trợ năng để đọc bánh xe chuột.": ("Needs the Accessibility permission to read the mouse wheel.", S),
    "Đang tạm dừng: ": ("Paused: ", F),
    " cũng làm mượt cuộn — tắt một trong hai.": (" also smooths scrolling — turn one of them off.", F),
    "Đang tạm dừng trong lúc chụp cuộn.": ("Paused during a scrolling capture.", S),
    "Lần cuộn vừa rồi: bánh xe chuột — đã làm mượt.": ("Last scroll: mouse wheel — smoothed.", S),
    "Lần cuộn vừa rồi: trackpad hoặc Magic Mouse — giữ nguyên.": ("Last scroll: trackpad or Magic Mouse — left as is.", S),
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
