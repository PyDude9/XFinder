#!/bin/sh
# Proves the new L10n tests can fail. A test that has never gone red has proven
# nothing — and this whole module exists because a silent Vietnamese fallback
# looked like a passing build for four reports.
#
# Each case injects one real bug into the shipped store, runs the suite, and
# requires that at least one test turns red. Everything is restored afterwards
# and the restore is verified byte-for-byte.
set -e
cd "$(dirname "$0")/.."

STORE=XFinder/Resources/L10n.strings.json
BACKUP=/tmp/xfinder-l10n-mutation-backup.json
cp "$STORE" "$BACKUP"

restore() {
  cp "$BACKUP" "$STORE"
}
trap restore EXIT

run_case() {
  name="$1"
  echo
  echo "=== $name ==="
  if swift test --package-path Tests 2>&1 | grep -qE "Executed [0-9]+ tests, with [1-9]"; then
    echo "RED as expected"
  else
    echo "STAYED GREEN -- this bug is not covered: $name"
    exit 1
  fi
  restore
}

# 1. The exact bug the user reported: a gesture string with no translation, so
#    L10n.t falls back to the Vietnamese literal in an English UI. The key is now
#    a numbered button label, but the failure shape is identical.
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.strings.json"
d = json.load(open(p, encoding="utf-8"))
del d["entries"]["Nút 3 (bấm con lăn xuống)"]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
run_case "1. delete a numbered button label (the reported leak)"

# 2. A sentence given padding: the classic copy-paste that turns a label into a
#    fragment and produces a double space mid-sentence.
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.strings.json"
d = json.load(open(p, encoding="utf-8"))
d["entries"]["Bật"] = {"en": " On ", "scope": "sentence"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
run_case "2. pad a standalone sentence"

# 3. A fragment that loses its edge space, which silently merges two words when
#    the call site concatenates it.
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.strings.json"
d = json.load(open(p, encoding="utf-8"))
d["entries"][" mục"] = {"en": "items", "scope": "fragment"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
run_case "3. strip a fragment's padding"

# 4. A translation that is just the Vietnamese again, which is what a missing
#    translation looks like once someone has "filled it in" carelessly.
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.strings.json"
d = json.load(open(p, encoding="utf-8"))
d["entries"]["Chuột & cử chỉ"] = {"en": "Chuột & cử chỉ", "scope": "sentence"}
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
run_case "4. translate a string to itself"

# 5. A direction heading dropped from the store, so the leak at
#    GestureDetailPanel.directionTitle returns. The heading is now built from the
#    button number plus this hint fragment, and BOTH halves must resolve.
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.strings.json"
d = json.load(open(p, encoding="utf-8"))
del d["entries"]["kéo sang trái"]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
run_case "5. delete a direction heading fragment"

# 6. The allowlist exception itself removed, so a same-by-design string is
#    reported as untranslated — proves the allowlist is load-bearing rather than
#    decorative.
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.allowlist.json"
d = json.load(open(p, encoding="utf-8"))
d["sameByDesign"] = [x for x in d["sameByDesign"] if x != "OCR"]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF
echo
echo "=== 6. drop the allowlist exception for OCR ==="
if swift test --package-path Tests 2>&1 | grep -qE "Executed [0-9]+ tests, with [1-9]"; then
  echo "RED as expected"
else
  echo "STAYED GREEN -- the allowlist is not actually consulted: OCR"
  exit 1
fi
python3 - <<'EOF'
import json
p = "XFinder/Resources/L10n.allowlist.json"
d = json.load(open(p, encoding="utf-8"))
d["sameByDesign"] = ["Apple Intelligence", "Clipboard", "OCR", "Quick Look"]
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
EOF

restore
trap - EXIT

echo
echo "=== store restored byte-identical? ==="
if cmp -s "$BACKUP" "$STORE"; then
  echo "yes"
else
  echo "NO -- restore failed"
  exit 1
fi

echo
echo "=== suite green again after restore ==="
swift test --package-path Tests 2>&1 | grep -E "Executed [0-9]+ tests, with" | tail -1
