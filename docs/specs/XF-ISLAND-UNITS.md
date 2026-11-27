# Dynamic Island đổi đơn vị

Thêm trang đổi đơn vị hoạt động offline. Dùng Foundation Measurement cho chiều dài, khối lượng và nhiệt độ. Người dùng chọn nhóm, nhập số theo locale, chọn hai đơn vị, hoán đổi và sao chép kết quả. Không quy đổi tiền tệ. Dùng bố cục và thành phần của XFinder.

Worker sở hữu file mới `XFinder/Core/Notch/NotchUnitRules.swift`, `XFinder/Views/NotchUnitsPage.swift` và test tương ứng. Người tích hợp sở hữu Xcode project, danh mục, router, công tắc Settings và file bản dịch chung. Trả danh sách chuỗi VI/EN và cách gắn trang.

Kiểm số âm và 0, dấu thập phân theo locale, chuỗi nhập dở, ký tự dư, số vượt giới hạn, đổi nhóm với đơn vị cũ, cùng đơn vị, tính nhiệt độ có độ lệch, làm tròn và thao tác sao chép. Hiện lỗi đúng chỗ, giữ nội dung khi thay đơn vị và vô hiệu hóa sao chép khi chưa có kết quả.
