import XCTest

final class InspectorPreviewRulesTests: XCTestCase {
    func testNarrowSplitCannotLoseItsListingToFixedInspector() {
        // 720-point window minus a 200-point sidebar, divided into two panes.
        XCTAssertTrue(InspectorLayoutRules.stacksInspector(availableWidth: 260))
        XCTAssertTrue(InspectorLayoutRules.stacksInspector(availableWidth: 560))
        XCTAssertFalse(InspectorLayoutRules.stacksInspector(availableWidth: 561))
        XCTAssertFalse(InspectorLayoutRules.stacksInspector(availableWidth: 1000))
    }
    func testStackedInspectorLeavesAtLeastSixtyPercentForFiles() {
        for height in [0.0, 0.5, 1, 40, 160, 300, 700, 2000] {
            let preview = InspectorLayoutRules.stackedInspectorHeight(availableHeight: height)
            let usable = max(0, height - InspectorLayoutRules.dividerWidth)
            XCTAssertGreaterThanOrEqual(preview, 0)
            XCTAssertLessThanOrEqual(preview, 280)
            XCTAssertGreaterThanOrEqual(usable - preview + 0.0001, usable * 0.6)
        }
        XCTAssertEqual(InspectorLayoutRules.stackedInspectorHeight(availableHeight: 301), 120)
        XCTAssertEqual(InspectorLayoutRules.stackedInspectorHeight(availableHeight: 2000), 280)
    }
    func testInvalidGeometryDoesNotProduceInvalidFrames() {
        for width in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertTrue(InspectorLayoutRules.stacksInspector(availableWidth: width))
        }
        for height in [-1.0, .nan, .infinity, -.infinity] {
            XCTAssertEqual(InspectorLayoutRules.stackedInspectorHeight(availableHeight: height), 0)
        }
    }
    func testBoundariesAndBinary() {
        XCTAssertEqual(InspectorPreviewRules.decode(Data()), .text(""))
        XCTAssertEqual(InspectorPreviewRules.decode(Data(repeating: 65, count: InspectorPreviewRules.byteLimit)), .text(String(repeating: "A", count: InspectorPreviewRules.byteLimit)))
        XCTAssertEqual(InspectorPreviewRules.decode(Data(repeating: 65, count: InspectorPreviewRules.byteLimit + 1)), .tooLarge)
        XCTAssertEqual(InspectorPreviewRules.decode(Data([0])), .binary)
        XCTAssertEqual(InspectorPreviewRules.decode(Data([0xff])), .binary)
    }
    func testMarkdownKeepsBlockBreaksListMarkersAndEmphasis() {
        let result = InspectorPreviewRules.markdown("# Heading\n\n**Bold** words\n\n- one\n- two")
        XCTAssertEqual(String(result.characters), "Heading\n\nBold words\n\n• one\n\n• two")
        XCTAssertTrue(result.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }
    func testKinds() {
        XCTAssertEqual(InspectorPreviewRules.kind(extension: "MD"), .markdown)
        XCTAssertEqual(InspectorPreviewRules.kind(extension: "swift"), .code)
        XCTAssertEqual(InspectorPreviewRules.kind(extension: "txt"), .plain)
        XCTAssertNil(InspectorPreviewRules.kind(extension: "png"))
    }
    func testLexicalPrecedenceAndUnicodeRanges() {
        let text = "let tên = \"return\" // if true\nreturn tên"
        let spans = InspectorPreviewRules.spans(in: text)
        XCTAssertEqual(spans.map(\.style), [.keyword, .string, .comment, .keyword])
        XCTAssertEqual(spans.map { (text as NSString).substring(with: $0.range) }, ["let", "\"return\"", "// if true", "return"])
    }
}
