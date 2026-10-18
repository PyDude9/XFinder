#!/usr/bin/env python3
"""XF-T21 (2026-10-18) — Chia sẻ nhanh and Kết nối từ xa join FeatureCatalog. ADD-ONLY: an existing key with another meaning is
a CONFLICT (exit 1), never rewritten. "Chia sẻ nhanh" / "Kết nối từ xa" already exist (page titles) and are reused as is."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES = {
    "Kết nối": ("Connect", S),
    "Liên kết tải file cho thiết bị cùng mạng Wi-Fi. Tắt là thu hồi mọi liên kết và dừng máy chủ ngay.":
        ("Download links for devices on the same Wi-Fi. Turning it off revokes every link and stops the server at once.", S),
    "Tải file lên máy chủ SSH bằng scp khi bạn bấm Tải lên. Tắt là không gửi gì ra mạng.":
        ("Uploads files to an SSH server with scp when you press Upload. Off means nothing is sent over the network.", S),
    "Cho phép Chia sẻ nhanh": ("Allow Quick Share", S),
    "Tắt là thu hồi mọi liên kết và dừng máy chủ ngay; không file nào được phục vụ nữa.":
        ("Turning it off revokes every link and stops the server at once; no file is served any more.", S),
    "Chia sẻ nhanh đang tắt — bật ở trên để tạo liên kết.": ("Quick Share is off — turn it on above to create links.", S),
    "Cho phép Kết nối từ xa": ("Allow Remote Connect", S),
    "Tắt là XFinder không chạy ssh hay scp nữa: Kiểm tra và Tải lên đều bị chặn. Danh sách kết nối vẫn giữ.":
        ("Off means XFinder no longer runs ssh or scp: Test and Upload are both blocked. Your connections are kept.", S),
    "Kết nối từ xa đang tắt — bật lại ở đầu trang.": ("Remote Connect is off — turn it back on at the top of the page.", S),
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
