import Foundation

/// Pure Async Coordinator for Weather in Dynamic Island.
/// Coordinates city selection, debounced search, caching, generation tokens, coalescing,
/// and cancellation of in-flight requests.
/// Runs I/O off the main thread and enforces no-polling / idle CPU policy.

public enum WeatherUIState: Equatable, Sendable {
    case unselected
    case loadingInitial(WeatherLocation)
    case loaded(WeatherSnapshot, freshness: WeatherFreshness)
    case refreshing(WeatherSnapshot)
    case offlineWithStale(WeatherSnapshot, age: TimeInterval)
    /// A fetch failed, but a still-valid cached forecast exists and stays on screen.
    ///
    /// This is deliberately NOT `offlineNoData`/`failed`: a timeout, an HTTP 429 or a broken backend says
    /// nothing about whether the last forecast is still usable, and throwing away six hours of good data
    /// because one request failed is worse than showing it with the failure attached. It is also not plain
    /// `offlineWithStale`, because "Ngoại tuyến" would be a false statement when the network is up and the
    /// quota is spent. The error travels with the snapshot so the page can name the group and offer the
    /// retry that actually applies.
    case failedWithStale(WeatherSnapshot, age: TimeInterval, WeatherError)
    case offlineNoData(WeatherLocation)
    case failed(WeatherLocation, WeatherError, canRetry: Bool)
    case locationDenied
}

public actor WeatherCoordinator {
    public private(set) var selectedLocation: WeatherLocation?
    public private(set) var state: WeatherUIState = .unselected
    public private(set) var searchResults: [WeatherLocation] = []
    /// Why the last city search returned nothing, or `nil` when it simply had no matches.
    ///
    /// The page used to infer "no cities found" from `searchResults.isEmpty`, so a timeout, a 429 or a
    /// 5xx looked exactly like a query that genuinely matched nothing — the person was told the city does
    /// not exist while the real problem was the network. This separates the two: a failed search carries
    /// its error group (and therefore its retry), an empty result stays empty with no error.
    public private(set) var searchError: WeatherError?

    public private(set) var isSearching: Bool = false

    private let provider: WeatherProvider
    private let cache: WeatherCacheStore
    private let locationStore: WeatherLocationStore?
    private let locationService: WeatherLocationService
    private let clock: @Sendable () -> Date

    private var activeGeneration: Int = 0
    /// Bumped per search query so a late reply (or a late failure) for a superseded query is dropped.
    private var searchGeneration: Int = 0
    /// Orders `search` against `cancelSearch` regardless of the order their tasks reach this actor.
    /// Monotonic; the highest intent the coordinator has acted on. `nil` intents (legacy callers) skip it.
    private var latestSearchIntent: Int = 0
    /// Intents at or below this are dead: set when the page closes or resets, so a search still queued
    /// behind it cannot start. A *new* search always carries a higher intent, so it is never blocked.
    ///
    /// This used to be `latestSearchIntent = .max`, which was a permanent kill switch: a finite counter
    /// can never be `>= .max`, so every search after the first close was silently dropped.
    private var searchIntentFence: Int = 0
    private var inFlightFetchTask: Task<WeatherSnapshot, Error>?
    private var inFlightSearchTask: Task<[WeatherLocation], Error>?
    private var stateChangeHandler: (@Sendable (WeatherUIState) -> Void)?

    public init(
        provider: WeatherProvider,
        cache: WeatherCacheStore = WeatherCacheStore(),
        locationStore: WeatherLocationStore? = UserDefaultsWeatherLocationStore(),
        locationService: WeatherLocationService = DefaultWeatherLocationService(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.cache = cache
        self.locationStore = locationStore
        self.locationService = locationService
        self.clock = clock

        if let saved = locationStore?.loadSavedLocation() {
            self.selectedLocation = saved
            let now = clock()
            if let cached = cache.get(providerId: provider.id, locationId: saved.id, now: now) {
                switch cached.freshness {
                case .fresh:
                    self.state = .loaded(cached.snapshot, freshness: .fresh)
                case .stale(let age):
                    self.state = .offlineWithStale(cached.snapshot, age: age)
                case .expired:
                    self.state = .unselected
                }
            }
        }
    }

    public func setStateChangeHandler(_ handler: (@Sendable (WeatherUIState) -> Void)?) {
        self.stateChangeHandler = handler
    }

    private func updateState(_ newState: WeatherUIState) {
        self.state = newState
        stateChangeHandler?(newState)
    }

    /// Selects a new location.
    /// Immediately clears prior forecast from UI to prevent stale cross-city rendering.
    public func selectLocation(_ location: WeatherLocation, triggerFetch: Bool = true) async {
        activeGeneration += 1
        let currentGen = activeGeneration

        // Cancel previous in-flight fetch
        inFlightFetchTask?.cancel()
        inFlightFetchTask = nil

        selectedLocation = location
        if !location.isCurrentLocation {
            locationStore?.saveLocation(location)
        }

        let now = clock()
        // Check cache for this location
        if let cached = cache.get(providerId: provider.id, locationId: location.id, now: now) {
            switch cached.freshness {
            case .fresh:
                updateState(.loaded(cached.snapshot, freshness: .fresh))
                return
            case .stale(let age):
                updateState(.offlineWithStale(cached.snapshot, age: age))
                if triggerFetch {
                    await performFetch(for: location, generation: currentGen, existingSnapshot: cached.snapshot)
                }
                return
            case .expired:
                updateState(.loadingInitial(location))
            }
        } else {
            updateState(.loadingInitial(location))
        }

        if triggerFetch {
            await performFetch(for: location, generation: currentGen, existingSnapshot: nil)
        }
    }

    /// Deliberate refresh action from the user.
    /// Coalesces if a fetch for this location is already in-flight.
    public func refresh() async {
        guard let location = selectedLocation else { return }

        // Coalesce if already in flight
        if let existing = inFlightFetchTask {
            _ = try? await existing.value
            return
        }

        activeGeneration += 1
        let currentGen = activeGeneration

        let currentSnapshot: WeatherSnapshot?
        switch state {
        case .loaded(let s, _), .refreshing(let s), .offlineWithStale(let s, _),
             .failedWithStale(let s, _, _):
            currentSnapshot = (s.location.id == location.id) ? s : nil
        default:
            currentSnapshot = nil
        }

        let fallbackSnapshot = validFallbackSnapshot(
            existing: currentSnapshot,
            for: location,
            at: clock()
        )

        await performFetch(for: location, generation: currentGen, existingSnapshot: fallbackSnapshot)
    }

    /// Lifecycle hook when the Weather surface reopens.
    /// Re-evaluates cache TTL against `clock()`:
    /// - `<= 15m` (.fresh): keeps cached forecast with 0 network requests.
    /// - `15m < age <= 6h` (.stale): refreshes while preserving the previous 12h forecast (.refreshing).
    /// - `> 6h` (.expired) or uncached: drops expired snapshot and fetches fresh data (.loadingInitial).
    public func reopen() async {
        guard let location = selectedLocation else { return }

        if inFlightFetchTask != nil {
            return
        }

        let now = clock()
        if let cached = cache.get(providerId: provider.id, locationId: location.id, now: now) {
            switch cached.freshness {
            case .fresh:
                if state != .loaded(cached.snapshot, freshness: .fresh) {
                    updateState(.loaded(cached.snapshot, freshness: .fresh))
                }
            case .stale:
                await refresh()
            case .expired:
                await selectLocation(location, triggerFetch: true)
            }
        } else {
            await selectLocation(location, triggerFetch: true)
        }
    }

    private func validFallbackSnapshot(
        existing: WeatherSnapshot?,
        for location: WeatherLocation,
        at now: Date
    ) -> WeatherSnapshot? {
        if let existing,
           existing.location.id == location.id,
           existing.freshness(at: now, freshLimit: cache.freshLimit, staleLimit: cache.staleLimit) != .expired,
           !existing.upcoming12Hours(from: now).isEmpty {
            return existing
        }
        return cache.get(providerId: provider.id, locationId: location.id, now: now)?.snapshot
    }

    /// Internal fetch logic with timeout, cancellation check, and generation gating.
    private func performFetch(
        for location: WeatherLocation,
        generation: Int,
        existingSnapshot: WeatherSnapshot?
    ) async {
        if let s = existingSnapshot {
            updateState(.refreshing(s))
        } else {
            updateState(.loadingInitial(location))
        }

        let prov = provider
        let fetchTask = Task<WeatherSnapshot, Error> {
            try await prov.fetchForecast(for: location)
        }
        inFlightFetchTask = fetchTask

        do {
            let snapshot = try await fetchTask.value

            // Drop response if generation drifted (e.g. user selected another city mid-fetch)
            guard generation == activeGeneration else {
                return
            }
            inFlightFetchTask = nil

            let now = clock()
            guard !snapshot.upcoming12Hours(from: now).isEmpty else {
                throw WeatherError.invalidData
            }

            // Store in cache under active provider's namespace while keeping true snapshot attribution
            cache.set(snapshot: snapshot, providerId: provider.id)

            let freshness = snapshot.freshness(at: now, freshLimit: cache.freshLimit, staleLimit: cache.staleLimit)
            updateState(.loaded(snapshot, freshness: freshness))
        } catch {
            guard generation == activeGeneration else {
                return
            }
            inFlightFetchTask = nil

            let weatherErr = (error as? WeatherError) ?? .unknown(error.localizedDescription)
            if weatherErr == .cancelled {
                return
            }

            let now = clock()
            if let existing = validFallbackSnapshot(existing: existingSnapshot, for: location, at: now) {
                let age = max(0, now.timeIntervalSince(existing.fetchedAt))
                if weatherErr == .networkUnavailable {
                    // The contract (case 2) names this state "Ngoại tuyến", and it is true: the network is gone.
                    updateState(.offlineWithStale(existing, age: age))
                } else {
                    // The request failed for a reason that is not "no network" — timeout, 429, 5xx, bad payload.
                    // The cached forecast is still valid, so keep it and carry the error: calling this offline
                    // would be a false statement, and dropping it would discard good data over one failure.
                    updateState(.failedWithStale(existing, age: age, weatherErr))
                }
            } else {
                if weatherErr == .networkUnavailable {
                    updateState(.offlineNoData(location))
                } else if weatherErr == .locationDenied {
                    updateState(.locationDenied)
                } else {
                    updateState(.failed(location, weatherErr, canRetry: weatherErr.isRetryable))
                }
            }
        }
    }

    /// Searches for cities matching query with cancellation of previous search tasks.
    ///
    /// `intent` orders this call against `cancelSearch(intent:)`: both are hopped onto this actor from
    /// separate tasks, and an actor does not promise the order those tasks arrive in. Without the
    /// comparison, a cancel queued by deleting the query could land *after* the next query started and
    /// kill it.
    ///
    /// Pass `nil` (the default) from code that has no keystroke ordering to express — it is always acted
    /// on, and it never advances the ordering state. That matters: a sentinel like `.max` used as a real
    /// value makes every later finite intent look stale, which is exactly how searching died after the
    /// first close.
    public func search(query: String, intent: Int? = nil) async {
        if let intent {
            guard intent > searchIntentFence, intent >= latestSearchIntent else { return }
            latestSearchIntent = intent
        }
        // An unversioned caller carries no ordering claim, so it is never refused: silently dropping it
        // would be the very bug this fence exists to avoid. Only intent-carrying (ViewModel) calls can be
        // fenced, because only they can say which keystroke they belong to.
        inFlightSearchTask?.cancel()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanQuery.count >= 2 else {
            searchResults = []
            searchError = nil
            isSearching = false
            return
        }

        // Latest-wins for search too: a reply for a superseded query must never overwrite the current
        // one, and its failure must never be shown against a query that is not on screen any more.
        searchGeneration += 1
        let currentGen = searchGeneration

        isSearching = true
        searchError = nil
        let prov = provider
        let task = Task<[WeatherLocation], Error> {
            try await prov.searchLocations(query: cleanQuery)
        }
        inFlightSearchTask = task

        do {
            let results = try await task.value
            guard currentGen == searchGeneration, !Task.isCancelled, !task.isCancelled else { return }
            inFlightSearchTask = nil
            searchResults = results
            searchError = nil
            isSearching = false
        } catch {
            guard currentGen == searchGeneration else { return }
            inFlightSearchTask = nil
            isSearching = false
            let weatherErr = (error as? WeatherError) ?? .unknown(error.localizedDescription)
            if task.isCancelled || Task.isCancelled || weatherErr == .cancelled {
                // Cancellation is not a failure: keep whatever the newer query is doing.
                return
            }
            // A failed search is not an empty result. Empty the rows and name the group instead.
            searchResults = []
            searchError = weatherErr
        }
    }

    /// Cancels any in-flight search task and clears transient search state.
    ///
    /// `intent` is the ordering token from `search(query:intent:)`: a cancel issued for an older
    /// keystroke must not tear down a search a newer keystroke already started. `nil` means "no ordering
    /// claim" — it always cancels and never advances the ordering state.
    public func cancelSearch(intent: Int? = nil) async {
        if let intent {
            guard intent > searchIntentFence, intent >= latestSearchIntent else { return }
            latestSearchIntent = intent
        }
        searchGeneration += 1
        inFlightSearchTask?.cancel()
        inFlightSearchTask = nil
        isSearching = false
        searchResults = []
        searchError = nil
    }

    /// User explicitly requests device location.
    /// Fulfills opt-in location without telemetry or logging precise coordinates.
    public func requestCurrentLocation() async {
        activeGeneration += 1
        let currentGen = activeGeneration
        inFlightFetchTask?.cancel()
        inFlightFetchTask = nil

        do {
            let loc = try await locationService.requestCurrentLocation()
            guard !Task.isCancelled, currentGen == activeGeneration else { return }
            await selectLocation(loc, triggerFetch: true)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? WeatherError) == .cancelled {
                return
            }
            guard currentGen == activeGeneration else { return }
            updateState(.locationDenied)
        }
    }

    /// User explicitly requests location services or location was denied.
    public func handleLocationDenied() {
        updateState(.locationDenied)
    }

    /// Closes page and cancels all UI-bound async tasks, invalidating any pending location/fetch generation.
    ///
    /// `searchIntent` is the caller's high-water mark: every search whose intent is at or below it is dead
    /// (a keystroke that was still in flight when the page went away). Searches issued *after* this call
    /// carry a higher intent and work normally. Omitting it fences nothing, because a coordinator-only
    /// caller has no counter to name.
    public func close(searchIntent: Int? = nil) {
        activeGeneration += 1
        inFlightFetchTask?.cancel()
        inFlightFetchTask = nil
        // Tearing the page down fences out anything still queued behind this call, without touching what
        // comes next: the old code used `.max` here, a value no finite counter can ever beat again.
        if let searchIntent {
            searchIntentFence = max(searchIntentFence, searchIntent)
        }
        searchGeneration += 1
        inFlightSearchTask?.cancel()
        inFlightSearchTask = nil
        isSearching = false
        // The search UI is torn down with the page, so a failure from the abandoned query must not be
        // waiting to draw itself under an empty field the next time the page opens. The forecast state is
        // kept: it is what the page reopens from.
        searchResults = []
        searchError = nil

        let now = clock()
        switch state {
        case .refreshing(let s):
            let f = s.freshness(at: now, freshLimit: cache.freshLimit, staleLimit: cache.staleLimit)
            switch f {
            case .fresh:
                updateState(.loaded(s, freshness: .fresh))
            case .stale(let age):
                updateState(.offlineWithStale(s, age: age))
            case .expired:
                updateState(.unselected)
            }
        case .failedWithStale(_, _, _):
            // Already a resting state: nothing is in flight, and the failed refresh did not change the
            // cache. Keep it as it is — flattening it to `.offlineWithStale` here would relabel a quota or
            // backend failure as "Ngoại tuyến" while the network is up. `reopen()` re-reads the cache and
            // re-evaluates TTL, so the next open reports whatever is true then.
            break
        case .loadingInitial(let loc):
            if let cached = cache.get(providerId: provider.id, locationId: loc.id, now: now) {
                switch cached.freshness {
                case .fresh:
                    updateState(.loaded(cached.snapshot, freshness: .fresh))
                case .stale(let age):
                    updateState(.offlineWithStale(cached.snapshot, age: age))
                case .expired:
                    updateState(.unselected)
                }
            } else {
                updateState(.unselected)
            }
        default:
            break
        }
    }

    /// Resets coordinator selection and UI state to initial unselected state.
    ///
    /// `searchIntent` behaves exactly as in `close(searchIntent:)`.
    public func reset(searchIntent: Int? = nil) {
        activeGeneration += 1
        inFlightFetchTask?.cancel()
        inFlightFetchTask = nil
        if let searchIntent {
            searchIntentFence = max(searchIntentFence, searchIntent)
        }
        inFlightSearchTask?.cancel()
        inFlightSearchTask = nil
        isSearching = false
        searchResults = []
        searchError = nil
        selectedLocation = nil
        locationStore?.clearSavedLocation()
        updateState(.unselected)
    }
}
