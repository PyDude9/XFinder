# XF-T40 — Trình duyệt tệp: bốn lệnh tệp còn thiếu so với FileOctopus 1.0.10 (2026-11-09)

**Câu việc:** "Người dùng tạo tệp trống, mở gói ứng dụng như thư mục, và mở một thư mục sang ngăn mới / ngăn kia — từ
chuột phải, menu Tệp hay bảng lệnh, như FileOctopus."

Rà bản đặc tả anh gửi (§2.1 "Open in New Tab / New Pane / Other Pane / New Window; Show Package Contents", §2.2 "New File
(văn bản rỗng)") với `BrowserCommand`: XFinder có Mở trong tab mới / cửa sổ mới, chưa có **Tệp mới**, **Hiện nội dung gói**,
**Mở trong ngăn mới**, **Mở trong ngăn kia**; "Mở trong cửa sổ mới" có lệnh nhưng không có trong menu chuột phải.

## Làm

| Lệnh | Ở đâu | Luật |
|:--|:--|:--|
| Tệp mới | menu Tệp (sau "Thư mục mới chứa mục chọn"), chuột phải nền, bảng lệnh | tạo `untitled.txt` rỗng (đánh số như Giữ cả hai khi trùng), chọn và vào chế độ đổi tên — y như Thư mục mới; không ở vị trí ảo/kết quả tìm |
| Hiện nội dung gói | chuột phải (chỉ hiện khi chọn đúng một gói), bảng lệnh | mở gói như thư mục (`isPackage`) |
| Mở trong ngăn mới | chuột phải, bảng lệnh | chia ngăn sang phải rồi mở thư mục đầu tiên đã chọn ở ngăn mới; các thư mục còn lại thành tab của ngăn đó; xám khi không có thư mục nào được chọn hoặc không chia thêm được |
| Mở trong ngăn kia | chuột phải, bảng lệnh | ngăn kia mở thư mục đầu tiên đã chọn (còn lại thành tab); giữ focus ở ngăn hiện tại; xám khi chỉ có một ngăn hoặc ngăn kia đang tìm / ở vị trí ảo |
| Mở trong cửa sổ mới | thêm vào chuột phải | như cũ |

Không có phím tắt (FileOctopus cũng không). Không làm: **Xoá ngay ⌥⌘⌫** (Q-T40-1, luật 9 "không bao giờ rm dữ liệu người
dùng — Thùng rác"), **Đặt lại (Put Back)** của Thùng rác (cần thông tin của Finder về vị trí cũ — Q-T40-2).

## Ca hỏng

| Ca | Phải |
|:--|:--|
| Tệp mới khi đã có `untitled.txt` | `untitled 2.txt` |
| Tệp mới trong kết quả tìm / Gần đây / thẻ | lệnh xám |
| Hiện nội dung gói khi chọn 2 mục hoặc một tệp thường | không hiện trong chuột phải, xám trong bảng lệnh |
| Mở trong ngăn kia với 1 ngăn | xám |
| Mở trong ngăn mới khi bố cục đã 16 ngăn | xám |

## Nghiệm thu

Build; test (`BrowserCommandsTests` phân loại lệnh có/không phím, `BrowserMenuLayoutTests` thứ tự menu Tệp, từ vựng L10n);
harness `T40-01`; chạy thật trong Atlas: bảng lệnh ">" ▸ Tệp mới ⇒ `untitled.txt` xuất hiện; chọn `Demo.app` ▸ Hiện nội dung
gói ⇒ vào trong gói; chọn thư mục ▸ Mở trong ngăn mới ⇒ 2 ngăn. Test tay T-T40-1.

| Mã | Câu hỏi | Mặc định |
|:--|:--|:--|
| Q-T40-1 | Xoá ngay (⌥⌘⌫, có hỏi) như FileOctopus/Finder | **Không làm** — luật 9; nếu anh muốn, sẽ làm với hộp xác nhận liệt kê tên, Huỷ là mặc định |
| Q-T40-2 | Đặt lại (Put Back) cho mục trong Thùng rác | Không làm (Finder giữ vị trí cũ riêng, app ngoài không đọc được tin cậy) |
