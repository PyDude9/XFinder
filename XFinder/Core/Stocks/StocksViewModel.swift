import Foundation
import Combine

@MainActor
public final class StocksViewModel: ObservableObject {
    @Published public private(set) var state: StocksUIState = .unconfigured
    @Published public private(set) var watchlist: [StockAssetDescriptor] = []
    @Published public var selectedAssetId: String? = nil
    @Published public var selectedRange: StockChartRange = .oneDay
    @Published public var searchText: String = ""
    @Published public private(set) var searchResults: [StockAssetDescriptor] = []
    @Published public private(set) var searchError: StocksError? = nil
    @Published public private(set) var isSearching: Bool = false
    @Published public var isShowingSearch: Bool = false

    public var onSearchVisibilityChanged: ((Bool) -> Void)?
    public var onOpenSettingsRequested: (() -> Void)?

    public let coordinator: StocksCoordinator
    private let clock: @Sendable () -> Date
    private var openTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchIntentCounter: Int = 0

    public init(coordinator: StocksCoordinator, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.coordinator = coordinator
        self.clock = clock
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.setStateChangeHandler { [weak self] newState in
                Task { @MainActor [weak self] in
                    await self?.applyCoordinatorState(newState)
                }
            }
            await self.syncState()
        }
    }

    public func syncState() async {
        let s = await coordinator.state
        await applyCoordinatorState(s)
        self.searchResults = await coordinator.searchResults
        self.searchError = await coordinator.searchError
        self.isSearching = await coordinator.isSearching
    }

    private func applyCoordinatorState(_ newState: StocksUIState) async {
        self.state = newState
        let wl = await coordinator.watchlist
        self.watchlist = wl
        if wl.isEmpty {
            self.selectedAssetId = nil
        } else if let sel = selectedAssetId, wl.contains(where: { $0.id == sel }) {
            // keep active selection
        } else {
            self.selectedAssetId = wl.first?.id
        }
        if let quote = selectedQuote, !quote.supportedRanges.isEmpty,
           !quote.supportedRanges.contains(selectedRange) {
            self.selectedRange = quote.supportedRanges[0]
        }
    }

    public func onAppear() {
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.openPage()
            await self.syncState()
        }
    }

    public func close() {
        openTask?.cancel()
        openTask = nil
        searchTask?.cancel()
        searchTask = nil
        isShowingSearch = false
        onSearchVisibilityChanged?(false)
        searchIntentCounter += 1
        let closeIntent = searchIntentCounter
        Task { await coordinator.close(searchIntent: closeIntent) }
    }

    public func refresh() {
        openTask?.cancel()
        openTask = Task { [weak self] in
            guard let self else { return }
            await self.coordinator.refresh(force: true)
            await self.syncState()
        }
    }

    public func openSearch() {
        isShowingSearch = true
        searchText = ""
        searchResults = []
        searchError = nil
        onSearchVisibilityChanged?(true)
    }

    public func closeSearch() {
        searchTask?.cancel()
        isShowingSearch = false
        onSearchVisibilityChanged?(false)
        searchText = ""
        searchResults = []
        searchError = nil
        searchIntentCounter += 1
        let intent = searchIntentCounter
        Task { await coordinator.cancelSearch(intent: intent) }
    }

    public func onSearchTextChanged(_ query: String) {
        searchText = query
        searchTask?.cancel()
        searchIntentCounter += 1
        let intent = searchIntentCounter
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            isSearching = false
            Task { await coordinator.cancelSearch(intent: intent) }
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self else { return }
            await self.coordinator.search(query: trimmed, intent: intent)
            guard !Task.isCancelled else { return }
            self.searchResults = await self.coordinator.searchResults
            self.searchError = await self.coordinator.searchError
            self.isSearching = await self.coordinator.isSearching
        }
    }

    public func addAsset(_ asset: StockAssetDescriptor) {
        selectedAssetId = asset.id
        closeSearch()
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.addAsset(asset)
            await self.syncState()
        }
    }

    public func removeAsset(id: String) {
        if selectedAssetId == id {
            selectedAssetId = watchlist.first(where: { $0.id != id })?.id
        }
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.removeAsset(id: id)
            await self.syncState()
        }
    }

    public func moveAsset(id: String, delta: Int) {
        guard let idx = watchlist.firstIndex(where: { $0.id == id }) else { return }
        let target = idx + delta
        guard watchlist.indices.contains(target) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.coordinator.moveAsset(fromIndex: idx, toIndex: target)
            await self.syncState()
        }
    }

    public func rowState(for id: String) -> StocksRowState? {
        if case .ready(let rows, _, _, _) = state {
            return rows[id]
        }
        return nil
    }

    public var selectedAsset: StockAssetDescriptor? {
        guard let selectedAssetId else { return watchlist.first }
        return watchlist.first(where: { $0.id == selectedAssetId }) ?? watchlist.first
    }

    public var selectedRowState: StocksRowState? {
        guard let id = selectedAsset?.id else { return nil }
        return rowState(for: id)
    }

    public var selectedQuote: StockQuote? {
        selectedRowState?.quote
    }

    public var availableRanges: [StockChartRange] {
        if let ranges = selectedQuote?.supportedRanges, !ranges.isEmpty {
            return ranges
        }
        return coordinator.supportedRanges
    }

    public var isRefreshing: Bool {
        switch state {
        case .loadingInitial: return true
        case .ready(_, let refreshing, _, _): return refreshing
        default: return false
        }
    }

    public var freshnessDescription: String {
        let updated: Date? = {
            if let q = selectedQuote { return q.fetchedAt }
            if case .ready(_, _, _, let last) = state { return last }
            return nil
        }()
        guard let updated else { return "" }
        let now = clock()
        let age = max(0, now.timeIntervalSince(updated))
        if age < 60 { return L10n.t("Vừa xong") }
        let mins = max(1, Int(age / 60))
        if mins < 60 {
            return "\(L10n.t("Cập nhật "))\(mins)\(L10n.t(" phút trước"))"
        }
        return "\(L10n.t("Cập nhật "))\(mins / 60)\(L10n.t(" giờ trước"))"
    }

    public func sessionBadgeText(for quote: StockQuote) -> String {
        let fresh = quote.effectiveFreshness(at: clock())
        if case .expired = fresh {
            return L10n.t("Hết hạn cache")
        }
        if case .stale = fresh {
            return L10n.t("Dữ liệu cũ")
        }
        switch quote.sessionState {
        case .open:
            if case .delayed(let m) = fresh {
                return "\(L10n.t("Trễ "))\(m)\(L10n.t(" phút"))"
            }
            return L10n.t("Đang mở")
        case .closed:
            return "\(L10n.t("Đóng cửa")) · \(quote.formattedQuoteTime())"
        case .preMarket:
            return L10n.t("Trước phiên")
        case .afterHours:
            return L10n.t("Sau phiên")
        case .continuous24x7:
            if case .delayed(let m) = fresh {
                return "24/7 · \(L10n.t("Trễ "))\(m)\(L10n.t(" phút"))"
            }
            return "24/7 · \(quote.formattedQuoteTime())"
        case .unknown:
            return L10n.t("Chưa rõ phiên")
        }
    }

    public func changeBasisText(for quote: StockQuote) -> String {
        L10n.t(quote.changeBasis.labelKey)
    }

    public func sourceDisplayName(for quote: StockQuote) -> String {
        quote.sourceName ?? coordinator.attribution.serviceName
    }
}
