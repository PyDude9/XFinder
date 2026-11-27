#!/usr/bin/env python3
"""XF-T41 — the notch's Drop Tray takes over the browser Shelf: copy / move its items into the browser's active pane.
ADD-ONLY. Idempotent: an existing key is never rewritten; a key that exists with different English stops the script.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    "Chép vào ngăn: ": ("Copy to pane: ", F),
    "Chuyển vào ngăn: ": ("Move to pane: ", F),
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
