import XCTest
import Foundation

@MainActor
private final class MockRemindersStore: RemindersStoreProtocol {
    var isPlatformSupported: Bool = true
    var status: RemindersAccessState = .notDetermined
    var nextRequestResult: RemindersAccessState = .authorized
    var requestAccessCallCount = 0
    var onRequestAccess: (() -> Void)?
    var fetchCallCount = 0
    var observerCount = 0
    var items: [ReminderItem] = []
    var fetchError: Error? = nil
    var createError: Error? = nil
    var completeError: Error? = nil
    var fetchDelayNanos: UInt64 = 0
    private var nextID = 1
    private var changeHandlers: [UUID: @MainActor () -> Void] = [:]

    func authorizationStatus() -> RemindersAccessState {
        isPlatformSupported ? status : .unavailable
    }

    func requestFullAccess() async -> RemindersAccessState {
        requestAccessCallCount += 1
        onRequestAccess?()
        guard isPlatformSupported else { return .unavailable }
        status = nextRequestResult
        return status
    }

    func fetchReminders() async throws -> [ReminderItem] {
        fetchCallCount += 1
        if fetchDelayNanos > 0 {
            try? await Task.sleep(nanoseconds: fetchDelayNanos)
        }
        if let fetchError { throw fetchError }
        return items
    }

    func createReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
        if let createError { throw createError }
        let trimmed = draft.trimmedTitle
        guard !trimmed.isEmpty else { throw RemindersError.emptyTitle }
        let created = ReminderItem(
            id: "mock-\(nextID)",
            title: trimmed,
            notes: draft.notes,
            dueDate: draft.dueDate,
            isCompleted: false,
            listTitle: "Reminders"
        )
        nextID += 1
        items.append(created)
        return created
    }

    func setCompleted(id: String, completed: Bool) async throws -> ReminderItem {
        if let completeError { throw completeError }
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            throw RemindersError.notFound
        }
        items[idx].isCompleted = completed
        return items[idx]
    }

    func observeChanges(_ handler: @escaping @MainActor () -> Void) -> AnyObject? {
        let id = UUID()
        changeHandlers[id] = handler
        observerCount = changeHandlers.count
        return id as NSUUID
    }

    func stopObserving(_ token: AnyObject?) {
        guard let ns = token as? NSUUID else { return }
        changeHandlers.removeValue(forKey: ns as UUID)
        observerCount = changeHandlers.count
    }

    func fireStoreChanged() {
        for handler in changeHandlers.values {
            handler()
        }
    }
}

final class RemindersDomainTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_795_600_000)

    @MainActor
    func testClosingDuringPermissionRequestDoesNotStartFetching() async {
        let store = MockRemindersStore()
        let viewModel = RemindersViewModel(store: store)
        viewModel.onAppear()
        store.onRequestAccess = { [weak viewModel] in
            XCTAssertEqual(viewModel?.isRequestingAccess, true)
            viewModel?.close()
        }

        await viewModel.requestAccess()

        XCTAssertFalse(viewModel.isRequestingAccess)
        XCTAssertEqual(store.fetchCallCount, 0)
        XCTAssertEqual(store.observerCount, 0)
    }

    @MainActor
    func testPermissionIsNeverRequestedImplicitlyOnInitOrAppear() async {
        let store = MockRemindersStore()
        store.status = .notDetermined

        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        XCTAssertEqual(vm.accessState, .notDetermined)
        XCTAssertEqual(store.requestAccessCallCount, 0)

        vm.onAppear()
        await vm.refresh()
        XCTAssertEqual(store.requestAccessCallCount, 0, "onAppear/refresh must never prompt TCC")
        XCTAssertEqual(store.fetchCallCount, 0)
        XCTAssertEqual(store.observerCount, 0)
        XCTAssertTrue(vm.items.isEmpty)
    }

    @MainActor
    func testExplicitRequestAccessGrantsFetchesAndObserves() async {
        let store = MockRemindersStore()
        store.status = .notDetermined
        store.nextRequestResult = .authorized
        store.items = [
            ReminderItem(id: "r1", title: "Buy milk", dueDate: fixedNow.addingTimeInterval(3600), isCompleted: false)
        ]

        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        vm.onAppear()
        await vm.requestAccess()

        XCTAssertEqual(store.requestAccessCallCount, 1)
        XCTAssertEqual(vm.accessState, .authorized)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.title, "Buy milk")
        XCTAssertEqual(store.observerCount, 1)

        vm.close()
        XCTAssertEqual(store.observerCount, 0, "closing tab must stop observing EventKit")
    }

    @MainActor
    func testDenialRestrictedAndMidSessionRevocationClearItemsAndBlockMutations() async {
        let store = MockRemindersStore()
        store.status = .authorized
        store.items = [
            ReminderItem(id: "r1", title: "Send report", dueDate: fixedNow, isCompleted: false)
        ]

        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        vm.onAppear()
        await vm.refresh()
        XCTAssertEqual(vm.items.count, 1)

        // Revoke permission mid-session -> refresh clears stale reminders immediately
        store.status = .denied
        await vm.refresh()
        XCTAssertEqual(vm.accessState, .denied)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(store.observerCount, 0)

        // Attempt to create while revoked -> blocked cleanly
        vm.draftTitle = "Should not save"
        await vm.createReminder()
        XCTAssertEqual(vm.errorMessageKey, RemindersError.accessDenied.messageKey)
        XCTAssertEqual(store.items.count, 1)

        // Restricted state
        store.status = .restricted
        await vm.toggleComplete(ReminderItem(id: "r1", title: "Send report"))
        XCTAssertEqual(vm.accessState, .restricted)
        XCTAssertEqual(vm.errorMessageKey, RemindersError.accessRestricted.messageKey)
    }

    @MainActor
    func testMacOS14UnavailablePlatformNeverPrompts() async {
        let store = MockRemindersStore()
        store.isPlatformSupported = false
        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        XCTAssertEqual(vm.accessState, .unavailable)

        vm.onAppear()
        await vm.requestAccess()
        XCTAssertEqual(store.requestAccessCallCount, 0)
        XCTAssertEqual(vm.accessState, .unavailable)
        XCTAssertEqual(vm.errorMessageKey, RemindersError.unavailable.messageKey)
    }

    @MainActor
    func testCreateCompleteFilterAndValidation() async {
        let store = MockRemindersStore()
        store.status = .authorized
        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        var composerEvents: [Bool] = []
        vm.onComposerStateChanged = { composerEvents.append($0) }

        vm.onAppear()
        vm.openComposer()
        XCTAssertTrue(vm.isCreating)
        XCTAssertEqual(composerEvents, [true])

        // Empty / whitespace title rejected
        vm.draftTitle = "   \n  "
        await vm.createReminder()
        XCTAssertEqual(vm.errorMessageKey, RemindersError.emptyTitle.messageKey)
        XCTAssertTrue(vm.items.isEmpty)

        // Valid create
        vm.draftTitle = "  Review PR  "
        vm.draftDuePreset = .today
        await vm.createReminder()
        XCTAssertNil(vm.errorMessageKey)
        XCTAssertFalse(vm.isCreating)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items[0].title, "Review PR")
        XCTAssertNotNil(vm.items[0].dueDate)

        // Complete moves item out of .all into .completed
        await vm.toggleComplete(vm.items[0])
        XCTAssertTrue(vm.items[0].isCompleted)
        vm.filter = .all
        XCTAssertTrue(vm.visibleItems.isEmpty)
        vm.filter = .completed
        XCTAssertEqual(vm.visibleItems.count, 1)

        // Uncomplete moves it back
        await vm.toggleComplete(vm.items[0])
        XCTAssertFalse(vm.items[0].isCompleted)
        vm.filter = .all
        XCTAssertEqual(vm.visibleItems.count, 1)
    }

    @MainActor
    func testNoDefaultListErrorIsSurfacedHonesty() async {
        let store = MockRemindersStore()
        store.status = .authorized
        store.createError = RemindersError.noDefaultList

        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        vm.draftTitle = "Check mail"
        await vm.createReminder()
        XCTAssertEqual(vm.errorMessageKey, RemindersError.noDefaultList.messageKey)
    }

    @MainActor
    func testCloseCancelsInFlightFetchAndIgnoresLateResults() async {
        let store = MockRemindersStore()
        store.status = .authorized
        store.fetchDelayNanos = 80_000_000
        store.items = [ReminderItem(id: "late", title: "Late item")]

        let vm = RemindersViewModel(store: store, nowProvider: { [fixedNow] in fixedNow })
        vm.onAppear()
        vm.close()
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertTrue(vm.items.isEmpty, "late result after close must be ignored")
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Unified catalog & routing registration

    func testRemindersRegisteredInUnifiedCatalogAndRouting() {
        let state = NotchDestinationCatalog.defaultState
        XCTAssertTrue(state.isEnabled(.reminders))
        XCTAssertEqual(NotchDestinationID.reminders.extraModule, .reminders)
        XCTAssertEqual(NotchDestinationID.reminders.destination, .extra(.reminders))
        XCTAssertEqual(NotchDestinationID.reminders.titleKey, "Nhắc việc")
        XCTAssertEqual(NotchDestinationID.reminders.symbol, "checklist")

        // Unique shortcuts & digits across every NotchDestinationID
        let allIDs = NotchDestinationID.allCases
        let shortcuts = allIDs.map(\.shortcutKey).filter { !$0.isEmpty }
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
        let digitKeys = allIDs.map(\.digitKey).filter { !$0.isEmpty }
        XCTAssertEqual(Set(digitKeys).count, digitKeys.count)

        // Deep link resolution respects visibility
        let resolved = NotchDestinationCatalog.resolveDeepLink(
            pageParam: "reminders",
            catalog: state,
            availability: .builtInOnly
        )
        XCTAssertEqual(resolved, .reminders)

        let hidden = state.setting(.reminders, enabled: false)
        let fallback = NotchDestinationCatalog.resolveDeepLink(
            pageParam: "reminders",
            catalog: hidden,
            availability: .builtInOnly
        )
        XCTAssertNotEqual(fallback, .reminders)
    }

    // MARK: - Calendar Month Grid (GlanceRules)

    func testCalendarMonthGridCoversAllDaysAlignedToSevenColumns() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2 // Monday
        let nov2026 = cal.date(from: DateComponents(year: 2026, month: 11, day: 15))!

        let grid = GlanceRules.monthGrid(for: nov2026, calendar: cal)
        XCTAssertEqual(grid.count % 7, 0)
        let inMonth = grid.filter(\.inMonth)
        XCTAssertEqual(inMonth.count, 30, "November has 30 days")
        XCTAssertEqual(cal.component(.day, from: inMonth.first!.date), 1)
        XCTAssertEqual(cal.component(.day, from: inMonth.last!.date), 30)
        // First cell in grid must start on calendar.firstWeekday
        XCTAssertEqual(cal.component(.weekday, from: grid.first!.date), cal.firstWeekday)
    }
}
