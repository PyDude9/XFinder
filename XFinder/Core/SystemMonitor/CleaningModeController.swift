import AppKit
import SwiftUI

/// XF-T27 — Lau bàn phím: the keyboard (and the media/brightness keys) does nothing for a few minutes so it can be
/// wiped; the mouse keeps working. Esc five times, the Mở khoá button, or the timer unlocks. The tap exists only while
/// cleaning. Rules (Esc counter, minutes) are `CaffeineRules`.
@MainActor
@Observable
final class CleaningModeController {
    static let shared = CleaningModeController()
    private init() {}

    private(set) var isActive = false
    private(set) var secondsLeft = 0

    /// ONE reader (the System page's picker binds the same key, default 2).
    var minutes: Int { CaffeineRules.clampCleaning(UserDefaults.standard.object(forKey: "cleaning.minutes") as? Int ?? 2) }

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var tapSource: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var panels: [NSPanel] = []
    @ObservationIgnored fileprivate var esc = CaffeineRules.EscCounter()

    func start() {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            CaffeineController.toast.show(symbol: "exclamationmark.triangle.fill", title: L10n.t("Cần quyền Trợ năng để khoá bàn phím."), duration: 3.0)
            return
        }
        // keyDown, keyUp, flagsChanged and NX_SYSDEFINED (14: volume, brightness, media keys).
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue) | (CGEventMask(1) << 14)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: { _, type, event, _ in
            // The source is on the MAIN run loop: the callback runs on the main thread. Only Sendable values cross.
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let pass = MainActor.assumeIsolated { CleaningModeController.shared.handle(type, keycode: keycode) }
            return pass ? Unmanaged.passUnretained(event) : nil
        }, userInfo: nil), let src = CFMachPortCreateRunLoopSource(nil, port, 0) else {
            CaffeineController.toast.show(symbol: "exclamationmark.triangle.fill", title: L10n.t("Cần quyền Trợ năng để khoá bàn phím."), duration: 3.0)
            return
        }
        tap = port; tapSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        isActive = true
        esc = CaffeineRules.EscCounter()
        secondsLeft = minutes * 60
        showPanels()
        let t = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                let c = CleaningModeController.shared
                c.secondsLeft -= 1
                if c.secondsLeft <= 0 { c.stop() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        guard isActive else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil; tapSource = nil
        timer?.invalidate(); timer = nil
        for p in panels { p.orderOut(nil) }
        panels = []
        isActive = false
    }

    /// True = let the event through (only the tap's own disable notices); every key is swallowed while cleaning.
    private func handle(_ type: CGEventType, keycode: Int64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, CFMachPortIsValid(tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        if type == .keyDown, esc.press(isEscape: keycode == 53, at: ProcessInfo.processInfo.systemUptime) {
            DispatchQueue.main.async { CleaningModeController.shared.stop() }
        }
        return false
    }

    private func showPanels() {
        for screen in NSScreen.screens {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .screenSaver
            p.isOpaque = false
            p.backgroundColor = .clear
            p.animationBehavior = .none
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: CleaningOverlay())
            p.setFrame(screen.frame, display: true)
            p.orderFrontRegardless()
            panels.append(p)
        }
    }
}

private struct CleaningOverlay: View {
    @State private var controller = CleaningModeController.shared

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: XFinderTokens.Space.section) {
                Image(systemName: "keyboard").font(.system(size: 44, weight: .light))
                Text(L10n.t("Đang lau bàn phím")).font(.title2.weight(.semibold))
                Text(L10n.t("Bàn phím đang khoá. Bấm Esc 5 lần hoặc Mở khoá.")).font(XFinderTokens.Font.row).foregroundColor(.secondary)
                Text(String(format: "%d:%02d", controller.secondsLeft / 60, max(controller.secondsLeft, 0) % 60))
                    .font(.system(size: 28, weight: .medium)).monospacedDigit()
                Button(L10n.t("Mở khoá")) { controller.stop() }.controlSize(.large)
            }
            .foregroundColor(.white)
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
        }
    }
}
