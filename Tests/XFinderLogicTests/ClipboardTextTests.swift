import XCTest
import Foundation

final class ClipboardTextTests: XCTestCase {
    typealias T = ClipboardText

    /// The measured bug: 201…4 096-character clips had no payload and a 200-character snippet.
    func testAnythingLongerThanThePreviewGetsAPayload() {
        XCTAssertFalse(T.needsPayload(String(repeating: "a", count: 200)))
        XCTAssertTrue(T.needsPayload(String(repeating: "a", count: 201)))
        XCTAssertEqual(T.preview(String(repeating: "x", count: 1000)).count, 200)
    }

    func testFullTextPrefersThePayloadAndFallsBackToTheSnippet() {
        let long = String(repeating: "đ", count: 1375)
        XCTAssertEqual(T.fullText(snippet: T.preview(long), payloadPath: "/p", read: { _ in long }), long)
        XCTAssertEqual(T.fullText(snippet: "short", payloadPath: nil, read: { _ in XCTFail("no payload ⇒ no read"); return nil }), "short")
        XCTAssertEqual(T.fullText(snippet: "preview", payloadPath: "/gone", read: { _ in nil }), "preview",
                       "a missing payload degrades to the preview, never to nothing")
        XCTAssertEqual(T.fullText(snippet: "preview", payloadPath: "/empty", read: { _ in "" }), "preview")
        XCTAssertNil(T.fullText(snippet: nil, payloadPath: nil))
    }

    func testTheRealReaderReadsAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("xf-cliptext-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(repeating: "xin chào ", count: 300)
        try text.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(T.fullText(snippet: T.preview(text), payloadPath: url.path), text)
    }
}
