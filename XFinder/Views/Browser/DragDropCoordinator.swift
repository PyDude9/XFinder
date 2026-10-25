import AppKit

/// XF-T30 W2 — drag-and-drop rules shared by the four views and the sidebar: default verb by volume, ⌥ copy / ⌘ move,
/// file promises, stacked drag image with a count, Finder-style drop highlight, spring-loaded folders on the system's
/// timing, Escape / leaving the window reverts. W2 builder (menu).
@MainActor
enum DragDropCoordinator {
    enum Verb: Equatable { case copy, move, none }

    /// The operation a drop of `sources` onto `folder` performs with `modifiers` held — same rule
    /// `BrowserWindowModel.drop(_:into:copy:)` itself applies when the drop actually lands, kept here too so every
    /// view can preview the verb (cursor badge, drop highlight) before the user releases the mouse. Same volume ⇒
    /// move; cross-volume ⇒ copy; ⌥ forces copy; ⌘ forces move (Finder's own convention: Option always copies,
    /// Command always moves, regardless of volume) — a destination-side safety check (nesting, permissions) can
    /// still block the actual drop later even when this reports a verb.
    static func verb(sources: [String], folder: String, modifiers: NSEvent.ModifierFlags) -> Verb {
        guard !sources.isEmpty, !folder.isEmpty else { return .none }
        if modifiers.contains(.option) { return .copy }
        if modifiers.contains(.command) { return .move }
        guard let folderVolume = DirectoryReader.volumeID(of: folder) else { return .none }
        let sameVolume = sources.allSatisfy { DirectoryReader.volumeID(of: $0) == folderVolume }
        return sameVolume ? .move : .copy
    }

    /// Spring-loading's enabled state and delay: System Settings ▸ Accessibility ▸ Pointer Control ▸ Spring-loading,
    /// never a separate app preference (contract: "timing/enablement from the system Accessibility pointer-control
    /// spring-loading setting, not a separate app preference"). Probed 2026-10-25 on this machine (never touched by
    /// the user — `defaults read com.apple.springing` errors "domain not found" in every user/host scope): with a
    /// positive control proving `CFPreferencesCopyAppValue` itself works (`AppleLanguages` in `NSGlobalDomain` reads
    /// back correctly in the same run), `com.apple.springing`'s `enabled`/`delay` keys both read back `nil` — i.e.
    /// genuinely absent, not a read failure — so the documented system default (spring-loading ON, 0.5 s) is what
    /// `nil` means here, exactly as this falls back to below.
    static var springLoading: (enabled: Bool, delay: TimeInterval) {
        let domain = "com.apple.springing" as CFString
        let enabled = CFPreferencesCopyAppValue("enabled" as CFString, domain) as? Bool ?? true
        let delay = CFPreferencesCopyAppValue("delay" as CFString, domain) as? Double ?? 0.5
        return (enabled, delay)
    }

    // MARK: - Drag image (stacked icons + count)

    /// A Finder-style stacked drag image for multiple items: the lead item's icon with the rest fanned slightly
    /// behind it, plus a count badge when more than one item is dragged. A single item just returns its own icon
    /// (no badge, no stacking) — the common case stays cheap and visually identical to dragging one Finder row.
    static func dragImage(for paths: [String]) -> NSImage {
        guard let first = paths.first else { return NSWorkspace.shared.icon(forFile: "/") }
        let iconSize = NSSize(width: 64, height: 64)
        guard paths.count > 1 else {
            return NSWorkspace.shared.icon(forFile: first).resized(to: iconSize)
        }
        let canvas = NSImage(size: iconSize)
        canvas.lockFocus()
        // Up to two faint icons behind the lead one, offset like a fanned stack of cards.
        let behind = paths.dropFirst().prefix(2)
        for (index, path) in behind.enumerated() {
            let offset = CGFloat(index + 1) * 4
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.draw(in: NSRect(x: offset, y: -offset, width: iconSize.width - 8, height: iconSize.height - 8),
                      from: .zero, operation: .sourceOver, fraction: 0.6)
        }
        let lead = NSWorkspace.shared.icon(forFile: first)
        lead.draw(in: NSRect(origin: .zero, size: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
        canvas.unlockFocus()
        return drawCountBadge(paths.count, on: canvas)
    }

    private static func drawCountBadge(_ count: Int, on image: NSImage) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        let text = "\(count)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let badgeDiameter = max(textSize.width, textSize.height) + 8
        let badgeRect = NSRect(x: image.size.width - badgeDiameter, y: 0, width: badgeDiameter, height: badgeDiameter)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        let textOrigin = NSPoint(x: badgeRect.midX - textSize.width / 2, y: badgeRect.midY - textSize.height / 2)
        text.draw(at: textOrigin, withAttributes: attributes)
        result.unlockFocus()
        return result
    }

    // MARK: - Drop-target highlight

    /// Finder-equivalent drop highlight for a folder row/icon or a pane background — a translucent accent fill plus
    /// a slightly stronger accent border, matching `XFinderTokens.Colors.focus`'s own accent-opacity convention
    /// (no new literal colour introduced here, CLAUDE.md §2's token rule).
    static func drawDropHighlight(in rect: NSRect, cornerRadius: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.65).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    // MARK: - Spring-loaded folders

    /// One spring-loaded hover timer, shared by whichever view currently owns a drag (only one drag is ever in
    /// flight at a time in this process). `begin` is idempotent for the same `path` (re-hovering the same row while
    /// already timing does not restart the clock); hovering a DIFFERENT path, or `cancel()` (Escape / the drag left
    /// the window, contract: "Escape or dragging outside the window must cancel the spring-open"), stops it first.
    @MainActor
    final class SpringLoader {
        private var timer: Timer?
        private var pendingPath: String?

        /// Starts (or continues) timing a hover over `path`; `open` fires once the system's spring-loading delay
        /// elapses, provided the system setting is still enabled at that moment. Does nothing if spring-loading is
        /// off system-wide (contract: "fully off when system setting is off" — no separate in-app toggle).
        func begin(hovering path: String, open: @escaping () -> Void) {
            guard DragDropCoordinator.springLoading.enabled else { return }
            guard pendingPath != path else { return }
            cancel()
            pendingPath = path
            let delay = DragDropCoordinator.springLoading.delay
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self, self.pendingPath == path else { return }
                self.pendingPath = nil
                self.timer = nil
                open()
            }
        }

        /// Stops any pending spring-open without firing it.
        func cancel() {
            timer?.invalidate()
            timer = nil
            pendingPath = nil
        }
    }
}

private extension NSImage {
    func resized(to size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
