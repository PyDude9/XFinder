import Foundation
import AppKit
import Observation

/// Liên kết nhanh (kiểu TinyCast): từ khóa → URL. CRUD thật, lưu trong
/// UserDefaults (`quickSearch.quicklinks`) — dùng trong Tìm nhanh của trang
/// Tìm kiếm.
@MainActor @Observable
final class Quicklinks {
    static let shared = Quicklinks()

    struct Quicklink: Codable, Identifiable, Equatable {
        var id = UUID()
        var keyword: String
        var title: String
        var url: String
    }

    private static let storageKey = "quickSearch.quicklinks"

    /// Liên kết mặc định lần đầu chạy — đủ để người dùng hiểu khái niệm.
    private static let defaults: [Quicklink] = [
        .init(keyword: "gg", title: "Google", url: "https://google.com"),
        .init(keyword: "gh", title: "GitHub", url: "https://github.com"),
        .init(keyword: "yt", title: "YouTube", url: "https://youtube.com"),
    ]

    private(set) var links: [Quicklink]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Quicklink].self, from: data) {
            links = saved
        } else {
            links = Self.defaults
            persist()
        }
    }

    func add(keyword: String, title: String, url: String) {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = Self.normalizeURL(url)
        guard !k.isEmpty, !t.isEmpty, !u.isEmpty else { return }
        links.append(Quicklink(keyword: k, title: t, url: u))
        persist()
    }

    func update(_ link: Quicklink, keyword: String, title: String, url: String) {
        guard let i = links.firstIndex(where: { $0.id == link.id }) else { return }
        var updated = links[i]
        updated.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.url = Self.normalizeURL(url)
        links[i] = updated
        persist()
    }

    func delete(_ link: Quicklink) {
        links.removeAll { $0.id == link.id }
        persist()
    }

    /// Tìm quicklink khớp query: khớp chính xác > tiền tố > trong tiêu đề.
    func search(query: String) -> [QuickSearchResult] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        let scored = links.compactMap { link -> (Int, QuickSearchResult)? in
            let score: Int
            if link.keyword == q {
                score = 0
            } else if link.keyword.hasPrefix(q) || q.hasPrefix(link.keyword) {
                score = 1
            } else if link.title.lowercased().contains(q) {
                score = 2
            } else {
                return nil
            }
            let result = QuickSearchResult(
                type: .quicklink,
                title: link.title,
                subtitle: "\(link.keyword) → \(link.url)",
                icon: NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil),
                action: { [link] in
                    if let url = URL(string: link.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
            return (score, result)
        }

        return scored
            .sorted { $0.0 < $1.0 }
            .prefix(4)
            .map(\.1)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func normalizeURL(_ raw: String) -> String {
        let u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return u }
        if u.hasPrefix("http://") || u.hasPrefix("https://") { return u }
        return "https://" + u
    }
}
