#!/usr/bin/env python3
"""XF-T30 W5a builder "engine" (FilenameIndex/DirectoryReader/DirectoryEntry, 2026-10-25). ADD-ONLY: a key already
present with another meaning is a CONFLICT. No new user-visible strings were needed for this builder's work
(wal_checkpoint, parent_id folder table, exact B-tree lookup, FTS5 columnsize=0, batched crawl, real inodes are all
internal mechanics with no new UI surface) — ENTRIES is empty on purpose, kept in the same add-only shape as every
other XF-T30 builder script so a future addition only needs to extend this file."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
}
def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); e = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in e and e[k].get("en") != en]
    for k in bad: print(f"CONFLICT: {k!r} = {e[k].get('en')!r}")
    if bad: return 1
    added = sum(1 for k in ENTRIES if k not in e)
    for k, (en, sc) in ENTRIES.items(): e.setdefault(k, {"en": en, "scope": sc})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}"); return 0
if __name__ == "__main__": sys.exit(main())
