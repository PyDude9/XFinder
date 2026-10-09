import Foundation

/// The pure rule behind the sidebar search box. Job: *"I know the page exists — get me to it
/// without scrolling 40 rows."*
///
/// Matching ignores case AND diacritics, and treats `đ` as `d`: a Vietnamese user typing on a
/// non-Vietnamese layout types `tong quan`, not `Tổng quan`. Every space-separated word must
/// appear somewhere in the row's searchable text (title, section, internal name), in any order.
enum SidebarSearch {

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
    }

    static func matches(query: String, texts: [String]) -> Bool {
        let words = fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return true }
        let haystack = texts.map(fold).joined(separator: " ")
        return words.allSatisfy { haystack.contains($0) }
    }

    /// Groups reduced to the rows that match; groups left empty disappear. An empty query returns
    /// everything unchanged.
    static func filter<T>(_ groups: [(header: String, items: [T])], query: String,
                          texts: (String, T) -> [String]) -> [(header: String, items: [T])] {
        groups.compactMap { g in
            let kept = g.items.filter { matches(query: query, texts: texts(g.header, $0)) }
            return kept.isEmpty ? nil : (g.header, kept)
        }
    }
}
