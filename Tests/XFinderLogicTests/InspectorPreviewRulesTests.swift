import XCTest

final class InspectorPreviewRulesTests: XCTestCase {
    func testBoundariesAndBinary() {
        XCTAssertEqual(InspectorPreviewRules.decode(Data()), .text(""))
        XCTAssertEqual(InspectorPreviewRules.decode(Data(repeating: 65, count: InspectorPreviewRules.byteLimit)), .text(String(repeating: "A", count: InspectorPreviewRules.byteLimit)))
        XCTAssertEqual(InspectorPreviewRules.decode(Data(repeating: 65, count: InspectorPreviewRules.byteLimit + 1)), .tooLarge)
        XCTAssertEqual(InspectorPreviewRules.decode(Data([0])), .binary)
        XCTAssertEqual(InspectorPreviewRules.decode(Data([0xff])), .binary)
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
