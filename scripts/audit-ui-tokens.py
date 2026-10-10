#!/usr/bin/env python3
"""UI-token gate for the flat System-Settings pages (Phase A of docs/REDESIGN_PLAN_2026-10.md).

Fails when a file in XFinder/Views/Detail/ (the pages) still:
  * uses `SettingsCard(` / `TileCard(` as a section box (tiles belong to grids in Components/),
  * sets a font size with a literal (`.font(.system(size: 13` …) instead of `XFinderTokens.Font.*`,
  * draws a RoundedRectangle with a literal radius instead of `XFinderTokens.Radius.*`,
  * opens `body` with a bare `Text(` title instead of `PageHeader(`,
  * uses `.pickerStyle(.segmented)` on a picker with more than 4 `.tag(` or a `ForEach` (unbounded).

Exit 1 on any problem. Prints `TOTAL N problems across K files`. Components/ is exempt on purpose —
that is where the literals are supposed to live, once.
"""
import re, sys, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGES = sorted((ROOT / "XFinder/Views/Detail").glob("*.swift"))
problems = []
FONT = re.compile(r"\.font\(\.system\(size:\s*\d")
RADIUS = re.compile(r"RoundedRectangle\(cornerRadius:\s*\d")
for f in PAGES:
    text = f.read_text(encoding="utf-8")
    rel = f.relative_to(ROOT)
    for i, line in enumerate(text.splitlines(), 1):
        if line.strip().startswith("//"): continue
        if "SettingsCard(" in line or "TileCard(" in line:
            problems.append(f"{rel}:{i}: boxed card used as a page section")
        if FONT.search(line):
            problems.append(f"{rel}:{i}: literal font size — use XFinderTokens.Font")
        if RADIUS.search(line):
            problems.append(f"{rel}:{i}: literal corner radius — use XFinderTokens.Radius")
    # bare title: the first Text( inside the first VStack of body with a 22/26 bold font
    # A file may declare itself an embedded panel (no page chrome of its own) with this marker.
    if "PageHeader(" not in text and "audit-ui-tokens: embedded-panel" not in text:
        problems.append(f"{rel}: page has no PageHeader")
    # Segmented pickers: scope each `.pickerStyle(.segmented)` to the NEAREST preceding `Picker(` so
    # two pickers on one page are never read as one (that false positive once pushed a 2-option
    # picker into a menu). `// segmented-ok` on the pickerStyle line asserts the ForEach has ≤ 4 cases.
    for sm in re.finditer(r"\.pickerStyle\(\.segmented\)([^\n]*)", text):
        if "segmented-ok" in sm.group(1): continue
        start = text.rfind("Picker(", 0, sm.start())
        block = text[start:sm.start()] if start >= 0 else ""
        tags = len(re.findall(r"\.tag\(", block))
        line = text.count("\n", 0, sm.start()) + 1
        if "ForEach" in block:
            problems.append(f"{rel}:{line}: segmented picker over a ForEach — add `// segmented-ok` if the enum has ≤ 4 cases, else use PickerRow/.menu")
        elif tags > 4:
            problems.append(f"{rel}:{line}: segmented picker with {tags} options — use PickerRow/.menu")
for p in problems: print("PROBLEM", p)
files = {p.split(":")[0] for p in problems}
print(f"TOTAL {len(problems)} problems across {len(files)} files")
sys.exit(1 if problems else 0)
