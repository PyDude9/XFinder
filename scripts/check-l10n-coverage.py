#!/usr/bin/env python3
"""Fail when a translated string is reachable but untranslated, or when the
translation store contradicts itself.

This is the gate the old lint could not be — and the reason the language bug was
reported four times instead of once.

The old lint searched `Views/` for Vietnamese *literals* that were not
immediately wrapped in `L10n.t(...)`. It could not see any of the three ways this
bug actually reached the screen:

  1. A computed property in `Core/` returning a hard-coded Vietnamese string,
     rendered by an unwrapped `Text(...)`. The literal and the call site are in
     different files, so the literal lint never looked at it. Shipped example:
     `TriggerSource.buttonName` -> "Nut giua / bam con lan (Button 2)" showing
     in an English UI.
  2. An interpolated string wrapped as a whole. `L10n.t("Da nen \\(n) muc")`
     builds a key containing a runtime value, so it can never match a store
     entry and silently falls back to Vietnamese.
  3. A string wrapped correctly but simply absent from the store. `L10n.t`
     returns the Vietnamese literal on a miss, which is the *safe* degradation
     but is indistinguishable from "translated" in the build.

So this script audits the store rather than the call sites. Three checks:

  A. **Coverage.** Every entry whose Vietnamese form contains letters (in any
     script — an emoji or "\\u2318T" has nothing to translate) must have an
     English value that is not identical to it, unless the string is on the
     explicit `sameByDesign` allowlist for genuine brand/protocol names.

  B. **Scope.** `sentence` and `fragment` are not filing cabinets, they are
     claims about how the string is used, and the store has to be right about
     them or the checker cannot reason at all. The distinction is exactly
     "must this be joined to something?":

       * **`sentence`** — rendered on its own. May be a full sentence *or* a
         bare label/button ("Move"), may be a label ending in a colon
         ("Compression level:"), must not carry calculated edge padding.
       * **`fragment`** — concatenated into a bigger string. Must end in a
         colon, opening bracket or quote when it opens a clause, and must keep
         its edge whitespace when the Vietnamese form has it.

  C. **Allowlist hygiene.** A stale exception is worse than no exception, so an
     allowlisted string that no longer exists in the store is a failure.

Note on what check B deliberately does *not* claim: padding is not required
whenever a string is concatenated. `"Khong co gi khop \u201c" + query + "\u201d."`
needs no padding, and demanding it would force call sites to change. The
whitespace requirement is keyed off the Vietnamese form, which is authoritative
because it is the string that actually renders today.

Exit code is non-zero when any entry fails, so this can gate a build.

Usage:  python3 scripts/check-l10n-coverage.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "XFinder/Resources/L10n.strings.json"
ALLOWLIST = ROOT / "XFinder/Resources/L10n.allowlist.json"
REL_STORE = STORE.relative_to(ROOT)
REL_ALLOWLIST = ALLOWLIST.relative_to(ROOT)

# Any letter, in any script. A string with no letters has nothing to translate.
LETTER = re.compile(r"[^\W\d_]", re.UNICODE)

# A fragment that opens a clause must end with the punctuation that opens it,
# because the next thing concatenated is its subject.
OPENS_CLAUSE = (":", "(", "\u201c", "\u2014")

# The reverse: these endings mean the string closes a thought, so it is a
# sentence even if it is short.
CLOSES_CLAUSE = (".", "!", "?", "\u2026", ")", "\u201d")


def main() -> int:
    if not STORE.exists():
        print(f"FAIL: translation store missing: {REL_STORE}")
        print("      regenerate: python3 scripts/migrate-l10n-source-literals.py --write")
        return 1

    entries = json.loads(STORE.read_text(encoding="utf-8")).get("entries", {})
    allowlist: set[str] = set()
    if ALLOWLIST.exists():
        allowlist = set(json.loads(ALLOWLIST.read_text(encoding="utf-8")).get("sameByDesign", []))

    problems: list[str] = []
    used_allowlist: set[str] = set()

    for vi in sorted(entries):
        entry = entries[vi]
        en = entry.get("en") or ""
        scope = entry.get("scope")
        swap = entry.get("swap")

        if scope not in ("sentence", "fragment"):
            problems.append(f"{vi!r}: unknown scope {scope!r}")
            continue

        has_letters = bool(LETTER.search(vi))

        # --- Check A: coverage -------------------------------------------------
        # A `swap` fragment is a deposition: the call site already supplies the
        # English wording, so an empty translation is the *correct* value and
        # `L10n.t` turns it into "". Everything else with letters must translate.
        if not en and not swap:
            if has_letters:
                problems.append(
                    f"{vi!r}: has no English. A miss here renders Vietnamese in "
                    f"an English UI and nothing else in the build notices")
            continue

        if has_letters and en == vi:
            if vi in allowlist:
                used_allowlist.add(vi)
            else:
                problems.append(
                    f"{vi!r}: its English is itself. The string has letters, so "
                    f"this can only be a missing translation. If the word really "
                    f"is spelled the same in both languages, add it to {REL_ALLOWLIST}")

        # --- Check B: scope ----------------------------------------------------
        vi_edge = vi != vi.strip()
        en_edge = en != en.strip()

        if scope == "fragment":
            opening = vi.rstrip().endswith(OPENS_CLAUSE)
            if opening and not en.rstrip().endswith(OPENS_CLAUSE) and not swap:
                problems.append(
                    f"{vi!r}: the Vietnamese opens a clause but the English "
                    f"({en!r}) does not — concatenating them straight after "
                    f"would swallow the next value into the wrong clause")
            if vi_edge and not en_edge and not swap:
                problems.append(
                    f"{vi!r}: concatenated and the Vietnamese keeps edge "
                    f"whitespace, but the English ({en!r}) does not — the words "
                    f"would run together")
            if not vi_edge and en_edge and vi.rstrip()[-1:] in OPENS_CLAUSE:
                problems.append(
                    f"{vi!r}: English ({en!r}) adds edge whitespace the "
                    f"Vietnamese does not use; the call site pads this one "
                    f"itself, so the translation would double the space")
        else:  # sentence
            if en_edge:
                problems.append(
                    f"{vi!r}: marked a *sentence* (rendered on its own) but the "
                    f"English ({en!r}) carries edge padding. Either it is a "
                    f"fragment, or the spaces are a copy-paste typo")
            elif en.rstrip().endswith(OPENS_CLAUSE) and not swap:
                problems.append(
                    f"{vi!r}: marked a *sentence* but the English ({en!r}) ends "
                    f"as an opening clause, which can only be joined to "
                    f"something. Mark it a fragment, or set \"swap\": true if "
                    f"the call site already supplies the opening clause itself")

        # --- Check B, part 2: the swap contract --------------------------------
        if swap and scope != "fragment":
            problems.append(f"{vi!r}: \"swap\" is only meaningful on a fragment")

    # --- Check C: allowlist hygiene -------------------------------------------
    for key in sorted(allowlist - used_allowlist):
        problems.append(
            f"{REL_ALLOWLIST}: {key!r} is allowlisted but is not an untranslated "
            f"entry any more — remove it, a stale exception hides a real gap")

    for line in problems:
        print("PROBLEM", line)
    print(f"TOTAL {len(problems)} problems across {len(entries)} entries "
          f"({len(entries) - len(problems) - 0} checked, "
          f"{len(used_allowlist)} allowlisted)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
