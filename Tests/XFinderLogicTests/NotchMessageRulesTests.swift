import Foundation
import XCTest

@MainActor
final class NotchMessageRulesTests: XCTestCase {

    func testEmptyAndWhitespaceOnlyTextBlocked() {
        let model = NotchMessageModel()
        var shown: [NotchMessageRules.NoticePayload] = []
        model.onShowNotice = { shown.append($0) }

        model.draft = ""
        XCTAssertEqual(model.showBlockReason, .emptyText)
        XCTAssertNil(model.showInIsland())

        model.draft = "   \n\t\r\n  "
        XCTAssertEqual(model.showBlockReason, .emptyText)
        XCTAssertNil(model.showInIsland())

        XCTAssertTrue(shown.isEmpty)
        XCTAssertFalse(model.isShowing)
    }

    func testMultilineAndControlCharsNormalizedToSingleLine() {
        let raw = "  Line one\r\nLine\ttwo\u{0007}\n\nLine three  "
        let normalized = NotchMessageRules.normalizeText(raw)
        XCTAssertEqual(normalized, "Line one Line two Line three")
    }

    func testUnicodePreservedAndGraphemeLengthLimitEnforced() {
        let vietnameseAndEmoji = "Xin chào 🚀👨‍👩‍👧‍👦 Tiếng Việt 123"
        XCTAssertEqual(NotchMessageRules.normalizeText(vietnameseAndEmoji), vietnameseAndEmoji)

        let exactLimit = String(repeating: "ệ", count: NotchMessageRules.maxCharacters)
        XCTAssertNil(
            NotchMessageRules.showBlockReason(
                draft: exactLimit,
                duration: NotchMessageRules.defaultDurationSeconds
            )
        )

        let overLimit = exactLimit + "😀"
        XCTAssertEqual(
            NotchMessageRules.showBlockReason(
                draft: overLimit,
                duration: NotchMessageRules.defaultDurationSeconds
            ),
            .tooLong(count: NotchMessageRules.maxCharacters + 1, limit: NotchMessageRules.maxCharacters)
        )
    }

    func testInvalidDurationsRejectedAndClampedSafely() {
        let invalid: [TimeInterval] = [0, -5, 1.5, 61, .nan, .infinity, -.infinity]
        for value in invalid {
            XCTAssertFalse(NotchMessageRules.isValidDuration(value), "Expected \(value) to be invalid")
            XCTAssertEqual(
                NotchMessageRules.showBlockReason(draft: "Hello", duration: value),
                .invalidDuration
            )
            XCTAssertNil(NotchMessageRules.makePayload(draft: "Hello", duration: value, reduceMotion: false))
            let clamped = NotchMessageRules.clampedDuration(value)
            XCTAssertTrue(NotchMessageRules.isValidDuration(clamped))
        }

        let model = NotchMessageModel()
        model.draft = "Valid text"
        model.durationSeconds = -10
        XCTAssertEqual(model.showBlockReason, .invalidDuration)
        XCTAssertNil(model.showInIsland())
    }

    func testConsecutiveSendsDismissPreviousByIDAndIgnoreStaleDismissal() {
        let id1 = UUID()
        let id2 = UUID()
        var nextIDs = [id1, id2]

        let model = NotchMessageModel(idProvider: { nextIDs.removeFirst() })
        var events: [String] = []
        model.onShowNotice = { events.append("show:\($0.id.uuidString):\($0.text)") }
        model.onDismissNotice = { events.append("dismiss:\($0.uuidString)") }

        model.draft = "First"
        let p1 = model.showInIsland(reduceMotion: false)
        XCTAssertEqual(p1?.id, id1)
        XCTAssertEqual(model.activeNotice?.id, id1)

        model.draft = "Second"
        let p2 = model.showInIsland(reduceMotion: false)
        XCTAssertEqual(p2?.id, id2)
        XCTAssertEqual(model.activeNotice?.id, id2)

        XCTAssertEqual(events, [
            "show:\(id1.uuidString):First",
            "dismiss:\(id1.uuidString)",
            "show:\(id2.uuidString):Second",
        ])

        // Stale dismissal for id1 must NOT clear id2
        model.notifyDismissed(id: id1)
        XCTAssertEqual(model.activeNotice?.id, id2)

        // Matching dismissal for id2 clears activeNotice
        model.notifyDismissed(id: id2)
        XCTAssertNil(model.activeNotice)
    }

    func testStopTabDisableAndShutdownCancelByID() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        var nextIDs = [id1, id2, id3]

        let model = NotchMessageModel(idProvider: { nextIDs.removeFirst() })
        var dismissed: [UUID] = []
        model.onDismissNotice = { dismissed.append($0) }

        // Stop button
        model.draft = "Notice 1"
        _ = model.showInIsland()
        model.stopActiveNotice()
        model.stopActiveNotice() // idempotent
        XCTAssertEqual(dismissed, [id1])
        XCTAssertNil(model.activeNotice)

        // Tab disabled
        model.draft = "Notice 2"
        model.isInputFocused = true
        _ = model.showInIsland()
        model.handleTabDisabled()
        XCTAssertEqual(dismissed, [id1, id2])
        XCTAssertNil(model.activeNotice)
        XCTAssertFalse(model.isInputFocused)

        // App shutdown (ephemeral: clears draft too)
        model.draft = "Notice 3"
        _ = model.showInIsland()
        model.shutdown()
        XCTAssertEqual(dismissed, [id1, id2, id3])
        XCTAssertNil(model.activeNotice)
        XCTAssertEqual(model.draft, "")
    }

    func testReduceMotionUsesStaticPresentationAndPropagatesInPayload() {
        XCTAssertEqual(NotchMessageRules.presentationMode(reduceMotion: true), .staticOnly)
        XCTAssertEqual(NotchMessageRules.presentationMode(reduceMotion: false), .animated)

        let model = NotchMessageModel()
        var captured: NotchMessageRules.NoticePayload?
        model.onShowNotice = { captured = $0 }

        model.draft = "Static notice"
        let payload = model.showInIsland(reduceMotion: true)
        XCTAssertEqual(payload?.reduceMotion, true)
        XCTAssertEqual(captured?.reduceMotion, true)
    }
}
