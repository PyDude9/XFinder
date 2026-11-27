import Foundation
import XCTest

@MainActor
final class NotchFeedbackRulesTests: XCTestCase {

    func testEmptyAndWhitespaceDraftBlockedFromCopy() {
        let model = NotchFeedbackModel()
        var copiedTexts: [String] = []
        model.onCopyText = { text in
            copiedTexts.append(text)
            return true
        }

        model.updateDraft("")
        XCTAssertEqual(model.copyBlockReason, .emptyText)
        XCTAssertFalse(model.copyPreview(categoryLabel: "Bug"))

        model.updateDraft("   \n\t\r\n  ")
        XCTAssertEqual(model.copyBlockReason, .emptyText)
        XCTAssertFalse(model.copyPreview(categoryLabel: "Bug"))

        XCTAssertTrue(copiedTexts.isEmpty)
        XCTAssertEqual(model.status, .idle)
    }

    func testCharacterLengthLimitPreservesDraftForTrimming() {
        let model = NotchFeedbackModel(maxCharacters: 10)
        var copyCount = 0
        model.onCopyText = { _ in
            copyCount += 1
            return true
        }

        let exact = String(repeating: "ế", count: 10)
        model.updateDraft(exact)
        XCTAssertNil(model.copyBlockReason)
        XCTAssertTrue(model.copyPreview(categoryLabel: "Bug"))
        XCTAssertEqual(copyCount, 1)

        let over = exact + "🚀"
        model.updateDraft(over)
        XCTAssertEqual(model.copyBlockReason, .tooLong(count: 11, limit: 10))
        XCTAssertFalse(model.copyPreview(categoryLabel: "Bug"))
        XCTAssertEqual(copyCount, 1)
        XCTAssertEqual(model.draft, over)
    }

    func testCategorySwitchUpdatesPreviewPreservesDraftAndClearsStaleCopiedStatus() {
        let model = NotchFeedbackModel()
        model.onCopyText = { _ in true }

        model.updateDraft("Line 1\r\nLine 2 👨‍👩‍👧‍👦")
        XCTAssertTrue(model.copyPreview(categoryLabel: "Bug"))
        XCTAssertEqual(model.status, .copied)

        model.selectCategory(.suggestion)
        XCTAssertEqual(model.category, .suggestion)
        XCTAssertEqual(model.draft, "Line 1\r\nLine 2 👨‍👩‍👧‍👦")
        XCTAssertEqual(model.status, .idle)

        let preview = model.formattedPreview(categoryLabel: "Suggestion")
        XCTAssertEqual(preview, "[Suggestion]\nLine 1\nLine 2 👨‍👩‍👧‍👦")

        model.selectCategory(.other)
        XCTAssertEqual(model.category, .other)
        XCTAssertEqual(model.formattedPreview(categoryLabel: "Other"), "[Other]\nLine 1\nLine 2 👨‍👩‍👧‍👦")
    }

    func testIssuesURLIsStrictlyDestinationOnlyAndNeverIncludesDraft() {
        let model = NotchFeedbackModel()
        model.updateDraft("Secret user draft that must never appear in URL")

        var openedURLs: [URL] = []
        model.onOpenIssuesPage = { url in
            openedURLs.append(url)
            return true
        }

        XCTAssertTrue(model.openIssuesPage())
        XCTAssertEqual(openedURLs.count, 1)
        let url = openedURLs[0]
        XCTAssertEqual(url.absoluteString, "https://github.com/PyDude9/XFinder/issues/new")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
        XCTAssertEqual(model.status, .openedIssues)
        // Draft stays intact so the user can still copy it.
        XCTAssertEqual(model.draft, "Secret user draft that must never appear in URL")
    }

    func testCopyAndBrowserOpenFailuresReportErrorAndPreserveDraft() {
        let model = NotchFeedbackModel()
        model.updateDraft("Crash when opening tray")

        // Browser open fails -> error shown, draft kept intact
        model.onOpenIssuesPage = { _ in false }
        XCTAssertFalse(model.openIssuesPage())
        XCTAssertEqual(model.status, .openBrowserFailed)
        XCTAssertEqual(model.draft, "Crash when opening tray")

        // Copy fails -> error shown, draft kept intact
        model.onCopyText = { _ in false }
        XCTAssertFalse(model.copyPreview(categoryLabel: "Bug"))
        XCTAssertEqual(model.status, .copyFailed)
        XCTAssertEqual(model.draft, "Crash when opening tray")

        // Copy succeeds after retry
        var copied: String?
        model.onCopyText = { text in
            copied = text
            return true
        }
        XCTAssertTrue(model.copyPreview(categoryLabel: "Bug"))
        XCTAssertEqual(model.status, .copied)
        XCTAssertEqual(copied, "[Bug]\nCrash when opening tray")
    }

    func testDiagnosticsCallbackSuccessAndFailurePreserveDraft() {
        let model = NotchFeedbackModel()
        model.updateDraft("Keeping my draft")

        var calls = 0
        model.onOpenDiagnostics = {
            calls += 1
            return false
        }
        XCTAssertFalse(model.openDiagnostics())
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.status, .openDiagnosticsFailed)
        XCTAssertEqual(model.draft, "Keeping my draft")

        model.onOpenDiagnostics = {
            calls += 1
            return true
        }
        XCTAssertTrue(model.openDiagnostics())
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.status, .openedDiagnostics)
        XCTAssertEqual(model.draft, "Keeping my draft")
    }

    func testTabDisablePreservesDraftWhileTypingAndShutdownClearsEphemeralState() {
        let model = NotchFeedbackModel()
        model.selectCategory(.suggestion)
        model.updateDraft("Half-written feedback")
        model.isInputFocused = true
        XCTAssertTrue(model.isComposing)

        // Switching / disabling tab while typing drops focus without losing in-memory draft.
        model.handleTabDisabled()
        XCTAssertFalse(model.isInputFocused)
        XCTAssertEqual(model.draft, "Half-written feedback")
        XCTAssertEqual(model.category, .suggestion)

        // App shutdown clears ephemeral draft.
        model.shutdown()
        XCTAssertEqual(model.draft, "")
        XCTAssertFalse(model.isInputFocused)
        XCTAssertEqual(model.status, .idle)
    }
}
