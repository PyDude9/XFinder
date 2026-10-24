import XCTest
import Foundation

/// XF-T29 — the Free-tier clipboard history gate (`ClipboardProGate`, declared alongside
/// `ClipboardLibrary` in `ClipboardLibraryRules.swift`): pinned/saved clips are exempt and always show;
/// of the rest, the newest `limit` show and the remainder is hidden, never deleted.
final class ClipboardProGateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    func rec(_ text: String, minutesAgo: Double = 0, pinned: Bool = false, saved: Bool = false, id: UUID = UUID()) -> ClipboardRecord {
        var meta: [String: String] = [:]
        if pinned { meta["isPinned"] = "true" }
        if saved { meta["isSaved"] = "true" }
        return ClipboardRecord(id: id, type: .text, timestamp: t0.addingTimeInterval(-minutesAgo * 60), sourceBundleID: nil,
                               sourceAppName: nil, textSnippet: text, thumbnailPath: nil, payloadPath: nil, ocrText: nil,
                               pinboardID: nil, metadata: meta)
    }

    func testNilLimitShowsEverything() {
        let all = (0..<60).map { rec("\($0)", minutesAgo: Double($0)) }
        XCTAssertEqual(ClipboardProGate.visible(all, limit: nil).count, 60)
        XCTAssertEqual(ClipboardProGate.hiddenCount(all, limit: nil), 0)
    }

    func testOnlyTheNewestLimitShowWhenOverTheCap() {
        // Newest first, as ClipboardManager.history is kept.
        let all = (0..<60).map { rec("\($0)", minutesAgo: Double($0)) }
        let visible = ClipboardProGate.visible(all, limit: 50)
        XCTAssertEqual(visible.count, 50)
        XCTAssertEqual(visible.map(\.textSnippet), (0..<50).map { "\($0)" }, "the 50 newest, not the 50 oldest")
        XCTAssertEqual(ClipboardProGate.hiddenCount(all, limit: 50), 10)
    }

    func testUnderTheCapHidesNothing() {
        let all = (0..<30).map { rec("\($0)", minutesAgo: Double($0)) }
        XCTAssertEqual(ClipboardProGate.visible(all, limit: 50).count, 30)
        XCTAssertEqual(ClipboardProGate.hiddenCount(all, limit: 50), 0)
    }

    func testPinnedAndSavedAreExemptAndDoNotCountAgainstTheLimit() {
        var all = (0..<50).map { rec("item\($0)", minutesAgo: Double($0) + 10) }
        all.append(rec("pinned-old", minutesAgo: 9999, pinned: true))
        all.append(rec("saved-old", minutesAgo: 9999, saved: true))
        // 50 ordinary items already fill the limit; the pinned and saved items are old but must still show.
        let visible = ClipboardProGate.visible(all, limit: 50)
        XCTAssertEqual(visible.count, 52)
        XCTAssertTrue(visible.contains { $0.textSnippet == "pinned-old" })
        XCTAssertTrue(visible.contains { $0.textSnippet == "saved-old" })
        XCTAssertEqual(ClipboardProGate.hiddenCount(all, limit: 50), 0)
    }

    func testExemptItemsInterleavedStillLeaveFiftyOrdinaryItemsVisible() {
        // 60 ordinary + 5 pinned interleaved: exactly 50 ordinary should show, all 5 pinned show, and
        // exactly 10 ordinary items are hidden.
        var all: [ClipboardRecord] = []
        for i in 0..<60 { all.append(rec("item\(i)", minutesAgo: Double(i))) }
        for i in 0..<5 { all.append(rec("pin\(i)", minutesAgo: 9999 + Double(i), pinned: true)) }
        all.sort { $0.timestamp > $1.timestamp }
        let visible = ClipboardProGate.visible(all, limit: 50)
        let visibleOrdinary = visible.filter { !ClipboardProGate.isExempt($0) }
        XCTAssertEqual(visibleOrdinary.count, 50)
        XCTAssertEqual(visible.filter(\.isPinned).count, 5)
        XCTAssertEqual(ClipboardProGate.hiddenCount(all, limit: 50), 10)
    }

    func testIsExemptCoversBothPinnedAndSaved() {
        XCTAssertTrue(ClipboardProGate.isExempt(rec("a", pinned: true)))
        XCTAssertTrue(ClipboardProGate.isExempt(rec("a", saved: true)))
        XCTAssertFalse(ClipboardProGate.isExempt(rec("a")))
    }
}
