#!/usr/bin/env python3
"""T14 — rebuild the Mouse & Gestures page in variant B (docs/specs/T14-mouse-gestures-B.md).

One add-only script for the whole T14 series: each step (T14a…T14f) appends the entries its own
step introduces and runs this script, so no `L10n.t("…")` ever waits for the store to catch up.

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that already exists with a
different English stops the script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # T14a — the status line's recording state (Khối 2, variant-b.html line 107)
    "Đang ghi — bấm nút trên chuột (Esc để hủy).":
        ("Recording — press a button on the mouse (Esc to cancel).", S),
    # T14a review — the same line while a keyboard shortcut is being recorded for a direction,
    # and the header switch's VoiceOver label
    "Đang ghi phím tắt — bấm tổ hợp phím trên bàn phím (Esc để hủy).":
        ("Recording a shortcut — press the key combination on the keyboard (Esc to cancel).", S),
    "Bật/tắt cử chỉ": ("Turn gestures on or off", S),
    # T14b — block 3's chip strip: the trailing "＋" chip and a preset the user has not installed
    "Thêm ứng dụng khác bằng Bundle ID": ("Add another app by bundle ID", S),
    "Chưa cài — đang xem preset dựng sẵn": ("Not installed — viewing its built-in preset", S),
    # T14c — block 4: button inspector (F8/F15) and 4-direction summary
    "Đây là nút giữ hiện tại": ("This is the current hold button", S),
    "Nút giữ cử chỉ hiện tại là ": ("The current gesture hold button is ", F),
    "Dùng làm nút giữ": ("Use as hold button", S),
    "Bấm nhanh": ("Quick click", S),
    # T14d — blocks 5 (side buttons), 6 (hold & scroll), 7 (tilt)
    "Nút hông": ("Side buttons", F),
    "Chưa đọc được nút nào": ("No buttons detected", S),
    "Cắm chuột có nút hông để xem và gán ở đây.":
        ("Connect a mouse with side buttons to view and assign them here.", S),
    "Bấm “Ghi nút” ở mục Nút giữ & cuộn rồi bấm nút này để XFinder đo.":
        ("Click “Record button” in the Hold & Scroll section, then click this button for XFinder to measure.", S),
    "Chưa khai báo": ("Undeclared", F),
    "Đổi nút giữ: bấm vào một ô nút trên hình phía trên.":
        ("Change hold button: click a button chip on the diagram above.", S),
    "Nút giữ & cuộn": ("Hold & scroll buttons", S),
    "Giữ nút này rồi kéo bốn hướng. Bấm chip trên hình bên trên để đổi.":
        ("Hold this button then drag four directions. Click a chip on the diagram above to change.", S),
    "Nghiêng con lăn": ("Tilt wheel", F),
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
