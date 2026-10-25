#!/usr/bin/env python3
"""XF-T30 W6 builder "w6q" — FileOperationQueue / FolderMergeController (2026-10-25). ADD-ONLY: a key already
present with another meaning is a CONFLICT. Run to test, then `git checkout -- XFinder/Resources/L10n.strings.json`
before committing (per the builder's own instructions)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # FileOperationQueue.stageLabelKey — two of the seven stage labels not already in the store (the rest reuse
    # existing keys: Đang chờ/Đang tạm dừng/Đang kiểm/Đang hoàn tất/Xong/Lỗi/Đã dừng).
    "Đang chuẩn bị": ("Preparing", S),
    "Đang chép": ("Copying", S),
    # Redo fragment to pair with the existing "Đã hoàn tác " (Undone: ).
    "Đã làm lại ": ("Redone: ", F),
    # Undo/redo deferred-while-running and unavailable/refused messages (spec R53, R58).
    "Sẽ hoàn tác sau khi việc đang chạy xong": ("Will undo once the running operation finishes", S),
    "Sẽ làm lại sau khi việc đang chạy xong": ("Will redo once the running operation finishes", S),
    "Không thể làm lại thao tác này.": ("This action cannot be redone.", S),
    "Không hoàn tác được…": ("Can't Undo…", S),
}
def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8")); e = data["entries"]
    bad = [k for k, (en, _) in ENTRIES.items() if k in e and e[k].get("en") != en]
    for k in bad: print(f"CONFLICT: {k!r} = {e[k].get('en')!r}")
    if bad: return 1
    added = sum(1 for k in ENTRIES if k not in e)
    for k, (en, sc) in ENTRIES.items(): e.setdefault(k, {"en": en, "scope": sc})
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}"); return 0
if __name__ == "__main__": sys.exit(main())
