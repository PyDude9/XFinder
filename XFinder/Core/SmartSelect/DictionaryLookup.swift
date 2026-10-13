import AppKit
import CoreServices

/// §3b #35 — the live half of "Định nghĩa": Dictionary Services (`DCSCopyTextDefinition`), public and on-device.
/// Measured on macOS 27 (2026-10-13): English and Vietnamese entries ("serendipity", "máy tính", "ngoại lệ", "Thuỷ") in
/// 1–73 ms, nil for non-words ("asdfqwer") and for phrases not in the installed dictionaries ("xin chào"). No permission,
/// no network — the row only appears when the dictionary actually has an entry.
enum DictionaryLookup {
    static func definition(_ term: String) -> String? {
        let range = CFRange(location: 0, length: (term as NSString).length)
        return DCSCopyTextDefinition(nil, term as CFString, range)?.takeRetainedValue() as String?
    }

    /// Opens the entry in Dictionary.app (`dict://` is the scheme Dictionary registers).
    @MainActor static func open(_ term: String) {
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "dict://\(q)") else { return }
        NSWorkspace.shared.open(url)
    }
}
