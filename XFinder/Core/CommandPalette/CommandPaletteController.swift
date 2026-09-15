import Foundation
import AppKit
import SwiftUI
import Carbon

/// Controller quản lý Command Palette với hotkey ⌥Space
final class CommandPaletteController {
    static let shared = CommandPaletteController()

    private var panel: NSPanel?
    private var eventTap: CFMachPort?
    private var isEnabled = true

    private init() {}

    func start() {
        isEnabled = UserDefaults.standard.bool(forKey: "commandPalette.enabled")
        guard isEnabled else { return }

        installEventTap()
    }

    func stop() {
        isEnabled = false
        removeEventTap()
        closePanel()
    }

    private func installEventTap() {
        // Event tap để bắt ⌥Space toàn hệ thống
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                let controller = Unmanaged<CommandPaletteController>.fromOpaque(refcon!).takeUnretainedValue()
                return controller.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ CommandPalette: Cần quyền Accessibility để hotkey hoạt động")
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ⌥Space: Option (0x80000) + Space (49)
        let isOption = flags.contains(.maskAlternate)
        let isSpace = keyCode == 49

        if isOption && isSpace {
            // Không có Shift/Command/Control cùng lúc
            let otherModifiers = flags.intersection([.maskShift, .maskCommand, .maskControl])
            if otherModifiers.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.togglePanel()
                }
                return nil  // Chặn event
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if panel == nil {
            let contentView = CommandPaletteView(onClose: { [weak self] in
                self?.closePanel()
            })

            let hosting = NSHostingController(rootView: contentView)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.contentViewController = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            self.panel = panel
        }

        if let panel = panel, let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelWidth: CGFloat = 600
            let panelHeight: CGFloat = 400
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.midY + 100  // Hơi lên trên giữa màn hình

            panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func closePanel() {
        panel?.orderOut(nil)
    }
}
