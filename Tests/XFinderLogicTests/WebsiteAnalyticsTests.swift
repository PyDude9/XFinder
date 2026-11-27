import XCTest
import Foundation
import os

// MARK: - Test Doubles

private final class MockWebsiteAnalyticsTransport: WebsiteAnalyticsHTTPTransport, Sendable {
    typealias Handler = @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)

    private struct State: Sendable {
        var requests: [URLRequest] = []
    }

    private let handler: Handler
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        state.withLock { $0.requests.append(request) }
        return try await handler(request, maxBytes)
    }

    var recordedRequests: [URLRequest] {
        state.withLock { $0.requests }
    }
}

private final class MockGA4OAuthDriver: GA4OAuthAuthorizationDriver, Sendable {
    private let resultProvider: @Sendable (String, @Sendable (String) throws -> URL) async throws -> GA4OAuthAuthorizationResult

    init(_ resultProvider: @escaping @Sendable (String, @Sendable (String) throws -> URL) async throws -> GA4OAuthAuthorizationResult) {
        self.resultProvider = resultProvider
    }

    func authorize(
        expectedState: String,
        buildAuthorizationURL: @Sendable (String) throws -> URL
    ) async throws -> GA4OAuthAuthorizationResult {
        try await resultProvider(expectedState, buildAuthorizationURL)
    }
}

private final class StubAnalyticsAdapter: WebsiteAnalyticsSourceAdapter, Sendable {
    let provider: WebsiteAnalyticsProviderKind
    private let fetcher: @Sendable (WebsiteAnalyticsRange, Date) async throws -> WebsiteAnalyticsReport

    init(
        provider: WebsiteAnalyticsProviderKind,
        fetcher: @escaping @Sendable (WebsiteAnalyticsRange, Date) async throws -> WebsiteAnalyticsReport
    ) {
        self.provider = provider
        self.fetcher = fetcher
    }

    func fetchReport(range: WebsiteAnalyticsRange, now: Date) async throws -> WebsiteAnalyticsReport {
        try await fetcher(range, now)
    }
}

private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
}

private func makeSampleReport(
    provider: WebsiteAnalyticsProviderKind,
    range: WebsiteAnalyticsRange = .sevenDays,
    visitors: Int? = 1200,
    pageviews: Int? = 3400,
    fetchedAt: Date = Date(timeIntervalSince1970: 1_760_000_000)
) -> WebsiteAnalyticsReport {
    WebsiteAnalyticsReport(
        provider: provider,
        siteLabel: provider == .dataFast ? "xfinder.app" : "XFinder GA4",
        range: range,
        windowStartDateKey: "2026-11-21",
        windowEndDateKey: "2026-11-27",
        timeZoneIdentifier: "Asia/Ho_Chi_Minh",
        kpis: WebsiteAnalyticsKPIs(
            visitors: visitors,
            pageviews: pageviews,
            bounceRatePercent: 41.2,
            averageSessionDurationSeconds: 135
        ),
        realtime: WebsiteAnalyticsRealtime(activeVisitors: 12, isSupported: true, windowMinutes: 5),
        timeseries: [
            WebsiteAnalyticsSeriesPoint(dateKey: "2026-11-26", label: "26/11", visitors: 550, pageviews: 1600),
            WebsiteAnalyticsSeriesPoint(dateKey: "2026-11-27", label: "27/11", visitors: 650, pageviews: 1800),
        ],
        topPages: [WebsiteAnalyticsBreakdownItem(name: "/pricing", visitors: 420, pageviews: 680)],
        topReferrers: [WebsiteAnalyticsBreakdownItem(name: "github.com", visitors: 310, pageviews: 500)],
        fetchedAt: fetchedAt
    )
}

// MARK: - Tests

final class WebsiteAnalyticsTests: XCTestCase {

    // MARK: 1. Host Policy, DataFast df_ / dft_ Validation & Secret Sanitization

    func testDataFastAPIKeyValidationRejectsAccountTokenAndAcceptsWebsiteKey() {
        XCTAssertEqual(
            WebsiteAnalyticsHostPolicy.validateDataFastAPIKey("df_live_abc123"),
            .success("df_live_abc123")
        )
        XCTAssertEqual(
            WebsiteAnalyticsHostPolicy.validateDataFastAPIKey("dft_account_secret"),
            .failure(.invalidConfiguration("datafast_account_token_rejected"))
        )
        XCTAssertEqual(
            WebsiteAnalyticsHostPolicy.validateDataFastAPIKey("sk_wrong_prefix"),
            .failure(.invalidConfiguration("datafast_key_prefix_required"))
        )
        XCTAssertEqual(
            WebsiteAnalyticsHostPolicy.validateDataFastAPIKey("   "),
            .failure(.unconfigured(.missingCredentials))
        )
    }

    func testHostPolicyRestrictsOutboundURLs() {
        let validDF = WebsiteAnalyticsHostPolicy.validatedDataFastURL(path: "/api/v1/analytics/overview")
        XCTAssertNotNil(validDF)
        XCTAssertTrue(WebsiteAnalyticsHostPolicy.validateDataFastOutboundURL(validDF!))

        XCTAssertFalse(WebsiteAnalyticsHostPolicy.validateDataFastOutboundURL(URL(string: "http://datafa.st/api/v1/analytics/overview")!))
        XCTAssertFalse(WebsiteAnalyticsHostPolicy.validateDataFastOutboundURL(URL(string: "https://evil.datafa.st/api/v1/analytics/overview")!))
        XCTAssertNil(WebsiteAnalyticsHostPolicy.validatedDataFastURL(path: "/api/v1/../admin"))

        let validGA = WebsiteAnalyticsHostPolicy.validatedGA4EndpointURL(propertyId: "properties/123456789", method: "runReport")
        XCTAssertEqual(validGA?.absoluteString, "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport")
        XCTAssertNil(WebsiteAnalyticsHostPolicy.validatedGA4EndpointURL(propertyId: "abc-not-numeric", method: "runReport"))
        XCTAssertNil(WebsiteAnalyticsHostPolicy.validatedGA4EndpointURL(propertyId: "12345", method: "deleteProperty"))
    }

    func testSecretSanitizationRedactsKeys() {
        let leaked = "Authorization failed for df_secret_9999 and ya29.token"
        let clean = WebsiteAnalyticsHostPolicy.sanitize(leaked, redacting: ["df_secret_9999", "ya29.token"])
        XCTAssertFalse(clean.contains("df_secret_9999"))
        XCTAssertFalse(clean.contains("ya29.token"))
        XCTAssertTrue(clean.contains("[REDACTED]"))
    }

    // MARK: 2. Timezone / Date Boundary & 7d/30d Window Rules (Failure Case 8)

    func testDateWindowRespectsProviderTimezoneBoundaries() {
        // 2026-11-27 01:30 UTC is 2026-11-26 20:30 in America/New_York and 2026-11-27 08:30 in Asia/Ho_Chi_Minh.
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = utcCal.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 1, minute: 30))!

        let nyWindow = WebsiteAnalyticsDateRules.dateWindow(
            for: .sevenDays,
            now: instant,
            timeZone: TimeZone(identifier: "America/New_York")!
        )
        XCTAssertEqual(nyWindow.startDateKey, "2026-11-20")
        XCTAssertEqual(nyWindow.endDateKey, "2026-11-26")

        let vnWindow = WebsiteAnalyticsDateRules.dateWindow(
            for: .sevenDays,
            now: instant,
            timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        )
        XCTAssertEqual(vnWindow.startDateKey, "2026-11-21")
        XCTAssertEqual(vnWindow.endDateKey, "2026-11-27")

        let thirtyDay = WebsiteAnalyticsDateRules.dateWindow(
            for: .thirtyDays,
            now: instant,
            timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        )
        XCTAssertEqual(thirtyDay.startDateKey, "2026-10-29")
        XCTAssertEqual(thirtyDay.endDateKey, "2026-11-27")
    }

    // MARK: 3. DataFast Decoders & Live Adapter (Empty, Malformed, Non-Finite, Oversized)

    func testDataFastAdapterFetchesCompleteReportAndVerifiesAuthHeader() async throws {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .dataFast,
            dataFastConfig: DataFastSiteConfig(siteId: "site1", siteLabel: "xfinder.app", timeZoneIdentifier: "UTC")
        )
        creds.setSecret("df_test_key_1234", for: .dataFastAPIKey, accountKey: "site1")

        let transport = MockWebsiteAnalyticsTransport { req, _ in
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer df_test_key_1234")
            XCTAssertEqual(req.url?.host, "datafa.st")
            let path = req.url?.path ?? ""
            let json: String
            if path.hasSuffix("/overview") {
                json = #"{"status":"success","data":{"visitors":1450,"pageviews":4200,"bounce_rate":38.5}}"#
            } else if path.hasSuffix("/timeseries") {
                json = #"{"status":"success","data":[{"date":"2026-11-26","visitors":700,"pageviews":2000},{"date":"2026-11-27","visitors":750,"pageviews":2200}]}"#
            } else if path.hasSuffix("/realtime") {
                json = #"{"status":"success","data":{"count":9}}"#
            } else if path.hasSuffix("/pages") {
                json = #"{"status":"success","data":[{"name":"/","visitors":900,"pageviews":1500},{"name":"/download","visitors":550,"pageviews":800}]}"#
            } else {
                json = #"{"status":"success","data":[{"name":"github.com","visitors":610,"pageviews":980}]}"#
            }
            return (Data(json.utf8), makeHTTPResponse(url: req.url!))
        }

        let adapter = DataFastAdapter(transport: transport, credentialStore: creds, configStore: configs)
        let now = Date(timeIntervalSince1970: 1_795_737_600)
        let report = try await adapter.fetchReport(range: .sevenDays, now: now)

        XCTAssertEqual(report.provider, .dataFast)
        XCTAssertEqual(report.kpis.visitors, 1450)
        XCTAssertEqual(report.kpis.pageviews, 4200)
        XCTAssertEqual(report.kpis.bounceRatePercent, 38.5)
        // Duration omitted by DataFast overview -> remains nil ("—"), never synthesized as 0.
        XCTAssertNil(report.kpis.averageSessionDurationSeconds)
        XCTAssertEqual(WebsiteAnalyticsFormatting.formatDuration(seconds: report.kpis.averageSessionDurationSeconds), "—")
        XCTAssertEqual(report.realtime.activeVisitors, 9)
        XCTAssertEqual(report.timeseries.count, 2)
        XCTAssertEqual(report.topPages.first?.name, "/")
        XCTAssertEqual(report.topReferrers.first?.name, "github.com")
    }

    func testDataFastRejectsMalformedNonFiniteAndOversizedPayloads() async throws {
        // Non-finite string
        XCTAssertThrowsError(try DataFastAdapter.decodeOverview(Data(#"{"status":"success","data":{"visitors":10,"bounce_rate":"NaN"}}"#.utf8))) { err in
            guard case WebsiteAnalyticsError.malformedResponse = err else {
                return XCTFail("Expected malformedResponse, got \(err)")
            }
        }
        // Out-of-range bounce rate (>100)
        XCTAssertThrowsError(try DataFastAdapter.decodeOverview(Data(#"{"status":"success","data":{"visitors":10,"bounce_rate":145.0}}"#.utf8)))
        // Negative visitors
        XCTAssertThrowsError(try DataFastAdapter.decodeOverview(Data(#"{"status":"success","data":{"visitors":-5}}"#.utf8)))
        // Missing data envelope
        XCTAssertThrowsError(try DataFastAdapter.decodeOverview(Data(#"{"status":"success"}"#.utf8)))

        // Oversized payload rejected by adapter
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            dataFastConfig: DataFastSiteConfig(siteId: "s1", siteLabel: "big.site", timeZoneIdentifier: "UTC")
        )
        creds.setSecret("df_key_valid", for: .dataFastAPIKey, accountKey: "s1")
        let huge = Data(repeating: UInt8(ascii: " "), count: 4096)
        let transport = MockWebsiteAnalyticsTransport { req, maxBytes in
            if huge.count > maxBytes {
                throw WebsiteAnalyticsError.oversizedPayload(byteCount: huge.count, limit: maxBytes)
            }
            return (huge, makeHTTPResponse(url: req.url!))
        }
        let adapter = DataFastAdapter(transport: transport, credentialStore: creds, configStore: configs, maxResponseBytes: 1024)
        do {
            _ = try await adapter.fetchReport(range: .sevenDays, now: Date())
            XCTFail("Expected oversizedPayload error")
        } catch let err as WebsiteAnalyticsError {
            guard case .oversizedPayload = err else {
                return XCTFail("Expected oversizedPayload, got \(err)")
            }
        }
    }

    // MARK: 4. GA4 Header Validation, Positional Decoding & OAuth PKCE

    func testGA4DecoderValidatesHeadersBeforePositionalRows() throws {
        // Reordered metric headers: screenPageViews is at index 0, activeUsers at index 1.
        let reordered = """
        {
          "metricHeaders": [
            {"name": "screenPageViews", "type": "TYPE_INTEGER"},
            {"name": "activeUsers", "type": "TYPE_INTEGER"},
            {"name": "bounceRate", "type": "TYPE_FLOAT"},
            {"name": "averageSessionDuration", "type": "TYPE_SECONDS"}
          ],
          "rows": [
            {
              "metricValues": [
                {"value": "5120"},
                {"value": "1980"},
                {"value": "0.276"},
                {"value": "142.4"}
              ]
            }
          ]
        }
        """
        let kpis = try GA4DataAPIAdapter.decodeOverviewResponse(Data(reordered.utf8))
        XCTAssertEqual(kpis.visitors, 1980)
        XCTAssertEqual(kpis.pageviews, 5120)
        XCTAssertEqual(kpis.bounceRatePercent ?? -1, 27.6, accuracy: 0.001)
        XCTAssertEqual(kpis.averageSessionDurationSeconds ?? -1, 142.4, accuracy: 0.001)

        // Missing required metric header -> rejected
        let missingHeader = #"{"metricHeaders":[{"name":"screenPageViews"}],"rows":[{"metricValues":[{"value":"10"}]}]}"#
        XCTAssertThrowsError(try GA4DataAPIAdapter.decodeOverviewResponse(Data(missingHeader.utf8)))

        // Non-finite metric value -> rejected
        let nonFinite = #"{"metricHeaders":[{"name":"activeUsers"},{"name":"screenPageViews"},{"name":"bounceRate"}],"rows":[{"metricValues":[{"value":"10"},{"value":"20"},{"value":"Infinity"}]}]}"#
        XCTAssertThrowsError(try GA4DataAPIAdapter.decodeOverviewResponse(Data(nonFinite.utf8)))

        // Empty rows -> returns nil KPIs (never synthesizes zeros)
        let emptyReport = #"{"metricHeaders":[{"name":"activeUsers"},{"name":"screenPageViews"}]}"#
        let emptyKPIs = try GA4DataAPIAdapter.decodeOverviewResponse(Data(emptyReport.utf8))
        XCTAssertFalse(emptyKPIs.hasAnyValue)
        XCTAssertNil(emptyKPIs.visitors)
        XCTAssertNil(emptyKPIs.pageviews)
    }

    func testGA4OAuthPKCEFlowAndCancellation() async throws {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .googleAnalytics4,
            ga4Config: GA4PropertyConfig(
                propertyId: "445566778",
                propertyLabel: "Main Site",
                oauthClientId: "client-123.apps.googleusercontent.com",
                redirectURI: nil,
                timeZoneIdentifier: "UTC"
            )
        )

        // Case A: User cancels OAuth -> remains disconnected, no tokens stored.
        let cancelDriver = MockGA4OAuthDriver { expectedState, buildAuthURL in
            let redirectURI = "http://127.0.0.1:51234/oauth2/callback"
            let authURL = try buildAuthURL(redirectURI)
            let comps = URLComponents(url: authURL, resolvingAgainstBaseURL: false)!
            let scope = comps.queryItems?.first(where: { $0.name == "scope" })?.value
            XCTAssertEqual(scope, WebsiteAnalyticsHostPolicy.ga4ReadOnlyScope)
            let callbackURL = URL(string: "\(redirectURI)?error=access_denied&state=\(expectedState)")!
            return GA4OAuthAuthorizationResult(callbackURL: callbackURL, redirectURI: redirectURI)
        }
        let noopTransport = MockWebsiteAnalyticsTransport { req, _ in
            XCTFail("Token endpoint must not be called on OAuth cancel")
            return (Data(), makeHTTPResponse(url: req.url!, statusCode: 500))
        }
        let cancelAdapter = GA4DataAPIAdapter(
            transport: noopTransport,
            credentialStore: creds,
            configStore: configs,
            oauthDriver: cancelDriver
        )
        do {
            _ = try await cancelAdapter.authorizeWithPKCE()
            XCTFail("Expected oauthCancelled")
        } catch let err as WebsiteAnalyticsError {
            XCTAssertEqual(err, .oauthCancelled)
        }
        XCTAssertNil(creds.secret(for: .ga4AccessToken, accountKey: "445566778"))

        // Case B: Successful PKCE exchange stores access + refresh token in Keychain abstraction.
        let successDriver = MockGA4OAuthDriver { expectedState, buildAuthURL in
            let redirectURI = "http://127.0.0.1:52345/oauth2/callback"
            _ = try buildAuthURL(redirectURI)
            let callbackURL = URL(string: "\(redirectURI)?code=auth_code_xyz&state=\(expectedState)")!
            return GA4OAuthAuthorizationResult(callbackURL: callbackURL, redirectURI: redirectURI)
        }
        let tokenTransport = MockWebsiteAnalyticsTransport { req, _ in
            XCTAssertEqual(req.url?.absoluteString, "https://oauth2.googleapis.com/token")
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("code_verifier="))
            XCTAssertTrue(body.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A52345%2Foauth2%2Fcallback"))
            XCTAssertFalse(body.contains("client_secret="))
            let json = #"{"access_token":"ya29.fresh","refresh_token":"1//refresh_tok","expires_in":3600}"#
            return (Data(json.utf8), makeHTTPResponse(url: req.url!))
        }
        let successAdapter = GA4DataAPIAdapter(
            transport: tokenTransport,
            credentialStore: creds,
            configStore: configs,
            oauthDriver: successDriver
        )
        let tokens = try await successAdapter.authorizeWithPKCE()
        XCTAssertEqual(tokens.accessToken, "ya29.fresh")
        XCTAssertEqual(creds.secret(for: .ga4AccessToken, accountKey: "445566778"), "ya29.fresh")
        XCTAssertEqual(creds.secret(for: .ga4RefreshToken, accountKey: "445566778"), "1//refresh_tok")
    }

    func testClosingPageCancelsTheUnderlyingOAuthDriver() async {
        let started = expectation(description: "OAuth driver started")
        let cancelled = expectation(description: "OAuth driver received cancellation")
        let driver = MockGA4OAuthDriver { _, _ in
            started.fulfill()
            do {
                try await Task.sleep(for: .seconds(10))
            } catch is CancellationError {
                cancelled.fulfill()
            }
            throw WebsiteAnalyticsError.oauthCancelled
        }
        let store = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .googleAnalytics4,
            ga4Config: GA4PropertyConfig(
                propertyId: "445566778",
                propertyLabel: "Test Site",
                oauthClientId: "client-123.apps.googleusercontent.com",
                redirectURI: nil,
                timeZoneIdentifier: "UTC"
            )
        )
        let coordinator = WebsiteAnalyticsCoordinator.makeDefault(
            credentialStore: InMemoryWebsiteAnalyticsCredentialStore(),
            configStore: store,
            oauthDriver: driver
        )
        await coordinator.openPage()
        let authorization = Task { await coordinator.startGA4OAuth() }
        await fulfillment(of: [started], timeout: 2)
        await coordinator.close()
        await fulfillment(of: [cancelled], timeout: 2)
        authorization.cancel()
        guard case .failure(.oauthCancelled) = await authorization.value else {
            return XCTFail("Expected the closed page to cancel authorization")
        }
    }

    // MARK: 5. Coordinator: Stale Cache Preservation, Fencing, Empty, Disconnect & Tab Disable

    func testUnconfiguredProviderIssuesZeroNetworkRequests() async {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(selectedProvider: .dataFast)
        let callCount = OSAllocatedUnfairLock(initialState: 0)

        let df = StubAnalyticsAdapter(provider: .dataFast) { _, _ in
            callCount.withLock { $0 += 1 }
            return makeSampleReport(provider: .dataFast)
        }
        let ga = StubAnalyticsAdapter(provider: .googleAnalytics4) { _, _ in
            callCount.withLock { $0 += 1 }
            return makeSampleReport(provider: .googleAnalytics4)
        }

        let coordinator = WebsiteAnalyticsCoordinator(
            dataFastAdapter: df,
            ga4Adapter: ga,
            credentialStore: creds,
            configStore: configs
        )
        await coordinator.openPage()

        XCTAssertEqual(callCount.withLock { $0 }, 0)
        let state = await coordinator.snapshot.activeState
        XCTAssertEqual(state, .unconfigured(reason: .missingCredentials))
    }

    func testFailedRefreshPreservesValidStaleCacheAcrossErrorTypes() async {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .dataFast,
            dataFastConfig: DataFastSiteConfig(siteId: "s1", siteLabel: "xfinder.app")
        )
        creds.setSecret("df_live_123", for: .dataFastAPIKey, accountKey: "s1")

        let nextError = OSAllocatedUnfairLock<WebsiteAnalyticsError?>(initialState: nil)
        let df = StubAnalyticsAdapter(provider: .dataFast) { range, now in
            if let err = nextError.withLock({ $0 }) {
                throw err
            }
            return makeSampleReport(provider: .dataFast, range: range, visitors: 2222, pageviews: 6666, fetchedAt: now)
        }
        let ga = StubAnalyticsAdapter(provider: .googleAnalytics4) { _, _ in
            makeSampleReport(provider: .googleAnalytics4)
        }

        let coordinator = WebsiteAnalyticsCoordinator(
            dataFastAdapter: df,
            ga4Adapter: ga,
            credentialStore: creds,
            configStore: configs
        )
        await coordinator.openPage()
        let initial = await coordinator.snapshot.activeState
        guard case .loaded(let cachedReport, false) = initial else {
            return XCTFail("Expected loaded state, got \(initial)")
        }
        XCTAssertEqual(cachedReport.kpis.visitors, 2222)

        // 401 unauthorized preserves cache with stale marker
        nextError.withLock { $0 = .unauthorized }
        await coordinator.refresh(force: true)
        let afterAuthFail = await coordinator.snapshot.activeState
        guard case .failedWithCache(let preserved1, .unauthorized) = afterAuthFail else {
            return XCTFail("Expected failedWithCache(.unauthorized), got \(afterAuthFail)")
        }
        XCTAssertEqual(preserved1.kpis.visitors, 2222)

        // 429 rate limited preserves cache
        nextError.withLock { $0 = .rateLimited(retryAfterSeconds: 60) }
        await coordinator.refresh(force: true)
        let afterRateLimit = await coordinator.snapshot.activeState
        guard case .failedWithCache(let preserved2, .rateLimited(retryAfterSeconds: 60)) = afterRateLimit else {
            return XCTFail("Expected failedWithCache(.rateLimited), got \(afterRateLimit)")
        }
        XCTAssertEqual(preserved2.kpis.visitors, 2222)

        // 503 server error preserves cache
        nextError.withLock { $0 = .serverUnavailable(statusCode: 503) }
        await coordinator.refresh(force: true)
        let afterServerErr = await coordinator.snapshot.activeState
        guard case .failedWithCache(let preserved3, .serverUnavailable(statusCode: 503)) = afterServerErr else {
            return XCTFail("Expected failedWithCache(.serverUnavailable), got \(afterServerErr)")
        }
        XCTAssertEqual(preserved3.kpis.visitors, 2222)
    }

    func testEmptyReportTransitionsToExplicitEmptyState() async {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .dataFast,
            dataFastConfig: DataFastSiteConfig(siteId: "s1", siteLabel: "empty.site")
        )
        creds.setSecret("df_live_123", for: .dataFastAPIKey, accountKey: "s1")

        let df = StubAnalyticsAdapter(provider: .dataFast) { range, now in
            WebsiteAnalyticsReport(
                provider: .dataFast,
                siteLabel: "empty.site",
                range: range,
                windowStartDateKey: "2026-11-21",
                windowEndDateKey: "2026-11-27",
                timeZoneIdentifier: "UTC",
                kpis: WebsiteAnalyticsKPIs(visitors: nil, pageviews: nil, bounceRatePercent: nil, averageSessionDurationSeconds: nil),
                realtime: .unsupported,
                timeseries: [],
                topPages: [],
                topReferrers: [],
                fetchedAt: now
            )
        }
        let ga = StubAnalyticsAdapter(provider: .googleAnalytics4) { _, _ in makeSampleReport(provider: .googleAnalytics4) }
        let coordinator = WebsiteAnalyticsCoordinator(dataFastAdapter: df, ga4Adapter: ga, credentialStore: creds, configStore: configs)
        await coordinator.openPage()

        let state = await coordinator.snapshot.activeState
        guard case .empty(let report, false) = state else {
            return XCTFail("Expected .empty state, got \(state)")
        }
        XCTAssertNil(report.kpis.visitors)
    }

    func testProviderSwitchPersistsSelectionAndFencesStaleInFlightRequest() async {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .dataFast,
            dataFastConfig: DataFastSiteConfig(siteId: "s1", siteLabel: "df.site"),
            ga4Config: GA4PropertyConfig(propertyId: "998877", propertyLabel: "ga.site")
        )
        creds.setSecret("df_live_123", for: .dataFastAPIKey, accountKey: "s1")
        creds.setSecret("ya29.valid", for: .ga4AccessToken, accountKey: "998877")

        let df = StubAnalyticsAdapter(provider: .dataFast) { range, now in
            try await Task.sleep(nanoseconds: 250_000_000)
            return makeSampleReport(provider: .dataFast, range: range, visitors: 9999, fetchedAt: now)
        }
        let ga = StubAnalyticsAdapter(provider: .googleAnalytics4) { range, now in
            makeSampleReport(provider: .googleAnalytics4, range: range, visitors: 333, fetchedAt: now)
        }

        let coordinator = WebsiteAnalyticsCoordinator(dataFastAdapter: df, ga4Adapter: ga, credentialStore: creds, configStore: configs)

        let openTask = Task { await coordinator.openPage() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await coordinator.selectProvider(.googleAnalytics4)
        await openTask.value

        let snap = await coordinator.snapshot
        XCTAssertEqual(snap.selectedProvider, .googleAnalytics4)
        XCTAssertEqual(configs.selectedProvider(), .googleAnalytics4)
        guard case .loaded(let gaReport, false) = snap.activeState else {
            return XCTFail("Expected GA4 loaded report, got \(snap.activeState)")
        }
        XCTAssertEqual(gaReport.provider, .googleAnalytics4)
        XCTAssertEqual(gaReport.kpis.visitors, 333)
    }

    func testDisconnectClearsKeychainAndCacheWhileDisablePreservesCredentials() async {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .dataFast,
            dataFastConfig: DataFastSiteConfig(siteId: "s1", siteLabel: "xfinder.app")
        )
        creds.setSecret("df_live_secret", for: .dataFastAPIKey, accountKey: "s1")

        let df = StubAnalyticsAdapter(provider: .dataFast) { range, now in
            makeSampleReport(provider: .dataFast, range: range, visitors: 777, fetchedAt: now)
        }
        let ga = StubAnalyticsAdapter(provider: .googleAnalytics4) { _, _ in makeSampleReport(provider: .googleAnalytics4) }
        let coordinator = WebsiteAnalyticsCoordinator(dataFastAdapter: df, ga4Adapter: ga, credentialStore: creds, configStore: configs)

        await coordinator.openPage()
        // Disabling destination preserves credentials & config (Failure case 12)
        await coordinator.setDestinationEnabled(false)
        XCTAssertEqual(creds.secret(for: .dataFastAPIKey, accountKey: "s1"), "df_live_secret")
        XCTAssertNotNil(configs.loadDataFastConfig())

        // Disconnect wipes Keychain, config, and cached report (Failure case 9)
        await coordinator.disconnect(provider: .dataFast)
        XCTAssertNil(creds.secret(for: .dataFastAPIKey, accountKey: "s1"))
        XCTAssertNil(configs.loadDataFastConfig())
        let state = await coordinator.snapshot.dataFastState
        XCTAssertEqual(state, .unconfigured(reason: .missingCredentials))
    }

    func testPrepareForTerminationCancelsInFlightWorkCleanly() async {
        let creds = InMemoryWebsiteAnalyticsCredentialStore()
        let configs = InMemoryWebsiteAnalyticsConfigStore(
            selectedProvider: .dataFast,
            dataFastConfig: DataFastSiteConfig(siteId: "s1", siteLabel: "xfinder.app")
        )
        creds.setSecret("df_live_123", for: .dataFastAPIKey, accountKey: "s1")

        let wasCancelled = OSAllocatedUnfairLock(initialState: false)
        let df = StubAnalyticsAdapter(provider: .dataFast) { _, _ in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return makeSampleReport(provider: .dataFast)
            } catch {
                wasCancelled.withLock { $0 = true }
                throw CancellationError()
            }
        }
        let ga = StubAnalyticsAdapter(provider: .googleAnalytics4) { _, _ in makeSampleReport(provider: .googleAnalytics4) }
        let coordinator = WebsiteAnalyticsCoordinator(dataFastAdapter: df, ga4Adapter: ga, credentialStore: creds, configStore: configs)

        let task = Task { await coordinator.openPage() }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await coordinator.prepareForTermination()
        await task.value

        XCTAssertTrue(wasCancelled.withLock { $0 })
    }
}
