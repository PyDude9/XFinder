import AppKit
import SwiftUI

/// "Hold ⌘Q to quit" — the live half of `QuitHold`.
///
/// A `CGEvent` tap at `.cgSessionEventTap` (Accessibility-gated, the same grant ⌘-Tab and snap
/// zones already need) sees ⌘Q before the frontmost app does. A tap of ⌘Q is swallowed; holding
/// it for `holdDuration` quits the app that was frontmost when the press began, with a HUD that
/// fills as you hold. Releasing early, releasing ⌘, or pressing Esc cancels.
///
/// Every rule about *which* events to swallow lives in `QuitHold.Machine` (pure, tested). This
/// type only translates CGEvents into machine inputs and machine actions into UI — because a
/// wrong decision in a global key tap takes the Q key away system-wide.
///
/// Cost model: no polling. The tap is event-driven, the HUD animates with a single SwiftUI
/// animation, and the only timer is one one-shot `DispatchWorkItem` that exists solely while a
/// hold is in progress. Disabled ⇒ no tap, no timer.
@MainActor
@Observable
final class QuitProtectionController {
    static let shared = QuitProtectionController()

    /// Why the feature is or is not active — shown under the toggle, never silent.
    var statusHint = ""

    /// How long ⌘Q must be held. Fixed on purpose: a second setting would be a second control
    /// for one behaviour, and 1 s is the long-standing "hold to quit" convention.
    static let holdDuration: TimeInterval = 1.0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var machine = QuitHold.Machine()
    private var holdTimer: DispatchWorkItem?
    private var target: NSRunningApplication?
    private let hud = QuitHoldHUD()

    private init() {}

    /// `quitProtection.enabled` — default **false**: it changes what ⌘Q does in every app, so it
    /// must be asked for. The settings page's `@AppStorage` default must equal this
    /// (`FeatureKeyDefaultsTests` checks both).
    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "quitProtection.enabled") as? Bool ?? false
    }

    /// Arms or tears down the tap to match the setting and the Accessibility grant. Safe to call
    /// repeatedly: launch, the toggle, and every `didBecomeActive` (a grant made in System
    /// Settings takes effect without a relaunch).
    func applySettings() {
        guard enabled else {
            teardownTap()
            statusHint = L10n.t("Đang tắt.")
            return
        }
        guard WindowManager.isTrusted else {
            teardownTap()
            statusHint = L10n.t("Chưa có quyền Trợ năng — không chặn được ⌘Q.")
            return
        }
        setupTap()
    }

    // MARK: - Event tap

    private func setupTap() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<QuitProtectionController>.fromOpaque(refcon).takeUnretainedValue()
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags.rawValue
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            // The tap's run-loop source is added to the MAIN run loop (below), so this runs on
            // the main thread. The decision must be synchronous — swallow or pass, right now —
            // which is why this is `assumeIsolated` and not a `Task` hop.
            let swallow = MainActor.assumeIsolated {
                controller.shouldSwallow(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
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
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        machine.reset()
        hud.prepare()   // build the panel now, off the hot path
        statusHint = L10n.t("Đang hoạt động — giữ ⌘Q khoảng 1 giây để thoát.")
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        // A tap that is gone can no longer deliver the key-up an in-progress hold is waiting for.
        endHold()
        machine.reset()
        hud.destroy()   // disabled means no window held either
    }

    // MARK: - Decision (main thread, synchronous)

    private func shouldSwallow(type: CGEventType, keyCode: Int, flags: UInt64, isRepeat: Bool) -> Bool {
        // The OS disabled the tap (timeout / user input). Events were dropped, so nothing the
        // machine believes can be trusted: forget the hold, then re-arm — or Q stays broken.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if type == .tapDisabledByTimeout { DiagnosticsLog.record("eventTap", "timeout.quitProtection") }
            endHold()
            machine.reset()
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        let input: QuitHold.Input?
        switch type {
        case .keyDown:
            if QuitHold.isQuitChord(keyCode: keyCode, flags: flags) {
                // Finder / Dock never see a hold: ⌘Q does nothing there, and a HUD promising a
                // quit that cannot happen would be a lie.
                guard QuitHold.intercepts(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
                else { return false }
                input = .quitDown(isRepeat: isRepeat)
            } else if keyCode == QuitHold.keyCodeEscape {
                input = .escapeDown
            } else {
                input = nil
            }
        case .keyUp:
            input = keyCode == QuitHold.keyCodeQ ? .quitUp : nil
        case .flagsChanged:
            input = QuitHold.commandHeld(flags: flags) ? nil : .commandReleased
        default:
            input = nil
        }
        guard let input else { return false }

        switch machine.handle(input) {
        case .passThrough, .ignore:
            return false
        case .swallow:
            return true
        case .beginHold:
            beginHold()
            return true
        case .cancelHold(let swallowEvent):
            endHold()
            return swallowEvent
        case .quit:
            // `.quit` comes only from the timer (`holdElapsed`), never from a key event.
            return true
        }
    }

    // MARK: - Hold lifecycle

    private func beginHold() {
        holdTimer?.cancel()
        let app = NSWorkspace.shared.frontmostApplication
        target = app
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.holdElapsed() }
        }
        holdTimer = work
        let startedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: work)
        // `startedAt` is the moment the timer started, not the moment the HUD finished rendering:
        // measured, the panel appears ~0.2 s later, and a bar that starts at `onAppear` would be
        // ~80 % full when the app quits.
        hud.show(appName: app?.localizedName ?? "", duration: Self.holdDuration, startedAt: startedAt)
    }

    private func holdElapsed() {
        // The machine decides whether this timer still means anything: a cancel that raced the
        // timer leaves the machine idle, and `.ignore` means "do nothing".
        guard machine.handle(.holdElapsed) == .quit else { return }
        let app = target
        endHold()
        app?.terminate()
    }

    /// Hide the HUD and disarm the timer. Does not touch the machine (callers that need a
    /// reset do it themselves).
    private func endHold() {
        holdTimer?.cancel()
        holdTimer = nil
        target = nil
        hud.hide()
    }
}

// MARK: - HUD

/// What the HUD shows for the hold in progress. The panel and its SwiftUI view are built ONCE
/// (see `QuitHoldHUD.prepare`) and fed through this model, because building them inside the event
/// tap's callback was measured at 0.15 s typically and 0.65 s cold — a HUD that first appears at
/// 65 % of a 1 s hold, and then lingers after release, is worse than none.
@MainActor
@Observable
final class QuitHoldHUDModel {
    var appName = ""
    var duration: TimeInterval = QuitProtectionController.holdDuration
    /// When the quit timer started — the bar is positioned from this so it ends with the timer.
    var startedAt = Date()
    /// Bumped on every `show`, so the view restarts its bar even though the same view is reused.
    var generation = 0
}

/// The "Hold ⌘Q to quit <App>" panel. Non-activating and mouse-transparent, so it never takes
/// focus from the app being protected (calling `NSApp.activate` for a floating panel is the
/// documented way to raise every XFinder window — never do it).
@MainActor
final class QuitHoldHUD {
    private let model = QuitHoldHUDModel()
    private var panel: SurfacePanel?

    /// Build the panel and render it once, hidden, so the first real hold pays no creation cost
    /// (measured: an NSHostingController built in the tap callback cost 0.15–0.65 s).
    func prepare() {
        guard panel == nil else { return }
        // 82 pt is the height SwiftUI fits to this content (measured via CGWindowList).
        let p = SurfacePanel(kind: .passive, size: NSSize(width: 340, height: 82))
        p.host(QuitHoldHUDView(model: model))
        // Lay the content out now (still ordered out) so the first show is just an order-front.
        p.contentViewController?.view.layoutSubtreeIfNeeded()
        panel = p
    }

    func show(appName: String, duration: TimeInterval, startedAt: Date) {
        prepare()
        guard let p = panel else { return }
        model.appName = appName
        model.duration = duration
        model.startedAt = startedAt
        model.generation += 1
        p.show(anchor: .topCenter(inset: 72))   // top-centre of the screen the pointer is on
    }

    func hide() {
        panel?.hide()
    }

    /// Release the panel entirely — used when the feature is switched off, so "disabled" really
    /// holds no window.
    func destroy() {
        panel?.hide()
        panel = nil
    }
}

struct QuitHoldHUDView: View {
    let model: QuitHoldHUDModel
    @State private var progress: CGFloat = 0

    var body: some View {
        VStack(spacing: 8) {
            Text("\(L10n.t("Giữ ⌘Q để thoát "))\(model.appName)")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(L10n.t("Nhả phím hoặc nhấn Esc để hủy"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule().fill(Color.primary.opacity(0.85))
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // One animation for the rest of the hold — no per-frame timer. Jump to where the timer
        // already is, then animate the remainder so the bar ends exactly when the app quits.
        .onChange(of: model.generation, initial: false) { startBar() }
    }

    private func startBar() {
        let elapsed = max(0, Date().timeIntervalSince(model.startedAt))
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { progress = CGFloat(min(1, elapsed / model.duration)) }
        let remaining = max(0, model.duration - elapsed)
        withAnimation(.linear(duration: remaining)) { progress = 1 }
    }
}
