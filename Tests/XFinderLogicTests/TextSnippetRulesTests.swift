import XCTest

final class TextSnippetRulesTests: XCTestCase {
    func testValidationRejectsEmptyAndDuplicateTriggers() {
        let existing = [TextSnippet(trigger: ";sig", expansion: "Best regards")]
        XCTAssertEqual(TextSnippetRules.validate(trigger: "   ", expansion: "hi", existing: existing), .emptyTrigger)
        XCTAssertEqual(TextSnippetRules.validate(trigger: ";ok", expansion: "", existing: existing), .emptyExpansion)
        XCTAssertEqual(TextSnippetRules.validate(trigger: ";SIG", expansion: "other", existing: existing), .duplicateTrigger)
        XCTAssertNil(TextSnippetRules.validate(trigger: ";date", expansion: "{date}", existing: existing))
    }

    func testSinglePassExpansionDoesNotReExpandClipboardTokens() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let tz = TimeZone(secondsFromGMT: 0)!
        let out = TextSnippetRules.expand(
            "Date={date} Time={time} Both={datetime} Clip={clipboard}",
            now: fixedDate,
            clipboardText: "literal {date} token",
            timeZone: tz
        )
        XCTAssertEqual(out, "Date=2023-11-14 Time=22:13 Both=2023-11-14 22:13 Clip=literal {date} token")
    }

    func testMatchPrefersLongestEnabledTrigger() {
        let snippets = [
            TextSnippet(trigger: ";d", expansion: "short", isEnabled: true),
            TextSnippet(trigger: ";date", expansion: "long", isEnabled: true),
            TextSnippet(trigger: ";datex", expansion: "disabled", isEnabled: false),
        ]
        XCTAssertEqual(TextSnippetRules.match(buffer: "hello ;date", snippets: snippets)?.expansion, "long")
        XCTAssertNil(TextSnippetRules.match(buffer: "hello ;datex", snippets: snippets))
    }

    func testSearchRanksExactTriggerFirstAndIgnoresDisabled() {
        let snippets = [
            TextSnippet(trigger: ";sig", expansion: "Best regards", isEnabled: true),
            TextSnippet(trigger: ";signature", expansion: "Full signature", isEnabled: true),
            TextSnippet(trigger: ";off", expansion: "sig disabled", isEnabled: false),
        ]
        let found = TextSnippetRules.search(query: ";sig", snippets: snippets)
        XCTAssertEqual(found.map(\.trigger), [";sig", ";signature"])
    }

    func testTypingBufferCapsLengthSupportsBackspaceAndResetsOnModifiersOrNav() {
        var buf = TextSnippetRules.TypingBuffer()
        buf.append("abc")
        buf.backspace()
        XCTAssertEqual(buf.text, "ab")
        buf.append(String(repeating: "x", count: 60))
        XCTAssertEqual(buf.text.count, TextSnippetRules.maxBufferLength)
        buf.clear()
        XCTAssertEqual(buf.text, "")

        XCTAssertTrue(TextSnippetRules.shouldResetBuffer(keyCode: 0, flags: 1 << 20))
        XCTAssertTrue(TextSnippetRules.shouldResetBuffer(keyCode: 36, flags: 0))
        XCTAssertTrue(TextSnippetRules.shouldResetBuffer(keyCode: 123, flags: 0))
        XCTAssertFalse(TextSnippetRules.shouldResetBuffer(keyCode: 0, flags: 0))

        let snippets = [TextSnippet(trigger: ";sig", expansion: "Thanks!")]
        buf.append("hello ;si")
        XCTAssertNil(TextSnippetRules.match(buffer: buf.text, snippets: snippets))
        buf.append("g")
        XCTAssertEqual(TextSnippetRules.match(buffer: buf.text, snippets: snippets)?.expansion, "Thanks!")
    }
}
