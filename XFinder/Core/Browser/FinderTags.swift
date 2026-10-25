import Foundation

/// XF-T30 W2/W3/W7 — Finder tags: the seven colours and the `com.apple.metadata:_kMDItemUserTags` value format
/// ("Name\n<colour number>"). Pure, symlinked into the test package. W2 builder (pure): implement.
enum TagColor: Int, Codable, CaseIterable, Sendable {
    case none = 0, gray, green, purple, blue, yellow, red, orange

    /// L10n key of the colour's default Finder tag name.
    var titleKey: String {
        switch self {
        case .none: return "Không màu"
        case .gray: return "Xám"
        case .green: return "Xanh lá"
        case .purple: return "Tím"
        case .blue: return "Xanh dương"
        case .yellow: return "Vàng"
        case .red: return "Đỏ"
        case .orange: return "Cam"
        }
    }
}

struct FinderTag: Equatable, Hashable, Sendable {
    let name: String
    let color: TagColor
}

enum FinderTags {
    /// One stored tag string ("Work\n6", or just "Work") → tag. W2 builder (pure): implement.
    static func parse(_ raw: String) -> FinderTag { FinderTag(name: raw, color: .none) }
    /// Tag → stored string (colour suffix only when the colour is not `.none`). W2 builder (pure): implement.
    static func encode(_ tag: FinderTag) -> String { tag.name }
    /// The xattr's property-list payload (array of strings) → tags; garbage ⇒ empty. W2 builder (pure): implement.
    static func decodeXattr(_ data: Data) -> [FinderTag] { [] }
    static func encodeXattr(_ tags: [FinderTag]) -> Data { Data() }
}
