import SwiftUI

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    // CHUNG — built now, real data
    case dashboard
    case quickControls
    case antiSleep
    case system
    case network
    case storage
    case pin
    // Clipboard & Ghi chú
    case clipboard
    case notes
    // CỬA SỔ — real except menuIcons (private API)
    case windowPreview
    case snapZones
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
    // CÀI ĐẶT
    // `settingsGeneral` was removed: "Cài đặt chung" only held theme + Dock
    // icon, both of which already live on Tổng quan / Điều khiển nhanh. A
    // catch-all settings bucket duplicated pages that own their own settings.
    case settingsClipboard
    // Footer
    case about

    var id: String { rawValue }

    var titleVI: String {
        switch self {
        case .dashboard: return L10n.t("Tổng quan")
        case .quickControls: return L10n.t("Điều khiển nhanh")
        case .antiSleep: return L10n.t("Chống ngủ")
        case .system: return L10n.t("Hệ thống")
        case .network: return L10n.t("Mạng")
        case .storage: return L10n.t("Ổ đĩa")
        case .pin: return L10n.t("Pin")
        case .clipboard: return L10n.t("Clipboard")
        case .notes: return L10n.t("Ghi chú")
        case .windowPreview: return L10n.t("Xem trước cửa sổ")
        case .snapZones: return L10n.t("Vùng bắt dính")
        case .menuIcons: return L10n.t("Biểu tượng thanh menu")
        case .finderKeyboard: return L10n.t("Bàn phím Finder")
        case .finderActions: return L10n.t("Thao tác Finder")
        case .finderSearch: return L10n.t("Tìm kiếm")
        case .aiSearch: return L10n.t("Tìm kiếm AI")
        case .batchRename: return L10n.t("Đổi tên hàng loạt")
        case .actionHistory: return L10n.t("Lịch sử thao tác")
        case .dropTray: return L10n.t("Khay thả")
        case .compress: return L10n.t("Nén & Giải nén")
        case .pdfTools: return L10n.t("Công cụ PDF")
        case .folderLock: return L10n.t("Khóa thư mục")
        case .quickLookPage: return L10n.t("Quick Look")
        case .mediaCompat: return L10n.t("Tương thích media")
        case .finderUtils: return L10n.t("Tiện ích Finder")
        case .sync: return L10n.t("Đồng bộ")
        case .remoteConnect: return L10n.t("Kết nối từ xa")
        case .quickShare: return L10n.t("Chia sẻ nhanh")
        case .settingsClipboard: return L10n.t("Cài đặt Clipboard")
        case .about: return L10n.t("Giới thiệu")
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .quickControls: return "slider.horizontal.3"
        case .antiSleep: return "moon.zzz.fill"
        case .system: return "cpu"
        case .network: return "network"
        case .storage: return "internaldrive.fill"
        case .pin: return "battery.100"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notes: return "note.text"
        case .windowPreview: return "macwindow.badge.plus"
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
            // Clipboard: hàng `clipboard` là trang nội dung (deck), hàng
            // `settingsClipboard` ("Cài đặt Clipboard") là tuỳ chỉnh + quyền
            // Trợ năng. Không còn kiểu "sidebar chỉ có settings" — khi chưa
            // cấp AX, ⌘⇧V không mở được và cả tính năng đọc như đã chết.
            // No CÀI ĐẶT group at all: every page owns its own settings, and a
            // catch-all bucket only duplicated them.
            //
            // Grouping follows the reference screenshots. The two file-name
            // tools (Đổi tên hàng loạt, Lịch sử thao tác) sit under
            // FINDER & TÌM KIẾM, not CÔNG CỤ — they act on the Finder selection
            // and belong beside the search rows the user reaches them from.
            // CÔNG CỤ keeps the content tools; TIỆN ÍCH keeps the Finder
            // integration surfaces.
            ("CHUNG", [.dashboard, .quickControls, .antiSleep, .system, .network, .storage, .pin]),
            ("CỬA SỔ", [.windowPreview, .snapZones, .menuIcons]),
            ("FINDER & TÌM KIẾM", [.finderKeyboard, .finderActions, .finderSearch, .aiSearch,
                                   .batchRename, .actionHistory]),
            ("CÔNG CỤ", [.clipboard, .settingsClipboard, .notes, .dropTray, .compress, .pdfTools, .folderLock]),
            ("KẾT NỐI", [.sync, .remoteConnect, .quickShare]),
            ("TIỆN ÍCH", [.finderUtils, .quickLookPage, .mediaCompat]),
        ]
    }
}
