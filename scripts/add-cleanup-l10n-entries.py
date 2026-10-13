#!/usr/bin/env python3
"""F1 (2026-10-13) — Dọn rác thư mục: register the page and `JunkCleanup.Kind` strings in the L10n store.

ADD-ONLY, like add-smartselect-l10n-entries.py: an existing key is never rewritten; a key that exists with a different
English text stops the script (CONFLICT, nothing written). `Kind.titleKey` / `explanationKey` reach the screen through
`L10n.t(variable)`, so `JunkCleanupTests.testEveryKindStringIsTranslated` resolves them.
"""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    "Dọn rác thư mục": ("Folder Cleanup", S),
    "Gỡ .DS_Store, ._tên, __MACOSX, Thumbs.db… khỏi một thư mục trước khi nén, chép sang USB hay gửi cho máy Windows. Xem trước, chỉ vào Thùng rác.":
        ("Remove .DS_Store, ._name, __MACOSX, Thumbs.db… from a folder before you zip it, copy it to a USB stick or send it to a Windows PC. Preview first, Trash only.", S),
    "Chỉ chọn siêu dữ liệu đã biết của Finder, AppleDouble, file nén và Windows — không bao giờ chọn \"file tạm\" chung chung. Không đi theo bí danh hay liên kết, không vào bên trong gói ứng dụng, không sang ổ khác, bỏ qua file iCloud chưa tải. Finder có thể tạo lại .DS_Store khi bạn mở thư mục.":
        ("Only known Finder, AppleDouble, archive and Windows metadata is selected — never \"temporary files\" in general. Aliases and links are not followed, app packages are not entered, other volumes are not crossed, iCloud files that are not downloaded are skipped. Finder may recreate .DS_Store when you open the folder.", S),
    "Thư mục cần dọn": ("Folder to clean", S),
    "Chưa chọn thư mục": ("No folder chosen", S),
    "Dùng thư mục đang chọn trong Finder": ("Use the folder selected in Finder", S),
    "Quét lại": ("Scan again", S),
    "Hoặc thả một thư mục vào đây": ("Or drop a folder here", S),
    "Sẽ chuyển vào Thùng rác": ("Will be moved to the Trash", S),
    "Bỏ chọn nhóm nào bạn muốn giữ lại.": ("Untick any group you want to keep.", S),
    "Đang quét…": ("Scanning…", S),
    "Chọn một thư mục để xem có gì cần dọn.": ("Choose a folder to see what there is to clean.", S),
    "Đã huỷ quét — danh sách dưới đây chưa đủ.": ("Scan cancelled — the list below is incomplete.", S),
    "Thư mục quá lớn: chỉ xem ": ("Folder too large: only the first ", F),
    " mục đầu. Hãy chọn một thư mục nhỏ hơn.": (" items were checked. Choose a smaller folder.", F),
    "Thư mục này đã sạch — không có rác metadata nào.": ("This folder is already clean — no metadata junk.", S),
    "Xem đường dẫn": ("Show paths", S),
    "Đã xem ": ("Checked ", F),
    " gói ứng dụng không mở vào": (" app packages not entered", F),
    " mục iCloud chưa tải bị bỏ qua": (" iCloud items not downloaded, skipped", F),
    "Hãy chọn một thư mục trong Finder rồi bấm lại.": ("Select a folder in Finder, then click again.", S),
    "Đó không phải thư mục.": ("That is not a folder.", S),
    " mục vào Thùng rác — mở Thùng rác để khôi phục nếu cần.": (" items to the Trash — open the Trash to restore them if needed.", F),
    " mục đã đổi sau khi quét nên được giữ nguyên.": (" items changed after the scan and were left alone.", F),
    " mục không chuyển được: ": (" items could not be moved: ", F),
    # JunkCleanup.Kind
    "Thiết lập hiển thị của Finder (.DS_Store)": ("Finder view settings (.DS_Store)", S),
    "Siêu dữ liệu AppleDouble (._tên)": ("AppleDouble metadata (._name)", S),
    "Thư mục __MACOSX trong file nén": ("__MACOSX folders from archives", S),
    "Ảnh thu nhỏ của Windows (Thumbs.db)": ("Windows thumbnails (Thumbs.db)", S),
    "Thiết lập thư mục của Windows (desktop.ini)": ("Windows folder settings (desktop.ini)", S),
    "Finder ghi vị trí biểu tượng và kiểu xem. Vô hại khi xoá; Finder có thể tạo lại khi bạn mở thư mục.":
        ("Finder stores icon positions and the view style here. Harmless to remove; Finder may recreate it when you open the folder.", S),
    "Nhãn, xattr của macOS khi chép sang ổ không phải APFS (USB, ổ mạng). Chỉ chọn file có đầu AppleDouble thật.":
        ("macOS tags and extended attributes, written when copying to a non-APFS drive (USB, network share). Only files with a real AppleDouble header are selected.", S),
    "Do công cụ nén để lại khi giải nén trên máy khác. Chỉ chọn khi bên trong toàn là siêu dữ liệu.":
        ("Left by zip tools when an archive made on a Mac is extracted elsewhere. Selected only when everything inside is metadata.", S),
    "Windows tự tạo để hiện ảnh thu nhỏ. Windows tạo lại khi cần.":
        ("Created by Windows to show thumbnails. Windows recreates it when needed.", S),
    "Windows ghi biểu tượng và tên hiển thị của thư mục. Chỉ có tác dụng trên Windows.":
        ("Windows stores the folder's icon and display name here. It only has an effect on Windows.", S),
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
