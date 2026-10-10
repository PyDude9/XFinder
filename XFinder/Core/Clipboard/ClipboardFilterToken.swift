import Foundation

/// The `@filter` syntax of the clipboard search field (B5), parsed in FRONT of the existing
/// `ClipboardManager.filteredHistory()` so that function stays untouched:
///
///   `@image`, `@link`, `@code`, `@text`, `@color`, `@file`, `@markdown`, `@merged` → content type
///   `@<anything else>`                                                          → source app (substring)
///   everything that is not a token                                              → free-text search
///
/// Deliberately small: two token kinds and plain text. Not a query language.
enum ClipboardFilterToken {

    struct Parsed: Equatable {
        var type: ContentType?
        /// Lower-cased substring to match against the source app name or bundle id.
        var app: String?
        /// The remaining free text, whitespace-normalised.
        var text: String
    }

    /// Lower-cased type tokens, including a few Vietnamese aliases people will actually type.
    static let typeAliases: [String: ContentType] = [
        "text": .text, "văn bản": .text, "vanban": .text,
        "code": .code, "mã": .code,
        "markdown": .markdown, "md": .markdown,
        "image": .image, "img": .image, "ảnh": .image, "anh": .image, "hình": .image,
        "link": .link, "url": .link,
        "color": .color, "colour": .color, "màu": .color, "mau": .color,
        "file": .file, "tệp": .file, "tep": .file,
        "merged": .merged, "gộp": .merged,
    ]

    static func parse(_ query: String) -> Parsed {
        var out = Parsed(type: nil, app: nil, text: "")
        var words: [String] = []
        for raw in query.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            let word = String(raw)
            guard word.hasPrefix("@"), word.count > 1 else { words.append(word); continue }
            let token = String(word.dropFirst()).lowercased()
            if let t = typeAliases[token] {
                out.type = t                              // the last type token wins
            } else {
                out.app = token                           // the last app token wins
            }
        }
        out.text = words.joined(separator: " ")
        return out
    }

    /// Does `record`-shaped data match the app token? Case-insensitive substring on the app name
    /// or the bundle identifier, so `@chrome` finds both "Google Chrome" and `com.google.Chrome`.
    static func appMatches(token: String?, appName: String?, bundleID: String?) -> Bool {
        guard let token, !token.isEmpty else { return true }
        return (appName?.lowercased().contains(token) ?? false) || (bundleID?.lowercased().contains(token) ?? false)
    }
}
