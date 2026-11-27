# Tệp và thư mục trong Dynamic Island

Thêm điểm đến Tệp riêng, dùng trình duyệt tệp và workspace XFinder đang có. Hiện thư mục quen dùng, workspace đã lưu và nút mở trình duyệt. Khi chọn mục, đóng Island rồi mở đúng nơi trong XFinder. Tôn trọng thiết lập tính năng và khả năng truy cập của trình duyệt. Không quét toàn đĩa, không tự xin quyền khi mở trang. Giữ ID `files` hiện tại cho Khay, điểm đến mới dùng ID `fileBrowser`.

Worker sở hữu file mới NotchFileBrowserPage.swift, quy tắc thuần và test nếu cần. Trả các API tái sử dụng, luồng mở và bản dịch. Kiểm không có workspace, đường dẫn biến mất, mất quyền, tên dài và điểm vào khi trình duyệt tắt. Người tích hợp sở hữu catalog, project và L10n chung.
