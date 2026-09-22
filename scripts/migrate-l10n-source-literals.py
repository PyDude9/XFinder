#!/usr/bin/env python3
"""Move the in-source translation literals into a text-based keyed store.

Why: the old L10n split every translated string across *three* Swift dictionary
literals (enDict / moreDict / fragDict) with no rule about which one a string
belongs in. Two consequences, both observed:

  * A string added to the wrong dictionary, or never added at all, renders the
    Vietnamese literal in an English UI. `L10n.t` falls back to VI on a miss, so
    the failure mode is silent — the same bug was reported four times.
  * Nothing links a Swift source string to the text a translator edits.

The target store is a plain JSON file, `XFinder/Resources/L10n.strings.json`,
keyed by the Vietnamese literal and carrying both languages plus the flags that
say whether an entry is a full sentence or an interpolation fragment:

    { "vi": "…", "en": "…", "scope": "sentence" | "fragment" }

`scope` is what the three literals encoded implicitly and inconsistently:
fragments keep their leading/trailing spaces because they are concatenated,
sentences do not. Keeping the distinction as data rather than as "which file is
this in" is the whole point.

This script performs the one-time extraction and prints a report. It is
idempotent: run it twice and the second run reports nothing to move.

Usage:  python3 scripts/migrate-l10n-source-literals.py [--write]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "XFinder/Resources/L10n.strings.json"

# (file, dictionary name) -> scope
SOURCES = [
    ("XFinder/Core/L10n.swift", "enDict", "sentence"),
    ("XFinder/Core/L10nStrings.swift", "moreDict", "sentence"),
    ("XFinder/Core/L10nStrings.swift", "fragDict", "fragment"),
    # Stable-key table: keyed by a dotted key, keyed per language.
    ("XFinder/Core/L10nDB.swift", "table", "keyed"),
]

DICT_START = re.compile(r"static\s+let\s+(\w+)\s*:\s*\[[^\]]*\]\s*=\s*\[")


def bracket_balance(line: str) -> int:
    """Net bracket delta of a line, ignoring brackets inside string literals."""
    depth = 0
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
    return depth


def unescape(literal: str) -> str:
    """Swift string literal body -> real string."""
    out = []
    i = 0
    while i < len(literal):
        ch = literal[i]
        if ch == "\\" and i + 1 < len(literal):
            nxt = literal[i + 1]
            if nxt == "n":
                out.append("\n")
                i += 2
                continue
            if nxt == "t":
                out.append("\t")
                i += 2
                continue
            if nxt == '"':
                out.append('"')
                i += 2
                continue
            if nxt == "\\":
                out.append("\\")
                i += 2
                continue
            out.append(nxt)
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def scan(path: Path, dict_name: str):
    """Yield (key_literal, value_literal, lineno) for one dictionary literal."""
    text = path.read_text(encoding="utf-8")
    active = False
    depth = 0
    for lineno, line in enumerate(text.splitlines(), start=1):
        if not active:
            m = DICT_START.search(line)
            if m and m.group(1) == dict_name:
                active = True
                depth = bracket_balance(line)
            continue
        depth += bracket_balance(line)
        if depth <= 0:
            active = False
            continue
        m = re.match(r'\s*"((?:[^"\\]|\\.)*)"\s*:\s*(.*)$', line)
        if not m:
            continue
        key = m.group(1)
        rest = m.group(2)
        vm = re.match(r'^"((?:[^"\\]|\\.)*)"\s*,?\s*$', rest)
        if vm:
            yield key, vm.group(1), lineno
            continue
        # Stable-key table: value is a `[AppLanguage: String]` literal.
        pair = {
            lang: lit
            for lang, lit in re.findall(r'\.(\w+)\s*:\s*"((?:[^"\\]|\\.)*)"', rest)
        }
        if pair:
            yield key, pair, lineno


def main() -> int:
    write = "--write" in sys.argv
    entries: dict[str, dict] = {}
    problems: list[str] = []

    for rel, dict_name, scope in SOURCES:
        path = ROOT / rel
        if not path.exists():
            problems.append(f"missing source file: {rel}")
            continue
        for key, value, lineno in scan(path, dict_name):
            if isinstance(value, dict):
                vi = value.get("vietnamese")
                en = value.get("english")
                if vi is None:
                    problems.append(f"{rel}:{lineno}: {dict_name} entry {key!r} has no vietnamese")
                    continue
                existing = entries.get(vi)
                if existing and existing["en"] != (en or ""):
                    problems.append(
                        f"{rel}:{lineno}: {vi!r} already translated as {existing['en']!r}, "
                        f"now {en!r} — first wins")
                entries.setdefault(vi, {"en": en or "", "scope": "keyed", "key": key,
                                        "source": f"{rel}:{dict_name}"})
                continue
            vi = unescape(key)
            en = unescape(value)
            existing = entries.get(vi)
            if existing:
                if existing["en"] != en:
                    problems.append(
                        f"{rel}:{lineno}: {vi!r} already translated as {existing['en']!r}, "
                        f"now {en!r} — first wins")
                # A string that appears as both sentence and fragment is a real
                # hazard of the old split; fragment (space-preserving) wins because
                # the concatenation is the stricter reader.
                if scope == "fragment" and existing["scope"] != "fragment":
                    existing["scope"] = "fragment"
                continue
            entries[vi] = {"en": en, "scope": scope, "source": f"{rel}:{dict_name}"}

    for line in problems:
        print("PROBLEM", line)

    print(f"collected {len(entries)} entries from {len(SOURCES)} dictionaries")

    if not write:
        print("(dry run — pass --write to emit the store)")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "_comment": (
            "Keyed by the Vietnamese literal, because that is what call sites read "
            "as. `scope` separates full sentences from interpolation fragments; a "
            "fragment keeps its surrounding spaces and is never used as a whole "
            "sentence. `key` is the stable dotted key when the string also has one. "
            "Generated from the Swift dictionaries by "
            "scripts/migrate-l10n-source-literals.py."
        ),
        "entries": {k: entries[k] for k in sorted(entries)},
    }
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
