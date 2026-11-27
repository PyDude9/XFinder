import XCTest
import Foundation

final class NotchGalleryRulesTests: XCTestCase {
    func testItemsHaveUniqueIDsShortcutsAndDigits() {
        let items = NotchGalleryRules.items
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertEqual(Set(items.map(\.shortcutKey)).count, items.count)
        XCTAssertEqual(Set(items.map(\.digitKey)).count, items.count)
    }

    func testShortcutLetterAndDigitResolveCaseInsensitively() {
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "f"), .page(.files))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "F"), .page(.files))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "1"), .page(.files))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "m"), .page(.nowPlaying))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "3"), .page(.nowPlaying))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "s"), .extra(.system))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "8"), .extra(.system))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "v"), .extra(.audio))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "9"), .extra(.audio))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: ""))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "Z"))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "ff"))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "W", weatherAvailable: false))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "0", weatherAvailable: false))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "w", weatherAvailable: true), .extra(.weather))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "W", weatherAvailable: true), .extra(.weather))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "0", weatherAvailable: true), .extra(.weather))
    }

    func testWeatherTileIsGatedOnExplicitProviderConfiguration() {
        let unconfigured = NotchGalleryRules.items(weatherAvailable: false)
        XCTAssertEqual(unconfigured.count, 9)
        XCTAssertFalse(unconfigured.contains { $0.destination == .extra(.weather) })

        let configured = NotchGalleryRules.items(weatherAvailable: true)
        XCTAssertEqual(configured.count, 10)
        XCTAssertEqual(Set(configured.map(\.id)).count, configured.count)
        XCTAssertEqual(Set(configured.map(\.shortcutKey)).count, configured.count)
        XCTAssertEqual(Set(configured.map(\.digitKey)).count, configured.count)
        XCTAssertEqual(configured.last?.destination, .extra(.weather))

        let full = NotchGalleryRules.items(weatherAvailable: true, stocksAvailable: true, revenueAvailable: true)
        XCTAssertEqual(full.count, 12)
        XCTAssertEqual(Set(full.map(\.id)).count, 12)
        XCTAssertEqual(Set(full.map(\.shortcutKey)).count, 12)
        XCTAssertEqual(Set(full.map(\.digitKey)).count, 12)
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "K", stocksAvailable: true), .extra(.stocks))
        XCTAssertEqual(NotchGalleryRules.destination(forKeyCharacter: "R", revenueAvailable: true), .extra(.revenue))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "K", stocksAvailable: false))
        XCTAssertNil(NotchGalleryRules.destination(forKeyCharacter: "R", revenueAvailable: false))
    }

    func testEveryGalleryTitleKeyIsTranslated() throws {
        let store = try L10nFixture.load()
        for item in NotchGalleryRules.items {
            if item.titleKey == "Clipboard" { continue } // proper noun allowlisted
            guard let entry = store.entries[item.titleKey] else {
                XCTFail("Missing L10n entry for \(item.titleKey)")
                continue
            }
            XCTAssertFalse(entry.en.isEmpty, "Empty English translation for \(item.titleKey)")
        }
        for extra in NotchExtraModule.allCases {
            let key = NotchGalleryRules.titleKey(for: extra)
            guard let entry = store.entries[key] else {
                XCTFail("Missing L10n entry for extra module title \(key)")
                continue
            }
            XCTAssertFalse(entry.en.isEmpty)
        }
    }
}
