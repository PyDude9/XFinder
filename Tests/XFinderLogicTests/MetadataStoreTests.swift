import Foundation
import SQLite3
import XCTest

/// XF-T32 W1 §C — the sidecar metadata SQLite. Every test gets its own temporary database file.
final class MetadataStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private var databaseURL: URL { directory.appendingPathComponent("metadata.sqlite") }
    private func makeStore() -> MetadataStore { MetadataStore(databaseURL: databaseURL) }

    private func definition(options: Int) -> PropertyDefinition {
        PropertyDefinition(id: UUID(), name: "Status", kind: .select,
                           options: (0..<options).map { PropertyOption(id: UUID(), title: "O\($0)", color: .blue) })
    }

    private func report(_ line: String) {
        FileHandle.standardError.write(Data("[MetadataStoreTests] \(line)\n".utf8))
    }

    // MARK: - Catalog

    func testEmptyStoreReturnsEmptyEverything() async {
        let store: MetadataStore = makeStore()
        let catalog: PropertyCatalog = await store.catalog()
        XCTAssertEqual(catalog.definitions, [])
        let all: [UUID: [String: UUID]] = await store.allSelections()
        XCTAssertTrue(all.isEmpty)
        let pins: [String] = await store.pins(in: "/a")
        XCTAssertEqual(pins, [])
        let nick: String? = await store.nickname(for: "/a")
        XCTAssertNil(nick)
        let emoji: String? = await store.emoji(for: "/a")
        XCTAssertNil(emoji)
        let relations: [FolderRelation] = await store.relations()
        XCTAssertEqual(relations, [])
        let token: Int = await store.changeToken()
        XCTAssertEqual(token, 0)
    }

    func testCatalogRoundTripsThroughEncodedBytes() async {
        let store: MetadataStore = makeStore()
        var catalog: PropertyCatalog = PropertyCatalog()
        catalog.definitions = [definition(options: 3)]
        await store.saveCatalog(catalog)
        let read: PropertyCatalog = await store.catalog()
        XCTAssertEqual(read, PropertyCatalog.decode(catalog.encoded()))
        let reopened: PropertyCatalog = await makeStore().catalog()
        XCTAssertEqual(reopened, PropertyCatalog.decode(catalog.encoded()))
    }

    func testSaveCatalogDropsOrphanSelectionsAndFolderProperties() async {
        let store: MetadataStore = makeStore()
        let keep: PropertyDefinition = definition(options: 2)
        let gone: PropertyDefinition = definition(options: 1)
        var catalog: PropertyCatalog = PropertyCatalog()
        catalog.definitions = [keep, gone]
        await store.saveCatalog(catalog)
        await store.select(path: "/a/x", property: keep.id, option: keep.options[0].id)
        await store.select(path: "/a/y", property: keep.id, option: keep.options[1].id)
        await store.select(path: "/a/z", property: gone.id, option: gone.options[0].id)
        await store.setFolderProperties("/a", [(property: keep.id, showInView: true), (property: gone.id, showInView: false)])

        var trimmed: PropertyDefinition = keep
        trimmed.options.removeLast()
        catalog.definitions = [trimmed]
        await store.saveCatalog(catalog)

        let all: [UUID: [String: UUID]] = await store.allSelections()
        XCTAssertEqual(all, [keep.id: ["/a/x": keep.options[0].id]])
        let shown: [(property: UUID, showInView: Bool)] = await store.folderProperties("/a")
        XCTAssertEqual(shown.map(\.property), [keep.id])
        XCTAssertEqual(shown.map(\.showInView), [true])
    }

    // MARK: - Selections

    func testSelectReplaceAndClear() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o1: UUID = UUID(), o2: UUID = UUID()
        await store.select(path: "/a/x", property: p, option: o1)
        await store.select(path: "/a/x", property: p, option: o2)
        var byProperty: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(byProperty, ["/a/x": o2])
        await store.select(path: "/a/x", property: p, option: nil)
        byProperty = await store.selections(property: p)
        XCTAssertEqual(byProperty, [:])
    }

    func testSelectionsInFolderAreDirectChildrenOnly() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), q: UUID = UUID(), o: UUID = UUID()
        await store.select(path: "/a/x", property: p, option: o)
        await store.select(path: "/a/y/", property: q, option: o)
        await store.select(path: "/a/y/deep", property: p, option: o)
        await store.select(path: "/ab/z", property: p, option: o)
        let inA: [UUID: [String: UUID]] = await store.selections(in: "/a/")
        XCTAssertEqual(inA, [p: ["/a/x": o], q: ["/a/y": o]])
        let atRoot: [UUID: [String: UUID]] = await store.selections(in: "/")
        XCTAssertEqual(atRoot, [:])
        await store.select(path: "/top", property: p, option: o)
        let root: [UUID: [String: UUID]] = await store.selections(in: "/")
        XCTAssertEqual(root, [p: ["/top": o]])
    }

    func testFolderPropertiesKeepOrderAndDropDuplicates() async {
        let store: MetadataStore = makeStore()
        let a: UUID = UUID(), b: UUID = UUID()
        await store.setFolderProperties("/f", [(property: b, showInView: false), (property: a, showInView: true),
                                               (property: b, showInView: true)])
        let list: [(property: UUID, showInView: Bool)] = await store.folderProperties("/f")
        XCTAssertEqual(list.map(\.property), [b, a])
        XCTAssertEqual(list.map(\.showInView), [false, true])
        await store.setFolderProperties("/f", [])
        let empty: [(property: UUID, showInView: Bool)] = await store.folderProperties("/f")
        XCTAssertTrue(empty.isEmpty)
    }

    // MARK: - Pins / nicknames / emoji / relations

    func testPinsKeepOrderDedupeAndCap() async {
        let store: MetadataStore = makeStore()
        await store.setPins(["/f/b", "/f/a", "/f/b/", "/f"], in: "/f")
        var pins: [String] = await store.pins(in: "/f/")
        XCTAssertEqual(pins, ["/f/b", "/f/a", "/f"])
        let many: [String] = (0..<(PinRules.maxPinsPerFolder + 5)).map { "/f/\($0)" }
        await store.setPins(many, in: "/f")
        pins = await store.pins(in: "/f")
        XCTAssertEqual(pins, Array(many.prefix(PinRules.maxPinsPerFolder)))
        let other: [String] = await store.pins(in: "/g")
        XCTAssertEqual(other, [])
    }

    func testNicknamesSetClearAndScope() async {
        let store: MetadataStore = makeStore()
        await store.setNickname("Báo cáo", for: "/a/report.pdf")
        await store.setNickname("Deep", for: "/a/sub/x")
        await store.setNickname("   ", for: "/a/blank")
        let one: String? = await store.nickname(for: "/a/report.pdf")
        XCTAssertEqual(one, "Báo cáo")
        let inA: [String: String] = await store.nicknames(in: "/a")
        XCTAssertEqual(inA, ["/a/report.pdf": "Báo cáo"])
        let all: [String: String] = await store.allNicknames()
        XCTAssertEqual(all, ["/a/report.pdf": "Báo cáo", "/a/sub/x": "Deep"])
        await store.setNickname(nil, for: "/a/report.pdf")
        let cleared: String? = await store.nickname(for: "/a/report.pdf")
        XCTAssertNil(cleared)
    }

    func testEmojiSetReplaceClear() async {
        let store: MetadataStore = makeStore()
        await store.setEmoji("👨‍👩‍👧", for: "/a")
        var e: String? = await store.emoji(for: "/a/")
        XCTAssertEqual(e, "👨‍👩‍👧")
        await store.setEmoji("🇻🇳", for: "/a")
        e = await store.emoji(for: "/a")
        XCTAssertEqual(e, "🇻🇳")
        await store.setEmoji("", for: "/a")
        e = await store.emoji(for: "/a")
        XCTAssertNil(e)
    }

    func testRelationsReplaceAllAndKeepOrder() async {
        let store: MetadataStore = makeStore()
        let r1: FolderRelation = FolderRelation(id: UUID(), a: "/x", b: "/y")
        let r2: FolderRelation = FolderRelation(id: UUID(), a: "/y", b: "/z")
        await store.setRelations([r1, r2])
        var read: [FolderRelation] = await store.relations()
        XCTAssertEqual(read, [r1, r2])
        await store.setRelations([r2])
        read = await store.relations()
        XCTAssertEqual(read, [r2])
    }

    // MARK: - Move / remove

    func testItemMovedRewritesEveryTableAndOnlyTheSubtree() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        await store.select(path: "/a/b", property: p, option: o)
        await store.select(path: "/a/b/c", property: p, option: o)
        await store.select(path: "/a/bc", property: p, option: o)
        await store.setNickname("B", for: "/a/b")
        await store.setNickname("C", for: "/a/b/c")
        await store.setNickname("BC", for: "/a/bc")
        await store.setPins(["/a/b/c", "/a/b"], in: "/a/b")
        await store.setPins(["/a/b"], in: "/a")
        await store.setEmoji("📁", for: "/a/b")
        await store.setEmoji("📁", for: "/a/bc")
        let showP: [(property: UUID, showInView: Bool)] = [(property: p, showInView: true)]
        await store.setFolderProperties("/a/b", showP)
        let rel: FolderRelation = FolderRelation(id: UUID(), a: "/a/b/c", b: "/a/bc")
        await store.setRelations([rel])

        await store.itemMoved(from: "/a/b", to: "/z/new")

        let all: [UUID: [String: UUID]] = await store.allSelections()
        XCTAssertEqual(all, [p: ["/z/new": o, "/z/new/c": o, "/a/bc": o]])
        let inZ: [UUID: [String: UUID]] = await store.selections(in: "/z")
        XCTAssertEqual(inZ, [p: ["/z/new": o]], "the moved item's own parent_path follows it")
        let inNew: [UUID: [String: UUID]] = await store.selections(in: "/z/new")
        XCTAssertEqual(inNew, [p: ["/z/new/c": o]], "descendants' parent_path is rewritten")
        let inA: [UUID: [String: UUID]] = await store.selections(in: "/a")
        XCTAssertEqual(inA, [p: ["/a/bc": o]])
        let nicks: [String: String] = await store.allNicknames()
        XCTAssertEqual(nicks, ["/z/new": "B", "/z/new/c": "C", "/a/bc": "BC"])
        let nicksInNew: [String: String] = await store.nicknames(in: "/z/new")
        XCTAssertEqual(nicksInNew, ["/z/new/c": "C"])
        let pinsNew: [String] = await store.pins(in: "/z/new")
        XCTAssertEqual(pinsNew, ["/z/new/c", "/z/new"])
        let pinsA: [String] = await store.pins(in: "/a")
        XCTAssertEqual(pinsA, ["/z/new"])
        let oldPins: [String] = await store.pins(in: "/a/b")
        XCTAssertEqual(oldPins, [])
        let emojiNew: String? = await store.emoji(for: "/z/new")
        XCTAssertEqual(emojiNew, "📁")
        let emojiBC: String? = await store.emoji(for: "/a/bc")
        XCTAssertEqual(emojiBC, "📁")
        let props: [(property: UUID, showInView: Bool)] = await store.folderProperties("/z/new")
        XCTAssertEqual(props.map(\.property), [p])
        let relations: [FolderRelation] = await store.relations()
        XCTAssertEqual(relations, [FolderRelation(id: rel.id, a: "/z/new/c", b: "/a/bc")])
    }

    func testItemMovedHandlesQuoteAndLikeWildcards() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        let weird: String = "/d/it's 100%_done"
        await store.select(path: weird, property: p, option: o)
        await store.select(path: weird + "/child", property: p, option: o)
        await store.select(path: "/d/itXs 100ab_done/child", property: p, option: o)
        await store.select(path: "/d/it's 100%_doneX", property: p, option: o)
        await store.itemMoved(from: weird, to: "/d/moved")
        let all: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(Set(all.keys), ["/d/moved", "/d/moved/child", "/d/itXs 100ab_done/child", "/d/it's 100%_doneX"])
        await store.itemRemoved("/d/it's 100%_doneX")
        let after: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(Set(after.keys), ["/d/moved", "/d/moved/child", "/d/itXs 100ab_done/child"])
    }

    func testItemMovedOverwritesStaleRowAtDestination() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), old: UUID = UUID(), fresh: UUID = UUID()
        await store.select(path: "/dst", property: p, option: old)
        await store.setNickname("stale", for: "/dst")
        await store.select(path: "/src", property: p, option: fresh)
        await store.setNickname("live", for: "/src")
        await store.itemMoved(from: "/src", to: "/dst")
        let all: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(all, ["/dst": fresh])
        let nick: String? = await store.nickname(for: "/dst")
        XCTAssertEqual(nick, "live")
    }

    func testItemMovedIgnoresRootSameAndEmpty() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        await store.select(path: "/a", property: p, option: o)
        await store.itemMoved(from: "/", to: "/x")
        await store.itemMoved(from: "/a", to: "/a/")
        await store.itemMoved(from: "", to: "/x")
        await store.itemRemoved("/")
        await store.itemRemoved("")
        let all: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(all, ["/a": o])
    }

    func testItemRemovedDeletesSubtreeEverywhere() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        await store.select(path: "/a/b", property: p, option: o)
        await store.select(path: "/a/b/c", property: p, option: o)
        await store.select(path: "/a/bc", property: p, option: o)
        await store.setNickname("C", for: "/a/b/c")
        await store.setPins(["/a/b"], in: "/a")
        await store.setPins(["/a/b/c"], in: "/a/b")
        await store.setEmoji("📁", for: "/a/b")
        await store.setFolderProperties("/a/b", [(property: p, showInView: true)])
        await store.setRelations([FolderRelation(id: UUID(), a: "/a/b/c", b: "/q"),
                                  FolderRelation(id: UUID(), a: "/q", b: "/a/bc")])
        await store.itemRemoved("/a/b/")
        let all: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(all, ["/a/bc": o])
        let nicks: [String: String] = await store.allNicknames()
        XCTAssertEqual(nicks, [:])
        let pinsA: [String] = await store.pins(in: "/a")
        XCTAssertEqual(pinsA, [])
        let pinsB: [String] = await store.pins(in: "/a/b")
        XCTAssertEqual(pinsB, [])
        let emoji: String? = await store.emoji(for: "/a/b")
        XCTAssertNil(emoji)
        let props: [(property: UUID, showInView: Bool)] = await store.folderProperties("/a/b")
        XCTAssertTrue(props.isEmpty)
        let relations: [FolderRelation] = await store.relations()
        XCTAssertEqual(relations.map(\.b), ["/a/bc"])
    }

    // MARK: - Change token / concurrency / persistence

    func testChangeTokenIncrementsOnEveryWrite() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        var last: Int = await store.changeToken()
        func expectBump(_ label: String) async {
            let now: Int = await store.changeToken()
            XCTAssertGreaterThan(now, last, label)
            last = now
        }
        await store.saveCatalog(PropertyCatalog()); await expectBump("saveCatalog")
        await store.select(path: "/a", property: p, option: o); await expectBump("select")
        await store.select(path: "/a", property: p, option: nil); await expectBump("select nil")
        await store.setFolderProperties("/a", []); await expectBump("setFolderProperties")
        await store.setPins([], in: "/a"); await expectBump("setPins")
        await store.setNickname("n", for: "/a"); await expectBump("setNickname")
        await store.setEmoji("🙂", for: "/a"); await expectBump("setEmoji")
        await store.setRelations([]); await expectBump("setRelations")
        await store.itemMoved(from: "/a", to: "/b"); await expectBump("itemMoved")
        await store.itemRemoved("/b"); await expectBump("itemRemoved")
        let read: Int = await store.changeToken()
        _ = await store.allSelections()
        let afterRead: Int = await store.changeToken()
        XCTAssertEqual(read, afterRead, "reads do not bump the token")
    }

    func testConcurrentWritesFromTwoTasksAllLand() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        async let first: Void = {
            for i in 0..<200 { await store.select(path: "/one/\(i)", property: p, option: o) }
        }()
        async let second: Void = {
            for i in 0..<200 { await store.setNickname("n\(i)", for: "/two/\(i)") }
        }()
        _ = await (first, second)
        let selections: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(selections.count, 200)
        let nicks: [String: String] = await store.allNicknames()
        XCTAssertEqual(nicks.count, 200)
        let token: Int = await store.changeToken()
        XCTAssertEqual(token, 400)
    }

    func testDataPersistsAcrossInstancesAndSchemaVersionIsSet() async throws {
        let p: UUID = UUID(), o: UUID = UUID()
        do {
            let store: MetadataStore = makeStore()
            await store.select(path: "/a/x", property: p, option: o)
            await store.setNickname("X", for: "/a/x")
        }
        let reopened: MetadataStore = makeStore()
        let all: [UUID: [String: UUID]] = await reopened.allSelections()
        XCTAssertEqual(all, [p: ["/a/x": o]])
        let nick: String? = await reopened.nickname(for: "/a/x")
        XCTAssertEqual(nick, "X")

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close_v2(handle) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(stmt, 0), MetadataStore.schemaVersion)
    }

    // MARK: - Corruption

    func testCorruptFileIsRenamedNeverDeletedAndStoreRecreates() async throws {
        let garbage: Data = Data((0..<8192).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try garbage.write(to: databaseURL)
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        let empty: [UUID: [String: UUID]] = await store.allSelections()
        XCTAssertTrue(empty.isEmpty)
        await store.select(path: "/a", property: p, option: o)
        let read: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(read, ["/a": o])

        let names: [String] = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined: [String] = names.filter { $0.hasPrefix("metadata.sqlite.corrupt-") }
        XCTAssertEqual(quarantined.count, 1, "names: \(names)")
        if let name: String = quarantined.first {
            let suffix: Substring = name.dropFirst("metadata.sqlite.corrupt-".count)
            XCTAssertNotNil(Int(suffix), "suffix is a unix timestamp")
            let kept: Data = try Data(contentsOf: directory.appendingPathComponent(name))
            XCTAssertEqual(kept, garbage, "the corrupt bytes are preserved")
        }
    }

    // MARK: - Measurements

    func testMeasureAllSelectionsWithTenThousandRows() async {
        let store: MetadataStore = makeStore()
        let properties: [UUID] = [UUID(), UUID()]
        let options: [UUID] = [UUID(), UUID(), UUID(), UUID()]
        for i in 0..<10_000 {
            await store.select(path: "/data/folder\(i % 100)/file\(i)", property: properties[i % 2], option: options[i % 4])
        }
        _ = await store.allSelections()
        var best: Double = .infinity
        var count: Int = 0
        for _ in 0..<3 {
            let start: ContinuousClock.Instant = ContinuousClock.now
            let all: [UUID: [String: UUID]] = await store.allSelections()
            let elapsed: Duration = ContinuousClock.now - start
            best = min(best, Self.milliseconds(elapsed))
            count = all.values.reduce(0) { $0 + $1.count }
        }
        XCTAssertEqual(count, 10_000)
        report(String(format: "allSelections 10000 rows: %.2f ms (best of 3)", best))
        XCTAssertLessThan(best, 300, "contract target < 30 ms; generous bound for debug builds")
    }

    func testMeasureItemMovedWithOneThousandDescendants() async {
        let store: MetadataStore = makeStore()
        let p: UUID = UUID(), o: UUID = UUID()
        for i in 0..<1_000 {
            let path: String = "/src/tree/sub\(i % 20)/file\(i)"
            await store.select(path: path, property: p, option: o)
            await store.setNickname("n\(i)", for: path)
        }
        for i in 0..<1_000 { await store.select(path: "/other/file\(i)", property: p, option: o) }
        let start: ContinuousClock.Instant = ContinuousClock.now
        await store.itemMoved(from: "/src/tree", to: "/dst/tree")
        let ms: Double = Self.milliseconds(ContinuousClock.now - start)
        report(String(format: "itemMoved 1000 descendants (x2 tables) + 1000 unrelated: %.2f ms", ms))
        let all: [String: UUID] = await store.selections(property: p)
        XCTAssertEqual(all.keys.filter { $0.hasPrefix("/dst/tree/") }.count, 1_000)
        XCTAssertEqual(all.keys.filter { $0.hasPrefix("/src/") }.count, 0)
        let nicks: [String: String] = await store.nicknames(in: "/dst/tree/sub3")
        XCTAssertEqual(nicks.count, 50)
        XCTAssertLessThan(ms, 500, "contract target < 50 ms; generous bound for debug builds")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let parts: (seconds: Int64, attoseconds: Int64) = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
