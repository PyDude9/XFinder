import Foundation

/// Keep file content usable when a split pane cannot fit the side Inspector.
enum InspectorLayoutRules {
    static let sidebarWidth: Double = 280
    static let minimumContentWidth: Double = 280
    static let dividerWidth: Double = 1

    static func stacksInspector(availableWidth: Double) -> Bool {
        !availableWidth.isFinite || availableWidth < sidebarWidth + dividerWidth + minimumContentWidth
    }

    static func stackedInspectorHeight(availableHeight: Double) -> Double {
        guard availableHeight.isFinite else { return 0 }
        let usable = max(0, availableHeight - dividerWidth)
        return min(sidebarWidth, usable * 0.4)
    }
}

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
    /// SwiftUI Text ignores block presentation intents. Materialize separators and list markers
    /// while retaining the Markdown parser's inline emphasis and links.
    static func markdown(_ text: String) -> AttributedString {
        guard let parsed = try? AttributedString(markdown: text) else { return AttributedString(text) }
        var output = AttributedString()
        var lastBlock: Int?
        for run in parsed.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            var segment = AttributedString(parsed[run.range])
            if block != lastBlock {
                if !output.characters.isEmpty { output.append(AttributedString("\n\n")) }
                if let listItem = components.first(where: { if case .listItem = $0.kind { return true }; return false }),
                   case .listItem(let ordinal) = listItem.kind {
                    let ordered = components.contains { if case .orderedList = $0.kind { return true }; return false }
                    output.append(AttributedString(ordered ? "\(ordinal). " : "• "))
                }
                lastBlock = block
            }
            if components.contains(where: { if case .header = $0.kind { return true }; return false }) {
                segment.inlinePresentationIntent = (segment.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            }
            output.append(segment)
        }
        return output
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
