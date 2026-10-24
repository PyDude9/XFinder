import XCTest

/// XF-T28: the file browser shows model vocabulary through `L10n.t(variable)` — command titles, recovery messages,
/// search warnings. No literal sweep sees those keys, so every model case is walked and resolved in the shipped store.
final class BrowserVocabularyL10nTests: XCTestCase {

    private func entries() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return (root["entries"] as? [String: Any]) ?? root
    }

    func testEveryBrowserVocabularyKeyIsTranslated() throws {
        let store = try entries()
        var keys = BrowserCommand.allCases.map { BrowserCommands.titleKey($0) }
        // One recovery message per unfinished phase.
        let job = UUID()
        let at = Date(timeIntervalSince1970: 0)
        for (i, phase) in [JournalPhase.started, .copied, .verified, .trashing].enumerated() {
            let entry = JournalEntry(job: job, kind: .move, source: "/src/\(i)", destination: "/dst/\(i)", phase: phase, at: at)
            keys += FileOperationRules.recoveryReport([entry]).map(\.messageKey)
        }
        keys += SearchQuery.parse("bogus:thing", now: at, calendar: Calendar(identifier: .gregorian)).warnings
        XCTAssertGreaterThanOrEqual(keys.count, BrowserCommand.allCases.count + 5, "a collapsed list would pass as a clean one")
        for k in keys {
            let en = (store[k] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "not translated: \(k)")
        }
    }
}
