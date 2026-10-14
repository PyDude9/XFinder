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
    # Merged pages (owner: "gộp cái nào duplicates") — tab labels and the rows' shared subtitles.
    # The sidebar page that hides OTHER apps' icons and the Tổng quan row that picks XFinder's own glyph shared one
    # title ("Biểu tượng thanh menu" / "Menu Bar Icons") while doing different jobs.
    "Ẩn biểu tượng thanh menu": ("Hide Menu Bar Icons", S),
    "Biểu tượng XFinder trên thanh menu": ("XFinder's menu bar icon", S),
    "Trợ năng và Ghi màn hình": ("Accessibility and Screen Recording", S),
    "Thiếu Trợ năng": ("Missing Accessibility", S),
    "Thiếu Ghi màn hình": ("Missing Screen Recording", S),
    "Xem tab Quyền": ("Open Permissions", S),
    # The four-corner tile of the notch layout row, and the card-scroll haptic (2026-10-14).
    "Bốn góc": ("Four corners", S),
    "Rung nhẹ khi lướt qua các thẻ": ("Tap lightly while scrolling through cards", S),
    "Mỗi thẻ lướt qua ở notch hoặc khay nổi là một nhịp rung. Chỉ trackpad Force Touch, và chỉ cảm nhận được khi ngón tay đang trên trackpad.": ("Each card that scrolls past at the notch or in the floating shelf is one tap. Force Touch trackpads only, and you feel it only with a finger on the trackpad.", S),
    "Xem trước file": ("File preview", S),
    "Hỗ trợ đa phương tiện": ("Media support", S),
    "Xem trước Markdown và file nén mà không cần mở; kiểm tra file media có phát được trên máy này không.": ("Preview Markdown and archives without opening them; check whether a media file plays on this Mac.", S),
    "Tìm ứng dụng, liên kết và tập tin: lọc theo tên, loại, thời gian, hoặc gõ một câu tự nhiên — 100% trên máy.": ("Find apps, links and files: filter by name, kind and date, or type one plain sentence — 100% on this Mac.", S),
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
