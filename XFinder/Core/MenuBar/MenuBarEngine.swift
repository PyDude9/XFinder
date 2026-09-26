import AppKit

public enum MenuBarEngineState: Equatable, Sendable {
    case expanded
    case calibrating
    case collapsed
    case unavailable
}

public enum CollapseResult: Equatable, Sendable {
    case collapsed
    case unavailable
}

@MainActor
public protocol MenuBarItemProvider: AnyObject {
    var toggleItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
}

@MainActor
public protocol MenuBarEngine: AnyObject {
    var state: MenuBarEngineState { get }
    func collapse(completion: @escaping @MainActor (CollapseResult) -> Void)
    func expand()
    func invalidateLayout()
}

public enum MenuBarSection: Int, Comparable, Sendable {
    case visible
    case hidden
    case alwaysHidden

    public static func < (lhs: MenuBarSection, rhs: MenuBarSection) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public struct MenuBarInventoryItem: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let frame: CGRect

    public init(bundleIdentifier: String?, frame: CGRect) {
        self.bundleIdentifier = bundleIdentifier
        self.frame = frame
    }
}

public struct MenuBarLayout: Equatable, Sendable {
    public var sections: [String: MenuBarSection]

    public init(sections: [String: MenuBarSection]) {
        self.sections = sections
    }

    public func bundles(in wanted: Set<MenuBarSection>) -> [String] {
        return sections.filter { wanted.contains($0.value) }.map(\.key).sorted()
    }
}

public enum MenuBarLayoutResolver {
    public static let systemItemOwners: Set<String> = [
        "com.apple.MenuBarAgent",
        "com.apple.controlcenter",
        "com.apple.systemuiserver"
    ]

    public static func resolve(
        inventory: [MenuBarInventoryItem],
        separatorFrame: CGRect,
        isLTR: Bool = true,
        excludingBundle ownBundle: String? = Bundle.main.bundleIdentifier
    ) -> MenuBarLayout {
        var sections: [String: MenuBarSection] = [:]
        for item in inventory {
            guard let bundle = item.bundleIdentifier,
                  bundle != ownBundle,
                  !systemItemOwners.contains(bundle) else { continue }
            let section = self.section(of: item.frame, separatorFrame: separatorFrame, isLTR: isLTR)
            // One app can own several items; the most visible item wins
            sections[bundle] = min(sections[bundle] ?? section, section)
        }
        return MenuBarLayout(sections: sections)
    }

    public static func section(
        of frame: CGRect,
        separatorFrame: CGRect,
        isLTR: Bool
    ) -> MenuBarSection {
        // Distance toward the arrow side: positive means on the visible side (right of arrow in LTR)
        let distance: CGFloat = isLTR ? frame.midX - separatorFrame.midX : separatorFrame.midX - frame.midX
        if distance > 0 {
            return .visible
        } else {
            return .hidden
        }
    }
}
