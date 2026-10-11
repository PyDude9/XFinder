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
