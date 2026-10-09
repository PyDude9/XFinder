import AppKit
import Observation

/// MenuBarHiderController coordinates menu bar hiding for XFinder.
/// Implements MenuBarItemProvider and delegates hiding mechanics to MenuBarEngine.
@MainActor
@Observable
public final class MenuBarHiderController: NSResponder, MenuBarItemProvider {
    public static let shared = MenuBarHiderController()

    public private(set) var isHiding = false

    private var separator: NSStatusItem?
    private var arrow: NSStatusItem?
    public private(set) var currentEngine: MenuBarEngine?

    public var autoHideTimer: Timer?

    public var toggleItem: NSStatusItem {
        if let arrow = arrow { return arrow }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.arrow = item
        return item
    }

    public var separatorItem: NSStatusItem {
        if let separator = separator { return separator }
        let item = NSStatusBar.system.statusItem(withLength: 1)
        self.separator = item
        return item
    }

    private nonisolated(unsafe) var defaultsObserver: (any NSObjectProtocol)?

    private override init() {
        super.init()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleUserDefaultsChange()
            }
        }
    }

    deinit {
        if let obs = defaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    required init?(coder: NSCoder) {
        assertionFailure("init(coder:) is not supported")
        return nil
    }

    private func handleUserDefaultsChange() {
        if !autoHideEnabled {
            autoHideTimer?.invalidate()
            autoHideTimer = nil
        }
        if hiderEnabled != (arrow != nil) {
            applySettings()
        }
    }

    public var hiderEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "menubar.hiderEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "menubar.hiderEnabled")
            applySettings()
        }
    }

    public var isEnabled: Bool {
        get { hiderEnabled }
        set { hiderEnabled = newValue }
    }

    public var autoHideEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "menubar.autoHideEnabled") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "menubar.autoHideEnabled")
            if newValue {
                if !isHiding {
                    scheduleAutoHide()
                }
            } else {
                autoHideTimer?.invalidate()
                autoHideTimer = nil
            }
        }
    }

    public var isAutoHideEnabled: Bool {
        get { autoHideEnabled }
        set { autoHideEnabled = newValue }
    }

    public var autoHideSeconds: Double {
        get { UserDefaults.standard.object(forKey: "menubar.autoHideSeconds") as? Double ?? 5.0 }
        set {
            UserDefaults.standard.set(newValue, forKey: "menubar.autoHideSeconds")
            if autoHideEnabled && !isHiding {
                scheduleAutoHide()
            }
        }
    }

    public var defaultCollapsed: Bool {
        get { UserDefaults.standard.object(forKey: "menubar.defaultCollapsed") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "menubar.defaultCollapsed")
        }
    }

    public func applySettings() {
        if hiderEnabled {
            install()
        } else {
            remove()
        }
    }

    private func install() {
        guard arrow == nil else { return }
        let bar = NSStatusBar.system

        let arrowItem = bar.statusItem(withLength: NSStatusItem.variableLength)
        if let b = arrowItem.button {
            b.image = NSImage(systemSymbolName: isHiding ? "chevron.right" : "chevron.left",
                              accessibilityDescription: L10n.t("Ẩn/hiện biểu tượng thanh menu"))
            b.target = self
            b.action = #selector(toggle)
        }
        arrowItem.autosaveName = "xfinder.menubar.arrow"
        self.arrow = arrowItem

        let sepItem = bar.statusItem(withLength: 1)
        sepItem.autosaveName = "xfinder.menubar.separator"
        self.separator = sepItem

        let engine = MenuBarEngineFactory.make(items: self)
        self.currentEngine = engine
        NSLog("MenuBarHiderController: initialized with engine %@", String(describing: type(of: engine)))

        if defaultCollapsed && hiderEnabled {
            attemptInitialCollapse(retriesLeft: 4)
        } else if autoHideEnabled && hiderEnabled {
            scheduleAutoHide()
        }
    }

    private func attemptInitialCollapse(retriesLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, self.defaultCollapsed, self.hiderEnabled else { return }
            self.collapse { [weak self] result in
                guard let self = self else { return }
                if result != .collapsed && retriesLeft > 0 {
                    self.attemptInitialCollapse(retriesLeft: retriesLeft - 1)
                }
            }
        }
    }

    private func remove() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        if let engine = currentEngine, engine.state == .collapsed {
            engine.expand()
        }
        currentEngine = nil

        if let separator { NSStatusBar.system.removeStatusItem(separator) }
        if let arrow { NSStatusBar.system.removeStatusItem(arrow) }
        separator = nil
        arrow = nil
        isHiding = false
    }

    public func expand() {
        guard let engine = currentEngine else { return }
        engine.expand()
        isHiding = false
        updateArrowImage()
        if autoHideEnabled {
            scheduleAutoHide()
        }
    }

    public func collapse(completion: ((CollapseResult) -> Void)? = nil) {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard let engine = currentEngine else {
            completion?(.unavailable)
            return
        }
        engine.collapse { [weak self] result in
            guard let self = self else { return }
            self.isHiding = (result == .collapsed)
            self.updateArrowImage()
            completion?(result)
        }
    }

    @objc public func toggle() {
        guard let engine = currentEngine else { return }
        if engine.state == .collapsed || isHiding {
            expand()
        } else {
            collapse()
        }
    }

    public func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        guard autoHideEnabled && autoHideSeconds > 0 else { return }
        let timer = Timer(timeInterval: autoHideSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isMouseInMenuBar() {
                    self.scheduleAutoHide()
                } else {
                    self.collapse()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.autoHideTimer = timer
    }

    public func isMouseInMenuBar() -> Bool {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.contains { p.y >= $0.visibleFrame.maxY && p.y <= $0.frame.maxY }
    }

    private func updateArrowImage() {
        arrow?.button?.image = NSImage(
            systemSymbolName: isHiding ? "chevron.right" : "chevron.left",
            accessibilityDescription: L10n.t("Ẩn/hiện biểu tượng thanh menu")
        )
    }

    public func openSystemMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
