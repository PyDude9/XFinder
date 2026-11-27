import Foundation
import Combine

/// MainActor View Model for Dynamic Island Weather (Phase 2).
/// Encapsulates coordinator interactions, debounced search, immediate loading feedback,
/// and reactive state synchronization.
@MainActor
public final class WeatherViewModel: ObservableObject {
    @Published public private(set) var state: WeatherUIState = .unselected
    @Published public var searchText: String = ""
    @Published public private(set) var searchResults: [WeatherLocation] = []
    /// Why the last search failed, or `nil` when it returned rows or genuinely matched nothing.
    /// Mirrors `WeatherCoordinator.searchError`; the page uses it to tell "no such city" from "lookup failed".
    @Published public private(set) var searchError: WeatherError?
    @Published public private(set) var isSearching: Bool = false
    @Published public var isShowingSearch: Bool = false

    /// Optional host callback fired when search visibility changes (e.g. so a non-activating Notch panel can acquire key focus).
    public var onSearchVisibilityChanged: ((Bool) -> Void)?

    public let coordinator: WeatherCoordinator
    private var activeSelectTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    /// Monotonic token per keystroke/retry, so the coordinator can tell a stale cancel from a live search.
    private var searchIntentCounter: Int = 0
    private var reopenTask: Task<Void, Never>?
    private var locationTask: Task<Void, Never>?

    public init(coordinator: WeatherCoordinator) {
        self.coordinator = coordinator
        Task { [weak self] in
            guard let self = self else { return }
            let initial = await self.coordinator.state
            self.state = initial

            await self.coordinator.setStateChangeHandler { [weak self] newState in
                Task { @MainActor [weak self] in
                    self?.state = newState
                }
            }
        }
    }

    /// Syncs state from coordinator.
    public func syncState() async {
        let currentState = await coordinator.state
        self.state = currentState
    }

    /// Selects a new location.
    /// Immediately clears prior forecast and sets state to loading on the MainActor,
    /// ensuring no stale data flickers on screen before the fetch begins.
    public func selectLocation(_ location: WeatherLocation) {
        if isShowingSearch {
            isShowingSearch = false
            onSearchVisibilityChanged?(false)
        }
        searchText = ""
        searchResults = []
        searchError = nil

        // Synchronously clear old city forecast immediately on MainActor
        self.state = .loadingInitial(location)

        reopenTask?.cancel()
        reopenTask = nil
        locationTask?.cancel()
        locationTask = nil
        activeSelectTask?.cancel()
        activeSelectTask = Task { [weak self] in
            guard let self = self else { return }
            await self.coordinator.selectLocation(location, triggerFetch: true)
            guard !Task.isCancelled else { return }
            await self.syncState()
        }
    }

    /// Deliberate user refresh action.
    /// Immediately sets state to refreshing if existing snapshot is present.
    public func refresh() {
        switch state {
        case .loaded(let snapshot, _), .offlineWithStale(let snapshot, _),
             .failedWithStale(let snapshot, _, _):
            self.state = .refreshing(snapshot)
        default:
            break
        }

        Task { [weak self] in
            guard let self = self else { return }
            await self.coordinator.refresh()
            await self.syncState()
        }
    }

    /// Deliberate user action to request device location.
    public func requestCurrentLocation() {
        if isShowingSearch {
            isShowingSearch = false
            onSearchVisibilityChanged?(false)
        }
        searchText = ""
        searchResults = []
        searchError = nil
        isSearching = false
        searchTask?.cancel()
        searchTask = nil

        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self = self else { return }
            await self.coordinator.requestCurrentLocation()
            guard !Task.isCancelled else { return }
            await self.syncState()
        }
    }

    /// Search text changed with 300ms debounce.
    public func onSearchTextChanged(_ query: String) {
        searchTask?.cancel()
        // One token per keystroke, monotonic. Deleting the query and typing a new one are two hops to the
        // coordinator from two tasks, so without it the cancel could arrive after the new search and
        // tear down a query the person is actually looking at.
        searchIntentCounter += 1
        let intent = searchIntentCounter
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            searchResults = []
            searchError = nil
            isSearching = false
            // Cancelling only `searchTask` above stops the debounce, not the request: the coordinator
            // already handed the query to the provider and nothing else would cancel it, so it ran to
            // completion for a field that no longer has text in it.
            Task { [weak self] in
                await self?.coordinator.cancelSearch(intent: intent)
            }
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled, let self = self else { return }
            await self.coordinator.search(query: trimmed, intent: intent)
            let results = await self.coordinator.searchResults
            let searching = await self.coordinator.isSearching
            let failure = await self.coordinator.searchError
            if !Task.isCancelled {
                self.searchResults = results
                self.isSearching = searching
                // A failed lookup must not wear the "no cities found" face.
                self.searchError = failure
            }
        }
    }

    /// Explicit retry of a failed city search: re-runs the query on screen with no debounce.
    ///
    /// The page used to call `onSearchTextChanged` from its Retry button, which went back through the
    /// 300 ms debounce — a press that visibly does nothing for a third of a second. A press is not typing,
    /// so it goes straight to the coordinator.
    public func retrySearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        searchTask?.cancel()
        searchIntentCounter += 1
        let intent = searchIntentCounter
        isSearching = true
        searchError = nil
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            await self.coordinator.search(query: trimmed, intent: intent)
            let results = await self.coordinator.searchResults
            let searching = await self.coordinator.isSearching
            let failure = await self.coordinator.searchError
            if !Task.isCancelled {
                self.searchResults = results
                self.isSearching = searching
                self.searchError = failure
            }
        }
    }

    public func openSearch() {
        guard !isShowingSearch else { return }
        isShowingSearch = true
        onSearchVisibilityChanged?(true)
    }

    public func closeSearch() {
        guard isShowingSearch else { return }
        isShowingSearch = false
        searchText = ""
        searchResults = []
        searchError = nil
        isSearching = false
        searchTask?.cancel()
        searchTask = nil
        onSearchVisibilityChanged?(false)
        Task { [weak self] in
            await self?.coordinator.cancelSearch()
        }
    }

    public func toggleSearch() {
        if isShowingSearch {
            closeSearch()
        } else {
            openSearch()
        }
    }

    /// Lifecycle hook called when the Weather view appears on screen.
    /// Re-evaluates TTL on the active location and refreshes while keeping cached forecast if stale.
    public func onAppear() {
        reopenTask?.cancel()
        reopenTask = Task { [weak self] in
            guard let self = self else { return }
            await self.coordinator.reopen()
            guard !Task.isCancelled else { return }
            await self.syncState()
        }
    }

    /// Lifecycle hook called when the view disappears or Dynamic Island collapses.
    /// Cancels in-flight UI-bound tasks immediately.
    public func close() {
        reopenTask?.cancel()
        reopenTask = nil
        locationTask?.cancel()
        locationTask = nil
        activeSelectTask?.cancel()
        activeSelectTask = nil
        searchTask?.cancel()
        searchTask = nil
        if isShowingSearch {
            isShowingSearch = false
            onSearchVisibilityChanged?(false)
        }
        isSearching = false
        searchResults = []
        searchError = nil
        // Hand the coordinator this keystroke's high-water mark so it fences exactly the searches that are
        // already dead — an old intent value here would be a permanent kill switch for all later typing.
        let intent = searchIntentCounter
        Task { [weak self] in
            await self?.coordinator.close(searchIntent: intent)
        }
    }

    /// Localized data age and status description.
    public var freshnessDescription: String {
        switch state {
        case .loaded(_, let freshness):
            switch freshness {
            case .fresh:
                return L10n.t("Vừa xong")
            case .stale(let age):
                let mins = max(1, Int(age / 60))
                if mins < 60 {
                    return "\(L10n.t("Cập nhật "))\(mins)\(L10n.t(" phút trước"))"
                } else {
                    let hrs = mins / 60
                    return "\(L10n.t("Cập nhật "))\(hrs)\(L10n.t(" giờ trước"))"
                }
            case .expired:
                return L10n.t("Ngoại tuyến")
            }
        case .offlineWithStale(_, let age):
            let mins = max(1, Int(age / 60))
            if mins < 60 {
                return "\(L10n.t("Ngoại tuyến")) · \(L10n.t("Cập nhật "))\(mins)\(L10n.t(" phút trước"))"
            } else {
                let hrs = mins / 60
                return "\(L10n.t("Ngoại tuyến")) · \(L10n.t("Cập nhật "))\(hrs)\(L10n.t(" giờ trước"))"
            }
        case .failedWithStale(_, let age, _):
            // Deliberately NOT "Ngoại tuyến": the network is up; the request failed for another reason
            // (timeout, quota, backend). The row above the forecast already names the group.
            let mins = max(1, Int(age / 60))
            if mins < 60 {
                return "\(L10n.t("Cập nhật "))\(mins)\(L10n.t(" phút trước"))"
            } else {
                let hrs = mins / 60
                return "\(L10n.t("Cập nhật "))\(hrs)\(L10n.t(" giờ trước"))"
            }
        case .refreshing:
            return L10n.t("Đang tải dự báo thời tiết...")
        default:
            return ""
        }
    }
}
