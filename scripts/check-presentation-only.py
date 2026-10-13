#!/usr/bin/env python3
"""P4 (2026-10-13) — prove a page restyle changed PRESENTATION only.

For every changed file in XFinder/Views/Detail/ (vs HEAD, or vs the ref given as argv[1]) compare, old vs new:
  * every `@AppStorage(...) …` / `@State …` / `@Environment …` declaration line (normalised whitespace) — a lost one is a
    lost setting, a changed default flips a feature (Part 0 §5);
  * the multiset of `L10n.t("…")` / `L10n.md("…")` literals — a restyle moves strings, it never drops or invents copy;
  * the multiset of `.onChange(of: X) { … }` side effects (subject + body, normalised);
  * the multiset of lifecycle bodies — `.onAppear`, `.onDisappear`, `.task`, `.onReceive` — the pages that sample metrics
    call retain()/release() there, so a dropped one is a frozen page or a timer that never stops (idle CPU 0 %);
  * the count of each control constructor (Toggle, ToggleRow, PickerRow, Picker, ActionRow, Button, TextField, Slider,
    Stepper, Menu, DatePicker, ColorPicker) — a missing one is a control that vanished in the move.
A difference is printed with the file; exit 1 if any. Known, intended exceptions go on the command line as
`--allow <file>:<kind>` so every exception is visible in the commit that makes it.
"""
from __future__ import annotations
import re, subprocess, sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
args = [a for a in sys.argv[1:] if not a.startswith("--allow")]
allow = {a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--allow=")}
REF = args[0] if args else "HEAD"

DECL = re.compile(r"^\s*@(AppStorage|State|Environment|FocusState|Bindable)\b.*$", re.M)
LIT = re.compile(r'L10n\.(?:t|md)\(\s*"((?:[^"\\]|\\.)*)"\s*\)', re.S)
ONCHANGE = re.compile(r"\.onChange\(of:\s*([^)]*)\)\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}", re.S)
LIFECYCLE = re.compile(r"\.(onAppear|onDisappear|task|onReceive)\b[^{]*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}", re.S)
CONTROLS = ["Toggle(", "ToggleRow(", "PickerRow(", "Picker(", "ActionRow(", "Button(", "TextField(", "SecureField(",
            "Slider(", "Stepper(", "Menu(", "DatePicker(", "ColorPicker(", "TextEditor("]


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def strip_comments(src: str) -> str:
    return "\n".join(l for l in src.splitlines() if not l.strip().startswith("//"))


def facts(src: str) -> dict[str, Counter]:
    src = strip_comments(src)
    return {
        "declarations": Counter(norm(m.group(0)) for m in DECL.finditer(src)),
        "strings": Counter(m.group(1) for m in LIT.finditer(src)),
        "onChange": Counter(norm(m.group(1)) + " => " + norm(m.group(2)) for m in ONCHANGE.finditer(src)),
        "lifecycle": Counter(m.group(1) + " => " + norm(m.group(2)) for m in LIFECYCLE.finditer(src)),
        "controls": Counter({c: len(re.findall(r"(?<![A-Za-z])" + re.escape(c), src)) for c in CONTROLS}),
    }


def git(*a: str) -> str:
    return subprocess.run(["git", "-C", str(ROOT), *a], capture_output=True, text=True).stdout


changed = [f for f in git("diff", "--name-only", REF, "--", "XFinder/Views/Detail").split() if f.endswith(".swift")]
problems = 0
checked = 0
for f in changed:
    old_src = git("show", f"{REF}:{f}")
    if not old_src:
        continue  # a new file — nothing to preserve
    new_path = ROOT / f
    if not new_path.exists():
        print(f"{f}: DELETED"); problems += 1; continue
    old, new = facts(old_src), facts(new_path.read_text(encoding="utf-8"))
    checked += 1
    for kind in old:
        if f"{Path(f).name}:{kind}" in allow:
            continue
        if old[kind] != new[kind]:
            lost = old[kind] - new[kind]
            gained = new[kind] - old[kind]
            problems += 1
            print(f"{f}: {kind} changed")
            for k, n in lost.items():
                print(f"    - {n}× {k[:150]}")
            for k, n in gained.items():
                print(f"    + {n}× {k[:150]}")
print(f"TOTAL {problems} differences across {checked} changed pages (vs {REF})")
sys.exit(1 if problems else 0)
