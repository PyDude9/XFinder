#!/usr/bin/env python3
"""XF-T36B fullscreen policy Settings copy. ADD-ONLY."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES = {
    "Luôn hiện notch": ("Always show notch", S),
    "Ẩn trong ứng dụng toàn màn hình": ("Hide in fullscreen apps", S),
    "Chỉ ẩn khi xem media toàn màn hình": ("Hide only for fullscreen media", S),
    "Notch khi ứng dụng toàn màn hình": ("Notch in fullscreen apps", S),
    "XFinder chỉ ẩn notch khi nhận diện được cửa sổ phủ khớp màn hình. Nếu không xác định chắc chắn, notch vẫn hiện. Thao tác đang chạy, yêu cầu duyệt và khung nhập luôn được giữ trên màn hình.":
        ("XFinder hides the notch only when it identifies a window matching the display. If uncertain, the notch stays visible. Running tasks, approval requests, and composers remain visible.", S),
    "Hiển thị notch trong ứng dụng toàn màn hình": ("Show notch in fullscreen apps", S),
    "Chế độ chỉ ẩn theo media cần ứng dụng phát nhạc/video cung cấp trạng thái Now Playing đang chạy.":
        ("Media-only hiding requires a playing Now Playing status from the app playing the audio or video.", S),
}

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); entries = data["entries"]
    conflicts = [(k, entries[k], en, scope) for k, (en, scope) in ENTRIES.items()
                 if k in entries and entries[k] != {"en": en, "scope": scope}]
    if conflicts:
        for key, current, en, scope in conflicts:
            print(f"CONFLICT {key!r}: {current!r}, wanted en={en!r} scope={scope!r}")
        return 1
    added = sum(key not in entries for key in ENTRIES)
    for key, (en, scope) in ENTRIES.items():
        entries.setdefault(key, {"en": en, "scope": scope})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
