import Foundation

public struct WebsiteAnalyticsSnapshot: Equatable, Sendable {
    public let selectedProvider: WebsiteAnalyticsProviderKind
    public let selectedRange: WebsiteAnalyticsRange
    public let dataFastState: WebsiteAnalyticsProviderState
    public let ga4State: WebsiteAnalyticsProviderState
    public let oauthInProgress: Bool

    public init(
        selectedProvider: WebsiteAnalyticsProviderKind,
        selectedRange: WebsiteAnalyticsRange,
        dataFastState: WebsiteAnalyticsProviderState,
        ga4State: WebsiteAnalyticsProviderState,
        oauthInProgress: Bool = false
    ) {
        self.selectedProvider = selectedProvider
        self.selectedRange = selectedRange
        self.dataFastState = dataFastState
        self.ga4State = ga4State
        self.oauthInProgress = oauthInProgress
    }

    public var activeState: WebsiteAnalyticsProviderState {
        state(for: selectedProvider)
    }

    public func state(for provider: WebsiteAnalyticsProviderKind) -> WebsiteAnalyticsProviderState {
        switch provider {
        case .dataFast: return dataFastState
        case .googleAnalytics4: return ga4State
        }
    }
}

/// Coordinates independent DataFast & GA4 adapters, per-(provider, range) caching,
/// generation-fenced refreshes, and clean cancellation on page leave / tab disable / app exit.
/// No polling timers: refreshes occur ONLY on initial page entry and explicit user refresh.
public actor WebsiteAnalyticsCoordinator {
    private struct CacheKey: Hashable {
        let provider: WebsiteAnalyticsProviderKind
        let range: WebsiteAnalyticsRange
    }

    private let dataFastAdapter: WebsiteAnalyticsSourceAdapter
    private let ga4Adapter: WebsiteAnalyticsSourceAdapter
    private let ga4LiveAdapter: GA4DataAPIAdapter?
    private let credentialStore: WebsiteAnalyticsCredentialStore
    private let configStore: WebsiteAnalyticsConfigStore
    private let clock: @Sendable () -> Date

    public private(set) var selectedProvider: WebsiteAnalyticsProviderKind
    public private(set) var selectedRange: WebsiteAnalyticsRange = .sevenDays
    public private(set) var dataFastState: WebsiteAnalyticsProviderState
    public private(set) var ga4State: WebsiteAnalyticsProviderState
    public private(set) var oauthInProgress: Bool = false

    private var cache: [CacheKey: WebsiteAnalyticsReport] = [:]
    private var generationByProvider: [WebsiteAnalyticsProviderKind: UInt64] = [:]
    private var inFlightTasks: [WebsiteAnalyticsProviderKind: Task<Void, Never>] = [:]
    private var oauthTask: Task<Result<Void, WebsiteAnalyticsError>, Never>?
    private var oauthGeneration: UInt64 = 0
    private var isPageOpen: Bool = false
    private var isDestinationEnabled: Bool = true
    private var onSnapshotChange: (@Sendable (WebsiteAnalyticsSnapshot) -> Void)?

    public init(
        dataFastAdapter: WebsiteAnalyticsSourceAdapter,
        ga4Adapter: WebsiteAnalyticsSourceAdapter,
        credentialStore: WebsiteAnalyticsCredentialStore = WebsiteAnalyticsKeychainStore.shared,
        configStore: WebsiteAnalyticsConfigStore = UserDefaultsWebsiteAnalyticsConfigStore(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.dataFastAdapter = dataFastAdapter
        self.ga4Adapter = ga4Adapter
        self.ga4LiveAdapter = ga4Adapter as? GA4DataAPIAdapter
        self.credentialStore = credentialStore
        self.configStore = configStore
        self.clock = clock
        self.selectedProvider = configStore.selectedProvider()
        self.dataFastState = Self.initialState(for: .dataFast, configStore: configStore, credentialStore: credentialStore)
        self.ga4State = Self.initialState(for: .googleAnalytics4, configStore: configStore, credentialStore: credentialStore)
    }

    public static func makeDefault(
        transport: WebsiteAnalyticsHTTPTransport = URLSessionWebsiteAnalyticsTransport(),
        credentialStore: WebsiteAnalyticsCredentialStore = WebsiteAnalyticsKeychainStore.shared,
        configStore: WebsiteAnalyticsConfigStore = UserDefaultsWebsiteAnalyticsConfigStore(),
        oauthDriver: GA4OAuthAuthorizationDriver = GA4LoopbackOAuthDriver(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) -> WebsiteAnalyticsCoordinator {
        let df = DataFastAdapter(transport: transport, credentialStore: credentialStore, configStore: configStore)
        let ga = GA4DataAPIAdapter(
            transport: transport,
            credentialStore: credentialStore,
            configStore: configStore,
            oauthDriver: oauthDriver
        )
        return WebsiteAnalyticsCoordinator(
            dataFastAdapter: df,
            ga4Adapter: ga,
            credentialStore: credentialStore,
            configStore: configStore,
            clock: clock
        )
    }

    public var snapshot: WebsiteAnalyticsSnapshot {
        WebsiteAnalyticsSnapshot(
            selectedProvider: selectedProvider,
            selectedRange: selectedRange,
            dataFastState: dataFastState,
            ga4State: ga4State,
            oauthInProgress: oauthInProgress
        )
    }

    public func setSnapshotChangeHandler(_ handler: (@Sendable (WebsiteAnalyticsSnapshot) -> Void)?) {
        self.onSnapshotChange = handler
        emitSnapshot()
    }

    // MARK: - Lifecycle (No polling timers)

    public func openPage() async {
        isPageOpen = true
        guard isDestinationEnabled else { return }
        await refreshActiveIfConfigured(force: false)
    }

    public func close() {
        isPageOpen = false
        cancelAllInFlightRefreshes()
        cancelGA4OAuth()
    }

    /// Disabling the destination cancels in-flight network requests while preserving user credentials & config.
    public func setDestinationEnabled(_ enabled: Bool) async {
        guard isDestinationEnabled != enabled else { return }
        isDestinationEnabled = enabled
        if !enabled {
            close()
        } else if isPageOpen {
            await refreshActiveIfConfigured(force: false)
        }
    }

    /// Called on app termination: cancels in-flight refreshes and OAuth tasks immediately.
    public func prepareForTermination() {
        close()
    }

    // MARK: - Selection & Refresh

    public func selectProvider(_ provider: WebsiteAnalyticsProviderKind) async {
        guard provider != selectedProvider else { return }
        cancelGA4OAuth()
        cancelRefresh(for: selectedProvider)
        selectedProvider = provider
        configStore.setSelectedProvider(provider)

        if let cached = cache[CacheKey(provider: provider, range: selectedRange)] {
            setState(cached.isEffectivelyEmpty ? .empty(cached, refreshing: false) : .loaded(cached, refreshing: false), for: provider)
        } else {
            setState(
                Self.initialState(for: provider, configStore: configStore, credentialStore: credentialStore),
                for: provider
            )
        }
        emitSnapshot()

        if isPageOpen && isDestinationEnabled {
            await refreshActiveIfConfigured(force: false)
        }
    }

    public func selectRange(_ range: WebsiteAnalyticsRange) async {
        guard range != selectedRange else { return }
        cancelRefresh(for: selectedProvider)
        selectedRange = range

        let provider = selectedProvider
        if let cached = cache[CacheKey(provider: provider, range: range)] {
            setState(cached.isEffectivelyEmpty ? .empty(cached, refreshing: false) : .loaded(cached, refreshing: false), for: provider)
        } else if !isProviderConfigured(provider) {
            setState(
                Self.initialState(for: provider, configStore: configStore, credentialStore: credentialStore),
                for: provider
            )
        }
        emitSnapshot()

        if isPageOpen && isDestinationEnabled {
            await refreshActiveIfConfigured(force: true)
        }
    }

    public func refresh(force: Bool = true) async {
        guard isDestinationEnabled else { return }
        await refreshProvider(selectedProvider, range: selectedRange, force: force)
    }

    // MARK: - Configuration & Credentials

    public func saveDataFastConfiguration(
        siteLabel: String,
        apiKey: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) async -> Result<Void, WebsiteAnalyticsError> {
        let validatedKey: String
        switch WebsiteAnalyticsHostPolicy.validateDataFastAPIKey(apiKey) {
        case .success(let key):
            validatedKey = key
        case .failure(let err):
            return .failure(err)
        }

        let previousSiteId = configStore.loadDataFastConfig()?.siteId
        let siteId = previousSiteId ?? "default"
        let config = DataFastSiteConfig(
            siteId: siteId,
            siteLabel: siteLabel.isEmpty ? "DataFast" : siteLabel,
            timeZoneIdentifier: timeZoneIdentifier
        )
        guard credentialStore.setSecret(validatedKey, for: .dataFastAPIKey, accountKey: config.siteId) else {
            return .failure(.invalidConfiguration("keychain_write_failed"))
        }
        configStore.saveDataFastConfig(config)
        clearCache(for: .dataFast)
        setState(.loadingInitial, for: .dataFast)
        emitSnapshot()

        if isPageOpen && isDestinationEnabled && selectedProvider == .dataFast {
            await refreshProvider(.dataFast, range: selectedRange, force: true)
        }
        return .success(())
    }

    public func saveGA4Configuration(
        propertyId: String,
        propertyLabel: String,
        oauthClientId: String,
        redirectURI: String?,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) async -> Result<Void, WebsiteAnalyticsError> {
        let config = GA4PropertyConfig(
            propertyId: propertyId,
            propertyLabel: propertyLabel,
            oauthClientId: oauthClientId,
            redirectURI: redirectURI,
            timeZoneIdentifier: timeZoneIdentifier
        )
        guard config.isPropertyIdValid else {
            return .failure(.invalidConfiguration("ga4_invalid_property_id"))
        }
        let previousPropertyId = configStore.loadGA4Config()?.propertyId
        if let previousPropertyId, previousPropertyId != config.propertyId {
            credentialStore.deleteAllSecrets(for: .googleAnalytics4, accountKey: previousPropertyId)
            clearCache(for: .googleAnalytics4)
        }
        configStore.saveGA4Config(config)
        let nextState = Self.initialState(for: .googleAnalytics4, configStore: configStore, credentialStore: credentialStore)
        setState(nextState, for: .googleAnalytics4)
        emitSnapshot()

        if isPageOpen && isDestinationEnabled && selectedProvider == .googleAnalytics4 && isProviderConfigured(.googleAnalytics4) {
            await refreshProvider(.googleAnalytics4, range: selectedRange, force: true)
        }
        return .success(())
    }

    public func startGA4OAuth() async -> Result<Void, WebsiteAnalyticsError> {
        guard !Task.isCancelled, isDestinationEnabled else { return .failure(.oauthCancelled) }
        cancelGA4OAuth()
        guard let ga4LiveAdapter else {
            return .failure(.unconfigured(.oauthNotConfigured))
        }
        oauthInProgress = true
        let generation = oauthGeneration
        emitSnapshot()

        let task = Task<Result<Void, WebsiteAnalyticsError>, Never> {
            do {
                _ = try await ga4LiveAdapter.authorizeWithPKCE()
                return .success(())
            } catch let err as WebsiteAnalyticsError {
                return .failure(err)
            } catch is CancellationError {
                return .failure(.oauthCancelled)
            } catch {
                return .failure(.offline)
            }
        }

        oauthTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard generation == oauthGeneration else { return .failure(.oauthCancelled) }
        oauthInProgress = false
        oauthTask = nil

        switch result {
        case .success:
            emitSnapshot()
            if isPageOpen && isDestinationEnabled && selectedProvider == .googleAnalytics4 {
                await refreshProvider(.googleAnalytics4, range: selectedRange, force: true)
            }
            return .success(())
        case .failure(let err):
            if err == .oauthCancelled {
                // Remain disconnected; never show misleading success.
                setState(
                    Self.initialState(for: .googleAnalytics4, configStore: configStore, credentialStore: credentialStore),
                    for: .googleAnalytics4
                )
            }
            emitSnapshot()
            return .failure(err)
        }
    }

    public func cancelGA4OAuth() {
        oauthGeneration &+= 1
        oauthTask?.cancel()
        oauthTask = nil
        if oauthInProgress {
            oauthInProgress = false
            emitSnapshot()
        }
    }

    /// Explicitly disconnects a provider: cancels in-flight requests, revokes GA4 tokens where possible,
    /// deletes Keychain secrets, clears cached reports, and returns the provider to unconfigured.
    public func disconnect(provider: WebsiteAnalyticsProviderKind) async {
        cancelRefresh(for: provider)
        if provider == .googleAnalytics4 {
            cancelGA4OAuth()
            if let propId = configStore.loadGA4Config()?.propertyId {
                await ga4LiveAdapter?.revokeStoredTokens(for: propId)
                credentialStore.deleteAllSecrets(for: .googleAnalytics4, accountKey: propId)
            }
            configStore.removeGA4Config()
        } else {
            if let siteId = configStore.loadDataFastConfig()?.siteId {
                credentialStore.deleteAllSecrets(for: .dataFast, accountKey: siteId)
            }
            configStore.removeDataFastConfig()
        }
        clearCache(for: provider)
        setState(
            Self.initialState(for: provider, configStore: configStore, credentialStore: credentialStore),
            for: provider
        )
        emitSnapshot()
    }

    // MARK: - Internal Refresh & Fencing

    private func refreshActiveIfConfigured(force: Bool) async {
        let provider = selectedProvider
        guard isProviderConfigured(provider) else {
            setState(
                Self.initialState(for: provider, configStore: configStore, credentialStore: credentialStore),
                for: provider
            )
            emitSnapshot()
            return
        }
        await refreshProvider(provider, range: selectedRange, force: force)
    }

    private func refreshProvider(
        _ provider: WebsiteAnalyticsProviderKind,
        range: WebsiteAnalyticsRange,
        force: Bool
    ) async {
        guard isProviderConfigured(provider) else {
            setState(
                Self.initialState(for: provider, configStore: configStore, credentialStore: credentialStore),
                for: provider
            )
            emitSnapshot()
            return
        }

        let cacheKey = CacheKey(provider: provider, range: range)
        let existingCache = cache[cacheKey]
        if !force, let existingCache {
            setState(
                existingCache.isEffectivelyEmpty ? .empty(existingCache, refreshing: false) : .loaded(existingCache, refreshing: false),
                for: provider
            )
            emitSnapshot()
            return
        }

        cancelRefresh(for: provider)
        let generation = nextGeneration(for: provider)

        if let existingCache {
            setState(
                existingCache.isEffectivelyEmpty ? .empty(existingCache, refreshing: true) : .loaded(existingCache, refreshing: true),
                for: provider
            )
        } else {
            setState(.loadingInitial, for: provider)
        }
        emitSnapshot()

        let adapter = (provider == .dataFast) ? dataFastAdapter : ga4Adapter
        let now = clock()

        let task = Task { [weak self] in
            do {
                let report = try await adapter.fetchReport(range: range, now: now)
                try Task.checkCancellation()
                await self?.handleFetchSuccess(report, provider: provider, range: range, generation: generation)
            } catch let err as WebsiteAnalyticsError {
                await self?.handleFetchFailure(err, provider: provider, range: range, generation: generation)
            } catch is CancellationError {
                await self?.handleFetchFailure(.cancelled, provider: provider, range: range, generation: generation)
            } catch {
                await self?.handleFetchFailure(.offline, provider: provider, range: range, generation: generation)
            }
        }
        inFlightTasks[provider] = task
        await task.value
    }

    private func handleFetchSuccess(
        _ report: WebsiteAnalyticsReport,
        provider: WebsiteAnalyticsProviderKind,
        range: WebsiteAnalyticsRange,
        generation: UInt64
    ) {
        guard generationByProvider[provider] == generation else { return }
        guard report.provider == provider, report.range == range else { return }
        inFlightTasks[provider] = nil

        let cacheKey = CacheKey(provider: provider, range: range)
        cache[cacheKey] = report

        // Only update visible state for this provider if range still matches.
        if selectedRange == range {
            let nextState: WebsiteAnalyticsProviderState = report.isEffectivelyEmpty
                ? .empty(report, refreshing: false)
                : .loaded(report, refreshing: false)
            setState(nextState, for: provider)
            emitSnapshot()
        }
    }

    private func handleFetchFailure(
        _ error: WebsiteAnalyticsError,
        provider: WebsiteAnalyticsProviderKind,
        range: WebsiteAnalyticsRange,
        generation: UInt64
    ) {
        guard generationByProvider[provider] == generation else { return }
        inFlightTasks[provider] = nil

        // Cancellation leaves existing cache/state clean without surfacing an error banner.
        if error == .cancelled {
            if let existing = cache[CacheKey(provider: provider, range: range)] {
                setState(
                    existing.isEffectivelyEmpty ? .empty(existing, refreshing: false) : .loaded(existing, refreshing: false),
                    for: provider
                )
            }
            emitSnapshot()
            return
        }

        // Preserve valid cached report on failure; never replace with zeros or sample data.
        if let existing = cache[CacheKey(provider: provider, range: range)] {
            setState(.failedWithCache(existing, error: error), for: provider)
        } else if case .unconfigured(let reason) = error {
            setState(.unconfigured(reason: reason), for: provider)
        } else {
            setState(.failedNoCache(error: error), for: provider)
        }
        emitSnapshot()
    }

    private func cancelRefresh(for provider: WebsiteAnalyticsProviderKind) {
        generationByProvider[provider, default: 0] &+= 1
        inFlightTasks[provider]?.cancel()
        inFlightTasks[provider] = nil
    }

    private func cancelAllInFlightRefreshes() {
        for provider in WebsiteAnalyticsProviderKind.allCases {
            cancelRefresh(for: provider)
        }
    }

    private func nextGeneration(for provider: WebsiteAnalyticsProviderKind) -> UInt64 {
        let next = generationByProvider[provider, default: 0] &+ 1
        generationByProvider[provider] = next
        return next
    }

    private func clearCache(for provider: WebsiteAnalyticsProviderKind) {
        cache = cache.filter { $0.key.provider != provider }
    }

    private func setState(_ state: WebsiteAnalyticsProviderState, for provider: WebsiteAnalyticsProviderKind) {
        switch provider {
        case .dataFast: dataFastState = state
        case .googleAnalytics4: ga4State = state
        }
    }

    private func isProviderConfigured(_ provider: WebsiteAnalyticsProviderKind) -> Bool {
        if case .unconfigured = Self.initialState(for: provider, configStore: configStore, credentialStore: credentialStore) {
            return false
        }
        return true
    }

    private static func initialState(
        for provider: WebsiteAnalyticsProviderKind,
        configStore: WebsiteAnalyticsConfigStore,
        credentialStore: WebsiteAnalyticsCredentialStore
    ) -> WebsiteAnalyticsProviderState {
        switch provider {
        case .dataFast:
            guard let config = configStore.loadDataFastConfig(),
                  let key = credentialStore.secret(for: .dataFastAPIKey, accountKey: config.siteId),
                  case .success = WebsiteAnalyticsHostPolicy.validateDataFastAPIKey(key) else {
                return .unconfigured(reason: .missingCredentials)
            }
            return .loadingInitial
        case .googleAnalytics4:
            guard let config = configStore.loadGA4Config(), config.isPropertyIdValid else {
                return .unconfigured(reason: .missingProperty)
            }
            let hasAccess = credentialStore.hasSecret(for: .ga4AccessToken, accountKey: config.propertyId)
            let hasRefresh = credentialStore.hasSecret(for: .ga4RefreshToken, accountKey: config.propertyId)
            if hasAccess || (hasRefresh && !config.oauthClientId.isEmpty) {
                return .loadingInitial
            }
            if !config.hasOAuthClientConfig {
                return .unconfigured(reason: .oauthNotConfigured)
            }
            return .unconfigured(reason: .missingCredentials)
        }
    }

    private func emitSnapshot() {
        onSnapshotChange?(snapshot)
    }
}
