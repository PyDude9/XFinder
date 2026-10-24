#!/usr/bin/env python3
"""XF-T28 Trình duyệt tệp (2026-10-24). ADD-ONLY: a key already present with another meaning is a CONFLICT."""
from __future__ import annotations
import json, sys
from pathlib import Path
STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S = "sentence"
F = "fragment"
ENTRIES = {
    # Catalogue, sidebar, shortcut catalogue, menu bar
    "Trình duyệt tệp": ("File Browser", S),
    "Finder nhiều ngăn: chép giữa các ngăn, tìm bằng một câu thường, hàng đợi chép an toàn.":
        ("Finder with split panes: copy between panes, search in plain words, a safe copy queue.", S),
    "Chỉ chạy khi cửa sổ đang mở": ("Runs only while its window is open", S),
    "Mở trình duyệt tệp từ mọi app": ("Open the file browser from any app", S),
    # Settings page
    "Duyệt, gom và chép tệp giữa nhiều thư mục trong một cửa sổ — như Finder, chia được tới 16 ngăn.":
        ("Browse, collect and copy files across folders in one window — like Finder, split into up to 16 panes.", S),
    "Mở trình duyệt": ("Open the browser", S),
    "Mở cửa sổ mới": ("Open a new window", S),
    "Trình duyệt tệp đang tắt — bật ở công tắc bên dưới.": ("The file browser is off — turn it on with the switch below.", S),
    "Bật trình duyệt tệp": ("Turn on the file browser", S),
    "Không chạy gì khi chưa mở cửa sổ; đóng cửa sổ là hết theo dõi thư mục.":
        ("Nothing runs until a window is open; closing the window stops watching folders.", S),
    "Phím tắt toàn cục ⌃⌥⌘F": ("Global shortcut ⌃⌥⌘F", S),
    "Một ứng dụng khác đang giữ ⌃⌥⌘F — phím tắt chưa hoạt động.": ("Another app holds ⌃⌥⌘F — the shortcut is not working.", S),
    "Mở trình duyệt từ mọi ứng dụng. Tắt sẵn vì nó chiếm phím này của mọi ứng dụng khác.":
        ("Open the browser from any app. Off by default because it takes this key from every other app.", S),
    "Khi mở": ("When it opens", S),
    "Mở lại cửa sổ lần trước": ("Reopen last session's windows", S),
    "Cửa sổ, ngăn, thư mục và lịch sử quay lại trở về khi XFinder mở. Giữ Shift khi mở để bắt đầu với cửa sổ trống.":
        ("Windows, panes, folders and Back history come back when XFinder opens. Hold Shift at launch to start with an empty window.", S),
    "Kiểu xem của ngăn mới": ("View for new panes", S),
    "Hiện tệp ẩn": ("Show hidden files", S),
    "Áp dụng cho ngăn mới; ⇧⌘. bật/tắt cho từng ngăn.": ("Applies to new panes; ⇧⌘. toggles it per pane.", S),
    "Thư mục luôn ở trên": ("Keep folders on top", S),
    "Như tuỳ chọn “Giữ thư mục ở trên cùng” của Finder.": ("Like Finder's “Keep folders on top” option.", S),
    "Phím tắt trong cửa sổ": ("Shortcuts in the window", S),
    "Mọi lệnh cũng có trong bảng lệnh: ⌃⇧⌘P, hoặc gõ > trong ⌃⌘P.": ("Every command is also in the command palette: ⌃⇧⌘P, or type > in ⌃⌘P.", S),
    # BrowserCommands.titleKey (reach the screen through L10n.t(variable) — BrowserVocabularyL10nTests)
    "Cửa sổ mới": ("New Window", S),
    "Thư mục mới": ("New Folder", S),
    "Lên thư mục cha": ("Enclosing Folder", S),
    "Lùi lại": ("Back", S),
    "Tiến tới": ("Forward", S),
    "Đổi tên": ("Rename", S),
    "Nhân bản": ("Duplicate", S),
    "Xem nhanh": ("Quick Look", S),
    "Dán và di chuyển": ("Move Item Here", S),
    "Hiện hoặc ẩn tệp ẩn": ("Show or Hide Hidden Files", S),
    "Chọn tất cả": ("Select All", S),
    "Xem dạng biểu tượng": ("as Icons", S),
    "Xem dạng danh sách": ("as List", S),
    "Xem dạng cột": ("as Columns", S),
    "Xem dạng gallery": ("as Gallery", S),
    "Lọc thư mục hiện tại": ("Filter Current Folder", S),
    "Gõ đường dẫn": ("Edit Location", S),
    "Đến thư mục": ("Go to Folder", S),
    "Mở nhanh": ("Quick Open", S),
    "Chia ngăn sang phải": ("Split Right", S),
    "Chia ngăn sang trái": ("Split Left", S),
    "Chia ngăn xuống dưới": ("Split Down", S),
    "Chia ngăn lên trên": ("Split Up", S),
    "Đóng ngăn": ("Close Pane", S),
    "Chia đều các ngăn": ("Make Panes Equal Size", S),
    "Phóng to ngăn": ("Zoom Pane", S),
    "Ngăn kế tiếp": ("Next Pane", S),
    "Ngăn trước đó": ("Previous Pane", S),
    "Một ngăn": ("Single", S),
    "Cạnh nhau": ("Side by Side", S),
    "Chồng lên nhau": ("Stacked", S),
    "Lưới 2×2": ("2×2 Grid", S),
    "Sao chép sang ngăn kia": ("Copy to Other Pane", S),
    "Di chuyển sang ngăn kia": ("Move to Other Pane", S),
    "Thêm vào Shelf": ("Add to Shelf", S),
    "Hiện hoặc ẩn Shelf": ("Show or Hide Shelf", S),
    "Hàng đợi thao tác": ("Operations", S),
    "Lưu Workspace": ("Save Workspace", S),
    "Mở Workspace": ("Open Workspace", S),
    "Tải về ngay": ("Download Now", S),
    "Gỡ bản tải": ("Remove Download", S),
    "Đóng cửa sổ": ("Close Window", S),
    # FileOperationRules.recoveryReport messages
    "Có thể còn tệp chép dở ở đích": ("A partly copied file may be left at the destination", S),
    "Bản sao chưa được kiểm": ("The copy was not verified", S),
    "Bản gốc vẫn còn ở chỗ cũ": ("The original is still in its old place", S),
    "Bản gốc có thể đã vào Thùng rác — kiểm tra trước khi coi là mất":
        ("The original may already be in the Trash — check before treating it as lost", S),
    # SearchQuery warnings
    "Toán tử không rõ: giữ là chữ": ("Unknown operator: kept as text", S),
    # DirectoryReadError.messageKey
    "XFinder chưa được phép đọc thư mục này": ("XFinder isn't allowed to read this folder yet", S),
    "Thư mục không còn tồn tại": ("This folder no longer exists", S),
    "Đây không phải là thư mục": ("This isn't a folder", S),
    "Thư mục phản hồi quá chậm": ("This folder is responding too slowly", S),
    "Không đọc được thư mục này": ("Couldn't read this folder", S),
    # Wave 3 views and controller (2026-10-24)
    'Báo cáo khôi phục': ('Recovery report', S),
    'Bản trình chiếu': ('Presentations', S),
    'Bảng tính': ('Spreadsheets', S),
    'Bằng': ('Equal to', S),
    'Chép vào ngăn đang chọn': ('Copy to the active pane', S),
    'Chạy kế tiếp': ('Run next', S),
    'Chọn cách xử lý cho mục này.': ('Choose what to do with this item.', S),
    'Chờ xong rồi hãy thoát, hay dừng việc đang chạy và thoát ngay?': ('Wait until it finishes, or stop the running work and quit now?', S),
    'Các ngăn': ('Open panes', S),
    'Cỡ': ('Size', S),
    'Di chuyển vào ngăn đang chọn': ('Move to the active pane', S),
    'Dừng và thoát': ('Stop and quit', S),
    'Giá trị': ('Value', S),
    'Gõ đường dẫn…': ('Type a path…', S),
    'Gõ để tìm hoặc ">" để gõ lệnh': ('Type to search, or ">" for commands', S),
    'Không có thư mục': ('No folders', S),
    'Không có tuỳ chọn khác': ('No other options', S),
    'Không có việc nào': ('No operations', S),
    'Không xem được': ("Can't show folders", S),
    'Kéo tệp vào đây để thêm vào Shelf': ('Drag files here to add them to the Shelf', S),
    'Lọc trong thư mục này': ('Filter this folder', S),
    'Lớn hơn': ('Larger than', S),
    'Màn hình nền': ('Desktop', S),
    'Máy này': ('This Mac', S),
    'Mới hơn': ('Newer', S),
    'Mở ở ngăn kia': ('Open in Other Pane', S),
    'Mục đang chép': ('Item being copied', S),
    'Mục đã có': ('Existing item', S),
    'Mục ưa thích': ('Favorites', S),
    'Ngăn đang mở': ('Open pane', S),
    'Nhỏ hơn': ('Smaller than', S),
    'Năm nay': ('This year', S),
    'Năm ngoái': ('Last year', S),
    'So sánh': ('Compare', S),
    'Spotlight có thể chưa lập chỉ mục nội dung ở đây': ('Spotlight may not have indexed the contents here', S),
    'Thao tác sau đây có thể đã bị cắt ngang. Xem lại trước khi coi là xong.': ('These operations may have been interrupted. Review them before treating them as done.', S),
    'Tháng này': ('This month', S),
    'Tháng trước': ('Last month', S),
    'Thư mục này': ('This folder', S),
    'Thẻ': ('Tag', S),
    'Tiếp tục tất cả': ('Resume All', S),
    'Tuần này': ('This week', S),
    'Tuần trước': ('Last week', S),
    'Tên Workspace': ('Workspace name', S),
    'Tìm kiếm…': ('Search…', S),
    'Tạm dừng tất cả': ('Pause All', S),
    'Tạo lúc': ('Created', S),
    'Tệp nén': ('Archives', S),
    'Từ': ('From', S),
    'Vẫn còn thao tác tệp đang chạy': ('File operations are still running', S),
    'Vị trí': ('Locations', S),
    'XFinder đang thực hiện một thao tác tệp trên ổ đĩa này': ('XFinder is running a file operation on this disk', S),
    'Xoá hết': ('Clear', S),
    'Đang chờ': ('Waiting', S),
    'Đang hoàn tất': ('Finishing', S),
    'Đang kiểm': ('Verifying', S),
    'Đang tải…': ('Loading…', S),
    'Đuôi': ('Extension', S),
    'Đã có tệp trùng tên': ('An item with this name already exists', S),
    'Đã huỷ': ('Cancelled', S),
    'Đã tạm dừng': ('Paused', S),
    'Đã xem xong': ('Done reviewing', S),
    'Đợi': ('Wait', S),
    'Ảnh chụp màn hình': ('Screenshots', S),
    # Wave 4
    'Lấy thông tin': ('Get Info', S),
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
