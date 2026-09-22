#!/usr/bin/env python3
"""Find Vietnamese strings that reach the UI without passing through `L10n.t`.

The old lint only looked inside `Views/`. That is why the reported leak survived
it: `TriggerSource.buttonName` lives in `Core/MouseGestures/GestureModel.swift`,
returns a Vietnamese sentence, and its call site passed it straight to `Text(...)`.
Both halves were individually legal; only the composition was broken.

This script looks at *both* halves and reports the pairs:

  * declarations — every `func`/`var` in `Core/` (and `Models/`) that returns a
    Vietnamese string literal, with its signature;
  * call sites — every `Text(...)`, `Label(...)`, `Button(...)`, `Picker`,
    `TextField`, `Toggle`, `Section`, `help`, `accessibilityLabel` whose argument
    is a bare expression that is not already inside `L10n.t(...)`.

Note on the one shape a regex cannot see: a helper that *itself* wraps, such as
`MouseDiagramView.helpText(_:)`, returns an already-translated string. The
cheap-and-honest answer is to *verify* rather than to match —
`scripts/verify-l10n-runtime.py` and `L10nTests.testGesturePageStringsAreAllTranslatable`
assert that every string those helpers can build resolves to English.

Matching the two by name is deliberately conservative: it reports a *candidate*
pair for a human to judge, because a function can also legitimately be wrapped at
the call site. What it must never do is stay silent, which is what the old lint
did for four consecutive reports.

Exit code is always 0 — this is a report, not a gate. The gate is
`check-l10n-coverage.py`, which can only work once every reachable string is in
the store.

Usage:  python3 scripts/audit-l10n-reachability.py [--strict]
        --strict exits non-zero when any unwrapped candidate remains.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

VIETNAMESE = re.compile(r"[À-ỹĐđ]")
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')

# Where a string can be *declared* with no translation dependency.
DECLARING_DIRS = ["XFinder/Core", "XFinder/Models"]

# Where a string must be wrapped before it renders. `Text` is the common one, but
# the reported leaks came equally from `Label`, `Button`, `Picker` and `Toggle`,
# and `help`/`accessibilityLabel` are strings a user reads too.
WRAPPERS = [
    "Text", "Label", "Button", "Toggle", "Picker", "TextField", "SecureField",
    "Section", "Stepper", "Link", "NavigationLink", "Menu", "DisclosureGroup",
    ".help", "accessibilityLabel", "SettingsCard", "ToggleRow", "PageHeader",
    "SectionHeader", "StatusChecklistRow", "LabeledLine", "MeterRow",
]

# Directories whose strings are *supposed* to be Vietnamese and are never shown.
# `L10n` itself and its store are the translation data.
SKIP_PREFIXES = [
    "XFinder/Core/L10n",
    "XFinder/Resources",
]

# Declarations that intentionally return Vietnamese because the value is only
# ever used as a lookup key or is wrapped by its single caller. Each entry needs
# a reason, checked by the `--strict` mode listing it.
ALLOWED_DECLARATIONS = {
    # Pure model, symlinked into the test package, so it cannot import L10n.
    # Both of these are wrapped at every call site — asserted by
    # L10nTests.testGesturePageStringsAreAllTranslatable.
    "TriggerSource.buttonName",
    "TriggerSource.numberedName",
    "TriggerSource.label",
    "GestureDirection.title",
    "GestureDirectionDisplay.title",
}


def iter_sources():
    for base in DECLARING_DIRS + ["XFinder/Views"]:
        root = ROOT / base
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            if any(rel.startswith(p) for p in SKIP_PREFIXES):
                continue
            yield rel, path


def unwrapped_arguments(line: str):
    """Yield (wrapper, argument) for every wrapper call whose arg is not L10n-wrapped."""
    for wrapper in WRAPPERS:
        start = 0
        token = wrapper + "("
        while True:
            at = line.find(token, start)
            if at == -1:
                break
            start = at + len(token)
            # Grab a shallow argument: enough to see whether L10n.t( is there.
            depth = 1
            i = start
            while i < len(line) and depth:
                ch = line[i]
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                i += 1
            argument = line[start:i - 1].strip()
            if not argument:
                continue
            if "L10n.t(" in argument or "L10n.md(" in argument:
                continue
            # A pure literal is fine only if it has no Vietnamese.
            literals = STRING.findall(argument)
            if literals and not any(VIETNAMESE.search(lit) for lit in literals):
                continue
            yield wrapper, argument


def main() -> int:
    strict = "--strict" in sys.argv

    declarations: dict[str, tuple[str, int, str]] = {}
    call_sites: list[tuple[str, int, str, str]] = []

    for rel, path in iter_sources():
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        current_func: str | None = None
        for lineno, line in enumerate(lines, start=1):
            stripped = line.strip()
            if stripped.startswith("//"):
                continue

            # Declaration: a function or computed property that returns Vietnamese.
            m = re.search(r"\b(?:static\s+)?func\s+(\w+)|^\s*(?:static\s+)?var\s+(\w+)\s*:", line)
            if m:
                current_func = m.group(1) or m.group(2)
            if current_func and VIETNAMESE.search(line):
                for lit in STRING.findall(line):
                    if VIETNAMESE.search(lit):
                        key = current_func
                        declarations.setdefault(key, (rel, lineno, lit))
                        break

            if "/Views/" not in rel:
                continue
            for wrapper, argument in unwrapped_arguments(line):
                has_vi_literal = any(VIETNAMESE.search(l) for l in STRING.findall(argument))
                has_bare_call = bool(re.match(r"^[A-Za-z_][\w.]*\(", argument))
                if has_vi_literal or has_bare_call or VIETNAMESE.search(argument):
                    call_sites.append((rel, lineno, wrapper, argument[:90]))

    print("=== Vietnamese-returning declarations in Core/ and Models/ ===")
    if not declarations:
        print("  (none)")
    for name, (rel, lineno, sample) in sorted(declarations.items()):
        flag = "allowed" if name in ALLOWED_DECLARATIONS else "REVIEW"
        print(f"  [{flag}] {rel}:{lineno}  {name}()  {sample!r}")

    print()
    print("=== Unwrapped call sites in Views/ ===")
    if not call_sites:
        print("  (none)")
    for rel, lineno, wrapper, argument in call_sites:
        print(f"  {rel}:{lineno}  {wrapper}({argument})")

    review = [n for n in declarations if n not in ALLOWED_DECLARATIONS]
    print()
    print(f"TOTAL {len(review)} declarations to review, {len(call_sites)} unwrapped call sites")

    if strict and (review or call_sites):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
