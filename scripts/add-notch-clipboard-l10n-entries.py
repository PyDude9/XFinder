#!/usr/bin/env python3
"""D0 — the ⌘⇧V shelf consolidated into the notch: register the page's new strings in the L10n store.

Idempotent: re-running changes nothing. Every string here is a literal that reaches the screen through
`L10n.t("…")` in NotchClipboardView / NotchClipCardView / SettingsDetailView / NotchSurfaceController.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

ENTRIES: dict[str, tuple[str, str]] = {
    # Settings — one picker, one key
    "⌘⇧V mở ở": ("⌘⇧V opens in", "sentence"),
    "Ở notch": ("At the notch", "sentence"),
    "Khay nổi cũ": ("Old floating shelf", "sentence"),
    "Lịch sử copy mở bằng ⌘⇧V, ở notch hoặc khay nổi.": ("Copy history opens with ⌘⇧V, at the notch or in the floating shelf.", "sentence"),
    "⌘⇧V mở clipboard trên mọi ứng dụng": ("⌘⇧V opens the clipboard over any app", "sentence"),
    "Mở clipboard (⌘⇧V)": ("Open clipboard (⌘⇧V)", "sentence"),
    # Notch page
    "↩ dán · ⇧↩ thuần · Space xem · ⌘P ghim · ⌘⌫ xoá · ⌘1–9 bảng": ("↩ paste · ⇧↩ plain · Space view · ⌘P pin · ⌘⌫ delete · ⌘1–9 boards", "sentence"),
    "Chưa có Trợ năng: ↩ chỉ sao chép, dán bằng ⌘V.": ("No Accessibility yet: ↩ only copies, paste with ⌘V.", "sentence"),
    "Mục này không có tệp để xem nhanh.": ("This item has no file to Quick Look.", "sentence"),
    "Đi tới nguồn": ("Go to source", "sentence"),
    # Card footer age — the existing " phút" fragment means " min LEFT" (the notch timer), so the
    # clip age gets its own unit words, joined to the number by the view.
    "Vừa xong": ("Just now", "sentence"),
    "phút": ("min", "fragment"),
    "giờ": ("h", "fragment"),
    "ngày": ("d", "fragment"),
    # History limit (user: 20 · 100 · 1000)
    "20 mục": ("20 items", "sentence"),
    "100 mục": ("100 items", "sentence"),
    # D0c: plain screens get a virtual notch at the top edge (B7 hung the surfaces under the menu bar)
    "Trên màn hình không có notch, XFinder vẽ một notch ảo: các bề mặt dính mép trên, ở giữa thanh menu, y như ở notch thật; rê chuột vào giữa mép trên để xem các tệp đang giữ.": ("On a screen without a notch XFinder draws a virtual one: the surfaces sit flush with the top edge, centred in the menu bar, exactly as at a real notch; rest the pointer on the middle of the top edge to see the files you are holding.", "sentence"),
    "Màn hình ngoài / iMac: tệp đang giữ, hẹn giờ và bài đang phát hiện trong một viên thuốc nhỏ dính mép trên, giữa thanh menu. Chưa đo trên màn hình thật — chỉ hình học.": ("External display / iMac: held files, the timer and the playing track show in a small pill flush with the top edge, centred in the menu bar. Not measured on a real display yet — geometry only.", "sentence"),
    # D1 quick wins
    "Tạm dừng ghi clipboard": ("Pause clipboard recording", "sentence"),
    "Không ghi gì vào lịch sử cho tới khi bật lại. ⌘⇧V vẫn mở được; trang notch báo đang tạm dừng.": ("Nothing is recorded until you turn this off. ⌘⇧V still opens; the notch page says recording is paused.", "sentence"),
    "Đang tạm dừng ghi clipboard.": ("Clipboard recording is paused.", "sentence"),
    "Âm sao chép": ("Copy sound", "sentence"),
    "Sửa văn bản…": ("Edit text…", "sentence"),
    "Sửa văn bản": ("Edit text", "sentence"),
    "Phát âm": ("Speak", "sentence"),
    "Dừng phát âm": ("Stop speaking", "sentence"),
    "Ghim khay (không đóng khi bấm ra ngoài)": ("Pin the shelf (stays open when you click outside)", "sentence"),
    "Bỏ ghim khay": ("Unpin the shelf", "sentence"),
}


def main() -> None:
    with open(STORE, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = data.get("entries", data)
    added = updated = 0
    for vi, (en, scope) in ENTRIES.items():
        cur = entries.get(vi)
        if cur is None:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        elif cur.get("en") != en or cur.get("scope") != scope:
            cur["en"], cur["scope"] = en, scope
            updated += 1
    with open(STORE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Added {added}, updated {updated} entries. Total in store: {len(entries)}")


if __name__ == "__main__":
    main()
