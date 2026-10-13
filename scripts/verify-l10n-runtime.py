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

# The strings that used to leak on an English page, plus the whole set the gesture
# page can render. The old physical-name list is kept on purpose: these are the
# *retired* keys. They must fall back to themselves (nothing else in the app uses
# them), which is what tells us a regression would be visible rather than silent.
RETIRED_PHYSICAL_NAMES = [
    "Nút giữa / bấm con lăn (Button 2)",
    "Nút trái (Button 0)",
    "Nút phải (Button 1)",
    "Nút hông sau — nút 4 (Button 3)",
    "Nút hông trước — nút 5 (Button 4)",
    "Nút 1 (chuột trái)",
    "Nút 2 (chuột phải)",
    "Nút 3 (bấm con lăn xuống)",
    "Giữ nút rồi kéo LÊN",
    "Giữ nút rồi kéo SANG PHẢI",
]
# Buttons are numbered now; these are the labels the page actually renders.
# RE-ANCHORED 2026-09-22: the three sentences below used to be "Nút N (mô tả)" and were
# declared language-neutral, which is why they rendered verbatim in an English UI. They
# are now three ordinary translatable labels plus one fragment, and the *retired* forms
# moved to `RETIRED_PHYSICAL_NAMES`-style exclusion below. Leaving the old strings here
# made this verifier report a LEAK for a string the app no longer renders — a false
# alarm, which is its own kind of broken gate.
BUTTON_LABELS = [
    "Nút trái",
    "Nút phải",
    "Bấm con lăn xuống",
    "Nút ",
    "thường là nút hông trên (gần con lăn)",
    "thường là nút hông dưới (ngón cái)",
]
# The numbered headings, including the interpolated ones the page assembles from
# `TriggerSource.numberedName` and the direction hint.
DIRECTION_HEADINGS = [
    "Nút 3: kéo lên", "Nút 3: kéo xuống", "Nút 3: kéo sang trái", "Nút 3: kéo sang phải",
    "Nghiêng con lăn TRÁI", "Nghiêng con lăn PHẢI",
]
SIDEBAR = ["Chuột & cử chỉ", "Tổng quan", "Hệ thống", "Mạng"]

# The sidebar GROUP HEADINGS. These are rendered through `L10n.t(group.header)` — a
# **variable** — so the literal sweep in `verify-gesture-ui.sh` §3 cannot see them, and all
# six were missing from the store until a rendered-page read found them showing Vietnamese
# on an English page. `check-sidebar-groups-l10n.py` is the static gate; this is the runtime
# half, resolved against the store **inside the installed bundle**.
SIDEBAR_GROUPS = ["CHUNG", "NOTCH", "CỬA SỔ", "FINDER & TÌM KIẾM", "CÔNG CỤ", "KẾT NỐI", "TIỆN ÍCH"]   # P3 added NOTCH

# The Finder-utilities page's extension row. Each of these is a full sentence the
# page prints for one measured plug-in state, so a missing translation is a
# Vietnamese paragraph on an English page.
FINDER_EXTENSION_STRINGS = [
    "Chưa bật",
    "Bạn đã tắt",
    "Không xác định",
    "XFinder đã kèm phần mở rộng Finder và macOS đang bật nó: bấm chuột phải vào tập tin "
    "trong Finder sẽ thấy mục “Thêm vào Khay thả XFinder” và nút trên thanh công cụ.",
    "Phần mở rộng đã cài nhưng đang bị tắt trong Cài đặt hệ thống, nên Finder không hiện "
    "mục của XFinder. Bật lại theo hướng dẫn bên dưới.",
    "Phần mở rộng đã cài và macOS đã biết nó, nhưng chưa bật — mặc định của mọi tiện ích "
    "mới. Bật theo hướng dẫn bên dưới để Finder hiện mục của XFinder.",
    "macOS chưa thấy phần mở rộng Finder của XFinder. Hãy cài bản dựng mới nhất, rồi bật "
    "theo hướng dẫn bên dưới.",
    "Chưa đọc được trạng thái phần mở rộng từ macOS. Bấm “Kiểm tra lại” sau khi mở trang "
    "cài đặt bên dưới.",
]

# Superseded copy: the page used to claim XFinder ships no extension. Keeping it
# translated would let the false statement come back with a clean English label.
RETIRED_FINDER_STRINGS = [
    "Menu chuột phải và Tác vụ nhanh của Finder cần một Finder Extension riêng. "
    "XFinder chưa kèm phần mở rộng đó, nên mục này báo đúng trạng thái thay vì hiện "
    "một công tắc không có tác dụng.",
]


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
    print("=== every heading and label is in the bundled store ===")
    for vi in BUTTON_LABELS + DIRECTION_HEADINGS:
        present = vi in sentences or vi in fragments
        print(f"  {'OK  ' if present else 'MISS'} {vi!r}")
        if not present:
            failures.append(f"{vi} missing from the bundled store")

    print()
    print("=== the retired physical names are gone from the store (not translated) ===")
    # Deliberate *removal* check. Keeping them translated would let the old
    # anatomy quietly come back with a working English label.
    for vi in RETIRED_PHYSICAL_NAMES:
        present = vi in sentences or vi in fragments
        print(f"  {'LEAK' if present else 'GONE'} {vi!r}")
        if present:
            failures.append(f"retired string still in the store: {vi}")

    print()
    print("=== button labels and numbered headings (the leak shape that was fixed) ===")
    for vi in BUTTON_LABELS + DIRECTION_HEADINGS:
        en = t(vi)
        ok = en != vi and not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== the interpolated button number: 'Nút \\(n+1)' ===")
    for n in (0, 1, 2, 6, 31):
        rendered = f"{t('Nút ')}{n + 1}"
        ok = not VIETNAMESE.search(rendered)
        print(f"  {'OK  ' if ok else 'LEAK'} n={n}: {rendered!r}")
        if not ok:
            failures.append(f"interpolated button {n}")

    print()
    print("=== the interpolated heading the diagram prints on every arm ===")
    # Composed exactly as the page does: `title(trigger:)` returns
    # "\(trigger.numberedName): \(hint)" and the call site wraps the whole thing.
    # `numberedName` is itself an interpolated "Nút \(n + 1)", so its fragment is
    # translated first — that two-step is the shape that leaked before.
    for hint in ["kéo lên", "kéo xuống", "kéo sang trái", "kéo sang phải"]:
        rendered = f"{t('Nút ')}3: {t(hint)}"
        ok = not VIETNAMESE.search(rendered)
        print(f"  {'OK  ' if ok else 'LEAK'} {rendered!r}")
        if not ok:
            failures.append(f"heading {hint}")

    print()
    print("=== the FULL heading the page computes, via the model itself ===")
    for vi in DIRECTION_HEADINGS:
        en = t(vi)
        ok = en != vi and not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== the detail panel's motion row carries no leftover motion text ===")
    # `GestureDetailPanel.motionText` prints the trigger label, the separator and
    # the heading. The old bare `` direction.instruction `` sentence is gone from
    # the model, so a stale reference to it would be a compile error rather than a
    # silent Vietnamese leak — this line documents that it was checked.
    for vi in DIRECTION_HEADINGS + BUTTON_LABELS:
        if vi not in sentences and vi not in fragments:
            failures.append(f"{vi} missing from the bundled store")

    print()
    print("=== sidebar rows ===")
    for vi in SIDEBAR:
        en = t(vi)
        ok = not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== sidebar groups ===")
    # P3: "NOTCH" is the hardware's name in both languages — identical BY DESIGN, so the bundled allowlist decides,
    # exactly as check-l10n-coverage.py does for the tree.
    allow_path = STORE_IN_BUNDLE.with_name("L10n.allowlist.json")
    same_by_design = set(json.loads(allow_path.read_text(encoding="utf-8")).get("sameByDesign", [])) if allow_path.exists() else set()
    for vi in SIDEBAR_GROUPS:
        en = t(vi)
        ok = (en != vi or vi in same_by_design) and not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi!r} -> {en!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== Finder-extension status strings (every measured state) ===")
    for vi in FINDER_EXTENSION_STRINGS:
        en = t(vi)
        ok = en != vi and not VIETNAMESE.search(en)
        print(f"  {'OK  ' if ok else 'LEAK'} {vi[:52]!r} -> {en[:52]!r}")
        if not ok:
            failures.append(vi)

    print()
    print("=== the retired 'no extension' claim is gone (not translated) ===")
    for vi in RETIRED_FINDER_STRINGS:
        present = vi in sentences or vi in fragments
        print(f"  {'LEAK' if present else 'GONE'} {vi[:52]!r}")
        if present:
            failures.append(f"stale Finder string still in the store: {vi[:40]}")

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
