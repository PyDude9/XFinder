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

    /// CoreGraphics numbers mouse buttons 0 = left, 1 = right, 2 = middle/wheel.
    /// "Button 2" alone is meaningless to a user, and some vendors print a
    /// *different* number on the mouse, so name the physical button and keep the
    /// raw code in parentheses for the rare case where they disagree.
    static func buttonName(_ n: Int) -> String {
        switch n {
        case 0:  return "Nút trái (Button 0)"
        case 1:  return "Nút phải (Button 1)"
        case 2:  return "Nút giữa / bấm con lăn (Button 2)"
        case 3:  return "Nút hông sau — nút 4 (Button 3)"
        case 4:  return "Nút hông trước — nút 5 (Button 4)"
        default: return "Nút chuột số \(n + 1) (Button \(n))"
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

enum GestureDirection: String, Codable, CaseIterable, Sendable {
    case up, down, left, right, tiltLeft, tiltRight
    var symbol: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .tiltLeft: return "Tilt ←"
        case .tiltRight: return "Tilt →"
        }
    }

    /// How the user physically performs this direction. The bare arrow is useless
    /// on its own: the user cannot tell whether the button is held, whether the
    /// motion is a drag or a scroll, or what "Tilt" even means on a normal mouse.
    var instruction: String {
        switch self {
        case .up: return "Giữ nút rồi kéo LÊN"
        case .down: return "Giữ nút rồi kéo XUỐNG"
        case .left: return "Giữ nút rồi kéo SANG TRÁI"
        case .right: return "Giữ nút rồi kéo SANG PHẢI"
        case .tiltLeft: return "Nghiêng con lăn sang TRÁI (không giữ nút)"
        case .tiltRight: return "Nghiêng con lăn sang PHẢI (không giữ nút)"
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
        let global: [GestureDirection: GestureAction] = [
            .up: key(126, ctrl), .down: key(125, ctrl), .left: key(123, ctrl), .right: key(124, ctrl),
            .tiltLeft: key(33, c), .tiltRight: key(30, c)]
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
        for (id,name) in [("co.elastic.obsidian","Obsidian"),("com.notion.Notion-App","Notion")] {
            result.append(.init(id:id,name:name,defaults:notes))
        }
        return result
    }()

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
