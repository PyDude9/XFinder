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

// MARK: - Controls and roles

/// A control the diagram draws, and the event button number it answers for.
///
/// The archetype is one mouse's layout — the Razer Basilisk this feature was built
/// for — used purely as a **drawing schema**. It is not a claim about the connected
/// device: which of these slots the hardware actually has comes from the probe, and a
/// slot the descriptor does not declare is drawn disabled rather than omitted, so the
/// user can see that something is missing instead of wondering where it went.
///
/// `rawValue` is the **0-based `CGEvent` button number**, not the HID usage. The
/// conversion from usages lives in `eventButtons(from:)`, in one place, because
/// getting it wrong shifts every label on the page by one.
enum MouseControlSlot: Int, CaseIterable, Sendable {
    case left = 0
    case right = 1
    case middle = 2
    case sideUpper = 3
    case sideLower = 4
    case sniper = 5

    var eventButton: Int { rawValue }

    /// The **archetype drawing's** short name for this position, as a store key.
    ///
    /// This describes the *drawing*, not the user's hardware — the caption under a chip
    /// says where that chip sits on the reference mouse, and the list says which controls
    /// the descriptor actually declares. Keeping the two claims separate is the point:
    /// no macOS API can report where a physical button sits, so the diagram must never
    /// present its layout as a measurement.
    ///
    /// A store key, never a sentence — `L10n.t(variable)` is the leak shape that reached
    /// the English page four times, and this file is in the Foundation-only half where a
    /// rendered string would be invisible to every literal sweep.
    var positionKey: String {
        switch self {
        case .left: return "Trái"
        case .right: return "Phải"
        case .middle: return "Con lăn"
        case .sideUpper: return "Hông trên"
        case .sideLower: return "Hông dưới"
        case .sniper: return "Hông cuối"
        }
    }

    /// Every slot the archetype figure has a place for, ascending.
    static var archetypeSlots: [MouseControlSlot] { allCases }

    /// The slot for an arbitrary button number, or `nil` when a mouse has more
    /// controls than the drawing has places for. Such a button is still listed and
    /// still assignable — it simply has no archetype position to sit in, and inventing
    /// one would be a claim about hardware nobody measured.
    static func slot(forEventButton n: Int) -> MouseControlSlot? {
        MouseControlSlot(rawValue: n)
    }
}

/// What one of the mouse's controls currently does.
///
/// Deliberately separate from `ArmSupport`: that answers "can this mouse perform this
/// direction?", this answers "what is this control doing right now?". Both are needed
/// and neither implies the other.
enum MouseButtonRole: Equatable, Sendable {
    /// The button held to start a four-way gesture.
    case holdTrigger
    /// The button held to start gestures, but also configured for instant action on click.
    case holdTriggerWithAction(ButtonAction)
    /// An assigned action (e.g. Back/Forward) on a non-trigger button.
    case assigned(ButtonAction)
    /// The button held to scroll (Engine C), only when that feature is on.
    case scrollButton
    /// Left and right click. The engine never consumes them at any setting: they are
    /// the controls the user always has, and a gesture that took one would remove the
    /// escape route from a gesture that misbehaved.
    case reserved
    /// Declared by the mouse, and currently sending nothing.
    case unassigned
    /// The descriptor was read and does not declare this control.
    case notDeclared
    /// Nothing was read, so whether this control exists is not known either. Distinct
    /// from `notDeclared` for the same reason `ArmSupport.unknownUntilDetected` is: a
    /// failed read is not a measured absence.
    case unknown

    /// Whether the user may point this control at the hold trigger. Everything except
    /// left/right, **including** a control the probe did not declare: a descriptor that
    /// under-reports is exactly the case the press-to-record path exists for, and
    /// refusing to let the user assign a button they can physically press would make
    /// the probe's limitation into the user's problem.
    var isAssignable: Bool { self != .reserved }

    /// Whether the descriptor actually put this control on the mouse (PATCH v10.1 R2).
    ///
    /// ── Why the drawing needs this, and why it is NOT the same as `isAssignable` ────────
    /// The two answer different questions and must not be collapsed:
    ///
    ///  * `isAssignable` — *may the user point the hold trigger at it?* True for a
    ///    control the descriptor never declared, because a real press is stronger
    ///    evidence than a descriptor and the user must be able to use the button they
    ///    can physically press.
    ///  * `isDeclared` — *did the read put this control on the mouse?* False for
    ///    `.notDeclared` and `.unknown`, and it is the one the **chip on the figure**
    ///    reads. A chip drawn as a live control claims XFinder can see that button; on a
    ///    control the descriptor does not declare, that claim is exactly the one the
    ///    "press Record" path exists to disprove, so the chip is drawn disabled and the
    ///    row below keeps the Record button that measures the truth.
    ///
    /// `.unknown` is false for the same reason `ArmSupport.unknownUntilDetected` is not
    /// `.unsupportedByMouse`: nothing was read, so nothing was declared either — but that
    /// is a fact about the *read*, and the tooltip says so rather than saying the mouse
    /// lacks the button.
    var isDeclared: Bool {
        switch self {
        case .notDeclared, .unknown: return false
        default: return true
        }
    }

    /// A **store key**, resolved by `L10n`. Never a sentence: a `String` member here is
    /// how Vietnamese reached the English page in earlier rounds, and this type lives in
    /// the Foundation-only half of the module where no test could catch it.
    var labelKey: String {
        switch self {
        case .holdTrigger: return "Nút giữ"
        case .holdTriggerWithAction(let action):
            switch action {
            case .instant(.forward): return "Nút giữ • Tiến"
            case .instant(.back): return "Nút giữ • Lùi"
            case .shortcut: return "Nút giữ"
            case .unassigned: return "Nút giữ"
            }
        case .assigned(let action):
            switch action {
            case .instant(.back): return "Đã gán: Lùi"
            case .instant(.forward): return "Đã gán: Tiến"
            case .shortcut: return "Đã gán: Phím tắt"
            case .unassigned: return "Chưa gán"
            }
        case .scrollButton: return "Nút cuộn"
        case .reserved: return "Chỉ bấm"
        case .unassigned: return "Chưa gán"
        case .notDeclared: return "Chuột không khai báo"
        case .unknown: return "Chưa đọc được"
        }
    }

    /// Why the control reads the way it does. A store key, same rule as `labelKey`.
    var explanationKey: String {
        switch self {
        case .holdTrigger:
            return "Giữ nút này rồi kéo một trong bốn hướng để chạy cử chỉ."
        case .holdTriggerWithAction(let action):
            switch action {
            case .instant(.forward):
                return "Bấm nhanh nút này để gửi phím tắt tiến. Giữ nút này rồi kéo một trong bốn hướng để chạy cử chỉ."
            case .instant(.back):
                return "Bấm đơn gửi phím tắt Lùi (Cmd+[). Giữ nút này có thể dùng làm nút giữ cử chỉ nếu được chọn."
            default:
                return "Bấm đơn gửi phím tắt đã gán. Giữ nút này rồi kéo một trong bốn hướng để chạy cử chỉ."
            }
        case .assigned(let action):
            switch action {
            case .instant(.back):
                return "Bấm đơn gửi phím tắt Lùi (Cmd+[). Giữ nút này có thể dùng làm nút giữ cử chỉ nếu được chọn."
            case .instant(.forward):
                return "Bấm đơn gửi phím tắt Tiến (Cmd+]). Giữ nút này có thể dùng làm nút giữ cử chỉ nếu được chọn."
            case .shortcut:
                return "Bấm đơn gửi phím tắt đã gán."
            case .unassigned:
                return "Chuột có nút này nhưng hiện chưa gán gì cho nó."
            }
        case .scrollButton:
            return "Giữ nút này rồi kéo là cuộn, không cần nhấc tay khỏi chuột."
        case .reserved:
            return "Nút bấm trái và phải luôn được giữ nguyên — XFinder không bao giờ chiếm hai nút này."
        case .unassigned:
            return "Chuột có nút này nhưng hiện chưa gán gì cho nó."
        case .notDeclared:
            return "Mô tả HID của chuột không khai báo nút này. Nếu chuột bạn thật sự có nó, hãy bấm nút đó rồi dùng “Ghi nút thật” — số XFinder nhận được là sự thật đo được, còn mô tả chỉ là khai báo."
        case .unknown:
            return "Chưa đọc được mô tả chuột, nên chưa biết chuột có nút này hay không."
        }
    }
}

/// Which figure the diagram should draw for the device in force (PATCH v10 R2).
///
/// ── Why the drawing is not always the six-slot archetype ─────────────────────────────
/// The archetype figure is the reference multi-button mouse: left, right, wheel, two
/// thumb buttons and a Sniper button. It is the right drawing for the hardware this
/// feature was built for, and drawing it for *everything* is what makes the page lie
/// about a device that is not that mouse — six chips on a one-button Magic Mouse reads
/// as "XFinder sees six buttons", which is the opposite of what was measured.
///
/// So the style is derived from the descriptor, and the fallback is stated:
///
/// * `.archetype` — a device that declares three or more buttons is a multi-button
///   mouse, and the six positions are the drawing that can explain it.
/// * `.generic` — anything else. Only the controls the descriptor declared are drawn.
/// * `.unknown` — nothing was read. The archetype is still drawn, **greyed and labelled
///   "not read yet"**, because a blank figure would read as "your mouse has no buttons",
///   and a failed probe is not a measured absence.
enum MouseDiagramStyle: Equatable, Sendable {
    case archetype
    case generic
    case unknown
}

/// A control that lives on the mouse itself and never reaches macOS (PATCH v10 R2).
///
/// ── What is measured and what is inferred ────────────────────────────────────────────
/// **Measured**: the descriptor of the mouse in this repo declares five button usages
/// (`[1, 2, 3, 4, 5]`), i.e. left, right, wheel and the two thumb buttons. Its
/// scroll-mode, DPI and profile controls are *not* in that list, and neither is the
/// Sniper button — which is why the page says so rather than pretending to see six.
///
/// **Inferred**: the usual reason a control is absent from a HID descriptor is that the
/// mouse's own firmware handles it. That is a plausible explanation, not a measurement,
/// and the copy is worded so the user can tell the difference: the page states the
/// *observation* (not declared) and offers the *test* (press it — the Record path reports
/// whatever number arrives, or reports nothing at all if the button is firmware-only).
struct MouseHardwareExclusion: Equatable, Sendable {
    /// A store key. Never a sentence — see `MouseControlSlot.positionKey`.
    var titleKey: String
    /// A store key explaining what this control does and why it is not listable.
    var explanationKey: String

    /// The three controls on the reference mouse that no HID button element carries.
    ///
    /// Named after the reference hardware's own labelling so the user can find them on
    /// their mouse. They are *examples*, not a claim about every mouse: the page presents
    /// them as "controls like these", and the measured evidence is the button count.
    static let all: [MouseHardwareExclusion] = [
        .init(titleKey: "Đổi chế độ con lăn",
              explanationKey: "Trên chuột có nút riêng cho việc này thì nó do firmware của chuột xử lý — mô tả HID không khai báo nó, nên XFinder không thấy và không gán được."),
        .init(titleKey: "Đổi DPI",
              explanationKey: "Nút đổi độ nhạy thường được firmware xử lý ngay trong chuột. XFinder chỉ biết tới những nút mà mô tả HID khai báo."),
        .init(titleKey: "Đổi hồ sơ",
              explanationKey: "Nút chuyển hồ sơ lưu trong bộ nhớ chuột, không gửi sự kiện nào ra macOS — không API nào đọc được nó."),
    ]
}

/// Everything `MouseCapabilityModel.role(for:)` needs, bundled so a call site cannot
/// pass three of the four facts and silently get a wrong answer.
struct MouseRoleContext: Equatable, Sendable {
    var trigger: TriggerSource
    var scrollButton: Int
    var scrollButtonEnabled: Bool
    /// The **0-based event button numbers** the descriptor declares, or `nil` when
    /// nothing was read. `nil` and `[]` mean different things and must not be collapsed.
    var declaredEventButtons: [Int]?
    /// Whether the descriptor carries a complete identity. Only then is an absence
    /// evidence about the product rather than about the read.
    var identityVerified: Bool
    var buttonActions: [Int: ButtonAction] = [:]
    var holdButtonSingleClickEnabled: Bool = true
}

extension DeviceCapabilityModel {

    /// The event button numbers a descriptor declares, or `nil` when none was read.
    ///
    /// ── The one conversion from HID usages to `CGEvent` numbers ─────────────────────
    /// `PhysicalCapabilities.buttons` holds **HID usages** (`[1, 2, 3, 4, 5]`, usage 1 is
    /// the primary button); `CGEvent`/`NSEvent` report a **0-based** `buttonNumber` where
    /// 0 is the primary button. So usage `N` answers for event button `N - 1`.
    ///
    /// This correspondence is the documented HID convention rather than something this
    /// code measured, so it is stated here once and treated as an **inference**: the
    /// press-to-record path measures the real number on real hardware and overrides it.
    /// Getting it wrong would shift every label by one, which is why it is one function
    /// with a test rather than a `- 1` sprinkled through the views.
    static func eventButtons(from device: CapabilityDescriptor?) -> [Int]? {
        guard let device else { return nil }
        return device.physical.buttons
            .map { $0 - 1 }
            .filter { $0 >= 0 }
            .sorted()
    }

    /// The role context for a device, so the view and the tests build it the same way.
    static func roleContext(for device: CapabilityDescriptor?,
                            configuration: GestureConfiguration) -> MouseRoleContext {
        MouseRoleContext(
            trigger: configuration.trigger,
            scrollButton: configuration.scrollButton,
            scrollButtonEnabled: configuration.scrollButtonEnabled,
            declaredEventButtons: eventButtons(from: device),
            identityVerified: device?.confidence == .verified,
            buttonActions: configuration.buttonActions,
            holdButtonSingleClickEnabled: configuration.holdButtonSingleClickEnabled
        )
    }

    /// What `button` is doing right now.
    ///
    /// The order of the checks is the contract, and only the first one is surprising:
    /// **an assignment beats everything else**. If the configuration points at the wheel
    /// or at the right button, the row must say so — the page's job is to report the
    /// stored truth, not the recommended one, and a row that showed "reserved" while the
    /// engine was consuming that button would be the worst kind of wrong.
    static func role(forEventButton button: Int,
                     context: MouseRoleContext) -> MouseButtonRole {
        if context.trigger.buttonNumber == button {
            if let assigned = GestureConfigStore.action(in: context.buttonActions, forEventButton: button),
               assigned.isAssigned, context.holdButtonSingleClickEnabled {
                return .holdTriggerWithAction(assigned)
            }
            return .holdTrigger
        }
        if context.scrollButtonEnabled, context.scrollButton == button { return .scrollButton }
        if button == 0 || button == 1 { return .reserved }
        if let assigned = GestureConfigStore.action(in: context.buttonActions, forEventButton: button),
           assigned.isAssigned {
            return .assigned(assigned)
        }
        guard let declared = context.declaredEventButtons else { return .unknown }
        if declared.contains(button) { return .unassigned }
        return context.identityVerified ? .notDeclared : .unknown
    }

    /// A press the engine actually saw that the descriptor does not declare, or `nil`.
    ///
    /// This is the honest answer to "the probe is under-reporting my mouse", and it is
    /// available only because the event tap already receives every press: the user
    /// presses their Sniper button, and if the number that arrives is not one the
    /// descriptor declared, that is a **measurement** — not a guess about the hardware and
    /// not a warning that fires on every mouse that simply has fewer buttons.
    ///
    /// Non-nil is also the exact condition under which the page should offer to record, so
    /// the prompt is caused by evidence rather than shown to everyone.
    static func undeclaredPress(observed: Int?, context: MouseRoleContext) -> Int? {
        guard let observed, let declared = context.declaredEventButtons else { return nil }
        return declared.contains(observed) ? nil : observed
    }

    /// The controls to draw, in archetype order: every slot the drawing has a place for,
    /// plus any extra button the mouse declares beyond them.
    ///
    /// Both halves matter. The first keeps the picture stable while the user unplugs the
    /// mouse (slots go disabled, they do not vanish); the second keeps a 10-button mouse
    /// from having controls the list never mentions.
    static func drawnButtons(declaredEventButtons: [Int]?) -> [Int] {
        let archetype = MouseControlSlot.allCases.map(\.eventButton)
        guard let declared = declaredEventButtons else { return archetype }
        return Array(Set(archetype).union(declared)).sorted()
    }

    // MARK: Pure: which figure to draw (R2)

    /// Which figure the diagram draws for the device in force.
    ///
    /// The threshold is three, and it is a property of the archetype rather than a taste
    /// setting: left + right + wheel is the smallest set that makes the six-position
    /// figure meaningful. Below that the generic figure draws exactly what was declared,
    /// which is the acceptance case "switch to a Magic Mouse and the diagram falls back
    /// to a plain one-button figure".
    static func diagramStyle(for device: CapabilityDescriptor?) -> MouseDiagramStyle {
        guard let device else { return .unknown }
        return device.physical.buttons.count >= 3 ? .archetype : .generic
    }

    /// The controls the generic figure draws: exactly what the descriptor declared, in
    /// order. Empty when nothing was declared — the figure then has no chips at all,
    /// which is the truthful drawing of "this device has no readable buttons".
    static func genericButtons(declaredEventButtons: [Int]?) -> [Int] {
        (declaredEventButtons ?? []).sorted()
    }

    /// How many button-typed elements the descriptor declares on a **vendor-defined**
    /// page. Evidence, not a button count — see
    /// `DeviceCapabilityProbe.vendorButtonUsages(from:)` for why the two cannot be added
    /// together.
    static func vendorControlCount(for device: CapabilityDescriptor?) -> Int {
        device?.physical.vendorButtonUsages.count ?? 0
    }

    /// Whether the descriptor under-reports this mouse, judged on **evidence** (R1).
    ///
    /// Two measured facts can establish it, and neither is a guess about the hardware:
    ///
    ///  * a press arrived whose number the descriptor never declared — the user pressed a
    ///    button, so the button exists and the descriptor is incomplete; or
    ///  * the descriptor declares fewer controls than the figure has positions **and**
    ///    declares extra vendor-page controls, i.e. the standard button page demonstrably
    ///    does not describe everything on this mouse.
    ///
    /// A mouse that simply has fewer buttons must NOT raise this. That is the difference
    /// between a prompt that reports a measurement and a prompt that is noise on every
    /// device — the v9.1 harness pins it as mutation M3.
    static func underReportedControls(declaredEventButtons: [Int]?,
                                      vendorControlCount: Int,
                                      observed: Int?,
                                      context: MouseRoleContext) -> Bool {
        if undeclaredPress(observed: observed, context: context) != nil { return true }
        guard let declared = declaredEventButtons else { return false }
        return declared.count < MouseControlSlot.archetypeSlots.count && vendorControlCount > 0
    }

    /// What a **single click** on this control does today, as a store key, or `nil` when
    /// there is nothing factual to say.
    ///
    /// Buttons 3 and 4 are the side buttons most applications already read as back and
    /// forward, and XFinder deliberately does not consume them: the engine takes only the
    /// hold trigger and the optional scroll modifier, so a plain click keeps reaching the
    /// application. Naming that is the honest form of the brief's "Instant Action" — the
    /// action already exists, it belongs to the application, and a row offering to rebind
    /// it would be a control whose label promises something the engine has no path for.
    static func passthroughNoteKey(forEventButton button: Int) -> String? {
        switch button {
        case 2:
            return "Bấm con lăn vẫn do ứng dụng xử lý (mở tab mới, cuộn tự động). XFinder không chiếm nút này."
        case 3:
            return "Mặc định: Lùi (Cmd+[ trong Safari/Chrome). Có thể đổi sang làm nút giữ cử chỉ."
        case 4:
            return "Mặc định: Bấm nhanh = Tiến (Cmd+]), giữ + kéo = cử chỉ."
        case 5:
            return "Nút này do firmware chuột tự xử lý qua Bluetooth. Kết nối qua USB hoặc gán phím tắt trong Razer Synapse để dùng."
        default:
            return nil
        }
    }
}
