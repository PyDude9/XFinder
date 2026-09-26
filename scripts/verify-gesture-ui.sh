#!/bin/sh
# Final acceptance check for the Mouse & Gestures page. Every line prints a
# measured result; nothing here is inferred from "the build said SUCCEEDED".
set -e
cd "$(dirname "$0")/.."

echo "=== 1. L10n store coverage (duplicate keys crash at launch if nonzero) ==="
python3 scripts/check-l10n-coverage.py

echo
echo "=== 1b. Sidebar group headers are translated (the variable-passed-key leak) ==="
# These six headings reach the screen through `L10n.t(group.header)` — a *variable* — so the
# literal sweep in §3 cannot see them, and they rendered Vietnamese on an English page until
# a rendered-page read found them. The gate fails loudly if its own parse goes stale.
python3 scripts/check-sidebar-groups-l10n.py

echo
echo "=== 2. L10n: VI literals not wrapped in t() in Views/ ==="
python3 - <<'PYEOF'
import re, glob
VI = re.compile(r'[\u00c0-\u1ef9]')
STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
total = 0
for f in glob.glob("XFinder/Views/**/*.swift", recursive=True):
    for i, line in enumerate(open(f, encoding='utf-8')):
        if line.strip().startswith('//'): continue
        for m in STR.finditer(line):
            if not VI.search(m.group(1)): continue
            p = line[:m.start()].rstrip()
            if p.endswith('L10n.t(') or p.endswith('L10n.md('): continue
            total += 1; print(f"{f}:{i+1}: {line.strip()}")
print("TOTAL", total)
PYEOF

echo
echo "=== 3. L10n: every key the gesture UI uses has a translation ==="
python3 - <<'PYEOF'
import re, json
files = ["XFinder/Views/Detail/MouseGesturesDetailView.swift",
         "XFinder/Views/Components/MouseDiagramView.swift",
         "XFinder/Views/Components/GestureDetailPanel.swift",
         # The Mac-Mouse-Fix-style UI split into three components: the arm (a real
         # button), the action picker (generated from the intent vocabulary) and the
         # measured-activity panel. Each renders sentences, so each must be swept.
         "XFinder/Views/Components/GestureArmView.swift",
         "XFinder/Views/Components/GestureActionPicker.swift",
         "XFinder/Views/Components/GestureActivityPanel.swift",
         # PATCH v9.1: the list of the mouse's own controls. It renders role labels and
         # explanations through `L10n.t(variable)`, so it belongs in the sweep and in the
         # compile-log check below — a component outside both is how a page ships
         # untranslated words plus a pbxproj entry that never got written.
         "XFinder/Views/Components/GestureButtonList.swift",
         "XFinder/Core/MouseGestures/GestureModel.swift",
         # The intent vocabulary and the built-in map. Every `labelKey`/`groupKey` here
         # is a Vietnamese literal that only `L10n.t` turns into words, so it has to be
         # in this sweep or the English page silently renders Vietnamese action names.
         "XFinder/Core/MouseGestures/GestureMap.swift",
         # The engine's diagnostic labels, which the activity panel renders.
         "XFinder/Core/MouseGestures/GestureEngine.swift",
         # The label-and-heading vocabulary. `GestureUIDisplay.swift` used to be
         # listed here, but it no longer renders anything: the heading structure
         # moved to `GestureLabelStructure.swift` and the words to `L10n.t`.
         "XFinder/Core/MouseGestures/GestureLabelStructure.swift",
         "XFinder/Core/MouseGestures/DeviceCapabilityModel.swift",
         # The system-action path: how Mission Control / App Exposé / Show Desktop / the two
         # Space moves are resolved, and the read of the machine's own symbolic hotkeys.
         # Both render captions or feed the warning text, so both belong in the sweep.
         "XFinder/Core/MouseGestures/SpaceBinding.swift",
         "XFinder/Models/SidebarDestination.swift"]
src = "".join(open(f, encoding='utf-8').read() for f in files)
keys = set(re.findall(r'L10n\.t\("((?:[^"\\]|\\.)*)"\)', src))
store = json.load(open("XFinder/Resources/L10n.strings.json", encoding='utf-8'))
entries = store["entries"] if isinstance(store, dict) and "entries" in store else store
have = {e["key"] for e in entries} if isinstance(entries, list) else set(entries)
allow = set()
try:
    al = json.load(open("XFinder/Resources/L10n.allowlist.json", encoding='utf-8'))
    for e in (al.get("sameByDesign") or []):
        allow.add(e if isinstance(e, str) else e.get("key"))
except FileNotFoundError:
    pass
missing = sorted(k for k in keys if k not in have and k not in allow)
print(f"keys used: {len(keys)} | missing: {len(missing)}")
for m in missing: print("  MISSING:", m)
if missing: raise SystemExit(1)
PYEOF

echo
echo "=== 4. Tests ==="
# From Tests/: from the repo root `swift test` reports 0 tests, which would make
# everything below look green while proving nothing.
(cd Tests && swift test 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -1)

echo
echo "=== 5. New sources present in the compile log by name ==="
grep -E "MouseDiagramView|GestureDetailPanel|GestureArmView|GestureActionPicker|GestureActivityPanel|GestureButtonList|GestureMap|GestureUIDisplay|MouseGesturesDetailView|DeviceCapability|GestureLabelStructure|SpaceBinding" \
  /tmp/xfinder-clean-build/dd/Build/Intermediates.noindex/XFinder.build/Debug/XFinder.build/Objects-normal/arm64/XFinder.SwiftFileList

echo
echo "=== 6. Installed binary: arch, signature, running ==="
lipo -archs /Applications/XFinder.app/Contents/MacOS/XFinder.debug.dylib
codesign -d -r- /Applications/XFinder.app 2>&1 | grep designated
pgrep -x XFinder >/dev/null && echo "app: RUNNING (pid $(pgrep -x XFinder))" || echo "app: not running"

echo
echo "=== 7. Event Tap state as measured by the app itself ==="
python3 - <<'PYEOF'
import plistlib, pathlib, json
d = plistlib.loads((pathlib.Path.home()/'Library/Preferences/com.xfinder.app.plist').read_bytes())
print("lastTapState:", d.get('mouseGestures.lastTapState'))
c = d.get('mouseGestures.configuration.v1')
if c:
    j = json.loads(c)
    print("enabled:", j.get('enabled'), "| trigger:", j.get('trigger'),
          "| overrides:", j.get('overrides'))
PYEOF
