import AppKit
import Combine

/// Biểu tượng thanh menu — Bartender-style hiding, built only on public API.
///
/// **How it actually works.** No public (or even private) API lets one app
/// hide another app's status item. What *is* possible: XFinder owns two status
/// items of its own — a chevron and an expandable **separator**. The user
/// ⌘-drags the icons they want hidden to the **left** of the separator; the
/// separator then expands to a width wider than the screen, pushing everything
/// left of it off the visible menu bar. Clicking the chevron collapses the
/// separator again, revealing them.
///
/// That is the same mechanism the shipping "hidden bar" apps use, and it needs
/// **no permission at all** — the ⌘-drag is performed by the user, by hand.
/// Accessibility is only needed to *open* a hidden icon's menu programmatically,
/// which this does not do.
@MainActor
@Observable
final class MenuBarHiderController: NSResponder {
    static let shared = MenuBarHiderController()

    private(set) var isHiding = false
    private(set) var isInstalled = false

    private var chevronItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var autoHideTimer: Timer?

    /// Wider than any plausible menu bar, so everything to its left is pushed
    /// off-screen when expanded.
    private let expandedWidth: CGFloat = 10_000
    private let collapsedWidth: CGFloat = 12

    private override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Settings (read at point of use)

    /// On by default: the point of the feature is that the bar is tidy the
    /// moment XFinder launches, without the user opting in first.
    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "menubar.hiderEnabled") as? Bool ?? true
    }
    private var autoHide: Bool {
        UserDefaults.standard.object(forKey: "menubar.autoHide") as? Bool ?? true
    }
    private var autoHideDelay: TimeInterval {
        UserDefaults.standard.object(forKey: "menubar.autoHideDelay") as? Double ?? 5
    }

    func applySettings() {
        if enabled { install() } else { uninstall() }
    }

    // MARK: Install / uninstall

    private func install() {
        guard !isInstalled else { return }
        let bar = NSStatusBar.system

        // Order matters. macOS lays status items out right-to-left in creation
        // order, so the CHEVRON must be created first to sit to the RIGHT of
        // the separator — otherwise it is swallowed by its own expansion and
        // there is no way to reveal the hidden group again.
        let chevron = bar.statusItem(withLength: NSStatusItem.variableLength)
        chevron.button?.image = NSImage(systemSymbolName: "chevron.left",
                                        accessibilityDescription: "Hiện/ẩn biểu tượng")
        chevron.button?.target = self
        chevron.button?.action = #selector(chevronClicked)
        // `autosaveName` pins the position across launches, so the user's
        // ⌘-drag arrangement survives a restart.
        chevron.autosaveName = "XFinderMenuBarChevron"
        chevron.behavior = []          // never let macOS auto-hide our own arrow
        installHoverTracking(on: chevron)
        chevronItem = chevron

        let separator = bar.statusItem(withLength: collapsedWidth)
        separator.button?.title = ""
        // A thin vertical rule marks the boundary the user drags across.
        separator.button?.image = Self.separatorImage()
        separator.button?.imagePosition = .imageOnly
        separator.button?.target = self
        separator.button?.action = #selector(chevronClicked)
        separator.autosaveName = "XFinderMenuBarSeparator"
        separator.behavior = []
        separatorItem = separator

        isInstalled = true
        // Start hidden so the bar is tidy the moment the feature is enabled.
        setHiding(true)
        showFirstRunGuidanceIfNeeded()
    }

    @objc private func chevronClicked() {
        toggleHiding()
    }

    /// A tracking area on the chevron so merely pointing at it reveals the
    /// hidden group — no click needed.
    private func installHoverTracking(on item: NSStatusItem) {
        guard let button = item.button else { return }
        let area = NSTrackingArea(rect: button.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        button.addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        if isHiding { setHiding(false) }
    }

    /// macOS cannot move another app's status item — only the user can, with a
    /// ⌘-drag. Explain that once instead of silently doing nothing.
    private func showFirstRunGuidanceIfNeeded() {
        let key = "menubar.guidanceShown"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Chọn biểu tượng muốn ẩn"
        alert.informativeText = """
        XFinder vừa thêm một mũi tên ‹ và một vạch ngăn vào thanh menu.

        Giữ phím ⌘ rồi kéo những biểu tượng bạn muốn giấu sang BÊN TRÁI vạch ngăn. Giữ các biểu tượng luôn muốn thấy ở bên phải.

        macOS không cho phép ứng dụng tự di chuyển biểu tượng của ứng dụng khác, nên thao tác kéo này phải do bạn thực hiện — chỉ cần làm một lần.
        """
        alert.addButton(withTitle: "Đã hiểu")
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func uninstall() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        if let c = chevronItem { NSStatusBar.system.removeStatusItem(c) }
        if let s = separatorItem { NSStatusBar.system.removeStatusItem(s) }
        chevronItem = nil
        separatorItem = nil
        isInstalled = false
        isHiding = false
    }

    // MARK: Hiding

    @objc private func toggleHiding() {
        setHiding(!isHiding)
    }

    func setHiding(_ hide: Bool) {
        guard isInstalled else { return }
        isHiding = hide
        separatorItem?.length = hide ? expandedWidth : collapsedWidth
        chevronItem?.button?.image = NSImage(
            systemSymbolName: hide ? "chevron.left" : "chevron.right",
            accessibilityDescription: "Hiện/ẩn biểu tượng")

        autoHideTimer?.invalidate()
        autoHideTimer = nil
        // Re-hide after the delay so the bar tidies itself without a click.
        if !hide, autoHide {
            let t = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.setHiding(true) }
            }
            RunLoop.main.add(t, forMode: .common)
            autoHideTimer = t
        }
    }

    /// Momentarily reveals the hidden group (used by the settings page button).
    func revealNow() {
        setHiding(false)
    }

    /// Collapses the separator and re-expands it, which makes macOS re-lay-out
    /// XFinder's own two items. It never reorders other apps' icons.
    func resetLayout() {
        guard isInstalled else { return }
        separatorItem?.length = collapsedWidth
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in self?.setHiding(true) }
        }
    }

    private static func separatorImage() -> NSImage {
        let size = NSSize(width: 6, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.secondaryLabelColor.withAlphaComponent(0.55).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: rect.minY + 2))
            path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 2))
            path.lineWidth = 1
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
