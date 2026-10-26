import XCTest
@testable import XFinderLogicTests

/// XF-T32 W1 §B — pins, nicknames, emoji, path rewrites, folder relations.
final class FolderAnnotationsTests: XCTestCase {

    private func entry(_ path: String, kind: DirectoryEntry.Kind = .file) -> DirectoryEntry {
        let name: String = (path as NSString).lastPathComponent
        return DirectoryEntry(name: name, path: path, kind: kind, isPackage: false, isHidden: false, size: 1,
                              modified: Date(timeIntervalSince1970: 0), created: Date(timeIntervalSince1970: 0),
                              volumeID: 1)
    }

    // MARK: - PinRules.split

    func testSplitPinnedInPinOrderRestInListingOrder() {
        let entries: [DirectoryEntry] = ["/p/a", "/p/b", "/p/c", "/p/d"].map { entry($0) }
        let r = PinRules.split(entries, folder: "/p", pins: ["/p/c", "/p/a"])
        XCTAssertEqual(r.pinned.map(\.path), ["/p/c", "/p/a"])
        XCTAssertEqual(r.rest.map(\.path), ["/p/b", "/p/d"])
        XCTAssertEqual(r.stale, [])
        XCTAssertFalse(r.pinsFolderItself)
    }

    func testSplitStalePinsReportedAndDropped() {
        let entries: [DirectoryEntry] = ["/p/a", "/p/b"].map { entry($0) }
        let r = PinRules.split(entries, folder: "/p", pins: ["/p/gone", "/p/b", "/other/x"])
        XCTAssertEqual(r.pinned.map(\.path), ["/p/b"])
        XCTAssertEqual(r.rest.map(\.path), ["/p/a"])
        XCTAssertEqual(r.stale, ["/p/gone", "/other/x"])
    }

    func testSplitThisFolderFlagNeverStale() {
        let entries: [DirectoryEntry] = ["/p/a"].map { entry($0) }
        let r = PinRules.split(entries, folder: "/p/", pins: ["/p/a", "/p"])
        XCTAssertTrue(r.pinsFolderItself)
        XCTAssertEqual(r.stale, [])
        XCTAssertEqual(r.pinned.map(\.path), ["/p/a"])
    }

    func testSplitThisFolderEntryStandsFirstWhenListed() {
        let entries: [DirectoryEntry] = ["/p/a", "/p"].map { entry($0, kind: .directory) }
        let r = PinRules.split(entries, folder: "/p", pins: ["/p/a", "/p"])
        XCTAssertEqual(r.pinned.map(\.path), ["/p", "/p/a"])
        XCTAssertEqual(r.rest, [])
    }

    func testSplitDuplicateAndTrailingSlashPinsCountOnce() {
        let entries: [DirectoryEntry] = ["/p/a", "/p/b"].map { entry($0) }
        let r = PinRules.split(entries, folder: "/p", pins: ["/p/a", "/p/a/", "/p/a"])
        XCTAssertEqual(r.pinned.map(\.path), ["/p/a"])
        XCTAssertEqual(r.rest.map(\.path), ["/p/b"])
        XCTAssertEqual(r.stale, [])
    }

    func testSplitNoPinsKeepsListing() {
        let entries: [DirectoryEntry] = ["/p/b", "/p/a"].map { entry($0) }
        let r = PinRules.split(entries, folder: "/p", pins: [])
        XCTAssertEqual(r.pinned, [])
        XCTAssertEqual(r.rest.map(\.path), ["/p/b", "/p/a"])
    }

    // MARK: - PinRules.toggled / moved

    func testToggleAddsAtEndThenRemoves() {
        let added: [String] = PinRules.toggled(["/p/a"], path: "/p/b")
        XCTAssertEqual(added, ["/p/a", "/p/b"])
        XCTAssertEqual(PinRules.toggled(added, path: "/p/a/"), ["/p/b"])
    }

    func testToggleRemovesEveryDuplicate() {
        XCTAssertEqual(PinRules.toggled(["/p/a", "/p/b", "/p/a"], path: "/p/a"), ["/p/b"])
    }

    func testToggleRespectsCap() {
        let full: [String] = (0..<PinRules.maxPinsPerFolder).map { "/p/\($0)" }
        XCTAssertEqual(PinRules.toggled(full, path: "/p/new"), full)
        XCTAssertEqual(PinRules.toggled(full, path: "/p/3").count, PinRules.maxPinsPerFolder - 1)
        let almost: [String] = Array(full.dropLast())
        XCTAssertEqual(PinRules.toggled(almost, path: "/p/new").last, "/p/new")
    }

    func testToggleEmptyPathUnchanged() {
        XCTAssertEqual(PinRules.toggled(["/p/a"], path: ""), ["/p/a"])
    }

    func testMoved() {
        let pins: [String] = ["a", "b", "c", "d"]
        XCTAssertEqual(PinRules.moved(pins, from: 0, to: 2), ["b", "c", "a", "d"])
        XCTAssertEqual(PinRules.moved(pins, from: 3, to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(PinRules.moved(pins, from: 1, to: 99), ["a", "c", "d", "b"])
        XCTAssertEqual(PinRules.moved(pins, from: 4, to: 0), pins)
        XCTAssertEqual(PinRules.moved(pins, from: -1, to: 0), pins)
        XCTAssertEqual(PinRules.moved(pins, from: 1, to: -1), pins)
        XCTAssertEqual(PinRules.moved(pins, from: 2, to: 2), pins)
        XCTAssertEqual(PinRules.moved([], from: 0, to: 0), [])
    }

    // MARK: - NicknameRules

    func testNicknameTrimsAndCollapsesWhitespace() {
        XCTAssertEqual(NicknameRules.normalized("  Dự án\n\tchính  "), "Dự án chính")
        XCTAssertEqual(NicknameRules.normalized("a\r\n\r\nb"), "a b")
        XCTAssertEqual(NicknameRules.normalized("a   b"), "a b")
    }

    func testNicknameBlankIsNil() {
        XCTAssertNil(NicknameRules.normalized(""))
        XCTAssertNil(NicknameRules.normalized("   \n\t "))
        XCTAssertNil(NicknameRules.normalized("\u{0}\u{7}"))
    }

    func testNicknameCutAtMaxLengthCharacters() {
        let long: String = String(repeating: "ế", count: 80)
        XCTAssertEqual(NicknameRules.normalized(long)?.count, NicknameRules.maxLength)
        let family: String = String(repeating: "👨‍👩‍👧", count: 70)
        let cut: String? = NicknameRules.normalized(family)
        XCTAssertEqual(cut?.count, NicknameRules.maxLength)
        XCTAssertEqual(cut, String(repeating: "👨‍👩‍👧", count: 60))
        // A cut landing on a space leaves no trailing space.
        let spaced: String = String(repeating: "a", count: 59) + " bcd"
        XCTAssertEqual(NicknameRules.normalized(spaced), String(repeating: "a", count: 59))
        let exact: String = String(repeating: "x", count: 60)
        XCTAssertEqual(NicknameRules.normalized(exact), exact)
    }

    func testSearchKeyCombinesFoldedNameAndNickname() {
        XCTAssertEqual(NicknameRules.searchKey(name: "Đơn.pdf", nickname: nil), EntryRules.foldBytes("Đơn.pdf"))
        XCTAssertEqual(NicknameRules.searchKey(name: "Đơn.pdf", nickname: "   "), EntryRules.foldBytes("Đơn.pdf"))
        let key: [UInt8] = NicknameRules.searchKey(name: "Đơn.pdf", nickname: " Hoá Đơn\nThuế ")
        XCTAssertEqual(key, EntryRules.foldBytes("Đơn.pdf") + [0x00] + Array("hoa don thue".utf8))
    }

    // MARK: - EmojiRules

    func testEmojiAccepts() {
        for e in ["👍", "👍🏽", "🇻🇳", "👨‍👩‍👧", "❤️", "1️⃣", "#️⃣", "🏴󠁧󠁢󠁥󠁮󠁧󠁿", "🏳️‍🌈", "📁"] {
            XCTAssertEqual(EmojiRules.normalized(e), e, e)
        }
        XCTAssertEqual(EmojiRules.normalized("  🚀 \n"), "🚀")
    }

    func testEmojiRejects() {
        for s in ["", " ", "a", "A", "1", "#", "*", "©", "™", "ab", "👍👍", "🇻", "a\u{301}", "👍\u{FE0E}",
                  "1\u{FE0F}", "đ", "日"] {
            XCTAssertNil(EmojiRules.normalized(s), s)
        }
    }

    // MARK: - PathRewrite

    func testRewriteSelfAndDescendants() {
        XCTAssertEqual(PathRewrite.rewritten("/a/b", from: "/a/b", to: "/x/y"), "/x/y")
        XCTAssertEqual(PathRewrite.rewritten("/a/b/c/d.txt", from: "/a/b", to: "/x/y"), "/x/y/c/d.txt")
    }

    func testRewriteSiblingPrefixIsUnrelated() {
        XCTAssertNil(PathRewrite.rewritten("/a/bc", from: "/a/b", to: "/x"))
        XCTAssertNil(PathRewrite.rewritten("/a/bc/d", from: "/a/b", to: "/x"))
        XCTAssertNil(PathRewrite.rewritten("/a", from: "/a/b", to: "/x"))
    }

    func testRewriteTrailingSlashes() {
        XCTAssertEqual(PathRewrite.rewritten("/a/b/", from: "/a/b", to: "/x"), "/x")
        XCTAssertEqual(PathRewrite.rewritten("/a/b/c", from: "/a/b/", to: "/x/"), "/x/c")
        XCTAssertEqual(PathRewrite.rewritten("/a/b//", from: "/a/b//", to: "/x"), "/x")
    }

    func testRewriteRootEdges() {
        XCTAssertEqual(PathRewrite.rewritten("/a/b", from: "/a", to: "/"), "/b")
        XCTAssertEqual(PathRewrite.rewritten("/a/b", from: "/", to: "/m"), "/m/a/b")
        XCTAssertEqual(PathRewrite.rewritten("/", from: "/", to: "/m"), "/m")
    }

    func testRewriteEmptyArgumentsNil() {
        XCTAssertNil(PathRewrite.rewritten("", from: "/a", to: "/b"))
        XCTAssertNil(PathRewrite.rewritten("/a", from: "", to: "/b"))
        XCTAssertNil(PathRewrite.rewritten("/a", from: "/a", to: ""))
    }

    // MARK: - RelationRules

    func testAddRelationRejectsSelfAndDuplicates() {
        var r: [FolderRelation] = RelationRules.adding([], a: "/a", b: "/b")
        XCTAssertEqual(r.count, 1)
        r = RelationRules.adding(r, a: "/b/", b: "/a")
        XCTAssertEqual(r.count, 1)
        r = RelationRules.adding(r, a: "/a", b: "/b")
        XCTAssertEqual(r.count, 1)
        r = RelationRules.adding(r, a: "/c", b: "/c/")
        XCTAssertEqual(r.count, 1)
        r = RelationRules.adding(r, a: "", b: "/c")
        XCTAssertEqual(r.count, 1)
        r = RelationRules.adding(r, a: "/a", b: "/c/")
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[1].b, "/c")
        XCTAssertNotEqual(r[0].id, r[1].id)
    }

    func testRelatedIsTwoWay() {
        var r: [FolderRelation] = RelationRules.adding([], a: "/a", b: "/b")
        r = RelationRules.adding(r, a: "/c", b: "/a")
        r = RelationRules.adding(r, a: "/b", b: "/c")
        XCTAssertEqual(RelationRules.related(to: "/a", in: r), ["/b", "/c"])
        XCTAssertEqual(RelationRules.related(to: "/b/", in: r), ["/a", "/c"])
        XCTAssertEqual(RelationRules.related(to: "/ab", in: r), [])
    }

    func testRelatedIgnoresHandBuiltSelfLinksAndDuplicates() {
        let r: [FolderRelation] = [
            FolderRelation(id: UUID(), a: "/a", b: "/a"),
            FolderRelation(id: UUID(), a: "/a", b: "/b"),
            FolderRelation(id: UUID(), a: "/b/", b: "/a"),
        ]
        XCTAssertEqual(RelationRules.related(to: "/a", in: r), ["/b"])
    }
}
