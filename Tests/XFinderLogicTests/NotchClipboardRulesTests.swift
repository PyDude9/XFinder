import XCTest
import Foundation

/// D0: the ⌘⇧V shelf's decisions, now pure rules of the notch's clipboard page.
final class NotchClipboardRulesTests: XCTestCase {
    typealias R = NotchClipboardRules

    func rec(_ type: ContentType, pinned: Bool = false, saved: Bool = false, id: UUID = UUID()) -> ClipboardRecord {
        var meta: [String: String] = [:]
        if pinned { meta["isPinned"] = "true" }
        if saved { meta["isSaved"] = "true" }
        return ClipboardRecord(id: id, type: type, timestamp: Date(), sourceBundleID: nil, sourceAppName: nil,
                               textSnippet: "x", thumbnailPath: nil, payloadPath: nil, ocrText: nil, pinboardID: nil, metadata: meta)
    }

    // MARK: ⌘⇧V surface

    func testHotkeySurfaceDefaultsToTheNotchAndIgnoresGarbage() {
        XCTAssertEqual(R.hotkeySurface(parsing: nil), .notch)
        XCTAssertEqual(R.hotkeySurface(parsing: "shelf"), .shelf)
        XCTAssertEqual(R.hotkeySurface(parsing: "Shelf"), .notch, "rawValue is exact; a hand-edited default falls back")
        XCTAssertEqual(R.hotkeySurface(parsing: ""), .notch)
    }

    func testANotchPreferenceFallsBackToTheShelfWhileTheNotchSurfaceIsOff() {
        XCTAssertEqual(R.surfaceToOpen(preferred: .notch, notchSurfaceEnabled: true), .notch)
        XCTAssertEqual(R.surfaceToOpen(preferred: .notch, notchSurfaceEnabled: false), .shelf, "⌘⇧V must open SOMETHING")
        XCTAssertEqual(R.surfaceToOpen(preferred: .shelf, notchSurfaceEnabled: true), .shelf)
    }

    // MARK: ⌘1–9

    func testDigitRowKeyCodesMapToSlotsLikeTheShelfAlwaysDid() {
        XCTAssertEqual(R.slot(forKeyCode: 18), 0)   // 1
        XCTAssertEqual(R.slot(forKeyCode: 25), 8)   // 9
        XCTAssertEqual(R.slot(forKeyCode: 23), 4)   // 5 — not in numeric order
        XCTAssertNil(R.slot(forKeyCode: 9), "V is not a digit")
    }

    func testSlotsAreHistoryPinnedSavedThenBoardsInOrderAndNothingPastTheLast() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(R.scope(forSlot: 0, boardIDs: [a, b]), .history)
        XCTAssertEqual(R.scope(forSlot: 1, boardIDs: [a, b]), .pinned)
        XCTAssertEqual(R.scope(forSlot: 2, boardIDs: [a, b]), .saved)
        XCTAssertEqual(R.scope(forSlot: 3, boardIDs: [a, b]), .board(a))
        XCTAssertEqual(R.scope(forSlot: 4, boardIDs: [a, b]), .board(b))
        XCTAssertNil(R.scope(forSlot: 5, boardIDs: [a, b]), "⌘6 with two boards means nothing")
        XCTAssertNil(R.scope(forSlot: 3, boardIDs: []))
    }

    // MARK: Grid keyboard

    func testArrowsWalkReadingOrderStopAtTheEndsAndRowsStayPutAtTheEdge() {
        // 7 cards in 3 columns:  0 1 2 / 3 4 5 / 6
        XCTAssertEqual(R.move(.right, from: nil, count: 7, columns: 3), 0, "no selection ⇒ the first card")
        XCTAssertEqual(R.move(.left, from: 99, count: 7, columns: 3), 0, "a stale index ⇒ the first card")
        XCTAssertEqual(R.move(.right, from: 2, count: 7, columns: 3), 3, "reading order crosses rows")
        XCTAssertEqual(R.move(.right, from: 6, count: 7, columns: 3), 6, "no wrap at the end")
        XCTAssertEqual(R.move(.left, from: 0, count: 7, columns: 3), 0, "no wrap at the start")
        XCTAssertEqual(R.move(.down, from: 1, count: 7, columns: 3), 4)
        XCTAssertEqual(R.move(.down, from: 4, count: 7, columns: 3), 4, "no card below ⇒ stay")
        XCTAssertEqual(R.move(.down, from: 3, count: 7, columns: 3), 6)
        XCTAssertEqual(R.move(.up, from: 6, count: 7, columns: 3), 3)
        XCTAssertEqual(R.move(.up, from: 1, count: 7, columns: 3), 1, "top row ⇒ stay")
        XCTAssertNil(R.move(.right, from: 0, count: 0, columns: 3), "empty deck ⇒ nothing to select")
        XCTAssertEqual(R.move(.down, from: 0, count: 2, columns: 0), 1, "a zero column count is treated as one")
    }

    func testSelectionAfterDeleteSlidesToTheNeighbourOrTheNewLast() {
        XCTAssertEqual(R.selectionAfterDeleting(index: 2, newCount: 5), 2)
        XCTAssertEqual(R.selectionAfterDeleting(index: 4, newCount: 4), 3, "deleted the last ⇒ the new last")
        XCTAssertNil(R.selectionAfterDeleting(index: 0, newCount: 0))
    }

    // MARK: Scope filter and chip counts

    func testScopesFilterByFlagOrBoardMembership() {
        let p = rec(.text, pinned: true), s = rec(.code, saved: true), plain = rec(.link)
        let all = [p, s, plain]
        XCTAssertEqual(R.apply(scope: .history, boardItemIDs: nil, to: all).count, 3)
        XCTAssertEqual(R.apply(scope: .suggestions, boardItemIDs: nil, to: all).count, 3, "suggestions are ranked elsewhere, not filtered here")
        XCTAssertEqual(R.apply(scope: .pinned, boardItemIDs: nil, to: all).map(\.id), [p.id])
        XCTAssertEqual(R.apply(scope: .saved, boardItemIDs: nil, to: all).map(\.id), [s.id])
        XCTAssertEqual(R.apply(scope: .board(UUID()), boardItemIDs: [plain.id], to: all).map(\.id), [plain.id])
        XCTAssertEqual(R.apply(scope: .board(UUID()), boardItemIDs: nil, to: all), [], "an unknown board shows nothing, not everything")
    }

    func testChipsCountTheLoadedHistoryAndSkipEmptyTypes() {
        let counts = R.typeCounts([.text, .text, .image, .link, .text])
        XCTAssertEqual(counts[.text], 3); XCTAssertEqual(counts[.image], 1); XCTAssertNil(counts[.color])
        let chips = R.chips(from: counts)
        XCTAssertEqual(chips.map(\.type), [.image, .link, .text], "fixed order, nothing for types with no record")
        XCTAssertEqual(chips.map(\.count), [1, 1, 3])
        XCTAssertTrue(R.chips(from: [:]).isEmpty)
    }

    // MARK: Footer

    func testFooterPrecedenceIsStackThenNoticeThenMissingAccessibilityThenHints() {
        XCTAssertEqual(R.footer(pasteStackActive: true, remaining: 2, interceptsCommandV: true, notice: "n", autoPaste: true, accessibilityTrusted: false),
                       .pasteStack(remaining: 2, interceptsCommandV: true))
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: "Đã sao chép", autoPaste: true, accessibilityTrusted: false),
                       .notice("Đã sao chép"))
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: "", autoPaste: true, accessibilityTrusted: false),
                       .accessibilityMissing, "an empty notice is no notice")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, autoPaste: false, accessibilityTrusted: false),
                       .hints, "auto-paste off ⇒ Return copies by design, nothing to warn about")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, autoPaste: true, accessibilityTrusted: true), .hints)
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, paused: true, autoPaste: true, accessibilityTrusted: false),
                       .paused, "paused outranks the Accessibility warning — nothing is being recorded at all")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: "n", paused: true, autoPaste: true, accessibilityTrusted: true),
                       .notice("n"), "but a fresh action's result still shows first")
    }

    func testProLimitNoticeIsLowestPriorityAmbientStatus() {
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, autoPaste: false,
                                accessibilityTrusted: true, hiddenByProLimit: 10), .proLimit(hidden: 10),
                       "nothing more urgent to show ⇒ the Free-limit notice takes the hint slot")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, autoPaste: false,
                                accessibilityTrusted: true, hiddenByProLimit: 0), .hints, "nothing hidden ⇒ ordinary hints")
        XCTAssertEqual(R.footer(pasteStackActive: true, remaining: 2, interceptsCommandV: true, notice: nil, autoPaste: false,
                                accessibilityTrusted: true, hiddenByProLimit: 10), .pasteStack(remaining: 2, interceptsCommandV: true),
                       "an active Paste Stack still outranks it")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: "n", autoPaste: false,
                                accessibilityTrusted: true, hiddenByProLimit: 10), .notice("n"), "a fresh notice still outranks it")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, paused: true, autoPaste: false,
                                accessibilityTrusted: true, hiddenByProLimit: 10), .paused, "paused still outranks it")
        XCTAssertEqual(R.footer(pasteStackActive: false, remaining: 0, interceptsCommandV: false, notice: nil, autoPaste: true,
                                accessibilityTrusted: false, hiddenByProLimit: 10), .accessibilityMissing, "the Accessibility warning still outranks it")
    }

    // MARK: Image tiles

    func testImagesFillTheTileOnlyWhenTheirShapeIsCloseToIt() {
        let tile = 174.0 / 100.0                                   // the deck card's picture area
        XCTAssertEqual(R.imageScaling(imageAspect: 2722.0 / 1562.0, tileAspect: tile), .fill, "a screen-shaped shot fills")
        XCTAssertEqual(R.imageScaling(imageAspect: 16.0 / 9.0, tileAspect: tile), .fill)
        XCTAssertEqual(R.imageScaling(imageAspect: 1280.0 / 460.0, tileAspect: tile), .fit, "the reported 2.8:1 settings shot is fitted, not zoomed")
        XCTAssertEqual(R.imageScaling(imageAspect: 1, tileAspect: tile), .fit, "a square is 1.74× off ⇒ fitted")
        XCTAssertEqual(R.imageScaling(imageAspect: 0.5, tileAspect: tile), .fit, "portrait")
        XCTAssertEqual(R.imageScaling(imageAspect: tile * 1.49, tileAspect: tile), .fill, "just inside the tolerance")
        XCTAssertEqual(R.imageScaling(imageAspect: 0, tileAspect: tile), .fit, "no size known ⇒ never crop")
    }

    // MARK: Card footer facts

    func testAgeBuckets() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        XCTAssertEqual(R.age(of: now - 30, now: now), .justNow)
        XCTAssertEqual(R.age(of: now - 60, now: now), .minutes(1))
        XCTAssertEqual(R.age(of: now - 59 * 60, now: now), .minutes(59))
        XCTAssertEqual(R.age(of: now - 3600, now: now), .hours(1))
        XCTAssertEqual(R.age(of: now - 86_399, now: now), .hours(23))
        XCTAssertEqual(R.age(of: now - 86_400, now: now), .days(1))
        XCTAssertEqual(R.age(of: now - 7 * 86_400, now: now), .older(now - 7 * 86_400))
    }

    func testMetaIsOneFactPerTypeAndNothingForLinksAndColours() {
        XCTAssertEqual(R.meta(type: .image, dimensions: "2552×1462", path: nil, text: nil), .dimensions("2552×1462"))
        XCTAssertNil(R.meta(type: .image, dimensions: nil, path: nil, text: "Image"), "no dimensions ⇒ no invented size")
        XCTAssertEqual(R.meta(type: .file, dimensions: nil, path: "/Users/x/Báo cáo quý 3.pdf", text: nil), .fileExtension("PDF"))
        XCTAssertEqual(R.meta(type: .file, dimensions: nil, path: nil, text: "notes.md"), .fileExtension("MD"), "falls back to the snippet (the file name)")
        XCTAssertNil(R.meta(type: .file, dimensions: nil, path: "/tmp/Makefile", text: nil))
        XCTAssertEqual(R.meta(type: .code, dimensions: nil, path: nil, text: "a\nb\nc"), .lines(3))
        XCTAssertEqual(R.meta(type: .markdown, dimensions: nil, path: nil, text: "# T\n\n- x"), .lines(3), "blank lines count")
        XCTAssertEqual(R.meta(type: .text, dimensions: nil, path: nil, text: "một  hai\nba"), .words(3))
        XCTAssertNil(R.meta(type: .text, dimensions: nil, path: nil, text: "   "))
        XCTAssertNil(R.meta(type: .link, dimensions: nil, path: nil, text: "https://x.y"))
        XCTAssertNil(R.meta(type: .color, dimensions: nil, path: nil, text: "#1F4E79"))
    }

    /// A card passing under the finger taps; the deck appearing, the same card, or a list replaced by a filter does not.
    func testTheDeckTapsOnlyWhenOneVisibleCardGivesWayToAnother() {
        let ids = [1, 2, 3, 4]
        XCTAssertTrue(R.cardChanged(from: 1, to: 2, in: ids))
        XCTAssertTrue(R.cardChanged(from: 3, to: 1, in: ids), "scrolling back taps too")
        XCTAssertFalse(R.cardChanged(from: nil, to: 1, in: ids), "the deck appearing is not a swipe")
        XCTAssertFalse(R.cardChanged(from: 2, to: nil, in: ids))
        XCTAssertFalse(R.cardChanged(from: 2, to: 2, in: ids))
        XCTAssertFalse(R.cardChanged(from: 9, to: 1, in: ids), "a filter replaced the list: the old card is gone")
        XCTAssertFalse(R.cardChanged(from: 1, to: 9, in: ids))
    }

    func testSearchPlacementStaysInHeaderOnPlainScreensAndMovesToContentRowOnConstrainedNotches() {
        XCTAssertEqual(
            R.searchPlacement(onPhysicalNotch: false, isWide: true, bodyWidth: 612, notchWidth: 0),
            .header(maxWidth: 280)
        )
        XCTAssertEqual(
            R.searchPlacement(onPhysicalNotch: false, isWide: false, bodyWidth: 382, notchWidth: 0),
            .header(maxWidth: 165)
        )

        for notchW in [185.0, 206.0, 240.0, 280.0] {
            let placement = R.searchPlacement(onPhysicalNotch: true, isWide: true, bodyWidth: 612, notchWidth: notchW)
            XCTAssertTrue(placement.isContentRow, "notch \(notchW) leaves < \(R.minHeaderSearchWidth)pt beside title and moves search to contentRow")
            if case let .contentRow(_, activeMin, activeMax) = placement {
                XCTAssertGreaterThanOrEqual(activeMin, 240)
                XCTAssertGreaterThanOrEqual(activeMax, 380)
            }
        }

        XCTAssertEqual(
            R.searchPlacement(onPhysicalNotch: true, isWide: true, bodyWidth: 612, notchWidth: 120),
            .header(maxWidth: 162)
        )
    }
}
