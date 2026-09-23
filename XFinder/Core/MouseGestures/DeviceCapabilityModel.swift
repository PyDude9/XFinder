import Foundation

// The single resolution layer between the hardware probe (`DeviceCapability.swift`,
// which imports IOKit and cannot be compiled into the test package) and the page.
//
// Why this file exists separately: everything here is **pure** — it takes a
// `[CapabilityDescriptor]` and produces the exact answers the UI needs, with no
// hardware, no AppKit and no IOKit. That is what makes the L3/R3/R4 behaviour
// assertable in `Tests/`, where a live probe would be theatre.
//
//   * Which preset governs an app            → `presetBundle(for:)`
//   * Whether an arm can fire at all         → `armSupport(for:)`
//   * What provenance to print               → `CapabilityProvenance`
//
// It also carries the one fact the brief is emphatic about: **a failed probe is not
// a measured absence.** `.unknownUntilDetected` exists so an unreadable descriptor
// can never be rendered as "this mouse does not have that button".

/// The provenance of the device in force, plus the explanation the page must print
/// for it.
///
/// `ArmSupport` used to live in `MouseDiagramView.swift`, which imports SwiftUI and
/// therefore cannot be compiled into the test package. It is domain logic — "can
/// this mouse perform this direction?" — not view code, so it lives here where the
/// tests can reach it.

/// Whether the connected mouse can perform a direction at all.
///
/// This is the D2/D3 contract: an unsupported arm is **disabled with a localized
/// reason**, an arm whose support could not be determined says "unavailable until
/// detected" rather than claiming the hardware lacks it, and a supported arm
/// behaves exactly as before. `.unknown` exists so a failed probe can never be
/// presented as a measured absence.
enum ArmSupport: Equatable, Sendable {
    case supported
    case unsupportedByMouse
    case unknownUntilDetected

    var isSupported: Bool { self == .supported }
}

/// Where the capability set currently driving the diagram came from.
///
/// The brief requires "Detected" and "You set this" to be distinguishable and
/// forbids presenting guessed data as `Detected`. A manual pick is an override, not
/// evidence, so it carries its own case.
enum CapabilityProvenance: Equatable, Sendable {
    /// A real IOHID probe produced this descriptor.
    case detected(productName: String, vendorID: Int?, productID: Int?)
    /// The user picked the device/preset themselves, or nothing could be probed.
    case manual
    /// No usable descriptor: the probe returned nothing, or returned only devices
    /// with no readable identity. Distinct from `manual` because the *reason* the
    /// UI must state differs.
    case unavailable

    var isDetected: Bool {
        if case .detected = self { return true }
        return false
    }
}

/// The answer the diagram needs per arm, and nothing more.
enum DeviceCapabilityModel {

    /// The preset key that governs `bundle`, or `nil` when the app has no built-in
    /// profile and therefore inherits Global.
    ///
    /// Kept here rather than re-derived in the view so the diagram, the badge and the
    /// runtime engine all read one lookup — the brief's "one resolver for UI and
    /// runtime, not two copies of mapping logic".
    static func presetBundle(for bundle: String) -> String? {
        GestureProfiles.hasPreset(bundle: bundle) ? bundle : nil
    }

    /// Whether a direction can be performed on the connected device.
    ///
    /// This is the D2/D3 contract in one function:
    ///
    /// * `.supported` — the descriptor declares what the direction physically needs.
    /// * `.unsupportedByMouse` — the descriptor was read successfully and the thing
    ///   the direction needs is genuinely absent. Only reachable from a `.verified`
    ///   descriptor, because that is the only confidence level where the absence is
    ///   evidence about a specific product.
    /// * `.unknownUntilDetected` — nothing was probed, or the descriptor's identity
    ///   is incomplete. The brief is explicit that this must NOT be presented as
    ///   "unsupported".
    ///
    /// Tilt is special: `supportsTiltArms` is deliberately derived from the declared
    /// horizontal axis, never from a button count (see `DeviceCapabilityProbe`), so a
    /// mouse with five buttons and no tilt axis still reports tilt unsupported.
    static func armSupport(for direction: GestureDirection,
                           device: CapabilityDescriptor?) -> ArmSupport {
        if let device = device {
            if capabilityField(for: direction)(device) { return .supported }
            // A declared capability is positive evidence regardless of identity.
            // Missing one is not evidence when we cannot attribute the descriptor to
            // a product — only a `.verified` identity makes an absence a fact.
            if device.confidence != .verified { return .unknownUntilDetected }
            return .unsupportedByMouse
        }
        return .unknownUntilDetected
    }

    /// Which capability flag answers for a direction. Never returns nil: both arms
    /// of the `isTilt` split have exactly one flag that decides them.
    private static func capabilityField(
        for direction: GestureDirection
    ) -> (CapabilityDescriptor) -> Bool {
        if GestureTriggerKind.isTilt(direction) {
            return { $0.features.supportsTiltArms }
        }
        return { $0.features.supportsFourWayHoldDrag }
    }

    /// The user-facing name of the device currently in force, or `nil` when none
    /// could be read. Never invents a name: an unnamed device prints its IDs.
    static func deviceLabel(_ provenance: CapabilityProvenance) -> String? {
        guard case .detected(let name, let vendorID, let productID) = provenance else { return nil }
        if !name.isEmpty { return name }
        if let v = vendorID, let p = productID {
            return String(format: "%04X:%04X", v, p)
        }
        return nil
    }
}

/// Chooses which connected device is "the mouse" for this session.
///
/// **D4: single mouse at a time.** There is no multi-device selection, no per-device
/// profile matrix and no attempt to attribute an event to a device — the brief locks
/// this because per-device attribution is not answerable from a CGEvent tap (C1).
///
/// The choice is deliberately boring: a real mouse beats a trackpad beats anything,
/// and ties are broken by the order IOHID reported. What it must NOT do is invent a
/// device: an empty list yields `nil`, which the caller renders as "not detected"
/// rather than as "no buttons".
enum DeviceSelection {

    /// Rank a descriptor for selection. Higher wins.
    ///
    /// A product name containing "mouse" wins outright; that is a heuristic and it is
    /// labelled as one, but it is only used to *order* candidates we can already see
    /// — never to fabricate one. Trackpads ("trackpad", "touchpad") lose to a mouse
    /// but beat an unidentifiable device, because a trackpad at least has real axes.
    /// Rank a descriptor for selection. Higher wins.
    ///
    /// The ranking is a heuristic and is labelled as one — but it is only ever used
    /// to **order candidates we can already see**, never to fabricate one. The
    /// ordering must survive a real-world naming problem: the Razer Basilisk reports
    /// its product name as `"BSKV3P 35K"`, which contains neither "mouse" nor
    /// "Magic". An earlier version of this function therefore ranked the internal
    /// Apple Magic Trackpad above the very mouse the feature was built for — a bug a
    /// test caught.
    ///
    /// So the ordering keys on what the device *does*, with the name as a tie-breaker
    /// only:
    ///   1. a usable hold button — the feature cannot run without one
    ///   2. more buttons
    ///   3. the product name mentions a mouse / does not mention a trackpad
    static func rank(_ device: CapabilityDescriptor) -> Int {
        var score = 0
        // Capability first, because it is evidence rather than a guess: a device you
        // can actually perform a gesture with is the one this page is about.
        if device.features.supportsFourWayHoldDrag { score += 1000 }
        score += min(device.physical.buttons.count, 20) * 10
        if device.confidence == .verified { score += 5 }

        // Name heuristics last, and only for devices that are otherwise tied. These
        // are the *least* trustworthy signal on the page, which is why they carry the
        // smallest weight and never decide on their own.
        let name = device.productName.lowercased()
        if name.contains("trackpad") || name.contains("touchpad") { score -= 3 }
        if name.contains("mouse") { score += 3 }
        return score
    }

    /// The device in force for this session, or `nil` when nothing was probed.
    ///
    /// `override` is the manual picker's choice. It is honoured as-is and **never
    /// silently replaced by a detection result** — the brief calls that out by name,
    /// because a user who pinned a device must not have the page drift underneath
    /// them. Detection only decides when the user has not chosen.
    static func active(from devices: [CapabilityDescriptor],
                       override: CapabilityDescriptor? = nil) -> CapabilityDescriptor? {
        if let override { return override }
        return devices.max { rank($0) < rank($1) }
    }

    /// The provenance to display for `active`. `detected` is only ever returned for a
    /// device that came from a probe; a device the caller supplied counts as `manual`
    /// unless it carries `source == .detected`.
    static func provenance(for device: CapabilityDescriptor?) -> CapabilityProvenance {
        guard let device else { return .unavailable }
        guard device.source == .detected else { return .manual }
        return .detected(productName: device.productName,
                         vendorID: device.vendorID,
                         productID: device.productID)
    }
}
