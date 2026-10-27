#!/usr/bin/env python3
"""XF-T32 W3 `chrome` unit (contract XF-T32-w23 §G) — related-items strip, folder menu button, pane focus picker.

Idempotent, ADD-ONLY (same contract as add-calendar13-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    "Thêm mục liên quan": ("Add related items", S),
    "Bỏ liên kết": ("Unlink", S),
    "Tuỳ chọn thư mục": ("Folder options", S),
    "Chọn thư mục liên quan tới thư mục này.": ("Choose folders related to this folder.", S),
    "Làm nổi ngăn đang dùng": ("Highlight the active pane", S),
    "Làm mờ ngăn khác": ("Dim other panes", S),
    "Viền ngăn đang dùng": ("Outline the active pane", S),
}

def main() -> None:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data.get("entries", data)
    added, conflicts = 0, []
    for vi, (en, scope) in ENTRIES.items():
        cur = entries.get(vi)
        if cur is None:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        elif cur.get("en") != en or cur.get("scope") != scope:
            conflicts.append((vi, cur, en, scope))
    if conflicts:
        for vi, cur, en, scope in conflicts:
            print(f"CONFLICT {vi!r}: store has {cur!r}, script wants {{'en': {en!r}, 'scope': {scope!r}}}")
        print("Nothing written."); sys.exit(1)
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Added {added} entries (0 rewritten). Total in store: {len(entries)}")

if __name__ == "__main__":
    main()
