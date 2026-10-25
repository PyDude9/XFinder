#!/usr/bin/env python3
"""XF-T30 W4 builder "w4s" — the Browser Settings window (General/Sidebar/Cloud/Advanced/Keyboard/Search/Privacy)
and the Welcome window (2026-10-25). ADD-ONLY: a key already present with another meaning is a CONFLICT. Contract
docs/specs/XF-T30-w4-contract.md."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES: dict[str, tuple[str, str]] = {
    # Settings window — tab titles
    "Chung": ("General", S),
    "Sidebar": ("Sidebar", S),
    "Đám mây": ("Cloud", S),
    "Nâng cao": ("Advanced", S),
    "Bàn phím": ("Keyboard", S),
    "Quyền riêng tư": ("Privacy", S),
    "Cài đặt trình duyệt": ("Browser Settings", S),

    # General tab
    "Cửa sổ mới hiện": ("New windows show", S),
    "Thư mục khác…": ("Other Folder…", S),
    "Chọn thư mục cửa sổ mới sẽ mở.": ("Choose the folder new windows will open to.", S),
    "Hiện trong cửa sổ": ("Show in window", S),
    "Mở lại cửa sổ…": ("Reopen windows…", S),
    "Cửa sổ, tab, ngăn và lịch sử Lùi/Tiến quay lại khi XFinder mở. Giữ Shift khi mở để bỏ qua lần đó.":
        ("Windows, tabs, panes and Back/Forward history come back when XFinder opens. Hold Shift while opening to skip it once.", S),
    "Thói quen Windows (tuỳ chọn)": ("Windows habits (optional)", S),
    "Return đổi tên / mở": ("Return renames / opens", S),
    "Bật: Return mở mục đã chọn, đổi tên chuyển sang F2 hoặc menu Sửa. Tắt: Return đổi tên như Finder.":
        ("On: Return opens the selection, renaming moves to F2 or the Edit menu. Off: Return renames, like Finder.", S),
    "⌘X để cắt": ("⌘X to Cut", S),
    "Kiểu Windows: ⌘X đánh dấu cắt, ⌘V nơi khác sẽ chuyển thay vì chép.":
        ("Windows style: ⌘X marks items as cut, ⌘V elsewhere moves them instead of copying.", S),
    "Cập nhật phần mềm": ("Software update", S),
    "Cập nhật phần mềm trong bản này theo XFinder": ("Software updates follow XFinder's own updates for this build.", S),

    # Sidebar tab
    "Hiện trong sidebar": ("Show in sidebar", S),
    "Ổ trong máy": ("Internal Disks", S),
    "Ổ ngoài": ("External Disks", S),
    "Máy chủ đã nối": ("Connected Servers", S),
    "Máy Bonjour": ("Bonjour Computers", S),
    "Thẻ gần đây": ("Recent Tags", S),
    "Tuỳ chọn": ("Options", S),
    "Nhóm Vị trí theo loại": ("Group Locations by kind", S),
    "Tách Vị trí thành Trong máy / Ngoài / Đám mây / Mạng.": ("Splits Locations into Internal / External / Cloud / Network.", S),
    "Tô sáng vị trí chứa thư mục hiện tại": ("Highlight the location holding the current folder", S),
    "Ổ bị ẩn khỏi mục Vị trí của sidebar — vẫn gắn vào máy bình thường.":
        ("A disk hidden from the sidebar's Locations group — still mounted normally.", S),

    # Cloud tab
    "Đám mây trong sidebar": ("Cloud in sidebar", S),
    "Hiện đám mây trong sidebar": ("Show cloud storage in sidebar", S),
    "Cùng công tắc với Sidebar ▸ Đám mây.": ("Same switch as Sidebar ▸ Cloud.", S),
    "Nhà cung cấp đã phát hiện": ("Providers detected", S),
    "Chưa phát hiện nhà cung cấp đám mây nào.": ("No cloud storage provider detected.", S),
    "Đọc từ ~/Library/CloudStorage — đăng nhập và đồng bộ qua ứng dụng riêng của mỗi hãng, XFinder không có OAuth riêng.":
        ("Read from ~/Library/CloudStorage — sign-in and sync happen in each provider's own app; XFinder has no OAuth of its own.", S),

    # Advanced tab
    "Hiển thị tệp": ("File display", S),
    "Hiện mọi đuôi tệp": ("Show all filename extensions", S),
    "Trừ tệp tự đặt cờ ẩn đuôi riêng (Lấy thông tin ▸ Tên & Đuôi).": ("Except a file with its own hide-extension flag (Get Info ▸ Name & Extension).", S),
    "Thư mục lên đầu khi sắp theo tên": ("Keep folders on top when sorted by name", S),
    "Khi tìm kiếm": ("When searching", S),
    "Phạm vi tìm mặc định": ("Default search scope", S),
    "Thư mục hiện tại": ("Current Folder", S),
    "Dùng phạm vi tìm trước": ("Use the previous search scope", S),

    # Keyboard tab
    "Hồ sơ phím tắt": ("Shortcut profile", S),
    "Finder": ("Finder", S),
    "Windows Explorer": ("Windows Explorer", S),
    "Total Commander": ("Total Commander", S),
    "Tuỳ chỉnh": ("Custom", S),
    "Bảng phím tắt": ("Shortcut table", S),
    "Nhấp một ô rồi gõ phím mới. Esc huỷ, Delete xoá. Control-click một hàng để khôi phục riêng hàng đó.":
        ("Click a box, then type the new key. Esc cancels, Delete clears. Control-click a row to restore just that row.", S),
    "Tìm theo tên hoặc phím": ("Search by name or key", S),
    "(Cài đặt hệ thống)": ("(System Settings)", S),
    "Nhấn phím…": ("Press a key…", S),
    "Chuột": ("Mouse", S),
    "Tab chuyển ngăn": ("Tab switches panes", S),
    "Như Total Commander: Tab chuyển ngăn đang chọn thay vì focus trong ngăn.":
        ("Like Total Commander: Tab switches the selected pane instead of moving focus within a pane.", S),
    "Nút chuột 4/5 (Lùi/Tiến)": ("Mouse buttons 4/5 (Back/Forward)", S),
    "Đảo": ("Swapped", S),
    "Xuất / nhập": ("Export / Import", S),
    "Không nhập được — mọi lỗi dưới đây cần sửa trước:": ("Could not import — every error below needs fixing first:", F),
    "Phím đang được dùng": ("Key already in use", S),
    "Vẫn dùng": ("Use Anyway", S),
    "Hủy": ("Cancel", S),
    "Phím này đang dùng cho ": ("This key is already used for ", F),
    "Chọn nơi lưu tệp phím tắt.": ("Choose where to save the shortcuts file.", S),
    "Chọn tệp phím tắt đã xuất.": ("Choose an exported shortcuts file.", S),
    "Tệp không đọc được.": ("The file could not be read.", S),
    "Lệnh lạ: ": ("Unknown command: ", F),
    "Phím dùng hai lần: ": ("Key used twice: ", F),
    "Phím dành riêng: ": ("Reserved key: ", F),

    # Search tab
    "Thư mục được đánh chỉ mục": ("Indexed folders", S),
    "Không tự quét toàn ổ đĩa — chỉ thư mục bạn thêm ở đây mới có chỉ mục tên/nội dung riêng; tìm theo Spotlight vẫn chạy ở mọi nơi khác.":
        ("Never scans the whole disk on its own — only a folder you add here gets its own name/content index; Spotlight search still works everywhere else.", S),
    "Chưa có thư mục nào được thêm.": ("No folder has been added yet.", S),
    "Chọn thư mục để đánh chỉ mục.": ("Choose a folder to index.", S),
    "Dựng lại": ("Rebuild", S),
    "Xoá chỉ mục…": ("Erase Index…", S),

    # Privacy tab
    "Quyền thư mục": ("Folder access", S),
    "Chưa kiểm tra": ("Not checked", S),
    "Chưa cho phép": ("Not allowed", S),
    "Truy cập toàn bộ ổ đĩa": ("Full Disk Access", S),
    "Full Disk Access": ("Full Disk Access", S),
    "Mở Cài đặt hệ thống…": ("Open System Settings…", S),
    "Kiểm lại": ("Check Again", S),
    "Vừa cấp quyền? Thoát và mở lại XFinder để chắc chắn quyền có hiệu lực.":
        ("Just granted access? Quit and reopen XFinder to make sure it takes effect.", S),
    "Khởi động": ("Startup", S),

    # Welcome window
    "Chào mừng đến với XFinder": ("Welcome to XFinder", S),
    # "Duyệt, gom và chép tệp..." already registered by add-xf-t30-w2w8-stub-l10n-entries.py (same key, same meaning).
    "Cho phép XFinder đọc các thư mục hay dùng. Mỗi nút gọi đúng hộp thoại hệ thống — không gì tự cấp quyền.":
        ("Let XFinder read the folders you use most. Each button triggers the real system dialog — nothing grants itself access.", S),
    "Cho phép tất cả": ("Allow All", S),
    "Đã cho phép": ("Allowed", S),
    "Full Disk Access (tuỳ chọn)": ("Full Disk Access (optional)", S),
    "Cho mọi thư mục trên máy, kể cả thư mục của ứng dụng khác. Có thể bỏ qua và bật sau trong Cài đặt trình duyệt ▸ Quyền riêng tư.":
        ("Access to every folder on the Mac, including other apps' own folders. You can skip this and turn it on later in Browser Settings ▸ Privacy.", S),
    "Trạng thái hiện tại": ("Current status", S),
    "Tiếp tục không cần Full Disk Access": ("Continue Without Full Disk Access", S),
    "Chọn bố cục": ("Choose a Layout", S),
    "Cửa sổ đầu tiên sẽ mở các thư mục bạn vừa cho phép.": ("The first window opens the folders you just allowed.", S),
    "Mở XFinder": ("Open XFinder", S),
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
