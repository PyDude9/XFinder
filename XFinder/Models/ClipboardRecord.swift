import Foundation

enum ContentType: String, CaseIterable, Identifiable, Codable, Sendable {
    case text
    case code
    case markdown
    case image
    case link
    case color
    case file

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
        }
    }
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
    var displayTitle: String {
        return sourceAppName ?? "Clipboard"
    }

    var displayPreview: String {
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
            return "now"
        } else if let minutes = components.minute, minutes < 60 {
            return "\(minutes)m ago"
        } else if let hours = components.hour, hours < 24 {
            return "\(hours)h ago"
        } else if let days = components.day, days < 7 {
            return "\(days)d ago"
        } else if let months = components.month, months < 12 {
            return "\(months)mo ago"
        } else {
            return "1y+ ago"
        }
    }
}
