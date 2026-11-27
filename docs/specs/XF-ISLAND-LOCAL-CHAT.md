# Chat trên máy trong Dynamic Island

Thêm trang chat dùng FoundationModels trên thiết bị. Kiểm khả dụng khi mở hoặc thử lại, với lý do riêng cho hệ điều hành, thiết bị, Apple Intelligence tắt và mô hình chưa sẵn sàng. Dùng đường kiểm khả dụng của AppleOnDeviceRefiner làm tham chiếu. Khởi tạo phiên hội thoại riêng cho trang, chỉ gửi prompt khi người dùng yêu cầu. Không dùng mạng, công cụ gọi ngoài, Clipboard tự động hoặc thiết lập của Voice. Lịch sử ở bộ nhớ trong phiên chạy XFinder, giữ khi đổi tab. Nút cuộc trò chuyện mới xóa ngữ cảnh và nội dung.

Hiện lịch sử, ô nhập, gửi, dừng và cuộc trò chuyện mới. Tôn trọng bàn phím, dùng các thành phần XFinder. Giới hạn số ký tự và ngữ cảnh, hiện lý do khi không thể gửi. Xử lý gửi liên tiếp, đổi tab, tắt tab, reset khi đang trả lời, từ chối và cửa sổ ngữ cảnh đầy. Hủy hoặc bỏ qua phản hồi trễ sau khi thoát và reset. Giữ tương thích với deployment target đang có; dùng fake engine trong test.

Worker sở hữu NotchLocalChatDomain.swift, FoundationModelsChatAdapter.swift, NotchLocalChatPage.swift và test tương ứng. Trả bản dịch, API lifecycle và hướng dẫn kiểm weak linkage. Người tích hợp sở hữu catalog, project và L10n chung. Không gọi mô hình trên phiên desktop của người dùng.
