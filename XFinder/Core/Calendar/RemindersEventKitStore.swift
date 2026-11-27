import Foundation
import EventKit
import AppKit

/// Live macOS 14+ EventKit adapter for `RemindersStoreProtocol`.
/// Permissions are requested ONLY when `requestFullAccess()` is called explicitly by user action.
@MainActor
final class RemindersEventKitStore: RemindersStoreProtocol {
    private var _eventStore: EKEventStore?

    private func eventStore() -> EKEventStore {
        if let existing = _eventStore { return existing }
        let created = EKEventStore()
        _eventStore = created
        return created
    }

    var isPlatformSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    func authorizationStatus() -> RemindersAccessState {
        guard #available(macOS 14.0, *) else { return .unavailable }
        return Self.mapStatus(EKEventStore.authorizationStatus(for: .reminder))
    }

    func requestFullAccess() async -> RemindersAccessState {
        guard #available(macOS 14.0, *) else { return .unavailable }
        let store = eventStore()
        do {
            let granted = try await store.requestFullAccessToReminders()
            if granted { return .authorized }
            return Self.mapStatus(EKEventStore.authorizationStatus(for: .reminder))
        } catch {
            return Self.mapStatus(EKEventStore.authorizationStatus(for: .reminder))
        }
    }

    func fetchReminders() async throws -> [ReminderItem] {
        let status = authorizationStatus()
        guard status == .authorized else {
            throw status == .restricted ? RemindersError.accessRestricted : RemindersError.accessDenied
        }
        let store = eventStore()
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { @Sendable ekItems in
                let mapped = (ekItems ?? []).map(Self.mapReminder)
                continuation.resume(returning: mapped)
            }
        }
    }

    func createReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
        let status = authorizationStatus()
        guard status == .authorized else {
            throw status == .restricted ? RemindersError.accessRestricted : RemindersError.accessDenied
        }
        let trimmed = draft.trimmedTitle
        guard !trimmed.isEmpty else { throw RemindersError.emptyTitle }

        let store = eventStore()
        guard let targetCalendar = store.defaultCalendarForNewReminders() else {
            throw RemindersError.noDefaultList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = targetCalendar
        reminder.title = trimmed
        reminder.notes = draft.notes
        if let due = draft.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: due
            )
        }
        do {
            try store.save(reminder, commit: true)
            return Self.mapReminder(reminder)
        } catch {
            throw RemindersError.storeFailure(error.localizedDescription)
        }
    }

    func setCompleted(id: String, completed: Bool) async throws -> ReminderItem {
        let status = authorizationStatus()
        guard status == .authorized else {
            throw status == .restricted ? RemindersError.accessRestricted : RemindersError.accessDenied
        }
        let store = eventStore()
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.notFound
        }
        item.isCompleted = completed
        item.completionDate = completed ? Date() : nil
        do {
            try store.save(item, commit: true)
            return Self.mapReminder(item)
        } catch {
            throw RemindersError.storeFailure(error.localizedDescription)
        }
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject? {
        let store = eventStore()
        return NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }

    func stopObserving(_ token: AnyObject?) {
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
            NSWorkspace.shared.open(url)
        }
    }

    @available(macOS 14.0, *)
    private static func mapStatus(_ status: EKAuthorizationStatus) -> RemindersAccessState {
        switch status {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    nonisolated private static func mapReminder(_ r: EKReminder) -> ReminderItem {
        let due: Date? = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(
            id: r.calendarItemIdentifier,
            title: r.title ?? "",
            notes: r.notes,
            dueDate: due,
            isCompleted: r.isCompleted,
            listTitle: r.calendar?.title,
            priority: r.priority
        )
    }
}
