#!/usr/bin/env python3
"""§3b #33 (2026-10-13) — meeting alerts under the notch: register the notice, button and settings strings.

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
    "Sắp đến giờ": ("Coming up", S),
    "Đến giờ lời nhắc": ("Reminder due", S),
    "đang bắt đầu": ("starting now", S),
    "Hoãn 5 phút": ("Snooze 5 min", S),
    "Báo trước sự kiện ở notch": ("Alert before events at the notch", S),
    "Một dòng dưới notch trước sự kiện có giờ và lời nhắc có giờ, với nút Tham gia (khi có link họp) và Hoãn 5 phút. Không báo sự kiện cả ngày.":
        ("A line under the notch before timed events and timed reminders, with Join (when there is a meeting link) and Snooze 5 min. All-day events never alert.", S),
    "Báo trước": ("Alert", S),
    " phút trước sự kiện": (" min before", F),
    "Âm báo khi nhắc": ("Sound with the alert", S),
    # What's New 1.3 (updated bodies)
    "Hôm nay có gì, việc kế tiếp, lịch âm theo giờ Việt Nam, nút Tham gia cho link họp; nhắc họp ngay dưới notch.":
        ("What is on today, what is next, the Vietnamese lunar date, a Join button for meeting links; meeting alerts right under the notch.", S),
    "Bôi đen chữ ở app khác: đổi đơn vị, tiền tệ, múi giờ, tính, thêm vào Lịch, dịch, tra từ điển.":
        ("Select text in another app: convert units, currencies and time zones, calculate, add to Calendar, translate, look it up in the dictionary.", S),
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
