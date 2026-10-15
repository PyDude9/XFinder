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

    // MARK: - PATCH v9.1 R2/R3: controls, roles, and the usage → event-number map

    /// A descriptor for the mouse this feature was built for, as the probe reports it.
    /// Kept as a helper because five tests below need the same real shape.
    private func basilisk(usages: [Int] = [1, 2, 3, 4, 5]) -> CapabilityDescriptor {
        DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K",
            elements: usages.map {
                .init(usagePage: 0x09, usage: $0, type: DeviceCapabilityProbe.elementTypeInputButton)
            }, source: .detected))
    }

    /// **The conversion that would shift every label on the page by one.**
    ///
    /// HID button usages are 1-based and `CGEvent.buttonNumber` is 0-based, so usage
    /// `N` answers for event button `N - 1`. Drawing usage 3 at the position of event
    /// button 3 would mislabel every chip, and the mistake is invisible in a screenshot
    /// because both are "some number on a mouse".
    func testEventButtonsConvertUsagesToZeroBasedNumbers() {
        XCTAssertEqual(DeviceCapabilityModel.eventButtons(from: basilisk()),
                       [0, 1, 2, 3, 4],
                       "usage 1 is the primary button, i.e. event button 0")
        // `nil` is not `[]`: nothing read is a different fact from a mouse with no buttons.
        XCTAssertNil(DeviceCapabilityModel.eventButtons(from: nil),
                     "an unread device must not be reported as a device with zero buttons")
        let noButtons = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "USB", vendorID: 1, productID: 2, productName: "Odd",
            elements: [], source: .detected))
        XCTAssertEqual(DeviceCapabilityModel.eventButtons(from: noButtons), [],
                       "a read descriptor with no buttons is an empty list, not nil")
    }

    /// A usage of 0 would map to event button -1, which is not a button. Pinned because
    /// the filter admits whatever the descriptor declares, and a `-1` rendered in the
    /// sidebar would be a fabricated control.
    func testUsageZeroNeverBecomesANegativeButtonNumber() {
        XCTAssertEqual(DeviceCapabilityModel.eventButtons(from: basilisk(usages: [0, 1, 2])),
                       [0, 1])
    }

    /// The role ordering contract. The first case is the one that is easy to get wrong
    /// and expensive to get wrong: **an assignment beats everything**, because the page's
    /// job is to report what is stored, not what is recommended. A row that read
    /// "reserved" while the engine was consuming that button would be worse than no row.
    func testAssignmentOutranksReservedAndEverythingElse() {
        let context = MouseRoleContext(trigger: .mouseButton(1), scrollButton: 4,
                                       scrollButtonEnabled: false,
                                       declaredEventButtons: [0, 1, 2, 3, 4],
                                       identityVerified: true)
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 1, context: context),
                       .holdTrigger,
                       "right click is reserved, but the stored trigger is right click — "
                       + "the page reports the configuration, not the recommendation")
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 0, context: context),
                       .reserved)
    }

    /// Left and right are never assignable, and that is structural rather than cosmetic:
    /// `TriggerSource.isValid` already refuses button 0, and a gesture that consumed right
    /// click would remove the control the user always has.
    func testLeftAndRightAreReservedAndNotAssignable() {
        let context = MouseRoleContext(trigger: .mouseButton(3), scrollButton: 4,
                                       scrollButtonEnabled: false,
                                       declaredEventButtons: [0, 1, 2, 3, 4],
                                       identityVerified: true)
        let left = DeviceCapabilityModel.role(forEventButton: 0, context: context)
        let right = DeviceCapabilityModel.role(forEventButton: 1, context: context)
        XCTAssertEqual(left, .reserved)
        XCTAssertEqual(right, .reserved)
        XCTAssertFalse(left.isAssignable)
        XCTAssertFalse(right.isAssignable)
        XCTAssertFalse(TriggerSource.mouseButton(0).isValid)
    }

    /// The scroll modifier only claims a control while the feature is on. With it off the
    /// button is an ordinary button again — claiming otherwise would label a control as
    /// doing something the engine has been told not to do.
    func testScrollRoleFollowsTheFeatureSwitch() {
        let off = MouseRoleContext(trigger: .mouseButton(3), scrollButton: 4,
                                   scrollButtonEnabled: false,
                                   declaredEventButtons: [0, 1, 2, 3, 4],
                                   identityVerified: true)
        var on = off
        on.scrollButtonEnabled = true
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 4, context: off), .unassigned)
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 4, context: on), .scrollButton)
    }

    /// The D2/D3 contract again, one level down: a *read* descriptor that does not declare
    /// a control is evidence the control is absent; an unread one, or one whose identity is
    /// incomplete, is not.
    func testNotDeclaredAndUnknownStayDistinct() {
        let readAndIdentified = MouseRoleContext(trigger: .mouseButton(3), scrollButton: 4,
                                                scrollButtonEnabled: false,
                                                declaredEventButtons: [0, 1, 2],
                                                identityVerified: true)
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 5, context: readAndIdentified),
                       .notDeclared)

        var readButUnattributable = readAndIdentified
        readButUnattributable.identityVerified = false
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 5, context: readButUnattributable),
                       .unknown,
                       "an absence on an unattributable device is not evidence")

        var nothingRead = readAndIdentified
        nothingRead.declaredEventButtons = nil
        XCTAssertEqual(DeviceCapabilityModel.role(forEventButton: 5, context: nothingRead),
                       .unknown)
    }

    /// A control the descriptor does not declare is **still assignable**, and that is
    /// deliberate: HID under-reports on real hardware (measured: the Basilisk in this repo
    /// declares five buttons), and refusing to let the user assign a button they can
    /// physically press would turn the probe's limitation into the user's problem.
    func testUndeclaredControlsRemainAssignable() {
        XCTAssertTrue(MouseButtonRole.notDeclared.isAssignable)
        XCTAssertTrue(MouseButtonRole.unknown.isAssignable)
        XCTAssertTrue(MouseButtonRole.unassigned.isAssignable)
        XCTAssertFalse(MouseButtonRole.reserved.isAssignable)
    }

    /// `isDeclared` is the **drawing's** question, and it must not be the same answer as
    /// `isAssignable` (PATCH v10.1 R2).
    ///
    /// The chip on the figure is drawn disabled exactly when the read did not put that
    /// control on the mouse — a live chip claims XFinder can see the button, which is the
    /// claim the press-to-record path exists to disprove. Assignability stays true for those
    /// same roles, because the row below keeps the Record button: the control is unreachable
    /// on the *picture* and reachable where the *measurement* happens, which is the whole
    /// point of separating the two.
    func testDeclaredIsTheDrawingsQuestionAndIsNotAssignability() {
        XCTAssertFalse(MouseButtonRole.notDeclared.isDeclared)
        XCTAssertFalse(MouseButtonRole.unknown.isDeclared,
                       "nothing was read, so nothing was declared either")

        XCTAssertTrue(MouseButtonRole.unassigned.isDeclared)
        XCTAssertTrue(MouseButtonRole.reserved.isDeclared)
        XCTAssertTrue(MouseButtonRole.holdTrigger.isDeclared)
        XCTAssertTrue(MouseButtonRole.scrollButton.isDeclared)

        // The two must not collapse into one another: if they ever did, one of the two
        // behaviours above would silently become the other's.
        XCTAssertNotEqual(MouseButtonRole.notDeclared.isDeclared,
                          MouseButtonRole.notDeclared.isAssignable)
    }

    /// The "missing button" prompt is caused by **evidence**: a press the engine saw that
    /// the descriptor never mentioned. It must not fire merely because a mouse has fewer
    /// buttons than some archetype — that would put a warning on every two-button mouse.
    func testUndeclaredPressFiresOnlyOnAMeasuredMismatch() {
        let declared: [Int]? = [0, 1, 2, 3, 4]
        let context = MouseRoleContext(trigger: .mouseButton(3), scrollButton: 4,
                                       scrollButtonEnabled: false,
                                       declaredEventButtons: declared,
                                       identityVerified: true)
        XCTAssertEqual(DeviceCapabilityModel.undeclaredPress(observed: 5, context: context), 5,
                       "the engine saw button 5 and the descriptor never declared it")
        XCTAssertNil(DeviceCapabilityModel.undeclaredPress(observed: 2, context: context),
                     "a declared press is not a mismatch")
        XCTAssertNil(DeviceCapabilityModel.undeclaredPress(observed: nil, context: context),
                     "nothing pressed, nothing to report")
        var nothingRead = context
        nothingRead.declaredEventButtons = nil
        XCTAssertNil(DeviceCapabilityModel.undeclaredPress(observed: 5, context: nothingRead),
                     "with nothing read there is no declaration to contradict")
    }

    /// The drawing keeps its shape while the mouse is unplugged: every archetype slot is
    /// still drawn (disabled), and a mouse with more controls than the archetype has
    /// positions still has them all listed.
    func testDrawnButtonsCoverTheArchetypeAndAnythingBeyondIt() {
        XCTAssertEqual(DeviceCapabilityModel.drawnButtons(declaredEventButtons: nil),
                       [0, 1, 2, 3, 4, 5],
                       "with nothing read, the archetype is drawn so the picture does not "
                       + "collapse while the device is missing")
        XCTAssertEqual(DeviceCapabilityModel.drawnButtons(declaredEventButtons: [0, 1, 2]),
                       [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(DeviceCapabilityModel.drawnButtons(declaredEventButtons: [0, 1, 2, 3, 4, 5, 7]),
                       [0, 1, 2, 3, 4, 5, 7],
                       "a control past the archetype is listed rather than dropped")
    }

    /// The archetype is positional only. Its names must never be read as a claim about
    /// the connected device — that is why `MouseControlSlot` has no user-facing strings.
    func testControlSlotsArePositionsAndTheirRawValuesAreEventNumbers() {
        for slot in MouseControlSlot.allCases {
            XCTAssertEqual(MouseControlSlot.slot(forEventButton: slot.eventButton), slot)
        }
        XCTAssertEqual(MouseControlSlot.left.eventButton, 0)
        XCTAssertEqual(MouseControlSlot.sniper.eventButton, 5)
        XCTAssertNil(MouseControlSlot.slot(forEventButton: 9),
                     "a control the drawing has no place for must not be given an invented one")
    }

    /// `roleContext` is the only place the view and the tests build the context, so the
    /// two cannot assemble it differently.
    func testRoleContextIsBuiltFromTheConfigurationAndTheDevice() {
        var config = GestureConfiguration()
        config.trigger = .mouseButton(5)
        config.scrollButton = 4
        config.scrollButtonEnabled = true
        let context = DeviceCapabilityModel.roleContext(for: basilisk(), configuration: config)
        XCTAssertEqual(context.trigger, .mouseButton(5))
        XCTAssertEqual(context.scrollButton, 4)
        XCTAssertTrue(context.scrollButtonEnabled)
        XCTAssertEqual(context.declaredEventButtons, [0, 1, 2, 3, 4])
        XCTAssertTrue(context.identityVerified, "0x068E/0x00D8 is a complete identity")

        let none = DeviceCapabilityModel.roleContext(for: nil, configuration: config)
        XCTAssertNil(none.declaredEventButtons)
        XCTAssertFalse(none.identityVerified)
    }

    // MARK: - PATCH v10: vendor-page evidence, diagram style, position captions

    /// Consumer-page controls are raw evidence only: they never become CoreGraphics buttons.
    func testConsumerPageUsagesStaySeparateFromEventButtons() {
        let elements: [HIDElementFact] = [
            .init(usagePage: 0x09, usage: 1, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x09, usage: 2, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: DeviceCapabilityProbe.usagePageConsumer, usage: 0xE9,
                  type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: DeviceCapabilityProbe.usagePageConsumer, usage: 0xEA,
                  type: DeviceCapabilityProbe.elementTypeUnknown),
            .init(usagePage: DeviceCapabilityProbe.usagePageConsumer, usage: 0xE9,
                  type: DeviceCapabilityProbe.elementTypeInputButton)
        ]

        XCTAssertEqual(DeviceCapabilityProbe.consumerUsages(from: elements), [0xE9, 0xEA])
        let physical = DeviceCapabilityProbe.physicalCapabilities(from: elements)
        XCTAssertEqual(physical.buttons, [1, 2])
        XCTAssertEqual(physical.consumerUsages, [0xE9, 0xEA])

        let descriptor = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "USB", vendorID: 1, productID: 2, productName: "Consumer fixture",
            elements: elements, source: .detected))
        XCTAssertEqual(DeviceCapabilityModel.eventButtons(from: descriptor), [0, 1])
        XCTAssertFalse((DeviceCapabilityModel.eventButtons(from: descriptor) ?? []).contains(0xE8),
                       "Consumer usage must never be converted with usage - 1")
    }

    func testElementDumpIncludesConsumerPageAsRawEvidence() {
        let dump = DeviceCapabilityProbe.elementDump(from: [
            .init(usagePage: DeviceCapabilityProbe.usagePageConsumer, usage: 0xE9,
                  type: DeviceCapabilityProbe.elementTypeInputButton)
        ])
        XCTAssertTrue(dump.contains { $0.contains("page=0x000C usage=0x00E9") })
        XCTAssertTrue(dump.contains { $0.contains("Consumer") })
    }

    /// The vendor-page scan must be **evidence**, not a button count (R1).
    ///
    /// The fixture reproduces the trap this machine measured: the Apple Internal Trackpad
    /// declares **1753** vendor-page elements carrying `type == Input_Button` and the
    /// `0xFFFFFFFF` "no usage" sentinel. A scan without the range guard reports 1753
    /// "buttons" and numbers one of them `-1` — the same failure shape as the original
    /// "873 input-button elements" bug, where a filter was widened until a number appeared
    /// and then that number was believed.
    func testVendorPageButtonElementsAreEvidenceAndTheSentinelUsageIsExcluded() {
        var elements: [HIDElementFact] = []
        // The five real buttons, exactly as measured on the Basilisk.
        for usage in 1...5 {
            elements.append(.init(usagePage: 0x09, usage: usage,
                                  type: DeviceCapabilityProbe.elementTypeInputButton))
        }
        // The trackpad's vendor page, reproduced: every element button-typed, every usage
        // the sentinel. None of them is a button.
        for _ in 0..<1753 {
            elements.append(.init(usagePage: 0xFF00, usage: DeviceCapabilityProbe.usageSentinelNone,
                                  type: DeviceCapabilityProbe.elementTypeInputButton))
        }
        // Two plausible vendor usages, which ARE reported — as usages, never as buttons.
        elements.append(.init(usagePage: 0xFF00, usage: 1,
                              type: DeviceCapabilityProbe.elementTypeInputButton))
        elements.append(.init(usagePage: 0xFF00, usage: 2,
                              type: DeviceCapabilityProbe.elementTypeInputButton))
        // A vendor element that is not a button must not be counted either.
        elements.append(.init(usagePage: 0xFF00, usage: 3, type: DeviceCapabilityProbe.elementTypeUnknown))

        let physical = DeviceCapabilityProbe.physicalCapabilities(from: elements)
        XCTAssertEqual(physical.buttons, [1, 2, 3, 4, 5],
                       "the standard button page is the only source of button *numbers*")
        XCTAssertEqual(physical.vendorButtonUsages, [1, 2],
                       "the sentinel usage is not a button, and a non-button element is not "
                       + "a button either — counting 1755 here is the 873 bug returning")

        let descriptor = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x068E, productID: 0x00D8,
            productName: "BSKV3P 35K", elements: elements, source: .detected))
        // The two arrays must stay separate: `buttons` drives every number on the page and
        // a vendor usage cannot be converted to a `CGEvent` button number.
        XCTAssertEqual(DeviceCapabilityModel.eventButtons(from: descriptor), [0, 1, 2, 3, 4])
        XCTAssertEqual(DeviceCapabilityModel.vendorControlCount(for: descriptor), 2)
        XCTAssertEqual(DeviceCapabilityModel.vendorControlCount(for: nil), 0)
    }

    /// The "log before you filter" step must show the raw facts (R1).
    func testElementDumpReportsTheRawFactsBeforeAnyFilter() {
        let elements: [HIDElementFact] = [
            .init(usagePage: 0x09, usage: 1, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x09, usage: 2, type: DeviceCapabilityProbe.elementTypeInputButton),
            .init(usagePage: 0x01, usage: 0x30, type: DeviceCapabilityProbe.elementTypeUnknown),
            .init(usagePage: 0xFF00, usage: 0x12, type: DeviceCapabilityProbe.elementTypeInputButton),
        ]
        let dump = DeviceCapabilityProbe.elementDump(from: elements)
        XCTAssertEqual(dump.first, "elements: 4")
        XCTAssertTrue(dump.contains { $0.contains("page=0x0009 type=0x02") },
                      "the tally must name the button page and its element type")
        XCTAssertTrue(dump.contains { $0.contains("page=0x0001 type=0x00") },
                      "the tally must account for every element, not only the interesting ones")
        XCTAssertTrue(dump.contains { $0.contains("page=0xFF00 usage=0x0012 (18) type=0x02") },
                      "the raw vendor element must appear verbatim, so the claim can be checked")
        XCTAssertFalse(dump.contains { $0.contains("page=0x0030") },
                       "an axis element must not be listed among the button/vendor candidates")
    }

    /// The figure must follow the device (R2) — this is the acceptance case "switch to a
    /// Magic Mouse and the diagram falls back to a generic figure".
    func testDiagramStyleFallsBackToGenericForADeviceWithFewButtons() {
        XCTAssertEqual(DeviceCapabilityModel.diagramStyle(for: basilisk()), .archetype,
                       "five declared buttons is a multi-button mouse")
        XCTAssertEqual(DeviceCapabilityModel.diagramStyle(for: nil), .unknown,
                       "nothing read is NOT the same as a one-button mouse")

        let magicMouse = DeviceCapabilityProbe.descriptor(from: .init(
            transport: "Bluetooth Low Energy", vendorID: 0x004C, productID: 0x0269,
            productName: "Magic Mouse",
            elements: [.init(usagePage: 0x09, usage: 1,
                             type: DeviceCapabilityProbe.elementTypeInputButton)],
            source: .detected))
        XCTAssertEqual(DeviceCapabilityModel.diagramStyle(for: magicMouse), .generic,
                       "a one-button mouse must not be drawn with six chips")
        XCTAssertEqual(DeviceCapabilityModel.genericButtons(declaredEventButtons: [0]), [0],
                       "the generic figure draws exactly what was declared")
        XCTAssertEqual(DeviceCapabilityModel.genericButtons(declaredEventButtons: nil), [],
                       "nothing declared draws nothing rather than the archetype")
    }

    /// Every archetype position must have a caption key, and the caption must be short
    /// enough for the chip it sits under (R2).
    ///
    /// The length bound is a **measured content constraint, not a style rule**: the chip is
    /// 46 pt wide and the caption is drawn at 7 pt, so a caption much past ~14 characters
    /// is clipped by the thing it describes. That is the same reasoning that put the bare
    /// number on the chip in the first place — the Vietnamese name for the wheel is 17
    /// characters and does not fit at any legible size.
    ///
    /// What this test cannot check is that the key resolves to a translation; that is
    /// `L10nTests.testGesturePageStringsAreAllTranslatable`, which enumerates
    /// `MouseControlSlot.allCases` for exactly this reason — `L10n.t(slot.positionKey)` is a
    /// variable, so no literal sweep can see it.
    func testEveryArchetypePositionHasACaptionKeyThatFitsItsChip() {
        XCTAssertEqual(MouseControlSlot.archetypeSlots.count, 6,
                       "the figure has six positions; the mouse's DPI/scroll-mode/profile "
                       + "controls are firmware-side and are deliberately not among them")
        for slot in MouseControlSlot.allCases {
            XCTAssertFalse(slot.positionKey.isEmpty)
            XCTAssertLessThanOrEqual(slot.positionKey.count, 14,
                                     "\(slot) caption \(slot.positionKey) will not fit a "
                                     + "46 pt chip at 7 pt type")
        }
        let keys = MouseControlSlot.allCases.map(\.positionKey)
        XCTAssertEqual(Set(keys).count, keys.count, "two positions share a caption")
    }

    /// The per-row statement of what a single click does must exist only where it is a fact
    /// (R3) — inventing one for the left button would be a sentence written to fill a cell.
    func testPassthroughNotesExistOnlyForTheSideButtons() {
        XCTAssertNotNil(DeviceCapabilityModel.passthroughNoteKey(forEventButton: 2))
        XCTAssertNotNil(DeviceCapabilityModel.passthroughNoteKey(forEventButton: 3))
        XCTAssertNotNil(DeviceCapabilityModel.passthroughNoteKey(forEventButton: 4))
        XCTAssertNotNil(DeviceCapabilityModel.passthroughNoteKey(forEventButton: 5))
        for button in [0, 1, 6, 7] {
            XCTAssertNil(DeviceCapabilityModel.passthroughNoteKey(forEventButton: button),
                         "button \(button) has no factual single-click statement")
        }
    }

    /// The "missing hardware buttons" prompt must be caused by **evidence** (R1).
    ///
    /// Two things can cause it: a press the descriptor never declared, or a descriptor that
    /// declares fewer controls than the figure has positions *while* also declaring vendor
    /// page controls. A mouse that simply has fewer buttons must stay quiet — that is the
    /// difference between a measurement and noise on every device.
    func testUnderReportedPromptNeedsEvidence() {
        var config = GestureConfiguration()
        config.trigger = .mouseButton(2)
        let fiveButton = DeviceCapabilityModel.roleContext(for: basilisk(), configuration: config)

        XCTAssertFalse(DeviceCapabilityModel.underReportedControls(
            declaredEventButtons: fiveButton.declaredEventButtons,
            vendorControlCount: 0, observed: nil, context: fiveButton),
            "five declared buttons and no vendor page is not under-reporting")

        XCTAssertTrue(DeviceCapabilityModel.underReportedControls(
            declaredEventButtons: fiveButton.declaredEventButtons,
            vendorControlCount: 3, observed: nil, context: fiveButton),
            "fewer declared controls than positions, plus a vendor page, is evidence")

        XCTAssertTrue(DeviceCapabilityModel.underReportedControls(
            declaredEventButtons: fiveButton.declaredEventButtons,
            vendorControlCount: 0, observed: 5, context: fiveButton),
            "a press the descriptor never declared is evidence on its own")

        XCTAssertFalse(DeviceCapabilityModel.underReportedControls(
            declaredEventButtons: nil, vendorControlCount: 3, observed: nil, context: fiveButton),
            "with nothing read, a vendor count cannot be evidence of anything")
    }

    // MARK: - PATCH v10.2: Side Buttons Instant Action + Sniper Truth Tests

    func testDefaultButtonActionsAndRoles() {
        let config = GestureConfiguration()
        XCTAssertEqual(config.trigger, .mouseButton(4), "Default trigger is Lower side (Button 5, eventButton 4)")
        XCTAssertTrue(config.holdButtonSingleClickEnabled)
        XCTAssertEqual(config.buttonActions[4], .instant(.back))
        XCTAssertEqual(config.buttonActions[5], .instant(.forward))

        let roleContext = DeviceCapabilityModel.roleContext(for: basilisk(), configuration: config)

        // Button 5 (eventButton 4) is hold trigger with action
        let role5 = DeviceCapabilityModel.role(forEventButton: 4, context: roleContext)
        XCTAssertEqual(role5, .holdTriggerWithAction(.instant(.forward)))
        XCTAssertEqual(role5.labelKey, "Nút giữ • Tiến")

        // Button 4 (eventButton 3) is assigned instant back
        let role4 = DeviceCapabilityModel.role(forEventButton: 3, context: roleContext)
        XCTAssertEqual(role4, .assigned(.instant(.back)))
        XCTAssertEqual(role4.labelKey, "Đã gán: Lùi")

        // Button 3 (Middle click, eventButton 2) is unassigned
        let role3 = DeviceCapabilityModel.role(forEventButton: 2, context: roleContext)
        XCTAssertEqual(role3, .unassigned)
        XCTAssertEqual(role3.labelKey, "Chưa gán")

        // When holdButtonSingleClickEnabled is toggled off, Button 5 becomes plain .holdTrigger
        var configNoSingleClick = config
        configNoSingleClick.holdButtonSingleClickEnabled = false
        let roleContextNoSingle = DeviceCapabilityModel.roleContext(for: basilisk(), configuration: configNoSingleClick)
        let role5NoSingle = DeviceCapabilityModel.role(forEventButton: 4, context: roleContextNoSingle)
        XCTAssertEqual(role5NoSingle, .holdTrigger)
        XCTAssertEqual(role5NoSingle.labelKey, "Nút giữ")
    }

    func testSniperButtonTruthOnBleAndUsb() {
        let config = GestureConfiguration()

        // On BLE, basilisk declares [1, 2, 3, 4, 5] (usages) -> eventButtons [0, 1, 2, 3, 4]
        let bleContext = DeviceCapabilityModel.roleContext(for: basilisk(), configuration: config)
        let sniperBleRole = DeviceCapabilityModel.role(forEventButton: 5, context: bleContext)
        XCTAssertEqual(sniperBleRole, .notDeclared)
        XCTAssertFalse(sniperBleRole.isDeclared)
        XCTAssertTrue(sniperBleRole.isAssignable, "Undeclared button must be assignable via Record")
        XCTAssertEqual(DeviceCapabilityModel.passthroughNoteKey(forEventButton: 5),
                       "Nút này do firmware chuột tự xử lý qua Bluetooth. Kết nối qua USB hoặc gán phím tắt trong Razer Synapse để dùng.")

        // On USB, 6-button mouse declares [1, 2, 3, 4, 5, 6] -> eventButtons [0, 1, 2, 3, 4, 5]
        let usbDescriptor = basilisk(usages: [1, 2, 3, 4, 5, 6])
        let usbContext = DeviceCapabilityModel.roleContext(for: usbDescriptor, configuration: config)
        let sniperUsbRole = DeviceCapabilityModel.role(forEventButton: 5, context: usbContext)
        XCTAssertEqual(sniperUsbRole, .unassigned)
        XCTAssertTrue(sniperUsbRole.isDeclared)

        // Assigning action to Button 6 (eventButton 5, display button 6)
        var configWithSniper = config
        configWithSniper.buttonActions[6] = .instant(.back)
        let sniperAssignedContext = DeviceCapabilityModel.roleContext(for: usbDescriptor, configuration: configWithSniper)
        let sniperAssignedRole = DeviceCapabilityModel.role(forEventButton: 5, context: sniperAssignedContext)
        XCTAssertEqual(sniperAssignedRole, .assigned(.instant(.back)))
        XCTAssertEqual(sniperAssignedRole.labelKey, "Đã gán: Lùi")
    }

    // MARK: - usagePageName

    /// `usagePageName` has four outcomes. Three were reachable from the other tests only by accident;
    /// "Other" and the `>=` boundary of "Vendor" were never called. Named constants, no bare numbers.
    func testUsagePageNameCoversEveryBranch() {
        XCTAssertEqual(DeviceCapabilityProbe.usagePageName(DeviceCapabilityProbe.usagePageButton), "Button")
        XCTAssertEqual(DeviceCapabilityProbe.usagePageName(DeviceCapabilityProbe.usagePageConsumer), "Consumer")

        // The boundary is load-bearing: `>=` (not `>`) is what makes a vendor page named "Vendor".
        XCTAssertEqual(DeviceCapabilityProbe.usagePageName(DeviceCapabilityProbe.usagePageVendorDefined), "Vendor")
        XCTAssertEqual(DeviceCapabilityProbe.usagePageName(DeviceCapabilityProbe.usagePageVendorDefined + 1), "Vendor")

        XCTAssertEqual(DeviceCapabilityProbe.usagePageName(DeviceCapabilityProbe.usagePageGenericDesktop), "Other")
        XCTAssertEqual(DeviceCapabilityProbe.usagePageName(DeviceCapabilityProbe.usagePageVendorDefined - 1), "Other")
    }
}
