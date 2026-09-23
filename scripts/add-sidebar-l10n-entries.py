#!/usr/bin/env python3
"""Register the sidebar GROUP HEADERS in the L10n store.

Why this file has to exist
--------------------------
The six group headings in the sidebar (`CHUNG`, `CỬA SỔ`, …) live as plain Vietnamese
strings in `Models/SidebarDestination.swift`, because the model is not allowed to render
text and the call site is what localises them:

    Section(header: Text(L10n.t(group.header))) { … }

That wrapping is correct — but the store had **no entry** for any of the six, so
`L10n.t` fell through to the Vietnamese literal and an English page showed
`CHUNG / CỬA SỔ / FINDER & TÌM KIẾM / CÔNG CỤ / KẾT NỐI / TIỆN ÍCH`.

Nothing caught it, and the reason is worth recording because it is a *class* of leak:

  * `verify-gesture-ui.sh` §3 only greps `L10n.t("…")` — a **literal** argument — so a
    call site that passes a variable is invisible to it;
  * `audit-l10n-literals.py` sees the literal in the model file and reports it as
    "unwrapped", which is report-only by design (most such literals are legitimate keys);
  * `check-l10n-coverage.py` reasons about the store's *internal* consistency, not about
    whether a rendered string is in it at all.

It was found by rendering the page and reading the Accessibility tree, i.e. by looking at
what the app actually shows. `scripts/check-sidebar-groups-l10n.py` is the gate added so
this particular class — a *variable*-passed key that is missing — fails a check instead.

This script is idempotent: running it twice changes nothing.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

# Vietnamese key -> English, matching the uppercase label style of the Vietnamese.
ENTRIES: dict[str, str] = {
    "CHUNG": "GENERAL",
    "CỬA SỔ": "WINDOWS",
    "FINDER & TÌM KIẾM": "FINDER & SEARCH",
    "CÔNG CỤ": "TOOLS",
    "KẾT NỐI": "CONNECT",
    "TIỆN ÍCH": "UTILITIES",
}


def main() -> int:
    doc = json.loads(STORE.read_text(encoding="utf-8"))
    entries = doc["entries"]
    before = len(entries)
    added = replaced = 0
    for vi, en in ENTRIES.items():
        if vi in entries:
            if entries[vi].get("en") != en or entries[vi].get("scope") != "sentence":
                entries[vi] = {"en": en, "scope": "sentence"}
                replaced += 1
        else:
            entries[vi] = {"en": en, "scope": "sentence"}
            added += 1
    doc["entries"] = dict(sorted(entries.items()))
    STORE.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"entries {before} -> {len(doc['entries'])}  (added {added}, replaced {replaced})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
