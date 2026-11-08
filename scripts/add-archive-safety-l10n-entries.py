#!/usr/bin/env python3
"""XF-MFGAP-03 stage 03B — register the archive-refusal sentences in the L10n store.

ADD-ONLY, like add-cleanup-l10n-entries.py: an existing key is never rewritten; a key that exists with a
different English text stops the script (CONFLICT, nothing written). `ArchiveRunner.Failure.messageKey`
reaches the screen through `L10n.t(variable)`, so
`ArchiveEngineTests.testEveryFailureMessageKeyIsInTheStore` resolves every one of them.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    "Tệp nén không an toàn nên đã bị từ chối, chưa ghi gì: ":
        ("This archive is not safe, so it was refused and nothing was written: ", F),
    "Không đủ dung lượng để giải nén tệp này.":
        ("There is not enough free space to extract this archive.", S),
    "Tệp nén đã thay đổi trong lúc kiểm tra nên đã dừng, chưa đặt gì.":
        ("The archive changed while it was being checked, so it stopped and nothing was placed.", S),
    "Không kiểm tra được tệp nén trên máy này nên đã từ chối, chưa giải nén gì.":
        ("This archive cannot be checked on this Mac, so it was refused and nothing was extracted.", S),
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
