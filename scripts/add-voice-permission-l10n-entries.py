#!/usr/bin/env python3
"""XF-VOICE-PERMISSIONS: the HUD lines and Voice-page row labels of VoicePermissionRules. ADD-ONLY.

Idempotent: an existing key is never rewritten; a key that exists with different English stops the script and writes
nothing. "Đã cấp", "Cần cấp quyền", "Yêu cầu" and "Mở Cài đặt hệ thống" are reused as they are.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
ENTRIES: dict[str, tuple[str, str]] = {
    "Micro đang bị từ chối cho XFinder": ("Microphone access is denied for XFinder", S),
    "Nhận dạng giọng nói đang bị từ chối cho XFinder": ("Speech Recognition is denied for XFinder", S),
    "Micro bị giới hạn trên máy này": ("Microphone is restricted on this Mac", S),
    "Nhận dạng giọng nói bị giới hạn trên máy này": ("Speech Recognition is restricted on this Mac", S),
    "Đã cấp quyền — nhấn phím lần nữa để nói": ("Permission granted — press the key again to talk", S),
    "Đã từ chối": ("Denied", S),
    "Bị giới hạn": ("Restricted", S),
}

def main() -> int:
    data = json.loads(STORE.read_text(encoding="utf-8"))
    entries = data["entries"]
    conflicts = [k for k, (en, _) in ENTRIES.items() if k in entries and entries[k].get("en") != en]
    if conflicts:
        for k in conflicts:
            print(f"CONFLICT: {k!r} already means {entries[k].get('en')!r}")
        return 1
    added = 0
    for k, (en, scope) in ENTRIES.items():
        if k not in entries:
            entries[k] = {"en": en, "scope": scope}
            added += 1
    STORE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"added {added}, already present {len(ENTRIES) - added}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
