import AppKit
import SwiftUI

/// DockDoor-style replacement Dock layer at bottom center.
///
/// Rendered using unified LiquidGlassTokens. When enabled, sets Apple Dock
/// to autohide without patching Dock binaries.
@MainActor
public final class DockLayerController: ObservableObject {
    public static let shared = DockLayerController()

    public struct AppEntry: Identifiable, Equatable {
        public let id: pid_t
        public let name: String
        public let bundleID: String
        public let icon: NSImage?
    }

    private var panel: NSPanel?
    private var hoverPanel: NSPanel?
    @Published public private(set) var runningApps: [AppEntry] = []
    @Published public var hoveredPID: pid_t?

    private init() {}

    public var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "windowPreview.customDockEnabled") as? Bool ?? false
    }

    public func applySettings() {
        if isEnabled {
            // Set Apple Dock auto-hide to true
            DockPrefs.setAutohide(true)
            showDock()
        } else {
            hideDock()
        }
    }

    public func reloadApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !($0.localizedName ?? "").isEmpty }
            .map { app in
                AppEntry(
                    id: app.processIdentifier,
                    name: app.localizedName ?? "",
                    bundleID: app.bundleIdentifier ?? "",
                    icon: app.icon
                )
            }
        self.runningApps = apps
    }

    public func showDock() {
        reloadApps()
        guard !runningApps.isEmpty else { return }

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 68),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)))
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = false
            self.panel = p
        }

        let content = DockLayerContentView(controller: self)
        let host = NSHostingView(rootView: content)
        panel?.contentView = host

        if let screen = NSScreen.main, let p = panel {
            let size = host.fittingSize
            let w = max(size.width, 320)
            let h = max(size.height, 68)
            let x = screen.frame.midX - w / 2
            let y = screen.frame.minY + 12
            p.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            p.orderFrontRegardless()
        }
    }

    public func hideDock() {
        panel?.orderOut(nil)
        panel = nil
        hideHoverPanel()
    }

    public func showHoverPreviews(for pid: pid_t, sourceFrame: CGRect) {
        hoveredPID = pid
        WindowPreviewStore.shared.loadDockPreviews(for: pid)

        let appName = runningApps.first(where: { $0.id == pid })?.name ?? ""
        let content = DockPreviewView(pid: pid, title: appName) { [weak self] in
            self?.hideHoverPanel()
        }
        let host = NSHostingView(rootView: content)

        if hoverPanel == nil {
            let hp = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hp.level = .popUpMenu
            hp.isOpaque = false
            hp.backgroundColor = .clear
            hp.hasShadow = true
            hp.ignoresMouseEvents = false
            self.hoverPanel = hp
        }

        hoverPanel?.contentView = host

        if let hp = hoverPanel, let screen = NSScreen.main {
            let size = host.fittingSize
            let w = max(size.width, 320)
            let h = max(size.height, 160)
            let x = min(max(sourceFrame.midX - w / 2, screen.frame.minX + 12), screen.frame.maxX - w - 12)
            let y = sourceFrame.maxY + 12
            hp.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
            hp.orderFrontRegardless()
        }
    }

    public func hideHoverPanel() {
        hoverPanel?.orderOut(nil)
        hoverPanel = nil
        hoveredPID = nil
    }

    public func activateApp(pid: pid_t) {
        WindowManager.activate(pid: pid)
        hideHoverPanel()
    }
}

/// SwiftUI view for the replacement Dock pill.
struct DockLayerContentView: View {
    @ObservedObject var controller: DockLayerController

    var body: some View {
        HStack(spacing: 10) {
            ForEach(controller.runningApps) { app in
                Button(action: {
                    controller.activateApp(pid: app.id)
                }) {
                    ZStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "app.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(controller.hoveredPID == app.id ? Color.white.opacity(0.18) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovered in
                    if isHovered {
                        if let screen = NSScreen.main {
                            let mouse = NSEvent.mouseLocation
                            let frame = CGRect(x: mouse.x - 25, y: screen.frame.minY + 12, width: 50, height: 50)
                            controller.showHoverPreviews(for: app.id, sourceFrame: frame)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassContainer(cornerRadius: LiquidGlassTokens.Container.cornerRadius)
    }
}
