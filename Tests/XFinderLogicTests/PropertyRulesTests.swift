import XCTest
@testable import XFinderLogicTests

final class PropertyRulesTests: XCTestCase {

    // MARK: - Fixtures

    private func entry(_ name: String, dir: String = "/d") -> DirectoryEntry {
        DirectoryEntry(name: name, path: "\(dir)/\(name)", kind: .file, isPackage: false, isHidden: false, size: 0,
                       modified: Date(timeIntervalSince1970: 0), created: Date(timeIntervalSince1970: 0), volumeID: 1)
    }

    private struct Fixture {
        var catalog: PropertyCatalog
        let property: PropertyDefinition
        let todo: PropertyOption
        let doing: PropertyOption
        let done: PropertyOption
    }

    private func fixture() -> Fixture {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Status")
        let todo: PropertyOption = catalog.addOption(p.id, title: "Todo", color: .red)!
        let doing: PropertyOption = catalog.addOption(p.id, title: "Doing", color: .yellow)!
        let done: PropertyOption = catalog.addOption(p.id, title: "Done", color: .green)!
        return Fixture(catalog: catalog, property: catalog.definition(p.id)!, todo: todo, doing: doing, done: done)
    }

    // MARK: - sections

    func testSectionsFollowOptionOrderDropEmptyUnsetLast() {
        let f: Fixture = fixture()
        let es: [DirectoryEntry] = ["e", "a", "c", "b", "d"].map { entry($0) }
        let sel: [String: UUID] = ["/d/a": f.done.id, "/d/b": f.todo.id, "/d/c": f.done.id]
        let s: [PropertyRules.Section] = PropertyRules.sections(es, property: f.property, selections: sel)
        XCTAssertEqual(s.map { $0.option?.id }, [f.todo.id, f.done.id, nil])   // "Doing" empty ⇒ dropped
        XCTAssertEqual(s[0].entries.map(\.name), ["b"])
        XCTAssertEqual(s[1].entries.map(\.name), ["a", "c"])                    // incoming order kept
        XCTAssertEqual(s[2].entries.map(\.name), ["e", "d"])
    }

    func testSectionsNoUnsetSectionWhenEverythingIsSet() {
        let f: Fixture = fixture()
        let s: [PropertyRules.Section] = PropertyRules.sections([entry("a")], property: f.property,
                                                                selections: ["/d/a": f.doing.id])
        XCTAssertEqual(s.map { $0.option?.id }, [f.doing.id])
    }

    func testSectionsEmptyInputGivesNoSections() {
        let f: Fixture = fixture()
        XCTAssertEqual(PropertyRules.sections([], property: f.property, selections: ["/d/a": f.todo.id]), [])
    }

    func testSectionsOrphanSelectionCountsAsUnset() {
        var f: Fixture = fixture()
        f.catalog.removeOption(f.property.id, option: f.todo.id)
        let property: PropertyDefinition = f.catalog.definition(f.property.id)!
        let s: [PropertyRules.Section] = PropertyRules.sections([entry("a"), entry("b")], property: property,
                                                                selections: ["/d/a": f.todo.id, "/d/b": UUID()])
        XCTAssertEqual(s.count, 1)
        XCTAssertNil(s[0].option)
        XCTAssertEqual(s[0].entries.map(\.name), ["a", "b"])
    }

    func testSectionsPropertyWithNoOptionsIsAllUnset() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Empty")
        let s: [PropertyRules.Section] = PropertyRules.sections([entry("a")], property: p, selections: ["/d/a": UUID()])
        XCTAssertEqual(s.map { $0.option }, [nil])
    }

    func testSectionsTwoOptionsSameTitleStaySeparate() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "S")
        let x: PropertyOption = catalog.addOption(p.id, title: "Same", color: .red)!
        let y: PropertyOption = catalog.addOption(p.id, title: "Same", color: .blue)!
        let s: [PropertyRules.Section] = PropertyRules.sections(
            [entry("a"), entry("b")], property: catalog.definition(p.id)!, selections: ["/d/a": y.id, "/d/b": x.id])
        XCTAssertEqual(s.map { $0.option?.id }, [x.id, y.id])
        XCTAssertEqual(s.map { $0.entries.map(\.name) }, [["b"], ["a"]])
    }

    func testSectionsDuplicateOptionIDFirstWins() {
        let f: Fixture = fixture()
        var property: PropertyDefinition = f.property
        property.options.append(PropertyOption(id: f.todo.id, title: "Dup", color: .gray))
        let s: [PropertyRules.Section] = PropertyRules.sections([entry("a")], property: property,
                                                                selections: ["/d/a": f.todo.id])
        XCTAssertEqual(s.map { $0.option?.title }, ["Todo"])
    }

    func testSectionsTiming10k() {
        let f: Fixture = fixture()
        let options: [UUID] = [f.todo.id, f.doing.id, f.done.id, UUID()]
        var es: [DirectoryEntry] = []
        var sel: [String: UUID] = [:]
        es.reserveCapacity(10_000)
        for i in 0..<10_000 {
            let e: DirectoryEntry = entry("File \(i)")
            es.append(e)
            if i % 5 != 0 { sel[e.path] = options[i % options.count] }
        }
        _ = PropertyRules.sections(es, property: f.property, selections: sel)   // warm-up
        let start: UInt64 = DispatchTime.now().uptimeNanoseconds
        let s: [PropertyRules.Section] = PropertyRules.sections(es, property: f.property, selections: sel)
        let ms: Double = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertEqual(s.reduce(0) { $0 + $1.entries.count }, 10_000)
        XCTAssertEqual(s.last?.option, nil)
        XCTAssertLessThan(ms, 200, "sections(10 000) took \(ms) ms")
        // The measured number is attached to the test result (xcresult) for the report.
        add(XCTAttachment(string: String(format: "PropertyRules.sections 10k: %.2f ms", ms)))
    }

    // MARK: - option(for:)

    func testOptionForPath() {
        let f: Fixture = fixture()
        let sel: [String: UUID] = ["/d/a": f.doing.id, "/d/b": UUID()]
        XCTAssertEqual(PropertyRules.option(for: "/d/a", property: f.property, selections: sel), f.doing)
        XCTAssertNil(PropertyRules.option(for: "/d/b", property: f.property, selections: sel))   // orphan
        XCTAssertNil(PropertyRules.option(for: "/d/c", property: f.property, selections: sel))   // unset
    }

    // MARK: - liveGroups

    func testLiveGroupsSortByDisplayNameNaturally() {
        let f: Fixture = fixture()
        let pid: UUID = f.property.id
        let sel: [UUID: [String: UUID]] = [pid: [
            "/x/File 10": f.done.id, "/y/file 2": f.done.id, "/z/Zeta": f.done.id, "/w/Beta": f.done.id,
            "/q/other": f.todo.id,
        ]]
        let nick: [String: String] = ["/z/Zeta": "alpha"]
        let g: [PropertyRules.LiveGroup] = PropertyRules.liveGroups(
            catalog: f.catalog, selections: sel, nicknames: nick,
            wanted: [LiveGroupRef(propertyID: pid, optionID: f.done.id)])
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].property, f.property)
        XCTAssertEqual(g[0].option, f.done)
        XCTAssertEqual(g[0].paths, ["/z/Zeta", "/w/Beta", "/y/file 2", "/x/File 10"])
    }

    func testLiveGroupsDropStaleRefsKeepOrderDedupe() {
        var f: Fixture = fixture()
        let pid: UUID = f.property.id
        let sel: [UUID: [String: UUID]] = [pid: ["/a": f.todo.id, "/b": f.doing.id]]
        f.catalog.removeOption(pid, option: f.done.id)
        let wanted: [LiveGroupRef] = [
            LiveGroupRef(propertyID: pid, optionID: f.doing.id),
            LiveGroupRef(propertyID: pid, optionID: f.done.id),          // option deleted
            LiveGroupRef(propertyID: UUID(), optionID: f.todo.id),       // property missing
            LiveGroupRef(propertyID: pid, optionID: f.todo.id),
            LiveGroupRef(propertyID: pid, optionID: f.doing.id),         // repeat
        ]
        let g: [PropertyRules.LiveGroup] = PropertyRules.liveGroups(catalog: f.catalog, selections: sel, nicknames: [:],
                                                                    wanted: wanted)
        XCTAssertEqual(g.map(\.option.id), [f.doing.id, f.todo.id])
        XCTAssertEqual(g.map(\.paths), [["/b"], ["/a"]])
    }

    func testLiveGroupsEmptyMembersAndMissingSelections() {
        let f: Fixture = fixture()
        let g: [PropertyRules.LiveGroup] = PropertyRules.liveGroups(
            catalog: f.catalog, selections: [:], nicknames: [:],
            wanted: [LiveGroupRef(propertyID: f.property.id, optionID: f.todo.id)])
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].paths, [])
        XCTAssertEqual(PropertyRules.liveGroups(catalog: f.catalog, selections: [:], nicknames: [:], wanted: []), [])
    }

    func testLiveGroupsNFDNamesSortWithNFCAndTieByPath() {
        let f: Fixture = fixture()
        let pid: UUID = f.property.id
        let nfd: String = "/a/Ảnh".decomposedStringWithCanonicalMapping
        let nfc: String = "/b/ảnh".precomposedStringWithCanonicalMapping
        let sel: [UUID: [String: UUID]] = [pid: [nfc: f.todo.id, nfd: f.todo.id, "/c/Bánh": f.todo.id, "/d/Ang": f.todo.id]]
        let g: [PropertyRules.LiveGroup] = PropertyRules.liveGroups(
            catalog: f.catalog, selections: sel, nicknames: [nfc: "   "],   // blank nickname ⇒ path name
            wanted: [LiveGroupRef(propertyID: pid, optionID: f.todo.id)])
        // "ang" < "anh" (== "anh", tie by path /a < /b) < "banh"
        XCTAssertEqual(g.first?.paths, ["/d/Ang", nfd, nfc, "/c/Bánh"])
    }
}
