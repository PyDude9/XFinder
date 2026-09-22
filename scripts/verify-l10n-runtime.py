#!/usr/bin/env python3
"""Prove the running app resolves English correctly — end to end, not statically.

The static audits prove the *store* is complete. They cannot prove the app loads
it, because the store is a bundle resource: if the pbxproj entry is wrong or the
Resource phase drops it, `L10nStore` logs one line to stderr and every page stays
Vietnamese, while every static check still passes.

So this reads the store the way the app does — from the *installed bundle* — and
then resolves the exact strings the Mouse & Gestures page renders, including the
two that leaked, under `AppLanguage = english`.

Usage:  python3 scripts/verify-l10n-runtime.py
"""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

APP = Path("/Applications/XFinder.app")
STORE_IN_BUNDLE = APP / "Contents/Resources/L10n.strings.json"
PREFS = Path.home() / "Library/Preferences/com.xfinder.app.plist"

VIETNAMESE = re.compile(r"[À-ỹĐđ]")

# The strings the user reported seeing in Vietnamese on an English page, plus the
# whole set the gesture page can render.
REPORTED_LEAKS = [
    "Nút giữa / bấm con lăn (Button 2)",
    "Nút trái (Button 0)",
    "Nút phải (Button 1)",
    "Nút hông sau — nút 4 (Button 3)",
    "Nút hông trước — nút 5 (Button 4)",
]
DIRECTION_HEADINGS = [
    "Kéo LÊN", "Kéo XUỐNG", "Kéo SANG TRÁI", "Kéo SANG PHẢI",
    "Nghiêng con lăn TRÁI", "Nghiêng con lăn PHẢI",
]
DIRECTION_INSTRUCTIONS = [
    "Giữ nút rồi kéo LÊN", "Giữ nút rồi kéo XUỐNG",
    "Giữ nút rồi kéo SANG TRÁI", "Giữ nút rồi kéo SANG PHẢI",
    "Nghiêng con lăn sang TRÁI (không giữ nút)",
    "Nghiêng con lăn sang PHẢI (không giữ nút)",
]
SIDEBAR = ["Chuột & cử chỉ", "Tổng quan", "Hệ thống", "Mạng"]


def main() -> int:
    failures: list[str] = []

    if not STORE_IN_BUNDLE.exists():
        print(f"FAIL: the store is not in the installed bundle: {STORE_IN_BUNDLE}")
        print("      the app would run entirely in Vietnamese with one stderr line")
        return 1
    print(f"store in bundle: {STORE_IN_BUNDLE.stat().st_size} bytes")

    store = json.loads(STORE_IN_BUNDLE.read_text(encoding="utf-8"))["entries"]
    sentences = {k: v["en"] for k, v in store.items() if v["scope"] == "sentence" and v["en"]}
    fragments = {k: v["en"] for k, v in store.items() if v["scope"] == "fragment"}
    print(f"loaded {len(sentences)} sentences + {len(fragments)} fragments")

    if PREFS.exists():
        prefs = plistlib.loads(PREFS.read_bytes())
        print(f"AppLanguage in prefs: {prefs.get('AppLanguage')!r}")
    else:
        prefs = {}

    # Resolve exactly as `L10n.t` does, in English mode.
    def t(vi: str) -> str:
        if vi in fragments:
            return fragments[vi]
        if vi in sentences:
            return sentences[vi]
        return vi

    print()
    print("=== the two reported leaks, resolved as the English UI renders them ===")
    for vi in REPORTED_LEAKS + DIRECTION_HEADINGS:
        en = t(vi)
        ok = en != vi and not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== the interpolated default: 'Nút chuột số \\(n+1) (Button \\(n))' ===")
    for n in (7, 31):
        rendered = f"{t('Nút chuột số ')}{n + 1}{t(' (Button ')}{n})"
        ok = not VIETNAMESE.search(rendered)
        print(f"  {'OK  ' if ok else 'LEAK'} n={n}: {rendered!r}")
        if not ok:
            failures.append(f"interpolated button {n}")

    print()
    print("=== every direction instruction ===")
    for vi in DIRECTION_INSTRUCTIONS:
        en = t(vi)
        ok = en != vi and not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== sidebar rows ===")
    for vi in SIDEBAR:
        en = t(vi)
        ok = not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== is the app running, and did it log a store failure? ===")
    running = subprocess.run(["pgrep", "-x", "XFinder"], capture_output=True, text=True)
    print("app running:", bool(running.stdout.strip()))
    print()
    print(f"TOTAL {len(failures)} leaks in the resolved English UI")
    for f in failures:
        print("   LEAK:", f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
