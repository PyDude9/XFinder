# Tin nhắn cục bộ trong Dynamic Island

Cho nhập một đoạn ngắn và chọn thời gian hiện. Có xem trước trong trang, nút hiển thị trong Island và nút dừng. Luồng dùng slot thông báo cục bộ thông qua callback do coordinator nối vào LiveActivity. Tin không tồn tại khi thoát app. Giảm chuyển động dùng hiển thị tĩnh. Không đọc Clipboard hoặc gửi dữ liệu. Hủy thông báo chờ hoặc đang hiện theo ID của tin khi tắt tab hoặc bấm dừng.

Worker sở hữu NotchMessageRules.swift, NotchMessagePage.swift và test tương ứng. Trả bản dịch, hợp đồng callback hiển thị/dừng và focus. Kiểm văn bản rỗng, nhiều dòng, Unicode, giới hạn độ dài, thời hạn không hợp lệ, gửi liên tiếp, tắt tab, đóng app và Reduce Motion. Người tích hợp sở hữu LiveActivity, catalog, router, project và L10n.
