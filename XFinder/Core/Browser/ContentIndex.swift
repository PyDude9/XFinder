import Foundation

/// XF-T30 W5a — the opt-in content index (FileOctopus `ContentIndex`, FTS5 `unicode61 remove_diacritics 2`, `alt` column
/// for OCR text). Extraction runs in the `XFinder --vision` child (text-pdf / text-rich / ocr-index). Contract
/// docs/specs/XF-T30-w5a-contract.md §3. W5a builder (C5): implement.
actor ContentIndex {
    static let shared = ContentIndex()

    struct Hit: Equatable, Sendable {
        let path: String
        let snippet: String
        let rank: Double
    }

    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/XFinder/Browser/Search/content.sqlite")
    }

    func setRoots(_ roots: [IndexRoot]) {}
    func status() -> [String: IndexRootStatus] { [:] }
    func search(_ text: String, within folders: [String]?, limit: Int) -> [Hit] { [] }
    func eraseAll() {}
    func suspend() {}
    func resume() {}
}
