import XCTest
import Combine

@MainActor
final class WeatherViewModelTests: XCTestCase {

    private func makeLocation(
        id: String = "loc-hanoi",
        name: String = "Hà Nội"
    ) -> WeatherLocation {
        WeatherLocation(
            id: id,
            name: name,
            region: name,
            country: "Việt Nam",
            latitude: 21.0285,
            longitude: 105.8542,
            timeZoneIdentifier: "Asia/Bangkok"
        )
    }

    private func makeSnapshot(
        location: WeatherLocation,
        fetchedAt: Date = Date(),
        temp: Double = 28.0
    ) -> WeatherSnapshot {
        WeatherSnapshot(
            location: location,
            fetchedAt: fetchedAt,
            attribution: WeatherAttribution(providerId: "mock", serviceName: "Mock"),
            hourly: [
                HourlyForecast(date: fetchedAt.addingTimeInterval(3600), temperatureCelsius: temp, condition: .clear)
            ]
        )
    }

    // MARK: - 1. Immediate loading feedback & clearing of old city forecast
    func testSelectLocationImmediatelyShowsLoadingAndClearsOldForecast() async {
        let locA = makeLocation(id: "locA", name: "Hà Nội")
        let locB = makeLocation(id: "locB", name: "Đà Nẵng")

        let snapA = makeSnapshot(location: locA, temp: 25.0)
        let snapB = makeSnapshot(location: locB, temp: 32.0)

        let mockProvider = MockWeatherProvider(
            stubbedSnapshots: ["locA": snapA, "locB": snapB],
            delaySeconds: 0.1 // 100ms simulated network delay
        )
        let coordinator = WeatherCoordinator(provider: mockProvider)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        // 1. Load city A first
        viewModel.selectLocation(locA)
        // Wait for city A to complete
        try? await Task.sleep(nanoseconds: 150_000_000)
        await viewModel.syncState()

        if case .loaded(let s, _) = viewModel.state {
            XCTAssertEqual(s.location.id, "locA")
            XCTAssertEqual(s.hourly.first?.temperatureCelsius, 25.0)
        } else {
            XCTFail("Expected loaded locA, got \(viewModel.state)")
        }

        // 2. Select city B: MUST immediately show loadingInitial(locB) and NOT locA!
        viewModel.selectLocation(locB)

        // Immediately check state on MainActor before waiting
        let immediateState = viewModel.state
        XCTAssertEqual(immediateState, .loadingInitial(locB))

        // Wait for B fetch to complete
        try? await Task.sleep(nanoseconds: 150_000_000)
        await viewModel.syncState()

        let finalState = viewModel.state
        if case .loaded(let s, _) = finalState {
            XCTAssertEqual(s.location.id, "locB")
            XCTAssertEqual(s.hourly.first?.temperatureCelsius, 32.0)
        } else {
            XCTFail("Expected loaded locB, got \(finalState)")
        }
    }

    // MARK: - 2. Immediate refreshing state feedback
    func testRefreshImmediatelyShowsRefreshingWithExistingSnapshot() async {
        let loc = makeLocation()
        let snap = makeSnapshot(location: loc, temp: 28.0)
        let mockProvider = MockWeatherProvider(
            stubbedSnapshots: [loc.id: snap],
            delaySeconds: 0.1
        )
        let coordinator = WeatherCoordinator(provider: mockProvider)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.selectLocation(loc)
        try? await Task.sleep(nanoseconds: 150_000_000)
        await viewModel.syncState()

        // Verify loaded
        guard case .loaded(let initialSnap, _) = viewModel.state else {
            XCTFail("Expected loaded state")
            return
        }
        XCTAssertEqual(initialSnap.location.id, loc.id)

        // Trigger refresh
        viewModel.refresh()

        // MUST immediately transition to .refreshing(initialSnap)
        let immediateRefreshState = viewModel.state
        XCTAssertEqual(immediateRefreshState, .refreshing(initialSnap))

        // Wait for refresh to complete
        try? await Task.sleep(nanoseconds: 150_000_000)
        await viewModel.syncState()

        guard case .loaded(let refreshedSnap, _) = viewModel.state else {
            XCTFail("Expected loaded state after refresh")
            return
        }
        XCTAssertEqual(refreshedSnap.location.id, loc.id)
    }

    // MARK: - 3. Rapid A -> B -> A switching never shows stale B data
    func testRapidCitySwitchingNeverShowsStaleData() async {
        let locA = makeLocation(id: "locA", name: "Hà Nội")
        let locB = makeLocation(id: "locB", name: "Đà Nẵng")

        let snapA = makeSnapshot(location: locA, temp: 22.0)
        let snapB = makeSnapshot(location: locB, temp: 35.0)

        let mockProvider = MockWeatherProvider(
            stubbedSnapshots: ["locA": snapA, "locB": snapB],
            delaySeconds: 0.2 // Slow delay
        )
        let coordinator = WeatherCoordinator(provider: mockProvider)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        // Select A, wait for finish
        viewModel.selectLocation(locA)
        try? await Task.sleep(nanoseconds: 250_000_000)
        await viewModel.syncState()

        // Rapidly switch to B
        viewModel.selectLocation(locB)
        XCTAssertEqual(viewModel.state, .loadingInitial(locB))

        // Then switch back to A before B finishes (after 50ms)
        try? await Task.sleep(nanoseconds: 50_000_000)
        viewModel.selectLocation(locA)
        XCTAssertEqual(viewModel.state, .loadingInitial(locA))

        // Wait for all in-flight work to settle
        try? await Task.sleep(nanoseconds: 300_000_000)
        await viewModel.syncState()

        // State MUST be locA, never overwritten by locB
        if case .loaded(let s, _) = viewModel.state {
            XCTAssertEqual(s.location.id, "locA")
            XCTAssertEqual(s.hourly.first?.temperatureCelsius, 22.0)
        } else {
            XCTFail("Expected locA, got \(viewModel.state)")
        }
    }

    // MARK: - 4. Close cancels pending tasks and onAppear re-syncs
    func testCloseCancelsPendingTasksAndOnAppearResyncs() async {
        let loc = makeLocation()
        let snap = makeSnapshot(location: loc)
        let mockProvider = MockWeatherProvider(
            stubbedSnapshots: [loc.id: snap],
            delaySeconds: 1.0 // Long delay
        )
        let coordinator = WeatherCoordinator(provider: mockProvider)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.selectLocation(loc)
        XCTAssertEqual(viewModel.state, .loadingInitial(loc))

        // Immediately close view (e.g. notch collapses)
        viewModel.close()

        // Open again after tasks settled
        viewModel.onAppear()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await viewModel.syncState()

        XCTAssertFalse(viewModel.isShowingSearch)
        XCTAssertFalse(viewModel.isSearching)
    }

    // MARK: - 5. Opt-in current location transitions to denied state when not permitted
    func testRequestCurrentLocationTransitionsToDeniedState() async {
        let mockProvider = MockWeatherProvider()
        let locationService = MockWeatherLocationService(errorToThrow: .locationDenied)
        let coordinator = WeatherCoordinator(
            provider: mockProvider,
            locationService: locationService
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.requestCurrentLocation()
        try? await Task.sleep(nanoseconds: 50_000_000)
        await viewModel.syncState()

        XCTAssertEqual(viewModel.state, .locationDenied)
    }

    // MARK: - 6. Fixture -> Offline -> Refresh preserves 12h forecast, age, and attribution
    func testFixtureToOfflineRefreshPreservesForecastAgeAndAttribution() async {
        final class ClockBox: @unchecked Sendable {
            var now: Date
            init(_ now: Date) { self.now = now }
        }

        let baseNow = Date()
        let clockBox = ClockBox(baseNow)
        let hcmc = WeatherLocation(
            id: "fixture:hcmc",
            name: "TP. Hồ Chí Minh",
            region: "Hồ Chí Minh",
            country: "Việt Nam",
            latitude: 10.8231,
            longitude: 106.6297,
            timeZoneIdentifier: "Asia/Ho_Chi_Minh"
        )
        let fixtureAttr = WeatherAttribution(
            providerId: "mock-provider",
            serviceName: "XFinder Fixture",
            legalURL: nil,
            markSymbol: "cloud.sun.fill"
        )
        let snap = WeatherSnapshot(
            location: hcmc,
            fetchedAt: baseNow,
            attribution: fixtureAttr,
            hourly: (0..<25).map { i in
                HourlyForecast(
                    date: baseNow.addingTimeInterval(TimeInterval(i * 3600)),
                    temperatureCelsius: 33.0,
                    precipitationProbability: 60.0,
                    condition: .thunderstorm
                )
            }
        )

        let mockProvider = MockWeatherProvider(stubbedSnapshots: [hcmc.id: snap])
        let cache = WeatherCacheStore()
        let coordinator = WeatherCoordinator(
            provider: mockProvider,
            cache: cache,
            locationStore: nil,
            clock: { clockBox.now }
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.selectLocation(hcmc)
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()

        guard case .loaded(let loadedSnap, .fresh) = viewModel.state else {
            XCTFail("Expected .loaded(.fresh), got \(viewModel.state)")
            return
        }
        XCTAssertEqual(loadedSnap.upcoming12Hours(from: clockBox.now).count, 12)
        XCTAssertEqual(loadedSnap.attribution.serviceName, "XFinder Fixture")

        // Switch to offline & advance clock 12 minutes
        await mockProvider.setError(.networkUnavailable)
        clockBox.now = baseNow.addingTimeInterval(720)

        viewModel.refresh()
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()

        guard case .offlineWithStale(let staleSnap, let age) = viewModel.state else {
            XCTFail("Expected .offlineWithStale after offline refresh, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(age, 720, accuracy: 2.0)
        XCTAssertEqual(staleSnap.upcoming12Hours(from: clockBox.now).count, 12)
        XCTAssertEqual(staleSnap.attribution.serviceName, "XFinder Fixture")
        XCTAssertTrue(viewModel.freshnessDescription.contains("12"))
    }

    // MARK: - 7. Live Open-Meteo (fake transport) -> Offline Refresh & Empty-Cache Offline
    func testLiveOpenMeteoFakeTransportToOfflineRefreshAndEmptyCacheOffline() async {
        final class TransportSwitch: @unchecked Sendable {
            var isOffline = false
            var now: Date
            init(now: Date) { self.now = now }
        }

        let baseNow = Date()
        let state = TransportSwitch(now: baseNow)
        let hcmc = WeatherLocation(
            id: "open-meteo:1566083",
            name: "Thành phố Hồ Chí Minh",
            region: "Thành phố Hồ Chí Minh",
            country: "Việt Nam",
            latitude: 10.823,
            longitude: 106.6296,
            timeZoneIdentifier: "Asia/Ho_Chi_Minh"
        )
        let danang = WeatherLocation(
            id: "open-meteo:1583992",
            name: "Đà Nẵng",
            region: "Đà Nẵng",
            country: "Việt Nam",
            latitude: 16.0678,
            longitude: 108.2208,
            timeZoneIdentifier: "Asia/Ho_Chi_Minh"
        )

        let startEpoch = Int(baseNow.timeIntervalSince1970)
        let timesJSON = (0..<25).map { startEpoch + ($0 * 3600) }.map(String.init).joined(separator: ",")
        let tempsJSON = (0..<25).map { String(format: "%.1f", 30.0 + Double($0 % 4)) }.joined(separator: ",")
        let precipsJSON = (0..<25).map { "\(($0 * 10) % 80)" }.joined(separator: ",")
        let codesJSON = (0..<25).map { "\($0 % 3)" }.joined(separator: ",")
        let payload = """
        {
          "hourly": {
            "time": [\(timesJSON)],
            "temperature_2m": [\(tempsJSON)],
            "precipitation_probability": [\(precipsJSON)],
            "weather_code": [\(codesJSON)]
          }
        }
        """.data(using: .utf8)!

        let adapter = OpenMeteoAdapter(transport: { request in
            if state.isOffline {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.open-meteo.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (payload, response)
        }, clock: { state.now })

        let cache = WeatherCacheStore()
        let coordinator = WeatherCoordinator(
            provider: adapter,
            cache: cache,
            locationStore: nil,
            clock: { state.now }
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        // 1. Load TP.HCM online via OpenMeteoAdapter
        viewModel.selectLocation(hcmc)
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()

        guard case .loaded(let liveSnap, _) = viewModel.state else {
            XCTFail("Expected .loaded from OpenMeteoAdapter, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(liveSnap.upcoming12Hours(from: state.now).count, 12)
        XCTAssertEqual(liveSnap.attribution.providerId, "open-meteo")
        XCTAssertEqual(liveSnap.attribution.serviceName, "Open-Meteo")
        XCTAssertEqual(liveSnap.attribution.legalURL, URL(string: "https://open-meteo.com/"))

        // 2. Flip transport to Offline, advance 18 minutes, Refresh -> keeps forecast, age, and Open-Meteo attribution
        state.isOffline = true
        state.now = baseNow.addingTimeInterval(1080)

        viewModel.refresh()
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()

        guard case .offlineWithStale(let offlineSnap, let age) = viewModel.state else {
            XCTFail("Expected .offlineWithStale after Open-Meteo -> Offline -> Refresh, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(age, 1080, accuracy: 5.0)
        XCTAssertEqual(offlineSnap.upcoming12Hours(from: state.now).count, 12)
        XCTAssertEqual(offlineSnap.attribution.providerId, "open-meteo")
        XCTAssertEqual(offlineSnap.attribution.serviceName, "Open-Meteo")
        XCTAssertEqual(offlineSnap.attribution.legalURL, URL(string: "https://open-meteo.com/"))
        XCTAssertTrue(viewModel.freshnessDescription.contains("18"))

        // 3. Select uncached Đà Nẵng while offline -> must report .offlineNoData
        viewModel.selectLocation(danang)
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()
        XCTAssertEqual(viewModel.state, .offlineNoData(danang))

        // Refresh on empty-cache city while offline -> stays .offlineNoData
        viewModel.refresh()
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()
        XCTAssertEqual(viewModel.state, .offlineNoData(danang))

        // 4. Switch back to cached TP.HCM while STILL offline -> restores TP.HCM stale cache & Open-Meteo attribution!
        viewModel.selectLocation(hcmc)
        try? await Task.sleep(nanoseconds: 60_000_000)
        await viewModel.syncState()
        guard case .offlineWithStale(let restoredSnap, _) = viewModel.state else {
            XCTFail("Expected .offlineWithStale when returning to cached TP.HCM offline, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(restoredSnap.location.id, hcmc.id)
        XCTAssertEqual(restoredSnap.attribution.serviceName, "Open-Meteo")
    }

    // MARK: - 8. Search open/close lifecycle fires host key-focus callback
    func testSearchOpenCloseNotifiesFocusCallback() async {
        let mockProvider = MockWeatherProvider()
        let coordinator = WeatherCoordinator(provider: mockProvider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        var events: [Bool] = []
        viewModel.onSearchVisibilityChanged = { events.append($0) }

        viewModel.openSearch()
        XCTAssertTrue(viewModel.isShowingSearch)
        viewModel.openSearch() // idempotent when already open
        XCTAssertEqual(events, [true])

        viewModel.closeSearch()
        XCTAssertFalse(viewModel.isShowingSearch)
        XCTAssertEqual(events, [true, false])

        // Closing page while search is open also notifies host to release search composing state
        viewModel.toggleSearch()
        XCTAssertTrue(viewModel.isShowingSearch)
        viewModel.close()
        XCTAssertFalse(viewModel.isShowingSearch)
        XCTAssertEqual(events, [true, false, true, false])
    }

    // MARK: - 9. Reopen after >15m TTL triggers refresh while keeping previous forecast on screen
    func testOnAppearAfterStaleTTLRefreshesWhilePreservingPreviousForecast() async {
        final class ClockBox: @unchecked Sendable {
            var now: Date
            init(_ now: Date) { self.now = now }
        }

        let baseNow = Date(timeIntervalSince1970: 600_000)
        let clockBox = ClockBox(baseNow)
        let hcmc = makeLocation(id: "qa-fixture:hcmc", name: "TP. Hồ Chí Minh")
        let snap1 = WeatherSnapshot(
            location: hcmc,
            fetchedAt: baseNow,
            attribution: WeatherAttribution(providerId: "mock-provider", serviceName: "Mock"),
            hourly: (0..<24).map { i in
                HourlyForecast(date: baseNow.addingTimeInterval(TimeInterval(i * 3600)), temperatureCelsius: 33.0, condition: .thunderstorm)
            }
        )
        let mockProvider = MockWeatherProvider(stubbedSnapshots: [hcmc.id: snap1], delaySeconds: 0.08)
        let coordinator = WeatherCoordinator(
            provider: mockProvider,
            cache: WeatherCacheStore(),
            locationStore: nil,
            clock: { clockBox.now }
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        // 1. Load TP.HCM -> Fetches == 1
        viewModel.selectLocation(hcmc)
        try? await Task.sleep(nanoseconds: 140_000_000)
        await viewModel.syncState()
        let fetches1 = await mockProvider.totalFetchCount
        XCTAssertEqual(fetches1, 1)

        // 2. Close Island, advance clock +20m, prepare refreshed snapshot snap2
        viewModel.close()
        try? await Task.sleep(nanoseconds: 30_000_000)

        let later = baseNow.addingTimeInterval(20 * 60)
        clockBox.now = later
        let snap2 = WeatherSnapshot(
            location: hcmc,
            fetchedAt: later,
            attribution: WeatherAttribution(providerId: "mock-provider", serviceName: "Mock"),
            hourly: (0..<24).map { i in
                HourlyForecast(date: later.addingTimeInterval(TimeInterval(i * 3600)), temperatureCelsius: 30.0, condition: .clear)
            }
        )
        await mockProvider.setSnapshot(snap2, for: hcmc.id)

        // 3. Reopen Weather -> mid-flight state keeps snap1 (.refreshing(snap1)), then settles to snap2 with Fetches == 2
        viewModel.onAppear()
        try? await Task.sleep(nanoseconds: 25_000_000)
        XCTAssertEqual(viewModel.state, .refreshing(snap1), "Previous forecast must stay visible while refreshing on stale reopen")

        try? await Task.sleep(nanoseconds: 120_000_000)
        await viewModel.syncState()
        let fetches2 = await mockProvider.totalFetchCount
        XCTAssertEqual(fetches2, 2, "Reopen after +20m TTL must perform a second fetch")
        if case .loaded(let refreshed, .fresh) = viewModel.state {
            XCTAssertEqual(refreshed.hourly.first?.temperatureCelsius, 30.0)
        } else {
            XCTFail("Expected .loaded(.fresh) with snap2, got \(viewModel.state)")
        }
    }

    // MARK: - 10. Closing search cancels in-flight coordinator search
    func testCloseSearchCancelsInFlightCoordinatorSearch() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let mockProvider = MockWeatherProvider(stubbedLocations: [hanoi], delaySeconds: 0.25)
        let coordinator = WeatherCoordinator(provider: mockProvider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.openSearch()
        viewModel.onSearchTextChanged("Hà")
        // Wait past 300ms debounce so coordinator.search is actively in-flight
        try? await Task.sleep(nanoseconds: 340_000_000)

        viewModel.closeSearch()
        try? await Task.sleep(nanoseconds: 40_000_000)

        let coordSearching = await coordinator.isSearching
        XCTAssertFalse(coordSearching, "Coordinator in-flight search must be cancelled when search UI closes")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    // MARK: - 11. A failed search is not "no cities found" at the ViewModel boundary

    /// The reported bug end to end through the ViewModel: the page decides between "no cities found" and a
    /// failure from `searchError`, so the ViewModel must carry it across the actor hop and clear it again
    /// when the transport recovers. Without this, an offline lookup still renders "Không tìm thấy thành phố".
    func testViewModelCarriesSearchErrorAndClearsItOnRecovery() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let mockProvider = MockWeatherProvider(stubbedLocations: [hanoi])
        let coordinator = WeatherCoordinator(provider: mockProvider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        // 1. Genuinely empty result: no error, so the page may say "no cities found".
        viewModel.openSearch()
        viewModel.onSearchTextChanged("zzz")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertNil(viewModel.searchError, "an empty match must stay an empty match")

        // 2. The same query while the network is down: rows stay empty but the failure is named.
        await mockProvider.setError(.networkUnavailable)
        viewModel.onSearchTextChanged("Hà Nội")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        XCTAssertEqual(
            viewModel.searchError,
            .networkUnavailable,
            "a transport failure must reach the ViewModel, not be flattened into an empty result"
        )

        // 3. Network back: the next search clears both the rows problem and the error.
        await mockProvider.setError(nil)
        viewModel.onSearchTextChanged("Hà")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["hanoi"])
        XCTAssertNil(viewModel.searchError, "a successful search must clear the failure")

        // 4. A one-character query is not a failure either; it never searches.
        viewModel.onSearchTextChanged("H")
        XCTAssertNil(viewModel.searchError)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }

    /// Each group keeps its identity through the ViewModel, so the page can name it and gate its Retry —
    /// a quota exhaustion must not be shown to the person as a broken Wi-Fi.
    func testViewModelPreservesEachSearchFailureGroup() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let mockProvider = MockWeatherProvider(stubbedLocations: [hanoi])
        let coordinator = WeatherCoordinator(provider: mockProvider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)
        viewModel.openSearch()

        for error in [WeatherError.timeout, .rateLimited, .serverError(statusCode: 503), .invalidData] {
            await mockProvider.setError(error)
            viewModel.onSearchTextChanged("Hà Nội")
            try? await Task.sleep(nanoseconds: 420_000_000)
            XCTAssertEqual(viewModel.searchError, error, "\(error) must survive the ViewModel hop")
            XCTAssertTrue(viewModel.searchResults.isEmpty)
        }
    }

    // MARK: - 13. Deleting the query mid-request stops the lookup, not just the ViewModel's task

    /// A provider that ignores cancellation, the way a real transport does: a fetch already on the wire
    /// still resolves, and `Task.cancel()` only makes the answer unwanted — it does not free the request.
    /// Records how many searches it was actually asked to run, which is what "the request kept running "
    /// means when the answer is thrown away anyway.
    final class StubbornSearchProvider: WeatherProvider, @unchecked Sendable {
        let id = "stubborn"
        let attribution = WeatherAttribution(providerId: "stubborn", serviceName: "Stubborn")

        private let lock = NSLock()
        private var _queries: [String] = []
        private var _completed: [String] = []
        private var _cancelledAtReturn: [String] = []
        private var started = 0
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        var queries: [String] { lock.lock(); defer { lock.unlock() }; return _queries }
        var completed: [String] { lock.lock(); defer { lock.unlock() }; return _completed }
        /// Queries whose request was cancelled while it was still on the wire.
        var cancelledAtReturn: [String] { lock.lock(); defer { lock.unlock() }; return _cancelledAtReturn }

        /// Lets every pending search return, ignoring cancellation.
        func release() {
            lock.lock()
            released = true
            let pending = waiters
            waiters = []
            lock.unlock()
            pending.forEach { $0.resume() }
        }

        private func waitIgnoringCancellation() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if released {
                    lock.unlock()
                    cont.resume()
                } else {
                    waiters.append(cont)
                    lock.unlock()
                }
            }
        }

        func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
            throw WeatherError.invalidData
        }

        func searchLocations(query: String) async throws -> [WeatherLocation] {
            lock.lock()
            _queries.append(query)
            started += 1
            lock.unlock()

            // Deliberately no early bail-out: this reply is already in flight and a real transport still
            // gets told to cancel the connection. Recording that is the point of the fake.
            await waitIgnoringCancellation()

            let cancelled = Task.isCancelled
            lock.lock()
            _completed.append(query)
            if cancelled { _cancelledAtReturn.append(query) }
            lock.unlock()

            return [
                WeatherLocation(
                    id: "result-\(query)", name: query, region: query, country: "Việt Nam",
                    latitude: 16.0, longitude: 108.0, timeZoneIdentifier: "Asia/Ho_Chi_Minh"
                )
            ]
        }
    }

    /// The reviewed bug: typing "Hà" and then deleting it back to "H" or "" cancelled only the
    /// ViewModel's debounce task. The coordinator's provider request had already been started and kept
    /// running — and `coordinator.isSearching` was left stuck on `true`, because the cancellation guard
    /// returns before the flag is reset. Nobody is looking at that query; the request must be cancelled.
    ///
    /// The reply itself doesn't paint rows even before the fix (the coordinator's `Task.isCancelled`
    /// guard catches it), so a rows-only assertion reads green on the broken code. What is measured here
    /// is the request: was the transport told to stop, and is the coordinator still claiming to search.
    func testDeletingTheQueryCancelsTheInFlightRequest() async {
        let provider = StubbornSearchProvider()
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)
        viewModel.openSearch()

        viewModel.onSearchTextChanged("Hà")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertEqual(provider.queries, ["Hà"], "setup: the search must have left the debounce")
        let searchingAfterType = await coordinator.isSearching
        XCTAssertTrue(searchingAfterType, "setup: the request is on the wire")

        // Delete back to one character — below the threshold, so nothing new may be asked for.
        viewModel.onSearchTextChanged("H")
        try? await Task.sleep(nanoseconds: 150_000_000)

        let searchingAfterDelete = await coordinator.isSearching
        XCTAssertFalse(
            searchingAfterDelete,
            "the coordinator must not still report a search in progress for a query nobody typed"
        )

        // Release the in-flight request. It must have been cancelled while waiting.
        provider.release()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(
            provider.cancelledAtReturn,
            ["Hà"],
            "the request for the deleted query must be cancelled, not left running to completion"
        )
        XCTAssertTrue(
            viewModel.searchResults.isEmpty,
            "a late reply for a deleted query must not paint rows under an empty field"
        )
        XCTAssertNil(viewModel.searchError, "and it is not a failure either")
        XCTAssertFalse(viewModel.isSearching, "the field must not keep a spinner for a vanished query")
        XCTAssertEqual(provider.queries, ["Hà"], "a short query must never reach the provider")
    }

    /// The other half of the same rule: a *newer* query must not be cancelled by the cleanup that
    /// clearing an older one triggers. Typing back up from "" to "Đà Nẵng" must still search and land.
    func testShortQueryCleanupDoesNotKillTheNextRealSearch() async {
        let provider = StubbornSearchProvider()
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)
        viewModel.openSearch()

        // 1. A search is in flight, then deleted.
        viewModel.onSearchTextChanged("Hà")
        try? await Task.sleep(nanoseconds: 420_000_000)
        viewModel.onSearchTextChanged("")
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 2. Type a real query again before the abandoned one has answered.
        viewModel.onSearchTextChanged("Đà Nẵng")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertEqual(provider.queries, ["Hà", "Đà Nẵng"], "the new query must reach the provider")

        let searching = await coordinator.isSearching
        XCTAssertTrue(searching, "clearing the old query must not have cancelled the new one")

        // 3. Release both; only the newest may finish as a live request.
        provider.release()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(
            viewModel.searchResults.map(\.id),
            ["result-Đà Nẵng"],
            "the abandoned query's reply must not overwrite the newer one"
        )
        XCTAssertFalse(viewModel.isSearching)
        let cancelled = provider.cancelledAtReturn
        XCTAssertEqual(cancelled, ["Hà"], "only the deleted query's request may be cancelled")
    }

    /// Retry on a failed search is an explicit press, so it must not wait out the 300 ms typing debounce.
    func testRetrySearchSkipsDebounceAndRecovers() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let mockProvider = MockWeatherProvider(stubbedLocations: [hanoi])
        let coordinator = WeatherCoordinator(provider: mockProvider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.openSearch()
        viewModel.searchText = "Hà Nội"
        await mockProvider.setError(.timeout)
        viewModel.onSearchTextChanged("Hà Nội")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertEqual(viewModel.searchError, .timeout)

        // Recover, then press Retry. 180 ms is well under the 300 ms debounce plus the round trip, so a
        // debounced path would still be idle here.
        await mockProvider.setError(nil)
        viewModel.retrySearch()
        try? await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertEqual(viewModel.searchResults.map(\.id), ["hanoi"], "Retry must run the query on screen now")
        XCTAssertNil(viewModel.searchError)
        XCTAssertFalse(viewModel.isSearching)
    }

    /// Retry with nothing typed must not search (and must not crash on an empty query).
    func testRetrySearchWithShortQueryDoesNothing() async {
        let mockProvider = MockWeatherProvider(stubbedLocations: [makeLocation()])
        let coordinator = WeatherCoordinator(provider: mockProvider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.searchText = "H"
        viewModel.retrySearch()
        try? await Task.sleep(nanoseconds: 60_000_000)

        let recorded = await mockProvider.recordedSearches
        XCTAssertTrue(recorded.isEmpty, "a one-character query must never reach the provider")
        XCTAssertNil(viewModel.searchError)
    }

    /// Closing the field must not leave a failure behind for the next time it opens.
    func testCloseClearsSearchFailureSoTheNextOpenStartsClean() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let provider = MockWeatherProvider(stubbedLocations: [hanoi])
        await provider.setError(.networkUnavailable)
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.openSearch()
        viewModel.onSearchTextChanged("Hà")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertEqual(viewModel.searchError, .networkUnavailable, "setup: expected a failed search")

        viewModel.close()
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertNil(viewModel.searchError, "the page must not reopen onto a stale failure row")
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        let coordError = await coordinator.searchError
        XCTAssertNil(coordError, "the coordinator must clear it too, not just the ViewModel")

        // Reopening with an empty field shows nothing at all — no error, and no "no cities found" either.
        viewModel.openSearch()
        let recorded = await provider.recordedSearches
        XCTAssertEqual(recorded, ["Hà"], "opening the field must not re-run the old query")
        XCTAssertNil(viewModel.searchError)
    }

    // MARK: - 14. Closing the page must not kill the search that comes after it

    /// The reviewer's blocker: `close()`/`reset()` set `latestSearchIntent = .max`, while the ViewModel
    /// sends a finite counter. `intent >= .max` can never hold again, so once the page had been closed or
    /// reopened, **every later search was silently dropped** — typing produced nothing and no spinner.
    ///
    /// The full user journey, not just the actor: open the field, close the page, reopen it, search.
    func testSearchStillWorksAfterThePageIsClosedAndReopened() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let provider = MockWeatherProvider(stubbedLocations: [hanoi])
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)
        let viewModel = WeatherViewModel(coordinator: coordinator)

        // 1. Search works before anything is closed (the control for this test).
        viewModel.openSearch()
        viewModel.onSearchTextChanged("Hà")
        try? await Task.sleep(nanoseconds: 420_000_000)
        XCTAssertEqual(viewModel.searchResults.map(\.id), ["hanoi"], "setup: search must work at all")

        // 2. Close the page: this is what fences pending work.
        viewModel.close()
        try? await Task.sleep(nanoseconds: 150_000_000)

        // 3. Reopen and search again. This is the blocker — it must still reach the provider.
        viewModel.onAppear()
        viewModel.openSearch()
        viewModel.onSearchTextChanged("Hà")
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertEqual(
            viewModel.searchResults.map(\.id), ["hanoi"],
            "searching after a close/reopen must still reach the provider"
        )
        XCTAssertFalse(viewModel.isSearching, "and it must not be left spinning")
    }

    /// The same journey through the coordinator alone, including `reset()` (which also used `.max`),
    /// and the Island's own close → reopen → search path.
    func testCoordinatorSearchSurvivesCloseResetAndReopen() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let provider = MockWeatherProvider(stubbedLocations: [hanoi])
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        await coordinator.search(query: "Hà")
        let first = await coordinator.searchResults
        XCTAssertEqual(first.map(\.id), ["hanoi"], "setup: search must work at all")

        // Island close (page hidden) then reopen (page shown again).
        await coordinator.close()
        await coordinator.reopen()
        await coordinator.search(query: "Hà")
        let afterClose = await coordinator.searchResults
        XCTAssertEqual(
            afterClose.map(\.id), ["hanoi"],
            "search after close + reopen must still work"
        )

        // reset() is the other place that fenced with .max.
        await coordinator.reset()
        await coordinator.search(query: "Hà")
        let afterReset = await coordinator.searchResults
        XCTAssertEqual(
            afterReset.map(\.id), ["hanoi"],
            "search after reset() must still work"
        )
    }

    /// A cancel issued *before* a close must not resurrect and kill the search that follows the reopen.
    /// This is the property the fence exists for; the fix must keep it while letting new searches through.
    func testCancelFromBeforeCloseDoesNotKillSearchAfterReopen() async {
        let hanoi = makeLocation(id: "hanoi", name: "Hà Nội")
        let provider = MockWeatherProvider(
            stubbedLocations: [hanoi],
            delaySeconds: 0.15
        )
        let coordinator = WeatherCoordinator(provider: provider, locationStore: nil)

        // A keystroke's cancel is queued, then the page closes.
        await coordinator.close()
        await coordinator.cancelSearch(intent: 1)

        // A new search after the reopen must not be cancelled by that old intent.
        let search = Task { await coordinator.search(query: "Hà", intent: 2) }
        try? await Task.sleep(nanoseconds: 60_000_000)
        let searching = await coordinator.isSearching
        XCTAssertTrue(searching, "a pre-close cancel must not kill the search after a reopen")

        _ = await search.value
        let rows = await coordinator.searchResults
        XCTAssertEqual(rows.map(\.id), ["hanoi"], "the reopened search must land")
    }

    // MARK: - 12. A failed refresh with valid cache keeps the forecast, not an "offline" claim

    /// Contract case 2/3 through the ViewModel: a 429 or a timeout with a still-valid cache must keep the
    /// forecast on screen, must not claim "Ngoại tuyến" (the network is up), and must leave the group
    /// reachable so the page can draw its strip with the right retry.
    func testFailedRefreshWithCacheKeepsForecastAndDoesNotClaimOffline() async {
        let hanoi = makeLocation(id: "loc-cache", name: "Hà Nội")
        let baseDate = Date(timeIntervalSince1970: 1_000_000)
        let dateBox = DateBox(baseDate)
        let snapshot = WeatherSnapshot(
            location: hanoi,
            fetchedAt: baseDate,
            attribution: WeatherAttribution(providerId: "mock-provider", serviceName: "Mock Weather"),
            hourly: (0..<24).map { i in
                HourlyForecast(
                    date: baseDate.addingTimeInterval(TimeInterval(i * 3600)),
                    temperatureCelsius: 27.0 + Double(i % 4),
                    condition: .clear
                )
            }
        )
        let mockProvider = MockWeatherProvider(stubbedSnapshots: [hanoi.id: snapshot])
        let coordinator = WeatherCoordinator(
            provider: mockProvider,
            locationStore: nil,
            clock: { dateBox.value }
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.selectLocation(hanoi)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await viewModel.syncState()
        guard case .loaded = viewModel.state else {
            XCTFail("setup: expected .loaded, got \(viewModel.state)")
            return
        }

        // 18 minutes later the cache is stale-but-valid; a 429 must not throw it away.
        dateBox.value = baseDate.addingTimeInterval(1080)
        await mockProvider.setError(.rateLimited)
        viewModel.refresh()
        try? await Task.sleep(nanoseconds: 180_000_000)
        await viewModel.syncState()

        guard case .failedWithStale(let kept, let age, let error) = viewModel.state else {
            XCTFail("expected .failedWithStale keeping the forecast, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(kept.location.id, hanoi.id)
        XCTAssertEqual(error, .rateLimited)
        XCTAssertEqual(age, 1080, accuracy: 1.0)
        XCTAssertFalse(kept.upcoming12Hours(from: dateBox.value).isEmpty)

        // The header must not lie about the network while naming the real failure above the ribbon.
        XCTAssertFalse(
            viewModel.freshnessDescription.contains("Ngoại tuyến"),
            "a quota failure is not being offline: \(viewModel.freshnessDescription)"
        )

        // And the group is drawable with a retry, from the same presentation the page uses.
        let presentation = WeatherErrorPresentation(for: error)
        XCTAssertEqual(presentation.titleKey, "Tạm hết lượt tải thời tiết")
        XCTAssertTrue(presentation.canRetry)
    }

    /// Plain offline keeps its old shape and wording: with valid cache it is `.offlineWithStale` and the
    /// header says "Ngoại tuyến". This is the positive control for the test above.
    func testPlainOfflineWithCacheStillSaysOffline() async {
        let hanoi = makeLocation(id: "loc-offline", name: "Hà Nội")
        let baseDate = Date(timeIntervalSince1970: 1_100_000)
        let dateBox = DateBox(baseDate)
        let snapshot = WeatherSnapshot(
            location: hanoi,
            fetchedAt: baseDate,
            attribution: WeatherAttribution(providerId: "mock-provider", serviceName: "Mock Weather"),
            hourly: (0..<24).map { i in
                HourlyForecast(
                    date: baseDate.addingTimeInterval(TimeInterval(i * 3600)),
                    temperatureCelsius: 25.0,
                    condition: .clear
                )
            }
        )
        let mockProvider = MockWeatherProvider(stubbedSnapshots: [hanoi.id: snapshot])
        let coordinator = WeatherCoordinator(
            provider: mockProvider,
            locationStore: nil,
            clock: { dateBox.value }
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.selectLocation(hanoi)
        try? await Task.sleep(nanoseconds: 120_000_000)
        await viewModel.syncState()

        dateBox.value = baseDate.addingTimeInterval(1080)
        await mockProvider.setError(.networkUnavailable)
        viewModel.refresh()
        try? await Task.sleep(nanoseconds: 180_000_000)
        await viewModel.syncState()

        guard case .offlineWithStale(let kept, _) = viewModel.state else {
            XCTFail("expected .offlineWithStale, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(kept.location.id, hanoi.id)
        XCTAssertTrue(
            viewModel.freshnessDescription.contains("Ngoại tuyến"),
            "offline must be stated when it is true: \(viewModel.freshnessDescription)"
        )
    }

    /// Closing Weather while an async cancellable GPS lookup is awaiting must cancel cleanly and stay
    /// `.unselected`, never flipping to `.locationDenied`.
    func testClosingDuringCancellableCurrentLocationDoesNotFlipToLocationDenied() async {
        struct CancellableDelayedLocationService: WeatherLocationService {
            func requestCurrentLocation() async throws -> WeatherLocation {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled {
                    throw WeatherError.cancelled
                }
                return WeatherLocation(
                    id: "loc-gps",
                    name: "GPS City",
                    latitude: 10.8,
                    longitude: 106.6,
                    timeZoneIdentifier: "Asia/Ho_Chi_Minh",
                    isCurrentLocation: true
                )
            }
        }

        let mockProvider = MockWeatherProvider()
        let coordinator = WeatherCoordinator(
            provider: mockProvider,
            locationStore: nil,
            locationService: CancellableDelayedLocationService()
        )
        let viewModel = WeatherViewModel(coordinator: coordinator)

        viewModel.requestCurrentLocation()
        try? await Task.sleep(nanoseconds: 30_000_000)
        viewModel.close()
        try? await Task.sleep(nanoseconds: 120_000_000)
        await viewModel.syncState()

        XCTAssertEqual(viewModel.state, .unselected)
        let coordState = await coordinator.state
        XCTAssertEqual(coordState, .unselected)
        let fetches = await mockProvider.totalFetchCount
        XCTAssertEqual(fetches, 0)
    }
}

/// Mutable clock shared with a `@Sendable` closure, same idiom as `Box` in `WeatherRulesTests`.
private final class DateBox: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}
