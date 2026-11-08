import XCTest

final class NotchDisplayTargetRulesTests: XCTestCase {
    private let builtIn = NotchDisplayTargetRules.Display(id: 10, isMain: true, hasPhysicalNotch: true)
    private let external = NotchDisplayTargetRules.Display(id: 20, isMain: false, hasPhysicalNotch: false)

    func testUnknownOrMissingTargetDefaultsToAutomatic() {
        XCTAssertEqual(NotchDisplayTargetRules.Target.parse(nil), .automatic)
        XCTAssertEqual(NotchDisplayTargetRules.Target.parse("invalid"), .automatic)
        XCTAssertEqual(NotchDisplayTargetRules.Target.parse("specific"), .specific)
    }

    func testAutomaticUsesPointerThenNotchedDisplayThenMain() {
        XCTAssertEqual(resolve(.automatic, pointer: 20)?.displayID, 20)
        XCTAssertEqual(resolve(.automatic, pointer: nil)?.displayID, 10)
        XCTAssertEqual(resolve(.automatic, pointer: nil, displays: [external])?.displayID, 20)
    }

    func testBuiltInAndMainTargetsHaveExplicitFallbacks() {
        XCTAssertEqual(resolve(.builtIn)?.displayID, 10)
        XCTAssertEqual(resolve(.builtIn, displays: [external])?.fallback, .builtInUnavailable)
        XCTAssertEqual(resolve(.main, displays: [external])?.fallback, .mainUnavailable)
    }

    func testSpecificTargetPersistsAsFallbackWhenDisconnected() {
        XCTAssertEqual(resolve(.specific, selected: 20)?.displayID, 20)
        XCTAssertEqual(resolve(.specific, selected: 99)?.displayID, 10)
        XCTAssertEqual(resolve(.specific, selected: 99)?.fallback, .selectedDisplayUnavailable)
        XCTAssertEqual(resolve(.specific, selected: nil)?.fallback, .selectedDisplayUnavailable)
    }

    func testReconnectedSelectionWinsAgainWithoutChangingPreference() {
        let missing = resolve(.specific, selected: 20, displays: [builtIn])
        let reconnected = resolve(.specific, selected: 20, displays: [builtIn, external])
        XCTAssertEqual(missing?.fallback, .selectedDisplayUnavailable)
        XCTAssertEqual(reconnected, .init(displayID: 20, fallback: nil))
    }

    func testBusySurfaceStaysOnItsDisplayUnlessThatDisplayWasRemoved() {
        XCTAssertEqual(resolve(.specific, selected: 20, active: 10, busy: true)?.displayID, 10)
        XCTAssertEqual(resolve(.specific, selected: 20, active: 99, busy: true)?.displayID, 20)
    }

    func testEmptyDisplayListReturnsNoResolutionAndDuplicateIDsAreDeterministic() {
        XCTAssertNil(resolve(.automatic, displays: []))
        let duplicate = NotchDisplayTargetRules.Display(id: 10, isMain: false, hasPhysicalNotch: false)
        XCTAssertEqual(resolve(.automatic, pointer: nil, displays: [external, builtIn, duplicate])?.displayID, 10)
    }

    private func resolve(_ target: NotchDisplayTargetRules.Target,
                         selected: UInt32? = nil,
                         pointer: UInt32? = nil,
                         active: UInt32? = nil,
                         busy: Bool = false,
                         displays: [NotchDisplayTargetRules.Display]? = nil) -> NotchDisplayTargetRules.Resolution? {
        NotchDisplayTargetRules.resolve(target: target, selectedDisplayID: selected,
                                        displays: displays ?? [builtIn, external],
                                        pointerDisplayID: pointer, activeDisplayID: active, busy: busy)
    }
}
