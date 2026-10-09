import Foundation

/// The pure half of the SMART readout — shared by the Ổ đĩa page and the menubar flyout so
/// the two surfaces can never disagree about what a `diskutil` answer means.
///
/// Two rules this type exists to enforce:
///
/// 1. **It returns store KEYS, never display strings.** The previous `DiskManager.smartLabel`
///    returned Vietnamese sentences from Core and the page rendered them with a bare
///    `Text(...)`, so an English UI showed "Bình thường" — bug shape #1 in
///    `check-l10n-coverage.py`'s own header, invisible to every literal sweep because the
///    literal lives in a model file. Views must wrap: `Text(L10n.t(label.key))`.
///    `SMARTStatusTests` resolves every key against the shipped store.
/// 2. **Parsing is separated from the subprocess** so the `SMART Status:` extraction can be
///    pinned by a test with the exact text `diskutil info` prints, instead of being trusted.
enum SMARTStatus {

    /// What macOS can say. The raw value is kept because `diskutil` may print something this
    /// table does not know; the UI then shows the OS's own words rather than inventing a state.
    struct Label: Equatable {
        /// A Vietnamese L10n store key — the view translates it.
        let key: String
        /// `true` healthy, `false` failing, `nil` unknown / not supported.
        let healthy: Bool?
    }

    /// The three values `diskutil info` is documented to print. Anything else falls through
    /// `label(forRaw:)` unchanged.
    static let knownRawValues = ["Verified", "Failing", "Not Supported"]

    static let healthyKey = "Bình thường"
    static let failingKey = "Đang hỏng — sao lưu ngay"
    static let notSupportedKey = "Ổ đĩa không hỗ trợ SMART"

    static func label(forRaw raw: String) -> Label {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "verified":      return Label(key: healthyKey, healthy: true)
        case "failing":       return Label(key: failingKey, healthy: false)
        case "not supported": return Label(key: notSupportedKey, healthy: nil)
        default:              return Label(key: raw, healthy: nil)
        }
    }

    /// The value after `SMART Status:` in `diskutil info` output, or nil when the line is absent
    /// or empty. `diskutil` pads with many spaces, so the value is trimmed; a value containing
    /// ':' is kept whole (only the first colon separates the field name).
    static func parse(diskutilOutput text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            guard line.contains("SMART Status") else { continue }
            let value = line
                .components(separatedBy: ":")
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
