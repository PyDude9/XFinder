import Foundation

enum ContentType: String, CaseIterable, Identifiable, Codable, Sendable {
    case text
    case code
    case markdown
    case image
    case link
    case color
    case file
    case merged

    var id: String { rawValue }

    var titleVI: String {
        switch self {
        case .text: return L10n.t("Văn bản")
        case .code: return L10n.t("Mã nguồn")
        case .markdown: return "Markdown"
        case .image: return L10n.t("Hình ảnh")
        case .link: return L10n.t("Liên kết")
        case .color: return L10n.t("Màu sắc")
        case .file: return L10n.t("Tập tin")
        case .merged: return L10n.t("Đã gộp")
        }
    }

    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "text.badge.checkmark"
        case .image: return "photo"
        case .link: return "link"
        case .color: return "paintpalette"
        case .file: return "doc"
        case .merged: return "arrow.triangle.merge"
        }
    }
}

/// Encoding / decoding codec for merged multi-clip records (Klippy format).
enum MergedClipCodec {
    private static let prefix = "\u{001F}XFINDER_MERGE\u{001F}"
    private static let separator = "\u{001F}"

    static func encode(_ components: [String]) -> String {
        prefix + separator + components.joined(separator: separator)
    }

    static func decode(_ content: String) -> [String] {
        guard content.hasPrefix(prefix) else { return [content] }
        let stripped = String(content.dropFirst(prefix.count))
        let trimmed = stripped.hasPrefix(separator) ? String(stripped.dropFirst(separator.count)) : stripped
        return trimmed.components(separatedBy: separator)
    }

    static func isMerged(_ content: String) -> Bool {
        content.hasPrefix(prefix)
    }
}

/// Slice of clipboard history (Klippy views: History, Pinned, Saved, Merged).
enum ClipboardSlice: String, CaseIterable, Identifiable {
    case all
    case pinned
    case saved
    case merged

    var id: String { rawValue }

    var titleVI: String {
        switch self {
        case .all: return L10n.t("Tất cả")
        case .pinned: return L10n.t("Đã ghim")
        case .saved: return L10n.t("Đã lưu")
        case .merged: return L10n.t("Đã gộp")
        }
    }

    var icon: String {
        switch self {
        case .all: return "clock"
        case .pinned: return "pin.fill"
        case .saved: return "bookmark.fill"
        case .merged: return "arrow.triangle.merge"
        }
    }
}

/// Sort order for clipboard history.
enum ClipboardSortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case mostUsed

    var id: String { rawValue }

    var titleVI: String {
        switch self {
        case .newest: return L10n.t("Mới nhất")
        case .oldest: return L10n.t("Cũ nhất")
        case .mostUsed: return L10n.t("Dùng nhiều nhất")
        }
    }

    var icon: String {
        switch self {
        case .newest: return "arrow.down"
        case .oldest: return "arrow.up"
        case .mostUsed: return "flame"
        }
    }
}

/// Date range filter for clipboard search.
enum ClipboardDateFilter: String, CaseIterable, Identifiable {
    case allTime
    case today
    case last7Days
    case last30Days

    var id: String { rawValue }

    var titleVI: String {
        switch self {
        case .allTime: return L10n.t("Tất cả thời gian")
        case .today: return L10n.t("Hôm nay")
        case .last7Days: return L10n.t("7 ngày qua")
        case .last30Days: return L10n.t("30 ngày qua")
        }
    }

    func matches(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .allTime:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .last7Days:
            guard let limit = calendar.date(byAdding: .day, value: -7, to: now) else { return true }
            return date >= limit
        case .last30Days:
            guard let limit = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return date >= limit
        }
    }
}

/// Day-grouped bucket of clipboard records.
struct ClipDayGroup: Identifiable {
    let id: Date
    let label: String
    let dateString: String
    var records: [ClipboardRecord]
}

struct ClipboardRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let type: ContentType
    let timestamp: Date
    let sourceBundleID: String?
    let sourceAppName: String?
    let textSnippet: String?
    let thumbnailPath: String?
    let payloadPath: String?
    let ocrText: String?
    let pinboardID: UUID?
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        type: ContentType,
        timestamp: Date = Date(),
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        textSnippet: String? = nil,
        thumbnailPath: String? = nil,
        payloadPath: String? = nil,
        ocrText: String? = nil,
        pinboardID: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.textSnippet = textSnippet
        self.thumbnailPath = thumbnailPath
        self.payloadPath = payloadPath
        self.ocrText = ocrText
        self.pinboardID = pinboardID
        self.metadata = metadata
    }

    // Preview properties
    var isPinned: Bool {
        metadata["isPinned"] == "true"
    }

    var isSavedSnippet: Bool {
        metadata["isSaved"] == "true"
    }

    var customTitle: String? {
        metadata["customTitle"]
    }

    var usageCount: Int {
        Int(metadata["usageCount"] ?? "0") ?? 0
    }

    var mergedComponents: [String] {
        guard type == .merged, let snippet = textSnippet else { return [] }
        return MergedClipCodec.decode(snippet)
    }

    var displayTitle: String {
        if let custom = customTitle, !custom.isEmpty {
            return custom
        }
        return sourceAppName ?? "Clipboard"
    }

    var displayPreview: String {
        if type == .merged {
            let parts = mergedComponents
            return parts.joined(separator: "\n")
        }
        return textSnippet ?? ""
    }

    var timeString: String {
        return timestamp.relativeString()
    }
}

extension Date {
    func relativeString() -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: self, to: now)

        if let minutes = components.minute, minutes < 1 {
            return L10n.t("vừa xong")
        } else if let minutes = components.minute, minutes < 60 {
            return "\(minutes)\(L10n.t(" phút trước"))"
        } else if let hours = components.hour, hours < 24 {
            return "\(hours)\(L10n.t(" giờ trước"))"
        } else {
            let days = components.day ?? 1
            return "\(days)\(L10n.t(" ngày trước"))"
        }
    }
}

