# Thời lượng dùng ứng dụng

Hiện tổng hôm nay, biểu đồ bảy ngày và thời lượng theo ứng dụng. Giải thích đây là thời gian ứng dụng ở trước khi XFinder chạy và người dùng không nhàn rỗi. Người dùng phải bật theo dõi rõ ràng, có nút tạm dừng và xóa lịch sử có xác nhận. Tắt theo dõi dừng thu thập ngay. Công tắc tab chỉ quản lý khả năng mở trang. Lưu riêng trên máy tối đa 30 ngày, gồm định danh ứng dụng, tên hiển thị tối thiểu và số giây theo ngày. Không lưu tiêu đề cửa sổ, phím gõ, URL hoặc nội dung.

Dùng sự kiện chuyển ứng dụng, phiên hoạt động và sleep/wake. Tính thời lượng theo timestamp và số giây idle phù hợp, không giữ timer hoặc observer thu thập khi theo dõi tắt. Không dùng lịch sử hệ thống hoặc xin Full Disk Access. Xử lý ngày đổi, giờ lùi, múi giờ, idle, khóa hoặc chuyển phiên, sleep, bundle ID thiếu, ghi lỗi và bật/tắt liên tiếp. Khi đọc lỗi, giữ file hiện có và hiện thử lại. Xóa lịch sử phải không cộng lại segment cũ.

Worker sở hữu LocalAppUsageRules.swift, LocalAppUsageTracker.swift, NotchAppUsagePage.swift và test tương ứng. Trả API start/stop, bản dịch, tham số idle, giới hạn lấy mẫu và chính sách retention. Coordinator sở hữu catalog, project, vòng đời app và L10n chung. Dùng dữ liệu giả trong test, không ghi theo dõi phiên của người dùng.
