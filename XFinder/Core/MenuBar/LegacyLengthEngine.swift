import AppKit

/// Hides icons by inflating the separator until items to its left leave the visible bar.
/// Used on macOS <= 26.
@MainActor
public final class LegacyLengthEngine: MenuBarEngine {
    private weak var items: MenuBarItemProvider?
    private let expandedLength: CGFloat = 20

    public init(items: MenuBarItemProvider) {
        self.items = items
    }

    public var state: MenuBarEngineState {
        guard let separator = items?.separatorItem else { return .expanded }
        return separator.length > expandedLength ? .collapsed : .expanded
    }

    private var collapsedLength: CGFloat {
        let screenWidth = NSScreen.screens.map { $0.frame.width }.max() ?? 1728
        return max(500, min(screenWidth * 2, 10_000))
    }

    public func collapse(completion: @escaping @MainActor (CollapseResult) -> Void) {
        items?.separatorItem.length = collapsedLength
        completion(.collapsed)
    }

    public func expand() {
        items?.separatorItem.length = expandedLength
    }

    public func invalidateLayout() {
        guard state == .collapsed else { return }
        items?.separatorItem.length = collapsedLength
    }
}
