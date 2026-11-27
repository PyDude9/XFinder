# Chuyển ảnh trong Dynamic Island

Chọn hoặc thả tối đa 50 ảnh. Chỉ hiện định dạng mà ImageEngine xác nhận trình mã hóa hỗ trợ. Cho chỉnh chất lượng khi phù hợp và tùy chọn cạnh dài tối đa. Tái sử dụng ImageRunner và ImageTransformRules. Chạy tuần tự ngoài MainActor, hiện kết quả từng tệp và mở ảnh đầu ra trong Finder. Hủy ngăn việc bắt đầu tệp tiếp theo. Giữ tệp nguồn và các bản kết quả đã ghi.

Worker sở hữu NotchImageConvertRules.swift, NotchImageConvertPage.swift và test tương ứng. Trả cách nối lifecycle và bản dịch. Kiểm tệp trùng, định dạng không hỗ trợ, ảnh lỗi hoặc quá lớn, hết chỗ, không có quyền, xung đột tên, hủy và đóng giữa batch. Người tích hợp sở hữu catalog, project và L10n chung.
