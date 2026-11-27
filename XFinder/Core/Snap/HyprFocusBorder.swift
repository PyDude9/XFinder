import AppKit

/// Highlight border around the currently focused window in HyprMac Tiling mode.
/// Mouse-transparent (`ignoresMouseEvents = true`), non-activating, zero timers.
@MainActor
final class HyprFocusBorder {
    private var panel: NSPanel?
    private let ringView = FocusRingView()
    private static let glowRoom: CGFloat = 10

    func show(aroundAXRect axRect: CGRect, borderWidth: CGFloat) {
        guard axRect.width > 10, axRect.height > 10 else {
            hide()
            return
        }
        let width = min(max(borderWidth, 1), 8)
        let appKit = WindowManager.axRectToAppKit(axRect)
        let expanded = appKit.insetBy(dx: -(width / 2 + Self.glowRoom), dy: -(width / 2 + Self.glowRoom))

        let p: NSPanel
        if let existing = panel {
            p = existing
        } else {
            let created = NSPanel(
                contentRect: expanded,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            created.level = .floating
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.ignoresMouseEvents = true
            created.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            ringView.wantsLayer = true
            created.contentView = ringView
            panel = created
            p = created
        }

        ringView.borderWidth = width
        ringView.glowRoom = Self.glowRoom
        ringView.needsLayout = true
        p.setFrame(expanded, display: true)
        ringView.layoutSubtreeIfNeeded()
        if !p.isVisible {
            p.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private final class FocusRingView: NSView {
    var borderWidth: CGFloat = 3
    var glowRoom: CGFloat = 10
    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        borderLayer.fillColor = nil
        borderLayer.shadowOffset = .zero
        borderLayer.shadowRadius = 7
        borderLayer.shadowOpacity = 0.50
        layer?.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let ringRect = bounds.insetBy(dx: glowRoom + borderWidth / 2, dy: glowRoom + borderWidth / 2)
        guard ringRect.width > 2, ringRect.height > 2 else { return }
        let corner = min(11, ringRect.width / 2, ringRect.height / 2)
        let path = CGPath(roundedRect: ringRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        let accent = NSColor.controlAccentColor.cgColor
        borderLayer.frame = bounds
        borderLayer.path = path
        borderLayer.lineWidth = borderWidth
        borderLayer.strokeColor = accent
        borderLayer.shadowColor = accent
    }
}
