#!/usr/bin/env python3
"""Check every mouse-gesture preset's bundle id against the apps installed on THIS Mac.

Why: on 2026-10-15 eight presets (Claude, VS Code, Cursor, Antigravity, CapCut, AyuGram, Obsidian, Notion) turned out to
be keyed by bundle ids that no installed app had, so those apps silently used the Global table. Nothing in the unit
tests can catch that — it is a fact about the machine, not the code — so this is a measurement you run, not a gate.

For each preset: OK when an app with that id is installed; otherwise it looks for an app with the preset's display name
in /Applications and ~/Applications and prints the id that app really has. Optional argument: another copy of
GestureModel.swift to check (used to prove the check fails on the pre-fix table). Exit code 1 when an installed app's real id
differs from its preset id (a preset that can never apply); 0 otherwise. Not-installed apps are reported, never fatal.
"""
import pathlib, plistlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODEL = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "XFinder/Core/MouseGestures/GestureModel.swift"

def presets():
    src = MODEL.read_text(encoding="utf-8")
    body = src[src.index("static let all: [GestureProfile]"):src.index("static func hasPreset")]
    pairs = re.findall(r'\(\s*"([A-Za-z0-9.\-]+\.[A-Za-z0-9.\-]+)",\s*"([^"]+)"\)', body)
    pairs += re.findall(r'profile\(\s*"([A-Za-z0-9.\-]+\.[A-Za-z0-9.\-]+)",\s*"([^"]+)"', body)
    seen, out = set(), []
    for bid, name in pairs:
        if bid not in seen:
            seen.add(bid); out.append((bid, name))
    if len(out) < 15:
        sys.exit(f"FATAL: parsed only {len(out)} presets from {MODEL} — the anchors rotted")
    return out

def installed(bid):
    r = subprocess.run(["mdfind", f"kMDItemCFBundleIdentifier == '{bid}'"], capture_output=True, text=True)
    return [line for line in r.stdout.splitlines() if line.endswith(".app")]

# Preset display names that differ from the app bundle's file name.
ALIASES = {"VS Code": "Visual Studio Code", "Chrome": "Google Chrome", "Kitty": "kitty"}

def app_named(name):
    """Apps whose file name equals the preset name (or its alias); substring matches only when there is no exact one,
    so "Claude" finds Claude.app and not "Claude Code URL Handler.app"."""
    want = ALIASES.get(name, name).lower()
    apps = [a for base in (pathlib.Path("/Applications"), pathlib.Path.home() / "Applications") for a in base.glob("*.app")]
    exact = [a for a in apps if a.stem.lower() == want]
    for app in exact or [a for a in apps if want in a.stem.lower()]:
        try:
            info = plistlib.load(open(app / "Contents/Info.plist", "rb"))
            yield app, info.get("CFBundleIdentifier")
        except Exception:
            continue

wrong = 0
for bid, name in presets():
    hits = installed(bid)
    if hits:
        print(f"OK       {name:14} {bid:34} {hits[0]}")
        continue
    alt = [(a, real) for a, real in app_named(name) if real and real != bid]
    if alt:
        wrong += 1
        for app, real in alt:
            print(f"WRONG    {name:14} {bid:34} installed app {app} has {real}")
    else:
        print(f"ABSENT   {name:14} {bid:34} (not installed here — unmeasured)")
print(f"TOTAL {wrong} preset(s) keyed by an id the installed app does not have")
sys.exit(1 if wrong else 0)
