#!/usr/bin/env python3
"""XF-T30 W1 builder "pure" (2026-10-25). ADD-ONLY: a key already present with another meaning is a CONFLICT.

No new user-visible vocabulary: this builder only implements the pure rules behind PaneTabList, PaneTabRules,
PaneTree.neighbor/resize/currentPreset, PaneHistory.goBack/goForward(steps:), and BrowserWorkspace's v2 session
restore — all the `BrowserCommand`/`GroupBy` titleKey strings these touch were already registered by
scripts/add-xf-t30-w1-l10n-entries.py (the W1 contract's integrator script). Kept as an empty, add-only stub in the
same shape so a later commit on this branch has somewhere to add a key without inventing a new script.
"""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # (no new keys from this builder)
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
