# Âm nền trong Dynamic Island

Tạo âm white, pink và brown noise bằng AVAudioEngine, có thể bật nhiều âm, chỉnh âm lượng, dừng tất cả và hẹn giờ tắt dần. Âm nền tiếp tục khi thu gọn hoặc chuyển trang, nút dừng vẫn có trong trang Âm nền. Tắt tab thì dừng âm. Khi ngủ hoặc đổi đầu ra, giải phóng hoặc khôi phục trạng thái có chủ đích. Thiết kế theo XFinder, dùng âm tự tạo và không yêu cầu micro.

Worker sở hữu NotchSoundsRules.swift, NotchSoundsEngine.swift, NotchSoundsPage.swift và test tương ứng. Trả bản dịch, API dừng và kiểm tra vòng đời. Kiểm hết giờ khi thu gọn, thao tác nhanh trong lúc fade, lỗi engine, mất thiết bị, ngủ/thức, thoát app, tắt tab và giới hạn âm lượng khi trộn. Idle không giữ timer hoặc xử lý âm thanh. Người tích hợp sở hữu catalog, project và L10n chung.
