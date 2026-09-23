import XCTest

/// Locks down the device-capability layer: the filter that produced the "873
/// input-button elements" lie, the resolution that decides which mouse is in force
/// (D4), and the arm-support contract that must never turn an unreadable descriptor
/// into a measured absence (D2/R3).
///
/// Everything here runs on plain values. `DeviceCapability.swift` imports IOKit and
/// is deliberately NOT in this package — but the pure half of it is extracted into
/// `DeviceCapabilityModel.swift` and symlinked here, so the *decisions* are
/// testable while the *plumbing* is not. That is not a compromise for its own sake:
/// a unit test that opens an IOHID manager and asserts on whatever mouse happens to
/// be plugged in would be theatre, and it would fail on CI.
final class DeviceCapabilityTests: XCTestCase {

    // MARK: - The filter bug (C3 / the 873 regression)

    /// **The regression this whole file exists for.**
    ///
    /// The shipped probe counted 873 "input-button elements" on a five-button mouse
    /// because it matched `usagePage == 0x01 && usage == 0x09` — the Button
    /// *collection* — and never checked the element type. `IOHIDManagerCopyDevices`
    /// reports a full flow of applications, collections and features, so a
    /// predicate that matches a collection matches hundreds of nodes.
    ///
    /// The fix needs **both** guards: the element type must be an input button AND
    /// the usage page must be the Button page. This test builds a synthetic element
    /// list that reproduces the old trap exactly — many non-button nodes that the
    /// old predicate would have counted — and pins the answer at 5.
    func testButtonFilterCountsOnlyRealButtonElementsAndSurvivesThe873Shape() {
        var elements: [HIDElementFact] = []

        // The Generic-Desktop collection node. The OLD predicate matched this
        // because it is (usagePage 0x01, usage 0x09); it is a collection, not a
        // button. Note the type is deliberately NOT `Input_Button` — that is the
        // guard that catches it, and removing the guard makes this fixture return a
        // fabricated sixth button.
        elements.append(.init(usagePage: 0x01, usage: 0x09, type: DeviceCapabilityProbe.elementTypeUnknown))

        // A hundred Generic-Desktop axe/feature nodes — the bulk of the old 873.
        for usage in stride(from: 0x30, to: 0x30 + 100, by: 1) {
            elements.append(.init(usagePage: 0x01, usage: usage, type: DeviceCapabilityProbe.elementTypeUnknown))
        }

        // Five real buttons: Button page, Input_Button type. This is what the
        // Basilisk actually declares, measured.
        for usage in 1...5 {
            elements.append(.init(usagePage: 0x09, usage: usage,
                                  type: DeviceCapabilityProbe.elementTypeInputButton))
        }

        // A Button-page element that is NOT an input — a feature report placeholder.
        // The type guard must exclude it, or the count races away again.
        elements.append(.init(usagePage: 0x09, usage: 90, type: DeviceCapabilityProbe.elementTypeUnknown))

        let buttons = DeviceCapabilityProbe.buttonUsages(from: elements)
        XCTAssertEqual(buttons, [1, 2, 3, 4, 5],
                       "the filter must count the real buttons and nothing else — "
                       + "counting \(buttons.count) is the 873 bug returning")
        XCTAssertLessThan(buttons.count, 10, "a five-button mouse is not a hundred-button mouse")
    }

    /// The specific half of the guard that is easiest to drop: element type alone.
    ///
    /// Guard 1 (`type == Input_Button`) with no page check admits any Generic-Desktop
    /// element that happens to carry the button element type. Measured earlier while
    /// writing the real probe: it returned `[1,2,3,4,5,9]` — it invented a sixth
    /// button out of a collection node. This pins that the page guard is load-bearing.
    func testButtonFilterRequiresTheButtonPageNotJustTheElementType() {
        let elements: [HIDElementFact] = [
            // Correct: button page.
            .init(usagePage: 0x09, usage: 1, type: DeviceCapabilityProbe.elementTypeInputButton),
            // Trap: the right *type* on the wrong page. Must not be counted.
            .init(usagePage: 0x01, usage: 9, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x06, usage: 3, type: DeviceCapabilityProbe.elementTypeInputButton),
        ]
        XCTAssertEqual(DeviceCapabilityProbe.buttonUsages(from: elements), [1],
                       "an element on another usage page was counted as a button")
    }

    /// A descriptor may repeat a usage across reports. A repeat is still one physical
    /// control, so the count must not inflate — the same failure shape as 873, from
    /// a different cause.
    func testRepeatedUsagesCollapseToOneButton() {
        let elements: [HIDElementFact] = [
            .init(usagePage: 0x09, usage: 4, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x09, usage: 4, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x09, usage: 4, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x09, usage: 5, type: DeviceCapabilityProbe.elementTypeInputButton),
        ]
        XCTAssertEqual(DeviceCapabilityProbe.buttonUsages(from: elements), [4, 5])
    }

    // MARK: - Features are derived from declared axes, never from button count

    /// Tilt must come from a declared horizontal axis, never from "this mouse has
    /// lots of buttons, so presumably it tilts". Measured on this machine, the
    /// Basilisk and the Magic Mouse both report continuous scrolling, so a button
    /// count would draw two arms that can never fire on the hardware the feature was
    /// requested for.
    func testTiltIsDerivedFromAxesAndNeverFromButtonCount() {
        let manyButtons: [HIDElementFact] = (1...12).map {
            .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
        }
        let withManyButtons = DeviceCapabilityProbe.physicalCapabilities(from: manyButtons)
        XCTAssertEqual(withManyButtons.buttons.count, 12)
        XCTAssertFalse(DeviceCapabilityProbe.features(from: withManyButtons).supportsTiltArms,
                       "twelve buttons must not be read as a tilt-capable wheel")

        var tiltable = withManyButtons
        tiltable.axes = ["x", "y", "wheel", "tiltLeft", "tiltRight"]
        XCTAssertTrue(DeviceCapabilityProbe.features(from: tiltable).supportsTiltArms,
                      "a declared tilt axis IS evidence of tilt")
    }

    /// The left button is reserved: it must never be what satisfies "there is a
    /// button to hold", because left click has to stay available for selecting,
    /// dragging and emergency UI access.
    func testLeftButtonCannotBeTheHoldTrigger() {
        let leftOnly: [HIDElementFact] = [
            .init(usagePage: 0x09, usage: 1, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x09, usage: 2, type: DeviceCapabilityProbe.elementTypeInputButton),
        ]
        let twoButtons = DeviceCapabilityProbe.physicalCapabilities(from: leftOnly)
        XCTAssertEqual(twoButtons.buttons, [1, 2])
        XCTAssertFalse(DeviceCapabilityProbe.features(from: twoButtons).supportsFourWayHoldDrag,
                       "a two-button mouse has no button the feature may hold")
        XCTAssertFalse(DeviceCapabilityProbe.features(from: twoButtons).supportsButtonRemapping)
    }

    // MARK: - Identity: absent is absent, never a fake number

    /// The Apple Internal Trackpad declares **no** vendor or product key. The probe
    /// must carry that as `nil` rather than coercing it to `0` or `-1`, because those
    /// are valid-looking numbers that would then be matched against presets.
    func testMissingIdentityStaysNilAndLowersConfidence() {
        let elements: [HIDElementFact] = [
            .init(usagePage: 0x09, usage: 1, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x30, usage: 0x30, type: DeviceCapabilityProbe.elementTypeUnknown),
            .init(usagePage: 0x30, usage: 0x31, type: DeviceCapabilityProbe.elementTypeUnknown),
        ]
        let nameless = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "SPI", vendorID: nil, productID: nil, productName: "",
            elements: elements, source: .detected))
        XCTAssertNil(nameless.vendorID)
        XCTAssertNil(nameless.productID)
        XCTAssertEqual(nameless.confidence, .unknown,
                       "no name and no identifiers cannot be attributed to a product")

        let named = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: nil, productID: nil,
            productName: "Magic Trackpad", elements: elements, source: .detected))
        XCTAssertEqual(named.confidence, .inferred,
                       "a name without identifiers is a weak identification, not a verified one")

        let verified = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K", elements: elements, source: .detected))
        XCTAssertEqual(verified.confidence, .verified)
    }

    /// `IOHIDManagerCopyDevices` returns the same physical device twice — measured:
    /// two identical Basilisk entries and two identical trackpad entries. Without
    /// dedupe the picker would list the same mouse twice and the two entries could
    /// drift apart in the UI.
    func testDuplicateDeviceReportsCollapseToOne() {
        func basilisk() -> CapabilityDescriptor {
            DeviceCapabilityProbe.descriptor(from: .init(
                transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
                productName: "BSKV3P 35K",
                elements: (1...5).map {
                    .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
                },
                source: .detected))
        }
        func trackpad() -> CapabilityDescriptor {
            DeviceCapabilityProbe.descriptor(from: .init(
                transport: "SPI", vendorID: nil, productID: nil, productName: "",
                elements: [], source: .detected))
        }
        let deduped = DeviceCapabilityProbe.deduplicated([basilisk(), basilisk(), trackpad(), trackpad()])
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped.filter { $0.productName == "BSKV3P 35K" }.count, 1)
        // Two *unnamed* devices DO dedupe to one: their identity tuple is identical,
        // and the alternative — treating every unnamed report as distinct — would
        // list the same trackpad many times.
        XCTAssertEqual(deduped.filter { $0.productName.isEmpty }.count, 1)
    }

    // MARK: - Single-mouse selection (D4)

    /// A real mouse must win over the internal trackpad, which must win over a device
    /// nothing is known about. Ordering only — this never fabricates a candidate.
    func testSelectionPrefersAMouseOverATrackpad() {
        let trackpad = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "SPI", vendorID: 0x1005, productID: 0x0001, productName: "Magic Trackpad",
            elements: (1...2).map {
                .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
            },
            source: .detected))
        let barMouse = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K", elements: (1...5).map {
                .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
            },
            source: .detected))

        XCTAssertEqual(DeviceSelection.active(from: [trackpad, barMouse])?.productName, "BSKV3P 35K")
        XCTAssertEqual(DeviceSelection.active(from: [trackpad])?.productName, "Magic Trackpad")
        // Nothing probed at all is nil, never a synthesised default device.
        XCTAssertNil(DeviceSelection.active(from: []))
    }

    /// A manual pick is an OVERRIDE and is never silently replaced by a detection
    /// result. The brief calls this out explicitly: a user who pinned a device must
    /// not have the page drift underneath them on the next probe.
    func testManualOverrideOutranksDetectionAndIsNeverSilentlyReplaced() {
        let detected = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K", elements: [], source: .detected))
        let pinned = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "USB", vendorID: 0x046D, productID: 0xB023, productName: "MX Master 3",
            elements: [], source: .manual))
        XCTAssertEqual(DeviceSelection.active(from: [detected], override: pinned)?.productName,
                       "MX Master 3")
    }

    /// Provenance has to distinguish a real probe from a user's choice from nothing at
    /// all, because "Đã nhận diện" is the word the UI prints for evidence.
    func testProvenanceDistinguishesDetectedFromManualFromUnavailable() {
        let detected = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K", elements: [], source: .detected))
        XCTAssertTrue(DeviceSelection.provenance(for: detected).isDetected)

        let manual = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "USB", vendorID: 0x046D, productID: 0xB023, productName: "MX Master 3",
            elements: [], source: .manual))
        XCTAssertFalse(DeviceSelection.provenance(for: manual).isDetected,
                       "a hand-supplied device must never be presented as Detected")

        XCTAssertEqual(DeviceSelection.provenance(for: nil), .unavailable)
        XCTAssertFalse(DeviceSelection.provenance(for: nil).isDetected)
    }

    // MARK: - R3/D2: arms follow the device, and unknown is not unsupported

    /// The D2 contract: an arm the mouse genuinely cannot perform is disabled.
    func testVerifiedAbsenceDisablesTheArm() {
        // A two-button mouse with no tilt axis, fully identified.
        let twoButton = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "USB", vendorID: 0x046D, productID: 0xB023, productName: "Basic Mouse",
            elements: [
                .init(usagePage: 0x09, usage: 1, type: DeviceCapabilityProbe.elementTypeInputButton),
                .init(usagePage: 0x09, usage: 2, type: DeviceCapabilityProbe.elementTypeInputButton),
            ], source: .detected))
        for direction in [GestureDirection.up, .down, .left, .right, .tiltLeft, .tiltRight] {
            XCTAssertEqual(DeviceCapabilityModel.armSupport(for: direction, device: twoButton),
                           .unsupportedByMouse, direction.rawValue)
        }
    }

    /// The R3 contract, and the one that stops the feature from lying: a device whose
    /// identity is incomplete cannot have its *absences* read as facts, so the arm is
    /// `.unknownUntilDetected` — which the UI must render as "unavailable until
    /// detected", NOT as "not supported by this mouse".
    ///
    /// This is the branch a stale "permission denied" lands in, and getting it wrong
    /// greys out a working mouse and tells the user their hardware lacks a button it
    /// actually has.
    func testIncompleteIdentityGivesUnknownNotUnsupported() {
        let nameless = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "SPI", vendorID: nil, productID: nil, productName: "",
            elements: [], source: .detected))
        XCTAssertEqual(nameless.confidence, .unknown)
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .up, device: nameless),
                       .unknownUntilDetected)
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .tiltLeft, device: nameless),
                       .unknownUntilDetected)
        // And an unprobed device is the same answer — never `unsupported`.
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .up, device: nil),
                       .unknownUntilDetected)
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .tiltRight, device: nil),
                       .unknownUntilDetected)
    }

    /// A declared capability is evidence regardless of identity: if the descriptor
    /// shows a button, the arm works, even when we cannot name the product.
    func testDeclaredCapabilityIsHonouredEvenWithoutFullIdentity() {
        let namelessButCapable = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "SPI", vendorID: nil, productID: nil, productName: "",
            elements: (1...5).map {
                .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
            } + [
                .init(usagePage: 0x30, usage: 0x3C, type: DeviceCapabilityProbe.elementTypeUnknown),
                .init(usagePage: 0x30, usage: 0x3D, type: DeviceCapabilityProbe.elementTypeUnknown),
            ], source: .detected))
        XCTAssertEqual(namelessButCapable.confidence, .unknown)
        // Presences hold even without an identity: the descriptor declares five
        // buttons, so a hold trigger exists whatever the product is called.
        XCTAssertEqual(namelessButCapable.physical.buttons, [1, 2, 3, 4, 5])
        XCTAssertTrue(namelessButCapable.features.supportsFourWayHoldDrag,
                      "five declared buttons is a usable hold trigger, identity or not")
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .up, device: namelessButCapable), .supported)
        // Tilt is the *absence* case, so an identity-less descriptor must NOT claim
        // the arm is unsupported — it says unknown, because `axes` was read but the
        // device cannot be attributed to a product.
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .tiltLeft, device: namelessButCapable),
                       .unknownUntilDetected,
                       "an absence on an unattributable device is not evidence")

        // The same descriptor WITH a full identity: now the missing tilt axis IS
        // evidence, and the arm is genuinely unsupported.
        var identified = namelessButCapable
        identified.vendorID = 0x046D
        identified.productID = 0xB023
        identified.productName = "MX Master 3"
        identified.confidence = .verified
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .tiltLeft, device: identified),
                       .unsupportedByMouse,
                       "a verified identity turns a missing axis into a real absence")
    }

    /// The diagram must not draw a tilt arm on hardware that cannot tilt, and must
    /// draw it when the hardware can — the same predicate the engine uses to decide
    /// whether a scroll event is a tilt at all.
    func testTiltArmFollowsTheMeasuredBasiliskDescriptor() {
        // Measured on this machine: the Basilisk declares five buttons and no tilt
        // axis, because its driver reports continuous scrolling.
        let basilisk = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K",
            elements: (1...5).map {
                .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
            }, source: .detected))
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .up, device: basilisk), .supported,
                       "five buttons is a usable hold trigger")
        XCTAssertEqual(DeviceCapabilityModel.armSupport(for: .tiltLeft, device: basilisk),
                       .unsupportedByMouse,
                       "no declared tilt axis means the tilt arm cannot fire")
    }

    // MARK: - ArmSupport semantics

    /// `isSupported` is what the view branches on, so it must be false for both
    /// non-supported cases — but the two cases must remain distinguishable, because
    /// they print different words.
    func testArmSupportKeepsUnsupportedAndUnknownDistinct() {
        XCTAssertTrue(ArmSupport.supported.isSupported)
        XCTAssertFalse(ArmSupport.unsupportedByMouse.isSupported)
        XCTAssertFalse(ArmSupport.unknownUntilDetected.isSupported)
        XCTAssertNotEqual(ArmSupport.unsupportedByMouse, ArmSupport.unknownUntilDetected,
                          "the UI prints 'not supported' for one and 'not detected yet' for "
                          + "the other; they can never collapse into one case")
    }

    // MARK: - Device label

    /// A device with a name prints the name; one without prints its IDs rather than an
    /// empty string; one with neither returns nil so the caller can say "not detected"
    /// instead of rendering a blank line.
    func testDeviceLabelNeverInventsAName() {
        XCTAssertEqual(DeviceCapabilityModel.deviceLabel(
            .detected(productName: "BSKV3P 35K", vendorID: 0x068E, productID: 0x00D8)),
            "BSKV3P 35K")
        XCTAssertEqual(DeviceCapabilityModel.deviceLabel(
            .detected(productName: "", vendorID: 0x068E, productID: 0x00D8)),
            "068E:00D8")
        XCTAssertNil(DeviceCapabilityModel.deviceLabel(
            .detected(productName: "", vendorID: nil, productID: nil)))
        XCTAssertNil(DeviceCapabilityModel.deviceLabel(.unavailable))
        XCTAssertNil(DeviceCapabilityModel.deviceLabel(.manual))
    }

    // MARK: - Preset resolution (R6 / L4: unknown apps inherit Global)

    /// A known app resolves to its own preset; an unknown one does not, so the page
    /// explains the Global fallback instead of pretending the app-specific preset
    /// matched.
    func testPresetBundleDistinguishesBuiltInFromUnknown() {
        XCTAssertEqual(DeviceCapabilityModel.presetBundle(for: "com.apple.Safari"), "com.apple.Safari")
        XCTAssertEqual(DeviceCapabilityModel.presetBundle(for: "dev.zed.Zed"), "dev.zed.Zed")
        XCTAssertNil(DeviceCapabilityModel.presetBundle(for: "com.example.notinstalled"),
                     "an app with no built-in profile must be reported as such, not mapped "
                     + "onto Global and called a match")
        XCTAssertNil(DeviceCapabilityModel.presetBundle(for: GestureProfiles.fallback),
                     "Global is the fallback, not a preset of its own")
    }

    // MARK: - Axis classification

    /// Only the two documented axis usages become tilt tokens. The filter must not
    /// invent a token for an unrelated Generic-Desktop usage.
    func testAxisTokensMapOnlyTheDocumentedUsages() {
        let elements: [HIDElementFact] = [
            .init(usagePage: 0x01, usage: 0x30, type: DeviceCapabilityProbe.elementTypeUnknown),  // X
            .init(usagePage: 0x01, usage: 0x31, type: DeviceCapabilityProbe.elementTypeUnknown),  // Y
            .init(usagePage: 0x01, usage: 0x38, type: DeviceCapabilityProbe.elementTypeUnknown),  // wheel
            .init(usagePage: 0x01, usage: 0x3C, type: DeviceCapabilityProbe.elementTypeUnknown),  // tilt L
            .init(usagePage: 0x01, usage: 0x3D, type: DeviceCapabilityProbe.elementTypeUnknown),  // tilt R
            .init(usagePage: 0x01, usage: 0x99, type: DeviceCapabilityProbe.elementTypeUnknown),  // unknown
            // A button usage on the wrong page must not become an axis either.
            .init(usagePage: 0x09, usage: 0x30, type: DeviceCapabilityProbe.elementTypeInputButton),
        ]
        let tokens = DeviceCapabilityProbe.axisTokens(from: elements)
        XCTAssertEqual(Set(tokens), ["x", "y", "wheel", "tiltLeft", "tiltRight"])
    }
}
