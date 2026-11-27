# Phản hồi trong Dynamic Island

Nối trang Phản hồi với luồng hỗ trợ hiện có của XFinder. Cho viết ý kiến, chọn Báo lỗi, Đề xuất hoặc Khác, xem trước nội dung rồi sao chép. Cho mở trang tạo issue của XFinder bằng thao tác rõ ràng. Mở trang issue không tự đăng hay gửi nội dung, và URL chỉ mang đích đến. Báo lỗi mở trình duyệt và giữ nội dung để sao chép. Có đường mở phần chẩn đoán hiện có để người dùng tự xem báo cáo. Không tự đọc hoặc ghép nhật ký và thông tin máy. Nội dung nháp ở bộ nhớ.

Worker sở hữu NotchFeedbackRules.swift, NotchFeedbackPage.swift và test tương ứng. Dùng callback cho trang GitHub và chẩn đoán để người tích hợp nối đúng luồng XFinder. Trả bản dịch và hợp đồng focus. Kiểm rỗng, giới hạn độ dài, chuyển loại, lỗi sao chép hoặc mở, đổi tab và tắt khi đang viết. Không mở GitHub, gửi issue hay sao chép dữ liệu của người dùng khi kiểm thử. Người tích hợp sở hữu catalog, router, project và L10n chung.
