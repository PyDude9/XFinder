import Foundation

/// Which tabs the menubar popover shows. Pure, so the rules that stop it from ending up empty
/// are pinned by tests: a popover with no tabs has nothing to click and no way back.
///
/// The job: *"I do not always want to see everything in the popover."*
///
/// One key, `menubar.hiddenTabs`, holds the HIDDEN ids (comma-separated). Hidden rather than
/// visible, so a tab added in a later version shows up by default instead of being invisible
/// to everyone who ever customised the popover.
enum FlyoutLayout {

    static let key = "menubar.hiddenTabs"

    static func encode(_ hidden: Set<String>) -> String { hidden.sorted().joined(separator: ",") }

    static func decode(_ s: String) -> Set<String> {
        Set(s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// The hidden set. `stored` is the new key; the two legacy keys (`menubar.showBattery`,
    /// `menubar.showNetwork`) are honoured ONLY until the user customises, so someone who had
    /// turned a tab off by hand does not see it come back. Once `stored` exists it wins outright.
    static func hidden(stored: String?, legacyShowBattery: Bool?, legacyShowNetwork: Bool?) -> Set<String> {
        if let stored { return decode(stored) }
        var out = Set<String>()
        if legacyShowBattery == false { out.insert("battery") }
        if legacyShowNetwork == false { out.insert("network") }
        return out
    }

    /// The tabs to show, in their natural order. Never empty: if every tab were hidden (a
    /// hand-edited default, a stale key), all of them are shown rather than an empty popover.
    static func visible(all: [String], hidden: Set<String>) -> [String] {
        let v = all.filter { !hidden.contains($0) }
        return v.isEmpty ? all : v
    }

    /// Hiding is refused for the last visible tab.
    static func canHide(_ id: String, all: [String], hidden: Set<String>) -> Bool {
        guard all.contains(id), !hidden.contains(id) else { return true }
        return visible(all: all, hidden: hidden).filter { $0 != id }.count >= 1
            && all.filter { !hidden.contains($0) && $0 != id }.count >= 1
    }

    /// The hidden set after flipping `id`. A refused hide returns the set unchanged.
    static func toggled(_ id: String, all: [String], hidden: Set<String>) -> Set<String> {
        if hidden.contains(id) { var h = hidden; h.remove(id); return h }
        guard canHide(id, all: all, hidden: hidden) else { return hidden }
        var h = hidden; h.insert(id); return h
    }

    /// The selected tab if it is still visible, otherwise the first visible one — so hiding the tab
    /// you are on moves you somewhere instead of leaving a blank page.
    static func selection(current: String, visible: [String]) -> String {
        visible.contains(current) ? current : (visible.first ?? current)
    }
}
