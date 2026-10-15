#!/usr/bin/env python3
"""HUD suppression + brightness HUD (owner's request, 2026-10-15): the notch's brightness readout, and the
switch that stops macOS drawing its own brightness/volume square beside it.

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that exists with different English stops the
script and writes nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # the notch's own brightness readout (LiveActivity.brightnessItem + the Hoạt động trực tiếp row)
    "Độ sáng": ("Brightness", S),
    "Mức âm lượng thật từ CoreAudio, hiện trên notch.":
        ("The real volume level from CoreAudio, shown on the notch.", S),
    "Mức độ sáng thật của màn hình trong, hiện trên notch khi bạn bấm phím độ sáng. Chỉ có khi bật “Chỉ dùng notch cho độ sáng và âm lượng” bên dưới.":
        ("The real brightness of the built-in display, shown on the notch when you press the brightness keys. Only while “Use the notch only for brightness and volume” below is on.", S),
    # the "hide macOS's own square" section
    "Hộp điều chỉnh của macOS": ("macOS's own brightness and volume square", S),
    "Chỉ dùng notch cho độ sáng và âm lượng": ("Use the notch only for brightness and volume", S),
    "XFinder tự nhận phím độ sáng và âm lượng rồi đặt giá trị, nên macOS không hiện hộp vuông riêng nữa.":
        ("XFinder takes the brightness and volume keys over and sets the values itself, so macOS no longer draws its own square.", S),
    "Khi tắt, macOS vẫn hiện hộp vuông của nó như trước. Phím bấm kèm ⌥, ⇧, ⌃ hoặc ⌘, và loa không cho chỉnh âm lượng, vẫn để macOS xử lý.":
        ("With this off, macOS keeps drawing its own square as before. Keys pressed with ⌥, ⇧, ⌃ or ⌘, and outputs whose volume cannot be set, are still left to macOS.", S),
    "Cần quyền Trợ năng để XFinder nhận được phím độ sáng và âm lượng.":
        ("Accessibility is required for XFinder to receive the brightness and volume keys.", S),
    # 2026-10-15: the takeover is on by default and part of the "Hằng ngày" onboarding preset
    "Thêm khay ⌘⇧V, xem trước Dock, vùng bắt dính, và độ sáng/âm lượng chỉ hiện trên notch.":
        ("Adds the ⌘⇧V shelf, the Dock preview, snap zones, and brightness/volume shown only on the notch.", S),
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
