import os
import Foundation

public enum StocksError: Error, Equatable, Sendable {
    case networkUnavailable
    case rateLimited
    case timeout
    case invalidData
    case accessRequired
    case symbolNotFound(String)
    case unsupportedRange
    case cancelled
    case unknown(String)

    public var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .rateLimited, .timeout:
            return true
        case .invalidData, .accessRequired, .symbolNotFound, .unsupportedRange, .cancelled, .unknown:
            return false
        }
    }
}

public struct StocksErrorPresentation: Equatable, Sendable {
    public enum Context: Sendable {
        case quote
        case search
    }

    public let titleKey: String
    public let hintKey: String?
    public let symbolName: String
    public let canRetry: Bool

    public init(for error: StocksError, context: Context = .quote, isDemoAccess: Bool = false) {
        self.canRetry = error.isRetryable
        switch error {
        case .networkUnavailable:
            self.titleKey = "Không có kết nối mạng"
            self.hintKey = context == .search
                ? "Kiểm tra kết nối rồi thử tìm lại."
                : "Hiển thị giá đã lưu gần nhất nếu có."
            self.symbolName = "wifi.slash"
        case .rateLimited:
            self.titleKey = "Tạm hết lượt tải giá chứng khoán"
            self.hintKey = "Thử lại sau ít phút."
            self.symbolName = "hourglass"
        case .timeout:
            self.titleKey = "Hết thời gian chờ nguồn giá"
            self.hintKey = context == .search
                ? "Thử tìm lại mã."
                : "Thử lại bằng nút Làm mới."
            self.symbolName = "clock.badge.exclamationmark"
        case .symbolNotFound:
            self.titleKey = "Không tìm thấy mã chứng khoán"
            self.hintKey = nil
            self.symbolName = "magnifyingglass"
        case .accessRequired:
            if isDemoAccess {
                self.titleKey = "Cần khóa API (chế độ demo)"
                self.hintKey = "Chế độ demo chỉ hỗ trợ AAPL & BTC/USD — thêm khóa API miễn phí trong Cài đặt."
            } else {
                self.titleKey = "Cần quyền truy cập nguồn giá"
                self.hintKey = "Kiểm tra khóa API hoặc gói tài khoản trong Cài đặt nguồn giá."
            }
            self.symbolName = "key"
        case .unsupportedRange:
            self.titleKey = "Kỳ biểu đồ không được nguồn hỗ trợ"
            self.hintKey = nil
            self.symbolName = "chart.xyaxis.line"
        case .invalidData, .cancelled, .unknown:
            self.titleKey = "Dữ liệu giá chứng khoán không đọc được"
            self.hintKey = context == .search ? nil : "Thử lại bằng nút Làm mới."
            self.symbolName = "exclamationmark.triangle.fill"
        }
    }
}

public struct StocksBatchResult: Equatable, Sendable {
    public let quotes: [String: StockQuote]
    public let errorsByAssetId: [String: StocksError]

    public init(quotes: [String: StockQuote], errorsByAssetId: [String: StocksError] = [:]) {
        self.quotes = quotes
        self.errorsByAssetId = errorsByAssetId
    }
}

public protocol StocksProvider: Sendable {
    var id: String { get }
    var attribution: StocksProviderAttribution { get }
    var supportedRanges: [StockChartRange] { get }
    var isDemoAccess: Bool { get }
    func searchSymbols(query: String) async throws -> [StockAssetDescriptor]
    func fetchQuotes(for assets: [StockAssetDescriptor]) async throws -> StocksBatchResult
}

public extension StocksProvider {
    var isDemoAccess: Bool { false }
}

public protocol StocksWatchlistStore: Sendable {
    func loadWatchlist() -> [StockAssetDescriptor]
    func saveWatchlist(_ assets: [StockAssetDescriptor])
    func clear()
}

public final class InMemoryStocksWatchlistStore: StocksWatchlistStore, @unchecked Sendable {
    private let lock = NSLock()
    private var assets: [StockAssetDescriptor]
    private var hasSavedConfiguration: Bool

    public init(initial: [StockAssetDescriptor] = []) {
        self.assets = initial
        self.hasSavedConfiguration = true
    }

    public init(seededIfUnconfigured: Bool) {
        self.assets = seededIfUnconfigured ? StocksWatchlistCatalog.defaultWatchlist : []
        self.hasSavedConfiguration = false
    }

    public func loadWatchlist() -> [StockAssetDescriptor] {
        lock.lock(); defer { lock.unlock() }
        return assets
    }

    public func saveWatchlist(_ assets: [StockAssetDescriptor]) {
        lock.lock(); defer { lock.unlock() }
        self.assets = assets
        self.hasSavedConfiguration = true
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        self.assets = []
        self.hasSavedConfiguration = true
    }
}

/// Persists the user's Stocks/Crypto watchlist in `UserDefaults`.
/// Seeds `StocksWatchlistCatalog.defaultWatchlist` ONLY when the key has never been saved;
/// existing custom lists and a deliberately emptied `[]` list are preserved verbatim.
public final class UserDefaultsStocksWatchlistStore: StocksWatchlistStore {
    private let defaults: OSAllocatedUnfairLock<UserDefaults>
    private let key: String
    private let defaultSeed: [StockAssetDescriptor]

    public init(
        defaults: UserDefaults = .standard,
        key: String = "xfinder.stocks.watchlist",
        defaultSeed: [StockAssetDescriptor] = StocksWatchlistCatalog.defaultWatchlist
    ) {
        self.defaults = OSAllocatedUnfairLock(uncheckedState: defaults)
        self.key = key
        self.defaultSeed = defaultSeed
    }

    public var hasSavedConfiguration: Bool {
        defaults.withLockUnchecked { $0.object(forKey: key) != nil }
    }

    public func loadWatchlist() -> [StockAssetDescriptor] {
        guard hasSavedConfiguration else {
            return defaultSeed
        }
        guard let data = defaults.withLockUnchecked({ $0.data(forKey: key) }),
              let decoded = try? JSONDecoder().decode([StockAssetDescriptor].self, from: data) else {
            return []
        }
        return decoded
    }

    public func saveWatchlist(_ assets: [StockAssetDescriptor]) {
        guard let data = try? JSONEncoder().encode(assets) else { return }
        defaults.withLockUnchecked { $0.set(data, forKey: key) }
    }

    public func resetToDefaults() {
        saveWatchlist(defaultSeed)
    }

    public func clear() {
        saveWatchlist([])
    }
}

public actor StocksCacheStore {
    private var quotesByProvider: [String: [String: StockQuote]] = [:]

    public init() {}

    public func quote(assetId: String, providerId: String) -> StockQuote? {
        quotesByProvider[providerId]?[assetId]
    }

    public func store(_ quote: StockQuote, providerId: String) {
        quotesByProvider[providerId, default: [:]][quote.asset.id] = quote
    }

    public func clear(providerId: String? = nil) {
        if let providerId {
            quotesByProvider.removeValue(forKey: providerId)
        } else {
            quotesByProvider.removeAll()
        }
    }
}

public actor StocksCoordinator {
    private let provider: StocksProvider
    private let watchlistStore: StocksWatchlistStore
    private let cache: StocksCacheStore
    private let clock: @Sendable () -> Date

    public private(set) var watchlist: [StockAssetDescriptor]
    public private(set) var state: StocksUIState
    public private(set) var searchResults: [StockAssetDescriptor] = []
    public private(set) var searchError: StocksError? = nil
    public private(set) var isSearching: Bool = false

    private var activeGeneration: Int = 0
    private var watchlistVersion: Int = 0
    private var refreshToken: UInt64 = 0
    private var isOpen: Bool = false
    private var isConfigured: Bool
    private var inFlightRefresh: Task<Void, Never>?
    private var inFlightSearch: Task<Void, Never>?
    private var searchGeneration: Int = 0
    private var latestSearchIntent: Int = 0
    private var searchIntentFence: Int = 0

    public nonisolated let attribution: StocksProviderAttribution
    public nonisolated let supportedRanges: [StockChartRange]
    public nonisolated let isDemoAccess: Bool

    private var onStateChange: (@Sendable (StocksUIState) -> Void)?

    public init(
        provider: StocksProvider,
        watchlistStore: StocksWatchlistStore = UserDefaultsStocksWatchlistStore(),
        cache: StocksCacheStore = StocksCacheStore(),
        isConfigured: Bool = true,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.watchlistStore = watchlistStore
        self.cache = cache
        self.isConfigured = isConfigured
        self.clock = clock
        self.attribution = provider.attribution
        self.supportedRanges = provider.supportedRanges
        self.isDemoAccess = provider.isDemoAccess
        let loaded = watchlistStore.loadWatchlist()
        self.watchlist = loaded
        if !isConfigured {
            self.state = .unconfigured
        } else if loaded.isEmpty {
            self.state = .empty
        } else {
            self.state = .loadingInitial(watchlist: loaded)
        }
    }

    public func setStateChangeHandler(_ handler: (@Sendable (StocksUIState) -> Void)?) {
        self.onStateChange = handler
    }

    private func updateState(_ next: StocksUIState) {
        self.state = next
        onStateChange?(next)
    }

    public func setConfigured(_ configured: Bool) {
        isConfigured = configured
        if !configured {
            cancelWork()
            updateState(.unconfigured)
        } else {
            refreshStateFromCacheOrTrigger(fetchIfOpen: isOpen)
        }
    }

    public func openPage() async {
        isOpen = true
        activeGeneration += 1
        guard isConfigured else {
            updateState(.unconfigured)
            return
        }
        guard !watchlist.isEmpty else {
            updateState(.empty)
            return
        }
        await refresh()
    }

    public func close(searchIntent: Int = 0) {
        isOpen = false
        activeGeneration += 1
        refreshToken += 1
        cancelWork()
        searchIntentFence = max(searchIntentFence, searchIntent)
        searchGeneration += 1
        isSearching = false
        searchResults = []
        searchError = nil
    }

    public func addAsset(_ asset: StockAssetDescriptor) async {
        guard !watchlist.contains(where: { $0.id == asset.id }) else { return }
        watchlist.append(asset)
        watchlistStore.saveWatchlist(watchlist)
        watchlistVersion += 1
        isConfigured = true
        await refresh(force: true)
    }

    public func removeAsset(id: String) async {
        guard watchlist.contains(where: { $0.id == id }) else { return }
        watchlist.removeAll { $0.id == id }
        watchlistStore.saveWatchlist(watchlist)
        watchlistVersion += 1
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        await rebuildFromCache()
    }

    public func moveAsset(fromIndex: Int, toIndex: Int) async {
        guard fromIndex != toIndex,
              watchlist.indices.contains(fromIndex),
              toIndex >= 0 && toIndex < watchlist.count else { return }
        let item = watchlist.remove(at: fromIndex)
        watchlist.insert(item, at: toIndex)
        watchlistStore.saveWatchlist(watchlist)
        watchlistVersion += 1
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        await rebuildFromCache()
    }

    /// Synchronizes coordinator watchlist from the shared `StocksWatchlistStore` (e.g. after edits in Settings).
    public func reloadWatchlistFromStore() async {
        let loaded = watchlistStore.loadWatchlist()
        guard loaded != watchlist else { return }
        watchlist = loaded
        watchlistVersion += 1
        refreshToken += 1
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        if !isConfigured {
            updateState(.unconfigured)
        } else if watchlist.isEmpty {
            updateState(.empty)
        } else {
            await rebuildFromCache()
            if isOpen {
                await refresh(force: true)
            }
        }
    }

    public func setWatchlist(_ assets: [StockAssetDescriptor], configured: Bool = true) async {
        watchlist = assets
        watchlistStore.saveWatchlist(assets)
        watchlistVersion += 1
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        isConfigured = configured
        await cache.clear(providerId: provider.id)
        if !configured {
            updateState(.unconfigured)
        } else if watchlist.isEmpty {
            updateState(.empty)
        } else {
            updateState(.loadingInitial(watchlist: watchlist))
            if isOpen { await refresh(force: true) }
        }
    }

    public func refresh(force: Bool = false) async {
        guard isConfigured else { updateState(.unconfigured); return }
        guard !watchlist.isEmpty else { updateState(.empty); return }

        if !force, let existing = inFlightRefresh {
            await existing.value
            return
        }
        if force {
            inFlightRefresh?.cancel()
        }

        let capturedGen = activeGeneration
        let capturedVersion = watchlistVersion
        refreshToken += 1
        let capturedRefreshToken = refreshToken
        let requestedAssets = watchlist

        let currentRows = await buildCachedRows(for: requestedAssets, includeMissingAsLoading: true)
        let hasAnyQuote = currentRows.values.contains { $0.quote != nil }
        if hasAnyQuote {
            let newest = currentRows.values.compactMap { $0.quote?.fetchedAt }.max()
            updateState(.ready(rows: currentRows, refreshing: true, bannerError: nil, lastUpdatedAt: newest))
        } else {
            updateState(.loadingInitial(watchlist: requestedAssets))
        }

        let task = Task<Void, Never> {
            do {
                let batch = try await provider.fetchQuotes(for: requestedAssets)
                guard !Task.isCancelled,
                      self.isOpen || force,
                      self.activeGeneration == capturedGen,
                      self.watchlistVersion == capturedVersion,
                      self.refreshToken == capturedRefreshToken else {
                    return
                }

                var updatedRows: [String: StocksRowState] = [:]
                for asset in requestedAssets {
                    if let quote = batch.quotes[asset.id] {
                        if quote.hasValidPrice {
                            await self.cache.store(quote, providerId: self.provider.id)
                            updatedRows[asset.id] = .loaded(quote)
                        } else {
                            let cached = await self.cache.quote(assetId: asset.id, providerId: self.provider.id)
                            updatedRows[asset.id] = .failed(error: .invalidData, cached: cached)
                        }
                    } else if let rowErr = batch.errorsByAssetId[asset.id] {
                        let cached = await self.cache.quote(assetId: asset.id, providerId: self.provider.id)
                        updatedRows[asset.id] = .failed(error: rowErr, cached: cached)
                    } else {
                        let cached = await self.cache.quote(assetId: asset.id, providerId: self.provider.id)
                        updatedRows[asset.id] = .failed(error: .invalidData, cached: cached)
                    }
                }
                let newest = updatedRows.values.compactMap { $0.quote?.fetchedAt }.max() ?? self.clock()
                self.updateState(.ready(rows: updatedRows, refreshing: false, bannerError: nil, lastUpdatedAt: newest))
            } catch {
                guard !Task.isCancelled,
                      self.activeGeneration == capturedGen,
                      self.watchlistVersion == capturedVersion,
                      self.refreshToken == capturedRefreshToken else {
                    return
                }
                let mapped = Self.mapError(error)
                if mapped == .cancelled { return }
                let cachedRows = await self.buildCachedRows(for: requestedAssets, includeMissingAsLoading: false, fallbackError: mapped)
                let anyCached = cachedRows.values.contains { $0.quote != nil }
                if anyCached {
                    let newest = cachedRows.values.compactMap { $0.quote?.fetchedAt }.max()
                    self.updateState(.ready(rows: cachedRows, refreshing: false, bannerError: mapped, lastUpdatedAt: newest))
                } else if mapped == .networkUnavailable {
                    self.updateState(.offlineNoData(error: mapped))
                } else {
                    self.updateState(.failedNoData(error: mapped))
                }
            }
        }
        inFlightRefresh = task
        await task.value
        if self.refreshToken == capturedRefreshToken {
            inFlightRefresh = nil
        }
    }

    public func search(query: String, intent: Int? = nil) async {
        if let intent {
            guard intent >= searchIntentFence, intent >= latestSearchIntent else { return }
            latestSearchIntent = intent
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await cancelSearch(intent: intent)
            return
        }

        inFlightSearch?.cancel()
        searchGeneration += 1
        let gen = searchGeneration
        let fence = searchIntentFence
        isSearching = true
        searchError = nil

        let task = Task<Void, Never> {
            do {
                let hits = try await provider.searchSymbols(query: trimmed)
                guard !Task.isCancelled,
                      self.searchGeneration == gen,
                      self.searchIntentFence == fence else { return }
                self.searchResults = hits
                self.searchError = nil
                self.isSearching = false
            } catch {
                guard !Task.isCancelled,
                      self.searchGeneration == gen,
                      self.searchIntentFence == fence else { return }
                let mapped = Self.mapError(error)
                if mapped != .cancelled {
                    self.searchResults = []
                    self.searchError = mapped
                }
                self.isSearching = false
            }
        }
        inFlightSearch = task
        await task.value
    }

    public func cancelSearch(intent: Int? = nil) async {
        if let intent {
            guard intent >= searchIntentFence, intent >= latestSearchIntent else { return }
            latestSearchIntent = intent
        }
        inFlightSearch?.cancel()
        inFlightSearch = nil
        searchGeneration += 1
        searchResults = []
        searchError = nil
        isSearching = false
    }

    private func cancelWork() {
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        inFlightSearch?.cancel()
        inFlightSearch = nil
    }

    private func rebuildFromCache() async {
        guard isConfigured else { updateState(.unconfigured); return }
        guard !watchlist.isEmpty else { updateState(.empty); return }
        let rows = await buildCachedRows(for: watchlist, includeMissingAsLoading: true)
        let newest = rows.values.compactMap { $0.quote?.fetchedAt }.max()
        updateState(.ready(rows: rows, refreshing: false, bannerError: nil, lastUpdatedAt: newest))
    }

    private func refreshStateFromCacheOrTrigger(fetchIfOpen: Bool) {
        if watchlist.isEmpty {
            updateState(.empty)
        } else {
            updateState(.loadingInitial(watchlist: watchlist))
            if fetchIfOpen {
                Task { await self.refresh() }
            }
        }
    }

    private func buildCachedRows(
        for assets: [StockAssetDescriptor],
        includeMissingAsLoading: Bool,
        fallbackError: StocksError? = nil
    ) async -> [String: StocksRowState] {
        var rows: [String: StocksRowState] = [:]
        for asset in assets {
            if let q = await cache.quote(assetId: asset.id, providerId: provider.id) {
                if let fallbackError {
                    rows[asset.id] = .failed(error: fallbackError, cached: q)
                } else {
                    rows[asset.id] = .loaded(q)
                }
            } else if includeMissingAsLoading {
                rows[asset.id] = .loading
            } else {
                rows[asset.id] = .failed(error: fallbackError ?? .invalidData, cached: nil)
            }
        }
        return rows
    }

    private static func mapError(_ error: Error) -> StocksError {
        if error is CancellationError { return .cancelled }
        if let e = error as? StocksError { return e }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled: return .cancelled
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return .networkUnavailable
            default: break
            }
        }
        return .unknown(ns.localizedDescription)
    }
}
