#!/usr/bin/env python3
"""Fail on duplicate keys in the L10n store.

Two things can duplicate a key, and both have bitten this project:

1. A Swift dictionary *literal* with a repeated key is a FATAL ERROR at runtime
   ("Dictionary literal contains duplicate keys"). Invisible to the compiler on
   most paths, and it killed the process at launch once, which made every page
   blank with the cause only visible on stderr.

2. The store is now a JSON file (`XFinder/Resources/L10n.strings.json`). It is
   written by scripts that merge entries, so a duplicate can survive as two
   object entries, and a duplicate in JSON is *silently* last-wins rather than a
   crash — which is worse, because the page quietly renders the wrong language.

Both are checked here: the JSON store for duplicate object keys (via a raw parse
that does not collapse them), and any remaining Swift literal dictionaries.

Exit code is non-zero when a duplicate exists, so this can gate a build.

Usage:  python3 scripts/check-l10n-duplicates.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

STORE = Path("XFinder/Resources/L10n.strings.json")

# Any Swift file that still declares a `[String: String]` table literal.
SWIFT_TARGETS = [
    "XFinder/Core/L10n.swift",
    "XFinder/Core/L10nStore.swift",
]

DICT_START = re.compile(r"static\s+let\s+(\w+)\s*:\s*\[String\s*:\s*String\]\s*=\s*\[")
KEY_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:')


def scan_swift(path: Path):
    """Yield (dict_name, line_number, key) for every key inside every literal."""
    text = path.read_text(encoding="utf-8")
    inside = None
    depth = 0
    for lineno, line in enumerate(text.splitlines(), start=1):
        if inside is None:
            m = DICT_START.search(line)
            if m:
                inside = m.group(1)
                depth = 1
            continue

        in_string = False
        escaped = False
        for ch in line:
            if escaped:
                escaped = False
                continue
            if ch == "\\":
                escaped = True
                continue
            if ch == '"':
                in_string = not in_string
                continue
            if in_string:
                continue
            if ch in "[{(":
                depth += 1
            elif ch in "]})":
                depth -= 1

        key_m = KEY_LINE.match(line)
        if key_m:
            yield inside, lineno, key_m.group(1)

        if depth <= 0:
            inside = None


def duplicate_json_keys(path: Path) -> list[str]:
    """Duplicate keys in the JSON object, which json.loads would silently collapse.

    `object_pairs_hook` receives every pair *before* deduplication, so a repeated
    key is visible here and nowhere else.
    """
    duplicates: list[str] = []

    def hook(pairs):
        seen: set[str] = set()
        for key, _ in pairs:
            if key in seen:
                duplicates.append(key)
            seen.add(key)
        return dict(pairs)

    json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=hook)
    return duplicates


def main() -> int:
    duplicates: list[str] = []
    unique = 0

    if STORE.exists():
        for key in duplicate_json_keys(STORE):
            duplicates.append(f"{STORE}: duplicate entry for {key!r}")
        entries = json.loads(STORE.read_text(encoding="utf-8")).get("entries", {})
        unique = len(entries)
    else:
        print(f"SKIP (missing): {STORE}")

    seen: dict[tuple[str, str], int] = {}
    for target in SWIFT_TARGETS:
        path = Path(target)
        if not path.exists():
            continue
        for dict_name, lineno, key in scan_swift(path):
            slot = (dict_name, key)
            if slot in seen:
                duplicates.append(
                    f"{target}:{lineno}: {dict_name} key {key!r} already at line {seen[slot]}"
                )
            else:
                seen[slot] = lineno

    for line in duplicates:
        print(line)
    print(f"TOTAL {len(duplicates)} duplicates across {unique + len(seen)} unique keys")
    return 1 if duplicates else 0


if __name__ == "__main__":
    sys.exit(main())
