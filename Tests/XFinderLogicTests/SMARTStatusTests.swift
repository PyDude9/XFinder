import XCTest
import Foundation

/// SMART readout: the extraction from `diskutil` text, the raw → key mapping, and the gate
/// that every key the mapper can produce is translatable — a model returning a display string
/// is how the Ổ đĩa page leaked "Bình thường" into the English UI.
final class SMARTStatusTests: XCTestCase {

    // MARK: Parsing — pinned against the exact text `diskutil info /` prints

    func testParsesTheSMARTStatusLineFromRealDiskutilOutput() {
        let output = """
           Device Identifier:         disk3s1s1
           Device Node:               /dev/disk3s1s1
           Whole:                     No
           Part of Whole:             disk3

           Volume Name:               Macintosh HD
           Mounted:                   Yes
           Mount Point:               /

           SMART Status:              Verified
           Volume UUID:               7B6F3C8C-1234-4D2A-9E7F-ABCDEF012345
        """
        XCTAssertEqual(SMARTStatus.parse(diskutilOutput: output), "Verified")
    }

    func testParseReturnsNilWhenTheLineIsAbsentOrEmpty() {
        XCTAssertNil(SMARTStatus.parse(diskutilOutput: "   Device Node: /dev/disk3\n   Mounted: Yes\n"),
                     "no SMART line at all — must not invent a status")
        XCTAssertNil(SMARTStatus.parse(diskutilOutput: "   SMART Status:    \n"),
                     "an empty value is not a status")
        XCTAssertNil(SMARTStatus.parse(diskutilOutput: ""))
    }

    func testParseKeepsAValueThatItselfContainsAColon() {
        XCTAssertEqual(SMARTStatus.parse(diskutilOutput: "   SMART Status: Not Supported: external\n"),
                       "Not Supported: external",
                       "only the first colon separates the field name")
    }

    // MARK: Mapping — raw → store key + health

    func testKnownValuesMapToTheThreeKeysAndTheirHealth() {
        XCTAssertEqual(SMARTStatus.label(forRaw: "Verified"),
                       .init(key: SMARTStatus.healthyKey, healthy: true))
        XCTAssertEqual(SMARTStatus.label(forRaw: "Failing"),
                       .init(key: SMARTStatus.failingKey, healthy: false))
        XCTAssertEqual(SMARTStatus.label(forRaw: "Not Supported"),
                       .init(key: SMARTStatus.notSupportedKey, healthy: nil))
        // diskutil's casing/padding must not matter.
        XCTAssertEqual(SMARTStatus.label(forRaw: "  verified ").healthy, true)
    }

    func testUnknownRawValuePassesThroughUnchangedWithUnknownHealth() {
        let label = SMARTStatus.label(forRaw: "Degraded")
        XCTAssertEqual(label.key, "Degraded", "the OS's own words, not an invented state")
        XCTAssertNil(label.healthy)
    }

    // MARK: The gate — every key the mapper can emit resolves in the shipped store

    func testEveryKnownLabelKeyIsTranslatedInTheStore() throws {
        let store = try L10nFixture.load()
        XCTAssertEqual(SMARTStatus.knownRawValues.count, 3,
                       "the known-value list collapsed; the loop below would prove nothing")
        for raw in SMARTStatus.knownRawValues {
            let key = SMARTStatus.label(forRaw: raw).key
            let entry = store.entries[key]
            XCTAssertNotNil(entry, "SMART label key \(key.debugDescription) is not in L10n.strings.json — "
                            + "it would reach the English UI as Vietnamese")
            if let entry {
                XCTAssertFalse(entry.en.isEmpty, "\(key.debugDescription) has an empty English value")
                XCTAssertNotEqual(entry.en, key, "\(key.debugDescription) is 'translated' to itself")
            }
        }
    }
}
