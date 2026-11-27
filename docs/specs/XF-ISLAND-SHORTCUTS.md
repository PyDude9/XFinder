# Phím tắt Apple trong Dynamic Island

Dùng công cụ shortcuts có sẵn của macOS để liệt kê phím tắt do người dùng sở hữu và chạy đúng mục họ chọn. Hiện trạng thái rỗng, đang tải, đang chạy và lỗi. Chạy process ngoài luồng UI với argument riêng, không qua shell. Tải danh sách khi mở hoặc làm mới. Tác vụ chỉ khởi chạy khi người dùng bấm. Không chạy shortcut thật trong kiểm thử, dùng runner giả.

Worker sở hữu AppleShortcutsDomain.swift, AppleShortcutsProcessRunner.swift, NotchShortcutsPage.swift và test tương ứng. Kiểm thiếu CLI, hung/timeout, output lớn, shortcut bị đổi tên, tên có khoảng trắng, dấu nháy hoặc ký tự shell, click liên tiếp, hủy, lỗi và stale reply sau đổi tab. Trả bản dịch, hợp đồng lifecycle và giới hạn cancel. Coordinator sở hữu catalog, project và L10n chung.
