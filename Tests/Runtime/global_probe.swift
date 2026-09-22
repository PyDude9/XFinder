// Scratch probe: resolve Global's rows exactly the way the page does, using the
// REAL production GestureModel (not a copy), to find out whether Global is empty.
import Foundation

// Compiled together with the symlinked production GestureModel.swift.

let cfg = GestureConfiguration()
print("== GestureProfiles.all.count =", GestureProfiles.all.count)
print("== fallback id =", GestureProfiles.fallback)
print("== all[0].id =", GestureProfiles.all[0].id, "name =", GestureProfiles.all[0].name)
print("== all[0].defaults.count =", GestureProfiles.all[0].defaults.count)
print()
print("== Global rows exactly as the page renders them ==")
for dir in GestureDirection.allCases {
    let action = cfg.action(bundle: GestureProfiles.fallback, direction: dir)
    let source = cfg.source(bundle: GestureProfiles.fallback, direction: dir)
    var display: String
    switch action {
    case .unassigned: display = "UNASSIGNED"
    case .horizontalScroll: display = "hscroll"
    case .shortcut(let s): display = s.label
    }
    print("  \(dir.symbol.padding(toLength: 10, withPad: " ", startingAt: 0)) -> \(display.padding(toLength: 12, withPad: " ", startingAt: 0)) [\(source)]")
}
print()
print("== picker entries (what the user sees in the dropdown) ==")
for p in GestureProfiles.all {
    print("  \(p.id) : \(p.name) (\(p.defaults.count) defaults)")
}
