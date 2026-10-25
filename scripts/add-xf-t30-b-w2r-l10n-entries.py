#!/usr/bin/env python3
"""XF-T30 W2 builder w2r — DirectoryReader/FileMetadataCache (2026-10-25). ADD-ONLY: a key already present with
another meaning is a CONFLICT. This builder's two files (getattrlistbulk Date Added + background Finder
tags/Date Last Opened/app name reader) introduce no user-visible strings, so ENTRIES is empty — kept only so the
integrator has one script per builder to run, per contract format."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {}
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
