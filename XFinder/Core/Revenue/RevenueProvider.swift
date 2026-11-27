import Foundation

public enum RevenueError: Error, Equatable, Sendable {
    case networkUnavailable
    case rateLimited
    case timeout
    case unauthorized
    case scopeRestricted
    case paginationInterrupted
    case invalidData
    case cancelled
    case unknown(String)

    public var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .rateLimited, .timeout, .paginationInterrupted:
            return true
        case .unauthorized, .scopeRestricted, .invalidData, .cancelled, .unknown:
            return false
        }
    }
}

public struct RevenueErrorPresentation: Equatable, Sendable {
    public let titleKey: String
    public let hintKey: String?
    public let symbolName: String
    public let canRetry: Bool

    public init(for error: RevenueError) {
        self.canRetry = error.isRetryable
        switch error {
        case .networkUnavailable:
            self.titleKey = "Không có kết nối mạng"
            self.hintKey = "Đang giữ số liệu đã đồng bộ gần nhất nếu có."
            self.symbolName = "wifi.slash"
        case .rateLimited:
            self.titleKey = "Tạm hết lượt đồng bộ doanh thu"
            self.hintKey = "Thử lại sau ít phút."
            self.symbolName = "hourglass"
        case .timeout:
            self.titleKey = "Hết thời gian chờ cổng thanh toán"
            self.hintKey = "Thử lại bằng nút Làm mới."
            self.symbolName = "clock.badge.exclamationmark"
        case .unauthorized:
            self.titleKey = "Phiên kết nối đã hết hạn"
            self.hintKey = "Mở Cài đặt để kết nối lại tài khoản chỉ đọc."
            self.symbolName = "key.slash.fill"
        case .scopeRestricted:
            self.titleKey = "Quyền đọc hiện tại chỉ xem được một phần dữ liệu"
            self.hintKey = "Kiểm tra phạm vi quyền trong Cài đặt."
            self.symbolName = "lock.shield"
        case .paginationInterrupted:
            self.titleKey = "Đồng bộ trang dữ liệu bị ngắt giữa chừng"
            self.hintKey = "Dữ liệu cũ được giữ nguyên cho tới khi đồng bộ đủ."
            self.symbolName = "arrow.triangle.2.circlepath"
        case .invalidData, .cancelled, .unknown:
            self.titleKey = "Không đọc được dữ liệu doanh thu"
            self.hintKey = "Thử lại bằng nút Làm mới."
            self.symbolName = "exclamationmark.triangle.fill"
        }
    }
}

public struct RevenueFetchPage: Equatable, Sendable {
    public let events: [RevenueLedgerEvent]
    public let cursor: String?
    public let wasPaginationInterrupted: Bool

    public init(
        events: [RevenueLedgerEvent],
        cursor: String? = nil,
        wasPaginationInterrupted: Bool = false
    ) {
        self.events = events
        self.cursor = cursor
        self.wasPaginationInterrupted = wasPaginationInterrupted
    }
}

public protocol RevenueProvider: Sendable {
    var id: String { get }
    func fetchLedger(
        for config: SourceAccountConfig,
        period: RevenuePeriod,
        cursor: String?,
        now: Date
    ) async throws -> RevenueFetchPage
}

public protocol RevenueAccountStore: Sendable {
    func loadConfigs() -> [RevenueSourceKind: SourceAccountConfig]
    func saveConfig(_ config: SourceAccountConfig)
    func removeConfig(for source: RevenueSourceKind)
    func clearAll()
}

public final class InMemoryRevenueAccountStore: RevenueAccountStore, @unchecked Sendable {
    private let lock = NSLock()
    private var configs: [RevenueSourceKind: SourceAccountConfig]

    public init(initial: [RevenueSourceKind: SourceAccountConfig] = [:]) {
        self.configs = initial
    }

    public func loadConfigs() -> [RevenueSourceKind: SourceAccountConfig] {
        lock.lock(); defer { lock.unlock() }
        return configs
    }

    public func saveConfig(_ config: SourceAccountConfig) {
        lock.lock(); defer { lock.unlock() }
        configs[config.source] = config
    }

    public func removeConfig(for source: RevenueSourceKind) {
        lock.lock(); defer { lock.unlock() }
        configs.removeValue(forKey: source)
    }

    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        configs.removeAll()
    }
}

public actor RevenueCacheStore {
    private struct CacheKey: Hashable {
        let source: RevenueSourceKind
        let accountId: String
    }

    private var eventsByAccount: [CacheKey: [RevenueLedgerEvent]] = [:]
    private var fetchedAtByAccount: [CacheKey: Date] = [:]
    private var cursorsByAccount: [CacheKey: String] = [:]

    public init() {}

    public func cached(for source: RevenueSourceKind, accountId: String) -> (events: [RevenueLedgerEvent], fetchedAt: Date, cursor: String?)? {
        let key = CacheKey(source: source, accountId: accountId)
        guard let evs = eventsByAccount[key], let fetched = fetchedAtByAccount[key] else { return nil }
        return (evs, fetched, cursorsByAccount[key])
    }

    public func upsert(events: [RevenueLedgerEvent], for source: RevenueSourceKind, accountId: String, fetchedAt: Date, cursor: String?) {
        let key = CacheKey(source: source, accountId: accountId)
        let scopedEvents = events.filter { $0.source == source && $0.accountId == accountId }
        var existing = eventsByAccount[key] ?? []
        var idxById: [String: Int] = [:]
        for (idx, item) in existing.enumerated() { idxById[item.id] = idx }
        for item in scopedEvents {
            if let existingIdx = idxById[item.id] {
                existing[existingIdx] = item
            } else {
                idxById[item.id] = existing.count
                existing.append(item)
            }
        }
        eventsByAccount[key] = existing
        fetchedAtByAccount[key] = fetchedAt
        if let cursor {
            cursorsByAccount[key] = cursor
        }
    }

    public func clear(source: RevenueSourceKind? = nil, accountId: String? = nil) {
        if let source, let accountId {
            let key = CacheKey(source: source, accountId: accountId)
            eventsByAccount.removeValue(forKey: key)
            fetchedAtByAccount.removeValue(forKey: key)
            cursorsByAccount.removeValue(forKey: key)
        } else if let source {
            for key in eventsByAccount.keys where key.source == source {
                eventsByAccount.removeValue(forKey: key)
                fetchedAtByAccount.removeValue(forKey: key)
                cursorsByAccount.removeValue(forKey: key)
            }
        } else {
            eventsByAccount.removeAll()
            fetchedAtByAccount.removeAll()
            cursorsByAccount.removeAll()
        }
    }
}

public actor RevenueCoordinator {
    private let provider: RevenueProvider
    private let accountStore: RevenueAccountStore
    private let cache: RevenueCacheStore
    private let credentialStore: RevenueCredentialStore?
    private let clock: @Sendable () -> Date

    public private(set) var period: RevenuePeriod = .today
    public private(set) var stripeState: SourceSyncState = .unconfigured
    public private(set) var shopifyState: SourceSyncState = .unconfigured
    public private(set) var snapshot: RevenueSnapshot

    private var configs: [RevenueSourceKind: SourceAccountConfig]
    private var activeGeneration: Int = 0
    private var refreshTokenBySource: [RevenueSourceKind: UInt64] = [:]
    private var inFlightTasks: [RevenueSourceKind: Task<Void, Never>] = [:]
    private var isOpen: Bool = false
    private var onSnapshotChange: (@Sendable (RevenueSnapshot) -> Void)?

    public init(
        provider: RevenueProvider,
        accountStore: RevenueAccountStore = InMemoryRevenueAccountStore(),
        cache: RevenueCacheStore = RevenueCacheStore(),
        credentialStore: RevenueCredentialStore? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.accountStore = accountStore
        self.cache = cache
        self.credentialStore = credentialStore
        self.clock = clock
        self.configs = accountStore.loadConfigs()
        self.snapshot = RevenueSnapshot(
            period: .today,
            stripeState: .unconfigured,
            shopifyState: .unconfigured,
            reconciliationStatus: .singleSourceOrNone,
            combinedTotalsByCurrency: nil
        )
    }

    public func setSnapshotChangeHandler(_ handler: (@Sendable (RevenueSnapshot) -> Void)?) {
        self.onSnapshotChange = handler
    }

    public func configureSource(_ config: SourceAccountConfig) async {
        let previousAccountId = configs[config.source]?.accountId
        accountStore.saveConfig(config)
        configs[config.source] = config
        if let previousAccountId, previousAccountId != config.accountId {
            inFlightTasks[config.source]?.cancel()
            inFlightTasks[config.source] = nil
            refreshTokenBySource[config.source, default: 0] += 1
            await cache.clear(source: config.source, accountId: previousAccountId)
            credentialStore?.deleteToken(for: config.source, accountId: previousAccountId)
            setState(.unconfigured, for: config.source)
        }
        if isOpen {
            await refreshSource(config.source, force: true)
        } else {
            await rebuildSnapshot()
        }
    }

    /// Cancels in-flight syncs for this portal and deletes its cached events/cursor/config and Keychain token.
    public func disconnectSource(_ source: RevenueSourceKind) async {
        let previousAccountId = configs[source]?.accountId
        inFlightTasks[source]?.cancel()
        inFlightTasks[source] = nil
        refreshTokenBySource[source, default: 0] += 1
        accountStore.removeConfig(for: source)
        configs.removeValue(forKey: source)
        if let previousAccountId {
            credentialStore?.deleteToken(for: source, accountId: previousAccountId)
        }
        await cache.clear(source: source)
        setState(.unconfigured, for: source)
        await rebuildSnapshot()
    }

    public func openPage() async {
        isOpen = true
        activeGeneration += 1
        configs = accountStore.loadConfigs()
        await refresh(force: false)
    }

    public func close() {
        isOpen = false
        activeGeneration += 1
        for (_, task) in inFlightTasks { task.cancel() }
        inFlightTasks.removeAll()
    }

    public func selectPeriod(_ newPeriod: RevenuePeriod) async {
        guard period != newPeriod else { return }
        period = newPeriod
        await rebuildSnapshot()
        if isOpen {
            await refresh(force: false)
        }
    }

    public func refresh(force: Bool = true) async {
        await withTaskGroup(of: Void.self) { group in
            for src in RevenueSourceKind.allCases {
                group.addTask { await self.refreshSource(src, force: force) }
            }
        }
    }

    public func refreshSource(_ source: RevenueSourceKind, force: Bool = false) async {
        guard let config = configs[source] else {
            setState(.unconfigured, for: source)
            await rebuildSnapshot()
            return
        }

        if !force, let existing = inFlightTasks[source] {
            await existing.value
            return
        }
        if force {
            inFlightTasks[source]?.cancel()
        }

        let capturedGen = activeGeneration
        let capturedAccountId = config.accountId
        let nextToken = (refreshTokenBySource[source] ?? 0) + 1
        refreshTokenBySource[source] = nextToken
        let requestedPeriod = period
        let cached = await cache.cached(for: source, accountId: capturedAccountId)

        if let cached {
            let report = RevenueAggregator.buildSourceReport(
                config: config,
                events: cached.events,
                period: requestedPeriod,
                now: clock(),
                fetchedAt: cached.fetchedAt,
                cursor: cached.cursor,
                wasPaginationInterrupted: false
            )
            setState(report.currencyTotals.isEmpty ? .empty(report, refreshing: true) : .loaded(report, refreshing: true), for: source)
        } else {
            setState(.loadingInitial, for: source)
        }
        await rebuildSnapshot()

        let task = Task<Void, Never> {
            do {
                let page = try await provider.fetchLedger(
                    for: config,
                    period: requestedPeriod,
                    cursor: cached?.cursor,
                    now: clock()
                )
                guard !Task.isCancelled,
                      self.activeGeneration == capturedGen,
                      self.refreshTokenBySource[source] == nextToken,
                      self.configs[source]?.accountId == capturedAccountId else { return }

                // Interrupted pagination does NOT advance cursor and preserves prior complete cache if present.
                if page.wasPaginationInterrupted {
                    if let cached {
                        let kept = RevenueAggregator.buildSourceReport(
                            config: config,
                            events: cached.events,
                            period: self.period,
                            now: self.clock(),
                            fetchedAt: cached.fetchedAt,
                            cursor: cached.cursor,
                            wasPaginationInterrupted: true
                        )
                        self.setState(.failedWithCache(kept, error: .paginationInterrupted), for: source)
                    } else {
                        self.setState(.failedNoCache(error: .paginationInterrupted), for: source)
                    }
                    await self.rebuildSnapshot()
                    return
                }

                let now = self.clock()
                await self.cache.upsert(events: page.events, for: source, accountId: capturedAccountId, fetchedAt: now, cursor: page.cursor)
                let merged = await self.cache.cached(for: source, accountId: capturedAccountId)
                let report = RevenueAggregator.buildSourceReport(
                    config: config,
                    events: merged?.events ?? page.events,
                    period: self.period,
                    now: now,
                    fetchedAt: now,
                    cursor: page.cursor,
                    wasPaginationInterrupted: false
                )
                self.setState(report.currencyTotals.isEmpty ? .empty(report, refreshing: false) : .loaded(report, refreshing: false), for: source)
                await self.rebuildSnapshot()
            } catch {
                guard !Task.isCancelled,
                      self.activeGeneration == capturedGen,
                      self.refreshTokenBySource[source] == nextToken,
                      self.configs[source]?.accountId == capturedAccountId else { return }
                let mapped = Self.mapError(error)
                if mapped == .cancelled { return }
                if let cached = await self.cache.cached(for: source, accountId: capturedAccountId) {
                    let report = RevenueAggregator.buildSourceReport(
                        config: config,
                        events: cached.events,
                        period: self.period,
                        now: self.clock(),
                        fetchedAt: cached.fetchedAt,
                        cursor: cached.cursor,
                        wasPaginationInterrupted: false
                    )
                    self.setState(.failedWithCache(report, error: mapped), for: source)
                } else {
                    self.setState(.failedNoCache(error: mapped), for: source)
                }
                await self.rebuildSnapshot()
            }
        }
        inFlightTasks[source] = task
        await task.value
        if self.refreshTokenBySource[source] == nextToken {
            inFlightTasks[source] = nil
        }
    }

    private func setState(_ newState: SourceSyncState, for source: RevenueSourceKind) {
        switch source {
        case .stripe: stripeState = newState
        case .shopify: shopifyState = newState
        }
    }

    private func rebuildSnapshot() async {
        // Re-project existing cached events whenever period changes without hitting network unnecessarily.
        for src in RevenueSourceKind.allCases {
            guard let cfg = configs[src], let cached = await cache.cached(for: src, accountId: cfg.accountId) else {
                if configs[src] == nil { setState(.unconfigured, for: src) }
                continue
            }
            let currentErr: RevenueError? = (src == .stripe ? stripeState : shopifyState).error
            let refreshing: Bool = (src == .stripe ? stripeState : shopifyState).isRefreshing
            let rep = RevenueAggregator.buildSourceReport(
                config: cfg,
                events: cached.events,
                period: period,
                now: clock(),
                fetchedAt: cached.fetchedAt,
                cursor: cached.cursor,
                wasPaginationInterrupted: currentErr == .paginationInterrupted
            )
            if let currentErr {
                setState(.failedWithCache(rep, error: currentErr), for: src)
            } else {
                setState(rep.currencyTotals.isEmpty ? .empty(rep, refreshing: refreshing) : .loaded(rep, refreshing: refreshing), for: src)
            }
        }

        let stripeEvents: [RevenueLedgerEvent]
        if let sCfg = configs[.stripe] {
            stripeEvents = await cache.cached(for: .stripe, accountId: sCfg.accountId)?.events ?? []
        } else {
            stripeEvents = []
        }
        let shopifyEvents: [RevenueLedgerEvent]
        if let shCfg = configs[.shopify] {
            shopifyEvents = await cache.cached(for: .shopify, accountId: shCfg.accountId)?.events ?? []
        } else {
            shopifyEvents = []
        }
        let cross = RevenueAggregator.evaluateCrossSource(
            stripeReport: stripeState.report,
            shopifyReport: shopifyState.report,
            stripeEvents: stripeEvents,
            shopifyEvents: shopifyEvents,
            period: period,
            now: clock()
        )
        let snap = RevenueSnapshot(
            period: period,
            stripeState: stripeState,
            shopifyState: shopifyState,
            reconciliationStatus: cross.status,
            combinedTotalsByCurrency: cross.combined
        )
        self.snapshot = snap
        onSnapshotChange?(snap)
    }

    private static func mapError(_ error: Error) -> RevenueError {
        if error is CancellationError { return .cancelled }
        if let e = error as? RevenueError { return e }
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
