#!/usr/bin/env python3
"""Learn lessons: idempotent ADD-ONLY translations; refuses conflicting existing keys."""
from __future__ import annotations
import json, sys
from pathlib import Path

STORE = Path(__file__).resolve().parent.parent / "XFinder/Resources/L10n.strings.json"
S, F = "sentence", "fragment"
ENTRIES: dict[str, tuple[str, str]] = {'Học sử dụng': ('Learn', 'sentence'), 'Đi đến thư mục': ('Navigate folders', 'sentence'), 'Làm việc với tab': ('Work with tabs', 'sentence'), 'Đặt các thư mục cạnh nhau': ('Place folders side by side', 'sentence'), 'Sắp xếp bằng thông tin riêng': ('Organize with metadata', 'sentence'), 'Tách công việc bằng Space': ('Separate work with Spaces', 'sentence'), 'Xem trước và dùng Shelf': ('Preview and use Shelf', 'sentence'), 'Sáu bài hướng dẫn ngắn. Tự đánh dấu khi bạn đã thực hành; tiến độ được lưu trên máy này.': ('Six short lessons. Mark each one after practicing; progress stays on this Mac.', 'sentence'), 'Tiến độ học': ('Learning progress', 'sentence'), 'Đã thực hành': ('Practiced', 'sentence'), 'Chọn một thư mục ở thanh bên. Nhấp đúp thư mục để mở; dùng nút Quay lại và Tiến tới để đi qua lịch sử. Thanh đường dẫn ở đáy giúp quay về thư mục cha.': ('Choose a folder in the sidebar. Double-click folders to open them; use Back and Forward to navigate history. The path bar at the bottom lets you return to parent folders.', 'sentence'), 'Dùng nút cộng trên thanh tab để mở tab mới trong ngăn. Chọn tab để chuyển thư mục; nút đóng nằm trên tab đang chọn. Đóng tab Học sử dụng để trở lại công việc.': ('Use the plus button on the tab bar to open a tab in the pane. Select tabs to switch folders; the selected tab has a close button. Close the Learn tab to return to work.', 'sentence'), 'Dùng nút chia ngăn bên phải thanh tab để xem hai thư mục cùng lúc. Nhấp vào một ngăn để chọn ngăn nhận lệnh. Số ngăn có thể tạo phụ thuộc gói sử dụng.': ('Use the split buttons to the right of the tab bar to see two folders at once. Click a pane to direct commands to it. The number of panes you can create depends on your plan.', 'sentence'), 'Nhấp phải một mục để ghim trong thư mục, đặt biệt danh hoặc thêm thuộc tính. Với thư mục, bạn còn có thể đặt emoji. Biệt danh không đổi tên tệp trên đĩa.': ('Right-click an item to pin it in the folder, set a nickname, or add a property. Folders can also have an emoji. Nicknames do not rename files on disk.', 'sentence'), 'Mở menu Space ở đầu thanh bên để tạo hoặc chuyển Space. Mỗi Space giữ danh sách mục ưa thích riêng. Dùng các chấm ở đáy thanh bên để chuyển nhanh giữa các Space.': ('Open the Space menu at the top of the sidebar to create or switch Spaces. Each Space keeps its own favorites. Use the dots at the bottom of the sidebar to switch quickly.', 'sentence'), 'Chọn một tệp rồi nhấn ⇧⌘P để bật hoặc tắt ngăn xem trước. Dùng menu ngữ cảnh để thêm mục vào Shelf, nơi giữ các tệp bạn muốn dùng lại.': ('Select a file and press ⇧⌘P to toggle the preview pane. Use the context menu to add items to Shelf, which holds files you want to use again.', 'sentence')}

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
