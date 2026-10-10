import XCTest
import Foundation

final class OnboardingTests: XCTestCase {
    func testShowsUntilTheCurrentVersionIsCompleted() {
        XCTAssertTrue(Onboarding.shouldShow(completedVersion: nil))
        XCTAssertTrue(Onboarding.shouldShow(completedVersion: 0))
        XCTAssertFalse(Onboarding.shouldShow(completedVersion: Onboarding.currentVersion))
        XCTAssertFalse(Onboarding.shouldShow(completedVersion: Onboarding.currentVersion + 3), "a newer stored version never re-shows")
    }

    func testMinimalPresetContainsNothingThatRunsInTheBackground() {
        let minimal = Onboarding.presets.first { $0.id == "minimal" }!
        XCTAssertFalse(minimal.features.isEmpty)
        for id in minimal.features { XCTAssertFalse(FeatureCatalog.def(id).idle.isBackgroundActive, "\(id)") }
        XCTAssertTrue(Onboarding.neededPermissions(for: minimal.features).isEmpty, "the minimal preset must need no permission at all")
    }

    func testPresetsAreNestedAndEverythingIsEverything() {
        let p = Dictionary(uniqueKeysWithValues: Onboarding.presets.map { ($0.id, $0.features) })
        XCTAssertTrue(p["minimal"]!.isSubset(of: p["everyday"]!))
        XCTAssertTrue(p["everyday"]!.isSubset(of: p["everything"]!))
        XCTAssertEqual(p["everything"], Set(FeatureID.allCases))
        XCTAssertNotEqual(p["minimal"], p["everyday"])
    }

    func testNeededPermissionsAreTheUnionOfTheChosenFeaturesInCatalogueOrder() {
        XCTAssertEqual(Onboarding.neededPermissions(for: [.snapZones]), [.accessibility])
        XCTAssertEqual(Onboarding.neededPermissions(for: [.dockPreview]), [.accessibility, .screenRecording])
        XCTAssertEqual(Onboarding.neededPermissions(for: [.voice]), [.accessibility, .microphone, .speechRecognition])
        XCTAssertEqual(Onboarding.neededPermissions(for: [.voice, .dockPreview]),
                       [.accessibility, .screenRecording, .microphone, .speechRecognition], "no duplicates, stable order")
        XCTAssertEqual(Onboarding.neededPermissions(for: []), [])
        // Every permission some feature lists — not every case: `.notifications` is optional (Alerts
        // always draw their own banner), so no feature requires it and setup must not ask for it.
        let referenced = AppPermission.allCases.filter { p in FeatureCatalog.all.contains { $0.permissions.contains(p) } }
        XCTAssertEqual(Onboarding.neededPermissions(for: Set(FeatureID.allCases)), referenced)
        XCTAssertFalse(referenced.contains(.notifications), "no feature may REQUIRE Notification Center (refused for self-signed builds)")
    }

    func testAPermissionIsNeverRequestedForAFeatureThatIsOff() {
        // Turning Voice off must drop microphone + speech from the list.
        let without = Onboarding.neededPermissions(for: Set(FeatureID.allCases).subtracting([.voice]))
        XCTAssertFalse(without.contains(.microphone))
        XCTAssertFalse(without.contains(.speechRecognition))
    }

    func testMatchingPresetOnlyOnExactEquality() {
        let everyday = Onboarding.presets.first { $0.id == "everyday" }!.features
        XCTAssertEqual(Onboarding.matchingPreset(everyday), "everyday")
        XCTAssertNil(Onboarding.matchingPreset(everyday.union([.voice])))
        XCTAssertNil(Onboarding.matchingPreset([]))
    }

    func testPresetTextResolvesInTheShippedStore() throws {
        let store = try L10nFixture.load()
        for p in Onboarding.presets {
            for k in [p.titleKey, p.descriptionKey] {
                XCTAssertNotNil(store.entries[k], "not in L10n.strings.json: \(k)")
            }
        }
    }
}
