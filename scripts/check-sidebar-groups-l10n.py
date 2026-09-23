#!/usr/bin/env python3
"""Fail when a sidebar GROUP HEADER is not translated.

The gate added after the six headings were found rendering Vietnamese on an English page.

The leak shape is specific and the three existing checks all miss it:

  * `verify-gesture-ui.sh` §3 greps for `L10n.t("…")` — a *literal* argument. The actual
    call site is `L10n.t(group.header)`, a variable, so it is invisible.
  * `audit-l10n-literals.py` sees the literal where it is *declared*
    (`Models/SidebarDestination.swift`) and reports it as "unwrapped" — report-only,
    because most literals in `Core/`/`Models/` are legitimate lookup keys.
  * `check-l10n-coverage.py` checks the store against itself, never against what is
    rendered.

So this script reads the declaration the sidebar actually iterates, extracts each group
header, and requires the store to carry it. It **fails loudly if its own parse finds too
few headers**, because a regex that silently matches nothing is how a gate reports green
over a structure it no longer understands (the rotting-anchor lesson in `AGENTS.md`).

Exit code is non-zero when a header is missing or untranslated.

Usage:  python3 scripts/check-sidebar-groups-l10n.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = ROOT / "XFinder/Models/SidebarDestination.swift"
STORE = ROOT / "XFinder/Resources/L10n.strings.json"
REL_MODEL = MODEL.relative_to(ROOT)

# The sidebar has had six groups for several passes; a parse that finds fewer than this
# means the structure changed and the gate must be re-derived rather than trusted.
MIN_EXPECTED_HEADERS = 4

VIETNAMESE = re.compile(r"[À-ỹĐđ]")

# `static var groups: [(header: String, items: [SidebarDestination])] {` … `}`
GROUPS_BLOCK = re.compile(
    r"static\s+var\s+groups\b.*?\{(.*?)\n    \}",
    re.DOTALL,
)

# The first element of each tuple: `("CHUNG", [.dashboard, …])`.
HEADER = re.compile(r'\("((?:[^"\\]|\\.)*)"\s*,\s*\[')


def group_headers() -> list[str]:
    text = MODEL.read_text(encoding="utf-8")
    block = GROUPS_BLOCK.search(text)
    if block is None:
        raise SystemExit(
            f"HARNESS ERROR: could not locate `groups` in {REL_MODEL}. "
            "The declaration was refactored — re-derive this gate instead of trusting it."
        )
    return HEADER.findall(block.group(1))


def main() -> int:
    headers = group_headers()
    if len(headers) < MIN_EXPECTED_HEADERS:
        print(
            f"HARNESS ERROR: found {len(headers)} group headers in {REL_MODEL} "
            f"(expected at least {MIN_EXPECTED_HEADERS}). The parse is stale — fix the "
            "gate, not the assertion."
        )
        return 1

    entries = json.loads(STORE.read_text(encoding="utf-8"))["entries"]
    problems: list[str] = []
    for header in headers:
        entry = entries.get(header)
        if entry is None:
            problems.append(
                f"{header!r} is rendered by the sidebar but is not in the store, so an "
                f"English UI shows it in Vietnamese"
            )
            continue
        en = entry.get("en") or ""
        if not en:
            problems.append(f"{header!r} has no English value")
        elif VIETNAMESE.search(en):
            problems.append(f"{header!r} -> {en!r} still carries Vietnamese characters")

    for line in problems:
        print("PROBLEM", line)
    print(f"TOTAL {len(problems)} problems across {len(headers)} sidebar group headers")
    if problems:
        print(f"       fix: python3 scripts/add-sidebar-l10n-entries.py")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
