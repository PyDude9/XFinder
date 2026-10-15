import XCTest

/// Locks down `GestureShortcut.label`: a shortcut must name its key, not print the raw
/// key code. The shipped bug was `⌘Key 18` for "Vừa khung" and `⇧⌘Key 20` for "Chụp màn hình"
/// — the table only held a handful of codes, so every letter and digit fell through to the
/// `"Key \(key)"` fallback (T16).
final class GestureShortcutLabelTests: XCTestCase {

    func testLetterAndDigitKeysUseTheirName() {
        XCTAssertEqual(GestureShortcut(key: 18, flags: GestureShortcut.command).label, "⌘1")
        XCTAssertEqual(GestureShortcut(key: 20, flags: GestureShortcut.command | GestureShortcut.shift).label, "⇧⌘3")
        XCTAssertEqual(GestureShortcut(key: 1, flags: 0).label, "S")
        XCTAssertEqual(GestureShortcut(key: 2, flags: 0).label, "D")
        XCTAssertEqual(GestureShortcut(key: 45, flags: 0).label, "N")
        XCTAssertEqual(GestureShortcut(key: 51, flags: 0).label, "⌫")
        XCTAssertEqual(GestureShortcut(key: 53, flags: 0).label, "⎋")
    }

    /// Every ANSI key code the shortcut recorder can carry must render as a name, never as the
    /// raw `"Key <code>"` fallback.
    func testEveryCarriedKeyCodeHasAName() {
        let named: [UInt16] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
                               11, 12, 13, 14, 15, 16, 17,
                               18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
                               30, 31, 32, 33, 34, 35,
                               36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
                               48, 49, 50, 51, 53,
                               116, 121, 123, 124, 125, 126]
        for key in named {
            let label = GestureShortcut(key: key, flags: 0).label
            XCTAssertFalse(label.isEmpty, "key code \(key) has no label")
            XCTAssertFalse(label.contains("Key "), "key code \(key) still shows the raw code: \(label)")
        }
    }

    /// The fallback must stay honest for a code with no name yet (10 and 52 are real ANSI codes
    /// this pass deliberately left out) — a blank label would be worse than `Key 10`.
    func testUnnamedKeyStillFallsBack() {
        XCTAssertEqual(GestureShortcut(key: 10, flags: 0).label, "Key 10")
        XCTAssertEqual(GestureShortcut(key: 52, flags: 0).label, "Key 52")
    }
}
