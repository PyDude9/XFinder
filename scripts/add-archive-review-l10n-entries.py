#!/usr/bin/env python3
"""Boss review of XF-MFGAP-03 stage 03C: one sentence reworded. ADD-ONLY.

The Merge option's help said "Khi nén: tệp nén cũ không bao giờ bị ghi thêm, bản mới được giữ cả hai" — the last
clause does not parse ("the new copy is kept both"), and the key held escaped straight quotes (CLAUDE.md rule 8 forbids
`\"` in a key). What compression actually does with Merge is Keep Both: the new archive gets a numbered name. The old
key stays in the store (add-only); the call site moves to this one.

Idempotent: an existing key is never rewritten; a key that exists with different English stops the script and writes
nothing.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES: dict[str, tuple[str, str]] = {
    "Gộp thư mục, giữ cả hai file trùng: thư mục được gộp vào nhau, file trùng tên được đánh số (“Report 2.pdf”) "
    "nên không file nào bị thay. Khi nén: không ghi thêm vào tệp nén cũ — tệp nén mới được đánh số.": (
        "Merge folders, keep both copies of same-named files: folders combine and same-named files are numbered "
        "(“Report 2.pdf”), so nothing is replaced. When compressing: the old archive is never appended to — the new "
        "archive gets a numbered name.", S),
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
