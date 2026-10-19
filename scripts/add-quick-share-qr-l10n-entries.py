#!/usr/bin/env python3
"""Quick Share QR codes + the index page (2026-10-19). ADD-ONLY: an existing key with another meaning is a CONFLICT (exit 1)."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "QR cho tất cả": ("QR for all", S),
    "Mọi file đang chia sẻ": ("Every file being shared", S),
    "Ai có mã này thấy cả danh sách. Quét bằng Camera của điện thoại cùng Wi-Fi.":
        ("Anyone with this code sees the whole list. Scan it with the camera of a phone on the same Wi-Fi.", S),
    "Mã QR cho điện thoại quét": ("QR code for a phone to scan", S),
    "Quét bằng Camera của điện thoại cùng Wi-Fi — không cần cài app.":
        ("Scan with the camera of a phone on the same Wi-Fi — nothing to install.", S),
    "Điện thoại lấy liên kết bằng cách **quét mã QR** (nút QR cạnh mỗi file, hoặc một mã chung cho cả danh sách) — Camera của iPhone và Android mở thẳng, không cần cài gì. Wi-Fi khách có bật cách ly thiết bị sẽ chặn.":
        ("A phone gets the link by **scanning a QR code** (the QR button beside each file, or one code for the whole list) — the iPhone and Android camera opens it directly, nothing to install. A guest Wi-Fi with client isolation blocks it.", S),
    "File chia sẻ từ máy Mac": ("Files shared from the Mac", S),
    "Không còn file nào đang chia sẻ.": ("Nothing is being shared any more.", S),
    "Chạm vào một file để tải về. Liên kết chỉ hoạt động trong cùng mạng Wi-Fi và tự hết hạn.":
        ("Tap a file to download it. Links work only on the same Wi-Fi and expire on their own.", S),
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
