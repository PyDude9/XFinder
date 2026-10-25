import XCTest
@testable import XFinderLogicTests

/// XF-T30 W2 — `GroupBy.sections`. A fixed `now`/`calendar` throughout so date-bucket boundaries (Today / Yesterday /
/// Previous 7 Days / Previous 30 Days / months this year / earlier years) are exact, not "close enough" against the
/// real clock. `now` = 2026-10-25 15:00:00 UTC, Gregorian calendar, UTC time zone (so a day boundary is always exactly
/// midnight UTC, with no local-timezone skew in the test itself).
final class GroupBySectionsTests: XCTestCase {

    // MARK: - Fixtures

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    /// 2026-10-25 15:00:00 UTC.
    private var now: Date { Date(timeIntervalSince1970: 1_792_940_400) }

    private func entry(
        name: String, kind: DirectoryEntry.Kind = .file, size: Int64 = 0, path: String? = nil,
        modified: Date? = nil, created: Date? = nil, added: Date? = nil, lastOpened: Date? = nil,
        tags: [String]? = nil
    ) -> DirectoryEntry {
        var e = DirectoryEntry(
            name: name, path: path ?? "/tmp/\(name)", kind: kind, isPackage: false, isHidden: false, size: size,
            modified: modified ?? Date(timeIntervalSince1970: 0), created: created ?? Date(timeIntervalSince1970: 0),
            volumeID: 1
        )
        e.added = added
        e.lastOpened = lastOpened
        e.tags = tags
        return e
    }

    private func day(_ offsetDays: Int, hour: Int = 12) -> Date {
        let base = calendar.startOfDay(for: now)
        let shifted = calendar.date(byAdding: .day, value: offsetDays, to: base)!
        return calendar.date(byAdding: .hour, value: hour, to: shifted)!
    }

    private func sections(
        _ entries: [DirectoryEntry], by group: GroupBy, sort: SortOrder = .finderDefault, foldersFirst: Bool = false
    ) -> [EntrySection] {
        GroupBy.sections(
            entries, by: group, sort: sort, foldersFirst: foldersFirst, now: now, calendar: calendar,
            kindName: { _ in "" }, appName: { _ in nil }
        )
    }

    // MARK: - .none

    func testNoneReturnsOneSectionWithEveryEntrySorted() {
        let a = entry(name: "Zeta"), b = entry(name: "Alpha")
        let result = sections([a, b], by: .none)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].entries.map(\.name), ["Alpha", "Zeta"])
        XCTAssertEqual(result[0].titleKey, "")
        XCTAssertNil(result[0].titleArg)
    }

    func testNoneWithEmptyInputStillReturnsOneSection() {
        let result = sections([], by: .none)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].entries, [])
    }

    // MARK: - Date groups: boundaries

    func testDateTodayBucket() {
        let e = entry(name: "A", modified: day(0, hour: 0))      // start of today
        let result = sections([e], by: .dateModified)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleKey, "Hôm nay")
        XCTAssertNil(result[0].titleArg)
    }

    func testDateYesterdayBucket() {
        let e = entry(name: "A", modified: day(-1))
        let result = sections([e], by: .dateModified)
        XCTAssertEqual(result[0].titleKey, "Hôm qua")
    }

    func testDateSevenDaysBucketIncludesExactlySevenDaysAgo() {
        // "Previous 7 Days": the oldest day still inside it is 7 calendar days back (2 days before yesterday through
        // 7 days back), NOT including today/yesterday.
        let twoDaysAgo = entry(name: "Two", modified: day(-2))
        let sevenDaysAgo = entry(name: "Seven", modified: day(-7))
        let result = sections([twoDaysAgo, sevenDaysAgo], by: .dateModified)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleKey, "7 ngày trước")
        XCTAssertEqual(Set(result[0].entries.map(\.name)), ["Two", "Seven"])
    }

    func testDateEightDaysAgoFallsIntoThirtyDaysBucketNotSeven() {
        let e = entry(name: "A", modified: day(-8))
        let result = sections([e], by: .dateModified)
        XCTAssertEqual(result[0].titleKey, "30 ngày trước")
    }

    func testDateThirtyDaysBucketIncludesExactlyThirtyDaysAgo() {
        let e = entry(name: "A", modified: day(-30))
        let result = sections([e], by: .dateModified)
        XCTAssertEqual(result[0].titleKey, "30 ngày trước")
    }

    func testDateThirtyOneDaysAgoFallsIntoThisYearMonthBucket() {
        // 31 days before 2026-10-25 is 2026-09-24 — still "this year", so it must land in a MONTH section (titleKey
        // "", titleArg = month name), not the 30-days bucket.
        let e = entry(name: "A", modified: day(-31))
        let result = sections([e], by: .dateModified)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleKey, "")
        XCTAssertEqual(result[0].titleArg, "September")
    }

    func testDateMonthsThisYearAreOrderedMostRecentFirst() {
        let september = entry(name: "Sep", modified: day(-31))                 // 2026-09-24
        let january = entry(name: "Jan", modified: Date(timeIntervalSince1970: 1_767_225_600)) // 2026-01-01 UTC
        let result = sections([january, september], by: .dateModified)
        XCTAssertEqual(result.map(\.titleArg), ["September", "January"])
        XCTAssertEqual(result.map(\.titleKey), ["", ""])
    }

    func testDateEarlierYearIsItsOwnSectionTitledByYear() {
        let lastYear = entry(name: "Old", modified: Date(timeIntervalSince1970: 1_735_000_000)) // 2024-12-24
        let result = sections([lastYear], by: .dateModified)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleKey, "")
        XCTAssertEqual(result[0].titleArg, "2024")
    }

    func testDateEarlierYearsOrderedMostRecentFirst() {
        let y2024 = entry(name: "A", modified: Date(timeIntervalSince1970: 1_703_000_000)) // 2023-12-19
        let y2020 = entry(name: "B", modified: Date(timeIntervalSince1970: 1_577_000_000)) // 2019-12-22
        let result = sections([y2020, y2024], by: .dateModified)
        XCTAssertEqual(result.map(\.titleArg), ["2023", "2019"])
    }

    func testDateNoDateBucketIsLastAndUsesChuaCoNgayKey() {
        let dated = entry(name: "Dated", added: day(0))
        let undated = entry(name: "Undated", added: nil)
        let result = sections([dated, undated], by: .dateAdded)
        XCTAssertEqual(result.last?.titleKey, "Chưa có ngày")
        XCTAssertEqual(result.last?.entries.map(\.name), ["Undated"])
    }

    func testDateGroupsOmitEmptyBuckets() {
        let e = entry(name: "A", modified: day(0))
        let result = sections([e], by: .dateModified)
        XCTAssertEqual(result.count, 1, "only the non-empty Today bucket should appear")
    }

    // MARK: - DST

    /// Spring-forward day in `America/Los_Angeles` (2026-03-08, a 23-hour calendar day: 2:00 AM PST jumps to 3:00 AM
    /// PDT). `Calendar.date(byAdding: .day:)` and `startOfDay` must still treat this as exactly ONE calendar day, not
    /// drift by the missing hour — a naive `now - 86400` (fixed seconds) would land at the wrong wall-clock time and
    /// could misclassify Yesterday as Today or vice versa.
    func testDateYesterdayAcrossSpringForwardDST() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        la.locale = Locale(identifier: "en_US_POSIX")
        let dayAfterSpringForward = Date(timeIntervalSince1970: 1_773_093_600)   // 2026-03-09 15:00 PDT
        let onSpringForwardDay = Date(timeIntervalSince1970: 1_772_996_400)      // 2026-03-08 12:00 PST (yesterday, the 23h day)
        let e = entry(name: "A", modified: onSpringForwardDay)
        let result = GroupBy.sections(
            [e], by: .dateModified, sort: .finderDefault, foldersFirst: false, now: dayAfterSpringForward, calendar: la,
            kindName: { _ in "" }, appName: { _ in nil }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleKey, "Hôm qua")
    }

    func testDateGroupUsesTheRightFieldPerGroupByCase() {
        // Same entry, different dates per field: grouping by each field must look at ITS OWN field, not always
        // `modified` (a likely copy-paste bug when four near-identical cases share one helper).
        var e = entry(name: "A")
        e.added = day(0)
        e.lastOpened = day(-1)
        // created/modified both default to epoch (1970), a different-year bucket.
        XCTAssertEqual(sections([e], by: .dateAdded)[0].titleKey, "Hôm nay")
        XCTAssertEqual(sections([e], by: .dateLastOpened)[0].titleKey, "Hôm qua")
        XCTAssertEqual(sections([e], by: .dateCreated)[0].titleArg, "1970")
        XCTAssertEqual(sections([e], by: .dateModified)[0].titleArg, "1970")
    }

    func testDateMonthNameIsLocaleAware() {
        var viCalendar = calendar
        viCalendar.locale = Locale(identifier: "vi_VN")
        let e = entry(name: "A", modified: day(-31))
        let result = GroupBy.sections(
            [e], by: .dateModified, sort: .finderDefault, foldersFirst: false, now: now, calendar: viCalendar,
            kindName: { _ in "" }, appName: { _ in nil }
        )
        XCTAssertEqual(result[0].titleArg, "Tháng 9")
    }

    func testDateEntriesWithinASectionAreSortedBySortOrder() {
        let a = entry(name: "Zeta", modified: day(0))
        let b = entry(name: "Alpha", modified: day(0))
        let result = sections([a, b], by: .dateModified, sort: SortOrder(key: .name, ascending: true))
        XCTAssertEqual(result[0].entries.map(\.name), ["Alpha", "Zeta"])
    }

    // MARK: - Name (first letter)

    func testNameGroupsByFoldedFirstLetterUppercased() {
        let a = entry(name: "apple")
        let b = entry(name: "Banana")
        let result = sections([a, b], by: .name)
        XCTAssertEqual(result.map(\.titleArg), ["A", "B"])
        XCTAssertEqual(result.map(\.titleKey), ["", ""])
    }

    func testNameGroupFoldsVietnameseDiacritics() {
        // "Đơn" folds to "d" (EntryRules.foldBytes), so it must group under "D", not get its own "Đ" bucket and not
        // fall into "#".
        let e = entry(name: "Đơn hàng.docx")
        let result = sections([e], by: .name)
        XCTAssertEqual(result[0].titleArg, "D")
    }

    func testNameGroupNonLetterFirstCharacterIsHash() {
        let digit = entry(name: "123 report.pdf")
        let symbol = entry(name: "_file.txt")
        let result = sections([digit, symbol], by: .name)
        XCTAssertEqual(result.map(\.titleArg), ["#"])
        XCTAssertEqual(result[0].entries.count, 2)
    }

    func testNameGroupsAreSortedAlphabetically() {
        let z = entry(name: "zebra")
        let a = entry(name: "apple")
        let hash = entry(name: "9lives")
        let result = sections([z, a, hash], by: .name)
        XCTAssertEqual(result.map(\.titleArg), ["#", "A", "Z"])
    }

    // MARK: - Kind

    func testKindGroupsByProvidedLocalizedKindName() {
        let a = entry(name: "a.pdf", path: "/a.pdf")
        let b = entry(name: "b.txt", path: "/b.txt")
        let names: [String: String] = ["/a.pdf": "Tài liệu PDF", "/b.txt": "Tài liệu văn bản"]
        let result = GroupBy.sections(
            [a, b], by: .kind, sort: .finderDefault, foldersFirst: false, now: now, calendar: calendar,
            kindName: { names[$0.path] ?? "" }, appName: { _ in nil }
        )
        XCTAssertEqual(result.map(\.titleArg), ["Tài liệu PDF", "Tài liệu văn bản"])
    }

    // MARK: - Application

    func testApplicationGroupsUnknownAsKhongRo() {
        let known = entry(name: "a", path: "/a")
        let unknown = entry(name: "b", path: "/b")
        let apps: [String: String?] = ["/a": "Xcode", "/b": nil]
        let result = GroupBy.sections(
            [known, unknown], by: .application, sort: .finderDefault, foldersFirst: false, now: now, calendar: calendar,
            kindName: { _ in "" }, appName: { apps[$0.path] ?? nil }
        )
        XCTAssertEqual(Set(result.map(\.titleArg)), ["Xcode", "Không rõ"])
    }

    // MARK: - Size

    func testSizeBucketsExactBoundaries() {
        let kb: Int64 = 1024, mb = kb * 1024, gb = mb * 1024
        let dir = entry(name: "Dir", kind: .directory, size: -1)
        let zero = entry(name: "Zero", size: 0)
        let under100 = entry(name: "Under100", size: 100 * kb - 1)
        let exactly100KB = entry(name: "Exactly100KB", size: 100 * kb)   // boundary: belongs to the NEXT bucket up
        let justUnder1MB = entry(name: "JustUnder1MB", size: mb - 1)
        let exactly1MB = entry(name: "Exactly1MB", size: mb)             // boundary: next bucket up (1-100 MB)
        let justUnder100MB = entry(name: "JustUnder100MB", size: 100 * mb - 1)
        let exactly100MB = entry(name: "Exactly100MB", size: 100 * mb)   // boundary: next bucket up (100MB-1GB)
        let justUnderGB = entry(name: "JustUnderGB", size: gb - 1)
        let exactlyGB = entry(name: "ExactlyGB", size: gb)               // boundary: over 1 GB
        let over1GB = entry(name: "Over1GB", size: gb + 1)

        let result = sections(
            [dir, zero, under100, exactly100KB, justUnder1MB, exactly1MB, justUnder100MB, exactly100MB, justUnderGB,
             exactlyGB, over1GB], by: .size
        )
        let byKey = Dictionary(uniqueKeysWithValues: result.map { ($0.titleKey, Set($0.entries.map(\.name))) })

        XCTAssertEqual(byKey["Thư mục"], ["Dir"])
        XCTAssertEqual(byKey["Không byte"], ["Zero"])
        XCTAssertEqual(byKey["Dưới 100 KB"], ["Under100"])
        XCTAssertEqual(byKey["Từ 100 KB đến 1 MB"], ["Exactly100KB", "JustUnder1MB"])
        XCTAssertEqual(byKey["Từ 1 đến 100 MB"], ["Exactly1MB", "JustUnder100MB"])
        XCTAssertEqual(byKey["Từ 100 MB đến 1 GB"], ["Exactly100MB", "JustUnderGB"])
        XCTAssertEqual(byKey["Trên 1 GB"], ["ExactlyGB", "Over1GB"])
    }

    func testSizeGroupOrderIsZeroToLargeThenFolders() {
        let dir = entry(name: "Dir", kind: .directory, size: -1)
        let big = entry(name: "Big", size: 2 * 1024 * 1024 * 1024)
        let zero = entry(name: "Zero", size: 0)
        let result = sections([dir, big, zero], by: .size)
        XCTAssertEqual(result.map(\.titleKey), ["Không byte", "Trên 1 GB", "Thư mục"])
    }

    // MARK: - Tags

    func testTagsGroupsEachTagSeparatelyAndUntaggedLast() {
        let work = entry(name: "Work file", tags: ["Work"])
        let personal = entry(name: "Personal file", tags: ["Personal"])
        let untagged = entry(name: "Plain file", tags: nil)
        let result = sections([work, personal, untagged], by: .tags)
        XCTAssertEqual(result.last?.titleKey, "Không có thẻ")
        XCTAssertEqual(result.last?.entries.map(\.name), ["Plain file"])
        XCTAssertEqual(Set(result.dropLast().map(\.titleArg)), ["Work", "Personal"])
    }

    func testTagsMultiTagEntryAppearsOnlyUnderFirstTag() {
        let e = entry(name: "Multi", tags: ["Work", "Important"])
        let result = sections([e], by: .tags)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleArg, "Work")
    }

    func testTagsEmptyTagsArrayCountsAsUntagged() {
        let e = entry(name: "EmptyTags", tags: [])
        let result = sections([e], by: .tags)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].titleKey, "Không có thẻ")
    }

    // MARK: - foldersFirst interaction

    func testSectionsHonorsFoldersFirstWithinEachSection() {
        let file = entry(name: "AAA file", kind: .file, tags: ["Tag"])
        let dir = entry(name: "ZZZ dir", kind: .directory, tags: ["Tag"])
        let result = sections([file, dir], by: .tags, sort: SortOrder(key: .name, ascending: true), foldersFirst: true)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].entries.map(\.name), ["ZZZ dir", "AAA file"])
    }
}
