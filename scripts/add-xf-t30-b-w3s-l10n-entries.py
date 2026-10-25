#!/usr/bin/env python3
"""XF-T30 W3 builder "w3s" — sidebar section headers (2026-10-25). ADD-ONLY: a key already present with another
meaning is a CONFLICT. Run to test, then `git checkout -- XFinder/Resources/L10n.strings.json` before committing
(the integrator applies the final set for the whole wave)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # SidebarSections.headers — "Nhóm Vị trí theo loại" sub-headers (Cục bộ/Ngoài/Đám mây reuse "Mạng" for Network,
    # already in the store from elsewhere). "Gần đây", "AirDrop", "iCloud Drive", "Vị trí", "Mạng", "Thẻ" already
    # exist in the store with the same meaning and are reused as-is, not re-added here.
    "Cục bộ": ("Local", S),
    "Ngoài": ("External", S),
    "Đám mây": ("Cloud", S),
    "Tất cả thẻ…": ("All Tags…", S),
    # Bonjour section header: distinct from "Mạng" (connected servers sub-header), which already has that meaning —
    # a new key, not a reuse, so the two sections never render the same literal text (review fix).
    "Máy tính lân cận": ("Nearby Computers", S),
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
