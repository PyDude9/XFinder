import AppKit
import EventKit
import SwiftUI

/// Smart Selection E5 — the badge beside a selection and the panel it opens. Both panels are built once and reused
/// (a hosting view built on the way to the screen cost 0.15–0.65 s in QuitProtection).
///
/// The badge is ordered front WITHOUT becoming key, so the source app keeps its selection highlighted; its hosting
/// view accepts the first mouse, so one click works while another app is frontmost (B1b review). The panel becomes
/// key (Esc closes it, click-outside dismisses it) — by then the user has chosen to act.
@MainActor
final class SmartSelectionBadge {
    static let shared = SmartSelectionBadge()
    private init() {}

    let model = SmartSelectionModel()
    private var badge: SurfacePanel?
    private var panel: SurfacePanel?
    private lazy var eventStore = EKEventStore()

    var isPanelOpen: Bool { panel?.isVisible ?? false }

    // MARK: Badge

    func showBadge(frame: CGRect, text: String, actions: [SmartSelectionRules.Action],
                   sourceApp: String?, sourceBundleID: String?) {
        model.text = text
        model.actions = actions
        model.sourceApp = sourceApp
        model.sourceBundleID = sourceBundleID
        model.notice = nil
        model.calendarAdded = nil
        if isPanelOpen { panel?.hide() }
        if badge == nil {
            let p = SurfacePanel(kind: .interactive, size: frame.size)
            p.contentView = FirstMouseHostingView(rootView: SmartSelectBadgeView(model: model))
            badge = p
        }
        badge?.setFrame(frame, display: true)
        badge?.orderFrontRegardless()
    }

    func hideBadge() { badge?.orderOut(nil) }

    func hideAll() {
        badge?.orderOut(nil)
        panel?.orderOut(nil)
    }

    // MARK: Panel

    func openPanel() {
        guard let badgeFrame = badge?.frame else { return }
        badge?.orderOut(nil)
        let size = CGSize(width: 360, height: Self.panelHeight(for: model.actions))
        if panel == nil {
            let p = SurfacePanel(kind: .interactive, size: size)
            p.contentView = FirstMouseHostingView(rootView: SmartSelectPanelView(model: model))
            panel = p
        }
        let screen = NSScreen.screens.first { $0.frame.contains(badgeFrame.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        // Below-right of where the badge was; above it when there is no room below.
        var origin = CGPoint(x: badgeFrame.minX, y: badgeFrame.minY - size.height - 4)
        if origin.y < visible.minY { origin.y = badgeFrame.maxY + 4 }
        let frame = SurfaceGeometry.clamp(CGRect(origin: origin, size: size), into: visible)
        panel?.setFrame(frame, display: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.installClickOutside { [weak self] in self?.closePanel() }
    }

    func closePanel() {
        panel?.hide()
        SelectionWatcher.shared.dismiss()
    }

    static func panelHeight(for actions: [SmartSelectionRules.Action]) -> CGFloat {
        let rows = actions.reduce(CGFloat(0)) { sum, a in
            switch a {
            case .time(let t): return sum + (t.regionNote == nil ? 58 : 74)
            case .calendar, .currency: return sum + 64
            case .define: return sum + 74
            default: return sum + 50
            }
        }
        return min(520, 86 + rows + 26)
    }

    /// E6 — a rate table arrived (or the request failed) while the badge or panel shows a selection: recompute the
    /// rows from the same text. Every currency row state has the same height, so the open panel keeps its frame.
    func refreshCurrency() {
        guard !model.text.isEmpty, (badge?.isVisible ?? false) || isPanelOpen else { return }
        let fresh = SmartSelectionRules.actions(for: model.text, now: Date(), localZone: .current,
                                                currency: CurrencyRateStore.shared.context(), define: DictionaryLookup.definition)
        if fresh != model.actions { model.actions = fresh }
    }

    // MARK: Actions

    func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ClipboardSounds.playCopy()
        model.notice = .init(key: SmartSelectionRules.NoticeKey.copied, kind: .success)
    }

    func translate() {
        let text = model.text, app = model.sourceApp
        let frame = panel?.frame ?? badge?.frame
        // Hide both badge and panel immediately (orderOut is synchronous) before the translate panel appears.
        badge?.orderOut(nil)
        panel?.orderOut(nil)
        SelectionWatcher.shared.dismiss()
        TranslateSelectionController.shared.translate(text: text, sourceApp: app, anchorRect: frame)
    }

    /// One event in the default calendar. Asked from the panel's button only; the button shows the title and the
    /// date first, so the click is the confirmation.
    func addToCalendar(title: String, date: Date, hasTime: Bool) {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            saveEvent(title: title, date: date, hasTime: hasTime)
        case .notDetermined:
            Task { @MainActor in
                let granted = (try? await self.eventStore.requestFullAccessToEvents()) ?? false
                if granted { self.saveEvent(title: title, date: date, hasTime: hasTime) }
                else { self.model.notice = .init(key: SmartSelectionRules.NoticeKey.calendarDenied, kind: .warning, opensCalendarPrivacy: true) }
            }
        default:
            model.notice = .init(key: SmartSelectionRules.NoticeKey.calendarDenied, kind: .warning, opensCalendarPrivacy: true)
        }
    }

    private func saveEvent(title: String, date: Date, hasTime: Bool) {
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            model.notice = .init(key: SmartSelectionRules.NoticeKey.noDefaultCalendar, kind: .warning)
            return
        }
        let ev = EKEvent(eventStore: eventStore)
        ev.title = title.isEmpty ? L10n.t("Sự kiện mới") : title
        if hasTime {
            ev.startDate = date
            ev.endDate = date.addingTimeInterval(3600)
        } else {
            let day = Calendar.current.startOfDay(for: date)
            ev.isAllDay = true
            ev.startDate = day
            ev.endDate = day
        }
        ev.calendar = calendar
        do {
            try eventStore.save(ev, span: .thisEvent)
            model.calendarAdded = date
            model.notice = .init(key: SmartSelectionRules.NoticeKey.calendarAdded, kind: .success)
        } catch {
            model.notice = .init(key: SmartSelectionRules.NoticeKey.calendarFailed, kind: .error)
        }
    }

    func openCalendar(on date: Date) {
        CalendarGlanceMonitor.shared.openCalendarApp(on: date)
    }

    func openCalendarPrivacy() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// What the badge and the panel show. Mutated by `SmartSelectionBadge`.
@MainActor
@Observable
final class SmartSelectionModel {
    struct Notice: Equatable {
        enum Kind { case success, warning, error }
        let key: String
        let kind: Kind
        var opensCalendarPrivacy = false
    }

    var text = ""
    var actions: [SmartSelectionRules.Action] = []
    var sourceApp: String?
    var sourceBundleID: String?
    var notice: Notice?
    var calendarAdded: Date?
}
