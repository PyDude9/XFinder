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
    /// One stored tag string ("Work\n6", or just "Work") → tag. A trailing "\n<digits>" is the colour number (0…7,
    /// matching `TagColor`'s raw values); any other suffix (no digits, out-of-range number, more than one newline) is
    /// part of the name itself — Finder lets a tag name contain a literal "\n" with no colour, and this must not
    /// mistake that for a malformed colour suffix and silently eat characters off the name.
    static func parse(_ raw: String) -> FinderTag {
        guard let lastNewline = raw.lastIndex(of: "\n") else { return FinderTag(name: raw, color: .none) }
        let suffix = raw[raw.index(after: lastNewline)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber), let number = Int(suffix), let color = TagColor(rawValue: number) else {
            return FinderTag(name: raw, color: .none)
        }
        return FinderTag(name: String(raw[raw.startIndex..<lastNewline]), color: color)
    }

    /// Tag → stored string (colour suffix only when the colour is not `.none`, matching what Finder itself writes —
    /// an uncoloured tag has no trailing "\n0").
    static func encode(_ tag: FinderTag) -> String {
        tag.color == .none ? tag.name : "\(tag.name)\n\(tag.color.rawValue)"
    }

    /// The xattr's property-list payload (binary plist array of strings, `com.apple.metadata:_kMDItemUserTags`) →
    /// tags; anything that is not a well-formed plist array of strings (empty data, a dictionary, non-string
    /// elements, truncated bytes) decodes to empty rather than throwing or crashing.
    static func decodeXattr(_ data: Data) -> [FinderTag] {
        guard !data.isEmpty,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let strings = plist as? [String]
        else { return [] }
        return strings.map(parse)
    }

    static func encodeXattr(_ tags: [FinderTag]) -> Data {
        let strings = tags.map(encode)
        return (try? PropertyListSerialization.data(fromPropertyList: strings, format: .binary, options: 0)) ?? Data()
    }
}
