import Foundation
import AppKit

/// Quicklinks: từ khóa → URL
final class Quicklinks {
    static let shared = Quicklinks()

    private let links: [String: (title: String, url: String)] = [
        "gg": ("Google", "https://google.com"),
        "search": ("Google", "https://google.com"),
        "gh": ("GitHub", "https://github.com"),
        "code": ("GitHub", "https://github.com"),
        "yt": ("YouTube", "https://youtube.com"),
        "video": ("YouTube", "https://youtube.com"),
    ]

    private init() {}

    func search(query: String) -> [CommandResult] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)

        // Khớp chính xác keyword
        if let link = links[q] {
            return [makeResult(keyword: q, title: link.title, url: link.url)]
        }

        // Fuzzy match: "g" → "gg", "gith" → "gh"
        let matches = links.filter { keyword, _ in
            keyword.hasPrefix(q) || q.hasPrefix(keyword)
        }

        return matches.map { keyword, link in
            makeResult(keyword: keyword, title: link.title, url: link.url)
        }
    }

    private func makeResult(keyword: String, title: String, url: String) -> CommandResult {
        CommandResult(
            type: .quicklink,
            title: title,
            subtitle: "\(keyword) → \(url)",
            icon: NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil),
            action: {
                if let nsUrl = URL(string: url) {
                    NSWorkspace.shared.open(nsUrl)
                }
            }
        )
    }
}
