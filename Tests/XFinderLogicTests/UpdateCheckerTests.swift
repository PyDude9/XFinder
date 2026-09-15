import XCTest

/// Version comparison for the "Kiểm tra cập nhật" button.
///
/// The failure mode worth guarding: a naive string compare says "1.10.0" is
/// OLDER than "1.9.0", so the app would stop offering updates forever once the
/// minor version passed 9 — silently, with the button still cheerfully
/// reporting "bạn đang dùng bản mới nhất".
///
/// Mirrors `UpdateChecker.isNewer` / `.normalize`. See GeometryTests for why
/// the logic is duplicated rather than imported.
final class UpdateCheckerTests: XCTestCase {

    private func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    private func components(_ version: String) -> [Int] {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        return core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(normalize(candidate))
        let b = components(normalize(current))
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: The bug this file exists for

    /// Lexicographically "1.10.0" < "1.9.0". Numerically it is newer.
    func testDoubleDigitMinorIsNewerThanSingleDigit() {
        XCTAssertTrue(isNewer("1.10.0", than: "1.9.0"),
                      "1.10.0 must be newer than 1.9.0 — a string compare gets this backwards")
    }

    func testDoubleDigitPatchIsNewer() {
        XCTAssertTrue(isNewer("1.0.12", than: "1.0.9"))
    }

    // MARK: Ordering

    func testEqualVersionIsNotNewer() {
        XCTAssertFalse(isNewer("1.0.0", than: "1.0.0"))
    }

    func testOlderVersionIsNotNewer() {
        XCTAssertFalse(isNewer("1.0.0", than: "1.2.0"))
    }

    func testMajorBeatsMinor() {
        XCTAssertTrue(isNewer("2.0.0", than: "1.99.99"))
    }

    // MARK: Tag shapes GitHub actually produces

    /// Releases are usually tagged "v1.2.0" while Info.plist holds "1.2.0".
    /// Treating the "v" as part of the number would make every check report an
    /// update forever.
    func testLeadingVIsIgnored() {
        XCTAssertFalse(isNewer("v1.0.0", than: "1.0.0"),
                       "v1.0.0 and 1.0.0 are the same release")
        XCTAssertTrue(isNewer("v1.1.0", than: "1.0.0"))
    }

    /// A missing component counts as zero, so "1.2" == "1.2.0".
    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(isNewer("1.2", than: "1.2.0"))
        XCTAssertFalse(isNewer("1.2.0", than: "1.2"))
    }

    /// A pre-release suffix must not be parsed as a version component.
    func testPreReleaseSuffixIsIgnored() {
        XCTAssertFalse(isNewer("1.0.0-beta.1", than: "1.0.0"),
                       "A beta of the current version is not an upgrade")
        XCTAssertTrue(isNewer("1.1.0-beta.1", than: "1.0.0"))
    }

    func testWhitespaceIsTrimmed() {
        XCTAssertFalse(isNewer("  v1.0.0 \n", than: "1.0.0"))
    }

    /// Garbage must never be reported as an update — that would send the user
    /// to a release page for a version that does not exist.
    func testNonNumericTagIsNotNewer() {
        XCTAssertFalse(isNewer("latest", than: "1.0.0"))
        XCTAssertFalse(isNewer("", than: "1.0.0"))
    }
}
