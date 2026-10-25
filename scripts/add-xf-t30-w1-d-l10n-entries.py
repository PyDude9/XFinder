#!/usr/bin/env python3
"""XF-T30 W1 builder "views" — pane tab strip + status bar strings not already seeded by the base L10n script
(2026-10-25). ADD-ONLY: a key already present with another meaning is a CONFLICT."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # PaneTabStripView: trailing + / split-right / split-down buttons' tooltips, and the "Close Other Tabs" menu item
    # (contract §4's context menu list — "Đóng tab" and the three move-to-* items already exist in the base script).
    "Chia phải": ("Split Right", S),
    "Chia dưới": ("Split Down", S),
    "Đóng các tab khác": ("Close Other Tabs", S),
    # StatusBarView: Trash without Full Disk Access (contract §4).
    "Cần quyền Full Disk Access": ("Full Disk Access needed", S),
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
