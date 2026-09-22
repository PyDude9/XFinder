import AppKit
import SwiftUI

/// Command-Tab window switcher with live thumbnails.
///
/// Intercepting ⌘-Tab needs a `CGEvent` tap at `.cgSessionEventTap`, which the
/// system only permits for Accessibility-trusted processes — the same grant as
/// snap zones. Without trust the tap cannot be created, and the settings page
/// says so rather than showing a switch that does nothing.
///
/// The tap consumes ⌘-Tab / ⌘-⇧-Tab only while the feature is enabled; every
/// other key passes through untouched.
@MainActor
@Observable
final class CommandTabController {
    static let shared = CommandTabController()

    private(set) var isActive = false
    var statusHint = ""

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var panel: NSPanel?
    private var entries: [WindowManager.WindowInfo] = []
    private var selection = 0

    private init() {}

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "windowPreview.commandTabEnabled") as? Bool ?? false
    }

    func applySettings() {
        guard enabled else {
            teardownTap()
            statusHint = "Đang tắt."
            return
        }
        guard WindowManager.isTrusted else {
            teardownTap()
            statusHint = "Chưa có quyền Trợ năng — không chặn được Command-Tab."
            return
        }
        setupTap()
    }

    // MARK: - Event tap

    private func setupTap() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<CommandTabController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            statusHint = "Không tạo được event tap — kiểm tra quyền Trợ năng."
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        statusHint = "Đang hoạt động — giữ ⌘ và nhấn Tab."
    }

    private func teardownTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        dismiss(activate: false)
    }

    /// Runs on the tap's thread — hop to the main actor for any UI work.
    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // A tap disabled by timeout must be re-armed or ⌘-Tab breaks entirely.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let commandDown = flags.contains(.maskCommand)

        if type == .keyDown, commandDown, keyCode == 48 { // Tab
            let backwards = flags.contains(.maskShift)
            Task { @MainActor in self.step(backwards: backwards) }
            return nil // consume
        }

        if type == .keyDown, keyCode == 53 { // Escape
            Task { @MainActor in
                if self.isActive { self.dismiss(activate: false) }
            }
            return Unmanaged.passUnretained(event)
        }

        // Command released → commit the selection.
        if type == .flagsChanged, !commandDown {
            Task { @MainActor in
                if self.isActive { self.dismiss(activate: true) }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Switcher UI

    private func step(backwards: Bool) {
        if !isActive {
            entries = switchableWindows()
            guard !entries.isEmpty else { return }
            selection = entries.count > 1 ? 1 : 0
            isActive = true
            showPanel()
            return
        }
        guard !entries.isEmpty else { return }
        selection = (selection + (backwards ? -1 : 1) + entries.count) % entries.count
        refreshPanel()
    }

    /// Every switchable **window**, not one row per app.
    ///
    /// This used to dedupe by pid, which made the switcher an app switcher —
    /// and a preview list of one icon per app shows the user nothing they did
    /// not already know. With per-window rows plus a live thumbnail, ⌘-Tab can
    /// pick "the second Safari window" directly, which is the whole point.
    /// Capped so a machine with dozens of windows still renders a sane panel.
    private func switchableWindows() -> [WindowManager.WindowInfo] {
        Array(WindowManager.listWindows()
            .filter { $0.bounds.width > 80 && $0.bounds.height > 80 }
            .prefix(12))
    }

    private func showPanel() {
        dismissPanelOnly()
        let host = NSHostingView(rootView: CommandTabSwitcherView(entries: entries, selection: selection))
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.contentView = host
        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2,
                                     y: screen.frame.midY - size.height / 2))
        }
        p.orderFrontRegardless()
        panel = p
    }

    private func refreshPanel() {
        guard let panel, let host = panel.contentView as? NSHostingView<CommandTabSwitcherView> else { return }
        host.rootView = CommandTabSwitcherView(entries: entries, selection: selection)
    }

    private func dismissPanelOnly() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func dismiss(activate: Bool) {
        if activate, entries.indices.contains(selection) {
            // Raise the chosen WINDOW, not the whole app — otherwise picking
            // one of several windows of the same app raises an arbitrary one.
            WindowManager.raiseWindow(entries[selection])
        }
        isActive = false
        entries = []
        selection = 0
        dismissPanelOnly()
    }
}

/// ⌘-Tab switcher showing a live thumbnail per **window**.
///
/// Previously this rendered only the app icon, which is why the user reported
/// "no preview": there was never a thumbnail here at all. Thumbnails come from
/// ScreenCaptureKit (`CGWindowListCreateImage` is unavailable on macOS 26/27),
/// loaded in one batched round trip and cached by window id so stepping through
/// the list does not re-capture.
private struct CommandTabSwitcherView: View {
    let entries: [WindowManager.WindowInfo]
    let selection: Int

    @State private var thumbs: [CGWindowID: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name of the highlighted window, like the system switcher.
            if entries.indices.contains(selection) {
                let win = entries[selection]
                Text(win.title.isEmpty ? win.ownerName : "\(win.ownerName) — \(win.title)")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 760, alignment: .center)
            }

            HStack(spacing: 10) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, win in
                    VStack(spacing: 5) {
                        ZStack {
                            if let img = thumbs[win.id] {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                // Honest placeholder while the capture lands —
                                // never a blank box with no explanation.
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color(.controlBackgroundColor))
                                    .overlay(Image(systemName: "macwindow")
                                        .foregroundColor(.secondary))
                            }
                        }
                        .frame(width: 132, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 5))

                        // Small app icon under each thumbnail identifies the
                        // owner when two windows look alike.
                        if let icon = NSRunningApplication(processIdentifier: win.ownerPID)?.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                        }
                    }
                    .padding(7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(index == selection ? Color.accentColor.opacity(0.28) : .clear)
                    )
                }
            }

            if !WindowManager.canRecordScreen {
                Text(L10n.t("Thiếu quyền Ghi màn hình — chưa có ảnh xem trước. Mở Tổng quan → “Cấp mọi quyền…”."))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.windowBackgroundColor).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.separatorColor), lineWidth: 1))
        .task(id: entries.map(\.id)) {
            let ids = entries.map(\.id).filter { thumbs[$0] == nil }
            guard !ids.isEmpty else { return }
            let made = await WindowManager.thumbnails(windowIDs: ids, maxSize: 260)
            for (id, img) in made { thumbs[id] = img }
        }
    }
}
