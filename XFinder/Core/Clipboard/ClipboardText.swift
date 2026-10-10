import Foundation

/// Where a clip's TEXT lives, and how to get all of it back. Pure, so the rule is tested.
///
/// Measured on this Mac's `xfinder.db` (2026-10-10): text records stored `textSnippet = prefix(200)`
/// and wrote a payload file only above 4 096 characters, while the paste path read `textSnippet`
/// and never the payload. 227 records of 201–4 096 characters held only their first 200 — every
/// paste of a clip longer than 200 characters from the shelf was truncated, silently. Now: the
/// snippet is a PREVIEW, anything longer than it gets a payload file, and every consumer that
/// needs the text goes through `fullText`.
enum ClipboardText {
    /// Length of the stored preview; a payload file is written for anything longer.
    static let previewLength = 200

    static func needsPayload(_ text: String) -> Bool { text.count > previewLength }

    static func preview(_ text: String) -> String { String(text.prefix(previewLength)) }

    /// The whole text: the payload file when there is one and it can be read, else the snippet.
    /// Never nil while a snippet exists — a missing payload degrades to the preview, not to nothing.
    static func fullText(snippet: String?, payloadPath: String?, read: (String) -> String? = Self.readFile) -> String? {
        if let p = payloadPath, !p.isEmpty, let full = read(p), !full.isEmpty { return full }
        return snippet
    }

    private static func readFile(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }
}
