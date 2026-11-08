# XF-T39 — Workspace của trình duyệt theo FileOctopus 1.0.10 (2026-11-08)

**Câu việc:** "Người dùng lưu toàn bộ các cửa sổ trình duyệt đang làm thành một workspace có tên, mở lại sau mà không mất
cửa sổ đang mở, và biết mỗi workspace chứa gì."

Câu hỏi chủ dự án (2026-11-08): "Workspace của XFinder đã giống đặc tả Workspace FileOctopus chưa". Đặc tả = bản dán (§2.11:
Save / Open / Rename / Duplicate / Delete / Export, mở lại cửa sổ khi mở app, giữ Shift để bỏ qua) + chuỗi trong binary
FileOctopus 1.0.10 (sha `940882b4…`):

| FileOctopus 1.0.10 (chuỗi trong binary) | XFinder trước XF-T39 | Sau |
|:--|:--|:--|
| "Saves the open windows, their tabs and panes, folders and views." | chỉ lưu **cửa sổ hiện tại** | mọi cửa sổ trình duyệt (khung, nhóm tab gốc) |
| "Opening it later adds these windows; no files are changed." | **thay** bố cục cửa sổ hiện tại | thêm cửa sổ, không đóng/thay cửa sổ nào |
| "A workspace named “X” already exists. Choose a different name." / "Replace the workspace “X”? Its saved layout will be replaced by the open windows." | tự đổi thành "X 2" | hỏi Thay thế; thay giữ nguyên id |
| "A workspace needs a name." / "There are no browser windows to save." | tên rỗng ⇒ "Workspace" | báo tại chỗ trong hộp Lưu |
| "Inspect Saved Workspaces…" — "What each saved workspace holds. Inspecting or exporting doesn't open a workspace or change any file." | không có (chỉ "Quản lý Workspace") | Window ▸ Xem các workspace đã lưu…: mỗi workspace mấy cửa sổ, mấy tab, ngày lưu, các thư mục; đổi tên / nhân đôi / xoá / xuất |
| "Exports the names, layouts and folder paths… No file contents are included." (`FileOctopus.SavedWorkspaces.v1`) | xuất trọn dữ liệu lưu (cả lịch sử Lùi/Tiến, tên mục đang chọn) | `XFinder.SavedWorkspaces.v1`: tên, ngày, bố cục ngăn, thư mục + kiểu xem từng tab; đường dẫn không bị escape `\/` |
| "The saved workspaces file couldn't be read, so it isn't changed." / "The file couldn't be moved aside, so FileOctopus won't save workspaces over it." | lần lưu sau **bỏ mất** mục hỏng | tệp đọc không trọn được chuyển sang `workspaces-unreadable-<thời điểm>.json` trước khi ghi; không chuyển được ⇒ không ghi |
| "That workspace no longer exists." | im lặng | báo |
| Rename: "Only the saved layout is renamed; no files are changed." | trùng/rỗng ⇒ im lặng | báo lý do |

Giữ nguyên (đã giống): mở lại cửa sổ khi mở app + giữ Shift bỏ qua (`SessionRestore.shouldRestore`), Nhân bản, Xoá có
xác nhận, khôi phục tab/ngăn/thư mục/kiểu xem/lịch sử. Không làm: giới hạn số workspace của bản Free (Pro ngủ — Q-T30-8);
Mở nhanh liệt kê workspace (FileOctopus "Folders, tabs and workspaces") — Q-T39-1.

## Ca hỏng

| Ca | Phải |
|:--|:--|
| Lưu với tên trùng (khác hoa/thường) | hỏi Thay thế; Huỷ ⇒ không ghi gì |
| Mở workspace khi đang có 2 cửa sổ | 2 cửa sổ cũ còn nguyên, thêm các cửa sổ của workspace (nhóm tab giữ nguyên) |
| `workspaces.json` hỏng một mục | các mục đọc được vẫn hiện; lần ghi sau tệp cũ được chuyển sang bên, không mất |
| Thư mục trong workspace đã bị xoá | mở được, tab đó thành tab chết "Thử lại" + banner |

## Nghiệm thu

Test `BrowserWorkspaceTests` (lưu/thay/tên rỗng/không cửa sổ, đổi tên có lý do, xuất không có lịch sử, tóm tắt), harness
`T39-*`; build; gate. Chạy thật: sheet Lưu/Thay thế là sheet ⇒ Atlas không gõ vào được (đã đo ở 03C) — T-T39-1…3 test tay.

## Quyết định

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-T39-1 | Mở nhanh (⌘K) có liệt kê workspace như FileOctopus? | Chưa làm (đợt sau nếu anh muốn) |
