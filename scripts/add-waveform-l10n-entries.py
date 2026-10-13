#!/usr/bin/env python3
"""§3b #21 (2026-10-13) — live waveform on the Now Playing notch page.

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
    "Sóng nhạc thời gian thực": ("Live waveform", S),
    "Cột sóng theo đúng âm thanh của app đang phát (không lẫn tiếng thông báo). Lần đầu macOS hỏi quyền Ghi âm thanh hệ thống. Chỉ chạy khi sóng đang hiện và nhạc đang phát; không ghi lại gì. Cần macOS 14.2.":
        ("Bars that follow the playing app's own audio (notification sounds never move them). macOS asks for the System Audio Recording permission the first time. Runs only while the waveform is on screen and music is playing; nothing is recorded. Needs macOS 14.2.", S),
    "Sóng nhạc chỉ nhận được im lặng — có thể chưa cấp quyền Ghi âm thanh hệ thống.":
        ("The waveform only receives silence — the System Audio Recording permission may not be granted.", S),
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
