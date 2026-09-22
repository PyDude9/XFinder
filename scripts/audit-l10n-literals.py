#!/usr/bin/env python3
"""Every Vietnamese string literal in the app, and whether the store covers it.

The other two scripts answer narrower questions:
  `check-l10n-coverage.py`  — is the *store* internally correct?
  `audit-l10n-reachability.py` — is a string *reachable* without going through t()?

Neither answers the question that actually caused four reports: "is every string
this app can show translated, everywhere, not just in Views/?" This script
enumerates every Vietnamese literal in the Swift sources and checks it against
the store, so a string that lives only in `Core/` and is wrapped at a call site
still has to exist in the store to work.

Report-only by default, because a literal used purely as a key or an internal
constant is legitimate. `--strict` exits non-zero, and is intended for CI once
the remaining gaps are closed.

Usage:  python3 scripts/audit-l10n-literals.py [--strict]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"

VIETNAMESE = re.compile(r"[À-ỹĐđ]")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')

SKIP_DIRS = ("XFinder/Core/L10n", "XFinder/Resources", "XFinder/Core/MouseGestures/GestureModel.swift")


def sources():
    for path in sorted((ROOT / "XFinder").rglob("*.swift")):
        rel = path.relative_to(ROOT).as_posix()
        if any(rel.startswith(s) for s in SKIP_DIRS):
            continue
        yield rel, path


def main() -> int:
    strict = "--strict" in sys.argv
    store = json.loads(STORE.read_text(encoding="utf-8"))["entries"]

    wrapped_total = 0
    unwrapped: list[tuple[str, int, str]] = []
    absent: list[tuple[str, int, str]] = []

    for rel, path in sources():
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.strip().startswith("//"):
                continue
            for match in STRING.finditer(line):
                literal = match.group(1)
                if not VIETNAMESE.search(literal):
                    continue
                prefix = line[:match.start()].rstrip()
                is_wrapped = prefix.endswith("L10n.t(") or prefix.endswith("L10n.md(")
                if is_wrapped:
                    wrapped_total += 1
                    if literal not in store:
                        absent.append((rel, lineno, literal))
                else:
                    unwrapped.append((rel, lineno, literal))

    print(f"=== {wrapped_total} wrapped literals, all present in the store? ===")
    if absent:
        print(f"!!! {len(absent)} WRAPPED but NOT in the store — these silently show Vietnamese:")
        for rel, lineno, literal in absent:
            print(f"  {rel}:{lineno}  {literal!r}")
    else:
        print("  yes — every wrapped literal resolves to a translation")

    print()
    print(f"=== {len(unwrapped)} unwrapped literals (may be keys, constants or gaps) ===")
    for rel, lineno, literal in unwrapped:
        print(f"  {rel}:{lineno}  {literal!r}")

    print()
    print(f"TOTAL {len(absent)} wrapped-but-untranslated, {len(unwrapped)} unwrapped")

    if strict and (absent or unwrapped):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
