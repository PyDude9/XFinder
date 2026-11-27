import Foundation

/// Deep settings search index: maps each `SidebarDestination` to individual setting keywords
/// (Vietnamese and English) so the sidebar search box finds specific toggles and tools inside
/// a page, not only the page's title. Pure Foundation so `Tests/XFinderLogicTests` can verify
/// coverage and matching without AppKit.
enum SettingsSearchIndex {
    /// Extra search terms for a destination (both Vietnamese and English).
    static func keywords(for destination: SidebarDestination) -> [String] {
        switch destination {
        case .dashboard:
            return ["tổng quan", "overview", "thanh menu", "menu bar", "số liệu", "readouts", "dock icon", "biểu tượng dock"]
        case .features:
            return ["tính năng", "quyền", "permissions", "trợ năng", "accessibility", "ghi màn hình", "screen recording", "sao lưu", "backup", "export", "import", "json", "dotfiles", "preset", "gói", "chống ngủ", "anti-sleep", "keep awake", "caffeine", "cleaning mode", "lau bàn phím", "khóa bàn phím"]
        case .system:
            return ["cpu", "gpu", "ram", "bộ nhớ", "memory", "nhiệt độ", "temperature", "hiệu năng", "performance", "tiến trình", "process"]
        case .network:
            return ["mạng", "network", "wifi", "wi-fi", "ip", "tốc độ", "speed", "băng thông", "bandwidth", "traffic"]
        case .storage:
            return ["ổ đĩa", "storage", "disk", "dung lượng", "capacity", "ssd", "phân vùng", "volume"]
        case .pin:
            return ["pin", "battery", "sạc", "charging", "chu kỳ", "cycle", "nhiệt độ pin", "watt", "nguồn", "power"]
        case .alerts:
            return ["cảnh báo", "alerts", "thông báo", "notification", "ngưỡng", "threshold", "quá nhiệt", "low battery"]
        case .shortcuts:
            return ["phím tắt", "shortcuts", "hotkey", "keybinding", "⌘k", "⌘⇧v", "command bar", "ghi phím"]
        case .notchInterface:
            return ["notch", "dynamic island", "tai thỏ", "hover", "rê chuột", "kích thước", "accent", "màu nhấn", "fullscreen", "toàn màn hình"]
        case .media:
            return ["đang phát", "now playing", "nhạc", "music", "spotify", "apple music", "ảnh bìa", "artwork", "phát nhạc"]
        case .aiAgents:
            return ["ai", "agent", "claude", "claude code", "codex", "opencode", "gemini", "antigravity", "hook", "terminal", "token", "usage", "quota", "chi phí"]
        case .stocks:
            return ["stocks", "watchlist", "cổ phiếu", "bitcoin", "twelve data", "khóa api", "quote source"]
        case .websiteAnalytics:
            return ["website analytics", "datafast", "google analytics", "ga4", "lượt truy cập"]
        case .revenue:
            return ["revenue", "stripe", "shopify", "doanh số", "thanh toán"]
        case .calendar:
            return ["lịch", "calendar", "lời nhắc", "reminders", "họp", "meeting", "zoom", "google meet", "sự kiện", "event"]
        case .liveActivities:
            return ["hoạt động trực tiếp", "live activities", "âm lượng", "volume", "độ sáng", "brightness", "hud", "caps lock", "bluetooth", "sạc pin"]
        case .notes:
            return ["ghi chú", "notes", "scratchpad", "mép màn hình", "edge notes", "markdown"]
        case .windowPreview:
            return ["xem trước cửa sổ", "window preview", "dock preview", "cmd-tab", "⌘-tab", "app switcher", "chuyển ứng dụng", "thumbnail", "thu nhỏ"]
        case .snapZones:
            return ["vùng bắt dính", "snap zones", "chia cửa sổ", "window layout", "tiling", "hyprmac", "bsp", "dwindle", "xếp lát", "focus border", "gap", "bố cục", "remember layout", "spaces", "mru", "thứ tự spaces", "fixed space order"]
        case .mouseGestures:
            return ["chuột", "mouse", "cử chỉ", "gestures", "cuộn mượt", "smooth scroll", "trackpad", "bánh xe", "wheel", "linear scrolling", "cuộn tuyến tính", "pointer acceleration", "tăng tốc con trỏ"]
        case .menuIcons:
            return ["ẩn biểu tượng", "menu bar icons", "thanh menu", "bartender", "ice"]
        case .fileBrowser:
            return ["trình duyệt tệp", "file browser", "nhiều ngăn", "dual pane", "split pane", "tab", "hàng đợi chép", "copy queue"]
        case .finderKeyboard:
            return ["bàn phím finder", "finder keyboard", "⌘x", "cắt dán", "cut paste", "enter rename", "đổi tên", "f2"]
        case .finderActions:
            return ["thao tác finder", "finder actions", "menu chuột phải", "context menu", "tệp mới", "new file", "mở terminal"]
        case .finderSearch:
            return ["tìm kiếm", "search", "spotlight", "command bar", "⌘k", "tính toán", "calculator"]
        case .aiSearch:
            return ["tìm kiếm ai", "ai search", "ngôn ngữ tự nhiên", "natural language", "semantic"]
        case .batchRename:
            return ["đổi tên hàng loạt", "batch rename", "regex", "tiền tố", "hậu tố", "prefix", "suffix", "đánh số"]
        case .junkCleanup:
            return ["dọn rác", "junk cleanup", "cleaner", "cache", "ds_store", "node_modules", "deriveddata", "thư mục rác"]
        case .uninstaller:
            return ["gỡ ứng dụng", "uninstaller", "xóa app", "leftovers", "tệp thừa", "preferences", "caches"]
        case .appQuit:
            return ["thoát ứng dụng", "quit apps", "giữ ⌘q", "hold ⌘q", "quit protection", "quit on close", "đóng cửa sổ cuối"]
        case .actionHistory:
            return ["lịch sử thao tác", "action history", "undo", "hoàn tác", "nhật ký"]
        case .dropTray:
            return ["khay thả", "drop tray", "shelf", "kéo thả", "drag drop", "tạm giữ tệp"]
        case .compress:
            return ["nén", "giải nén", "compress", "extract", "zip", "tar", "7z", "rar", "archive"]
        case .pdfTools:
            return ["pdf", "gộp pdf", "merge", "tách pdf", "split", "nén pdf", "xoay trang", "watermark"]
        case .folderLock:
            return ["khóa thư mục", "folder lock", "mật khẩu", "password", "bảo vệ", "ẩn thư mục"]
        case .duplicateFinder:
            return ["tệp trùng", "duplicate finder", "trùng lặp", "hash", "sha256", "dọn trùng"]
        case .quickLookPage:
            return ["quick look", "xem trước", "preview", "markdown", "json", "code", "archive"]
        case .mediaCompat:
            return ["tương thích media", "media compatibility", "codec", "mkv", "hevc", "av1", "ffmpeg", "video", "audio"]
        case .finderUtils:
            return ["tiện ích finder", "finder utilities", "tệp ẩn", "hidden files", "đường dẫn", "copy path", "eject"]
        case .sync:
            return ["đồng bộ", "sync", "folder sync", "mirror", "sao lưu thư mục", "rsync"]
        case .remoteConnect:
            return ["kết nối từ xa", "remote connect", "ssh", "scp", "sftp", "server", "máy chủ"]
        case .quickShare:
            return ["chia sẻ nhanh", "quick share", "wi-fi", "qr code", "lan", "http server", "gửi tệp"]
        case .ports:
            return ["cổng đang mở", "open ports", "port manager", "tcp", "udp", "lsof", "kill process", "localhost"]
        case .voiceTyping:
            return ["giọng nói", "voice typing", "dictation", "micro", "microphone", "whisper", "speech to text"]
        case .smartSelect:
            return ["chọn văn bản thông minh", "smart selection", "đổi đơn vị", "unit convert", "múi giờ", "timezone", "dịch", "translate", "⇧⌘g"]
        case .capture:
            return ["chụp màn hình", "capture", "screenshot", "chú thích", "annotate", "ghim ảnh", "pin image", "ocr"]
        case .clipboard:
            return ["thư viện clipboard", "clipboard library", "lịch sử clipboard", "pinboard", "bảng ghim", "dán", "paste"]
        case .settingsClipboard:
            return ["cài đặt clipboard", "clipboard settings", "tự xóa", "auto clear", "clean url", "làm sạch liên kết", "link preview", "touch id", "mật khẩu", "password manager", "credit card", "thẻ tín dụng", "mcp", "xfinderclip", "icloud", "ocr", "âm thanh", "haptic", "gợi ý", "suggestions", "plain text", "snippet", "snippets", "gõ tắt", "đoạn văn bản nhanh", "tự mở rộng", "auto expand"]
        case .pro:
            return ["pro", "license", "bản quyền", "nâng cấp", "upgrade", "trial", "dùng thử"]
        case .about:
            return ["giới thiệu", "about", "phiên bản", "version", "cập nhật", "update", "chẩn đoán", "diagnostics", "log"]
        }
    }

    /// Returns the first setting keyword that matches `query` (case/diacritic insensitive)
    /// when `query` is non-empty, so the sidebar can show a subtle hint under the matched page.
    static func firstMatchedKeyword(for destination: SidebarDestination, query: String) -> String? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        return keywords(for: destination).first {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
