import SwiftUI

/// D (2026-10-12) — a code clip's body with on-device syntax colouring (`CodeHighlighter`, Foundation
/// only, no network). One `Text` built from an `AttributedString`, so the card keeps a single text
/// node, its `lineLimit`, and its truncation. Only the lines a card can show are tokenised: a 4 000-
/// character clip is cut to `maxLines` before tokenising, and anything longer than
/// `CodeHighlighter.maxLength` comes back as one plain run anyway.
struct HighlightedCodeText: View {
    let text: String
    var font: Font = .system(size: 10.5, design: .monospaced)
    /// `true` on the notch's dark cards, `false` on the shelf (which follows the system appearance).
    var dark: Bool
    var lineLimit: Int = 6
    var maxLines: Int = 8

    var body: some View {
        Text(Self.attributed(text, dark: dark, maxLines: maxLines))
            .font(font)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
    }

    static func attributed(_ text: String, dark: Bool, maxLines: Int) -> AttributedString {
        let shown = text.split(separator: "\n", maxSplits: maxLines, omittingEmptySubsequences: false)
            .prefix(maxLines).joined(separator: "\n")
        let language = CodeHighlighter.guessLanguage(shown)
        var out = AttributedString()
        for token in CodeHighlighter.tokenize(shown, language: language) {
            var run = AttributedString(String(shown[token.range]))
            run.foregroundColor = color(for: token.kind, dark: dark)
            out.append(run)
        }
        return out
    }

    /// Two palettes, one per background. Plain text is the card's normal colour so a clip with no
    /// recognised tokens looks exactly as it did before highlighting existed.
    static func color(for kind: CodeHighlighter.TokenKind, dark: Bool) -> Color {
        switch (kind, dark) {
        case (.plain, true):    return .white
        case (.plain, false):   return .primary
        case (.keyword, true):  return Color(red: 1.00, green: 0.48, blue: 0.70)
        case (.keyword, false): return Color(red: 0.61, green: 0.14, blue: 0.58)
        case (.string, true):   return Color(red: 0.99, green: 0.69, blue: 0.42)
        case (.string, false):  return Color(red: 0.77, green: 0.26, blue: 0.10)
        case (.comment, true):  return Color.white.opacity(0.5)
        case (.comment, false): return .secondary
        case (.number, true):   return Color(red: 0.78, green: 0.86, blue: 1.00)
        case (.number, false):  return Color(red: 0.11, green: 0.37, blue: 0.78)
        case (.type, true):     return Color(red: 0.56, green: 0.86, blue: 0.94)
        case (.type, false):    return Color(red: 0.10, green: 0.50, blue: 0.58)
        }
    }
}
