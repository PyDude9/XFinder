#!/usr/bin/env python3
"""XF-T30 W1 builder "chrome" — NSToolbar/NSWindow/main-menu strings not already covered by
scripts/add-xf-t30-w1-l10n-entries.py (2026-10-25). ADD-ONLY: a key already present with another meaning is a
CONFLICT. Run to test; `git checkout -- XFinder/Resources/L10n.strings.json` before committing (the integrator
runs every L10n script together)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # BrowserToolbarController: Pane Layout button label/tooltip, Action menu button ("…"), Workspaces menu button.
    "Bố cục ngăn": ("Pane Layout", S),
    "Thao tác": ("Action", S),
    "Các Workspace": ("Workspaces", S),
    # BrowserMainMenu: the synthetic top-level "Go" menu (Q-T30-13).
    "Đi": ("Go", S),
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
