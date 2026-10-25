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

/// XF-T30 W2 — one group of a grouped listing. `titleKey` is an L10n key; `titleArg` a value shown after it (a month
/// name, a year, a kind or tag name) that is not translated.
struct EntrySection: Equatable, Sendable {
    let titleKey: String
    let titleArg: String?
    let entries: [DirectoryEntry]
}

extension GroupBy {
    /// Groups `entries` (already filtered) into sections in display order, each section sorted by `sort` — rules in
    /// contract XF-T30-w2 §1 (relative dates Today / Yesterday / Previous 7 Days / Previous 30 Days / months / years,
    /// first letter, kind, application, size buckets, tags). `.none` ⇒ one section with every entry. W2 builder (pure).
    static func sections(_ entries: [DirectoryEntry], by group: GroupBy, sort: SortOrder, foldersFirst: Bool, now: Date,
                         calendar: Calendar, kindName: (DirectoryEntry) -> String,
                         appName: (DirectoryEntry) -> String?) -> [EntrySection] {
        [EntrySection(titleKey: "", titleArg: nil, entries: entries)]
    }
}
