#!/bin/sh
# Final acceptance check for the Mouse & Gestures page. Every line prints a
# measured result; nothing here is inferred from "the build said SUCCEEDED".
set -e
cd "$(dirname "$0")/.."

echo "=== 1. L10n: duplicate keys (fatal crash at launch if nonzero) ==="
python3 scripts/check-l10n-duplicates.py

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
import re
files = ["XFinder/Views/Detail/MouseGesturesDetailView.swift",
         "XFinder/Views/Components/MouseDiagramView.swift",
         "XFinder/Views/Components/GestureDetailPanel.swift",
         "XFinder/Core/MouseGestures/GestureModel.swift",
         "XFinder/Core/MouseGestures/GestureUIDisplay.swift",
         "XFinder/Models/SidebarDestination.swift"]
src = "".join(open(f, encoding='utf-8').read() for f in files)
keys = set(re.findall(r'L10n\.t\("((?:[^"\\]|\\.)*)"\)', src))
strings = "".join(open(f, encoding='utf-8').read() for f in
    ["XFinder/Core/L10n.swift","XFinder/Core/L10nStrings.swift","XFinder/Core/L10nDB.swift"])
missing = sorted(k for k in keys if ('"%s":' % k) not in strings)
print(f"keys used: {len(keys)} | missing: {len(missing)}")
for m in missing: print("  MISSING:", m)
PYEOF

echo
echo "=== 4. Tests ==="
swift test --package-path Tests 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -1

echo
echo "=== 5. New sources present in the compile log by name ==="
grep -E "MouseDiagramView|GestureDetailPanel|GestureUIDisplay|MouseGesturesDetailView" \
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
