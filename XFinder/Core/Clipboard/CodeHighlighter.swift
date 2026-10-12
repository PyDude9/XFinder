import Foundation

/// On-device syntax colouring for code clips shown on dark cards (Phase D, "highlight code (xử lý trên
/// máy)") — no network, no third-party library, Foundation only. `guessLanguage` is a cheap heuristic over
/// the text alone (clipboard clips carry no file name); `tokenize` is a single left-to-right pass that
/// must cover the whole string, in order, with no gaps (the test suite asserts contiguity).
///
/// A card shows at most a handful of lines, so this is capped rather than made clever: text over
/// `maxLength` characters renders as one `.plain` token. Re-tokenizing a long clip on every scroll frame
/// would cost more than the colouring is worth, and nothing on a card needs highlighting past what fits.
enum CodeHighlighter {

    /// Detected language. `.plain` means "nothing matched" — never a guess from one ambiguous word.
    enum Language: String, CaseIterable {
        case swift, javascript, typescript, python, shell, json, html, css, rust, go, c, plain
    }

    enum TokenKind: Equatable {
        case keyword, string, comment, number, type, plain
    }

    struct Token: Equatable {
        let range: Range<String.Index>
        let kind: TokenKind
    }

    /// Clips longer than this render as a single `.plain` token — see the type doc comment.
    static let maxLength = 4_000

    // MARK: - Language guessing

    /// Guesses a language from the text alone. Order matters: more specific / cheaper checks run first so
    /// a snippet that happens to contain an ambiguous word (e.g. plain prose mentioning "import") does not
    /// get claimed by a language whose marker is a single common English word.
    static func guessLanguage(_ text: String) -> Language {
        let t = text

        // JSON: a leading `{`/`[` (ignoring leading whitespace) that actually parses. Checked before the
        // brace-heavy C-family languages so a bare JSON object is never mistaken for e.g. a CSS rule.
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "{" || first == "[",
           let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
            return .json
        }

        if t.contains("<!--") || containsWord(t, "<html") || containsAny(t, ["<div", "<span", "<body", "<head", "</"]) {
            return .html
        }

        if t.contains("#!/bin/") || t.contains("#!/usr/bin/env") {
            return .shell
        }

        // CSS: a selector block — "... { prop: value; }" — without the keywords that mark a C-family
        // language. Checked before swift/js/c so `.card { color: red; }` is not read as a block statement.
        if looksLikeCSS(t) {
            return .css
        }

        if containsWord(t, "fn") || t.contains("let mut ") || containsWord(t, "impl") || t.contains("->") && containsWord(t, "fn") {
            return .rust
        }

        if t.contains(":=") && (containsWord(t, "package") || containsWord(t, "func")) {
            return .go
        }

        if t.contains("#include") || t.contains("int main") {
            return .c
        }

        if containsWord(t, "def") || containsWord(t, "self.") || looksLikePythonImport(t) || t.contains("elif ") || t.contains("print(") && containsWord(t, "def") {
            return .python
        }

        if containsWord(t, "func") || containsWord(t, "let") || containsWord(t, "guard") || containsWord(t, "var") && t.contains("->") {
            return .swift
        }

        if looksLikeJSOrTS(t) {
            if t.contains(": string") || t.contains(": number") || t.contains(": boolean") ||
                containsWord(t, "interface") || t.contains("<T>") || t.contains("): void") {
                return .typescript
            }
            return .javascript
        }

        // Shell, as a last resort: command-substitution / pipe idioms with no other language's markers.
        if (t.contains("$(") || containsWord(t, "echo") || t.contains("| grep")) {
            return .shell
        }

        return .plain
    }

    // MARK: - Tokenizing

    /// One left-to-right pass. Tokens are contiguous, cover the whole string, and are returned in order.
    static func tokenize(_ text: String, language: Language) -> [Token] {
        guard !text.isEmpty else { return [] }
        guard text.count <= maxLength else {
            return [Token(range: text.startIndex..<text.endIndex, kind: .plain)]
        }
        if language == .plain {
            return [Token(range: text.startIndex..<text.endIndex, kind: .plain)]
        }

        let scalars = Array(text.unicodeScalars)
        // Map unicode-scalar offsets back to String.Index once, up front, so the walk below stays O(n)
        // instead of re-deriving an index from an offset (which is itself O(n)) at every token boundary.
        var indices: [String.Index] = []
        indices.reserveCapacity(scalars.count + 1)
        var idx = text.startIndex
        indices.append(idx)
        for _ in scalars {
            idx = text.unicodeScalars.index(idx, offsetBy: 1)
            indices.append(idx)
        }

        let kws = keywords(for: language)
        let lineComment = lineCommentMarker(for: language)
        let hasBlockComment = language != .shell && language != .python
        let hasHashComment = language == .python || language == .shell
        let hasHTMLComment = language == .html

        var tokens: [Token] = []
        var i = 0
        let n = scalars.count

        func emit(_ start: Int, _ end: Int, _ kind: TokenKind) {
            guard end > start else { return }
            tokens.append(Token(range: indices[start]..<indices[end], kind: kind))
        }

        func isIdentStart(_ c: UnicodeScalar) -> Bool { CharacterSet.letters.contains(c) || c == "_" }
        func isIdentCont(_ c: UnicodeScalar) -> Bool { CharacterSet.alphanumerics.contains(c) || c == "_" }
        func isDigit(_ c: UnicodeScalar) -> Bool { c.properties.numericType == .decimal || ("0"..."9").contains(c) }

        while i < n {
            let c = scalars[i]

            // Comments — longest-match, checked before string/number so e.g. `//` is never read as
            // division-then-division.
            if hasHTMLComment, c == "<", i + 3 < n, scalars[i + 1] == "!", scalars[i + 2] == "-", scalars[i + 3] == "-" {
                var j = i + 4
                while j < n {
                    if scalars[j] == "-", j + 2 < n, scalars[j + 1] == "-", scalars[j + 2] == ">" { j += 3; break }
                    j += 1
                }
                emit(i, min(j, n), .comment)
                i = min(j, n)
                continue
            }
            if hasBlockComment, c == "/", i + 1 < n, scalars[i + 1] == "*" {
                var j = i + 2
                while j < n, !(scalars[j] == "*" && j + 1 < n && scalars[j + 1] == "/") { j += 1 }
                j = min(j + 2, n)
                emit(i, j, .comment)
                i = j
                continue
            }
            if lineComment == "//", c == "/", i + 1 < n, scalars[i + 1] == "/" {
                var j = i
                while j < n, !isNewline(scalars[j]) { j += 1 }
                emit(i, j, .comment)
                i = j
                continue
            }
            if hasHashComment, c == "#" {
                var j = i
                while j < n, !isNewline(scalars[j]) { j += 1 }
                emit(i, j, .comment)
                i = j
                continue
            }

            // Strings — longest-match: Swift triple-quote before single `"`.
            if language == .swift, c == "\"", i + 2 < n, scalars[i + 1] == "\"", scalars[i + 2] == "\"" {
                var j = i + 3
                while j < n {
                    if scalars[j] == "\"", j + 2 < n, scalars[j + 1] == "\"", scalars[j + 2] == "\"" { j += 3; break }
                    j += 1
                }
                j = min(j, n)
                emit(i, j, .string)
                i = j
                continue
            }
            if c == "\"" || c == "'" || c == "`" {
                let quote = c
                var j = i + 1
                while j < n {
                    if scalars[j] == "\\", j + 1 < n { j += 2; continue }
                    if scalars[j] == quote { j += 1; break }
                    j += 1
                }
                j = min(j, n)
                emit(i, j, .string)
                i = j
                continue
            }

            // Numbers.
            if isDigit(c) {
                var j = i + 1
                if c == "0", j < n, scalars[j] == "x" || scalars[j] == "X" {
                    j += 1
                    while j < n, scalars[j].properties.isHexDigit || scalars[j] == "_" { j += 1 }
                } else {
                    while j < n, isDigit(scalars[j]) || scalars[j] == "_" { j += 1 }
                    if j < n, scalars[j] == "." , j + 1 < n, isDigit(scalars[j + 1]) {
                        j += 1
                        while j < n, isDigit(scalars[j]) || scalars[j] == "_" { j += 1 }
                    }
                    if j < n, scalars[j] == "e" || scalars[j] == "E" {
                        var k = j + 1
                        if k < n, scalars[k] == "+" || scalars[k] == "-" { k += 1 }
                        if k < n, isDigit(scalars[k]) {
                            k += 1
                            while k < n, isDigit(scalars[k]) { k += 1 }
                            j = k
                        }
                    }
                }
                emit(i, j, .number)
                i = j
                continue
            }

            // Identifiers — keyword, type, or plain.
            if isIdentStart(c) {
                var j = i + 1
                while j < n, isIdentCont(scalars[j]) { j += 1 }
                let word = String(String.UnicodeScalarView(scalars[i..<j]))
                if kws.contains(word) {
                    emit(i, j, .keyword)
                } else if languageUsesTypeCapitalization(language), let first = word.unicodeScalars.first,
                          CharacterSet.uppercaseLetters.contains(first) {
                    emit(i, j, .type)
                } else {
                    emit(i, j, .plain)
                }
                i = j
                continue
            }

            // Everything else: run plain characters together up to the next special one, so punctuation
            // and whitespace do not each become their own token.
            var j = i + 1
            while j < n, !isSpecial(scalars[j], language: language) { j += 1 }
            emit(i, j, .plain)
            i = j
        }

        return tokens
    }

    /// Keyword sets per language. Public so tests can spot-check a few without re-deriving the list.
    static func keywords(for language: Language) -> Set<String> {
        switch language {
        case .swift:
            return ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum",
                    "protocol", "extension", "for", "while", "switch", "case", "default", "break",
                    "continue", "import", "public", "private", "internal", "fileprivate", "static",
                    "self", "Self", "init", "deinit", "throws", "throw", "try", "catch", "do", "as",
                    "is", "in", "where", "nil", "true", "false", "async", "await", "mutating",
                    "typealias", "associatedtype", "inout", "some", "any", "weak", "unowned", "lazy",
                    "final", "override", "required", "convenience", "operator", "defer", "repeat"]
        case .javascript:
            return ["function", "const", "let", "var", "if", "else", "return", "for", "while", "do",
                    "switch", "case", "default", "break", "continue", "class", "extends", "super",
                    "import", "export", "from", "async", "await", "try", "catch", "finally", "throw",
                    "new", "delete", "typeof", "instanceof", "in", "of", "this", "null", "undefined",
                    "true", "false", "yield", "static", "get", "set", "void"]
        case .typescript:
            return keywords(for: .javascript).union([
                "interface", "type", "enum", "implements", "namespace", "declare", "readonly",
                "public", "private", "protected", "abstract", "as", "is", "keyof", "infer", "never",
                "unknown", "any", "string", "number", "boolean"])
        case .python:
            return ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from",
                    "as", "try", "except", "finally", "raise", "with", "pass", "break", "continue",
                    "lambda", "yield", "global", "nonlocal", "del", "assert", "and", "or", "not", "in",
                    "is", "None", "True", "False", "self", "async", "await"]
        case .shell:
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
                    "function", "return", "exit", "export", "local", "readonly", "shift", "in",
                    "echo", "set", "unset", "source", "break", "continue"]
        case .json:
            return []
        case .html:
            return ["html", "head", "body", "div", "span", "a", "p", "script", "style", "link",
                    "meta", "title", "ul", "li", "table", "tr", "td", "form", "input", "button"]
        case .css:
            return ["important", "inherit", "initial", "unset", "auto", "none", "solid", "dashed",
                    "flex", "grid", "block", "inline", "absolute", "relative", "fixed", "static"]
        case .rust:
            return ["fn", "let", "mut", "if", "else", "match", "for", "while", "loop", "return",
                    "struct", "enum", "impl", "trait", "pub", "use", "mod", "crate", "self", "Self",
                    "as", "in", "where", "async", "await", "move", "ref", "static", "const", "unsafe",
                    "true", "false", "break", "continue", "dyn"]
        case .go:
            return ["func", "package", "import", "if", "else", "for", "range", "switch", "case",
                    "default", "return", "var", "const", "type", "struct", "interface", "map", "chan",
                    "go", "defer", "select", "break", "continue", "fallthrough", "goto", "nil", "true",
                    "false"]
        case .c:
            return ["int", "char", "float", "double", "void", "long", "short", "unsigned", "signed",
                    "struct", "union", "enum", "typedef", "if", "else", "for", "while", "do", "switch",
                    "case", "default", "break", "continue", "return", "sizeof", "static", "const",
                    "extern", "volatile", "goto", "include", "define"]
        case .plain:
            return []
        }
    }

    // MARK: - Private helpers

    private static func languageUsesTypeCapitalization(_ language: Language) -> Bool {
        language == .swift || language == .typescript || language == .rust || language == .go || language == .c
    }

    private static func lineCommentMarker(for language: Language) -> String? {
        switch language {
        case .swift, .javascript, .typescript, .rust, .go, .c: return "//"
        default: return nil
        }
    }

    private static func isNewline(_ c: UnicodeScalar) -> Bool {
        c == "\n" || c == "\r"
    }

    private static func isSpecial(_ c: UnicodeScalar, language: Language) -> Bool {
        if CharacterSet.letters.contains(c) || CharacterSet.decimalDigits.contains(c) || c == "_" { return true }
        if c == "\"" || c == "'" || c == "`" { return true }
        if c == "/" { return true }
        if c == "#", language == .python || language == .shell { return true }
        if c == "<", language == .html { return true }
        return false
    }

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        guard let range = text.range(of: word) else { return false }
        let beforeOK = range.lowerBound == text.startIndex || !isWordScalar(text[text.index(before: range.lowerBound)])
        let afterOK = range.upperBound == text.endIndex || !isWordScalar(text[range.upperBound])
        return beforeOK && afterOK
    }

    private static func isWordScalar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private static func looksLikePythonImport(_ text: String) -> Bool {
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("import ") || l.hasPrefix("from ") { return true }
        }
        return false
    }

    /// `const `, `=>`, `function ` — the three markers named in the spec. Checked after swift/python so a
    /// snippet with swift's `func`/`let`/`guard` or python's `def`/`self.` is claimed by the more specific
    /// language first.
    private static func looksLikeJSOrTS(_ text: String) -> Bool {
        text.contains("const ") || text.contains("=>") || containsWord(text, "function")
    }

    /// A CSS rule: a selector followed by `{`, with at least one `property: value;` inside, and none of
    /// the keywords that would mark a brace block as a different language's code (an `if`/`for` body, a
    /// Swift/Rust/Go function). This keeps `.card { color: red; }` from being read as a bare block statement.
    ///
    /// Only the trimmed LINE immediately before the `{` is checked as the selector — not everything
    /// before the brace — because a `.` or `#` can appear earlier in unrelated code (e.g. Python's
    /// `self.last = name` on its own line above an f-string's `{name}`), and that must not count.
    private static func looksLikeCSS(_ text: String) -> Bool {
        guard let braceRange = text.range(of: "{") else { return false }
        let beforeBrace = text[text.startIndex..<braceRange.lowerBound]
        let selectorLine = (beforeBrace.split(separator: "\n").last.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !selectorLine.isEmpty else { return false }
        let selectorLooksRight = selectorLine.range(
            of: #"^[.#]?[a-zA-Z][a-zA-Z0-9_-]*(\s*,\s*[.#]?[a-zA-Z][a-zA-Z0-9_-]*)*$"#,
            options: .regularExpression) != nil
        guard selectorLooksRight else { return false }
        guard text.range(of: #"[a-zA-Z-]+\s*:\s*[^;{}]+;"#, options: .regularExpression) != nil else { return false }
        let disqualifying = ["func ", "fn ", "def ", "if ", "if(", "for ", "for(", "while ", "class ", "package "]
        return !disqualifying.contains { text.contains($0) }
    }
}
