import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    // CHUNG — built now, real data
    case dashboard
    case features
    case antiSleep
    case system
    case network
    case storage
    case pin
    case alerts
    /// P3 (2026-10-13): one page for every keyboard shortcut — owns the recorders (capture, ⌘K), lists the fixed ones.
    case shortcuts
    // NOTCH — P3 split of the old "Notch & Khay thả" page by what the user comes to do
    /// The notch itself: master switch, hover, shape, which pages it shows, accent.
    case notchInterface
    /// Now Playing at the notch (OneNotch's "Media").
    case media
    /// Claude Code sessions, the hook, the statusLine that feeds the AI usage tool.
    case aiAgents
    /// The Calendar notch page and meeting alerts.
    case calendar
    /// Short notices under the notch: power, network, Caps Lock, Bluetooth, alerts, volume.
    case liveActivities
    // Ghi chú (clipboard content lives in the ⌘⇧V shelf and the Notch — decision 2026-10-10; no page)
    case notes
    // CỬA SỔ — real except menuIcons (private API)
    case windowPreview
    case snapZones
    case mouseGestures
    case menuIcons
    // FINDER & TÌM KIẾM
    case finderKeyboard
    case finderActions
    case finderSearch
    case aiSearch
    // CÔNG CỤ
    case batchRename
    case junkCleanup
    case uninstaller
    case appQuit
    case actionHistory
    case dropTray
    case compress
    case pdfTools
    case folderLock
    case quickLookPage
    case mediaCompat
    case finderUtils
    // KẾT NỐI
    case sync
    case remoteConnect
    case quickShare
    case ports
    // CÔNG CỤ
    case voiceTyping
    /// E5 (2026-10-13): Smart Selection — a badge beside text selected in other apps (+ ⇧⌘G, moved from Voice).
    case smartSelect
    /// F4 (2026-10-13): Chụp & chú thích — capture shortcuts, a floating preview card and an annotate editor (OneNotch-like).
    case capture
    /// D3 (2026-10-12): the Clipboard LIBRARY — every row in SQLite, filter rail, inspector. Content
    /// returns to the sidebar by the owner's choice (wireframe B); the notch/shelf stay the quick surfaces.
    case clipboard
    // CÀI ĐẶT
    // `settingsGeneral` was removed: "Cài đặt chung" only held theme + Dock
    // icon, both of which already live on Tổng quan / Điều khiển nhanh. A
    // catch-all settings bucket duplicated pages that own their own settings.
    case settingsClipboard
    // Footer
    case about

    var id: String { rawValue }

    /// 2026-10-14 (owner: "gộp các mục liên quan đến xem hệ thống lại cho gọn gàng") — Hệ thống, Mạng, Ổ đĩa and Pin
    /// answer one question, "how is this Mac doing", so they are ONE sidebar row ("Theo dõi hệ thống", `.system`) with
    /// four tabs. The four cases stay: deep links (`xfinder://settings?page=network`), the flyout, What's New and
    /// `-startPage` keep working — `AppState.navigate` selects the row and opens the tab.
    static let monitorTabs: [SidebarDestination] = [.system, .network, .storage, .pin]
    /// The sidebar row a destination lives under (itself, except the three monitor tabs).
    var monitorRow: SidebarDestination { Self.monitorTabs.contains(self) ? .system : self }
    /// The tab's label inside "Theo dõi hệ thống".
    var tabTitleKey: String { self == .system ? "Hệ thống" : titleKey }
    /// Extra words the sidebar search matches for this row: the monitor row answers to its tabs' names too.
    var searchAlsoKeys: [String] { self == .system ? Self.monitorTabs.map(\.tabTitleKey) : [] }

    /// The Vietnamese literal — the L10n store key. Search matches it AND its English translation,
    /// so the box finds a page in either language whatever the UI language is.
    var titleKey: String {
        switch self {
        case .dashboard: return "Tổng quan"
        case .features: return "Tính năng & Quyền"
        case .antiSleep: return "Chống ngủ"
        case .system: return "Theo dõi hệ thống"
        case .network: return "Mạng"
        case .storage: return "Ổ đĩa"
        case .pin: return "Pin"
        case .alerts: return "Cảnh báo"
        case .notes: return "Ghi chú"
        case .windowPreview: return "Xem trước cửa sổ"
        case .mouseGestures: return "Chuột & cử chỉ"
        case .snapZones: return "Vùng bắt dính"
        case .menuIcons: return "Biểu tượng thanh menu"
        case .finderKeyboard: return "Bàn phím Finder"
        case .finderActions: return "Thao tác Finder"
        case .finderSearch: return "Tìm kiếm"
        case .aiSearch: return "Tìm kiếm AI"
        case .batchRename: return "Đổi tên hàng loạt"
        case .junkCleanup: return "Dọn rác thư mục"
        case .uninstaller: return "Gỡ ứng dụng"
        case .appQuit: return "Thoát ứng dụng"
        case .actionHistory: return "Lịch sử thao tác"
        case .dropTray: return "Khay thả"
        case .compress: return "Nén & Giải nén"
        case .pdfTools: return "Công cụ PDF"
        case .folderLock: return "Khóa thư mục"
        case .quickLookPage: return "Quick Look"
        case .mediaCompat: return "Tương thích media"
        case .finderUtils: return "Tiện ích Finder"
        case .sync: return "Đồng bộ"
        case .remoteConnect: return "Kết nối từ xa"
        case .quickShare: return "Chia sẻ nhanh"
        case .ports: return "Cổng đang mở"
        case .voiceTyping: return "Nhập bằng giọng nói"
        case .smartSelect: return "Chọn văn bản thông minh"
        case .capture: return "Chụp & chú thích"
        case .clipboard: return "Thư viện Clipboard"
        case .settingsClipboard: return "Cài đặt Clipboard"
        case .about: return "Giới thiệu"
        case .shortcuts: return "Phím tắt"
        case .notchInterface: return "Giao diện notch"
        case .media: return "Đang phát"
        case .aiAgents: return "Agent AI"
        case .calendar: return "Lịch & lời nhắc"
        case .liveActivities: return "Hoạt động trực tiếp"
        }
    }

    var titleVI: String { L10n.t(titleKey) }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .features: return "square.grid.2x2"
        case .antiSleep: return "moon.zzz.fill"
        case .system: return "cpu"
        case .network: return "network"
        case .storage: return "internaldrive.fill"
        case .pin: return "battery.100"
        case .alerts: return "bell.badge"
        case .notes: return "note.text"
        case .windowPreview: return "macwindow.badge.plus"
        case .mouseGestures: return "computermouse"
        case .snapZones: return "rectangle.split.3x1"
        case .menuIcons: return "menubar.rectangle"
        case .finderKeyboard: return "keyboard.fill"
        case .finderActions: return "contextualmenu.and.cursorarrow"
        case .finderSearch: return "magnifyingglass"
        // `sparkles.magnifyingglass` does NOT exist on this macOS — the row
        // rendered with no icon at all. Verified with NSImage(systemSymbolName:).
        case .aiSearch: return "wand.and.stars"
        case .batchRename: return "textformat.abc.dottedunderline"
        case .junkCleanup: return "bubbles.and.sparkles"
        case .uninstaller: return "xmark.bin"
        case .appQuit: return "power"
        case .actionHistory: return "clock.arrow.circlepath"
        case .dropTray: return "tray.and.arrow.down.fill"
        case .compress: return "archivebox.fill"
        case .pdfTools: return "doc.richtext.fill"
        case .folderLock: return "lock.fill"
        case .quickLookPage: return "eye.fill"
        case .mediaCompat: return "play.rectangle.fill"
        case .finderUtils: return "wrench.and.screwdriver.fill"
        case .sync: return "arrow.triangle.2.circlepath"
        case .remoteConnect: return "display.2"
        case .quickShare: return "square.and.arrow.up"
        case .ports: return "point.3.connected.trianglepath.dotted"
        case .voiceTyping: return "mic.fill"
        case .smartSelect: return "character.cursor.ibeam"   // was wand.and.stars — the same symbol as aiSearch
        case .capture: return "camera.viewfinder"
        case .clipboard: return "doc.on.clipboard"
        case .settingsClipboard: return "gearshape"
        case .about: return "info.circle"
        case .shortcuts: return "command"
        case .notchInterface: return "rectangle.topthird.inset.filled"
        case .media: return "music.note"
        case .aiAgents: return "sparkles"
        case .calendar: return "calendar"
        case .liveActivities: return "dot.radiowaves.left.and.right"
        }
    }

    /// P3: the coloured tile behind each sidebar icon (OneNotch's convention: one flat colour per page). A name, not a
    /// `Color`, so this file stays Foundation-only and the test package can check every page has one.
    var tile: SidebarTile {
        switch self {
        case .dashboard, .storage, .menuIcons, .finderKeyboard, .actionHistory, .folderLock, .finderUtils, .about: return .gray
        case .features, .snapZones: return .indigo
        case .shortcuts, .finderSearch, .quickShare, .quickLookPage: return .cyan
        case .antiSleep, .aiSearch, .smartSelect, .aiAgents: return .purple
        case .system, .notchInterface, .windowPreview, .finderActions, .remoteConnect: return .blue
        case .network, .settingsClipboard, .ports: return .teal
        case .pin, .junkCleanup, .clipboard: return .green
        case .alerts, .calendar, .appQuit, .pdfTools, .uninstaller: return .red
        case .dropTray, .sync: return .mint
        case .media, .voiceTyping, .mediaCompat: return .pink
        case .liveActivities, .batchRename, .notes: return .orange
        case .mouseGestures, .compress: return .brown
        case .capture: return .yellow
        }
    }

    var isComingSoon: Bool {
        switch self {
        // Every sidebar row is a real page now.
        default:
            return false
        }
    }

    static var groups: [(header: String, items: [SidebarDestination])] {
        [
            ("CHUNG", [.dashboard, .features, .shortcuts, .antiSleep, .system, .alerts]),
            // P3: everything the notch shows, by what the user comes to do — the old "Notch & Khay thả" page split six ways.
            ("NOTCH", [.notchInterface, .dropTray, .media, .aiAgents, .calendar, .liveActivities]),
            ("CỬA SỔ", [.windowPreview, .snapZones, .appQuit, .mouseGestures, .menuIcons]),
            ("FINDER & TÌM KIẾM", [.finderKeyboard, .finderActions, .finderSearch, .aiSearch,
                                   .batchRename, .junkCleanup, .actionHistory]),
            ("CÔNG CỤ", [.voiceTyping, .smartSelect, .capture, .clipboard, .settingsClipboard, .notes, .compress, .pdfTools, .folderLock]),
            ("KẾT NỐI", [.sync, .remoteConnect, .quickShare, .ports]),
            ("TIỆN ÍCH", [.finderUtils, .quickLookPage, .mediaCompat, .uninstaller]),
        ]
    }
}

/// P3: the sidebar tile colours. Mapped to `NSColor.system*` in the view, so they follow light/dark mode.
enum SidebarTile: String, CaseIterable {
    case gray, blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, cyan, brown
}
