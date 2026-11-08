#!/usr/bin/env python3
"""Boss review of the Gemini translate branch (2026-11-08): honest copy for the network translate engines.

Idempotent, ADD-ONLY: an existing key is never rewritten; a key that already exists with different English stops
the script.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES: dict[str, tuple[str, str]] = {
    "Đọc chữ đang bôi đen qua Trợ năng rồi mở thẻ dịch. Từ điển macOS chạy trên máy; Google Dịch và Dịch AI, khi bật, gửi chữ bạn chọn tới dịch vụ đó. App nào không cho Trợ năng đọc vùng chọn thì panel nói rõ.":
        ("Reads the highlighted text through Accessibility and opens the translate card. The macOS dictionary runs on this Mac; Google Translate and AI translation, when on, send the text you selected to that service. Apps that do not let Accessibility read the selection are named in the panel.", S),
    "Gửi chữ bạn bôi đen tới Google qua một địa chỉ không chính thức (không cần khoá API, ~200 ms). Google có thể chặn hay đổi địa chỉ này bất cứ lúc nào; tắt nếu chữ bạn chọn không được rời máy.":
        ("Sends the text you highlight to Google through an unofficial address (no API key, ~200 ms). Google can block or change it at any time; turn it off if your selection must not leave this Mac.", S),
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
