import AppKit
import Observation

/// Biểu tượng thanh menu — nút mũi tên ẩn biểu tượng, theo đúng cơ chế public
/// API của dwarvesf/hidden (Hidden Bar):
///
/// XFinder tạo 2 `NSStatusItem` của chính mình:
///   * **nút mũi tên** (chevron) — bấm để ẩn/hiện.
///   * **vạch ngăn** (separator) — `length = 1` khi hiện, phình lên
///     `max(500, min(screenWidth + 200, 4000))` khi thu gọn để đẩy các icon
///     nằm bên TRÁI ra ngoài. `NSStatusItem.autosaveName` để macOS nhớ vị trí
///     người dùng ⌘-kéo nó tới.
///
/// ⚠️ macOS 26/27 — đã đo (xem CLAUDE.md "macOS 27 — Biểu tượng thanh menu"):
///     `length` bị clamp ~5016pt và layout KHÔNG còn đẩy item hàng xóm đi,
///     nên trick này có thể không ẩn được icon của app khác trên macOS mới.
///     Giữ lại như cách làm tham chiếu (đúng public API, không private XPC);
///     UI ghi rõ giới hạn này thay vì giấu.
@MainActor
@Observable
final class MenuBarHiderController: NSResponder {
    static let shared = MenuBarHiderController()

    private(set) var isHiding = false

    private var separator: NSStatusItem?
    private var arrow: NSStatusItem?
    private var covers: [NSWindow] = []

    private override init() { super.init() }
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Settings (read at point of use)

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "menubar.hiderEnabled") as? Bool ?? false
    }

    /// TẠM TẮT (chờ giải pháp ẩn RIÊNG icon app, không che cả thanh menu bên
    /// phải). Luôn gỡ items; giữ lại code để bật lại khi có cách đúng.
    func applySettings() {
        remove()
    }

    // MARK: - Install / remove

    private func install() {
        guard separator == nil else { return }
        let bar = NSStatusBar.system

        let arrow = bar.statusItem(withLength: NSStatusItem.squareLength)
        if let b = arrow.button {
            b.image = NSImage(systemSymbolName: isHiding ? "chevron.right" : "chevron.left",
                              accessibilityDescription: "Ẩn/hiện biểu tượng thanh menu")
            b.target = self
            b.action = #selector(toggle)
        }
        arrow.autosaveName = "xfinder.menubar.arrow"
        self.arrow = arrow

        let sep = bar.statusItem(withLength: isHiding ? collapseLength() : 1)
        sep.autosaveName = "xfinder.menubar.separator"
        separator = sep
    }

    private func remove() {
        hideCovers()
        if let separator { NSStatusBar.system.removeStatusItem(separator) }
        if let arrow { NSStatusBar.system.removeStatusItem(arrow) }
        separator = nil
        arrow = nil
        isHiding = false
    }

    /// Hidden Bar giới hạn độ dài phình trong khoảng 500…4000pt (sàn + màn + 200).
    private func collapseLength() -> CGFloat {
        let width = NSScreen.main?.frame.width ?? 1440
        return min(max(500, width + 200), 4000)
    }

    @objc func toggle() {
        guard let separator else { return }
        isHiding.toggle()
        separator.length = isHiding ? collapseLength() : 1
        if isHiding { showCovers() } else { hideCovers() }
        arrow?.button?.image = NSImage(systemSymbolName: isHiding ? "chevron.right" : "chevron.left",
                                       accessibilityDescription: nil)
    }

    /// Cover: trên macOS 27 separator không còn đẩy icon hàng xóm ra ngoài, nên
    /// XFinder che VÙNG ẨN bằng panel vibrancy `.menu` ngang thanh menu. Che
    /// phần BÊN PHẢI mũi tên — nơi status icon nằm — để menu app + Apple menu
    /// bên trái không bị che (chỉ ẩn icon, không ẩn thanh menu).
    private func showCovers() {
        hideCovers()
        guard let arrow,
              let arrowWin = arrow.button?.window,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(arrowWin.frame.origin) })
              ?? NSScreen.main
        else { return }
        let bar = screen.frame.maxY - screen.visibleFrame.maxY
        guard bar > 2 else { return }
        let arrowMaxX = arrowWin.frame.maxX
        let rect = NSRect(x: arrowMaxX,
                          y: screen.frame.maxY - bar,
                          width: max(0, screen.frame.maxX - arrowMaxX),
                          height: bar + 1)

        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .statusBar
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let eff = NSVisualEffectView()
        eff.material = .menu
        eff.blendingMode = .behindWindow
        eff.state = .active
        w.contentView = eff
        w.orderFrontRegardless()
        covers = [w]
    }

    private func hideCovers() {
        covers.forEach { $0.orderOut(nil) }
        covers.removeAll()
    }

    // MARK: - macOS native path

    /// Opens System Settings → Control Centre → Menu Bar, where macOS 26/27
    /// governs *system* menu-bar icons. Falls back to the Dock pane, then to
    /// System Settings itself, so the button is never dead.
    func openSystemMenuBarSettings() {
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
