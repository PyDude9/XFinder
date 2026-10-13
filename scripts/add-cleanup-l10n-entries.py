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
    # F2 — Gỡ ứng dụng
    "Gỡ ứng dụng": ("Uninstall Apps", S),
    "Chuyển một app và những gì nó để lại trong Thư viện của bạn vào Thùng rác — xem từng mục trước.":
        ("Move an app and what it left in your Library to the Trash — see every item first.", S),
    "XFinder chỉ chọn sẵn những gì mang đúng mã nhận dạng (bundle id) của app. Thư mục trùng tên app chỉ là đoán nên để trống. Container của app (Thư viện ▸ Containers) được macOS bảo vệ — XFinder không chuyển được (đã đo); bấm Hiện trong Finder rồi kéo vào Thùng rác. Không gỡ app của Apple, app đang chạy hay chính XFinder.":
        ("XFinder only pre-selects items that carry the app's exact identifier (bundle id). A folder that merely has the app's name is a guess and stays unticked. App containers (Library ▸ Containers) are protected by macOS — XFinder cannot move them (measured); click Show in Finder and drag them to the Trash. Apple's apps, running apps and XFinder itself are never removed.", S),
    "Chọn ứng dụng": ("Choose an app", S),
    " app trong Applications": (" apps in Applications", F),
    "Tìm theo tên hoặc bundle id": ("Search by name or bundle id", S),
    "Gỡ ": ("Uninstall ", F),
    "Bỏ chọn mục nào bạn muốn giữ lại.": ("Untick anything you want to keep.", S),
    "Không tìm thấy file nào app này để lại trong Thư viện.": ("Found nothing this app left in your Library.", S),
    "Đã vào Thùng rác": ("In the Trash", S),
    "macOS chặn": ("Blocked by macOS", S),
    "Đã không còn": ("Already gone", S),
    "Đúng bundle id": ("Exact bundle id", S),
    "Thành phần phụ của app (helper, extension)": ("Part of the app (helper, extension)", S),
    "Nhóm dữ liệu dùng chung của app": ("The app's shared data group", S),
    "Trùng tên app — chỉ là đoán": ("Same name as the app — only a guess", S),
    "Tác vụ chạy nền của app": ("The app's background task", S),
    "macOS bảo vệ — dùng Finder": ("protected by macOS — use Finder", S),
    "macOS có thể chặn": ("macOS may block it", S),
    "App đang chạy. Thoát app trước để nó không ghi tiếp vào những file sắp chuyển đi.":
        ("The app is running. Quit it first so it does not keep writing to the files about to be moved.", S),
    "Thoát app": ("Quit the app", S),
    "Đây là app của Apple — XFinder không gỡ app hệ thống.": ("This is an Apple app — XFinder does not remove system apps.", S),
    "App nằm trong thư mục hệ thống — XFinder không gỡ.": ("The app is in a system folder — XFinder does not remove it.", S),
    "Không thể tự gỡ XFinder từ chính nó — kéo XFinder vào Thùng rác trong Finder.":
        ("XFinder cannot remove itself — drag XFinder to the Trash in Finder.", S),
    "Không đọc được thông tin của app này.": ("Could not read this app's information.", S),
    " mục bị macOS chặn — dùng Hiện trong Finder.": (" items were blocked by macOS — use Show in Finder.", F),
    " mục không chuyển được.": (" items could not be moved.", F),
    # F3 — Thoát ứng dụng
    "Thoát ứng dụng": ("Quitting Apps", S),
    "Không thoát nhầm vì ⌘Q, và tự thoát một app khi bạn đã đóng hết cửa sổ của nó.":
        ("Never quit by a stray ⌘Q, and quit an app on its own once you have closed all its windows.", S),
    "Bật giữ ⌘Q": ("Turn on hold ⌘Q", S),
    "Một vòng tiến trình hiện khi bạn giữ; nhả sớm hoặc bấm Esc là huỷ.":
        ("A progress ring appears while you hold; letting go early or pressing Esc cancels.", S),
    "Thoát khi đóng cửa sổ cuối": ("Quit when the last window closes", S),
    "Đóng hết cửa sổ của một app trong danh sách thì app thoát, không nằm lại trên Dock.":
        ("Close every window of an app in the list and it quits instead of staying in the Dock.", S),
    "Thoát app khi đóng cửa sổ cuối": ("Quit an app when its last window closes", S),
    "Chỉ với những app bạn chọn dưới đây. App vẫn hỏi lưu tài liệu như khi bạn chọn Thoát.":
        ("Only for the apps you choose below. The app still asks to save documents, as when you choose Quit.", S),
    "Cần quyền Trợ năng để biết cửa sổ của app khác đã đóng.":
        ("Accessibility permission is needed to know when another app's window closed.", S),
    "Chưa chọn app nào — chưa có app nào tự thoát.": ("No apps chosen — no app quits on its own yet.", S),
    "Mọi cửa sổ đều tính, kể cả bảng phụ và hộp thoại; app đang ẩn vẫn còn cửa sổ nên không bị thoát. XFinder đợi 1 giây sau khi cửa sổ đóng rồi mới đếm lại, để ⌘W rồi ⌘N không làm app thoát giữa chừng. Finder không bao giờ bị thoát.":
        ("Every window counts, palettes and dialogs included; a hidden app still has its windows, so it does not quit. XFinder waits 1 second after a window closes before counting again, so ⌘W followed by ⌘N does not quit the app in between. Finder is never quit.", S),
    "Theo dõi cửa sổ app đã chọn": ("Watches the chosen apps' windows", S),
    "Chỉ với những app bạn chọn; Finder không bao giờ.": ("Only the apps you choose; never Finder.", S),
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
