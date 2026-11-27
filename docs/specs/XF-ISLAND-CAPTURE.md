# Chụp màn hình từ Dynamic Island

Hiện các chế độ đã hỗ trợ bởi CaptureController và CaptureMode. Tôn trọng trạng thái tắt và luồng xin quyền của engine. Gọi callback để Island ẩn trước khi bắt đầu chụp, tránh ghi hình chính bảng điều khiển. Nếu có lịch sử chụp, cho phép sao chép từ lịch sử hiện có. Dùng cùng cài đặt và dữ liệu với trang Capture.

Worker sở hữu file mới `XFinder/Views/NotchCapturePage.swift`, phần quy tắc thuần nếu cần và test tương ứng. Xuất danh sách chuỗi VI/EN và hợp đồng callback. Người tích hợp sở hữu router, catalog và vòng đời bảng Island. Kiểm quyền bị từ chối, tính năng tắt, lịch sử trống, click liên tiếp và thao tác chụp bị hủy.
