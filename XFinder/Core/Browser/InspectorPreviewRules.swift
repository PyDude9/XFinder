import Foundation

/// Bounded content classification and syntax ranges; no file I/O or AppKit.
enum InspectorPreviewRules {
    static let byteLimit = 256 * 1024
    enum Kind: Equatable { case markdown, code, plain }
    enum ReadResult: Equatable { case text(String), tooLarge, binary }
    static func kind(extension ext: String) -> Kind? {
        let ext = ext.lowercased()
        if ["md", "markdown", "mdown"].contains(ext) { return .markdown }
        if ["swift", "py", "js", "ts", "tsx", "jsx", "json", "sh", "zsh", "bash", "c", "h", "cpp", "rs", "go", "java", "css", "html", "xml", "yaml", "yml", "toml", "sql"].contains(ext) { return .code }
        if ["txt", "log", "csv"].contains(ext) { return .plain }
        return nil
    }
    static func decode(_ data: Data) -> ReadResult {
        guard data.count <= byteLimit else { return .tooLarge }
        guard !data.contains(0), let string = String(data: data, encoding: .utf8) else { return .binary }
        return .text(string)
    }
    struct Span: Equatable {
        enum Style { case keyword, string, comment }
        let range: NSRange
        let style: Style
    }
    /// Strings/comments win over keywords by matching all alternatives in a single forward pass.
    static func spans(in text: String) -> [Span] {
        let pattern = #"(?m)(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|\b(?:let|var|func|class|struct|enum|import|return|if|else|for|while|switch|case|true|false|nil|null|def|const|function|async|await|public|private|static|try|throw|throws|guard|in)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            Span(range: match.range, style: match.range(at: 1).location != NSNotFound ? .comment : (match.range(at: 2).location != NSNotFound ? .string : .keyword))
        }
    }
}
