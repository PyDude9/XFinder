import XCTest
import Foundation

/// XF-T28 — tests for `BrowserCommands`. Covers: (1) every chord the spec's §2.3 table requires round-trips through
/// `chord(for:)`/`command(for:)`, (2) the fixed table has no two commands sharing one chord, (3) `titleKey` covers
/// every `BrowserCommand` case, (4) `display` glyph order and named-key rendering, (5) fuzzy `score`/`rank`, and
/// (6) `commandMode`'s `>` prefix parsing.
final class BrowserCommandsTests: XCTestCase {

    // MARK: - Required chords (spec §2.3)

    /// Every bound chord the spec lists, keyed by command, so one table drives both the round-trip test below and
    /// the "exactly these commands are bound" test.
    private let requiredChords: [BrowserCommand: KeyChord] = [
        .newWindow: KeyChord("n", command: true),
        .newFolder: KeyChord("n", command: true, shift: true),
        .open: KeyChord("o", command: true),
        .openEnclosing: KeyChord("up", command: true),
        .back: KeyChord("[", command: true),
        .forward: KeyChord("]", command: true),
        .rename: KeyChord("return"),
        .duplicate: KeyChord("d", command: true),
        .moveToTrash: KeyChord("delete", command: true),
        .quickLook: KeyChord("y", command: true),
        .copy: KeyChord("c", command: true),
        .paste: KeyChord("v", command: true),
        .pasteMove: KeyChord("v", command: true, option: true),
        .copyPath: KeyChord("c", command: true, option: true),
        .toggleHidden: KeyChord(".", command: true, shift: true),
        .selectAll: KeyChord("a", command: true),
        .undo: KeyChord("z", command: true),
        .viewIcons: KeyChord("1", command: true),
        .viewList: KeyChord("2", command: true),
        .viewColumns: KeyChord("3", command: true),
        .viewGallery: KeyChord("4", command: true),
        .find: KeyChord("f", command: true),   // Q-T30-2: ⌘F is Find alone now; filter has no chord.
        .editLocation: KeyChord("l", command: true, control: true),
        .goToFolder: KeyChord("g", command: true, shift: true),
        .quickOpen: KeyChord("p", command: true, control: true),
        .commandPalette: KeyChord("p", command: true, shift: true, control: true),
        .splitRight: KeyChord("right", command: true, option: true, control: true),
        .splitLeft: KeyChord("left", command: true, option: true, control: true),
        .splitDown: KeyChord("down", command: true, option: true, control: true),
        .splitUp: KeyChord("up", command: true, option: true, control: true),
        .closePane: KeyChord("w", command: true, option: true, control: true),
        .equalizePanes: KeyChord("=", command: true, option: true, control: true),
        .zoomPane: KeyChord("return", command: true, shift: true),
        .nextPane: KeyChord("]", command: true, control: true),
        .previousPane: KeyChord("[", command: true, control: true),
        .copyToOtherPane: KeyChord("c", command: true, shift: true, control: true),
        .moveToOtherPane: KeyChord("m", command: true, shift: true, control: true),
        .addToShelf: KeyChord("s", command: true, control: true),
        .toggleShelf: KeyChord("b", command: true, option: true),
        .operations: KeyChord("o", command: true, option: true),
        .batchRename: KeyChord("r", command: true, control: true),
        .getInfo: KeyChord("i", command: true),   // XF-T28 Wave 4
        .closeWindow: KeyChord("w", command: true),
        // XF-T30 W1 (contract §2):
        .newWindowTab: KeyChord("t", command: true),
        .newPaneTab: KeyChord("t", command: true, option: true, control: true),
        .nextPaneTab: KeyChord("]", command: true, option: true),
        .previousPaneTab: KeyChord("[", command: true, option: true),
        .moveTabToNewPaneRight: KeyChord("right", command: true, shift: true, option: true),
        .moveTabToNewPaneBelow: KeyChord("down", command: true, shift: true, option: true),
        .paneLeft: KeyChord("left", command: true, shift: true, control: true),
        .paneRight: KeyChord("right", command: true, shift: true, control: true),
        .paneAbove: KeyChord("up", command: true, shift: true, control: true),
        .paneBelow: KeyChord("down", command: true, shift: true, control: true),
        .togglePathBar: KeyChord("p", command: true, option: true),
        .toggleStatusBar: KeyChord("/", command: true),
        .toggleToolbar: KeyChord("t", command: true, option: true),
        .toggleSidebar: KeyChord("s", command: true, option: true),
        .useGroups: KeyChord("0", command: true, control: true),
    ]

    /// Commands the spec explicitly says have no chord — palette/menu only.
    private let unboundCommands: Set<BrowserCommand> = [
        .presetSingle, .presetSideBySide, .presetStacked, .presetGrid,
        .compress, .saveWorkspace, .openWorkspace, .downloadNow, .removeDownload, .showInFinder,
        // XF-T30 W1 (contract §2's "Không phím" list):
        .filter, .closePaneTab, .moveTabToNextPane, .swapWithNextPane, .moveTabToWindow,
        .makePaneWider, .makePaneNarrower, .makePaneTaller, .makePaneShorter,
        .toggleLocationBar, .customizeToolbar, .openInNewTab, .openInNewWindow,
    ]

    func testEveryRequiredChordRoundTrips() {
        for (command, expected) in requiredChords {
            XCTAssertEqual(BrowserCommands.chord(for: command), expected, "chord(for: \(command))")
            XCTAssertEqual(BrowserCommands.command(for: expected), command, "command(for: \(expected)) via \(command)")
        }
    }

    func testRequiredAndUnboundCommandsPartitionAllCases() {
        // Every BrowserCommand is either in the required-chord table or explicitly unbound — if the contract gains
        // a new case, this test fails until it's classified one way or the other.
        let allCases = Set(BrowserCommand.allCases)
        let bound = Set(requiredChords.keys)
        XCTAssertEqual(bound.union(unboundCommands), allCases)
        XCTAssertTrue(bound.isDisjoint(with: unboundCommands))
    }

    func testUnboundCommandsHaveNoChord() {
        for command in unboundCommands {
            XCTAssertNil(BrowserCommands.chord(for: command), "\(command) should have no chord")
        }
    }

    /// Q-T30-2: ⌘F is Find alone (FileOctopus parity); the old XF-T28 split of ⌘F/⌥⌘F between filter/find is gone —
    /// filter has no chord at all now (palette/menu only).
    func testCommandFQ_T30_2FindAloneFilterUnbound() {
        XCTAssertEqual(BrowserCommands.command(for: KeyChord("f", command: true)), .find)
        XCTAssertNil(BrowserCommands.chord(for: .filter))
    }

    func testOpenSecondaryChordCommandDown() {
        // ⌘↓ is Finder's own "open" convention — a secondary chord not reported by chord(for:).
        let secondary = KeyChord("down", command: true)
        XCTAssertEqual(BrowserCommands.command(for: secondary), .open)
        XCTAssertNotEqual(BrowserCommands.chord(for: .open), secondary, "chord(for:) reports only the primary chord")
    }

    func testUnboundChordReturnsNilCommand() {
        let nothing = KeyChord("q", command: true, shift: true, option: true, control: true)
        XCTAssertNil(BrowserCommands.command(for: nothing))
    }

    func testSpaceIsNotBoundHereViewDecidesQuickLook() {
        // Spec §2.3: Space is only Quick Look when the view is not in a text field — that decision belongs to the
        // view, not this table, so a bare Space chord must not resolve to any command.
        XCTAssertNil(BrowserCommands.command(for: KeyChord("space")))
    }

    // MARK: - No two commands share a chord

    func testNoTwoCommandsShareAChord() {
        var seen: [KeyChord: BrowserCommand] = [:]
        for command in BrowserCommand.allCases {
            guard let chord = BrowserCommands.chord(for: command) else { continue }
            if let existing = seen[chord] {
                XCTFail("\(chord) is bound to both \(existing) and \(command)")
            }
            seen[chord] = command
        }
    }

    // MARK: - titleKey

    func testTitleKeyIsNonEmptyForEveryCommand() {
        for command in BrowserCommand.allCases {
            let key = BrowserCommands.titleKey(command)
            XCTAssertFalse(key.isEmpty, "\(command) has an empty titleKey")
        }
    }

    func testTitleKeyIsStableSpotCheck() {
        XCTAssertEqual(BrowserCommands.titleKey(.newFolder), "Thư mục mới")
        XCTAssertEqual(BrowserCommands.titleKey(.newWindow), "Cửa sổ mới")
        XCTAssertEqual(BrowserCommands.titleKey(.moveToTrash), "Chuyển vào Thùng rác")
    }

    func testTitleKeysAreUniquePerCommand() {
        // Not a hard requirement of the contract, but two commands sharing a title would be a real authoring bug
        // (the palette would show indistinguishable rows) — assert it explicitly rather than hoping nobody notices.
        var seen: [String: BrowserCommand] = [:]
        for command in BrowserCommand.allCases {
            let key = BrowserCommands.titleKey(command)
            if let existing = seen[key] {
                XCTFail("\(command) and \(existing) share titleKey \"\(key)\"")
            }
            seen[key] = command
        }
    }

    // MARK: - display

    func testDisplayModifierOrderIsControlOptionShiftCommand() {
        let chord = KeyChord("right", command: true, shift: true, option: true, control: true)
        XCTAssertEqual(BrowserCommands.display(chord), "⌃⌥⇧⌘→")
    }

    func testDisplaySplitRight() {
        XCTAssertEqual(BrowserCommands.display(KeyChord("right", command: true, option: true, control: true)), "⌃⌥⌘→")
    }

    func testDisplayZoomPane() {
        XCTAssertEqual(BrowserCommands.display(KeyChord("return", command: true, shift: true)), "⇧⌘↩")
    }

    func testDisplayMoveToTrash() {
        XCTAssertEqual(BrowserCommands.display(KeyChord("delete", command: true)), "⌘⌫")
    }

    func testDisplayPlainLetterUppercases() {
        XCTAssertEqual(BrowserCommands.display(KeyChord("n", command: true)), "⌘N")
    }

    func testDisplayPunctuationIsLiteral() {
        XCTAssertEqual(BrowserCommands.display(KeyChord(".", command: true, shift: true)), "⇧⌘.")
        XCTAssertEqual(BrowserCommands.display(KeyChord("=", command: true, option: true, control: true)), "⌃⌥⌘=")
    }

    func testDisplayNoModifiersJustReturn() {
        XCTAssertEqual(BrowserCommands.display(KeyChord("return")), "↩")
    }

    /// `toggleStatusBar` is ⌘/ (contract §2) — "/" is a literal punctuation key, not a named glyph, and must render
    /// as itself (not uppercased, since it has no case).
    func testDisplayToggleStatusBarSlash() {
        XCTAssertEqual(BrowserCommands.display(KeyChord("/", command: true)), "⌘/")
        XCTAssertEqual(BrowserCommands.chord(for: .toggleStatusBar), KeyChord("/", command: true))
    }

    // MARK: - score / fuzzy match

    func testScoreEmptyQueryIsZero() {
        XCTAssertEqual(BrowserCommands.score(query: "", candidate: "Thư mục mới"), 0)
    }

    func testScoreEmptyTitleWithNonEmptyQueryIsNil() {
        XCTAssertNil(BrowserCommands.score(query: "a", candidate: ""))
    }

    func testScoreRequiresSubsequence() {
        XCTAssertNil(BrowserCommands.score(query: "xyz", candidate: "Thư mục mới"))
        XCTAssertNotNil(BrowserCommands.score(query: "tmm", candidate: "Thư mục mới"))
    }

    func testScoreIsCaseAndDiacriticInsensitive() {
        XCTAssertNotNil(BrowserCommands.score(query: "thu muc moi", candidate: "Thư mục mới"))
        XCTAssertNotNil(BrowserCommands.score(query: "THU", candidate: "Thư mục mới"))
    }

    /// `.diacriticInsensitive` alone does NOT fold "đ" to "d" (verified: it is not a combining-mark decomposition
    /// of "d", unlike "ư"/"ơ"/tone marks) — a user typing "doi ten" on a plain US keyboard, the common way to type
    /// Vietnamese without an IME, must still find "Đổi tên" (rename). `SidebarSearch.fold`/`CrewGate` both flatten
    /// "đ"/"Đ" by hand for exactly this reason; this is the real-world defect this test catches.
    func testScoreFoldsVietnameseDJustLikeOtherDiacritics() {
        XCTAssertNotNil(BrowserCommands.score(query: "doi ten", candidate: "Đổi tên"))
        XCTAssertNotNil(BrowserCommands.score(query: "DOI", candidate: "Đổi tên"))
        XCTAssertNotNil(BrowserCommands.score(query: "d", candidate: "Đóng cửa sổ"))
    }

    func testScorePrefixBeatsScatteredMatch() {
        // "mo" matches at the very start of "Mo nhanh" (prefix bonus) vs. the same two letters found scattered
        // mid-string in "xa mo nhanh" (no prefix bonus, no word-start bonus either since they land inside "mo").
        let prefixScore = BrowserCommands.score(query: "mo", candidate: "Mo nhanh")!
        let midScore = BrowserCommands.score(query: "mo", candidate: "xaamoo nhanh")!
        XCTAssertGreaterThan(prefixScore, midScore)
    }

    func testScoreConsecutiveBeatsScattered() {
        // Both are subsequences of "newFolder", but "new" is a consecutive run while "n", "e", "r" scattered across
        // positions 0, 1, 8... should score lower.
        let consecutive = BrowserCommands.score(query: "new", candidate: "newFolder")!
        let scattered = BrowserCommands.score(query: "nwr", candidate: "newFolder")!
        XCTAssertGreaterThan(consecutive, scattered)
    }

    func testScoreWordStartBonus() {
        // "f" matching the start of the second word ("Folder") should beat "f" matching mid-word in a string with
        // no word boundary at that position.
        let wordStart = BrowserCommands.score(query: "f", candidate: "new Folder")!
        let midWord = BrowserCommands.score(query: "f", candidate: "newxfolder")!
        XCTAssertGreaterThan(wordStart, midWord)
    }

    // MARK: - rank

    func testRankDropsNonMatchesAndOrdersByScore() {
        let items = [
            BrowserCommands.Candidate(id: "a", title: "Thư mục mới", subtitle: nil),
            BrowserCommands.Candidate(id: "b", title: "Mở nhanh", subtitle: nil),
            BrowserCommands.Candidate(id: "c", title: "Sao chép", subtitle: nil),
        ]
        let ranked = BrowserCommands.rank("mo", items, limit: 10)
        XCTAssertFalse(ranked.contains { $0.id == "c" }, "Sao chép has no 'm' and 'o' in order, should be dropped")
        XCTAssertTrue(ranked.contains { $0.id == "a" })
        XCTAssertTrue(ranked.contains { $0.id == "b" })
    }

    func testRankOrdersHighestScoreFirstNotLast() {
        // Deliberately list the WEAKEST match first in the input, so a reversed comparator (ascending instead of
        // descending) would still happen to put the best match last by coincidence of input order alone — this
        // only catches a flipped comparator because the strongest match is NOT already first in `items`.
        let items = [
            BrowserCommands.Candidate(id: "weak", title: "xxxmoxxx", subtitle: nil),   // scattered match
            BrowserCommands.Candidate(id: "strong", title: "mo", subtitle: nil),        // exact prefix match
        ]
        let ranked = BrowserCommands.rank("mo", items, limit: 10)
        XCTAssertEqual(ranked.map(\.id), ["strong", "weak"], "best score must sort first")
    }

    func testRankIsStableOnTies() {
        // Three candidates with titles that score identically for an empty query (score 0 each) must keep their
        // original relative order.
        let items = [
            BrowserCommands.Candidate(id: "first", title: "Alpha", subtitle: nil),
            BrowserCommands.Candidate(id: "second", title: "Beta", subtitle: nil),
            BrowserCommands.Candidate(id: "third", title: "Gamma", subtitle: nil),
        ]
        let ranked = BrowserCommands.rank("", items, limit: 10)
        XCTAssertEqual(ranked.map(\.id), ["first", "second", "third"])
    }

    func testRankRespectsLimit() {
        let items = (0..<10).map { BrowserCommands.Candidate(id: "\($0)", title: "Mở \($0)", subtitle: nil) }
        let ranked = BrowserCommands.rank("mo", items, limit: 3)
        XCTAssertEqual(ranked.count, 3)
    }

    func testRankEmptyItemsIsEmpty() {
        XCTAssertTrue(BrowserCommands.rank("anything", [], limit: 10).isEmpty)
    }

    // MARK: - commandMode

    func testCommandModeDetectsLeadingChevron() {
        let result = BrowserCommands.commandMode(">open")
        XCTAssertTrue(result.isCommand)
        XCTAssertEqual(result.rest, "open")
    }

    func testCommandModeStripsLeadingWhitespaceAndTrimsRest() {
        let result = BrowserCommands.commandMode("  > open folder  ")
        XCTAssertTrue(result.isCommand)
        XCTAssertEqual(result.rest, "open folder")
    }

    func testCommandModeWithoutChevronIsNotCommandMode() {
        let result = BrowserCommands.commandMode("open folder")
        XCTAssertFalse(result.isCommand)
        XCTAssertEqual(result.rest, "open folder")
    }

    func testCommandModeJustChevronGivesEmptyRest() {
        let result = BrowserCommands.commandMode(">")
        XCTAssertTrue(result.isCommand)
        XCTAssertEqual(result.rest, "")
    }

    func testCommandModeChevronNotFirstCharacterIsNotCommandMode() {
        // A ">" after other text (e.g. a pasted path fragment) must not trigger command mode.
        let result = BrowserCommands.commandMode("a > b")
        XCTAssertFalse(result.isCommand)
        XCTAssertEqual(result.rest, "a > b")
    }

    func testCommandModeEmptyQuery() {
        let result = BrowserCommands.commandMode("")
        XCTAssertFalse(result.isCommand)
        XCTAssertEqual(result.rest, "")
    }

    // MARK: - KeyChord equality (Hashable/Codable sanity, since the table and tests lean on it)

    func testKeyChordEqualityIgnoresNothingAllFieldsMatter() {
        let a = KeyChord("c", command: true)
        let b = KeyChord("c", command: true, shift: true)
        XCTAssertNotEqual(a, b)
    }

    func testKeyChordCodableRoundTrip() throws {
        let chord = KeyChord("right", command: true, option: true, control: true)
        let data = try JSONEncoder().encode(chord)
        let decoded = try JSONDecoder().decode(KeyChord.self, from: data)
        XCTAssertEqual(chord, decoded)
    }
}
