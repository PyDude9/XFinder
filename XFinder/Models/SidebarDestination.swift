import SwiftUI

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
    // CÀI ĐẶT
    // `settingsGeneral` was removed: "Cài đặt chung" only held theme + Dock
    // icon, both of which already live on Tổng quan / Điều khiển nhanh. A
    // catch-all settings bucket duplicated pages that own their own settings.
    case settingsClipboard
    // Footer
    case about

    var id: String { rawValue }

    /// The Vietnamese literal — the L10n store key. Search matches it AND its English translation,
    /// so the box finds a page in either language whatever the UI language is.
    var titleKey: String {
        switch self {
        case .dashboard: return "Tổng quan"
        case .features: return "Tính năng & Quyền"
        case .antiSleep: return "Chống ngủ"
        case .system: return "Hệ thống"
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
        case .actionHistory: return "Lịch sử thao tác"
        case .dropTray: return "Notch & Khay thả"
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
        case .settingsClipboard: return "Cài đặt Clipboard"
        case .about: return "Giới thiệu"
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
        case .settingsClipboard: return "gearshape"
        case .about: return "info.circle"
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
            ("CHUNG", [.dashboard, .features, .antiSleep, .system, .network, .storage, .pin, .alerts]),
            ("CỬA SỔ", [.windowPreview, .snapZones, .mouseGestures, .menuIcons]),
            ("FINDER & TÌM KIẾM", [.finderKeyboard, .finderActions, .finderSearch, .aiSearch,
                                   .batchRename, .actionHistory]),
            ("CÔNG CỤ", [.voiceTyping, .settingsClipboard, .notes, .dropTray, .compress, .pdfTools, .folderLock]),
            ("KẾT NỐI", [.sync, .remoteConnect, .quickShare, .ports]),
            ("TIỆN ÍCH", [.finderUtils, .quickLookPage, .mediaCompat]),
        ]
    }
}
