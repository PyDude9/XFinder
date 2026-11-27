# Việc cần làm trong Dynamic Island

Danh sách cá nhân lưu cục bộ. Cho phép thêm, đánh dấu hoàn thành, bỏ đánh dấu và xóa mục đã chọn. Có bộ lọc Đang làm và Đã xong. Tái sử dụng kiểu dòng và điều khiển focus của XFinder. Công tắc tab chỉ ẩn giao diện. Dữ liệu tách khỏi Nhắc việc EventKit.

Worker sở hữu NotchTodoDomain.swift, NotchTodosPage.swift và test tương ứng. Dùng lưu nguyên tử, báo lỗi ghi, bảo toàn dữ liệu khi không đọc được. Kiểm tiêu đề rỗng và dài, khởi động lại, sửa khi đang lọc, xóa và hủy, lỗi đọc/ghi, mục cũ và điều hướng bàn phím. Trả bản dịch và hợp đồng focus. Coordinator sở hữu catalog, project và L10n chung.
