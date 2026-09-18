import Foundation

/// Stable-key translation table — single source of truth for 100% EN/VI switching.
///
/// Key format: "domain.key" (e.g. "sidebar.dashboard", "system.cpu.placeholder").
/// Every key must have both .vietnamese and .english. A missing EN is a bug, not a fallback.
///
/// Migration: new code calls `L10n.t(key: "domain.key")`. Old code keeps calling
/// `L10n.t("chuỗi Việt")` — the legacy shim reverse-lookups the table before falling
/// back to `enDict`. No flag day; migrate one view per commit.
///
/// Lint: `grep -rn 'Text("' XFinder/Views | grep -v 'L10n.t' | grep -v '//'` must be empty.
enum L10nDB {

    /// Reverse map: VI literal → stable key. Built once from `table`.
    static let viToKey: [String: String] = {
        var m: [String: String] = [:]
        for (key, pair) in table {
            if let vi = pair[.vietnamese] { m[vi] = key }
        }
        return m
    }()

    static let table: [String: [AppLanguage: String]] = [
        // MARK: - Sidebar groups
        "group.chung":       [.vietnamese: "CHUNG",              .english: "GENERAL"],
        "group.cuaSo":       [.vietnamese: "CỬA SỔ",             .english: "WINDOWS"],
        "group.finder":      [.vietnamese: "FINDER & TÌM KIẾM",  .english: "FINDER & SEARCH"],
        "group.congCu":      [.vietnamese: "CÔNG CỤ",            .english: "TOOLS"],
        "group.ketNoi":      [.vietnamese: "KẾT NỐI",            .english: "CONNECTIONS"],
        "group.tienIch":     [.vietnamese: "TIỆN ÍCH",           .english: "UTILITIES"],

        // MARK: - Sidebar destinations
        "sidebar.dashboard":      [.vietnamese: "Tổng quan",          .english: "Overview"],
        "sidebar.quickControls":  [.vietnamese: "Điều khiển nhanh",   .english: "Quick Controls"],
        "sidebar.antiSleep":      [.vietnamese: "Chống ngủ",          .english: "Anti-sleep"],
        "sidebar.system":         [.vietnamese: "Hệ thống",           .english: "System"],
        "sidebar.network":        [.vietnamese: "Mạng",               .english: "Network"],
        "sidebar.storage":        [.vietnamese: "Ổ đĩa",              .english: "Storage"],
        "sidebar.pin":            [.vietnamese: "Pin",                .english: "Battery"],
        "sidebar.clipboard":      [.vietnamese: "Clipboard",          .english: "Clipboard"],
        "sidebar.notes":          [.vietnamese: "Ghi chú",            .english: "Notes"],
        "sidebar.windowPreview":  [.vietnamese: "Xem trước cửa sổ",   .english: "Window Preview"],
        "sidebar.snapZones":      [.vietnamese: "Vùng bắt dính",     .english: "Snap Zones"],
        "sidebar.menuIcons":      [.vietnamese: "Biểu tượng thanh menu", .english: "Menu Bar Icons"],
        "sidebar.finderKeyboard": [.vietnamese: "Bàn phím Finder",    .english: "Finder Keyboard"],
        "sidebar.finderActions":  [.vietnamese: "Thao tác Finder",    .english: "Finder Actions"],
        "sidebar.finderSearch":   [.vietnamese: "Tìm kiếm",           .english: "Search"],
        "sidebar.aiSearch":       [.vietnamese: "Tìm kiếm AI",        .english: "AI Search"],
        "sidebar.batchRename":    [.vietnamese: "Đổi tên hàng loạt",  .english: "Batch Rename"],
        "sidebar.actionHistory":  [.vietnamese: "Lịch sử thao tác",   .english: "Action History"],
        "sidebar.dropTray":       [.vietnamese: "Khay thả",           .english: "Drop Tray"],
        "sidebar.compress":       [.vietnamese: "Nén & Giải nén",     .english: "Compress & Extract"],
        "sidebar.pdfTools":       [.vietnamese: "Công cụ PDF",        .english: "PDF Tools"],
        "sidebar.folderLock":     [.vietnamese: "Khóa thư mục",       .english: "Folder Lock"],
        "sidebar.quickLookPage":  [.vietnamese: "Quick Look",         .english: "Quick Look"],
        "sidebar.mediaCompat":    [.vietnamese: "Tương thích media",  .english: "Media Compatibility"],
        "sidebar.finderUtils":    [.vietnamese: "Tiện ích Finder",    .english: "Finder Utilities"],
        "sidebar.sync":           [.vietnamese: "Đồng bộ",            .english: "Sync"],
        "sidebar.remoteConnect":  [.vietnamese: "Kết nối từ xa",      .english: "Remote Connect"],
        "sidebar.quickShare":     [.vietnamese: "Chia sẻ nhanh",      .english: "Quick Share"],
        "sidebar.settingsClipboard": [.vietnamese: "Cài đặt Clipboard", .english: "Clipboard Settings"],
        "sidebar.about":          [.vietnamese: "Giới thiệu",         .english: "About"],

        // MARK: - Tổng quan (dashboard)
        "dashboard.subtitle":        [.vietnamese: "Xem những gì đã sẵn sàng và hoàn tất thiết lập.", .english: "See what's ready and finish setup."],
        "dashboard.appLanguage":     [.vietnamese: "Ngôn ngữ ứng dụng", .english: "App language"],
        "dashboard.quickGrant":      [.vietnamese: "Cấp quyền nhanh", .english: "Quick permissions"],
        "dashboard.quickGrantHint":  [.vietnamese: "Nhắc Trợ năng + Ghi màn hình cùng lúc; mở Cài đặt nếu vẫn thiếu.", .english: "Prompt Accessibility + Screen Recording at once; open Settings if still missing."],
        "dashboard.grantAll":        [.vietnamese: "Cấp mọi quyền…", .english: "Grant all…"],
        "dashboard.launchAtLogin":   [.vietnamese: "Khởi động XFinder khi đăng nhập", .english: "Launch XFinder at login"],
        "dashboard.showDock":        [.vietnamese: "Hiện biểu tượng trong Dock", .english: "Show icon in Dock"],
        "dashboard.menuBarIcon":     [.vietnamese: "Biểu tượng thanh menu", .english: "Menu bar icon"],

        // MARK: - System / Network / Storage / Pin (placeholders for next batch)
        "system.title":              [.vietnamese: "Hệ thống", .english: "System"],
        "system.cpu":                [.vietnamese: "CPU", .english: "CPU"],
        "system.gpu":                [.vietnamese: "GPU", .english: "GPU"],
        "system.collecting":         [.vietnamese: "Đang thu thập…", .english: "Collecting…"],
        "system.unavailable":        [.vietnamese: "Không khả dụng", .english: "Not available"],
        "network.title":             [.vietnamese: "Mạng", .english: "Network"],
        "storage.title":             [.vietnamese: "Ổ đĩa", .english: "Storage"],
        "pin.title":                 [.vietnamese: "Pin", .english: "Battery"],
    ]
}
