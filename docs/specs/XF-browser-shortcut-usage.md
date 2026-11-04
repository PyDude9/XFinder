# Bộ phím Browser và Snap Zones

Rà soát 2026-10-28 trên cấu hình đang lưu: Browser dùng mặc định Finder; chưa có bộ phím tùy chỉnh, Return mở, cắt bằng ⌘X hay Tab chuyển ngăn. Giữ các giá trị này để tránh đổi thói quen ngoài ý muốn. Chủ máy đã yêu cầu bật phím mở Browser; khóa hiện có `fileBrowser.globalHotkey` được giữ mặc định OFF cho người dùng khác.

## Phân biệt ba tầng

| Phạm vi | Phím | Công việc |
| --- | --- | --- |
| Toàn máy, khi bật | ⌃⌥⌘F hoặc ⌃⇧⌘F (chọn trong Settings) | Mở/đưa File Browser hiện có lên trước; không nhân thêm cửa sổ |
| Toàn máy, khi bật | ⌃⌥⌘D | Khay Tải về |
| Toàn máy, khi Snap bật | ⌃⌥← / → / ↑ / ↓ | Nửa trái / nửa phải / phóng lớn / nửa dưới cửa sổ |
| Toàn máy, khi Snap bật | ⌃⌥Return | Căn giữa cửa sổ |
| Toàn máy, khi Snap bật | ⌃⌥D / F / G | Một phần ba trái / giữa / phải |
| Trong Browser | ⌃⌥⌘← / → / ↑ / ↓ | Chia ngăn trái / phải / trên / dưới |
| Trong Browser | ⌃⇧⌘ + mũi tên | Chuyển tiêu điểm tới ngăn theo hướng |
| Trong Browser | ⇧⌘Return | Phóng/thu ngăn đang dùng |
| Trong Browser | ⌘K, hoặc ⌃⌘P | Quick Open |
| Trong Browser | ⌃⇧⌘P | Bảng lệnh; có thể gõ > trong Quick Open |
| Trong Browser | ⌘, | XFinder Settings → Trình duyệt tệp |

Đo live: ⌃⌥⌘F bị từ chối đăng ký trên máy này. Vì vậy có thêm lựa chọn ⌃⇧⌘F; Settings hiển thị lỗi nếu tổ hợp đang chọn cũng bị ứng dụng khác giữ. Trang Phím tắt theo đúng lựa chọn thực tế. Không tự đổi mặc định của người dùng khác.

Snap chỉ nhận đúng ⌃⌥, không nhận các tổ hợp thêm ⌘ hoặc ⇧. Vì thế các phím chia ngăn và hai launcher không bị Snap nuốt. ⌘K toàn máy vẫn là bảng tìm chung khi không ở Browser; trong Browser nó ưu tiên Quick Open theo bộ phím đang chọn.

## Giữ thói quen Finder

⌘O hoặc ⌘↓ mở; Return đổi tên; ⌘⌫ bỏ vào Thùng rác; ⌘C rồi ⌘V chép; ⌘C rồi ⌥⌘V chuyển. ⌘N tạo cửa sổ mới, ⌘T tạo tab cửa sổ, ⌘W đóng theo lệnh Browser hiện tại. ⌘1–4 đổi kiểu xem; ⇧⌘P bật/tắt Preview.

Nếu thích Windows, vào XFinder → Trình duyệt tệp → Nhóm cài đặt → Chung bật Return mở và ⌘X để cắt. Không đổi sang cấu hình Windows khi chưa xác nhận sở thích. Có thể sửa từng phím trong nhóm Bàn phím; tránh gán lại nhóm ⌃⌥ của Snap. Trang Phím tắt chung hiển thị launcher, trạng thái và xung đột với các phím toàn máy mà XFinder biết; không cam kết phát hiện mọi tổ hợp do ứng dụng khác đăng ký.

## Giới hạn hình học

Browser giữ kích thước nội dung tối thiểu 720×460 điểm. Khi vùng chia nhỏ hơn giới hạn này, cửa sổ giữ kích thước tối thiểu nên các cửa sổ có thể chồng nhau. Không phải mọi màn hình đều đủ chỗ cho bốn Browser không chồng lấn. Cửa sổ toàn màn hình và panel nổi không được nhắm tới như Browser thường.

Bản cài của chủ máy sau kiểm tra: launcher bật, chọn ⌃⇧⌘F, UI không báo lỗi đăng ký; lựa chọn này tồn tại sau cài lại/relaunch. Kiểm tra thực tế việc nhấn phím vật lý và kéo cạnh vẫn còn cần nghiệm thu; công cụ phím tổng hợp không chứng minh đường Carbon/CGEvent tap. Các phép kiểm thử pure và mutation chỉ xác nhận logic, không thay thế nghiệm thu này.
