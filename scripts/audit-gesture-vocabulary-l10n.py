#!/usr/bin/env python3
"""Resolve the mouse-gesture module's *whole vocabulary* against the shipped store.

Why this exists
---------------
`verify-l10n-runtime.py` checks a fixed list of literals (sidebar titles, group
headings, Finder-extension states). It cannot see a string that reaches the screen
through `L10n.t(variable)` — and that is exactly the class of leak that has been
reported repeatedly: six sidebar headings and five model captions shipped
untranslated because *no gate enumerated them*.

The gesture model is the worst case, because it is built to return **keys**, not
sentences (R2: "the model must not emit display strings"). That is the right design
— but it moves the failure mode from "unwrapped literal" (which the literal lint
catches) to "a key nobody put in the store" (which nothing caught). `L10n.t`
falls back to the Vietnamese on a miss, so the English UI silently shows
Vietnamese.

So: parse the declarations that produce those keys, and assert every one resolves
to non-empty English in the store that is actually inside the built bundle.

Two sources, because the vocabulary is declared in two shapes:

  1. `switch` bodies inside the key-producing functions of `GestureModel.swift`,
     `GestureMap.swift`, `GestureLabelStructure.swift` — every `return "…"` is a key.
  2. `GestureProfiles.all`'s name arguments — those render in the app picker via
     `Text(item.name)`, which does **not** pass through `L10n.t`, so a Vietnamese
     profile name would leak by construction. Flagged separately.

Usage:  python3 scripts/audit-gesture-vocabulary-l10n.py [--store PATH]
Exit:   0 = every key resolves, 1 = at least one does not.
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The files that declare gesture vocabulary, and the declarations inside them whose
# string values are store keys. Naming the declarations (rather than grabbing every
# string in the file) keeps unrelated literals — comments, log lines, the `"x"`
# / `"wheel"` axis tokens — out of the check.
#
# Two shapes, because the vocabulary is declared in two:
#   * `BRACE_SOURCES`  — a declaration with a body; every `return "…"` is a key.
#   * `LITERAL_SOURCES` — a `let` bound straight to a literal, which has NO body and
#     would otherwise make the brace walker jump into the next declaration.
BRACE_SOURCES = {
    "XFinder/Core/MouseGestures/GestureModel.swift": [
        r"var motionKey: String",
        r"var titleKey: String",
        r"var motionHintKey: String",
        r"var captionKey: String",
        r"var unboundCaptionKey: String",
    ],
    "XFinder/Core/MouseGestures/GestureMap.swift": [
        r"var labelKey: String",
        r"var groupKey: String",
    ],
    "XFinder/Core/MouseGestures/GestureLabelStructure.swift": [
        r"func namedKey\(forButtonNumber n: Int\) -> String\?",
        r"func hintKey\(forButtonNumber n: Int\) -> String\?",
    ],
    # The capability module. `MouseButtonRole` is the second half of PATCH v9.1 and its
    # two key members reach the screen through `L10n.t(variable)` — added the moment they
    # existed, because a vocabulary member outside the gate is the exact hole this file
    # was written to close.
    "XFinder/Core/MouseGestures/DeviceCapabilityModel.swift": [
        r"var labelKey: String",
        r"var explanationKey: String",
        r"static func passthroughNoteKey\(forEventButton button: Int\) -> String\?",
    ],
}

LITERAL_SOURCES = {
    "XFinder/Core/MouseGestures/GestureLabelStructure.swift": [
        r'static let numberedPrefixKey = "((?:[^"\\]|\\.)*)"',
    ],
}

# Files that must exist (declaration drift is a gate failure, not a silent miss).
WATCHED_FILES = [
    "XFinder/Core/MouseGestures/GestureModel.swift",
    "XFinder/Core/MouseGestures/GestureMap.swift",
    "XFinder/Core/MouseGestures/GestureLabelStructure.swift",
]

# Strings that are symbols or brand names, identical in every language. Kept
# explicit so "resolves to itself" is a declared fact rather than an untranslated
# sentence hiding among the rest.
NEUTRAL = {
    "Mission Control", "App Exposé", "App Expose", "⌘", "⌥", "⌃", "⇧",
}

# Every double-quoted literal inside a key declaration's body is a store key. Both
# explicit (`return "…"`) and implicit-return (`{ "…" }`) bodies are covered — the
# earlier version only read `return "…"` and silently skipped any single-expression
# declaration, which is how `unboundCaptionKey` slipped past the first run.
ATTR = r'"((?:[^"\\]|\\.)*)"'


def declaration_bodies(text, opener):
    """The body of the declaration that `opener` matches, by brace depth."""
    match = re.search(opener, text)
    if not match:
        return None
    # Search from the *start* of the opener, not its end: some openers include the
    # brace themselves (`... = {`), and searching past it would walk into the next
    # declaration and silently return that one's body. That bug made the profile-name
    # check pass over zero names — a gate reporting green over nothing, which is the
    # exact failure mode this file exists to prevent.
    start = text.find("{", match.start())
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return None


def collect_keys():
    """(key, file, declaration) for every key the gesture module can emit."""
    found = []
    for rel, openers in BRACE_SOURCES.items():
        path = ROOT / rel
        if not path.exists():
            print(f"ERROR: missing source {rel}", file=sys.stderr)
            sys.exit(2)
        text = path.read_text(encoding="utf-8")
        for opener in openers:
            body = declaration_bodies(text, opener)
            if body is None:
                print(f"ERROR: declaration not found in {rel}: {opener}", file=sys.stderr)
                sys.exit(2)
            values = re.findall(ATTR, body)
            if not values:
                print(f"ERROR: declaration has no string keys in {rel}: {opener}", file=sys.stderr)
                sys.exit(2)
            for value in values:
                found.append((value, rel, opener))
    for rel, patterns in LITERAL_SOURCES.items():
        path = ROOT / rel
        if not path.exists():
            print(f"ERROR: missing source {rel}", file=sys.stderr)
            sys.exit(2)
        text = path.read_text(encoding="utf-8")
        for pattern in patterns:
            values = re.findall(pattern, text)
            if not values:
                print(f"ERROR: literal not found in {rel}: {pattern}", file=sys.stderr)
                sys.exit(2)
            for value in values:
                found.append((value, rel, pattern))
    return found


def profile_names():
    """The `name` argument of every built-in profile — rendered raw by the picker.

    `MouseGesturesDetailView` renders `Text(item.name)` without `L10n.t`, so a
    Vietnamese profile name has no translation path at all. Extracted from the real
    declaration rather than a copy of it, so adding a profile cannot escape the check.
    """
    text = (ROOT / "XFinder/Core/MouseGestures/GestureModel.swift").read_text(encoding="utf-8")
    table = declaration_bodies(text, r"static let all: \[GestureProfile\] = \{")
    if table is None:
        print("ERROR: GestureProfiles.all not found", file=sys.stderr)
        sys.exit(2)
    # Two declaration shapes, both needed: the `for (id, name) in [("bundle", "Name"), …]`
    # loop tuples, and the direct `profile("bundle", "Name", …)` calls (Global, Excel,
    # Word, the shared terminal map). Matching only the tuple form missed four profiles
    # — the same "gate quietly checks less than it claims" shape as the brace bug above.
    # A bundle id is recognised by its shape — a dotted identifier starting with a
    # letter — so a two-string tuple that is not a profile cannot be mistaken for one.
    # The character class must allow UPPERCASE: `com.apple.Safari`, `dev.zed.Zed`,
    # `com.adobe.Photoshop` are all real, and a lowercase-only rule silently dropped
    # seven of them.
    pairs = re.findall(r'"([A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z0-9\-]+)+)",\s*"([^"]+)"', table)
    return pairs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", default=None,
                        help="L10n.strings.json to resolve against (default: the source store)")
    parser.add_argument("--bundle", action="store_true",
                        help="resolve against the store inside /Applications/XFinder.app")
    args = parser.parse_args()

    if args.bundle:
        store_path = Path("/Applications/XFinder.app/Contents/Resources/L10n.strings.json")
        label = "installed bundle"
    else:
        store_path = Path(args.store) if args.store else ROOT / "XFinder/Resources/L10n.strings.json"
        label = "source store"

    if not store_path.exists():
        print(f"ERROR: store not found: {store_path}", file=sys.stderr)
        sys.exit(2)

    data = json.loads(store_path.read_text(encoding="utf-8"))
    sentences = data.get("entries", {})
    print(f"store: {store_path} ({label}) — {len(sentences)} entries")

    missing = []
    checked = 0
    for value, rel, opener in collect_keys():
        if value in NEUTRAL:
            continue
        checked += 1
        entry = sentences.get(value)
        if not entry or not (entry.get("en") or "").strip():
            missing.append((value, rel, opener))

    # Profile names go straight into `Text(item.name)`, so a Vietnamese name has no
    # translation path at all. A brand name is fine; a Vietnamese sentence is not.
    VI = re.compile(r"[À-ỹ]")
    names = profile_names()
    name_leaks = [(bundle, name) for bundle, name in names if VI.search(name)]

    print("----- vocabulary -----")
    print(f"  keys checked: {checked}")
    print(f"  profile names: {len(names)} (Vietnamese: {len(name_leaks)})")

    for value, rel, opener in missing:
        print(f"  MISSING  {value!r}   ({rel} :: {opener})")
    for bundle, name in name_leaks:
        print(f"  NAME-LEAK {bundle} -> {name!r}")

    total = len(missing) + len(name_leaks)
    print(f"TOTAL {total} unresolved gesture strings")
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
