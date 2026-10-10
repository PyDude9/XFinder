import XCTest

/// Unit tests for Klippy-inspired clipboard features:
/// - Merged clip codec (Unicode separator boundary, encoding, decoding)
/// - Multi-tier date range filtering
/// - Slice filtering logic (All, Pinned, Saved, Merged)
/// - Sort order evaluation (Newest, Oldest, Most Used)
final class ClipboardKlippyTests: XCTestCase {

    // MARK: - MergedClipCodec

    struct TestClipCodec {
        static let separator = "\n\u{001F}───XFINDER_MERGE───\u{001F}\n"

        static func encode(components: [String]) -> String {
            components.joined(separator: separator)
        }

        static func decode(rawText: String) -> [String] {
            guard rawText.contains(separator) else {
                return [rawText]
            }
            return rawText.components(separatedBy: separator)
        }

        static func isMerged(rawText: String) -> Bool {
            rawText.contains(separator)
        }
    }

    func testMergedClipCodecSingleComponent() {
        let text = "First piece of content"
        let encoded = TestClipCodec.encode(components: [text])
        XCTAssertEqual(encoded, text)
        XCTAssertFalse(TestClipCodec.isMerged(rawText: encoded))
        let decoded = TestClipCodec.decode(rawText: encoded)
        XCTAssertEqual(decoded, [text])
    }

    func testMergedClipCodecMultipleComponents() {
        let parts = ["Line 1: Alpha", "Line 2: Beta", "Line 3: Gamma"]
        let encoded = TestClipCodec.encode(components: parts)

        XCTAssertTrue(TestClipCodec.isMerged(rawText: encoded))
        let decoded = TestClipCodec.decode(rawText: encoded)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0], "Line 1: Alpha")
        XCTAssertEqual(decoded[1], "Line 2: Beta")
        XCTAssertEqual(decoded[2], "Line 3: Gamma")
    }

    func testMergedClipWithSpecialCharacters() {
        let parts = ["print(\"hello world\")", "https://example.com?q=test&page=1", "{\n  \"status\": 200\n}"]
        let encoded = TestClipCodec.encode(components: parts)

        XCTAssertTrue(TestClipCodec.isMerged(rawText: encoded))
        let decoded = TestClipCodec.decode(rawText: encoded)
        XCTAssertEqual(decoded, parts)
    }

    // MARK: - Date Range Filtering

    enum DateRangeFilter {
        case allTime
        case today
        case last7Days
        case last30Days

        func matches(_ date: Date, reference: Date = Date(), calendar: Calendar = .current) -> Bool {
            switch self {
            case .allTime:
                return true
            case .today:
                return calendar.isDate(date, inSameDayAs: reference)
            case .last7Days:
                guard let cutoff = calendar.date(byAdding: .day, value: -7, to: reference) else { return true }
                return date >= cutoff
            case .last30Days:
                guard let cutoff = calendar.date(byAdding: .day, value: -30, to: reference) else { return true }
                return date >= cutoff
            }
        }
    }

    func testDateFilterToday() {
        let calendar = Calendar.current
        // Noon, not the wall clock: "two hours ago" crossed midnight when the suite ran between
        // 00:00 and 02:00, and the test failed for two hours every night (seen 2026-10-11 00:14).
        let now = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let twoDaysAgo = now.addingTimeInterval(-172800)

        XCTAssertTrue(DateRangeFilter.today.matches(now, reference: now, calendar: calendar))
        XCTAssertTrue(DateRangeFilter.today.matches(twoHoursAgo, reference: now, calendar: calendar))
        XCTAssertFalse(DateRangeFilter.today.matches(twoDaysAgo, reference: now, calendar: calendar))
    }

    func testDateFilterLast7Days() {
        let calendar = Calendar.current
        let now = Date()
        let fiveDaysAgo = now.addingTimeInterval(-5 * 24 * 3600)
        let tenDaysAgo = now.addingTimeInterval(-10 * 24 * 3600)

        XCTAssertTrue(DateRangeFilter.last7Days.matches(now, reference: now, calendar: calendar))
        XCTAssertTrue(DateRangeFilter.last7Days.matches(fiveDaysAgo, reference: now, calendar: calendar))
        XCTAssertFalse(DateRangeFilter.last7Days.matches(tenDaysAgo, reference: now, calendar: calendar))
    }

    func testDateFilterLast30Days() {
        let calendar = Calendar.current
        let now = Date()
        let twentyDaysAgo = now.addingTimeInterval(-20 * 24 * 3600)
        let fortyDaysAgo = now.addingTimeInterval(-40 * 24 * 3600)

        XCTAssertTrue(DateRangeFilter.last30Days.matches(twentyDaysAgo, reference: now, calendar: calendar))
        XCTAssertFalse(DateRangeFilter.last30Days.matches(fortyDaysAgo, reference: now, calendar: calendar))
    }

    // MARK: - Sorting Logic

    struct TestRecord {
        let id: UUID
        let timestamp: Date
        let usageCount: Int
    }

    func testSortByNewestOldestAndUsage() {
        let now = Date()
        let r1 = TestRecord(id: UUID(), timestamp: now.addingTimeInterval(-300), usageCount: 10)
        let r2 = TestRecord(id: UUID(), timestamp: now.addingTimeInterval(-100), usageCount: 2)
        let r3 = TestRecord(id: UUID(), timestamp: now.addingTimeInterval(-600), usageCount: 25)

        let records = [r1, r2, r3]

        let newest = records.sorted { $0.timestamp > $1.timestamp }
        XCTAssertEqual(newest.map(\.id), [r2.id, r1.id, r3.id])

        let oldest = records.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(oldest.map(\.id), [r3.id, r1.id, r2.id])

        let mostUsed = records.sorted { $0.usageCount > $1.usageCount }
        XCTAssertEqual(mostUsed.map(\.id), [r3.id, r1.id, r2.id])
    }
}
