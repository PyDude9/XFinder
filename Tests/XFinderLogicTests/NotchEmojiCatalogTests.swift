import XCTest
import Foundation

final class NotchEmojiCatalogTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.xfinder.tests.notchEmoji.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Catalog Integrity

    func testCatalogCoversAllBrowseableCategoriesWithUniqueGlyphs() {
        XCTAssertFalse(NotchEmojiCatalog.all.isEmpty)
        let glyphs = NotchEmojiCatalog.all.map(\.glyph)
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "catalog glyphs must be unique")

        for category in NotchEmojiCategory.browseable {
            let items = NotchEmojiCatalog.items(in: category, recents: [])
            XCTAssertFalse(items.isEmpty, "category \(category.rawValue) must not be empty")
            for item in items {
                XCTAssertFalse(item.nameVI.isEmpty)
                XCTAssertFalse(item.nameEN.isEmpty)
                XCTAssertFalse(item.keywordsVI.isEmpty)
                XCTAssertFalse(item.keywordsEN.isEmpty)
            }
        }
    }

    // MARK: - Accented Vietnamese & English Search (từ có dấu)

    func testSearchMatchesAccentedAndUnaccentedVietnameseKeywordsIncludingDStroke() {
        // Accented and unaccented queries must resolve the same target emojis.
        let accentedSmile = NotchEmojiCatalog.search("cười")
        let plainSmile = NotchEmojiCatalog.search("cuoi")
        XCTAssertTrue(accentedSmile.contains(where: { $0.glyph == "😀" }))
        XCTAssertEqual(accentedSmile.map(\.glyph), plainSmile.map(\.glyph))

        // Vietnamese đ/Đ folding: "đồng hồ" == "dong ho", "Đức" == "duc", "đỏ" == "do"
        let clockAccented = NotchEmojiCatalog.search("đồng hồ")
        let clockPlain = NotchEmojiCatalog.search("dong ho")
        XCTAssertTrue(clockAccented.contains(where: { $0.glyph == "⏰" }))
        XCTAssertEqual(clockAccented.map(\.glyph), clockPlain.map(\.glyph))

        let germanyUpperDStroke = NotchEmojiCatalog.search("ĐỨC")
        let germanyPlain = NotchEmojiCatalog.search("duc")
        XCTAssertTrue(germanyUpperDStroke.contains(where: { $0.glyph == "🇩🇪" }))
        XCTAssertEqual(germanyUpperDStroke.map(\.glyph), germanyPlain.map(\.glyph))

        // Multi-word accented query with extra spaces
        let coffee = NotchEmojiCatalog.search("  Cà   Phê  ")
        XCTAssertEqual(coffee.first?.glyph, "☕")

        // English keywords
        let rocket = NotchEmojiCatalog.search("rocket")
        XCTAssertEqual(rocket.first?.glyph, "🚀")
        let heart = NotchEmojiCatalog.search("heart")
        XCTAssertTrue(heart.contains(where: { $0.glyph == "❤️" }))
    }

    // MARK: - No-Match Search (tìm không khớp)

    func testSearchReturnsEmptyWhenNoMatch() {
        XCTAssertTrue(NotchEmojiCatalog.search("khongcogihet12345").isEmpty)
        XCTAssertTrue(NotchEmojiCatalog.search("cà phê tên lửa").isEmpty, "AND semantics across unrelated tokens")

        let store = NotchEmojiRecentsStore(defaults: defaults)
        var session = NotchEmojiPickerSession(store: store, copyHandler: { _ in true })
        session.query = "zzzz-no-match-emoji"
        XCTAssertTrue(session.isSearching)
        XCTAssertTrue(session.displayedItems.isEmpty)
    }

    // MARK: - Multi-Scalar Unicode Graphemes (grapheme nhiều ký tự Unicode)

    func testMultiScalarUnicodeGraphemesStayIntactAcrossSearchRecentsAndCopy() {
        let multiScalarGlyphs = [
            "👨‍💻",   // ZWJ sequence
            "👨‍👩‍👧‍👦", // multi-ZWJ family sequence
            "❤️‍🔥",   // VS16 + ZWJ heart on fire
            "👍🏽",     // base + skin-tone modifier
            "1️⃣",     // keycap sequence
            "🇻🇳",     // regional indicator pair
            "✈️",     // base + VS16
        ]

        for glyph in multiScalarGlyphs {
            XCTAssertEqual(glyph.count, 1, "\(glyph) should be one extended grapheme cluster")
            XCTAssertGreaterThan(glyph.unicodeScalars.count, 1, "\(glyph) should contain multiple Unicode scalars")
            let found = NotchEmojiCatalog.search(glyph)
            XCTAssertEqual(found.first?.glyph, glyph, "exact glyph search must preserve \(glyph)")
        }

        // Verify copying and persisting preserves exact scalar sequences byte-for-byte.
        var copied: [String] = []
        let store = NotchEmojiRecentsStore(defaults: defaults)
        var session = NotchEmojiPickerSession(store: store) { glyph in
            copied.append(glyph)
            return true
        }

        for glyph in multiScalarGlyphs {
            XCTAssertTrue(session.copy(glyph: glyph))
        }

        XCTAssertEqual(copied, multiScalarGlyphs)
        XCTAssertEqual(session.recents, Array(multiScalarGlyphs.reversed()))

        // Reopen with a new session reading from the same defaults: scalars must remain identical.
        let reopened = NotchEmojiPickerSession(store: NotchEmojiRecentsStore(defaults: defaults), copyHandler: { _ in true })
        XCTAssertEqual(reopened.recents, Array(multiScalarGlyphs.reversed()))
        for (expected, actual) in zip(multiScalarGlyphs.reversed(), reopened.recents) {
            XCTAssertEqual(Array(expected.unicodeScalars), Array(actual.unicodeScalars))
        }
    }

    // MARK: - Recents Limit (24), Deduplication & Persistence After Reopen (mục gần đây sau mở lại)

    func testRecentsCap24AndDeduplicationMoveToFront() {
        let glyphs = Array(NotchEmojiCatalog.all.prefix(30).map(\.glyph))
        XCTAssertEqual(glyphs.count, 30)

        var recents: [String] = []
        for g in glyphs {
            recents = NotchEmojiCatalog.recordRecent(g, into: recents)
        }
        XCTAssertEqual(recents.count, 24, "recents must cap at 24")
        XCTAssertEqual(recents.first, glyphs[29], "most recent must be first")
        XCTAssertEqual(recents.last, glyphs[6], "oldest beyond 24 must be evicted")

        // Re-selecting an existing recent moves it to front without duplicating or shrinking count.
        let target = glyphs[10]
        recents = NotchEmojiCatalog.recordRecent(target, into: recents)
        XCTAssertEqual(recents.count, 24)
        XCTAssertEqual(recents.first, target)
        XCTAssertEqual(recents.filter { $0 == target }.count, 1)
    }

    func testSanitizeRecentsDropsEmptyDeduplicatesAndCaps() {
        let dirty = ["", "   ", "🔥", "❤️", "🔥", "👨‍💻", "\n", "🇻🇳"]
        let clean = NotchEmojiCatalog.sanitizeRecents(dirty, limit: 3)
        XCTAssertEqual(clean, ["🔥", "❤️", "👨‍💻"])
    }

    func testRecentsPersistAfterReopen() {
        let store1 = NotchEmojiRecentsStore(defaults: defaults)
        var copied: [String] = []
        var session1 = NotchEmojiPickerSession(store: store1) { glyph in
            copied.append(glyph)
            return true
        }

        XCTAssertTrue(session1.copy(glyph: "🔥"))
        XCTAssertTrue(session1.copy(glyph: "👨‍💻"))
        XCTAssertTrue(session1.copy(glyph: "🇻🇳"))
        XCTAssertTrue(session1.copy(glyph: "🔥")) // duplicate moves to front

        // Simulate closing and reopening the Dynamic Island emoji page.
        let store2 = NotchEmojiRecentsStore(defaults: defaults)
        var session2 = NotchEmojiPickerSession(store: store2, copyHandler: { _ in true })
        session2.selectCategory(.recent)

        XCTAssertEqual(session2.recents, ["🔥", "🇻🇳", "👨‍💻"])
        XCTAssertEqual(session2.displayedItems.map(\.glyph), ["🔥", "🇻🇳", "👨‍💻"])
    }

    // MARK: - Copy Behavior (sao chép)

    func testCopyInvokesHandlerAndDoesNotRecordOnFailure() {
        let store = NotchEmojiRecentsStore(defaults: defaults)
        var copied: [String] = []
        var shouldSucceed = false

        var session = NotchEmojiPickerSession(store: store) { glyph in
            if shouldSucceed {
                copied.append(glyph)
                return true
            }
            return false
        }

        let fire = try! XCTUnwrap(NotchEmojiCatalog.byGlyph["🔥"])
        XCTAssertFalse(session.copy(fire))
        XCTAssertTrue(copied.isEmpty)
        XCTAssertTrue(session.recents.isEmpty)
        XCTAssertNil(session.lastCopiedGlyph)

        shouldSucceed = true
        XCTAssertTrue(session.copy(fire))
        XCTAssertEqual(copied, ["🔥"])
        XCTAssertEqual(session.recents, ["🔥"])
        XCTAssertEqual(session.lastCopiedGlyph, "🔥")
    }
}
