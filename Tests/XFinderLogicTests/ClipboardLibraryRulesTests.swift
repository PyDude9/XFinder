import XCTest
import Foundation

/// Pins the pure rules of the Thư viện Clipboard sidebar page (D3) — facets, scope/token/period
/// filtering, sort orders, pagination, scope titles and grid movement. No AppKit, no SQLite: fixtures
/// are built directly with `ClipboardRecord(...)` the same way `MCPProtocolTests`/`ClipExportTests` do.
final class ClipboardLibraryRulesTests: XCTestCase {
    typealias X = ClipboardLibrary

    // Fixed "now" so period-boundary tests do not depend on when the suite runs.
    // 2026-10-12 14:30:00 UTC — deliberately NOT midnight-aligned: a "week" implemented as a rolling
    // 7×24h window and one implemented as "since the start of the day 7 calendar days ago" disagree
    // whenever `now` has a nonzero time-of-day, which is exactly the case a midnight `now` would hide.
    let now = Date(timeIntervalSince1970: 1_791_815_400)

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    func makeColor() -> CodableColor { CodableColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1) }

    func board(name: String, id: UUID = UUID(), itemIDs: [UUID] = [], isBuiltIn: Bool = false) -> Pinboard {
        Pinboard(id: id, name: name, color: makeColor(), itemIDs: itemIDs, isBuiltIn: isBuiltIn)
    }

    func rec(
        _ text: String = "x",
        type: ContentType = .text,
        id: UUID = UUID(),
        secondsAgo: TimeInterval = 0,
        bundleID: String? = "com.apple.Notes",
        appName: String? = "Ghi chú",
        ocr: String? = nil,
        customTitle: String? = nil,
        url: String? = nil,
        pinboardID: UUID? = nil,
        pinned: Bool = false
    ) -> ClipboardRecord {
        var metadata: [String: String] = [:]
        if pinned { metadata["isPinned"] = "true" }
        if let customTitle { metadata["customTitle"] = customTitle }
        if let url { metadata["url"] = url }
        return ClipboardRecord(
            id: id, type: type, timestamp: now.addingTimeInterval(-secondsAgo),
            sourceBundleID: bundleID, sourceAppName: appName, textSnippet: text,
            thumbnailPath: nil, payloadPath: nil, ocrText: ocr, pinboardID: pinboardID, metadata: metadata
        )
    }

    // MARK: - Facets

    func testFacetsCountTypesAppsAndBoardsAndSortAppsByCountThenName() {
        let b1 = board(name: "Board A")
        let b2 = board(name: "Board B")
        let records = [
            rec("1", type: .text, bundleID: "com.a", appName: "Alpha"),
            rec("2", type: .text, bundleID: "com.a", appName: "Alpha"),
            rec("3", type: .code, bundleID: "com.b", appName: "Beta"),
            rec("4", type: .code, bundleID: "com.c", appName: "Zed"),
            rec("5", type: .link, bundleID: "com.c", appName: "Zed", pinboardID: b1.id),
            rec("6", type: .link, bundleID: "com.c", appName: "Zed", pinned: true),
        ]
        let facets = X.facets(records, boards: [b1, b2])

        XCTAssertEqual(facets.total, 6)
        XCTAssertEqual(facets.pinned, 1)
        XCTAssertEqual(facets.byType[.text], 2)
        XCTAssertEqual(facets.byType[.code], 2)
        XCTAssertEqual(facets.byType[.link], 2)
        XCTAssertNil(facets.byType[.image], "a type with zero records must not appear at all")

        // com.c (Zed) has 3 records, com.a (Alpha) has 2, com.b (Beta) has 1 — count desc.
        XCTAssertEqual(facets.apps.map(\.bundleID), ["com.c", "com.a", "com.b"])
        XCTAssertEqual(facets.apps.map(\.count), [3, 2, 1])

        XCTAssertEqual(facets.byBoard[b1.id], 1, "one record captured straight into Board A")
        XCTAssertEqual(facets.byBoard[b2.id], 0)
    }

    func testFacetsSortAppsByNameWhenCountsTie() {
        // Equal counts: a facets implementation that sorted by name FIRST would still pass this test
        // with count ascending too, so the test asserts the exact tie-broken order (Alpha before Zed)
        // for an unambiguous sort key comparison.
        let records = [
            rec("1", bundleID: "com.z", appName: "Zed"),
            rec("2", bundleID: "com.a", appName: "Alpha"),
        ]
        let facets = X.facets(records, boards: [])
        XCTAssertEqual(facets.apps.map(\.name), ["Alpha", "Zed"], "tied counts break by name ascending")
    }

    func testFacetsPutANilBundleIDUnderTheEmptyStringKeyedByAppName() {
        let records = [
            rec("1", bundleID: nil, appName: "Mystery App"),
            rec("2", bundleID: nil, appName: "Mystery App"),
        ]
        let facets = X.facets(records, boards: [])
        XCTAssertEqual(facets.apps.count, 1)
        XCTAssertEqual(facets.apps.first?.bundleID, "")
        XCTAssertEqual(facets.apps.first?.name, "Mystery App")
        XCTAssertEqual(facets.apps.first?.count, 2)
    }

    func testFacetsBoardMembershipCountsBothPinboardIDAndItemIDs() {
        let boardID = UUID()
        let viaPinboardID = ClipboardRecord(id: UUID(), type: .text, timestamp: now, sourceBundleID: nil,
            sourceAppName: nil, textSnippet: "a", thumbnailPath: nil, payloadPath: nil, ocrText: nil,
            pinboardID: boardID, metadata: [:])
        let viaItemIDs = rec("b")
        let unrelated = rec("c")
        let b = board(name: "Mixed", id: boardID, itemIDs: [viaItemIDs.id])
        let facets = X.facets([viaPinboardID, viaItemIDs, unrelated], boards: [b])
        XCTAssertEqual(facets.byBoard[b.id], 2, "one via pinboardID, one via itemIDs")
    }

    // MARK: - Scope filtering

    func testScopeAllReturnsEverything() {
        let records = [rec("1"), rec("2", pinned: true)]
        XCTAssertEqual(X.apply(X.Query(scope: .all), to: records, boards: [], now: now, calendar: calendar).count, 2)
    }

    func testScopePinnedKeepsOnlyPinnedRecords() {
        let pinned = rec("pinned", pinned: true)
        let plain = rec("plain")
        let out = X.apply(X.Query(scope: .pinned), to: [pinned, plain], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [pinned.id])
    }

    func testScopeTypeKeepsOnlyThatContentType() {
        let codeRec = rec("code", type: .code)
        let textRec = rec("text", type: .text)
        let out = X.apply(X.Query(scope: .type(.code)), to: [codeRec, textRec], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [codeRec.id])
    }

    func testScopeAppKeepsOnlyThatBundleIDIncludingTheEmptyStringForNil() {
        let a = rec("a", bundleID: "com.a")
        let b = rec("b", bundleID: "com.b")
        let noBundle = rec("c", bundleID: nil)
        let out = X.apply(X.Query(scope: .app("com.a")), to: [a, b, noBundle], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [a.id])

        let noBundleOut = X.apply(X.Query(scope: .app("")), to: [a, b, noBundle], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(noBundleOut.map(\.id), [noBundle.id])
    }

    func testScopeBoardKeepsMembersViaPinboardIDOrItemIDs() {
        let board1ID = UUID()
        let viaPinboardID = ClipboardRecord(id: UUID(), type: .text, timestamp: now, sourceBundleID: nil,
            sourceAppName: nil, textSnippet: "a", thumbnailPath: nil, payloadPath: nil, ocrText: nil,
            pinboardID: board1ID, metadata: [:])
        let viaItemIDs = rec("b")
        let outside = rec("c")
        let b = board(name: "B1", id: board1ID, itemIDs: [viaItemIDs.id])
        let out = X.apply(X.Query(scope: .board(board1ID)), to: [viaPinboardID, viaItemIDs, outside], boards: [b], now: now, calendar: calendar)
        XCTAssertEqual(Set(out.map(\.id)), [viaPinboardID.id, viaItemIDs.id])
    }

    func testScopeBoardWithUnknownIDReturnsEmpty() {
        let records = [rec("a")]
        let out = X.apply(X.Query(scope: .board(UUID())), to: records, boards: [], now: now, calendar: calendar)
        XCTAssertTrue(out.isEmpty)
    }

    /// If `apply` ignored `scope` entirely this test would see both records (free text "a" matches
    /// both snippets) — it only passes because the pinned-only scope actually narrows first.
    func testApplyWouldFailIfScopeWereIgnored() {
        let pinned = rec("alpha", pinned: true)
        let plain = rec("alpha-two")
        let out = X.apply(X.Query(scope: .pinned, text: "alpha"), to: [pinned, plain], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [pinned.id])
    }

    // MARK: - Token narrowing on top of scope and free text

    func testTypeTokenNarrowsOnTopOfScope() {
        let text1 = rec("hello", type: .text)
        let code1 = rec("hello", type: .code)
        let out = X.apply(X.Query(scope: .all, text: "@code hello"), to: [text1, code1], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [code1.id])
    }

    func testAppTokenNarrowsViaFilterTokenAppMatches() {
        let chrome = rec("x", bundleID: "com.google.Chrome", appName: "Google Chrome")
        let notes = rec("x", bundleID: "com.apple.Notes", appName: "Notes")
        let out = X.apply(X.Query(scope: .all, text: "@chrome"), to: [chrome, notes], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [chrome.id])
    }

    func testFreeTextMatchesSnippetOcrCustomTitleAppNameAndMetadataURLCaseInsensitively() {
        let bySnippet = rec("Contains NEEDLE here")
        let byOCR = rec("plain", ocr: "scanned NEEDLE text")
        let byTitle = rec("plain", customTitle: "My NEEDLE Title")
        let byAppName = rec("plain", appName: "NEEDLE App")
        let byURL = rec("plain", url: "https://example.com/NEEDLE")
        let none = rec("nothing here")

        let out = X.apply(X.Query(scope: .all, text: "needle"), to: [bySnippet, byOCR, byTitle, byAppName, byURL, none], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(Set(out.map(\.id)), [bySnippet.id, byOCR.id, byTitle.id, byAppName.id, byURL.id])
    }

    // MARK: - Period boundaries

    func testPeriodTodayMatchesSameCalendarDayOnBothSidesOfMidnight() {
        // now = 2026-10-12 14:30:00 UTC. Earlier today vs. yesterday just before midnight.
        let earlierToday = rec("a", secondsAgo: 3600)                       // 13:30 UTC, same day
        let justBeforeMidnightYesterday = rec("b", secondsAgo: 14 * 3600 + 30 * 60 + 1) // 2026-10-11 23:59:59 UTC
        let out = X.apply(X.Query(scope: .all, period: .today), to: [earlierToday, justBeforeMidnightYesterday], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [earlierToday.id])
    }

    /// Pins the definition: `.week` is a ROLLING 7×24h window from `now`, not a calendar week. A record
    /// exactly at 7*24h ago is included (<=); one second past is excluded.
    func testPeriodWeekIsExactlySevenTimesTwentyFourHoursNotSevenCalendarDays() {
        let exactlyAtBoundary = rec("a", secondsAgo: 7 * 24 * 3600)
        let justOutside = rec("b", secondsAgo: 7 * 24 * 3600 + 1)
        let wellInside = rec("c", secondsAgo: 24 * 3600)

        let out = X.apply(X.Query(scope: .all, period: .week), to: [exactlyAtBoundary, justOutside, wellInside], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(Set(out.map(\.id)), [exactlyAtBoundary.id, wellInside.id])
    }

    /// `now` is deliberately NOT midnight-aligned (14:30 UTC). A "week" implemented as "since the
    /// START OF THE DAY 7 calendar days ago" (midnight 2026-10-05, a plausible wrong reading of
    /// "7 calendar days") would keep a record from 2026-10-05 01:00 UTC — it is the same calendar
    /// date as the 7-days-back boundary. But that record is 181.5h before `now`, well past the
    /// rolling 168h (7×24h) window this type is pinned to. A `now` sitting exactly on a day boundary
    /// cannot distinguish these two readings, which is why `now` here carries a nonzero time-of-day.
    func testPeriodWeekRollingWindowExcludesARecordWithinSevenCalendarDaysButPastSevenTimesTwentyFourHours() {
        let pastRollingWindow = rec("old", secondsAgo: 181.5 * 3600)
        let out = X.apply(X.Query(scope: .all, period: .week), to: [pastRollingWindow], boards: [], now: now, calendar: calendar)
        XCTAssertTrue(out.isEmpty, "a start-of-calendar-day based .week would keep this record; the rolling 168h definition must not")
    }

    func testPeriodMonthIsExactlyThirtyTimesTwentyFourHours() {
        let exactlyAtBoundary = rec("a", secondsAgo: 30 * 24 * 3600)
        let justOutside = rec("b", secondsAgo: 30 * 24 * 3600 + 1)
        let out = X.apply(X.Query(scope: .all, period: .month), to: [exactlyAtBoundary, justOutside], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [exactlyAtBoundary.id])
    }

    func testPeriodAnyMatchesEverythingRegardlessOfAge() {
        let ancient = rec("a", secondsAgo: 365 * 24 * 3600)
        let out = X.apply(X.Query(scope: .all, period: .any), to: [ancient], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [ancient.id])
    }

    // MARK: - Sort orders

    func testSortNewestOrdersDescendingByTimestamp() {
        let oldest = rec("old", secondsAgo: 100)
        let middle = rec("mid", secondsAgo: 50)
        let newest = rec("new", secondsAgo: 0)
        let out = X.apply(X.Query(scope: .all, sort: .newest), to: [oldest, newest, middle], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [newest.id, middle.id, oldest.id])
    }

    func testSortOldestOrdersAscendingByTimestamp() {
        let oldest = rec("old", secondsAgo: 100)
        let middle = rec("mid", secondsAgo: 50)
        let newest = rec("new", secondsAgo: 0)
        let out = X.apply(X.Query(scope: .all, sort: .oldest), to: [oldest, newest, middle], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [oldest.id, middle.id, newest.id])
    }

    func testSortByAppOrdersCaseInsensitiveAscendingThenNewestWithinAnApp() {
        let alphaOld = rec("a", secondsAgo: 100, appName: "alpha")
        let alphaNew = rec("a", secondsAgo: 10, appName: "Alpha")
        let zed = rec("z", secondsAgo: 5, appName: "Zed")
        let out = X.apply(X.Query(scope: .all, sort: .byApp), to: [zed, alphaOld, alphaNew], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [alphaNew.id, alphaOld.id, zed.id], "case-insensitive name order, newest first within the same app")
    }

    func testSortByTypeOrdersByRawValueAscendingThenNewestWithinAType() {
        // ContentType raw values alphabetically: code, color, file, image, link, markdown, merged, text
        let textOld = rec("t", type: .text, secondsAgo: 100)
        let textNew = rec("t", type: .text, secondsAgo: 10)
        let code = rec("c", type: .code, secondsAgo: 5)
        let out = X.apply(X.Query(scope: .all, sort: .byType), to: [textOld, textNew, code], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [code.id, textNew.id, textOld.id])
    }

    /// If `apply` sorted apps by NAME first (ignoring the declared sort order) this would still look
    /// plausible for `.byApp`, so pin `.newest` explicitly against a dataset whose app-name order
    /// would differ from timestamp order.
    func testSortNewestWouldFailIfAppsWereSortedByNameInstead() {
        let zedNewest = rec("z", secondsAgo: 0, appName: "Zed")
        let alphaOldest = rec("a", secondsAgo: 1000, appName: "Alpha")
        let out = X.apply(X.Query(scope: .all, sort: .newest), to: [alphaOldest, zedNewest], boards: [], now: now, calendar: calendar)
        XCTAssertEqual(out.map(\.id), [zedNewest.id, alphaOldest.id], "newest-first must win over any app-name ordering")
    }

    // MARK: - Pagination

    func testVisibleCountClampsToTotalAndToAtLeastOnePage() {
        XCTAssertEqual(X.visibleCount(total: 10, pagesShown: 1), 10)
        XCTAssertEqual(X.visibleCount(total: 200, pagesShown: 1), X.pageSize)
        XCTAssertEqual(X.visibleCount(total: 200, pagesShown: 2), min(200, 2 * X.pageSize))
        XCTAssertEqual(X.visibleCount(total: 10, pagesShown: 0), 10, "pagesShown below 1 must not hide everything")
        XCTAssertEqual(X.visibleCount(total: 0, pagesShown: 1), 0)
    }

    // MARK: - Scope titles

    func testScopeTitleKeyAndIsKeyForAllPinnedAndType() {
        XCTAssertEqual(X.scopeTitleKey(.all, boards: []), "Tất cả")
        XCTAssertTrue(X.scopeTitleIsKey(.all))
        XCTAssertEqual(X.scopeTitleKey(.pinned, boards: []), "Đã ghim")
        XCTAssertTrue(X.scopeTitleIsKey(.pinned))
        XCTAssertEqual(X.scopeTitleKey(.type(.code), boards: []), ContentType.code.titleVI)
        XCTAssertTrue(X.scopeTitleIsKey(.type(.code)))
    }

    func testScopeTitleForBoardIsTheBoardsOwnNameAndIsNotAKey() {
        let b = board(name: "My Custom Board")
        XCTAssertEqual(X.scopeTitleKey(.board(b.id), boards: [b]), "My Custom Board")
        XCTAssertFalse(X.scopeTitleIsKey(.board(b.id)), "a board name must never be wrapped in L10n.t")
    }

    func testScopeTitleForAppIsNotAKey() {
        XCTAssertFalse(X.scopeTitleIsKey(.app("com.apple.Safari")), "an app name must never be wrapped in L10n.t")
    }

    // MARK: - Facts

    func testFactsLinesCountsOnePlusNewlines() {
        XCTAssertEqual(X.Facts.lines(in: ""), 0)
        XCTAssertEqual(X.Facts.lines(in: "one line"), 1)
        XCTAssertEqual(X.Facts.lines(in: "line one\nline two"), 2)
        XCTAssertEqual(X.Facts.lines(in: "a\nb\nc"), 3)
    }

    func testFactsCharactersCountsCharacters() {
        XCTAssertEqual(X.Facts.characters(in: ""), 0)
        XCTAssertEqual(X.Facts.characters(in: "hello"), 5)
    }

    func testFactsSizeLabelFormatsPositiveBytesAndIsEmptyOtherwise() {
        XCTAssertEqual(X.Facts.sizeLabel(bytes: 0), "")
        XCTAssertEqual(X.Facts.sizeLabel(bytes: -5), "")
        XCTAssertFalse(X.Facts.sizeLabel(bytes: 4_100_000).isEmpty)
    }

    // MARK: - Grid move, no-wrap semantics

    func testMoveLeftRightStopAtTheEnds() {
        XCTAssertEqual(X.move(0, direction: .left, count: 5, columns: 3), 0, "already at the start")
        XCTAssertEqual(X.move(2, direction: .left, count: 5, columns: 3), 1)
        XCTAssertEqual(X.move(4, direction: .right, count: 5, columns: 3), 4, "already at the end")
        XCTAssertEqual(X.move(2, direction: .right, count: 5, columns: 3), 3)
    }

    func testMoveUpDownStayPutWhenThereIsNoRowThere() {
        // 5 items, 3 columns: row 0 = [0,1,2], row 1 = [3,4].
        XCTAssertEqual(X.move(1, direction: .up, count: 5, columns: 3), 1, "no row above row 0")
        XCTAssertEqual(X.move(4, direction: .down, count: 5, columns: 3), 4, "no row below the last partial row")
        XCTAssertEqual(X.move(1, direction: .down, count: 5, columns: 3), 4, "moves down one full row")
        XCTAssertEqual(X.move(4, direction: .up, count: 5, columns: 3), 1, "moves up one full row")
    }

    func testMoveClampsAnOutOfRangeStartingIndex() {
        XCTAssertEqual(X.move(99, direction: .left, count: 5, columns: 3), 3, "clamp to the last valid index, then move left")
        XCTAssertEqual(X.move(-1, direction: .right, count: 5, columns: 3), 1, "clamp to 0, then move right")
    }

    func testMoveWithNoItemsReturnsZero() {
        XCTAssertEqual(X.move(0, direction: .left, count: 0, columns: 3), 0)
    }
}
