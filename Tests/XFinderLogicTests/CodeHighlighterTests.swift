import XCTest
import Foundation

final class CodeHighlighterTests: XCTestCase {
    typealias H = CodeHighlighter

    // MARK: - Language guessing

    func testGuessLanguageOnRealSnippets() {
        XCTAssertEqual(H.guessLanguage("""
            func greet(name: String) -> String {
                guard !name.isEmpty else { return "?" }
                let message = "Hello, \\(name)!"
                return message
            }
            """), .swift)

        XCTAssertEqual(H.guessLanguage("""
            def greet(name):
                if not name:
                    return "?"
                self.last = name
                return f"Hello, {name}!"
            """), .python)

        XCTAssertEqual(H.guessLanguage("""
            const greet = (name) => {
                if (!name) return "?";
                return `Hello, ${name}!`;
            };
            """), .javascript)

        XCTAssertEqual(H.guessLanguage("""
            interface Greeting {
                name: string;
            }
            const greet = (g: Greeting): string => `Hello, ${g.name}!`;
            """), .typescript)

        XCTAssertEqual(H.guessLanguage(#"""
            {"name": "XFinder", "version": 2, "tags": ["mac", "clipboard"]}
            """#), .json)

        XCTAssertEqual(H.guessLanguage("""
            <html>
              <body>
                <div class="card">Hello</div>
              </body>
            </html>
            """), .html)

        XCTAssertEqual(H.guessLanguage("""
            #!/bin/bash
            echo "building…"
            $(pwd) | grep XFinder
            """), .shell)

        XCTAssertEqual(
            H.guessLanguage("Remember to import your contacts before the trip, it saves time."),
            .plain,
            "a prose sentence containing the word import must stay plain"
        )
    }

    func testMoreLanguageMarkers() {
        XCTAssertEqual(H.guessLanguage("""
            .card {
                color: red;
                padding: 4px;
            }
            """), .css)

        XCTAssertEqual(H.guessLanguage("""
            fn main() {
                let mut count = 0;
                impl Counter for Widget {}
            }
            """), .rust)

        XCTAssertEqual(H.guessLanguage("""
            package main
            func main() {
                x := 1
            }
            """), .go)

        XCTAssertEqual(H.guessLanguage("""
            #include <stdio.h>
            int main() {
                return 0;
            }
            """), .c)
    }

    // MARK: - Token coverage / contiguity

    /// A token stream must be contiguous (`tokens[i].range.upperBound == tokens[i+1].range.lowerBound`),
    /// start at `text.startIndex`, and end at `text.endIndex` — i.e. cover the whole string, in order.
    private func assertCoversWholeString(_ tokens: [H.Token], _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard !text.isEmpty else {
            XCTAssertTrue(tokens.isEmpty, file: file, line: line)
            return
        }
        XCTAssertFalse(tokens.isEmpty, "no tokens for non-empty text", file: file, line: line)
        guard let first = tokens.first, let last = tokens.last else { return }
        XCTAssertEqual(first.range.lowerBound, text.startIndex, "coverage must start at the beginning", file: file, line: line)
        XCTAssertEqual(last.range.upperBound, text.endIndex, "coverage must reach the end", file: file, line: line)
        for i in 0..<(tokens.count - 1) {
            XCTAssertEqual(tokens[i].range.upperBound, tokens[i + 1].range.lowerBound,
                            "gap or overlap between token \(i) and \(i + 1)", file: file, line: line)
        }
    }

    func testTokensAreContiguousAndCoverTheStringForEveryLanguage() {
        let samples: [(H.Language, String)] = [
            (.swift, "func greet(name: String) -> String {\n    // say hi\n    let x = 0x1F\n    return \"Hi \\(name)\"\n}"),
            (.javascript, "const x = 42; // comment\nfunction f() { return `hi ${x}`; }"),
            (.typescript, "interface X { name: string; }\nconst f = (x: X): string => `hi ${x.name}`;"),
            (.python, "def f(x):\n    # comment\n    return f'hi {x}'  # trailing"),
            (.shell, "#!/bin/bash\n# comment\necho \"hi $(whoami)\" | grep h"),
            (.json, "{\"a\": 1, \"b\": [1, 2, 3.5]}"),
            (.html, "<!-- comment -->\n<div class=\"card\">Hi</div>"),
            (.css, ".card {\n  /* comment */\n  color: red;\n}"),
            (.rust, "fn main() {\n    let mut x = 0x1F;\n    // comment\n}"),
            (.go, "package main\nfunc main() {\n    x := 1_000\n}"),
            (.c, "#include <stdio.h>\nint main() {\n    /* comment */\n    return 0;\n}"),
            (.plain, "just some plain prose with no code in it at all."),
        ]
        for (lang, text) in samples {
            let tokens = H.tokenize(text, language: lang)
            assertCoversWholeString(tokens, text)
        }
    }

    func testEmptyStringProducesNoTokens() {
        XCTAssertEqual(H.tokenize("", language: .swift), [])
    }

    // MARK: - Comment vs string disambiguation

    func testSlashSlashInsideAStringIsNotAComment() {
        let text = #"let url = "https://example.com" // real comment"#
        let tokens = H.tokenize(text, language: .swift)
        assertCoversWholeString(tokens, text)

        guard let urlRange = text.range(of: #""https://example.com""#) else {
            return XCTFail("fixture missing the quoted URL")
        }
        let stringToken = tokens.first { $0.range == urlRange }
        XCTAssertEqual(stringToken?.kind, .string, "the quoted URL (with // inside) must be ONE string token")

        guard let commentRange = text.range(of: "// real comment") else {
            return XCTFail("fixture missing the trailing comment")
        }
        let commentToken = tokens.first { $0.range == commentRange }
        XCTAssertEqual(commentToken?.kind, .comment, "the real // after the string must still be a comment")
    }

    func testHashInsidePythonStringIsNotAComment() {
        let text = #"x = "a # b"  # real comment"#
        let tokens = H.tokenize(text, language: .python)
        assertCoversWholeString(tokens, text)
        guard let stringRange = text.range(of: #""a # b""#) else {
            return XCTFail("fixture missing the quoted string")
        }
        XCTAssertEqual(tokens.first { $0.range == stringRange }?.kind, .string)
        guard let commentRange = text.range(of: "# real comment") else {
            return XCTFail("fixture missing the trailing comment")
        }
        XCTAssertEqual(tokens.first { $0.range == commentRange }?.kind, .comment)
    }

    // MARK: - Swift multi-line string

    func testSwiftTripleQuoteMultilineString() {
        let text = "let s = \"\"\"\nline one\nline // not a comment\n\"\"\"\nlet n = 1"
        let tokens = H.tokenize(text, language: .swift)
        assertCoversWholeString(tokens, text)

        guard let tripleRange = text.range(of: "\"\"\"\nline one\nline // not a comment\n\"\"\"") else {
            return XCTFail("fixture missing the triple-quoted block")
        }
        let tripleToken = tokens.first { $0.range == tripleRange }
        XCTAssertEqual(tripleToken?.kind, .string, "the whole triple-quoted block is ONE string token")

        guard let nRange = text.range(of: "1", range: text.range(of: "let n = ")!.upperBound..<text.endIndex) else {
            return XCTFail("fixture missing the trailing number")
        }
        XCTAssertEqual(tokens.first { $0.range == nRange }?.kind, .number, "code after the string is tokenized normally")
    }

    func testUnterminatedStringRunsToTheEnd() {
        let text = #"let s = "never closed"#
        let tokens = H.tokenize(text, language: .swift)
        assertCoversWholeString(tokens, text)
        XCTAssertEqual(tokens.last?.kind, .string)
        XCTAssertEqual(tokens.last?.range.upperBound, text.endIndex)
    }

    func testUnterminatedBlockCommentRunsToTheEnd() {
        let text = "let x = 1\n/* never closed"
        let tokens = H.tokenize(text, language: .swift)
        assertCoversWholeString(tokens, text)
        XCTAssertEqual(tokens.last?.kind, .comment)
        XCTAssertEqual(tokens.last?.range.upperBound, text.endIndex)
    }

    // MARK: - Numbers

    func testNumberLiterals() {
        let text = "let a = 0xFF\nlet b = 1_000\nlet c = 1.5e3"
        let tokens = H.tokenize(text, language: .swift)
        assertCoversWholeString(tokens, text)

        func numberToken(_ literal: String) -> H.Token? {
            guard let r = text.range(of: literal) else { return nil }
            return tokens.first { $0.range == r }
        }
        XCTAssertEqual(numberToken("0xFF")?.kind, .number, "hex literal")
        XCTAssertEqual(numberToken("1_000")?.kind, .number, "underscore grouping")
        XCTAssertEqual(numberToken("1.5e3")?.kind, .number, "decimal exponent")
    }

    // MARK: - Vietnamese text inside a string literal keeps correct String.Index ranges

    func testVietnameseDiacriticsInsideStringKeepCorrectRanges() {
        let text = #"let greeting = "Xin chào, đây là XFinder!" // lời chào"#
        let tokens = H.tokenize(text, language: .swift)
        assertCoversWholeString(tokens, text)

        guard let stringRange = text.range(of: #""Xin chào, đây là XFinder!""#) else {
            return XCTFail("fixture missing the Vietnamese string literal")
        }
        let stringToken = tokens.first { $0.range == stringRange }
        XCTAssertNotNil(stringToken, "the diacritic-bearing string must be found by its exact String.Index range")
        XCTAssertEqual(stringToken?.kind, .string)
        XCTAssertEqual(text[stringToken!.range], #""Xin chào, đây là XFinder!""#, "substring at the reported range must round-trip exactly")

        guard let commentRange = text.range(of: "// lời chào") else {
            return XCTFail("fixture missing the Vietnamese trailing comment")
        }
        let commentToken = tokens.first { $0.range == commentRange }
        XCTAssertEqual(commentToken?.kind, .comment)
        XCTAssertEqual(text[commentToken!.range], "// lời chào")
    }

    // MARK: - Length cap

    func testTextOverFourThousandCharactersIsOnePlainToken() {
        let long = String(repeating: "a", count: H.maxLength + 1)
        let tokens = H.tokenize(long, language: .swift)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens.first?.kind, .plain)
        XCTAssertEqual(tokens.first?.range, long.startIndex..<long.endIndex)
    }

    func testTextAtExactlyFourThousandCharactersIsTokenizedNormally() {
        let exact = String(repeating: "a", count: H.maxLength)
        let tokens = H.tokenize("func " + exact.dropFirst(5), language: .swift)
        assertCoversWholeString(tokens, "func " + exact.dropFirst(5))
        XCTAssertTrue(tokens.contains { $0.kind == .keyword }, "at the cap, real tokenizing still happens")
    }

    // MARK: - Keyword sets

    func testEveryKeywordSetIsNonEmptyExceptPlainAndJSON() {
        for language in CodeHighlighter.Language.allCases {
            let kws = H.keywords(for: language)
            if language == .plain || language == .json {
                XCTAssertTrue(kws.isEmpty, "\(language) should have no keywords")
            } else {
                XCTAssertFalse(kws.isEmpty, "\(language) must have at least one keyword")
            }
        }
    }

    func testSpotCheckSomeKeywords() {
        XCTAssertTrue(H.keywords(for: .swift).contains("func"))
        XCTAssertTrue(H.keywords(for: .python).contains("def"))
        XCTAssertTrue(H.keywords(for: .javascript).contains("function"))
        XCTAssertTrue(H.keywords(for: .typescript).contains("interface"))
        XCTAssertTrue(H.keywords(for: .rust).contains("fn"))
        XCTAssertTrue(H.keywords(for: .go).contains("package"))
        XCTAssertTrue(H.keywords(for: .c).contains("int"))
        XCTAssertTrue(H.keywords(for: .shell).contains("echo"))
    }
}
