import Foundation

// The **pure** capability vocabulary and derivation, with no IOKit and no AppKit.
//
// Why this file is separate from `DeviceCapability.swift`
// -------------------------------------------------------
// That file owns the live probe: `IOHIDManagerCreate`, `IOHIDManagerCopyDevices`,
// the element walk. It imports `IOKit.hid`, which means a plain-Foundation test
// package cannot compile it — and a unit test that opened an IOHID manager and
// asserted on whatever mouse happened to be plugged in would be theatre anyway: it
// would pass on the author's desk and fail everywhere else.
//
// So the split is by *testability*, not by taste:
//
//   * `DeviceCapability.swift` — plumbing. Not in the test package.
//   * this file                 — every decision. Symlinked into the test package.
//   * `DeviceCapabilityModel.swift` — the resolution the UI consumes. Also symlinked.
//
// The filter bug that produced "873 input-button elements" lives on the boundary,
// so `buttonUsages(from:)` is here on purpose: it is the one function that must
// never regress, and this placement is what lets the fixture pin it.
//
// ── THE FILTER BUG THAT MUST NOT COME BACK ──────────────────────────────────
// An earlier probe selected button elements with
//
//      el.usagePage == 0x01 && el.usage == 0x09        // WRONG — never do this
//
// 0x01/0x09 is Generic Desktop / Button **collection**. It matches the collection
// node rather than the individual button elements and, on a real Razer
// "BSKV3P 35K", counted **898 matching elements and printed "873 input-button
// elements"** — a number larger than the mouse has controls, reported as if it
// were a button count. It was a filter bug, not a discovery about the hardware.
//
// The correct filter needs **both** guards:
//
//      type == kIOHIDElementTypeInput_Button && usagePage == 0x09
//
// Measured on a real Basilisk that yields usages `[1, 2, 3, 4, 5]`, which is what
// the mouse has. The page guard is load-bearing: with the type check alone, a
// Generic-Desktop `0x01 / 0x09` element carrying the button element type is still
// admitted, and building that exact fixture produced `[1,2,3,4,5,9]` — a sixth
// button that does not exist.
//
// ── DUPLICATE DEVICES ───────────────────────────────────────────────────────
// `IOHIDManagerCopyDevices` returns duplicates for one physical device: the probe
// saw **2 identical Basilisk entries and 2 identical trackpad entries**. A device
// that appears twice would otherwise be offered twice in a picker, so
// `deduplicated(_:)` collapses them on (vendorID, productID, productName,
// transport). First occurrence wins.
//
// ── ABSENT PROPERTIES ARE `nil`, NEVER A FABRICATED NUMBER ──────────────────
// The Apple Internal Keyboard / Trackpad matches the pointer criteria but does
// **not** carry `kIOHIDVendorIDKey` / `kIOHIDProductIDKey` at all. A missing key is
// `nil` — never `-1`, never `0`, never a guess. When either is absent the
// descriptor cannot be attributed to a specific product, so it reports
// `confidence: .unknown`, and `DeviceCapabilityModel` then refuses to read that
// device's *absences* as evidence.

/// Where a capability set came from. `detected` is a real probe result;
/// `manual` is a user- or profile-supplied override; `fallback` is the safe
/// default used when nothing better is available.
enum CapabilitySource: String, Codable, Sendable {
    case detected, manual, fallback
}

/// How much the capability set should be trusted.
///
/// `.unknown` is the required value whenever identity is incomplete (vendor or
/// product absent), because a capability list that cannot be tied to a known
/// product is not evidence about the hardware.
enum CapabilityConfidence: String, Codable, Sendable {
    case verified, inferred, unknown
}

/// What the device declares in its HID descriptor.
struct PhysicalCapabilities: Codable, Equatable, Sendable {
    /// HID button usages, e.g. `[1, 2, 3, 4, 5]`. Usage 1 is the left button.
    var buttons: [Int]
    /// Canonical axis tokens: `"x"`, `"y"`, `"wheel"`, `"tiltLeft"`,
    /// `"tiltRight"`, `"wheelThumb"`. Only declared axes appear.
    var axes: [String]
    /// Whether any button-page element was seen at all. This distinguishes "a
    /// device with no buttons" from "a descriptor that could not be read".
    var hasButtonPage: Bool
}

/// What the mouse module may attempt with this hardware. Derived purely from
/// `PhysicalCapabilities` so it is testable without hardware.
struct FeatureCapabilities: Codable, Equatable, Sendable {
    var supportsButtonRemapping: Bool
    var supportsFourWayHoldDrag: Bool
    var supportsTiltArms: Bool
}

/// One pointing device, fully described.
struct CapabilityDescriptor: Codable, Equatable, Sendable {
    var transport: String
    /// `nil` when the device does not declare the key — never a fake number.
    var vendorID: Int?
    /// `nil` when the device does not declare the key — never a fake number.
    var productID: Int?
    var productName: String
    var physical: PhysicalCapabilities
    var features: FeatureCapabilities
    var source: CapabilitySource
    var confidence: CapabilityConfidence
}

/// The element facts the derivation reasons about, lifted out of `IOHIDElementRef`
/// so a fixture test can express them as plain values. The live probe reads these
/// three fields off each element and does nothing else with it.
struct HIDElementFact: Equatable, Sendable {
    var usagePage: Int
    var usage: Int
    /// `IOHIDElementGetType(_:)` as a raw value.
    var type: UInt32

    init(usagePage: Int, usage: Int, type: UInt32) {
        self.usagePage = usagePage
        self.usage = usage
        self.type = type
    }
}

/// Just property values, before any derivation. A fixture can build this and hand
/// it to `descriptor(from:)` with no IOHID in the process.
struct HIDDeviceProperties: Equatable, Sendable {
    var transport: String
    var vendorID: Int?
    var productID: Int?
    var productName: String
    var elements: [HIDElementFact]
    var source: CapabilitySource
}

/// The dedupe key. Hashable so it can back a `Set`.
struct DeviceIdentity: Hashable, Sendable {
    var vendorID: Int?
    var productID: Int?
    var productName: String
    var transport: String
}

/// The pure half of the capability probe: element facts in, capabilities out.
enum DeviceCapabilityProbe {

    // MARK: Constants

    /// Generic Desktop usage page: axes and other top-level controls.
    static let usagePageGenericDesktop = 0x01
    /// Button usage page. Buttons are identified by element *type*, not by a
    /// usage pair — see the filter-bug note in the file header.
    static let usagePageButton = 0x09

    static let axisUsageX = 0x30
    static let axisUsageY = 0x31
    static let axisUsageWheel = 0x38
    static let axisUsageTiltLeft = 0x3C
    static let axisUsageTiltRight = 0x3D
    static let axisUsageWheelThumb = 0x3E

    /// `kIOHIDElementTypeInput_Button` — the type a real button element carries.
    /// Spelled as a literal so the pure helpers stay free of IOKit symbols.
    static let elementTypeInputButton: UInt32 = 0x02
    /// `IOHIDElementGetType` never returns a raw 0, so this literal is a safe
    /// stand-in for unreadable elements. Such elements are not buttons.
    static let elementTypeUnknown: UInt32 = 0

    // MARK: Pure: elements → usages

    /// The correct button filter. Returns the button usages, ascending and
    /// de-duplicated — a descriptor can legitimately repeat a usage across reports,
    /// and a repeated usage is still one physical control.
    static func buttonUsages(from elements: [HIDElementFact]) -> [Int] {
        var seen = Set<Int>()
        for el in elements where el.type == elementTypeInputButton && el.usagePage == usagePageButton {
            seen.insert(el.usage)
        }
        return seen.sorted()
    }

    /// Tuple convenience for a fixture that does not want to name the type.
    static func buttonUsages(fromTriples triples: [(usagePage: Int, usage: Int, type: UInt32)]) -> [Int] {
        buttonUsages(from: triples.map { HIDElementFact(usagePage: $0.usagePage, usage: $0.usage, type: $0.type) })
    }

    // MARK: Pure: elements → axes

    /// Canonical token for a Generic-Desktop axis usage, or nil when the element is
    /// not one of the documented axes. Returning nil rather than a generic token is
    /// deliberate: an unrecognised usage must not be presented as a capability.
    static func axisToken(usagePage: Int, usage: Int) -> String? {
        guard usagePage == usagePageGenericDesktop else { return nil }
        switch usage {
        case axisUsageX: return "x"
        case axisUsageY: return "y"
        case axisUsageWheel: return "wheel"
        case axisUsageTiltLeft: return "tiltLeft"
        case axisUsageTiltRight: return "tiltRight"
        case axisUsageWheelThumb: return "wheelThumb"
        default: return nil
        }
    }

    static func axisTokens(from elements: [HIDElementFact]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for el in elements {
            guard let token = axisToken(usagePage: el.usagePage, usage: el.usage) else { continue }
            if seen.insert(token).inserted { order.append(token) }
        }
        return order
    }

    // MARK: Pure: elements → physical

    /// Builds `PhysicalCapabilities` from element facts. `hasButtonPage` is true
    /// when any element at all arrives on the button page, even if no usable
    /// button element was found — that keeps "declares buttons but we could not
    /// read them" distinct from "declares no buttons".
    static func physicalCapabilities(from elements: [HIDElementFact]) -> PhysicalCapabilities {
        PhysicalCapabilities(
            buttons: buttonUsages(from: elements),
            axes: axisTokens(from: elements),
            hasButtonPage: elements.contains { $0.usagePage == usagePageButton }
        )
    }

    // MARK: Pure: physical → features

    /// Derives what the mouse module may attempt, **from the descriptor alone**.
    ///
    /// - `supportsButtonRemapping` — there is something beyond left and right to
    ///   bind. Needs `buttons.count > 2`.
    ///
    /// - `supportsFourWayHoldDrag` — there is a button usable as a hold trigger.
    ///   Any usage `>= 3` qualifies. **The left button is reserved** and usage 1
    ///   never satisfies this test, because left click must stay available for
    ///   selecting, dragging and emergency UI access; a gesture that consumed it
    ///   would remove the one control the user always has.
    ///
    /// - `supportsTiltArms` — true only when the descriptor declares a horizontal
    ///   wheel axis. **Tilt is deliberately NOT inferred from the button page**,
    ///   however many extra buttons exist: measured on this machine, the Razer
    ///   Basilisk and the Apple Magic Mouse both report every wheel event with
    ///   `scrollWheelEventIsContinuous == 1` and axis2 == 0, i.e. as continuous
    ///   scrolling rather than discrete tilt. Inferring the arms from a button count
    ///   would draw two controls that can never fire on the hardware the feature was
    ///   built for.
    static func features(from physical: PhysicalCapabilities) -> FeatureCapabilities {
        let hasHoldCandidate = physical.buttons.contains { $0 >= 3 }
        let hasTiltAxis = physical.axes.contains("tiltLeft") || physical.axes.contains("tiltRight")
        return FeatureCapabilities(
            supportsButtonRemapping: physical.buttons.count > 2,
            supportsFourWayHoldDrag: hasHoldCandidate,
            supportsTiltArms: hasTiltAxis
        )
    }

    // MARK: Pure: properties → descriptor

    /// The single constructor used by both the live probe and tests, so tests
    /// never need hardware and the two paths cannot drift.
    ///
    /// Confidence rule, applied here so no call site can forget it:
    /// - vendor **and** product both known → `.verified`
    /// - product name present but an identifier missing → `.inferred`
    /// - no usable name and no identifiers → `.unknown`
    static func descriptor(from properties: HIDDeviceProperties) -> CapabilityDescriptor {
        let physical = physicalCapabilities(from: properties.elements)
        let hasIdentity = properties.vendorID != nil && properties.productID != nil
        let hasName = !properties.productName.isEmpty

        let confidence: CapabilityConfidence
        if hasIdentity {
            confidence = .verified
        } else if hasName {
            confidence = .inferred
        } else {
            confidence = .unknown
        }

        return CapabilityDescriptor(
            transport: properties.transport,
            vendorID: properties.vendorID,
            productID: properties.productID,
            productName: properties.productName,
            physical: physical,
            features: features(from: physical),
            source: properties.source,
            confidence: confidence
        )
    }

    /// Collapses duplicate reports of one physical device. Identity is the
    /// (vendor, product, name, transport) tuple; identifiers absent for both
    /// copies still compare equal, so two entries of the same unnamed trackpad
    /// dedupe to one.
    static func deduplicated(_ descriptors: [CapabilityDescriptor]) -> [CapabilityDescriptor] {
        var seen = Set<DeviceIdentity>()
        var result: [CapabilityDescriptor] = []
        for d in descriptors {
            let identity = DeviceIdentity(
                vendorID: d.vendorID,
                productID: d.productID,
                productName: d.productName,
                transport: d.transport
            )
            if seen.insert(identity).inserted { result.append(d) }
        }
        return result
    }
}
