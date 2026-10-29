import XCTest
import Foundation

/// N5a — what ⇧⌘G does with what Accessibility returned, and that every panel line is in the store.
final class TranslateSelectionRulesTests: XCTestCase {
    typealias R = TranslateSelectionRules

    func testNativeDismissalClosesOnlyCurrentUnfinishedSession() {
        XCTAssertTrue(R.shouldDismissHost(endedRequest: 2, currentRequest: 2, hasTranslation: false, isActive: true))
        XCTAssertFalse(R.shouldDismissHost(endedRequest: 1, currentRequest: 2, hasTranslation: false, isActive: true), "An old popover must not close a newer selection")
        XCTAssertTrue(R.shouldDismissHost(endedRequest: 2, currentRequest: 2, hasTranslation: true, isActive: true), "Native close dismisses host even after Replace to avoid leaving a stranded overlay")
        XCTAssertFalse(R.shouldDismissHost(endedRequest: 2, currentRequest: 2, hasTranslation: false, isActive: false), "Explicit dismissal must stay idempotent")
    }

    func testVerdicts() {
        XCTAssertEqual(R.verdict(for: nil), .nothingSelected)
        XCTAssertEqual(R.verdict(for: "   "), .nothingSelected)
        XCTAssertEqual(R.verdict(for: "a"), .tooShort, "a single character is the caret's own artifact")
        XCTAssertEqual(R.verdict(for: "  xin chào  "), .translate("xin chào"))
        XCTAssertEqual(R.verdict(for: String(repeating: "x", count: R.maxCharacters)), .translate(String(repeating: "x", count: R.maxCharacters)))
        XCTAssertEqual(R.verdict(for: String(repeating: "x", count: R.maxCharacters + 1)), .tooLong)
    }

    func testEveryMessageKeyIsInTheStoreAndTranslateHasNone() throws {
        let store = try L10nFixture.load()
        XCTAssertNil(R.messageKey(for: .translate("x")))
        for v in [R.Verdict.tooShort, .tooLong, .nothingSelected] {
            let k = try XCTUnwrap(R.messageKey(for: v))
            XCTAssertNotNil(store.entries[k], k)
        }
        XCTAssertEqual(R.keyCodeG, 5); XCTAssertEqual(R.hotkeyLabel, "⇧⌘G")
    }
}
