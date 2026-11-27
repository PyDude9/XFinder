import Foundation

/// Pure model and expansion rules for Text Snippets (inspired by Vorssaint's Snippet Library).
/// Supports single-pass variable substitution: `{date}`, `{time}`, `{datetime}`, `{clipboard}`.
struct TextSnippet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var trigger: String
    var expansion: String
    var isEnabled: Bool

    init(id: UUID = UUID(), trigger: String, expansion: String, isEnabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.isEnabled = isEnabled
    }
}

enum TextSnippetRules {
    static let maxBufferLength = 48
    static let syntheticTag: Int64 = 0x5846534E4950 // "XFSNIP"
    static let keyCodeBackspace = 51

    private static let resetKeyCodes: Set<Int> = [36, 48, 53, 76, 115, 116, 119, 121, 123, 124, 125, 126]

    static func shouldResetBuffer(keyCode: Int, flags: UInt64) -> Bool {
        // Command (1 << 20), Control (1 << 18), Option (1 << 19)
        let modifierMask: UInt64 = (1 << 20) | (1 << 18) | (1 << 19)
        if (flags & modifierMask) != 0 { return true }
        return resetKeyCodes.contains(keyCode)
    }

    struct TypingBuffer: Equatable, Sendable {
        private(set) var text: String = ""

        mutating func append(_ chars: String) {
            text.append(chars)
            if text.count > TextSnippetRules.maxBufferLength {
                text.removeFirst(text.count - TextSnippetRules.maxBufferLength)
            }
        }

        mutating func backspace() {
            guard !text.isEmpty else { return }
            text.removeLast()
        }

        mutating func clear() {
            text = ""
        }
    }

    enum ValidationError: Equatable, Sendable {
        case emptyTrigger
        case emptyExpansion
        case duplicateTrigger
    }

    static func normalizedTrigger(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validate(
        trigger: String,
        expansion: String,
        existing: [TextSnippet],
        excludingID: UUID? = nil
    ) -> ValidationError? {
        let cleanTrigger = normalizedTrigger(trigger)
        guard !cleanTrigger.isEmpty else { return .emptyTrigger }
        guard !expansion.isEmpty else { return .emptyExpansion }
        let lower = cleanTrigger.lowercased()
        let dup = existing.contains { snippet in
            snippet.id != excludingID && normalizedTrigger(snippet.trigger).lowercased() == lower
        }
        return dup ? .duplicateTrigger : nil
    }

    /// Single-pass expansion of `{date}`, `{time}`, `{datetime}`, and `{clipboard}`.
    /// Never re-expands tokens that appear inside the clipboard value.
    static func expand(
        _ template: String,
        now: Date = Date(),
        clipboardText: String? = nil,
        timeZone: TimeZone = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.timeZone = timeZone
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: now)

        let replacements: [String: String] = [
            "{date}": dateStr,
            "{time}": timeStr,
            "{datetime}": "\(dateStr) \(timeStr)",
            "{clipboard}": clipboardText ?? "",
        ]

        var result = ""
        result.reserveCapacity(template.count)
        var idx = template.startIndex
        while idx < template.endIndex {
            var matched = false
            for (token, value) in replacements {
                if template[idx...].hasPrefix(token) {
                    result.append(value)
                    idx = template.index(idx, offsetBy: token.count)
                    matched = true
                    break
                }
            }
            if !matched {
                result.append(template[idx])
                idx = template.index(after: idx)
            }
        }
        return result
    }

    /// Find the longest enabled snippet whose trigger matches the suffix of `buffer`.
    static func match(buffer: String, snippets: [TextSnippet]) -> TextSnippet? {
        guard !buffer.isEmpty else { return nil }
        return snippets
            .filter { $0.isEnabled && !$0.trigger.isEmpty && buffer.hasSuffix($0.trigger) }
            .max { $0.trigger.count < $1.trigger.count }
    }

    /// Filter enabled snippets for Command Bar (`⌘K`) / QuickSearch by trigger or expansion text.
    /// Exact trigger matches rank first, followed by prefix trigger matches, then substring matches.
    static func search(query: String, snippets: [TextSnippet]) -> [TextSnippet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return snippets
            .filter { $0.isEnabled }
            .compactMap { item -> (Int, TextSnippet)? in
                let trig = item.trigger.lowercased()
                let exp = item.expansion.lowercased()
                if trig == q { return (0, item) }
                if trig.hasPrefix(q) { return (1, item) }
                if trig.contains(q) { return (2, item) }
                if exp.contains(q) { return (3, item) }
                return nil
            }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.trigger.count < $1.1.trigger.count }
            .map(\.1)
    }
}
