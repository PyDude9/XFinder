#!/usr/bin/env python3
"""XF-T26 scrolling capture (2026-10-22). ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Chụp cuộn": ("Scrolling capture", S),
    "Chọn một vùng rồi cuộn — XFinder ghép thành một ảnh dài": ("Pick an area and scroll — XFinder stitches it into one long image", S),
    "Chọn vùng ít nhất 48 × 48 điểm.": ("Choose an area at least 48 × 48 points.", S),
    "Kéo để chọn vùng sẽ cuộn · Esc để huỷ": ("Drag to choose the area to scroll · Esc to cancel", S),
    "Không chụp được vùng này.": ("This area could not be captured.", S),
    "Đã đến cuối trang.": ("Reached the end of the page.", S),
    "Đã đến giới hạn chiều cao.": ("Reached the height limit.", S),
    "Không ghép được đoạn mới — cuộn ngược lên một chút.": ("Lost the place — scroll back up a little.", S),
    "Không ghép được ảnh chụp cuộn.": ("The scrolling capture could not be stitched.", S),
    "Đang ghép ảnh…": ("Stitching…", S),
    "Cuộn trong vùng để chụp tiếp": ("Scroll inside the area to keep capturing", S),
    "Enter: xong · Esc: huỷ": ("Enter: done · Esc: cancel", S),
    "Dừng tự cuộn": ("Stop auto-scroll", S),
    "Tự cuộn": ("Auto-scroll", S),
    "XFinder tự cuộn xuống tới cuối trang.": ("XFinder scrolls down to the end of the page by itself.", S),
    "Cần quyền Trợ năng để tự cuộn.": ("Auto-scroll needs the Accessibility permission.", S),
    "Xong": ("Done", S),
    "Huỷ": ("Cancel", S),
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
