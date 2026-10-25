#!/usr/bin/env python3
"""XF-T30 W3 builder "w3v" — BrowserSidebarView + EjectGuard + ConnectToServer banner strings (2026-10-25). ADD-ONLY:
a key already present with another meaning is a CONFLICT. Builders append the keys their views need to ENTRIES."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # integration 2026-10-25: ConnectToServer strings the builder's script missed
    "Không kết nối được máy chủ": ("Couldn't connect to the server", S),
    "Địa chỉ không hợp lệ (smb:// afp:// nfs:// ftp:// webdav)": ("Invalid address (smb:// afp:// nfs:// ftp:// webdav)", S),
    "Kết nối máy chủ": ("Connect to Server", S),
    "Gần đây và ưa thích": ("Recent and Favorites", S),
    # BrowserSidebarView: eject flow, sidebar sections, AirDrop
    "Buộc đẩy": ("Force Eject", S),
    "Chỉ phân vùng này": ("Just This Volume", S),
    "Cục bộ": ("Local", S),
    "Hiện trong thư mục chứa": ("Show in Enclosing Folder", S),
    "Một ứng dụng đang dùng ổ này. Đẩy ngay có thể làm mất dữ liệu chưa lưu.": (
        "An app is using this disk. Ejecting now may lose its unsaved changes.", S),
    "Ngoài": ("External", S),
    "Tất cả thẻ…": ("All Tags…", S),
    "macOS không cho ứng dụng khác hiện thiết bị AirDrop gần đây — bấm để mở AirDrop của Finder": (
        "macOS doesn't let other apps show nearby AirDrop devices — click to open Finder's AirDrop", S),
    "Đám mây": ("Cloud", S),
    "Đẩy mọi phân vùng": ("Eject All Volumes", S),
    "Đẩy ổ đĩa này?": ("Eject This Disk?", S),
    "Ổ này có nhiều phân vùng. Bạn muốn đẩy chỉ phân vùng này hay mọi phân vùng trên ổ?": (
        "This disk has several volumes. Eject just this one, or every volume on the disk?", S),
    "Ổ đĩa đang bận": ("Disk Is Busy", S),
    "Ứng dụng ": ("App ", F),
    " đang dùng ổ này. Đẩy ngay có thể làm mất dữ liệu chưa lưu của ứng dụng đó.": (
        " is using this disk. Ejecting now may lose that app's unsaved changes.", F),
    # BrowserWindowModel.showBanner keys (rendered through L10n.t at the banner view, not wrapped at the call site —
    # same shape as the pre-existing "Đồng bộ xong" / "Không đẩy được ổ…" banner keys in BrowserWindowModel.swift)
    "AirDrop không khả dụng cho các mục này trên máy này.": ("AirDrop isn't available for these items on this Mac.", S),
    "Không đẩy được — XFinder đang thực hiện một thao tác tệp trên ổ này.": (
        "Can't eject — XFinder is running a file operation on this disk.", S),
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
