import Foundation

// No AppKit dependencies: the test package compiles this exact file, not a copy.
enum TriggerSource: Codable, Equatable, Sendable {
    case mouseButton(Int)
    case modifierKey(UInt64)

    var label: String {
        switch self {
        case .mouseButton(let n): return TriggerSource.buttonName(n)
        case .modifierKey(let flags): return GestureShortcut(key: 0, flags: flags).modifierLabel
        }
    }

    /// The button number alone — "Nút 3". Used where a note would wrap the line.
    var numberedName: String {
        switch self {
        case .mouseButton(let n): return "Nút \(n + 1)"
        case .modifierKey(let flags): return GestureShortcut(key: 0, flags: flags).modifierLabel
        }
    }

    /// Buttons are named by the number macOS reports, because that is the only
    /// identifier that is true for **every** mouse. Physical names are not:
    /// Mac Mouse Fix, MOS and Razer all label the same hardware differently, and
    /// a Razer Basilisk's "Button 4" is a different control from a Magic Mouse's.
    /// Inventing "nút bắn tỉa" / "nút DPI" / "nút hông sau" was worse than the
    /// bare number — it asserted a layout nothing had measured.
    ///
    /// The three numbers every mouse shares get a short factual note in
    /// parentheses; the rest are the plain number.
    static func buttonName(_ n: Int) -> String {
        switch n {
        case 0:  return "Nút 1 (chuột trái)"
        case 1:  return "Nút 2 (chuột phải)"
        case 2:  return "Nút 3 (bấm con lăn xuống)"
        default: return "Nút \(n + 1)"
        }
    }

    var isValid: Bool {
        switch self {
        // Left click is deliberately reserved for selecting, dragging and emergency UI access.
        case .mouseButton(let n): return (1...31).contains(n)
        case .modifierKey(let f): return [1 << 17, 1 << 18, 1 << 19, 1 << 20].contains(f)
        }
    }
}

/// Whether this direction is performed by tilting the wheel rather than by
/// holding a button. Lives with the model so the direction title and the diagram
/// cannot disagree about which arms need a held trigger.
enum GestureTriggerKind {
    static func isTilt(_ direction: GestureDirection) -> Bool {
        direction == .tiltLeft || direction == .tiltRight
    }
}

enum GestureDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right, tiltLeft, tiltRight

    /// What the user sees in a heading or a compact list: the direction word plus
    /// the number of the mouse button they hold for it.
    ///
    /// It lives here rather than in the view because the page must never print a
    /// bare arrow: the user asked, verbatim, *"tôi ko hiểu dùng nút nào của chuột
    /// với mũi tên"* — an arrow does not say which button is held. One spelling
    /// for the heading, the detail panel and the tooltip.
    func title(trigger: TriggerSource) -> String {
        let (motion, hint): (String, String)
        switch self {
        case .up:        motion = "Kéo LÊN";        hint = "kéo lên"
        case .down:      motion = "Kéo XUỐNG";      hint = "kéo xuống"
        case .left:      motion = "Kéo SANG TRÁI";  hint = "kéo sang trái"
        case .right:     motion = "Kéo SANG PHẢI";  hint = "kéo sang phải"
        case .tiltLeft:  motion = "Nghiêng con lăn TRÁI";  hint = "nghiêng con lăn trái"
        case .tiltRight: motion = "Nghiêng con lăn PHẢI";  hint = "nghiêng con lăn phải"
        }
        guard !GestureTriggerKind.isTilt(self) else { return motion }
        return "\(trigger.numberedName): \(hint)"
    }

    /// "Nút 3" — the number alone, no note. Used where the full name would wrap.
    var shortLabel: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .tiltLeft: return "Tilt ←"
        case .tiltRight: return "Tilt →"
        }
    }
}

struct GestureShortcut: Codable, Equatable, Sendable {
    var key: UInt16
    var flags: UInt64
    static let shift: UInt64 = 1 << 17
    static let control: UInt64 = 1 << 18
    static let option: UInt64 = 1 << 19
    static let command: UInt64 = 1 << 20
    static let modifierMask = shift | control | option | command
    var modifierLabel: String {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .filter { flags & $0.0 != 0 }.map(\.1).joined()
    }
    var label: String {
        let names: [UInt16: String] = [0:"A", 3:"F", 9:"V", 13:"W", 17:"T", 24:"=", 27:"-",
            29:"0", 30:"]", 33:"[", 35:"P", 6:"Z", 48:"⇥", 50:"`", 116:"Page Up", 121:"Page Down",
            123:"←", 124:"→", 125:"↓", 126:"↑", 36:"↩", 49:"Space"]
        return modifierLabel + (names[key] ?? "Key \(key)")
    }
}

enum GestureAction: Codable, Equatable, Sendable {
    case unassigned
    case shortcut(GestureShortcut)
    // Explicit opt-in forwarding, not an assertion of app-specific timeline semantics.
    case horizontalScroll
}

struct GestureProfile: Identifiable, Sendable {
    var id: String
    var name: String
    var defaults: [GestureDirection: GestureAction]
}

// Built-in presets are the immutable factory layer. The resolver is the single
// source of truth for both the Settings UI and the runtime engine:
//   1. explicit per-bundle override in `overrides[bundle]`
//   2. explicit shared overrides for the built-in profile family `overrides[profileId]`
//      (legacy alias — preserved for upgrades, not used for new saves)
//   3. built-in preset for that exact bundleId, or Global for an unknown app
//   4. `.unassigned` — and an explicit `.unassigned` override NEVER falls through.
enum GestureProfiles {
    static let fallback = "*"
    static func key(_ code: UInt16, _ flags: UInt64) -> GestureAction {
        .shortcut(GestureShortcut(key: code, flags: flags))
    }
    static let all: [GestureProfile] = {
        let c = GestureShortcut.command, ctrl = GestureShortcut.control
        let s = GestureShortcut.shift, o = GestureShortcut.option
        // Platform-standard text-editing keys, shared by every macOS app that has a
        // text surface: Kitty, Terminal and iTerm all set `macos_option_as_alt`
        // OFF by default precisely so ⌥←/⌥→ arrive as Option-Left/Option-Right, and
        // AppKit's own `moveWordBackward:` / `moveWordForward:` are documented in
        // the standard key bindings. So this is a real convention, not a guess.
        let wordLeft = GestureProfiles.key(123, o)
        let wordRight = GestureProfiles.key(124, o)
        let global: [GestureDirection: GestureAction] = [
            .up: key(33, c | s), .down: key(30, c | s), .left: key(33, c), .right: key(30, c),
            .tiltLeft: key(24, c), .tiltRight: key(27, c)]
        let browsers: [GestureDirection: GestureAction] = [
            .up: key(17,c), .down: key(13,c), .left:key(48,ctrl|s), .right:key(48,ctrl),
            .tiltLeft:key(17,c|s), .tiltRight:key(17,c|s)]
        // Ambiguous actions stay unassigned. A matching profile never silently falls
        // through to a destructive global action for one of its unassigned directions.
        let dev: [GestureDirection: GestureAction] = [.left:key(27,ctrl), .right:key(27,ctrl|s)]
        let design: [GestureDirection: GestureAction] = [.up:key(29,c), .down:key(6,c),
            .left:key(33,0), .right:key(30,0)]
        let chat: [GestureDirection: GestureAction] = [.left:key(126,o), .right:key(125,o)]
        let notes: [GestureDirection: GestureAction] = [.up:key(35,c), .left:key(123,c|o), .right:key(124,c|o)]
        // Terminals: Kitty (`net.kovidgoyal.kitty`), Terminal.app and iTerm2. Only
        // the two word-jump directions are shipped — they are the one pair that is
        // an OS convention rather than an app guess. Scrolling, splits and new
        // tabs were deliberately left Unassigned: ⌘T is a new *window* in Terminal,
        // ⌘W can kill a running command, and there is no shared "next pane" key.
        // A wrong keystroke in a terminal can destroy work, so here Unassigned is
        // the honest answer and "Đổi phím tắt" is one click away.
        let terminal: [GestureDirection: GestureAction] = [.left: wordLeft, .right: wordRight]
        var result = [GestureProfile(id:fallback,name:"Global",defaults:global)]
        for (id,name) in [("com.microsoft.edgemac","Microsoft Edge"),("com.apple.Safari","Safari"),("com.google.Chrome","Chrome")] {
            result.append(.init(id:id,name:name,defaults:browsers))
        }
        for (id,name) in [("com.visualstudio.code","VS Code"),("com.cursor.ide","Cursor"),("dev.zed.Zed","Zed"),("com.antigravity.ide","Antigravity"),("com.anthropic.claude","Claude")] {
            result.append(.init(id:id,name:name,defaults:dev))
        }
        for (id,name) in [("com.adobe.Photoshop","Photoshop"),("com.lemon.CapCutMac","CapCut")] {
            result.append(.init(id:id,name:name,defaults:design))
        }
        for (id,name) in [("com.hnc.Discord","Discord"),("com.vng.zalo","Zalo"),("org.telegram.ayugram","AyuGram")] {
            result.append(.init(id:id,name:name,defaults:chat))
        }
        for (id,name) in [("com.microsoft.Excel","Excel"),("com.microsoft.Word","Word")] {
            result.append(.init(id:id,name:name,defaults:[:]))
        }
        for (id,name) in [("net.kovidgoyal.kitty","Kitty"),("com.apple.Terminal","Terminal"),("com.googlecode.iterm2","iTerm2")] {
            result.append(.init(id:id,name:name,defaults:terminal))
        }
        for (id,name) in [("co.elastic.obsidian","Obsidian"),("com.notion.Notion-App","Notion")] {
            result.append(.init(id:id,name:name,defaults:notes))
        }
        return result
    }()

    /// Which preset governs a bundle, or nil when the app has none of its own and
    /// therefore inherits Global. Published so the UI can say "this app has no
    /// preset" without re-deriving the lookup and risking disagreement with the
    /// resolver.
    static func hasPreset(bundle: String) -> Bool {
        bundle != fallback && all.contains { $0.id == bundle }
    }

    /// Single resolver for both Settings row display and GestureWorker dispatch.
    static func resolve(overrides: [String: [GestureDirection: GestureAction]],
                        bundle: String,
                        direction: GestureDirection) -> GestureAction {
        if let explicit = overrides[bundle]?[direction] { return explicit }
        let profile = all.first { $0.id == bundle } ?? all[0]
        // Legacy alias: keep shared family overrides readable as second tier.
        if all.contains(where: { $0.id == bundle }), let shared = overrides[profile.id]?[direction] {
            return shared
        }
        return profile.defaults[direction] ?? .unassigned
    }
}

struct GestureConfiguration: Codable, Sendable {
    var enabled = false
    var trigger: TriggerSource = .mouseButton(2)
    // Raw event delta units, NOT calibrated screen points or physical millimetres.
    var deadzone = 12.0
    var tiltEnabled = false
    var debug = false
    // Default OFF on purpose, and the switch says so on the page: a Razer mouse
    // chosen by name in the product brief reports every wheel event as
    // `scrollWheelEventIsContinuous == 1` with axis2 == 0, measured on this
    // machine — so shipping this default on would draw two arms that can never
    // fire on the very hardware the feature was built for.
    var tiltAvailable = false
    // Persist ONLY genuine user overrides. Do not pre-fill with factory defaults.
    var overrides: [String: [GestureDirection: GestureAction]] = [:]

    func action(bundle: String, direction: GestureDirection) -> GestureAction {
        GestureProfiles.resolve(overrides: overrides, bundle: bundle, direction: direction)
    }

    func source(bundle: String, direction: GestureDirection) -> GestureRowSource {
        if overrides[bundle]?[direction] != nil { return .userOverride }
        let isKnown = GestureProfiles.all.contains { $0.id == bundle }
        if isKnown {
            let profile = GestureProfiles.all.first { $0.id == bundle }!
            if profile.defaults[direction] != nil { return .preset }
            return .unassigned
        }
        if GestureProfiles.all[0].defaults[direction] != nil { return .presetGlobal }
        return .unassigned
    }

    mutating func validate() {
        if !trigger.isValid { trigger = .mouseButton(2) }
        deadzone = deadzone.isFinite ? min(200, max(4, deadzone)) : 12
    }
}

enum GestureRowSource: Sendable { case preset, presetGlobal, userOverride, unassigned }

struct GestureStroke: Sendable {
    private(set) var x = 0.0
    private(set) var y = 0.0
    private(set) var distance = 0.0
    mutating func move(dx: Double, dy: Double) {
        x += dx; y += dy
        distance += hypot(dx, dy)
    }
    func direction(deadzone: Double) -> GestureDirection? {
        guard distance >= deadzone, hypot(x,y) >= deadzone else { return nil }
        return abs(x) > abs(y) ? (x < 0 ? .left : .right) : (y < 0 ? .up : .down)
    }
    func isClick(deadzone: Double) -> Bool { distance < deadzone }
}
