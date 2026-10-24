import XCTest
import CryptoKit

/// XF-T29 — tiers, limits, the 14-day trial and offline licence keys.
final class ProEntitlementTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_792_000_000)
    let day: TimeInterval = 86_400

    func testDevelopmentBuildsAreFull() {
        XCTAssertEqual(Entitlement.tier(enforced: false, licenseValid: false, trialStart: start, now: start + 100 * day, maxSeen: nil), .pro)
    }

    func testLicenceWinsOverAnExpiredTrial() {
        XCTAssertEqual(Entitlement.tier(enforced: true, licenseValid: true, trialStart: start, now: start + 100 * day, maxSeen: nil), .pro)
    }

    func testTrialCountsFourteenDaysRoundedUp() {
        func t(_ elapsed: TimeInterval) -> ProTier {
            Entitlement.tier(enforced: true, licenseValid: false, trialStart: start, now: start + elapsed, maxSeen: nil)
        }
        XCTAssertEqual(Entitlement.tier(enforced: true, licenseValid: false, trialStart: nil, now: start, maxSeen: nil), .trial(daysLeft: 14))
        XCTAssertEqual(t(0), .trial(daysLeft: 14))
        XCTAssertEqual(t(1), .trial(daysLeft: 14), "the first day shows 14, not 13")
        XCTAssertEqual(t(day), .trial(daysLeft: 13))
        XCTAssertEqual(t(13.5 * day), .trial(daysLeft: 1))
        XCTAssertEqual(t(14 * day), .free)
        XCTAssertEqual(t(30 * day), .free)
    }

    func testSettingTheClockBackDoesNotBuyDays() {
        let late = start + 20 * day
        XCTAssertEqual(Entitlement.tier(enforced: true, licenseValid: false, trialStart: start, now: start + day, maxSeen: late), .free)
        XCTAssertEqual(Entitlement.tier(enforced: true, licenseValid: false, trialStart: start, now: start - 5 * day, maxSeen: start + 2 * day),
                       .trial(daysLeft: 12))
    }

    func testFreeLimitsAndUnlockedTiers() {
        XCTAssertEqual(Entitlement.limit(.clipboardItems, tier: .free), 50)
        XCTAssertEqual(Entitlement.limit(.captures, tier: .free), 20)
        XCTAssertEqual(Entitlement.limit(.browserPanes, tier: .free), 2)
        XCTAssertEqual(Entitlement.limit(.quickShareLinks, tier: .free), 1)
        for l in ProLimit.allCases {
            XCTAssertNil(Entitlement.limit(l, tier: .pro))
            XCTAssertNil(Entitlement.limit(l, tier: .trial(daysLeft: 3)))
            XCTAssertNotNil(Entitlement.limit(l, tier: .free), "\(l) needs a Free number")
        }
        for f in ProFeature.allCases {
            XCTAssertFalse(Entitlement.allows(f, tier: .free))
            XCTAssertTrue(Entitlement.allows(f, tier: .pro))
            XCTAssertTrue(Entitlement.allows(f, tier: .trial(daysLeft: 1)))
        }
    }

    func testOverTheLimitIsHiddenNotDeleted() {
        XCTAssertEqual(Entitlement.visibleCount(total: 900, pinned: 0, limit: 50).visible, 50)
        XCTAssertEqual(Entitlement.visibleCount(total: 900, pinned: 0, limit: 50).hidden, 850)
        let p = Entitlement.visibleCount(total: 60, pinned: 5, limit: 50)
        XCTAssertEqual(p.visible, 55, "pinned items always show and do not count")
        XCTAssertEqual(p.hidden, 5)
        XCTAssertEqual(Entitlement.visibleCount(total: 30, pinned: 0, limit: 50).hidden, 0)
        XCTAssertEqual(Entitlement.visibleCount(total: 900, pinned: 3, limit: nil).visible, 900)
        XCTAssertEqual(Entitlement.visibleCount(total: 2, pinned: 9, limit: 1).visible, 2, "pinned never exceeds total")
    }

    func testEveryProTitleIsTranslated() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let store = (root["entries"] as? [String: Any]) ?? root
        for f in ProFeature.allCases {
            let en = (store[f.titleKey] as? [String: Any])?["en"] as? String
            XCTAssertFalse((en ?? "").isEmpty, "not translated: \(f.titleKey)")
        }
    }

    // MARK: Licence keys

    func testASignedKeyVerifiesAndOneChangedCharacterDoesNot() throws {
        let priv = Curve25519.Signing.PrivateKey()
        let payload = LicensePayload(id: "L-1", licensee: "owner@example.com", edition: "pro", issued: start)
        let key = try XCTUnwrap(LicenseKey.make(payload: payload, privateKey: priv.rawRepresentation))
        XCTAssertTrue(key.hasPrefix("XF1-"))
        XCTAssertEqual(LicenseKey.verify(key, publicKey: priv.publicKey.rawRepresentation), payload)
        // Pasted with spaces and line breaks.
        let spaced = key.enumerated().map { $0.offset % 20 == 19 ? "\($0.element)\n " : String($0.element) }.joined()
        XCTAssertEqual(LicenseKey.verify(spaced, publicKey: priv.publicKey.rawRepresentation), payload)
        // Every single-character change in the payload breaks it.
        var chars = Array(key)
        let i = 6
        chars[i] = chars[i] == "A" ? "B" : "A"
        XCTAssertNil(LicenseKey.verify(String(chars), publicKey: priv.publicKey.rawRepresentation))
        // Another key pair, garbage, a missing part.
        XCTAssertNil(LicenseKey.verify(key, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation))
        XCTAssertNil(LicenseKey.verify("XF1-abc", publicKey: priv.publicKey.rawRepresentation))
        XCTAssertNil(LicenseKey.verify("hello", publicKey: priv.publicKey.rawRepresentation))
        XCTAssertNil(LicenseKey.verify(key, publicKey: Data([1, 2, 3])))
    }
}
