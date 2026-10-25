#!/usr/bin/env python3
"""XF-T30 W2 builder "b-w2i" — FileIconView/FileColumnView/FileGalleryView (2026-10-25). ADD-ONLY: a key already
present with another meaning is a CONFLICT.

No new strings: every user-visible label this builder's three files show (group-section headers, the "…" context
menu it builds through `BrowserContextMenu.menu(for:pane:)`) comes from keys other W2 files already own —
`GroupBy.titleKey` (seeded by `add-xf-t30-w1-l10n-entries.py`), `TagColor.titleKey`/`BrowserCommand` titles (the
context-menu builder's own file). This script exists so the integrator has one script per builder to run, same as
every other XF-T30 W2/W3 builder.
"""
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
