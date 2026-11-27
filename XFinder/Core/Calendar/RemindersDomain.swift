import Foundation
import Combine

/// Permission & availability state for the Dynamic Island EventKit Reminders module.
/// Pure Foundation so `Tests/XFinderLogicTests` verifies every transition without TCC/AppKit.
public enum RemindersAccessState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

/// Filter tabs inside `NotchRemindersPage`.
public enum RemindersFilter: String, CaseIterable, Equatable, Sendable, Identifiable {
    case today
    case upcoming
    case all
    case completed

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .today: return "Hôm nay"
        case .upcoming: return "Sắp tới"
        case .all: return "Tất cả"
        case .completed: return "Đã xong"
        }
    }
}

/// Quick due-date presets for inline reminder creation inside the Island.
public enum ReminderDuePreset: String, CaseIterable, Equatable, Sendable, Identifiable {
    case none
    case today
    case tomorrow

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .none: return "Không hạn"
        case .today: return "Hôm nay"
        case .tomorrow: return "Ngày mai"
        }
    }

    public func dueDate(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none:
            return nil
        case .today:
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
        case .tomorrow:
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay) ?? nextDay
        }
    }
}

/// Pure snapshot of one EventKit reminder item.
public struct ReminderItem: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    public var isCompleted: Bool
    public var listTitle: String?
    public var priority: Int

    public init(
        id: String,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        listTitle: String? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.listTitle = listTitle
        self.priority = priority
    }
}

/// Input payload for creating a reminder.
public struct ReminderDraft: Equatable, Sendable {
    public var title: String
    public var dueDate: Date?
    public var notes: String?

    public init(title: String, dueDate: Date? = nil, notes: String? = nil) {
        self.title = title
        self.dueDate = dueDate
        self.notes = notes
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum RemindersError: Error, Equatable, Sendable {
    case accessDenied
    case accessRestricted
    case unavailable
    case emptyTitle
    case noDefaultList
    case notFound
    case storeFailure(String)

    public var messageKey: String {
        switch self {
        case .accessDenied: return "Quyền Nhắc việc bị từ chối."
        case .accessRestricted: return "Quyền Nhắc việc bị giới hạn trên máy này."
        case .unavailable: return "Nhắc việc cần macOS 14 trở lên."
        case .emptyTitle: return "Nhập nội dung nhắc việc trước khi lưu."
        case .noDefaultList: return "Chưa có danh sách Nhắc việc mặc định trên máy."
        case .notFound: return "Không tìm thấy lời nhắc này."
        case .storeFailure: return "Không thể đồng bộ với Nhắc việc."
        }
    }
}

/// Pure EventKit store abstraction so unit tests exercise every permission, CRUD, and revocation path.
@MainActor
public protocol RemindersStoreProtocol: AnyObject {
    var isPlatformSupported: Bool { get }
    func authorizationStatus() -> RemindersAccessState
    func requestFullAccess() async -> RemindersAccessState
    func fetchReminders() async throws -> [ReminderItem]
    func createReminder(_ draft: ReminderDraft) async throws -> ReminderItem
    func setCompleted(id: String, completed: Bool) async throws -> ReminderItem
    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject?
    func stopObserving(_ token: AnyObject?)
}

/// Pure sorting, filtering, and overdue classification rules for Reminders.
public enum RemindersRules {
    public static func isOverdue(_ item: ReminderItem, now: Date) -> Bool {
        guard !item.isCompleted, let due = item.dueDate else { return false }
        return due < now
    }

    public static func filtered(
        _ items: [ReminderItem],
        by filter: RemindersFilter,
        now: Date,
        calendar: Calendar = .current
    ) -> [ReminderItem] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)

        let matched: [ReminderItem]
        switch filter {
        case .completed:
            matched = items.filter(\.isCompleted)
        case .all:
            matched = items.filter { !$0.isCompleted }
        case .today:
            matched = items.filter { item in
                guard !item.isCompleted, let due = item.dueDate else { return false }
                return due < startOfTomorrow
            }
        case .upcoming:
            matched = items.filter { item in
                guard !item.isCompleted, let due = item.dueDate else { return false }
                return due >= startOfTomorrow
            }
        }

        return matched.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?) where da != db:
                return da < db
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    public static func count(
        _ items: [ReminderItem],
        for filter: RemindersFilter,
        now: Date,
        calendar: Calendar = .current
    ) -> Int {
        filtered(items, by: filter, now: now, calendar: calendar).count
    }
}

/// ViewModel for the Dynamic Island Reminders tab.
/// Never requests EventKit permission implicitly — only `requestAccess()` triggers a system prompt.
@MainActor
public final class RemindersViewModel: ObservableObject {
    @Published public private(set) var accessState: RemindersAccessState = .notDetermined
    @Published public private(set) var items: [ReminderItem] = []
    @Published public var filter: RemindersFilter = .all
    @Published public private(set) var isLoading = false
    @Published public private(set) var isRequestingAccess = false
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var isCreating = false
    @Published public var draftTitle = ""
    @Published public var draftDuePreset: ReminderDuePreset = .today
    @Published public private(set) var errorMessageKey: String? = nil

    public var onComposerStateChanged: ((Bool) -> Void)?

    private let store: any RemindersStoreProtocol
    private let nowProvider: @Sendable () -> Date
    private var fetchTask: Task<Void, Never>?
    private var changeToken: AnyObject?
    private var loadGeneration: UInt64 = 0
    private var isOpen = false

    public init(
        store: any RemindersStoreProtocol,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.nowProvider = nowProvider
        self.accessState = store.isPlatformSupported ? store.authorizationStatus() : .unavailable
    }

    public var visibleItems: [ReminderItem] {
        RemindersRules.filtered(items, by: filter, now: nowProvider())
    }

    public var incompleteCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    /// Called when the Reminders tab opens. Checks authorization read-only and fetches only if already granted.
    public func onAppear() {
        isOpen = true
        errorMessageKey = nil
        recheckAuthorizationAndLoad(allowFetch: true)
    }

    /// Called when the Reminders tab closes or the Island dismisses. Cancels in-flight work and stops observing.
    public func close() {
        isOpen = false
        loadGeneration &+= 1
        fetchTask?.cancel()
        fetchTask = nil
        isLoading = false
        stopObserver()
        setCreating(false)
    }

    /// Explicit user action ("Cấp quyền Nhắc việc"). The ONLY path that prompts TCC.
    public func requestAccess() async {
        guard !isRequestingAccess else { return }
        guard store.isPlatformSupported else {
            accessState = .unavailable
            items = []
            errorMessageKey = RemindersError.unavailable.messageKey
            return
        }
        errorMessageKey = nil
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        let grantedState = await store.requestFullAccess()
        guard isOpen else { return }
        accessState = grantedState
        if grantedState == .authorized {
            startObserverIfNeeded()
            await refresh()
        } else {
            stopObserver()
            items = []
        }
    }

    public func openComposer() {
        guard accessState == .authorized else { return }
        errorMessageKey = nil
        setCreating(true)
    }

    public func closeComposer() {
        draftTitle = ""
        errorMessageKey = nil
        setCreating(false)
    }

    private func setCreating(_ open: Bool) {
        guard isCreating != open else { return }
        isCreating = open
        onComposerStateChanged?(open)
    }

    /// Re-checks live authorization (detecting mid-session revocation) and reloads reminders if authorized.
    public func refresh() async {
        guard !Task.isCancelled else { return }
        guard store.isPlatformSupported else {
            accessState = .unavailable
            items = []
            stopObserver()
            return
        }
        let current = store.authorizationStatus()
        accessState = current
        guard current == .authorized else {
            items = []
            isLoading = false
            stopObserver()
            return
        }

        startObserverIfNeeded()
        loadGeneration &+= 1
        let gen = loadGeneration
        isLoading = true
        errorMessageKey = nil

        do {
            let fetched = try await store.fetchReminders()
            guard !Task.isCancelled, gen == loadGeneration else { return }
            // Re-verify in case permission was revoked mid-fetch.
            let postStatus = store.authorizationStatus()
            accessState = postStatus
            guard postStatus == .authorized else {
                items = []
                isLoading = false
                stopObserver()
                return
            }
            items = fetched
            isLoading = false
        } catch let err as RemindersError {
            guard !Task.isCancelled, gen == loadGeneration else { return }
            isLoading = false
            handleStoreError(err)
        } catch {
            guard !Task.isCancelled, gen == loadGeneration else { return }
            isLoading = false
            errorMessageKey = RemindersError.storeFailure(error.localizedDescription).messageKey
        }
    }

    public func createReminder() async {
        guard store.isPlatformSupported else {
            accessState = .unavailable
            errorMessageKey = RemindersError.unavailable.messageKey
            return
        }
        let current = store.authorizationStatus()
        accessState = current
        guard current == .authorized else {
            items = []
            stopObserver()
            errorMessageKey = current == .restricted
                ? RemindersError.accessRestricted.messageKey
                : RemindersError.accessDenied.messageKey
            return
        }

        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessageKey = RemindersError.emptyTitle.messageKey
            return
        }

        isSubmitting = true
        errorMessageKey = nil
        let due = draftDuePreset.dueDate(now: nowProvider())
        let draft = ReminderDraft(title: trimmed, dueDate: due)
        do {
            let created = try await store.createReminder(draft)
            isSubmitting = false
            items.append(created)
            draftTitle = ""
            setCreating(false)
            if filter == .completed {
                filter = .all
            }
        } catch let err as RemindersError {
            isSubmitting = false
            handleStoreError(err)
        } catch {
            isSubmitting = false
            errorMessageKey = RemindersError.storeFailure(error.localizedDescription).messageKey
        }
    }

    public func toggleComplete(_ item: ReminderItem) async {
        guard store.isPlatformSupported else {
            accessState = .unavailable
            errorMessageKey = RemindersError.unavailable.messageKey
            return
        }
        let current = store.authorizationStatus()
        accessState = current
        guard current == .authorized else {
            items = []
            stopObserver()
            errorMessageKey = current == .restricted
                ? RemindersError.accessRestricted.messageKey
                : RemindersError.accessDenied.messageKey
            return
        }

        errorMessageKey = nil
        do {
            let updated = try await store.setCompleted(id: item.id, completed: !item.isCompleted)
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = updated
            } else {
                items.append(updated)
            }
        } catch let err as RemindersError {
            handleStoreError(err)
        } catch {
            errorMessageKey = RemindersError.storeFailure(error.localizedDescription).messageKey
        }
    }

    // MARK: - Helpers

    private func recheckAuthorizationAndLoad(allowFetch: Bool) {
        guard store.isPlatformSupported else {
            accessState = .unavailable
            items = []
            stopObserver()
            return
        }
        let status = store.authorizationStatus()
        accessState = status
        guard status == .authorized else {
            items = []
            stopObserver()
            return
        }
        startObserverIfNeeded()
        guard allowFetch else { return }
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            guard let self, self.isOpen, !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    private func startObserverIfNeeded() {
        guard changeToken == nil, isOpen else { return }
        changeToken = store.observeChanges { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isOpen else { return }
                await self.refresh()
            }
        }
    }

    private func stopObserver() {
        if let token = changeToken {
            store.stopObserving(token)
            changeToken = nil
        }
    }

    private func handleStoreError(_ err: RemindersError) {
        switch err {
        case .accessDenied:
            accessState = .denied
            items = []
            stopObserver()
        case .accessRestricted:
            accessState = .restricted
            items = []
            stopObserver()
        case .unavailable:
            accessState = .unavailable
            items = []
            stopObserver()
        default:
            break
        }
        errorMessageKey = err.messageKey
    }
}
