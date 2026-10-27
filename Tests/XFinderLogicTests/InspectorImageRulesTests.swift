import XCTest
import Darwin

final class InspectorImageRulesTests: XCTestCase {
    func testResizeLimitsAndPathValidation() {
        for pixels in [0, 8193] {
            XCTAssertFalse(InspectorImageRules.Request(source: "/a.png", expectedIdentity: "stamp", operation: .resize, maxPixels: pixels).isValid)
        }
        XCTAssertTrue(InspectorImageRules.Request(source: "/a.png", expectedIdentity: "stamp", operation: .resize, maxPixels: 512).isValid)
        XCTAssertFalse(InspectorImageRules.Request(source: "a.png", expectedIdentity: "stamp", operation: .png, maxPixels: nil).isValid)
    }
    func testIdentityDetectsSameSecondReplacementAndSizeChange() {
        var info = stat(); info.st_ino = 42; info.st_size = 10; info.st_mtimespec.tv_sec = 1
        let first = InspectorImageRules.identity(path: "/a", info: info)
        info.st_mtimespec.tv_nsec = 1
        XCTAssertNotEqual(first, InspectorImageRules.identity(path: "/a", info: info))
        info.st_mtimespec.tv_nsec = 0; info.st_ino = 43
        XCTAssertNotEqual(first, InspectorImageRules.identity(path: "/a", info: info))
        info.st_ino = 42; info.st_size = 11
        XCTAssertNotEqual(first, InspectorImageRules.identity(path: "/a", info: info))
    }
    func testNewNamesAndUnicode() {
        let url = URL(fileURLWithPath: "/tmp/Ảnh gốc.png")
        XCTAssertEqual(InspectorImageRules.outputName(source: url, operation: .flipHorizontal, maxPixels: nil, attempt: 0), "Ảnh gốc-flip-h.png")
        XCTAssertEqual(InspectorImageRules.outputName(source: url, operation: .resize, maxPixels: 512, attempt: 1), "Ảnh gốc-512px (2).png")
        XCTAssertEqual(InspectorImageRules.outputName(source: url, operation: .jpeg, maxPixels: nil, attempt: 0), "Ảnh gốc.jpg")
    }
}
