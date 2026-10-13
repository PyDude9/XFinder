import XCTest

/// F4: the capture page, card and editor show model vocabulary through `L10n.t(variable)` — no literal sweep sees
/// those keys, so this walks every model case and resolves its key in the shipped store.
final class CaptureVocabularyL10nTests: XCTestCase {

    private func entries() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (root["entries"] as? [String: Any]) ?? root
    }

    func testEveryCaptureVocabularyKeyIsTranslated() throws {
        let store = try entries()
        var keys: [String] = []
        keys += CaptureMode.allCases.flatMap { [$0.titleKey, $0.descriptionKey] }
        keys += CaptureAfter.allCases.map(\.titleKey)
        keys += CaptureCardEdge.allCases.map(\.titleKey)
        keys += AnnotationTool.allCases.map(\.titleKey)
        keys += StrokeWidth.allCases.map(\.titleKey)
        keys += CaptureRules.systemReserved.map(\.nameKey)
        XCTAssertGreaterThan(keys.count, 30, "a collapsed list would pass as a clean one")
        for k in keys {
            let en = (store[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "not translated: \(k)")
        }
    }
}
