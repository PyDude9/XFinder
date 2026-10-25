#!/usr/bin/env python3
"""XF-T30 W1 builder B (model, BrowserWindowModel.swift) — 2026-10-25. ADD-ONLY: a key already present with another
meaning is a CONFLICT. This builder's file introduces no new user-visible strings (every new command routes through
existing L10n keys in BrowserCommands.titleKey, toggles a `fileBrowser.*` UserDefaults key, or calls into chrome/
window-controller methods owned by other W1 builders); ENTRIES stays empty so the integrator's add-only run over
every XF-T30 W1 script is a no-op for this one."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # (intentionally empty — see module docstring)
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
