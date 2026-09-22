#!/usr/bin/env python3
"""Add the Finder-extension status strings to the L10n store.

Written as a script for the same reason as `add-gesture-l10n-entries.py`: the
store is generated, `scope` drives `check-l10n-reachability`, and re-running must
change nothing. A hand edit is how a wrong `scope` (or a missing English value)
sneaks in and makes the whole checker lie.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

# Vietnamese key -> (English, scope)
ENTRIES: dict[str, tuple[str, str]] = {
    # --- Measured extension states -------------------------------------------
    "Chưa bật": ("Not enabled yet", "sentence"),
    "Bạn đã tắt": ("You turned it off", "sentence"),
    "Không xác định": ("Unknown", "sentence"),

    # --- One sentence per state, each naming the next action ------------------
    "XFinder đã kèm phần mở rộng Finder và macOS đang bật nó: bấm chuột phải vào tập tin trong Finder sẽ thấy mục “Thêm vào Khay thả XFinder” và nút trên thanh công cụ.":
        ("XFinder ships a Finder extension and macOS has it enabled: right-click a file in "
         "Finder to see “Add to XFinder Drop Tray”, plus a toolbar button.", "sentence"),
    "Phần mở rộng đã cài nhưng đang bị tắt trong Cài đặt hệ thống, nên Finder không hiện mục của XFinder. Bật lại theo hướng dẫn bên dưới.":
        ("The extension is installed but switched off in System Settings, so Finder does not "
         "show XFinder's menu item. Turn it back on using the steps below.", "sentence"),
    "Phần mở rộng đã cài và macOS đã biết nó, nhưng chưa bật — mặc định của mọi tiện ích mới. Bật theo hướng dẫn bên dưới để Finder hiện mục của XFinder.":
        ("The extension is installed and macOS knows about it, but it is not enabled yet — "
         "the default for any new extension. Enable it with the steps below so Finder shows "
         "XFinder's menu item.", "sentence"),
    "macOS chưa thấy phần mở rộng Finder của XFinder. Hãy cài bản dựng mới nhất, rồi bật theo hướng dẫn bên dưới.":
        ("macOS cannot see XFinder's Finder extension. Install the latest build, then enable "
         "it with the steps below.", "sentence"),
    "Chưa đọc được trạng thái phần mở rộng từ macOS. Bấm “Kiểm tra lại” sau khi mở trang cài đặt bên dưới.":
        ("Could not read the extension's state from macOS. Open the settings page below, then "
         "press “Check again”.", "sentence"),
}

# Superseded: the page used to assert this unconditionally, which became untrue
# once the appex actually registered. A stale key is a failure in this store.
REMOVED = [
    "Menu chuột phải và Tác vụ nhanh của Finder cần một Finder Extension riêng. "
    "XFinder chưa kèm phần mở rộng đó, nên mục này báo đúng trạng thái thay vì hiện "
    "một công tắc không có tác dụng.",
]


def main() -> int:
    doc = json.loads(STORE.read_text(encoding="utf-8"))
    entries = doc["entries"]
    before = len(entries)

    added = replaced = removed = 0
    for key, (en, scope) in ENTRIES.items():
        if key in entries:
            if entries[key].get("en") != en or entries[key].get("scope") != scope:
                entries[key] = {"en": en, "scope": scope}
                replaced += 1
        else:
            entries[key] = {"en": en, "scope": scope}
            added += 1

    for key in REMOVED:
        if key in entries:
            del entries[key]
            removed += 1

    doc["entries"] = dict(sorted(entries.items()))
    STORE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"entries {before} -> {len(doc['entries'])}  "
          f"(added {added}, replaced {replaced}, removed {removed})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
