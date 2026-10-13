#!/usr/bin/env python3
"""§3b #37 (2026-10-13) — AI usage strip on the notch Agents page.

Idempotent, ADD-ONLY (same contract as add-smartselect-l10n-entries.py): an existing key is never rewritten; a key that
exists with different English stops the script. Model keys (CaptureMode / CaptureAfter / AnnotationTool / StrokeWidth
titles) reach the screen through `L10n.t(variable)`; CaptureRulesTests / AnnotationTests resolve them against the store.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    " · 5 giờ: ": (" · 5 h: ", F),
    " token ra": (" tokens out", F),
    " · 7 ngày: ": (" · 7 days: ", F),
    "Token đọc từ lịch sử phiên trên máy này. Claude Code không ghi phần trăm hạn mức ra máy, nên đây không phải %.":
        ("Tokens read from the session history on this Mac. Claude Code keeps no allowance percentage locally, so this is not a %.", S),
    " · 5 giờ ": (" · 5 h ", F),
    " · tuần ": (" · week ", F),
    "Hạn mức do chính Codex ghi vào log của nó, ở lần dùng gần nhất.": ("Limits as Codex itself wrote them to its log, at its last use.", S),
    " · đã qua giờ reset — số mới có sau lần dùng Codex kế tiếp": (" · past its reset — a new figure comes with the next Codex use", F),
}

def main() -> None:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data.get("entries", data)
    added, conflicts = 0, []
    for vi, (en, scope) in ENTRIES.items():
        cur = entries.get(vi)
        if cur is None:
            entries[vi] = {"en": en, "scope": scope}
            added += 1
        elif cur.get("en") != en or cur.get("scope") != scope:
            conflicts.append((vi, cur, en, scope))
    if conflicts:
        for vi, cur, en, scope in conflicts:
            print(f"CONFLICT {vi!r}: store has {cur!r}, script wants {{'en': {en!r}, 'scope': {scope!r}}}")
        print("Nothing written."); sys.exit(1)
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Added {added} entries (0 rewritten). Total in store: {len(entries)}")

if __name__ == "__main__":
    main()
