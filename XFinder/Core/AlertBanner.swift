import AppKit
import SwiftUI

/// XFinder's own alert banner: a non-activating, mouse-transparent panel at the top of the screen
/// the pointer is on, shown for 8 s. Needs no permission — the reason it exists (see `AlertMonitor`).
@MainActor
final class AlertBanner {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(symbol: String, title: String, body: String) {
        hideWork?.cancel()
        panel?.orderOut(nil)
        let size = NSSize(width: 380, height: 68)
        let host = NSHostingController(rootView: AlertBannerView(symbol: symbol, title: title, message: body))
        host.view.frame = NSRect(origin: .zero, size: size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentViewController = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        if let frame = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        p.orderFrontRegardless()
        panel = p
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.panel?.orderOut(nil); self?.panel = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }
}

struct AlertBannerView: View {
    let symbol: String, title: String, message: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundColor(.orange).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(width: 380, height: 68)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
