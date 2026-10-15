import XCTest

/// The Mouse & Gestures status line (T14a). The page is SwiftUI, so the choice of sentence lives in
/// `GesturePageStatus` (GestureLabelStructure.swift, symlinked) and is held here.
final class GesturePageStatusTests: XCTestCase {

    private func status(recording: Bool = false, shortcut: Bool = false, enabled: Bool = true,
                        tap: Bool = true, failure: String = "") -> GesturePageStatus {
        .of(recording: recording, recordingShortcut: shortcut, enabled: enabled, tapActive: tap, tapFailure: failure)
    }

    /// The T14a review's finding: one `recording` Bool serves both modes, and the first version told the
    /// user to press a MOUSE button while a KEYBOARD shortcut was being recorded.
    func testRecordingAShortcutDoesNotAskForAMouseButton() {
        XCTAssertEqual(status(recording: true, shortcut: true), .recordingShortcut)
        XCTAssertEqual(status(recording: true, shortcut: false), .recordingButton)
        XCTAssertNotEqual(GesturePageStatus.recordingShortcut.textKey, GesturePageStatus.recordingButton.textKey)
        XCTAssertFalse(GesturePageStatus.recordingShortcut.textKey.contains("chuột"),
                       "the shortcut sentence must not send the user to the mouse")
        XCTAssertTrue(GesturePageStatus.recordingButton.textKey.contains("chuột"))
    }

    /// Recording is what the user is doing right now, so it outranks every other state.
    func testRecordingOutranksOffAndAFailedTap() {
        XCTAssertEqual(status(recording: true, enabled: false), .recordingButton)
        XCTAssertEqual(status(recording: true, shortcut: true, tap: false, failure: "x"), .recordingShortcut)
        XCTAssertTrue(status(recording: true).isRecording)
        XCTAssertFalse(status().isRecording)
    }

    func testTheFourIdleStates() {
        XCTAssertEqual(status(enabled: false), .off)
        XCTAssertEqual(status(enabled: false, tap: false, failure: "x"), .off, "off says off, not an error")
        XCTAssertEqual(status(), .ready)
        XCTAssertEqual(status(tap: false, failure: "Lỗi cụ thể"), .tapFailure("Lỗi cụ thể"))
        XCTAssertEqual(GesturePageStatus.tapFailure("Lỗi cụ thể").textKey, "Lỗi cụ thể",
                       "a named failure carries the controller's own key")
        XCTAssertEqual(status(tap: false), .needsAccessibility)
    }

    /// The sentences reach the screen through `L10n.t(status.textKey)` — a variable, which no literal
    /// sweep can see — so every fixed key is resolved against the shipped store here.
    func testEveryFixedSentenceIsInTheStore() throws {
        let store = try L10nFixture.load()
        let keys = [GesturePageStatus.recordingShortcut, .recordingButton, .off, .ready, .needsAccessibility].map(\.textKey)
        XCTAssertEqual(Set(keys).count, 5, "the vocabulary walk collapsed")
        for key in keys {
            let en = store.entries[key]?.en ?? ""
            XCTAssertFalse(en.isEmpty, key)
            XCTAssertNotEqual(en, key, key)
        }
    }
}

/// The "app in front" dot on the Mouse & Gestures app strip (T14b review).
final class GestureAppChooserTests: XCTestCase {
    private let ids = ["*", "com.apple.Safari", "com.microsoft.VSCode", "my.custom.app"]
    private func dot(_ front: String, selected: String = "com.apple.Safari") -> String? {
        GestureAppChooser.dottedChip(front: front, chipIDs: ids, selected: selected, fallback: "*")
    }

    /// The defect: an app without a chip of its own is governed by Global, and T14b dotted nothing.
    func testAnAppWithoutItsOwnChipDotsGlobal() {
        XCTAssertEqual(dot("com.tinyspeck.slackmacgap"), "*")
    }

    func testAnAppWithItsOwnChipDotsThatChip() {
        XCTAssertEqual(dot("com.microsoft.VSCode"), "com.microsoft.VSCode")
        XCTAssertEqual(dot("my.custom.app"), "my.custom.app", "a custom bundle id is a chip too")
    }

    func testNoDotWhenNothingIsInFrontOrTheChipIsAlreadySelected() {
        XCTAssertNil(dot(""), "nothing in front: we cannot name an app")
        XCTAssertNil(dot("com.apple.Safari"), "the selection frame already marks it")
        XCTAssertNil(dot("com.tinyspeck.slackmacgap", selected: "*"), "Global selected and governing")
    }
}
