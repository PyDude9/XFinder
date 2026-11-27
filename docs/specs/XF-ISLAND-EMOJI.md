# Emoji trong Dynamic Island

Cho phép duyệt một bộ emoji cục bộ theo nhóm, tìm bằng từ khóa VI/EN và sao chép emoji được chọn. Hiện mục đã dùng gần đây với giới hạn 24 mục và bỏ trùng. Dùng glyph hệ thống và dữ liệu từ khóa tự viết hoặc có nguồn rõ. Nhãn tìm kiếm, nút và trạng thái trống có bản dịch và nhãn trợ năng. Giữ focus khi nhập.

Worker sở hữu file mới NotchEmojiCatalog.swift, NotchEmojiPage.swift và test tương ứng. Trả cách nối focus và bản dịch VI/EN. Người tích hợp sở hữu catalog, project, router và L10n. Kiểm từ có dấu, tìm không khớp, grapheme nhiều ký tự Unicode, mục gần đây sau mở lại và sao chép.
