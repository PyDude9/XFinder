#!/usr/bin/env python3
"""Fail on duplicate keys in the L10n string dictionaries.

A duplicate key in a Swift dictionary *literal* is a FATAL ERROR at runtime:

    Swift/Dictionary.swift:880: Fatal error: Dictionary literal contains duplicate keys

It is invisible to the compiler (which only warns, and not on every path) and to
the Vietnamese-literal lint, because the lint looks at *views*, not at the L10n
stores. It has already shipped once: two duplicate keys in `L10n.moreDict` killed
the process at launch, which made every page blank, and the cause was only
findable by reading stderr.

Exit code is non-zero when a duplicate exists, so this can gate a build.

Usage:  python3 scripts/check-l10n-duplicates.py [path-to-L10nStorage dir]
"""

import re
import sys
from pathlib import Path

# Scan every file that contributes a `[String: String]` literal to the string tables.
DEFAULT_TARGETS = [
    "XFinder/Core/L10nStrings.swift",
    "XFinder/Core/L10n.swift",
    "XFinder/Core/L10nDB.swift",
]

# `static let moreDict: [String: String] = [` — capture the dictionary name.
DICT_START = re.compile(r"static\s+let\s+(\w+)\s*:\s*\[String\s*:\s*String\]\s*=\s*\[")
# A line whose first non-space token is a string literal followed by `:` — i.e. a key.
KEY_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:')


def scan(path: Path):
    """Yield (dict_name, line_number, key) for every key line inside every literal."""
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

        # Track bracket depth so a nested literal (e.g. inside a computed value)
        # cannot terminate the dict early. Bracket characters inside a string
        # literal are skipped by walking the line character by character.
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


def main() -> int:
    targets = sys.argv[1:] or DEFAULT_TARGETS
    seen = {}       # (dict_name, key) -> first line number
    duplicates = []

    for target in targets:
        path = Path(target)
        if not path.exists():
            print(f"SKIP (missing): {target}")
            continue
        for dict_name, lineno, key in scan(path):
            slot = (dict_name, key)
            if slot in seen:
                duplicates.append((target, dict_name, key, seen[slot], lineno))
            else:
                seen[slot] = lineno

    for target, dict_name, key, first, dup in duplicates:
        print(f"DUPLICATE {target}:{dup}: {dict_name} key {key!r} already at line {first}")

    print(f"TOTAL {len(duplicates)} duplicates across {len(seen)} unique keys")
    return 1 if duplicates else 0


if __name__ == "__main__":
    sys.exit(main())
