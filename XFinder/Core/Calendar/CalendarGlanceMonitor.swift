import Foundation
import EventKit
import AppKit

/// N4 — the EventKit half of the Glance page. ONE reader of `notch.calendar`. While on: asks for full access to
/// events (and reminders) when the page first needs them, fetches a ±5-day window into `GlanceEvent`s, and
/// refetches on `EKEventStoreChanged` (the system posts it; no polling) and once a minute while the page is open
/// (the "up next" line and the countdown move with the clock). Off ⇒ no store, no observer, no timer.
@MainActor
final class CalendarGlanceMonitor {
    static let shared = CalendarGlanceMonitor()

    enum Access: Equatable { case unknown, granted, denied, restricted, notDetermined }

    private(set) var events: [GlanceEvent] = []
    private(set) var reminders: [GlanceEvent] = []
    private(set) var eventAccess: Access = .unknown
    private(set) var reminderAccess: Access = .unknown
    var onChange: (() -> Void)?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "notch.calendar") as? Bool ?? false }
    var hidesAllDay: Bool { UserDefaults.standard.object(forKey: "notch.calendar.hideAllDay") as? Bool ?? false }

    // §3b #33 — meeting alerts under the notch. ONE reader of each key.
    var alertsOn: Bool { UserDefaults.standard.object(forKey: "notch.calendar.alerts") as? Bool ?? true }
    var alertLead: Int { UserDefaults.standard.object(forKey: "notch.calendar.alertLead") as? Int ?? 5 }
    var alertSound: Bool { UserDefaults.standard.object(forKey: "notch.calendar.alertSound") as? Bool ?? true }
    private var alerted: Set<String> = []
    private var snoozed: [String: Date] = [:]
    /// ONE wall-clock timer, set for the next alert only (a Timer with a fire date still fires after the Mac wakes,
    /// late rather than never). None when there is nothing upcoming, the switch is off, or the calendar is off.
    private var alertTimer: Timer?

    private var store: EKEventStore?
    private var observer: NSObjectProtocol?
    private var pageOpen = false
    private var minuteTimer: Timer?

    func applySettings(underMaster master: Bool = true) {
        if master && isEnabled { start() } else { stop() }
    }

    private func start() {
        guard store == nil else { return }
        let s = EKEventStore()
        store = s
        eventAccess = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        reminderAccess = Self.access(for: EKEventStore.authorizationStatus(for: .reminder))
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: s, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refetch() }
        }
        refetch()
    }

    private func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        minuteTimer?.invalidate(); minuteTimer = nil
        alertTimer?.invalidate(); alertTimer = nil
        store = nil
        if !events.isEmpty || !reminders.isEmpty { events = []; reminders = []; onChange?() }
    }

    /// The hub page came on screen / went away: a 60 s refetch exists only while it is open.
    func setPageOpen(_ open: Bool) {
        pageOpen = open
        if open, store != nil, minuteTimer == nil {
            let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.refetch() } }
            RunLoop.main.add(t, forMode: .common)
            minuteTimer = t
            refetch()
        } else if !open, let t = minuteTimer {
            t.invalidate(); minuteTimer = nil
        }
    }

    /// Ask macOS (the system sheet). Called from the page's button, never on a switch.
    func requestAccess() {
        guard let store else { return }
        Task { @MainActor in
            let ok = (try? await store.requestFullAccessToEvents()) ?? false
            eventAccess = ok ? .granted : Self.access(for: EKEventStore.authorizationStatus(for: .event))
            let rOK = (try? await store.requestFullAccessToReminders()) ?? false
            reminderAccess = rOK ? .granted : Self.access(for: EKEventStore.authorizationStatus(for: .reminder))
            refetch()
        }
    }

    func refetch() {
        guard let store else { return }
        eventAccess = Self.access(for: EKEventStore.authorizationStatus(for: .event))
        reminderAccess = Self.access(for: EKEventStore.authorizationStatus(for: .reminder))
        let cal = Calendar.current
        let now = Date()
        guard let from = cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: now)),
              let to = cal.date(byAdding: .day, value: 6, to: cal.startOfDay(for: now)) else { return }
        var changed = false
        if eventAccess == .granted {
            let pred = store.predicateForEvents(withStart: from, end: to, calendars: nil)
            let fetched = store.events(matching: pred).map(Self.glance(from:))
            if fetched != events { events = fetched; changed = true }
        } else if !events.isEmpty { events = []; changed = true }
        if reminderAccess == .granted {
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: from, ending: to, calendars: nil)
            store.fetchReminders(matching: pred) { [weak self] items in
                let mapped = (items ?? []).compactMap(Self.glance(fromReminder:))
                Task { @MainActor in
                    guard let self else { return }
                    if mapped != self.reminders { self.reminders = mapped; self.onChange?(); self.scheduleAlert() }
                }
            }
        } else if !reminders.isEmpty { reminders = []; changed = true }
        if changed { onChange?() }
        scheduleAlert()
    }

    // MARK: Meeting alerts (§3b #33)

    func scheduleAlert() {
        alertTimer?.invalidate(); alertTimer = nil
        guard store != nil, alertsOn,
              let plan = MeetingAlertRules.next(events: events + reminders, now: Date(), leadMinutes: alertLead,
                                                alerted: alerted, snoozedUntil: snoozed, includeReminders: true) else { return }
        let key = plan.key
        let t = Timer(fire: plan.fireAt, interval: 0, repeats: false) { _ in
            Task { @MainActor in CalendarGlanceMonitor.shared.fireAlert(key: key) }
        }
        RunLoop.main.add(t, forMode: .common)
        alertTimer = t
    }

    private func fireAlert(key: String) {
        alertTimer = nil
        guard let e = (events + reminders).first(where: { MeetingAlertRules.key($0) == key }) else { scheduleAlert(); return }
        alerted.insert(key)
        snoozed.removeValue(forKey: key)
        let mins = MeetingAlertRules.minutesUntil(e.start, now: Date())
        let when = mins == 0 ? L10n.t(MeetingAlertRules.startingNowKey) : "\(L10n.t("còn "))\(mins)\(L10n.t(" phút"))"
        let title = e.title.isEmpty ? L10n.t("Sự kiện") : e.title          // the user's own words: not translated
        var buttons: [LiveActivity.Button] = []
        if let url = GlanceRules.meetingURL(in: e) { buttons.append(.join(url)) } else { buttons.append(.openCalendar) }
        buttons.append(.snooze(key: key))
        NotchSurfaceController.shared.present(LiveActivity.Item(
            kind: .meeting, symbol: e.isReminder ? "checklist" : "calendar.badge.clock",
            titleKey: e.isReminder ? MeetingAlertRules.reminderHeadlineKey : MeetingAlertRules.eventHeadlineKey, detail: "\(title) · \(when)", tint: .warning,
            duration: 15, buttons: buttons))
        if alertSound { NSSound(named: "Glass")?.play() }
        scheduleAlert()
    }

    func snooze(key: String) {
        snoozed[key] = Date().addingTimeInterval(TimeInterval(MeetingAlertRules.snoozeMinutes * 60))
        scheduleAlert()
    }

    nonisolated static func access(for s: EKAuthorizationStatus) -> Access {
        switch s {
        case .fullAccess: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        default: return .denied          // .writeOnly and anything newer: not enough to read
        }
    }

    nonisolated static func glance(from e: EKEvent) -> GlanceEvent {
        GlanceEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "", start: e.startDate, end: e.endDate,
                    isAllDay: e.isAllDay, location: e.location, notes: e.notes, url: e.url, calendarTitle: e.calendar?.title)
    }

    nonisolated static func glance(fromReminder r: EKReminder) -> GlanceEvent? {
        guard let due = r.dueDateComponents, let date = Calendar.current.date(from: due) else { return nil }
        let timed = due.hour != nil
        return GlanceEvent(id: r.calendarItemIdentifier, title: r.title ?? "", start: date, end: date.addingTimeInterval(timed ? 1800 : 86_400),
                           isAllDay: !timed, location: r.location, notes: r.notes, url: r.url, calendarTitle: r.calendar?.title, isReminder: true)
    }

    /// Open the system Calendar app on a day (there is no public API to open it at an event).
    func openCalendarApp(on day: Date) {
        let seconds = Int(day.timeIntervalSinceReferenceDate)
        if let url = URL(string: "ical://?date=\(seconds)") { NSWorkspace.shared.open(url) }
        else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
