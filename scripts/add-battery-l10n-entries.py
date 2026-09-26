#!/usr/bin/env python3
"""Add the Battery Hub strings to the L10n store."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

ENTRIES: dict[str, tuple[str, str]] = {
    "Thiết bị đã kết nối": ("Connected Devices", "sentence"),
    "Đã kết nối": ("Connected", "sentence"),
    "Đã ngắt kết nối": ("Disconnected", "sentence"),
    "Chưa có thiết bị kết nối": ("No connected devices", "sentence"),
    "Hỗ trợ AirPods, chuột, bàn phím Bluetooth/HID": ("Supports AirPods, Bluetooth & HID mouse/keyboard", "sentence"),
    "Chế độ thẻ lớn": ("Large card mode", "sentence"),
    "Chế độ lưới": ("Grid mode", "sentence"),
    "Làm mới pin": ("Refresh battery", "sentence"),
    "Pin thiết bị": ("Device Battery", "sentence"),
}

def main() -> None:
    with open(STORE, "r", encoding="utf-8") as f:
        data = json.load(f)

    entries = data.get("entries", data)
    added = 0
    updated = 0
    for vi, (en, scope) in ENTRIES.items():
        if vi not in entries:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        else:
            if entries[vi].get("en") != en or entries[vi].get("scope") != scope:
                entries[vi]["en"] = en
                entries[vi]["scope"] = scope
                updated += 1

    with open(STORE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Added {added}, updated {updated} entries. Total in store: {len(entries)}")

if __name__ == "__main__":
    main()
