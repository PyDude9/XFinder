import XCTest
@testable import XFinderLogicTests

final class PropertySchemaTests: XCTestCase {

    // MARK: - add / rename / delete

    func testAddCreatesSelectPropertyWithNoOptions() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let d: PropertyDefinition = catalog.add(name: "Status")
        XCTAssertEqual(d.name, "Status")
        XCTAssertEqual(d.kind, .select)
        XCTAssertTrue(d.options.isEmpty)
        XCTAssertEqual(catalog.definitions, [d])
        XCTAssertEqual(catalog.definition(d.id), d)
        XCTAssertEqual(catalog.schemaVersion, PropertyCatalog.currentSchemaVersion)
    }

    func testAddEmptyNameUsesDefaultKey() {
        var catalog: PropertyCatalog = PropertyCatalog()
        XCTAssertEqual(catalog.add(name: "").name, "Thuộc tính")
        XCTAssertEqual(catalog.add(name: "   \n").name, "Thuộc tính 2")
    }

    func testAddDuplicateNameGetsNumberSuffix() {
        var catalog: PropertyCatalog = PropertyCatalog()
        XCTAssertEqual(catalog.add(name: "Status").name, "Status")
        XCTAssertEqual(catalog.add(name: "status").name, "status 2")
        XCTAssertEqual(catalog.add(name: "STATUS").name, "STATUS 3")
        XCTAssertEqual(catalog.add(name: " Status ").name, "Status 4")
    }

    func testDuplicateCheckIsNFCNFDInsensitiveButKeepsToneMarks() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let nfc: String = "Trạng thái".precomposedStringWithCanonicalMapping
        let nfd: String = "Trạng thái".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))
        XCTAssertEqual(catalog.add(name: nfc).name, nfc)
        XCTAssertEqual(catalog.add(name: nfd).name, nfd + " 2")
        // Tone marks are part of a Vietnamese word: "TRANG THAI" is a different name, not a duplicate.
        XCTAssertEqual(catalog.add(name: "TRANG THAI").name, "TRANG THAI")
        XCTAssertEqual(catalog.add(name: "TRẠNG THÁI").name, "TRẠNG THÁI 3")
    }

    func testRename() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let a: PropertyDefinition = catalog.add(name: "A")
        let b: PropertyDefinition = catalog.add(name: "B")
        XCTAssertTrue(catalog.rename(a.id, to: "Priority"))
        XCTAssertEqual(catalog.definition(a.id)?.name, "Priority")
        XCTAssertFalse(catalog.rename(a.id, to: "  "))
        XCTAssertEqual(catalog.definition(a.id)?.name, "Priority")
        XCTAssertFalse(catalog.rename(UUID(), to: "X"))
        XCTAssertTrue(catalog.rename(b.id, to: "priority"))
        XCTAssertEqual(catalog.definition(b.id)?.name, "priority 2")
        // Renaming to its own name in another case is not a clash with itself.
        XCTAssertTrue(catalog.rename(a.id, to: "PRIORITY"))
        XCTAssertEqual(catalog.definition(a.id)?.name, "PRIORITY")
    }

    func testDelete() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let a: PropertyDefinition = catalog.add(name: "A")
        let b: PropertyDefinition = catalog.add(name: "B")
        catalog.delete(a.id)
        XCTAssertNil(catalog.definition(a.id))
        XCTAssertEqual(catalog.definitions.map(\.id), [b.id])
        catalog.delete(UUID())
        XCTAssertEqual(catalog.definitions.count, 1)
    }

    // MARK: - options

    func testAddOption() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Status")
        let todo: PropertyOption? = catalog.addOption(p.id, title: " Todo ", color: .red)
        XCTAssertEqual(todo?.title, "Todo")
        XCTAssertEqual(todo?.color, .red)
        XCTAssertNil(catalog.addOption(p.id, title: "  ", color: .red))
        XCTAssertNil(catalog.addOption(UUID(), title: "Done", color: .green))
        // Two options with the same title are allowed and distinct.
        let todo2: PropertyOption? = catalog.addOption(p.id, title: "Todo", color: .blue)
        XCTAssertNotNil(todo2)
        XCTAssertNotEqual(todo?.id, todo2?.id)
        XCTAssertEqual(catalog.definition(p.id)?.options.count, 2)
    }

    func testUpdateOption() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Status")
        guard var o: PropertyOption = catalog.addOption(p.id, title: "Todo", color: .red) else { return XCTFail("nil") }
        o.title = "Doing"
        o.color = .yellow
        XCTAssertTrue(catalog.updateOption(p.id, option: o))
        XCTAssertEqual(catalog.definition(p.id)?.options, [o])
        XCTAssertFalse(catalog.updateOption(UUID(), option: o))
        XCTAssertFalse(catalog.updateOption(p.id, option: PropertyOption(id: UUID(), title: "X", color: .gray)))
        var blank: PropertyOption = o
        blank.title = " "
        XCTAssertFalse(catalog.updateOption(p.id, option: blank))
        XCTAssertEqual(catalog.definition(p.id)?.options.first?.title, "Doing")
    }

    func testRemoveOption() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Status")
        let a: PropertyOption? = catalog.addOption(p.id, title: "A", color: .red)
        let b: PropertyOption? = catalog.addOption(p.id, title: "B", color: .red)
        catalog.removeOption(p.id, option: a!.id)
        XCTAssertEqual(catalog.definition(p.id)?.options.map(\.id), [b!.id])
        catalog.removeOption(p.id, option: UUID())
        catalog.removeOption(UUID(), option: b!.id)
        XCTAssertEqual(catalog.definition(p.id)?.options.count, 1)
    }

    func testMoveOptionClamps() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Status")
        for t in ["A", "B", "C", "D"] { _ = catalog.addOption(p.id, title: t, color: .gray) }
        func titles() -> [String] { catalog.definition(p.id)?.options.map(\.title) ?? [] }
        catalog.moveOption(p.id, from: 0, to: 2)
        XCTAssertEqual(titles(), ["B", "C", "A", "D"])
        catalog.moveOption(p.id, from: 3, to: -5)
        XCTAssertEqual(titles(), ["D", "B", "C", "A"])
        catalog.moveOption(p.id, from: 99, to: 0)
        XCTAssertEqual(titles(), ["A", "D", "B", "C"])
        catalog.moveOption(p.id, from: -1, to: 99)
        XCTAssertEqual(titles(), ["D", "B", "C", "A"])
        catalog.moveOption(p.id, from: 1, to: 1)
        XCTAssertEqual(titles(), ["D", "B", "C", "A"])
        catalog.moveOption(UUID(), from: 0, to: 1)
        XCTAssertEqual(titles(), ["D", "B", "C", "A"])
    }

    func testMoveOptionOnEmptyOrSingleIsNoOp() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Status")
        catalog.moveOption(p.id, from: 0, to: 3)
        XCTAssertEqual(catalog.definition(p.id)?.options.count, 0)
        _ = catalog.addOption(p.id, title: "A", color: .gray)
        catalog.moveOption(p.id, from: 0, to: 3)
        XCTAssertEqual(catalog.definition(p.id)?.options.map(\.title), ["A"])
    }

    func testColorTitleKeysAreDistinct() {
        let keys: [String] = PropertyColor.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, PropertyColor.allCases.count)
        XCTAssertEqual(PropertyColor.gray.titleKey, "Xám")
        XCTAssertEqual(PropertyColor.purple.titleKey, "Tím")
    }

    // MARK: - encode / decode

    func testRoundTrip() {
        var catalog: PropertyCatalog = PropertyCatalog()
        let p: PropertyDefinition = catalog.add(name: "Trạng thái")
        _ = catalog.addOption(p.id, title: "Đang làm", color: .orange)
        _ = catalog.addOption(p.id, title: "Xong", color: .green)
        _ = catalog.add(name: "Priority")
        XCTAssertEqual(PropertyCatalog.decode(catalog.encoded()), catalog)
    }

    func testDecodeNilEmptyAndGarbage() {
        XCTAssertEqual(PropertyCatalog.decode(nil), PropertyCatalog())
        XCTAssertEqual(PropertyCatalog.decode(Data()), PropertyCatalog())
        XCTAssertEqual(PropertyCatalog.decode(Data("not json".utf8)), PropertyCatalog())
        XCTAssertEqual(PropertyCatalog.decode(Data("42".utf8)), PropertyCatalog())
        XCTAssertEqual(PropertyCatalog.decode(Data("{\"definitions\": 7}".utf8)), PropertyCatalog())
    }

    func testDecodeDropsDamagedDefinitionKeepsTheRest() {
        let good1: String = UUID().uuidString, good2: String = UUID().uuidString
        let json: String = """
        {"schemaVersion": 1, "definitions": [
          {"id": "\(good1)", "name": "A", "kind": "select", "options": []},
          {"id": "not-a-uuid", "name": "Broken", "kind": "select", "options": []},
          {"id": "\(UUID().uuidString)", "name": "Future", "kind": "number", "options": []},
          {"id": "\(UUID().uuidString)", "kind": "select", "options": []},
          17,
          null,
          {"id": "\(good2)", "name": "B", "kind": "select", "options": []}
        ]}
        """
        let catalog: PropertyCatalog = PropertyCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.definitions.map(\.name), ["A", "B"])
        XCTAssertEqual(catalog.definitions.map(\.id.uuidString), [good1, good2])
    }

    func testDecodeDropsDamagedOptionAndMapsUnknownColorToGray() {
        let pid: String = UUID().uuidString, o1: String = UUID().uuidString, o2: String = UUID().uuidString
        let json: String = """
        {"schemaVersion": 1, "definitions": [
          {"id": "\(pid)", "name": "S", "kind": "select", "options": [
            {"id": "\(o1)", "title": "One", "color": 2},
            {"id": "bad", "title": "Bad", "color": 1},
            {"title": "NoID", "color": 1},
            "junk",
            {"id": "\(o2)", "title": "Two", "color": 42},
            {"id": "\(o1)", "title": "Dup", "color": 3}
          ]}
        ]}
        """
        let catalog: PropertyCatalog = PropertyCatalog.decode(Data(json.utf8))
        let options: [PropertyOption] = catalog.definitions.first?.options ?? []
        XCTAssertEqual(options.map(\.title), ["One", "Two"])
        XCTAssertEqual(options.map(\.color), [.orange, .gray])
    }

    func testDecodeMissingOptionsAndVersionKeepsDefinition() {
        let pid: String = UUID().uuidString
        let json: String = "{\"definitions\": [{\"id\": \"\(pid)\", \"name\": \"S\", \"kind\": \"select\"}]}"
        let catalog: PropertyCatalog = PropertyCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.schemaVersion, PropertyCatalog.currentSchemaVersion)
        XCTAssertEqual(catalog.definitions.count, 1)
        XCTAssertEqual(catalog.definitions.first?.options, [])
    }

    func testDecodeDuplicateDefinitionIDKeepsFirst() {
        let pid: String = UUID().uuidString
        let json: String = """
        {"schemaVersion": 1, "definitions": [
          {"id": "\(pid)", "name": "First", "kind": "select", "options": []},
          {"id": "\(pid)", "name": "Second", "kind": "select", "options": []}
        ]}
        """
        XCTAssertEqual(PropertyCatalog.decode(Data(json.utf8)).definitions.map(\.name), ["First"])
    }

    func testDecodeBareArray() {
        let pid: String = UUID().uuidString
        let json: String = "[{\"id\": \"\(pid)\", \"name\": \"S\", \"kind\": \"select\", \"options\": []}, 3]"
        let catalog: PropertyCatalog = PropertyCatalog.decode(Data(json.utf8))
        XCTAssertEqual(catalog.definitions.map(\.name), ["S"])
        XCTAssertEqual(catalog.schemaVersion, PropertyCatalog.currentSchemaVersion)
    }
}
