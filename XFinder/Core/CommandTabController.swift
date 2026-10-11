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
            statusHint = L10n.t("Đang tắt.")
            return
        }
        guard WindowManager.isTrusted else {
            teardownTap()
            statusHint = L10n.t("Chưa có quyền Trợ năng — không chặn được Command-Tab.")
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
            statusHint = L10n.t("Không tạo được event tap — kiểm tra quyền Trợ năng.")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        statusHint = L10n.t("Đang hoạt động — giữ ⌘ và nhấn Tab.")
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        dismiss(activate: false)
    }

    private let isActiveSnapshot = Locked<Bool>(false)
    /// Mirrors the store's `isSearchActive` for the tap thread: while the user types a query, Q/H/Space/`
    /// are letters, not commands.
    private let searchActiveSnapshot = Locked<Bool>(false)

    nonisolated private var hotkeyPreference: String {
        UserDefaults.standard.string(forKey: "windowPreview.switcherHotkey") ?? "commandTab"
    }

    /// Runs on the tap's thread — hop to the main actor for any UI work.
    private nonisolated func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // A tap disabled by timeout must be re-armed or ⌘-Tab breaks entirely.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = self.eventTap, CFMachPortIsValid(tap) {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isOptionHotkey = hotkeyPreference == "optionTab"
        let modifierDown = isOptionHotkey ? flags.contains(.maskAlternate) : flags.contains(.maskCommand)

        if type == .keyDown, modifierDown, keyCode == 48 { // Tab
            let backwards = flags.contains(.maskShift)
            Task { @MainActor in self.step(backwards: backwards) }
            return nil // consume
        }

        // When switcher is active:
        if isActiveSnapshot.value {
            // Comma (,) focuses search field
            if type == .keyDown, keyCode == 43 {
                searchActiveSnapshot.value = true
                Task { @MainActor in
                    PreviewOverlayWindow.shared.focusSearch()
                }
                return nil
            }

            // Phase C — while NOT typing a query: Q closes the selected window, H hides its app,
            // Space zooms the thumbnail, ` flips between one card per app and one per window.
            if type == .keyDown, !searchActiveSnapshot.value {
                switch keyCode {
                case 12: Task { @MainActor in self.closeSelected() }; return nil          // Q
                case 4:  Task { @MainActor in self.hideSelectedApp() }; return nil        // H
                case 49: Task { @MainActor in self.toggleZoom() }; return nil             // Space
                case 50: Task { @MainActor in self.toggleMode() }; return nil             // `
                default: break
                }
            }

            // Left arrow
            if type == .keyDown, keyCode == 123 {
                Task { @MainActor in self.step(backwards: true) }
                return nil
            }

            // Right arrow
            if type == .keyDown, keyCode == 124 {
                Task { @MainActor in self.step(backwards: false) }
                return nil
            }

            // Return / Enter commits selection
            if type == .keyDown, keyCode == 36 {
                Task { @MainActor in self.dismiss(activate: true) }
                return nil
            }

            // Escape
            if type == .keyDown, keyCode == 53 {
                searchActiveSnapshot.value = false
                Task { @MainActor in
                    if WindowPreviewStore.shared.isSearchActive {
                        WindowPreviewStore.shared.isSearchActive = false
                        WindowPreviewStore.shared.searchQuery = ""
                    } else {
                        self.dismiss(activate: false)
                    }
                }
                return nil
            }
        }

        // Modifier released → commit the selection (unless in active search typing mode)
        if type == .flagsChanged, !modifierDown {
            Task { @MainActor in
                if self.isActive && !WindowPreviewStore.shared.isSearchActive {
                    self.dismiss(activate: true)
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Switcher UI

    private func step(backwards: Bool) {
        if !isActive {
            // Phase C: optionally only the screen under the pointer (CG space for the window bounds).
            var screenCG: CGRect?
            if WindowPreviewStore.currentScreenOnly, let primary = NSScreen.screens.first {
                let screen = WindowManager.screenUnderPointer()
                screenCG = WindowPreviewStore.cgRect(forAppKitFrame: screen.frame, primaryHeight: primary.frame.height)
            }
            WindowPreviewStore.shared.loadSwitchableWindows(screenCG: screenCG)
            let items = WindowPreviewStore.shared.filteredPreviewItems
            guard !items.isEmpty else { return }
            selection = items.count > 1 ? 1 : 0
            WindowPreviewStore.shared.selectedIndex = selection
            isActive = true
            isActiveSnapshot.value = true

            // Check if modifier was already released during a quick tap
            let isOptionHotkey = hotkeyPreference == "optionTab"
            let modifierKey: NSEvent.ModifierFlags = isOptionHotkey ? .option : .command
            if !NSEvent.modifierFlags.contains(modifierKey) {
                dismiss(activate: true)
                return
            }

            PreviewOverlayWindow.shared.present(
                selection: selection,
                onCommit: { [weak self] idx in
                    self?.selection = idx
                    WindowPreviewStore.shared.selectedIndex = idx
                    self?.dismiss(activate: true)
                },
                onDismiss: { [weak self] in
                    self?.dismiss(activate: false)
                }
            )
            return
        }
        WindowPreviewStore.shared.step(forward: !backwards)
        selection = WindowPreviewStore.shared.selectedIndex
        if WindowPreviewStore.shared.isZoomed { WindowPreviewStore.shared.refreshZoom() }
        PreviewOverlayWindow.shared.updateSelection(selection)
    }

    // MARK: - Phase C actions (all while the switcher is up and the modifier held)

    private func syncOverlay() {
        selection = WindowPreviewStore.shared.selectedIndex
        if WindowPreviewStore.shared.filteredPreviewItems.isEmpty { dismiss(activate: false); return }
        PreviewOverlayWindow.shared.updateSelection(selection)
    }

    /// Q: close the selected window (the app's representative window in app mode) via its AX close button.
    private func closeSelected() {
        let store = WindowPreviewStore.shared
        guard isActive, let item = store.commitSelection(), item.windowID != 0,
              let win = WindowManager.listWindows().first(where: { $0.id == item.windowID }) else { return }
        guard WindowManager.closeWindow(win) else { return }     // no AX ⇒ nothing happens, nothing pretends to
        store.removeWindow(id: item.windowID)
        syncOverlay()
        // The window server lags the press; converge on the truth once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                store.reload(); self.syncOverlay()
            }
        }
    }

    /// H: hide the selected app (`NSRunningApplication.hide`), drop its cards.
    private func hideSelectedApp() {
        let store = WindowPreviewStore.shared
        guard isActive, let item = store.commitSelection() else { return }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first
            ?? WindowManager.listWindows().first(where: { $0.id == item.windowID }).flatMap { NSRunningApplication(processIdentifier: $0.ownerPID) }
        guard let app, app.hide() else { return }
        store.removeApp(bundleID: item.bundleID)
        syncOverlay()
    }

    private func toggleZoom() {
        guard isActive else { return }
        WindowPreviewStore.shared.toggleZoom()
        PreviewOverlayWindow.shared.updateSelection(selection)   // the panel grows/shrinks for the zoom
    }

    private func toggleMode() {
        guard isActive else { return }
        WindowPreviewStore.shared.toggleMode()
        syncOverlay()
    }

    private func dismiss(activate: Bool) {
        if activate, let item = WindowPreviewStore.shared.commitSelection() {
            let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: item.bundleID).first
                ?? NSWorkspace.shared.runningApplications.first(where: {
                    $0.localizedName == item.appName || $0.bundleIdentifier == item.bundleID
                })

            if let app = runningApp {
                if app.isHidden { app.unhide() }
                _ = app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                _ = WindowManager.activate(pid: app.processIdentifier)
            }

            if !item.isGroup, let win = WindowManager.listWindows().first(where: { $0.id == item.windowID }) {
                WindowManager.raiseWindow(win)
            }
        }
        isActive = false
        isActiveSnapshot.value = false
        searchActiveSnapshot.value = false
        selection = 0
        PreviewOverlayWindow.shared.dismiss()
        WindowPreviewStore.shared.clear()
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
