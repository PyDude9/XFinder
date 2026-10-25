import Foundation

/// XF-T30 — Finder/FileOctopus "Group By" (Icon, List, Column views; Gallery has none, only Sort By). W1 declares the
/// cases so the toolbar's Group menu and the pane state can name them; W2 implements the grouping itself (headers such
/// as Today / Yesterday / Previous 7 Days). Pure, symlinked into the test package.
enum GroupBy: String, Codable, CaseIterable, Sendable {
    case none, name, kind, application, dateLastOpened, dateAdded, dateModified, dateCreated, size, tags

    /// L10n store key (the Vietnamese text itself).
    var titleKey: String {
        switch self {
        case .none: return "Không nhóm"
        case .name: return "Tên"
        case .kind: return "Loại"
        case .application: return "Ứng dụng"
        case .dateLastOpened: return "Ngày mở gần nhất"
        case .dateAdded: return "Ngày thêm"
        case .dateModified: return "Ngày sửa"
        case .dateCreated: return "Ngày tạo"
        case .size: return "Cỡ"
        case .tags: return "Các thẻ"
        }
    }
}
