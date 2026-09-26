import AppKit

/// NativeVisibilityEngine handles menu bar item hiding on macOS 27+ using Apple's Assessment Mode Restriction API.
/// Does not inflate NSStatusItem.length. Instead, asks macOS to display only the allowed bundle identifiers
/// (apps to the right of the toggle arrow) and system items (0..<64). macOS then hides non-allowed items and reflows.
@MainActor
public final class NativeVisibilityEngine: MenuBarEngine {
    public static let systemItemsToKeep = Array(0...255)

    private weak var items: MenuBarItemProvider?
    private let inventory: MenuBarInventoryProviding
    private let visibility: NativeVisibilityProviding
    private let ownBundleIdentifier: String?
    private let itemFrame: (NSStatusItem) -> CGRect?
    private let isLTR: () -> Bool

    public private(set) var state: MenuBarEngineState = .expanded
    public private(set) var layout: MenuBarLayout?

    private var assertion: NativeVisibilityAssertion?
    private var generation = 0
    private var lastUnavailableReason: String?

    public init(
        items: MenuBarItemProvider,
        inventory: MenuBarInventoryProviding = AccessibilityMenuBarInventory(),
        visibility: NativeVisibilityProviding = NativeVisibilityBridge(),
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        itemFrame: @escaping (NSStatusItem) -> CGRect? = { $0.button?.window?.frame },
        isLTR: @escaping () -> Bool = { NSApplication.shared.userInterfaceLayoutDirection == .leftToRight }
    ) {
        self.items = items
        self.inventory = inventory
        self.visibility = visibility
        self.ownBundleIdentifier = ownBundleIdentifier
        self.itemFrame = itemFrame
        self.isLTR = isLTR
        items.separatorItem.isVisible = false
    }

    public func collapse(completion: @escaping @MainActor (CollapseResult) -> Void) {
        switch state {
        case .collapsed:
            return completion(.collapsed)
        case .calibrating:
            return
        case .expanded, .unavailable:
            break
        }

        guard visibility.isAvailable else {
            logUnavailableOnce("the native menu-bar visibility API is not available in this build or on this macOS")
            state = .unavailable
            return completion(.unavailable)
        }

        guard inventory.isAuthorized else {
            inventory.requestAuthorization()
            logUnavailableOnce("Accessibility permission is needed to read the menu-bar sections")
            return completion(.unavailable)
        }

        state = .calibrating
        withLayout { [weak self] layout in
            guard let self = self else { return }
            guard let layout = layout else {
                self.logUnavailableOnce("the arrow's position cannot be read yet")
                self.state = .expanded
                return completion(.unavailable)
            }

            let visibleBundles = layout.bundles(in: [.visible])
            NSLog("NativeVisibility: allowing %ld visible bundles: %@", visibleBundles.count, visibleBundles)
            self.activate(allowing: visibleBundles) { [weak self] succeeded in
                guard let self = self else { return }
                self.state = succeeded ? .collapsed : .expanded
                completion(succeeded ? .collapsed : .unavailable)
            }
        }
    }

    public func expand() {
        releaseAssertion()
        state = .expanded
        items?.separatorItem.isVisible = false
    }

    public func invalidateLayout() {
        if assertion == nil {
            layout = nil
        }
    }

    private func withLayout(_ body: @escaping @MainActor (MenuBarLayout?) -> Void) {
        if assertion != nil {
            return body(layout)
        }
        guard let arrow = items?.toggleItem else {
            return body(nil)
        }

        var boundary = itemFrame(arrow)
        if boundary == nil || boundary?.origin.x == 0 {
            boundary = AccessibilityMenuBarInventory.ownStatusItemFrame(matching: "Ẩn/hiện biểu tượng thanh menu")
        }
        guard let resolvedBoundary = boundary, resolvedBoundary.origin.x > 0 else {
            return body(nil)
        }

        let isLTR = self.isLTR()
        generation += 1
        let currentGen = self.generation

        inventory.snapshot { [weak self] inventoryItems in
            guard let self = self, currentGen == self.generation else { return }
            let layout = MenuBarLayoutResolver.resolve(
                inventory: inventoryItems,
                separatorFrame: resolvedBoundary,
                isLTR: isLTR,
                excludingBundle: self.ownBundleIdentifier
            )
            NSLog("NativeVisibility: arrow at x=%.1f; visible %@, hidden %@",
                  resolvedBoundary.midX,
                  layout.bundles(in: [.visible]),
                  layout.bundles(in: [.hidden]))
            self.layout = layout
            body(layout)
        }
    }

    private func activate(allowing bundles: [String], completion: @escaping @MainActor (Bool) -> Void) {
        generation += 1
        let currentGen = self.generation
        let allowed = (ownBundleIdentifier.map { [$0] } ?? []) + bundles

        visibility.activate(
            allowedSystemItems: Self.systemItemsToKeep,
            allowedBundleIdentifiers: allowed
        ) { [weak self] result in
            guard let self = self, currentGen == self.generation else {
                if case .success(let stale) = result { stale.invalidate() }
                return
            }
            switch result {
            case .success(let newAssertion):
                let old = self.assertion
                self.assertion = newAssertion
                old?.invalidate()
                NSLog("NativeVisibility: activation SUCCEEDED with %ld allowed bundles: %@", allowed.count, allowed)
                completion(true)
            case .failure(let error):
                NSLog("NativeVisibility: activation failed: %@", error.localizedDescription)
                self.releaseAssertion()
                completion(false)
            }
        }
    }

    private func releaseAssertion() {
        generation += 1
        assertion?.invalidate()
        assertion = nil
    }

    private func logUnavailableOnce(_ reason: String) {
        guard reason != lastUnavailableReason else { return }
        lastUnavailableReason = reason
        NSLog("NativeVisibility: hiding unavailable: %@", reason)
    }
}
