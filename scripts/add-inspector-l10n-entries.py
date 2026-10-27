#!/usr/bin/env python3
"""Learn lessons: idempotent ADD-ONLY translations; refuses conflicting existing keys."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {'Tệp văn bản trống.': ('Text file is empty.', 'sentence'), 'Nội dung Inspector': ('Inspector content', 'sentence'), 'Tệp văn bản quá lớn để xem trước (tối đa 256 KiB).': ('Text file is too large to preview (256 KiB maximum).', 'sentence'), 'Chỉ xem trước văn bản UTF-8 không chứa dữ liệu nhị phân.': ('Only UTF-8 text without binary data can be previewed.', 'sentence'), 'Không đọc được nội dung tệp.': ('Unable to read file contents.', 'sentence')}

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
