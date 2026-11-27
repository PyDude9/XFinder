import Foundation

/// Pure navigation model for the Dynamic Island Section Gallery and extra inline modules
/// (System Telemetry & Audio/Display deck). Kept pure Foundation so `Tests/XFinderLogicTests`
/// verifies item uniqueness, shortcut key lookup, and L10n coverage without AppKit.
enum NotchExtraModule: String, Equatable, CaseIterable, Sendable {
    case sections
    case settings
    case home
    case system
    case audio
    case reminders
    case weather
    case stocks
    case revenue
    case websiteAnalytics
    case mirror
    case teleprompter
    case notes
    case capture
    case units
    case scratchpad
    case emoji
    case fileBrowser
    case links
    case imageConvert
    case sounds
    case todos
    case shortcuts
    case appUsage
    case localChat
    case message
    case feedback
}

enum NotchGalleryDestination: Equatable, Hashable, Sendable {
    case page(NotchSurfaceMachine.Page)
    case extra(NotchExtraModule)
}

struct NotchGalleryItem: Equatable, Identifiable, Sendable {
    let id: String
    let destination: NotchGalleryDestination
    let titleKey: String
    let symbol: String
    let shortcutKey: String
    let digitKey: String
}

enum NotchGalleryRules {
    /// Fixed 3×3 order shown in the Section Gallery grid inside the wide Dynamic Island body.
    static let items: [NotchGalleryItem] = [
        NotchGalleryItem(
            id: "files",
            destination: .page(.files),
            titleKey: "Khay",
            symbol: "tray.fill",
            shortcutKey: "F",
            digitKey: "1"
        ),
        NotchGalleryItem(
            id: "clipboard",
            destination: .page(.clipboard),
            titleKey: "Clipboard",
            symbol: "doc.on.clipboard.fill",
            shortcutKey: "B",
            digitKey: "2"
        ),
        NotchGalleryItem(
            id: "nowPlaying",
            destination: .page(.nowPlaying),
            titleKey: "Đang phát",
            symbol: "music.note",
            shortcutKey: "M",
            digitKey: "3"
        ),
        NotchGalleryItem(
            id: "agents",
            destination: .page(.agents),
            titleKey: "Agent AI",
            symbol: "terminal.fill",
            shortcutKey: "A",
            digitKey: "4"
        ),
        NotchGalleryItem(
            id: "calendar",
            destination: .page(.calendar),
            titleKey: "Lịch",
            symbol: "calendar",
            shortcutKey: "C",
            digitKey: "5"
        ),
        NotchGalleryItem(
            id: "timer",
            destination: .page(.timer),
            titleKey: "Hẹn giờ",
            symbol: "timer",
            shortcutKey: "T",
            digitKey: "6"
        ),
        NotchGalleryItem(
            id: "aiUsage",
            destination: .page(.aiUsage),
            titleKey: "Hạn mức AI",
            symbol: "gauge.with.dots.needle.50percent",
            shortcutKey: "U",
            digitKey: "7"
        ),
        NotchGalleryItem(
            id: "system",
            destination: .extra(.system),
            titleKey: "Hệ thống",
            symbol: "cpu",
            shortcutKey: "S",
            digitKey: "8"
        ),
        NotchGalleryItem(
            id: "audio",
            destination: .extra(.audio),
            titleKey: "Âm thanh",
            symbol: "speaker.wave.2.fill",
            shortcutKey: "V",
            digitKey: "9"
        ),
    ]

    /// Phase 2 Weather tile — registered only when an explicit WeatherProvider is configured.
    static let weatherItem = NotchGalleryItem(
        id: "weather",
        destination: .extra(.weather),
        titleKey: "Thời tiết",
        symbol: "cloud.sun.fill",
        shortcutKey: "W",
        digitKey: "0"
    )

    static let stocksItem = NotchGalleryItem(
        id: "stocks",
        destination: .extra(.stocks),
        titleKey: "Chứng khoán",
        symbol: "chart.line.uptrend.xyaxis",
        shortcutKey: "K",
        digitKey: "-"
    )

    static let revenueItem = NotchGalleryItem(
        id: "revenue",
        destination: .extra(.revenue),
        titleKey: "Doanh thu",
        symbol: "banknote.fill",
        shortcutKey: "R",
        digitKey: "="
    )

    static func items(
        weatherAvailable: Bool,
        stocksAvailable: Bool = false,
        revenueAvailable: Bool = false
    ) -> [NotchGalleryItem] {
        var out = items
        if weatherAvailable { out.append(weatherItem) }
        if stocksAvailable { out.append(stocksItem) }
        if revenueAvailable { out.append(revenueItem) }
        return out
    }

    /// Matches either the mnemonic letter (case-insensitive) or digit (`1`–`9`, `0`, `-`, `=`).
    static func destination(
        forKeyCharacter ch: String,
        weatherAvailable: Bool = false,
        stocksAvailable: Bool = false,
        revenueAvailable: Bool = false
    ) -> NotchGalleryDestination? {
        let needle = ch.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard needle.count == 1 else { return nil }
        return items(weatherAvailable: weatherAvailable, stocksAvailable: stocksAvailable, revenueAvailable: revenueAvailable)
            .first { $0.shortcutKey.uppercased() == needle || $0.digitKey == needle }?
            .destination
    }

    /// XF-ISLAND-C: Returns only enabled AND ready destinations in the user's unified catalog order.
    static func items(
        catalog: NotchTabCatalogState,
        availability: NotchDestinationAvailability
    ) -> [NotchGalleryItem] {
        catalog.visibleDestinations(availability: availability).map(\.galleryItem)
    }

    /// XF-ISLAND-C: Resolves gallery mnemonic letters or digits strictly against enabled AND ready destinations.
    static func destination(
        forKeyCharacter ch: String,
        catalog: NotchTabCatalogState,
        availability: NotchDestinationAvailability
    ) -> NotchGalleryDestination? {
        let needle = ch.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard needle.count == 1 else { return nil }
        return items(catalog: catalog, availability: availability)
            .first { $0.shortcutKey.uppercased() == needle || $0.digitKey == needle }?
            .destination
    }

    static func titleKey(for extra: NotchExtraModule) -> String {
        switch extra {
        case .sections: return "Tất cả mục"
        case .settings: return "Cài đặt"
        case .home: return "Tổng quan"
        case .system: return "Hệ thống"
        case .audio: return "Âm thanh"
        case .reminders: return "Nhắc việc"
        case .weather: return "Thời tiết"
        case .stocks: return "Chứng khoán"
        case .revenue: return "Doanh thu"
        case .websiteAnalytics: return "Phân tích web"
        case .mirror: return "Gương"
        case .teleprompter: return "Máy nhắc chữ"
        case .notes: return "Ghi chú"
        case .capture: return "Chụp màn hình"
        case .units: return "Đổi đơn vị"
        case .scratchpad: return "Bản nháp"
        case .emoji: return "Emoji"
        case .fileBrowser: return "Trình duyệt tệp"
        case .links: return "Liên kết"
        case .imageConvert: return "Chuyển ảnh"
        case .sounds: return "Âm nền"
        case .todos: return "Việc cần làm"
        case .shortcuts: return "Phím tắt Apple"
        case .appUsage: return "Thời lượng ứng dụng"
        case .localChat: return "Chat trên máy"
        case .message: return "Tin nhắn cục bộ"
        case .feedback: return "Phản hồi"
        }
    }

    static func symbol(for extra: NotchExtraModule) -> String {
        switch extra {
        case .sections: return "square.grid.2x2"
        case .settings: return "gearshape"
        case .home: return "house.fill"
        case .system: return "cpu"
        case .audio: return "speaker.wave.2.fill"
        case .reminders: return "checklist"
        case .weather: return "cloud.sun.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .revenue: return "banknote.fill"
        case .websiteAnalytics: return "chart.xyaxis.line"
        case .mirror: return "camera"
        case .teleprompter: return "text.alignleft"
        case .notes: return "note.text"
        case .capture: return "camera.viewfinder"
        case .units: return "ruler"
        case .scratchpad: return "square.and.pencil"
        case .emoji: return "face.smiling"
        case .fileBrowser: return "folder"
        case .links: return "link"
        case .imageConvert: return "photo.on.rectangle.angled"
        case .sounds: return "waveform"
        case .todos: return "checkmark.square"
        case .shortcuts: return "square.stack.3d.up"
        case .appUsage: return "hourglass"
        case .localChat: return "bubble.left.and.bubble.right"
        case .message: return "bubble.left"
        case .feedback: return "bubble.left.and.text.bubble.right"
        }
    }
}
