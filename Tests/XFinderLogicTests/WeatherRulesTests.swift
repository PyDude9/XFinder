import XCTest

final class WeatherRulesTests: XCTestCase {

    // Helper to create a predictable location
    private func makeLocation(
        id: String = "loc-paris-fr",
        name: String = "Paris",
        region: String = "Île-de-France",
        country: String = "Pháp",
        tz: String = "Europe/Paris",
        isCurrentLocation: Bool = false
    ) -> WeatherLocation {
        WeatherLocation(
            id: id,
            name: name,
            region: region,
            country: country,
            latitude: 48.8566,
            longitude: 2.3522,
            timeZoneIdentifier: tz,
            isCurrentLocation: isCurrentLocation
        )
    }

    // Helper to create a predictable snapshot
    private func makeSnapshot(
        location: WeatherLocation,
        fetchedAt: Date,
        providerId: String = "mock-provider",
        hoursCount: Int = 24
    ) -> WeatherSnapshot {
        let attribution = WeatherAttribution(
            providerId: providerId,
            serviceName: "Mock Weather",
            legalURL: URL(string: "https://example.com/legal"),
            markSymbol: "cloud.sun.fill"
        )
        var hourly: [HourlyForecast] = []
        for i in 0..<hoursCount {
            let hourDate = fetchedAt.addingTimeInterval(TimeInterval(i * 3600))
            hourly.append(
                HourlyForecast(
                    date: hourDate,
                    temperatureCelsius: 20.0 + Double(i % 5),
                    precipitationProbability: (i % 2 == 0) ? 15.0 : nil,
                    condition: .partlyCloudy
                )
            )
        }
        return WeatherSnapshot(
            location: location,
            fetchedAt: fetchedAt,
            attribution: attribution,
            hourly: hourly
        )
    }

    // MARK: - 1. Two cities with identical names
    func testDuplicateCityNamesDisambiguation() {
        let parisFrance = makeLocation(id: "fr-paris", name: "Paris", region: "Île-de-France", country: "Pháp")
        let parisTexas = makeLocation(id: "us-paris-tx", name: "Paris", region: "Texas", country: "Hoa Kỳ")

        XCTAssertNotEqual(parisFrance.id, parisTexas.id)
        XCTAssertEqual(parisFrance.displayName, "Paris, Île-de-France, Pháp")
        XCTAssertEqual(parisTexas.displayName, "Paris, Texas, Hoa Kỳ")
    }

    // MARK: - 2. Timezone & DST formatting
    func testTimezoneAndDSTFormatting() {
        // 2026-07-15 12:00:00 UTC
        let utcDate = Date(timeIntervalSince1970: 1784116800)
        let forecast = HourlyForecast(
            date: utcDate,
            temperatureCelsius: 28.4,
            precipitationProbability: 20.0,
            condition: .clear
        )

        let tokyoTZ = TimeZone(identifier: "Asia/Tokyo")! // UTC+9
        let nyTZ = TimeZone(identifier: "America/New_York")! // EDT is UTC-4 in July

        // Tokyo: 12:00 UTC + 9 = 21:00
        XCTAssertEqual(forecast.formattedHour(using: tokyoTZ), "21:00")
        // New York (EDT): 12:00 UTC - 4 = 08:00
        XCTAssertEqual(forecast.formattedHour(using: nyTZ), "08:00")
        XCTAssertEqual(forecast.formattedTemperature(), "28°")
        XCTAssertEqual(forecast.formattedTemperature(useFahrenheit: true), "83°F")
    }

    // MARK: - 3. Freshness & Cache TTL (15 min fresh, 6 hr stale, >6 hr expired)
    func testFreshnessTransitions() {
        let baseDate = Date(timeIntervalSince1970: 100000)

        // Fetched 5 minutes ago -> Fresh
        let freshDate = baseDate.addingTimeInterval(300)
        XCTAssertEqual(
            WeatherFreshness.evaluate(fetchedAt: baseDate, now: freshDate),
            .fresh
        )

        // Fetched 20 minutes ago -> Stale (age = 1200s)
        let staleDate = baseDate.addingTimeInterval(1200)
        XCTAssertEqual(
            WeatherFreshness.evaluate(fetchedAt: baseDate, now: staleDate),
            .stale(age: 1200)
        )

        // Fetched 6 hours + 1 second ago -> Expired
        let expiredDate = baseDate.addingTimeInterval(21601)
        XCTAssertEqual(
            WeatherFreshness.evaluate(fetchedAt: baseDate, now: expiredDate),
            .expired
        )
    }

    // MARK: - 4. Upcoming 12 Hours & Past Hours Pruning
    func testUpcoming12HoursFiltersPastHours() {
        let baseDate = Date(timeIntervalSince1970: 100000)
        let loc = makeLocation()
        let snapshot = makeSnapshot(location: loc, fetchedAt: baseDate, hoursCount: 24)

        // At fetchedAt: all 24 hours are >= fetchedAt, prefix 12 returns 12
        let upcoming0 = snapshot.upcoming12Hours(from: baseDate)
        XCTAssertEqual(upcoming0.count, 12)
        XCTAssertEqual(upcoming0.first?.date, baseDate)

        // 5 hours later: first 5 hours are in the past, upcoming returns next 12
        let fiveHoursLater = baseDate.addingTimeInterval(5 * 3600)
        let upcoming5 = snapshot.upcoming12Hours(from: fiveHoursLater)
        XCTAssertEqual(upcoming5.count, 12)
        XCTAssertEqual(upcoming5.first?.date, fiveHoursLater)

        // 25 hours later: all hours are in the past -> empty
        let pastAll = baseDate.addingTimeInterval(25 * 3600)
        let upcomingEmpty = snapshot.upcoming12Hours(from: pastAll)
        XCTAssertTrue(upcomingEmpty.isEmpty)
    }

    // MARK: - 5. Cache Store: hit, miss, expired, wrong provider, max count
    func testCacheStoreRules() {
        let cache = WeatherCacheStore(maxStoredEntries: 3, freshLimit: 900, staleLimit: 21600)
        let baseDate = Date(timeIntervalSince1970: 100000)

        let loc1 = makeLocation(id: "loc1")
        let loc2 = makeLocation(id: "loc2")
        let loc3 = makeLocation(id: "loc3")
        let loc4 = makeLocation(id: "loc4")

        let snap1 = makeSnapshot(location: loc1, fetchedAt: baseDate, providerId: "providerA")
        cache.set(snapshot: snap1)

        // Cache hit fresh
        let hit = cache.get(providerId: "providerA", locationId: "loc1", now: baseDate.addingTimeInterval(300))
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.freshness, .fresh)

        // Wrong provider -> cache miss
        let wrongProvider = cache.get(providerId: "providerB", locationId: "loc1", now: baseDate)
        XCTAssertNil(wrongProvider)

        // Expired (> 6 hours) -> cache miss & evicted
        let expiredHit = cache.get(providerId: "providerA", locationId: "loc1", now: baseDate.addingTimeInterval(30000))
        XCTAssertNil(expiredHit)

        // Max capacity limit: 3 entries max
        cache.set(snapshot: makeSnapshot(location: loc1, fetchedAt: baseDate.addingTimeInterval(10)))
        cache.set(snapshot: makeSnapshot(location: loc2, fetchedAt: baseDate.addingTimeInterval(20)))
        cache.set(snapshot: makeSnapshot(location: loc3, fetchedAt: baseDate.addingTimeInterval(30)))
        XCTAssertEqual(cache.count, 3)

        // Adding 4th drops oldest (loc1)
        cache.set(snapshot: makeSnapshot(location: loc4, fetchedAt: baseDate.addingTimeInterval(40)))
        XCTAssertEqual(cache.count, 3)
        XCTAssertNil(cache.get(providerId: "mock-provider", locationId: "loc1", now: baseDate.addingTimeInterval(45)))
        XCTAssertNotNil(cache.get(providerId: "mock-provider", locationId: "loc4", now: baseDate.addingTimeInterval(45)))
    }

    private final class Box<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    // MARK: - 6. Coordinator: Zero launch requests, Fresh cache doesn't fetch
    func testCoordinatorZeroLaunchRequestsAndFreshCacheReuse() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation()

        let baseDate = Date(timeIntervalSince1970: 100000)
        let dateBox = Box(baseDate)

        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            clock: { dateBox.value }
        )

        // Coordinator initialized: 0 fetches
        let initialFetches = await provider.totalFetchCount
        XCTAssertEqual(initialFetches, 0)
        let initialState = await coordinator.state
        XCTAssertEqual(initialState, .unselected)

        // Prepopulate cache with fresh data
        let snap = makeSnapshot(location: loc, fetchedAt: baseDate, providerId: provider.id)
        cache.set(snapshot: snap)

        // Opening weather for loc with fresh cache: 0 network calls!
        dateBox.value = baseDate.addingTimeInterval(300) // 5 min later
        await coordinator.selectLocation(loc, triggerFetch: true)

        let stateAfterSelect = await coordinator.state
        XCTAssertEqual(stateAfterSelect, .loaded(snap, freshness: .fresh))
        let finalFetches = await provider.totalFetchCount
        XCTAssertEqual(finalFetches, 0) // No network calls made!
    }

    // MARK: - 7. Coordinator: Out-of-order responses A -> B -> A
    func testCoordinatorOutOfOrderCitySwitching() async {
        final class BlockableProvider: WeatherProvider, @unchecked Sendable {
            let id = "blockable"
            let attribution = WeatherAttribution(providerId: "blockable", serviceName: "Blockable")
            private let lock = NSLock()
            private var bStarted = false
            private var bReleased = false
            private var startedBContinuations: [CheckedContinuation<Void, Never>] = []
            private var releaseBContinuations: [CheckedContinuation<Void, Never>] = []

            func waitForBToStart() async {
                await withCheckedContinuation { cont in
                    lock.lock()
                    if bStarted {
                        lock.unlock()
                        cont.resume()
                    } else {
                        startedBContinuations.append(cont)
                        lock.unlock()
                    }
                }
            }

            func releaseB() {
                lock.lock()
                bReleased = true
                let toRelease = releaseBContinuations
                releaseBContinuations.removeAll()
                lock.unlock()
                for cont in toRelease {
                    cont.resume()
                }
            }

            func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
                if location.id == "locB" {
                    lock.lock()
                    bStarted = true
                    let toNotify = startedBContinuations
                    startedBContinuations.removeAll()
                    let alreadyReleased = bReleased
                    lock.unlock()
                    for cont in toNotify {
                        cont.resume()
                    }

                    if !alreadyReleased {
                        await withCheckedContinuation { cont in
                            lock.lock()
                            if bReleased {
                                lock.unlock()
                                cont.resume()
                            } else {
                                releaseBContinuations.append(cont)
                                lock.unlock()
                            }
                        }
                    }
                }

                let attribution = WeatherAttribution(providerId: "blockable", serviceName: "Blockable")
                return WeatherSnapshot(
                    location: location,
                    fetchedAt: Date(),
                    attribution: attribution,
                    hourly: [HourlyForecast(date: Date().addingTimeInterval(3600), temperatureCelsius: 25, condition: .clear)]
                )
            }

            func searchLocations(query: String) async throws -> [WeatherLocation] { [] }
        }

        let provider = BlockableProvider()
        let cache = WeatherCacheStore()
        let coordinator = WeatherCoordinator(provider: provider, cache: cache)

        let locA = makeLocation(id: "locA", name: "Hà Nội")
        let locB = makeLocation(id: "locB", name: "Đà Nẵng")

        // Select A first
        await coordinator.selectLocation(locA, triggerFetch: true)
        let stateA = await coordinator.state
        if case .loaded(let s, _) = stateA {
            XCTAssertEqual(s.location.id, "locA")
        } else {
            XCTFail("Expected loaded A, got \(stateA)")
        }

        // Start selecting B in background task
        let taskB = Task {
            await coordinator.selectLocation(locB, triggerFetch: true)
        }

        // Wait until B has started its network fetch and suspended
        await provider.waitForBToStart()

        // Switch back to A before B finishes
        await coordinator.selectLocation(locA, triggerFetch: true)

        // Now release B
        provider.releaseB()
        _ = await taskB.value

        // State MUST remain locA, never overwritten by delayed locB
        let finalState = await coordinator.state
        if case .loaded(let s, _) = finalState {
            XCTAssertEqual(s.location.id, "locA")
        } else {
            XCTFail("Expected locA, got \(finalState)")
        }
    }

    // MARK: - 8. Coordinator: Consecutive refresh coalescing
    func testConsecutiveRefreshCoalescing() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation()
        let snap = makeSnapshot(location: loc, fetchedAt: Date(), providerId: provider.id)
        await provider.setSnapshot(snap, for: loc.id)
        await provider.setDelay(0.1)

        let coordinator = WeatherCoordinator(provider: provider, cache: cache)
        await coordinator.selectLocation(loc, triggerFetch: false)

        // Fire 3 refreshes almost simultaneously
        async let r1: Void = coordinator.refresh()
        async let r2: Void = coordinator.refresh()
        async let r3: Void = coordinator.refresh()

        _ = await (r1, r2, r3)

        // Only 1 network fetch should have been performed
        let total = await provider.totalFetchCount
        XCTAssertEqual(total, 1)
    }

    // MARK: - 9. Error handling: offline, timeout, 429 rate limit, location denied
    func testCoordinatorErrorHandling() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation()

        let baseDate = Date(timeIntervalSince1970: 100000)
        let dateBox = Box(baseDate)
        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            clock: { dateBox.value }
        )

        // 1. Offline with NO cache
        await provider.setError(.networkUnavailable)
        await coordinator.selectLocation(loc, triggerFetch: true)
        var state = await coordinator.state
        XCTAssertEqual(state, .offlineNoData(loc))

        // 2. Offline WITH stale cache
        let staleFetchedAt = baseDate.addingTimeInterval(-1800) // 30 minutes before baseDate
        let snap = makeSnapshot(location: loc, fetchedAt: staleFetchedAt, providerId: provider.id)
        cache.set(snapshot: snap)

        // Select again while offline: should show offline with stale data
        await coordinator.selectLocation(loc, triggerFetch: true)
        state = await coordinator.state
        if case .offlineWithStale(let s, _) = state {
            XCTAssertEqual(s.location.id, loc.id)
        } else {
            XCTFail("Expected offlineWithStale, got \(state)")
        }

        // 3. Rate limited 429
        cache.clear()
        await provider.setError(.rateLimited)
        await coordinator.selectLocation(loc, triggerFetch: true)
        state = await coordinator.state
        XCTAssertEqual(state, .failed(loc, .rateLimited, canRetry: true))

        // 4. Location denied
        await coordinator.handleLocationDenied()
        state = await coordinator.state
        XCTAssertEqual(state, .locationDenied)
    }

    // MARK: - 9b. A failed city search must never be reported as "no cities found"

    /// The reported bug: with the network down (or a 429, or a 5xx) `search` emptied `searchResults`, and the
    /// page rendered "Không tìm thấy thành phố" — blaming the query for a transport failure. The coordinator
    /// now carries the error group, so the two cases are distinguishable at the one place that decides.
    func testSearchFailureIsDistinctFromAGenuinelyEmptyResult() async {
        let provider = MockWeatherProvider()
        await provider.setLocations([
            makeLocation(id: "hanoi", name: "Hà Nội"),
        ])
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        // A query that genuinely matches nothing: empty rows, NO error.
        await coordinator.search(query: "zzz")
        var results = await coordinator.searchResults
        var failure = await coordinator.searchError
        XCTAssertTrue(results.isEmpty)
        XCTAssertNil(failure, "an empty match must not be dressed up as a failure")

        // The same query with the network down: still no rows, but the failure is now named.
        await provider.setError(.networkUnavailable)
        await coordinator.search(query: "zzz")
        results = await coordinator.searchResults
        failure = await coordinator.searchError
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(failure, .networkUnavailable, "a transport failure must be reported as one")

        // Each group keeps its own identity, so the page can name it and offer the right retry.
        for error in [WeatherError.timeout, .rateLimited, .serverError(statusCode: 503), .invalidData] {
            await provider.setError(error)
            await coordinator.search(query: "hanoi")
            let f = await coordinator.searchError
            XCTAssertEqual(f, error, "search must carry the concrete group for \(error)")
            let rows = await coordinator.searchResults
            XCTAssertTrue(rows.isEmpty, "\(error): a failed search must not keep stale rows")
        }

        // Recovering: the next successful search clears the error.
        await provider.setError(nil)
        await coordinator.search(query: "Đà")
        await coordinator.search(query: "Hà")
        let recovered = await coordinator.searchError
        XCTAssertNil(recovered, "a successful search must clear the previous failure")
    }

    /// A cancelled search is not a failure. Closing the field (or typing a newer query) cancels the flight,
    /// and reporting that cancellation as an error would put a red row under a field the person just cleared.
    func testCancelledSearchReportsNoError() async {
        let provider = MockWeatherProvider()
        await provider.setLocations([makeLocation(id: "hanoi", name: "Hà Nội")])
        await provider.setDelay(0.2)
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        let inFlight = Task { await coordinator.search(query: "Hà") }
        try? await Task.sleep(nanoseconds: 40_000_000)
        await coordinator.cancelSearch()
        _ = await inFlight.value

        let failure = await coordinator.searchError
        XCTAssertNil(failure, "a cancelled search must not surface as an error")
        let searching = await coordinator.isSearching
        XCTAssertFalse(searching)
        let rows = await coordinator.searchResults
        XCTAssertTrue(rows.isEmpty)
    }

    /// Latest-wins (contract case 4, applied to search as well): a slow failure for an abandoned query must
    /// not overwrite the result or the error of the query actually on screen.
    func testSlowSearchFailureForAbandonedQueryDoesNotOverwriteLatest() async {
        final class ScriptedSearchProvider: WeatherProvider, @unchecked Sendable {
            let id = "scripted-search"
            let attribution = WeatherAttribution(providerId: "scripted-search", serviceName: "Scripted")
            private let lock = NSLock()
            private var _queries: [String] = []

            var queries: [String] {
                lock.lock(); defer { lock.unlock() }
                return _queries
            }

            func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
                throw WeatherError.invalidData
            }

            func searchLocations(query: String) async throws -> [WeatherLocation] {
                lock.lock(); _queries.append(query); lock.unlock()
                if query == "slow" {
                    // The abandoned query answers late, and badly.
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    throw WeatherError.timeout
                }
                return [WeatherLocation(
                    id: "fast-1",
                    name: "Đà Nẵng",
                    region: "Đà Nẵng",
                    country: "Việt Nam",
                    latitude: 16.0678,
                    longitude: 108.2208,
                    timeZoneIdentifier: "Asia/Ho_Chi_Minh"
                )]
            }
        }

        let provider = ScriptedSearchProvider()
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        let slow = Task { await coordinator.search(query: "slow") }
        try? await Task.sleep(nanoseconds: 20_000_000)
        await coordinator.search(query: "fast")
        _ = await slow.value

        let rows = await coordinator.searchResults
        XCTAssertEqual(rows.map(\.id), ["fast-1"], "the newest query's rows must survive")
        let failure = await coordinator.searchError
        XCTAssertNil(failure, "the abandoned query's timeout must not be shown against the newest query")
        XCTAssertEqual(provider.queries, ["slow", "fast"])
    }

    /// A search still queued when the page closes must not start a request afterwards.
    ///
    /// The debounce means a keystroke's search can arrive at the coordinator *after* `close()`. Closing
    /// the page must fence it out, or a request runs for a field that no longer exists. The ViewModel
    /// always hands `close` its current counter, which is what this models.
    func testSearchQueuedBehindCloseNeverStarts() async {
        let provider = MockWeatherProvider(
            stubbedLocations: [
                WeatherLocation(
                    id: "hanoi", name: "Hà Nội", region: "Hà Nội", country: "Việt Nam",
                    latitude: 21.0, longitude: 105.8, timeZoneIdentifier: "Asia/Ho_Chi_Minh"
                )
            ]
        )
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        // Keystroke 3 was on its way when the page closed.
        await coordinator.close(searchIntent: 3)
        await coordinator.search(query: "Hà", intent: 3)

        let recorded = await provider.recordedSearches
        XCTAssertTrue(recorded.isEmpty, "a search queued behind close() must never reach the provider")
        let searching = await coordinator.isSearching
        XCTAssertFalse(searching)
        let rows = await coordinator.searchResults
        XCTAssertTrue(rows.isEmpty)

        // ...but a search *after* the close (a higher intent) must still work: the fence is not permanent.
        await coordinator.search(query: "Hà", intent: 4)
        let after = await coordinator.searchResults
        XCTAssertEqual(after.map(\.id), ["hanoi"], "the fence must only kill the past, not the next search")
    }

    /// A stale cancel arriving behind a newer search must not tear down that newer search.
    func testStaleCancelDoesNotTearDownANewerSearch() async {
        let provider = MockWeatherProvider(
            stubbedLocations: [
                WeatherLocation(
                    id: "hanoi", name: "Hà Nội", region: "Hà Nội", country: "Việt Nam",
                    latitude: 21.0, longitude: 105.8, timeZoneIdentifier: "Asia/Ho_Chi_Minh"
                )
            ],
            delaySeconds: 0.2
        )
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        // Keystroke 5 starts a search; keystroke 4's cancel arrives afterwards (the inversion).
        let search = Task { await coordinator.search(query: "Hà", intent: 5) }
        try? await Task.sleep(nanoseconds: 80_000_000)
        await coordinator.cancelSearch(intent: 4)

        let stillSearching = await coordinator.isSearching
        XCTAssertTrue(stillSearching, "a cancel for an older keystroke must not stop a newer search")

        _ = await search.value
        let rows = await coordinator.searchResults
        XCTAssertEqual(
            rows.map(\.id), ["hanoi"],
            "the newer search must still land after a stale cancel arrived behind it"
        )
        let failure = await coordinator.searchError
        XCTAssertNil(failure, "a stale cancel must not turn the newer search into a failure")
    }

    /// The other half: a cancel for the *current* keystroke must still work. Without this, the fence could
    /// be "ignore every cancel" and the test above would still pass.
    func testCurrentCancelStillStopsTheSearch() async {
        let provider = MockWeatherProvider(
            stubbedLocations: [
                WeatherLocation(
                    id: "hanoi", name: "Hà Nội", region: "Hà Nội", country: "Việt Nam",
                    latitude: 21.0, longitude: 105.8, timeZoneIdentifier: "Asia/Ho_Chi_Minh"
                )
            ],
            delaySeconds: 0.2
        )
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        let search = Task { await coordinator.search(query: "Hà", intent: 5) }
        try? await Task.sleep(nanoseconds: 80_000_000)
        await coordinator.cancelSearch(intent: 5)

        let stopped = await coordinator.isSearching
        XCTAssertFalse(stopped, "a cancel for the current keystroke must stop the search")
        _ = await search.value

        let rows = await coordinator.searchResults
        XCTAssertTrue(rows.isEmpty, "the cancelled search must not paint rows")
        let failure = await coordinator.searchError
        XCTAssertNil(failure, "cancellation is not a failure")
    }

    /// The success path of latest-wins: a slow query that *succeeds* must not paint its rows over a newer
    /// query that has already answered. A transient-error test cannot cover this — the reply itself is valid.
    ///
    /// The fake deliberately ignores cancellation, which is what a real transport does: a reply already on
    /// the wire still arrives after the task is cancelled, and it is the coordinator's generation check —
    /// not the cancellation — that must stop it from being drawn.
    func testSlowSuccessfulSearchForAbandonedQueryDoesNotOverwriteLatestRows() async {
        /// Holds the abandoned reply until the test releases it, ignoring cancellation.
        final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<Void, Never>?
            private var opened = false

            func wait() async {
                await withCheckedContinuation { cont in
                    lock.lock()
                    if opened {
                        lock.unlock()
                        cont.resume()
                    } else {
                        continuation = cont
                        lock.unlock()
                    }
                }
            }

            func open() {
                lock.lock()
                opened = true
                let cont = continuation
                continuation = nil
                lock.unlock()
                cont?.resume()
            }
        }

        final class ScriptedSearchProvider: WeatherProvider, @unchecked Sendable {
            let id = "scripted-search"
            let attribution = WeatherAttribution(providerId: "scripted-search", serviceName: "Scripted")
            let gate = Gate()

            func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
                throw WeatherError.invalidData
            }

            func searchLocations(query: String) async throws -> [WeatherLocation] {
                func location(_ id: String, _ name: String) -> WeatherLocation {
                    WeatherLocation(
                        id: id, name: name, region: name, country: "Việt Nam",
                        latitude: 16.0, longitude: 108.0, timeZoneIdentifier: "Asia/Ho_Chi_Minh"
                    )
                }
                if query == "slow" {
                    // Ignores cancellation on purpose: this reply is already in flight and will land late.
                    await gate.wait()
                    return [location("slow-1", "Hà Nội")]
                }
                return [location("fast-1", "Đà Nẵng")]
            }
        }

        let provider = ScriptedSearchProvider()
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        let slow = Task { await coordinator.search(query: "slow") }
        try? await Task.sleep(nanoseconds: 60_000_000)
        await coordinator.search(query: "fast")
        // Only now does the abandoned query answer — after the newer one has already painted its rows.
        provider.gate.open()
        _ = await slow.value

        let rows = await coordinator.searchResults
        XCTAssertEqual(rows.map(\.id), ["fast-1"], "the newest query's rows must not be replaced by an older reply")
        let failure = await coordinator.searchError
        XCTAssertNil(failure)
        let searching = await coordinator.isSearching
        XCTAssertFalse(searching, "the abandoned reply must not leave the field spinning")
    }

    // MARK: - 9c. A failed fetch with valid cache keeps the forecast and names the group

    /// Contract case 2/3: a timeout, a 429 or a 5xx says nothing about whether the last forecast is still
    /// usable. Dropping six hours of good data because one request failed is worse than showing it with the
    /// failure attached — and calling it "Ngoại tuyến" when the network is up and the quota is spent is a
    /// false statement. So the snapshot stays and the error travels with it.
    func testFailedRefreshWithValidCacheKeepsForecastAndCarriesGroup() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation(id: "loc-kept", name: "Hà Nội")
        let baseDate = Date(timeIntervalSince1970: 500_000)
        let dateBox = Box(baseDate)

        await provider.setSnapshot(
            makeSnapshot(location: loc, fetchedAt: baseDate, providerId: provider.id, hoursCount: 24),
            for: loc.id
        )
        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: nil,
            clock: { dateBox.value }
        )

        // 1. Load online.
        await coordinator.selectLocation(loc, triggerFetch: true)
        let loaded = await coordinator.state
        guard case .loaded(let loadedSnapshot, .fresh) = loaded else {
            XCTFail("setup: expected a fresh online load, got \(loaded)")
            return
        }
        XCTAssertEqual(loadedSnapshot.location.id, loc.id)

        // 2. Each non-network failure must keep the forecast, with its own group and a retry that applies.
        for error in [WeatherError.timeout, .rateLimited, .serverError(statusCode: 503), .invalidData] {
            dateBox.value = baseDate.addingTimeInterval(1200) // 20 min: still inside the 6 h stale limit
            await provider.setError(error)
            await coordinator.refresh()

            let state = await coordinator.state
            guard case .failedWithStale(let snapshot, let age, let carried) = state else {
                XCTFail("\(error): expected .failedWithStale, got \(state)")
                continue
            }
            XCTAssertEqual(carried, error, "\(error): the group must reach the page")
            XCTAssertEqual(snapshot.location.id, loc.id, "\(error): the cached city must survive")
            XCTAssertEqual(age, 1200, accuracy: 1.0)
            XCTAssertFalse(
                snapshot.upcoming12Hours(from: dateBox.value).isEmpty,
                "\(error): the kept forecast must still have upcoming hours to draw"
            )
        }

        // 3. Plain offline is still plain offline: contract case 2 names it "Ngoại tuyến" and it is true.
        dateBox.value = baseDate.addingTimeInterval(1300)
        await provider.setError(.networkUnavailable)
        await coordinator.refresh()
        let offline = await coordinator.state
        guard case .offlineWithStale(let s, let age) = offline else {
            XCTFail("networkUnavailable with cache must stay .offlineWithStale, got \(offline)")
            return
        }
        XCTAssertEqual(s.location.id, loc.id)
        XCTAssertEqual(age, 1300, accuracy: 1.0)
    }

    /// The stale limit still wins: past six hours the cache is not good data, so the failure is reported
    /// with no forecast rather than keeping something expired.
    func testFailedRefreshWithExpiredCacheDropsIt() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation(id: "loc-expired", name: "Đà Nẵng")
        let baseDate = Date(timeIntervalSince1970: 600_000)
        let dateBox = Box(baseDate)

        await provider.setSnapshot(
            makeSnapshot(location: loc, fetchedAt: baseDate, providerId: provider.id, hoursCount: 24),
            for: loc.id
        )
        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: nil,
            clock: { dateBox.value }
        )
        await coordinator.selectLocation(loc, triggerFetch: true)

        dateBox.value = baseDate.addingTimeInterval(7 * 3600)
        await provider.setError(.rateLimited)
        await coordinator.refresh()

        let state = await coordinator.state
        XCTAssertEqual(
            state,
            .failed(loc, .rateLimited, canRetry: true),
            "an expired cache must not be kept; the failure stands alone"
        )
    }

    /// Retry from `.failedWithStale` must keep the forecast while it runs, not blink to a spinner — and a
    /// later success must clear the failure.
    func testRetryFromFailedWithStaleKeepsForecastThenRecovers() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation(id: "loc-retry", name: "Hà Nội")
        let baseDate = Date(timeIntervalSince1970: 700_000)
        let dateBox = Box(baseDate)

        await provider.setSnapshot(
            makeSnapshot(location: loc, fetchedAt: baseDate, providerId: provider.id, hoursCount: 24),
            for: loc.id
        )
        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: nil,
            clock: { dateBox.value }
        )
        await coordinator.selectLocation(loc, triggerFetch: true)

        dateBox.value = baseDate.addingTimeInterval(900)
        await provider.setError(.timeout)
        await coordinator.refresh()
        guard case .failedWithStale = await coordinator.state else {
            XCTFail("setup: expected .failedWithStale")
            return
        }

        // Retry: the old forecast must be visible during the flight.
        await provider.setDelay(0.15)
        await provider.setError(nil)
        let retry = Task { await coordinator.refresh() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let during = await coordinator.state
        guard case .refreshing(let kept) = during else {
            XCTFail("retry from a kept forecast must show .refreshing(kept), got \(during)")
            await retry.value
            return
        }
        XCTAssertEqual(kept.location.id, loc.id)
        await retry.value

        let after = await coordinator.state
        guard case .loaded(let fresh, let freshness) = after else {
            XCTFail("a successful retry must load, got \(after)")
            return
        }
        XCTAssertEqual(fresh.location.id, loc.id)
        // The mock keeps the snapshot's original `fetchedAt`, so this is `.loaded` with the true age of the
        // data — not `.fresh`. What matters is that the failure state is gone and the forecast is back.
        guard case .stale = freshness else {
            XCTFail("expected the kept snapshot's real age, got \(freshness)")
            return
        }
    }

    /// Closing the Island while a failure is on screen must not invent an "offline" claim or lose the cache.
    func testCloseFromFailedWithStaleKeepsCacheAndDoesNotRelabelAsOffline() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let loc = makeLocation(id: "loc-close", name: "Hà Nội")
        let baseDate = Date(timeIntervalSince1970: 800_000)
        let dateBox = Box(baseDate)

        await provider.setSnapshot(
            makeSnapshot(location: loc, fetchedAt: baseDate, providerId: provider.id, hoursCount: 24),
            for: loc.id
        )
        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: nil,
            clock: { dateBox.value }
        )
        await coordinator.selectLocation(loc, triggerFetch: true)

        // 20 minutes: past the 15-minute fresh limit, still inside the 6-hour stale limit — the range where
        // relabelling would silently happen.
        dateBox.value = baseDate.addingTimeInterval(1200)
        await provider.setError(.rateLimited)
        await coordinator.refresh()
        guard case .failedWithStale = await coordinator.state else {
            XCTFail("setup: expected .failedWithStale")
            return
        }

        await coordinator.close()
        let closed = await coordinator.state
        guard case .failedWithStale(let kept, let age, let error) = closed else {
            XCTFail("closing must not relabel a quota failure as offline, got \(closed)")
            return
        }
        XCTAssertEqual(kept.location.id, loc.id)
        XCTAssertEqual(age, 1200, accuracy: 1.0)
        XCTAssertEqual(error, .rateLimited)

        // The cache itself is untouched by the failure, so reopening re-evaluates TTL and refetches.
        await provider.setError(nil)
        await coordinator.reopen()
        let state = await coordinator.state
        guard case .loaded(let loaded, _) = state else {
            XCTFail("reopen must recover from the untouched cache, got \(state)")
            return
        }
        XCTAssertEqual(loaded.location.id, loc.id)
    }

    // MARK: - 10. Debounced search & cancellation
    func testSearchDebounceAndCancellation() async {
        let provider = MockWeatherProvider()
        let loc1 = makeLocation(id: "hanoi", name: "Hà Nội")
        let loc2 = makeLocation(id: "hagiang", name: "Hà Giang")
        await provider.setLocations([loc1, loc2])

        let coordinator = WeatherCoordinator(provider: provider)

        // Query < 2 chars does not hit provider
        await coordinator.search(query: "H")
        let resultsShort = await coordinator.searchResults
        XCTAssertTrue(resultsShort.isEmpty)
        let searchesShort = await provider.recordedSearches
        XCTAssertTrue(searchesShort.isEmpty)

        // Valid query
        await coordinator.search(query: "Hà")
        let results = await coordinator.searchResults
        XCTAssertEqual(results.count, 2)
        let searchesValid = await provider.recordedSearches
        XCTAssertEqual(searchesValid, ["Hà"])
    }

    // MARK: - 11. Closing page cancels UI tasks
    func testClosingPageCancelsTasks() async {
        let provider = MockWeatherProvider()
        await provider.setDelay(1.0) // Long delay
        let loc = makeLocation()
        let coordinator = WeatherCoordinator(provider: provider)

        let fetchTask = Task {
            await coordinator.selectLocation(loc, triggerFetch: true)
        }

        // Immediately close
        await coordinator.close()
        _ = await fetchTask.value

        let isSearching = await coordinator.isSearching
        XCTAssertFalse(isSearching)
    }

    // MARK: - 12. Location Store & Privacy (Never persist device coordinates)
    func testLocationStorePersistsManualCityAndRefusesPreciseCoordinates() {
        let store = InMemoryWeatherLocationStore()

        // 1. Manual city selection persists
        let manualCity = makeLocation(id: "loc-manual-hanoi", name: "Hà Nội", isCurrentLocation: false)
        store.saveLocation(manualCity)
        XCTAssertEqual(store.loadSavedLocation(), manualCity)

        // 2. Precise device coordinates must be rejected and never persisted
        let deviceCoords = WeatherLocation(
            id: "loc-device-gps",
            name: "Vị trí hiện tại",
            latitude: 21.0285,
            longitude: 105.8542,
            timeZoneIdentifier: "Asia/Bangkok",
            isCurrentLocation: true
        )
        store.saveLocation(deviceCoords)
        // Store must still hold the manual city, refusing device coordinates
        XCTAssertEqual(store.loadSavedLocation(), manualCity)

        store.clearSavedLocation()
        XCTAssertNil(store.loadSavedLocation())
    }

    // MARK: - 13. Coordinator initializes with saved location without fetching at launch
    func testCoordinatorInitializesWithSavedLocationWithoutFetchingAtLaunch() async {
        let provider = MockWeatherProvider()
        let manualCity = makeLocation(id: "loc-saved-tokyo", name: "Tokyo", tz: "Asia/Tokyo")
        let store = InMemoryWeatherLocationStore(initial: manualCity)

        // Init coordinator with saved location
        let coordinator = WeatherCoordinator(
            provider: provider,
            locationStore: store
        )

        let selected = await coordinator.selectedLocation
        XCTAssertEqual(selected, manualCity)

        // Verifies zero network/provider requests occurred during initialization
        let requestCount = await provider.totalFetchCount
        XCTAssertEqual(requestCount, 0, "Initializing coordinator with saved location must not trigger fetch at launch")
    }

    // MARK: - 14. Coordinator opt-in location denied falls back cleanly
    func testCoordinatorOptInLocationDeniedFallsBackToLocationDeniedState() async {
        let provider = MockWeatherProvider()
        let locationService = MockWeatherLocationService(errorToThrow: .locationDenied)

        let coordinator = WeatherCoordinator(
            provider: provider,
            locationService: locationService
        )

        await coordinator.requestCurrentLocation()

        let state = await coordinator.state
        XCTAssertEqual(state, .locationDenied)

        // Zero provider fetches on location denial
        let requestCount = await provider.totalFetchCount
        XCTAssertEqual(requestCount, 0)
    }

    // MARK: - 15. Coordinator opt-in location success fetches forecast without saving coordinates
    func testCoordinatorOptInLocationAllowedFetchesForecastWithoutPersistingCoordinates() async {
        let provider = MockWeatherProvider()
        let store = InMemoryWeatherLocationStore()
        let now = Date()

        let deviceLocation = WeatherLocation(
            id: "loc-current-gps",
            name: "Vị trí hiện tại",
            latitude: 10.7769,
            longitude: 106.7009,
            timeZoneIdentifier: "Asia/Ho_Chi_Minh",
            isCurrentLocation: true
        )
        let snapshot = makeSnapshot(location: deviceLocation, fetchedAt: now)
        await provider.setSnapshot(snapshot, for: deviceLocation.id)

        let locationService = MockWeatherLocationService(stubbedLocation: deviceLocation)

        let coordinator = WeatherCoordinator(
            provider: provider,
            locationStore: store,
            locationService: locationService,
            clock: { now }
        )

        await coordinator.requestCurrentLocation()

        let state = await coordinator.state
        if case .loaded(let snap, _) = state {
            XCTAssertEqual(snap.location.id, deviceLocation.id)
            XCTAssertTrue(snap.location.isCurrentLocation)
        } else {
            XCTFail("Expected .loaded state, got \(state)")
        }

        // Privacy check: Device coordinates must NOT be written to locationStore
        XCTAssertNil(store.loadSavedLocation(), "Device location coordinates must never be saved to persistent store")
    }

    // MARK: - 16. Cache namespace consistency & strict cross-provider isolation
    func testProviderCacheNamespaceConsistencyAndCrossProviderIsolation() async {
        final class SwitchableWrapperProvider: WeatherProvider, @unchecked Sendable {
            let id: String
            let attribution: WeatherAttribution
            var isOffline: Bool = false
            private let snapshot: WeatherSnapshot

            init(id: String, attribution: WeatherAttribution, snapshot: WeatherSnapshot) {
                self.id = id
                self.attribution = attribution
                self.snapshot = snapshot
            }

            func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
                if isOffline { throw WeatherError.networkUnavailable }
                return snapshot
            }

            func searchLocations(query: String) async throws -> [WeatherLocation] { [] }
        }

        let baseDate = Date(timeIntervalSince1970: 200_000)
        let dateBox = Box(baseDate)
        let sharedCache = WeatherCacheStore()
        let hcmc = makeLocation(id: "loc-hcmc", name: "TP. Hồ Chí Minh", region: "TP. Hồ Chí Minh", country: "Việt Nam", tz: "Asia/Ho_Chi_Minh")

        // Wrapper provider whose id ("fixture-slot") differs from snapshot attribution ("fixture"),
        // reproducing the db36f03 interactive-mock vs fixture/open-meteo mismatch.
        let fixtureAttr = WeatherAttribution(
            providerId: "fixture",
            serviceName: "XFinder Fixture",
            legalURL: URL(string: "https://open-meteo.com/")
        )
        let fixtureSnap = WeatherSnapshot(
            location: hcmc,
            fetchedAt: baseDate,
            attribution: fixtureAttr,
            hourly: (0..<24).map { i in
                HourlyForecast(
                    date: baseDate.addingTimeInterval(TimeInterval(i * 3600)),
                    temperatureCelsius: 32.0,
                    precipitationProbability: 40.0,
                    condition: .partlyCloudy
                )
            }
        )

        let wrapperProvider = SwitchableWrapperProvider(id: "fixture-slot", attribution: fixtureAttr, snapshot: fixtureSnap)
        let coordinator = WeatherCoordinator(
            provider: wrapperProvider,
            cache: sharedCache,
            locationStore: nil,
            clock: { dateBox.value }
        )

        // 1. Fetch online -> loaded with true attribution
        await coordinator.selectLocation(hcmc, triggerFetch: true)
        let loadedState = await coordinator.state
        guard case .loaded(let initialSnap, _) = loadedState else {
            XCTFail("Expected .loaded, got \(loadedState)")
            return
        }
        XCTAssertEqual(initialSnap.attribution.serviceName, "XFinder Fixture")
        XCTAssertEqual(initialSnap.attribution.providerId, "fixture")

        // 2. Go offline, advance clock 20m (stale), re-select same city -> must hit cache, NOT offlineNoData
        wrapperProvider.isOffline = true
        dateBox.value = baseDate.addingTimeInterval(1200)
        await coordinator.selectLocation(hcmc, triggerFetch: true)

        let offlineState = await coordinator.state
        guard case .offlineWithStale(let cachedSnap, let age) = offlineState else {
            XCTFail("Expected .offlineWithStale after going offline, got \(offlineState)")
            return
        }
        XCTAssertEqual(age, 1200, accuracy: 1.0)
        XCTAssertEqual(cachedSnap.upcoming12Hours(from: dateBox.value).count, 12)
        XCTAssertEqual(cachedSnap.attribution.serviceName, "XFinder Fixture")
        XCTAssertEqual(cachedSnap.attribution.providerId, "fixture")

        // 3. Cross-provider isolation: Open-Meteo coordinator sharing the SAME WeatherCacheStore
        // must NOT read fixture-slot's cached snapshot when offline.
        let offlineOpenMeteo = OpenMeteoAdapter(transport: { _ in
            throw URLError(.notConnectedToInternet)
        })
        let liveCoordinator = WeatherCoordinator(
            provider: offlineOpenMeteo,
            cache: sharedCache,
            locationStore: nil,
            clock: { dateBox.value }
        )
        await liveCoordinator.selectLocation(hcmc, triggerFetch: true)
        let isolatedState = await liveCoordinator.state
        XCTAssertEqual(isolatedState, .offlineNoData(hcmc), "Different production providers must never mix cached forecasts")
    }

    // MARK: - 17. Refresh recovers from cache after transient state & drops expired cache offline
    func testRefreshRecoversFromCacheAfterTransientStateAndDropsExpiredCache() async {
        let provider = MockWeatherProvider()
        let cache = WeatherCacheStore()
        let hcmc = makeLocation(id: "loc-hcmc", name: "TP. Hồ Chí Minh", tz: "Asia/Ho_Chi_Minh")
        let baseDate = Date(timeIntervalSince1970: 300_000)
        let dateBox = Box(baseDate)

        let snap = makeSnapshot(location: hcmc, fetchedAt: baseDate, providerId: provider.id, hoursCount: 24)
        await provider.setSnapshot(snap, for: hcmc.id)

        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: nil,
            clock: { dateBox.value }
        )

        // 1. Initial load online
        await coordinator.selectLocation(hcmc, triggerFetch: true)

        // 2. User triggers opt-in location which fails (.locationDenied), while selectedLocation remains hcmc
        await coordinator.handleLocationDenied()
        let denied = await coordinator.state
        XCTAssertEqual(denied, .locationDenied)

        // 3. Network goes offline, 10 minutes pass, user taps Refresh -> must recover cached forecast!
        await provider.setError(.networkUnavailable)
        dateBox.value = baseDate.addingTimeInterval(600)
        await coordinator.refresh()

        let recoveredState = await coordinator.state
        if case .offlineWithStale(let recovered, let age) = recoveredState {
            XCTAssertEqual(recovered.location.id, hcmc.id)
            XCTAssertEqual(age, 600, accuracy: 1.0)
        } else {
            XCTFail("Expected .offlineWithStale recovery from cache, got \(recoveredState)")
        }

        // 4. Advance past 6-hour stale limit (7 hours) while still offline -> Refresh must NOT keep expired forecast
        dateBox.value = baseDate.addingTimeInterval(7 * 3600)
        await coordinator.refresh()
        let expiredOfflineState = await coordinator.state
        XCTAssertEqual(expiredOfflineState, .offlineNoData(hcmc), "Expired snapshot (>6h) must not remain displayed on offline refresh")
    }

    // MARK: - 18. Reopen TTL re-evaluation: <=15m fresh (0 fetch), >15m stale refreshes while keeping old forecast, >6h drops expired
    func testReopenRespectsTTLPreservesForecastWhileRefreshingAndDropsExpired() async {
        final class ScriptedProvider: WeatherProvider, @unchecked Sendable {
            let id = "scripted"
            let attribution = WeatherAttribution(providerId: "scripted", serviceName: "Scripted QA")
            private let lock = NSLock()
            var fetchCount = 0
            var isOffline = false
            var nextTemp: Double = 33.0
            var clock: () -> Date

            init(clock: @escaping () -> Date) {
                self.clock = clock
            }

            private func recordAndRead() -> (Bool, Double, Date) {
                lock.lock()
                defer { lock.unlock() }
                fetchCount += 1
                return (isOffline, nextTemp, clock())
            }

            func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
                let (offline, temp, now) = recordAndRead()
                if offline { throw WeatherError.networkUnavailable }
                return WeatherSnapshot(
                    location: location,
                    fetchedAt: now,
                    attribution: attribution,
                    hourly: (0..<24).map { i in
                        HourlyForecast(
                            date: now.addingTimeInterval(TimeInterval(i * 3600)),
                            temperatureCelsius: temp,
                            precipitationProbability: 30.0,
                            condition: .partlyCloudy
                        )
                    }
                )
            }

            func searchLocations(query: String) async throws -> [WeatherLocation] { [] }
        }

        let baseDate = Date(timeIntervalSince1970: 500_000)
        let dateBox = Box(baseDate)
        let provider = ScriptedProvider(clock: { dateBox.value })
        let cache = WeatherCacheStore()
        let hcmc = makeLocation(id: "loc-hcmc", name: "TP. Hồ Chí Minh", tz: "Asia/Ho_Chi_Minh")

        let observedStates = Box<[WeatherUIState]>([])
        let coordinator = WeatherCoordinator(
            provider: provider,
            cache: cache,
            locationStore: nil,
            clock: { dateBox.value }
        )
        await coordinator.setStateChangeHandler { newState in
            observedStates.value.append(newState)
        }

        // 1. Initial load at t = 0 -> fetchCount == 1
        await coordinator.selectLocation(hcmc, triggerFetch: true)
        XCTAssertEqual(provider.fetchCount, 1)
        guard case .loaded(let snap1, .fresh) = await coordinator.state else {
            XCTFail("Expected initial .loaded(.fresh)")
            return
        }
        XCTAssertEqual(snap1.hourly.first?.temperatureCelsius, 33.0)

        // 2. Close & reopen within 15m TTL (+5m) -> 0 new fetches
        await coordinator.close()
        dateBox.value = baseDate.addingTimeInterval(300)
        observedStates.value.removeAll()
        await coordinator.reopen()
        XCTAssertEqual(provider.fetchCount, 1, "Reopening within 15m TTL must not fetch again")
        let freshReopenState = await coordinator.state
        XCTAssertEqual(freshReopenState, .loaded(snap1, freshness: .fresh))

        // 3. Close, advance +20m (1200s > 15m TTL), reopen -> must transition through .refreshing(snap1) & fetch snap2 (fetchCount == 2)
        await coordinator.close()
        dateBox.value = baseDate.addingTimeInterval(1200)
        provider.nextTemp = 29.5
        observedStates.value.removeAll()
        await coordinator.reopen()

        XCTAssertEqual(provider.fetchCount, 2, "Reopening after 20m (>15m TTL) must trigger fresh fetch")
        XCTAssertTrue(
            observedStates.value.contains(.refreshing(snap1)),
            "Reopen refresh must preserve previous forecast (.refreshing(snap1)) instead of blanking out"
        )
        guard case .loaded(let snap2, .fresh) = await coordinator.state else {
            XCTFail("Expected refreshed .loaded(.fresh)")
            return
        }
        XCTAssertEqual(snap2.hourly.first?.temperatureCelsius, 29.5)

        // 4. Close, advance another +20m (t = 2400s) while offline, reopen -> attempts refresh keeping snap2, falls back to .offlineWithStale(snap2)
        await coordinator.close()
        dateBox.value = baseDate.addingTimeInterval(2400)
        provider.isOffline = true
        observedStates.value.removeAll()
        await coordinator.reopen()

        XCTAssertEqual(provider.fetchCount, 3)
        XCTAssertTrue(observedStates.value.contains(.refreshing(snap2)))
        if case .offlineWithStale(let staleSnap, let age) = await coordinator.state {
            XCTAssertEqual(staleSnap, snap2)
            XCTAssertEqual(age, 1200, accuracy: 1.0)
        } else {
            XCTFail("Expected .offlineWithStale on offline reopen within 6h")
        }

        // 5. Close, advance +7h (>6h stale limit) while still offline, reopen -> drops expired cache -> .offlineNoData
        await coordinator.close()
        dateBox.value = baseDate.addingTimeInterval(2400 + 7 * 3600)
        observedStates.value.removeAll()
        await coordinator.reopen()

        let expiredReopenState = await coordinator.state
        XCTAssertEqual(expiredReopenState, .offlineNoData(hcmc))
    }

    // MARK: - 19. Delayed GPS completion after close() must NOT start a hidden fetch
    func testDelayedCurrentLocationCompletionAfterCloseDoesNotStartHiddenFetch() async {
        final class DelayedGPSService: WeatherLocationService, @unchecked Sendable {
            private let lock = NSLock()
            private var started = false
            private var startedContinuation: CheckedContinuation<Void, Never>?
            private var releaseContinuation: CheckedContinuation<WeatherLocation, Never>?

            func waitUntilStarted() async {
                await withCheckedContinuation { cont in
                    lock.lock()
                    if started {
                        lock.unlock()
                        cont.resume()
                    } else {
                        startedContinuation = cont
                        lock.unlock()
                    }
                }
            }

            func finish(with location: WeatherLocation) {
                lock.lock()
                let cont = releaseContinuation
                releaseContinuation = nil
                lock.unlock()
                cont?.resume(returning: location)
            }

            func requestCurrentLocation() async throws -> WeatherLocation {
                lock.lock()
                started = true
                let notify = startedContinuation
                startedContinuation = nil
                lock.unlock()
                notify?.resume()

                return await withCheckedContinuation { cont in
                    lock.lock()
                    releaseContinuation = cont
                    lock.unlock()
                }
            }
        }

        let provider = MockWeatherProvider()
        let gpsLocation = WeatherLocation(
            id: "gps-hcmc",
            name: "Vị trí hiện tại",
            latitude: 10.8231,
            longitude: 106.6297,
            timeZoneIdentifier: "Asia/Ho_Chi_Minh",
            isCurrentLocation: true
        )
        await provider.setSnapshot(makeSnapshot(location: gpsLocation, fetchedAt: Date()), for: gpsLocation.id)

        let gpsService = DelayedGPSService()
        let coordinator = WeatherCoordinator(
            provider: provider,
            locationStore: nil,
            locationService: gpsService
        )

        let gpsTask = Task {
            await coordinator.requestCurrentLocation()
        }
        await gpsService.waitUntilStarted()

        // User closes Weather / Dynamic Island BEFORE GPS finishes resolving
        await coordinator.close()

        // Late GPS completion arrives after close()
        gpsService.finish(with: gpsLocation)
        _ = await gpsTask.value

        let fetches = await provider.totalFetchCount
        XCTAssertEqual(fetches, 0, "Late GPS completion after close() must never start a hidden forecast fetch")
        let selected = await coordinator.selectedLocation
        XCTAssertNil(selected)
        let state = await coordinator.state
        XCTAssertEqual(state, .unselected)
    }

    // MARK: - 20. Failure copy: grouped, localized, never raw runtime text

    /// Every `WeatherError` the page can be handed. Listed here so a case added to the enum without copy
    /// fails this test instead of silently rendering an empty row.
    private static let allWeatherErrors: [WeatherError] = [
        .networkUnavailable, .rateLimited, .timeout, .invalidData,
        .locationDenied, .locationUnavailable, .serverError(statusCode: 503),
        .cancelled, .unknown("https://geocoding-api.open-meteo.com/v1/search?status=502"),
    ]

    /// The page used to render `error.localizedDescription`, which is the runtime's own sentence:
    /// `The operation couldn’t be completed. (XFinder.WeatherError error 2.)` — a module name, an error
    /// number and no step the person can take. `WeatherErrorPresentation` replaced it, and this locks that
    /// down: no title may be a runtime sentence, name the backend, or carry a URL/http status/Swift detail.
    func testFailurePresentationNeverLeaksRawRuntimeOrBackendText() {
        for error in Self.allWeatherErrors {
            let p = WeatherErrorPresentation(for: error)

            XCTAssertFalse(p.titleKey.isEmpty, "\(error): no headline")
            XCTAssertFalse(
                p.titleKey.localizedCaseInsensitiveContains("operation couldn"),
                "\(error): headline is the raw runtime sentence — \(p.titleKey)"
            )
            XCTAssertFalse(
                p.titleKey.localizedCaseInsensitiveContains("WeatherError"),
                "\(error): headline names the Swift error type — \(p.titleKey)"
            )

            for text in [p.titleKey, p.hintKey].compactMap({ $0 }) {
                XCTAssertFalse(text.localizedCaseInsensitiveContains("http"), "\(error): exposes a URL — \(text)")
                XCTAssertFalse(text.localizedCaseInsensitiveContains("www."), "\(error): exposes a URL — \(text)")
                XCTAssertFalse(text.localizedCaseInsensitiveContains("open-meteo"), "\(error): names the backend — \(text)")
                XCTAssertFalse(text.localizedCaseInsensitiveContains("weatherkit"), "\(error): names the backend — \(text)")
                XCTAssertFalse(text.localizedCaseInsensitiveContains("status"), "\(error): exposes an HTTP status — \(text)")
                // The 503 in `.serverError(statusCode:)` must not reach the person.
                XCTAssertFalse(text.contains("503"), "\(error): prints the status code — \(text)")
                // The `.unknown(String)` payload is often a transport sentence; it must never be echoed.
                XCTAssertFalse(text.contains("status=502"), "\(error): echoes the unknown payload — \(text)")
            }
        }
    }

    /// Grouping: each failure gets its own headline, and the pairs a person confuses most
    /// (network vs timeout, quota vs backend) must not collapse onto the same words.
    func testFailurePresentationGroupsFailuresDistinctly() {
        let titles = Self.allWeatherErrors.map { WeatherErrorPresentation(for: $0).titleKey }

        XCTAssertNotEqual(
            WeatherErrorPresentation(for: .networkUnavailable).titleKey,
            WeatherErrorPresentation(for: .timeout).titleKey,
            "a timeout must not read as a plain network failure"
        )
        XCTAssertNotEqual(
            WeatherErrorPresentation(for: .rateLimited).titleKey,
            WeatherErrorPresentation(for: .serverError(statusCode: 503)).titleKey,
            "quota and a broken backend need different next steps"
        )
        XCTAssertEqual(
            WeatherErrorPresentation(for: .locationDenied).titleKey,
            WeatherErrorPresentation(for: .locationUnavailable).titleKey,
            "the page shows one permission message; both cases mean the same thing to the person"
        )
        XCTAssertEqual(
            WeatherErrorPresentation(for: .unknown("x")).titleKey,
            WeatherErrorPresentation(for: .unknown("y")).titleKey,
            "the fallback headline must not depend on the payload"
        )
        // 9 cases, 8 distinct headlines (denied == unavailable).
        XCTAssertEqual(Set(titles).count, 8, "unexpected grouping: \(Set(titles).sorted())")
    }

    /// Retry is a promise, so it appears only where repeating the request can help — and it must
    /// agree with the coordinator, which decides `canRetry` from the same property.
    func testFailurePresentationRetryMatchesCoordinatorRetryability() {
        for error in Self.allWeatherErrors {
            XCTAssertEqual(
                WeatherErrorPresentation(for: error).canRetry,
                error.isRetryable,
                "\(error): the button and the state disagree about retry"
            )
        }
        XCTAssertFalse(WeatherErrorPresentation(for: .invalidData).canRetry)
        XCTAssertFalse(WeatherErrorPresentation(for: .cancelled).canRetry)
        XCTAssertFalse(WeatherErrorPresentation(for: .locationDenied).canRetry)
        XCTAssertTrue(WeatherErrorPresentation(for: .networkUnavailable).canRetry)
        XCTAssertTrue(WeatherErrorPresentation(for: .timeout).canRetry)
        XCTAssertTrue(WeatherErrorPresentation(for: .rateLimited).canRetry)
        XCTAssertTrue(WeatherErrorPresentation(for: .serverError(statusCode: 500)).canRetry)
    }

    /// Every key the row can draw must exist in the store, or `L10n.t` falls back to Vietnamese and the
    /// English page shows Vietnamese — the bug shape `L10nTests` documents. Read from the real JSON so a
    /// key renamed on one side alone fails here.
    func testFailurePresentationKeysExistInTheL10nStore() throws {
        let entries = try Self.l10nEntries()

        for error in Self.allWeatherErrors {
            let p = WeatherErrorPresentation(for: error)
            for key in [p.titleKey, p.hintKey].compactMap({ $0 }) {
                let entry = entries[key]
                let en = entry?["en"] as? String ?? ""
                XCTAssertNotNil(entry, "\(error): missing L10n key \(key)")
                XCTAssertFalse(en.isEmpty, "\(error): L10n key \(key) has no English")
                XCTAssertNotEqual(en, key, "\(error): L10n key \(key) is untranslated")
                XCTAssertEqual(entry?["scope"] as? String, "sentence",
                               "\(error): \(key) is drawn on its own, so it must be a sentence")
            }
        }
    }

    /// The search context draws its own hint keys, so they need the same guarantee — this is the check that
    /// would have caught the missing `Kiểm tra Wi-Fi hoặc mạng rồi thử lại.` before it shipped.
    func testSearchContextKeysExistInTheL10nStore() throws {
        let entries = try Self.l10nEntries()

        for error in Self.allWeatherErrors {
            let p = WeatherErrorPresentation(for: error, context: .search)
            for key in [p.titleKey, p.hintKey].compactMap({ $0 }) {
                let entry = entries[key]
                XCTAssertNotNil(entry, "\(error) [search]: missing L10n key \(key)")
                XCTAssertFalse((entry?["en"] as? String ?? "").isEmpty, "\(error) [search]: \(key) has no English")
                XCTAssertNotEqual(entry?["en"] as? String, key, "\(error) [search]: \(key) is untranslated")
            }
        }
    }

    /// A hint that names a control must only appear where that control exists. Under the search field there
    /// is no Refresh button, and "choose a city" answers a permission failure search cannot produce — so the
    /// headline stands alone there instead of sending the person looking for something that is not on screen.
    func testSearchContextDropsHintsThatNameControlsItDoesNotHave() {
        for error in [WeatherError.invalidData, .unknown("x"), .locationDenied, .locationUnavailable] {
            let forecast = WeatherErrorPresentation(for: error)
            let search = WeatherErrorPresentation(for: error, context: .search)
            XCTAssertNotNil(forecast.hintKey, "\(error): the forecast body should still explain the next step")
            XCTAssertNil(search.hintKey, "\(error): search must not name a control it does not have")
            // Only the hint changes; the headline, icon and retry decision are the same failure.
            XCTAssertEqual(search.titleKey, forecast.titleKey)
            XCTAssertEqual(search.symbol, forecast.symbol)
            XCTAssertEqual(search.canRetry, forecast.canRetry)
        }

        // Network and quota advice is location-independent, so it survives in both places.
        for error in [WeatherError.networkUnavailable, .timeout, .rateLimited, .serverError(statusCode: 500)] {
            XCTAssertEqual(
                WeatherErrorPresentation(for: error, context: .search).hintKey,
                WeatherErrorPresentation(for: error).hintKey,
                "\(error): this hint is useful under the search field too"
            )
        }
    }

    /// Every `WeatherCondition.accessibilityLabelKey` must resolve cleanly to a translated English entry in
    /// `L10n.strings.json` so VoiceOver never falls back to raw Vietnamese in English mode.
    func testConditionAccessibilityKeysExistInTheL10nStore() throws {
        let entries = try Self.l10nEntries()

        for condition in WeatherCondition.allCases {
            let key = condition.accessibilityLabelKey
            let entry = entries[key]
            let en = entry?["en"] as? String ?? ""
            XCTAssertNotNil(entry, "\(condition): missing L10n key \(key)")
            XCTAssertFalse(en.isEmpty, "\(condition): L10n key \(key) has no English")
            XCTAssertNotEqual(en, key, "\(condition): L10n key \(key) is untranslated")
            XCTAssertEqual(entry?["scope"] as? String, "sentence",
                           "\(condition): \(key) must use sentence scope")
        }
    }

    private static func l10nEntries() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // XFinderLogicTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("XFinder/Resources/L10n.strings.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["entries"] as? [String: [String: Any]])
    }
}
