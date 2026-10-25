#!/usr/bin/env python3
"""XF-T30 W3 builder "w3g" (BrowserWindowModel+Go, VirtualLocations, BrowserMainMenu Go menu) — new strings not
already covered by an earlier XF-T30 L10n script (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Run to test; `git checkout -- XFinder/Resources/L10n.strings.json` before committing (the
integrator runs every L10n script together)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # BrowserMainMenu: the Go menu's "Recent Folders" submenu title and its empty-state placeholder.
    "Thư mục gần đây": ("Recent Folders", S),
    "Không có thư mục nào": ("No Folders", S),
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
