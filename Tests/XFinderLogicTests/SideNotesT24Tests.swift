import XCTest
import CoreGraphics

/// XF-T24 — the edge-notes geometry (preview that fits the note) and the dated-backup rules.
final class SideNotesT24Tests: XCTestCase {
    typealias L = EdgeNotesLayout
    // A 1728×1117 screen with a 33 pt menu bar, like this Mac's built-in display.
    let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    func testTheStackNeverMovesWhenANoteIsPeeked() {
        for count in [1, 2, 5, 12] {
            let docked = L.docked(count: count, visible: visible, screen: screen, onLeft: false)
            let stackTopDocked = docked.panel.maxY - docked.stackTopInset
            for i in 0..<count {
                for h in [72.0, 180, 400, 650] {
                    let p = L.peek(index: i, count: count, cardHeight: h, visible: visible, screen: screen, onLeft: false)
                    XCTAssertEqual(p.panel.maxY - p.stackTopInset, stackTopDocked, accuracy: 0.001,
                                   "count \(count) peek \(i) card \(h): the pills must stay where the hit test reads them")
                    // The identity above holds by construction; what can break is the panel no longer covering the pills
                    // (a lower pill's card would then cut off the ones above it). Mutation T1 proved the identity alone blind.
                    let stack = L.stackRect(count: count, visible: visible, screen: screen, onLeft: false)
                    XCTAssertGreaterThanOrEqual(p.panel.maxY, stack.maxY + L.slack - 0.001, "count \(count) peek \(i): top pills inside the panel")
                    XCTAssertLessThanOrEqual(p.panel.minY, stack.minY - L.slack + 0.001, "count \(count) peek \(i): bottom pills inside the panel")
                }
            }
        }
    }

    func testTheCardStaysInsideTheVisibleFrameAndBesideItsPill() {
        for count in [1, 3, 12] {
            let stack = L.stackRect(count: count, visible: visible, screen: screen, onLeft: true)
            for i in 0..<count {
                for h in [72.0, 300, L.maxCardHeight(visible: visible)] {
                    let p = L.peek(index: i, count: count, cardHeight: h, visible: visible, screen: screen, onLeft: true)
                    let rowTop = stack.maxY - CGFloat(i) * (L.tabHeight + L.tabGap)
                    let cardTop = rowTop + p.cardLift
                    XCTAssertGreaterThanOrEqual(p.cardLift, 0)
                    XCTAssertGreaterThanOrEqual(cardTop - h, visible.minY + L.screenMargin - 0.001, "the card's bottom stays on screen")
                    XCTAssertLessThanOrEqual(cardTop, visible.maxY - L.screenMargin + 0.001, "the card's top stays on screen")
                    XCTAssertTrue(p.panel.contains(CGRect(x: p.panel.minX, y: cardTop - h, width: 1, height: h)),
                                  "the panel contains the whole card — the clipping the owner saw with one or two notes")
                    XCTAssertEqual(p.panel.minX, screen.minX, "flush with the left edge")
                }
            }
        }
        let right = L.peek(index: 0, count: 1, cardHeight: 100, visible: visible, screen: screen, onLeft: false)
        XCTAssertEqual(right.panel.maxX, screen.maxX, accuracy: 0.001, "flush with the right edge")
        XCTAssertEqual(right.cardLift, 0, "a short card beside a centred pill needs no lift")
    }

    func testTheCardIsAsTallAsTheNoteUpToTheCap() {
        let nine = L.cardHeight(bodyHeight: 9 * 14, visible: visible)       // nine lines of 11 pt text
        XCTAssertFalse(nine.truncated, "a nine-line note shows whole")
        XCTAssertEqual(nine.height, L.cardChrome + 126, accuracy: 0.001)
        XCTAssertEqual(L.cardHeight(bodyHeight: 0, visible: visible).height, L.minCardHeight, "an empty note keeps a readable minimum")
        let long = L.cardHeight(bodyHeight: 5_000, visible: visible)
        XCTAssertTrue(long.truncated)
        XCTAssertEqual(long.height, L.maxCardHeight(visible: visible))
        XCTAssertEqual(L.maxCardHeight(visible: visible), 520, "60 % of 1 084 is 650, capped at 520")
        XCTAssertEqual(L.maxCardHeight(visible: CGRect(x: 0, y: 0, width: 1280, height: 400)), 240, "a short screen: 60 %")
    }

    func testTheHitTestMapsYToThePillDrawnThere() {
        let stack = L.stackRect(count: 4, visible: visible, screen: screen, onLeft: false)
        XCTAssertEqual(L.index(at: stack.maxY - 1, stack: stack, count: 4), 0)
        XCTAssertEqual(L.index(at: stack.maxY - (L.tabHeight + L.tabGap) - 1, stack: stack, count: 4), 1)
        XCTAssertEqual(L.index(at: stack.minY + 1, stack: stack, count: 4), 3)
        XCTAssertNil(L.index(at: stack.maxY + 1, stack: stack, count: 4))
        XCTAssertNil(L.index(at: stack.minY - 1, stack: stack, count: 4))
        XCTAssertNil(L.index(at: stack.midY, stack: stack, count: 0))
    }

    // MARK: Backup

    func testBackupFilesAreNamedByThePersonsDay() {
        let d = Date(timeIntervalSince1970: 1_800_000_000)     // 2027-01-15 08:00 UTC
        XCTAssertEqual(NoteBackup.stem(for: d, timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!), "notes-2027-01-15")
        XCTAssertEqual(NoteBackup.stem(for: d, timeZone: TimeZone(identifier: "America/Los_Angeles")!), "notes-2027-01-15")
        XCTAssertEqual(NoteBackup.stem(for: Date(timeIntervalSince1970: 1_800_050_000), timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!),
                       "notes-2027-01-16", "21:53 UTC is already the next day in Vietnam")
        XCTAssertEqual(NoteBackup.day(ofFile: "notes-2026-10-18.json"), "2026-10-18")
        XCTAssertEqual(NoteBackup.day(ofFile: "notes-2026-10-18.md"), "2026-10-18")
        XCTAssertNil(NoteBackup.day(ofFile: "notes-2026-10-18.txt"))
        XCTAssertNil(NoteBackup.day(ofFile: "notes-latest.json"))
        XCTAssertNil(NoteBackup.day(ofFile: "my-notes.json"))
    }

    func testRetentionKeepsTheNewestDaysAndNeverTouchesOtherFiles() {
        let days = (1...20).map { String(format: "2026-10-%02d", $0) }
        let names = days.flatMap { ["notes-\($0).json", "notes-\($0).md"] } + ["README.txt", "notes-keep-me.json", ".DS_Store"]
        let prune = NoteBackup.filesToPrune(names, keep: 14)
        XCTAssertEqual(prune.count, 12, "six oldest days × two files")
        XCTAssertTrue(prune.allSatisfy { $0 < "notes-2026-10-07" }, "only days 01…06 go")
        XCTAssertFalse(prune.contains("README.txt")); XCTAssertFalse(prune.contains("notes-keep-me.json")); XCTAssertFalse(prune.contains(".DS_Store"))
        XCTAssertTrue(NoteBackup.filesToPrune(Array(names.prefix(10)), keep: 14).isEmpty, "fewer days than the window: nothing goes")
        XCTAssertEqual(NoteBackup.keepDays, 14)
    }
}
