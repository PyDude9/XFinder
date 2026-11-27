import XCTest
import Foundation

private actor ScriptedStocksProvider: StocksProvider {
    let id = "qa-stocks-test"
    let attribution = StocksProviderAttribution(providerId: "qa-stocks-test", serviceName: "QA Stocks Mock")
    let supportedRanges: [StockChartRange] = [.oneDay, .oneWeek, .oneMonth]

    var catalog: [StockAssetDescriptor] = []
    var quotesById: [String: StockQuote] = [:]
    var perAssetErrors: [String: StocksError] = [:]
    var globalError: StocksError? = nil
    var searchError: StocksError? = nil
    var perQueryDelay: [String: TimeInterval] = [:]
    var fetchDelay: TimeInterval = 0
    var fetchCount = 0

    func configure(
        catalog: [StockAssetDescriptor]? = nil,
        quotesById: [String: StockQuote]? = nil,
        perAssetErrors: [String: StocksError] = [:],
        globalError: StocksError? = nil,
        searchError: StocksError? = nil,
        perQueryDelay: [String: TimeInterval] = [:],
        fetchDelay: TimeInterval = 0
    ) {
        if let catalog { self.catalog = catalog }
        if let quotesById { self.quotesById = quotesById }
        self.perAssetErrors = perAssetErrors
        self.globalError = globalError
        self.searchError = searchError
        self.perQueryDelay = perQueryDelay
        self.fetchDelay = fetchDelay
    }

    func searchSymbols(query: String) async throws -> [StockAssetDescriptor] {
        if let delay = perQueryDelay[query], delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if Task.isCancelled { throw StocksError.cancelled }
        if let searchError { throw searchError }
        let q = query.lowercased()
        return catalog.filter {
            $0.displayName.lowercased().contains(q)
                || $0.shortTicker.lowercased().contains(q)
                || $0.providerCode.lowercased().contains(q)
                || $0.key.exchange.lowercased().contains(q)
        }
    }

    func fetchQuotes(for assets: [StockAssetDescriptor]) async throws -> StocksBatchResult {
        fetchCount += 1
        if fetchDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(fetchDelay * 1_000_000_000))
        }
        if Task.isCancelled { throw StocksError.cancelled }
        if let globalError { throw globalError }
        var quotes: [String: StockQuote] = [:]
        var errs: [String: StocksError] = [:]
        for asset in assets {
            if let err = perAssetErrors[asset.id] {
                errs[asset.id] = err
            } else if let q = quotesById[asset.id] {
                quotes[asset.id] = q
            }
        }
        return StocksBatchResult(quotes: quotes, errorsByAssetId: errs)
    }
}

final class StocksRulesTests: XCTestCase {
    private func sampleAssets() -> [StockAssetDescriptor] {
        [
            StockAssetDescriptor(
                key: StockSymbolKey(symbol: "S&P 500", exchange: "US Index", providerAssetId: "idx:sp500"),
                displayName: "S&P 500",
                shortTicker: "SPX",
                providerCode: "^GSPC",
                kind: .index
            ),
            StockAssetDescriptor(
                key: StockSymbolKey(symbol: "AAPL", exchange: "NASDAQ", providerAssetId: "eq:nasdaq:aapl"),
                displayName: "Apple Inc.",
                shortTicker: "AAPL",
                providerCode: "AAPL",
                kind: .equity
            ),
            StockAssetDescriptor(
                key: StockSymbolKey(symbol: "NVDA", exchange: "NASDAQ", providerAssetId: "eq:nasdaq:nvda"),
                displayName: "NVIDIA Corp.",
                shortTicker: "NVDA",
                providerCode: "NVDA",
                kind: .equity
            ),
        ]
    }

    func testIndexAndETFRemainDistinctAssetsAndDuplicateExchangeTickersStayUnique() {
        let spIndex = StockAssetDescriptor(
            key: StockSymbolKey(symbol: "S&P 500", exchange: "US Index", providerAssetId: "idx:sp500"),
            displayName: "S&P 500",
            shortTicker: "SPX",
            providerCode: "^GSPC",
            kind: .index
        )
        let spyEtf = StockAssetDescriptor(
            key: StockSymbolKey(symbol: "SPY", exchange: "NYSE Arca", providerAssetId: "etf:nyse:spy"),
            displayName: "SPDR S&P 500 ETF",
            shortTicker: "SPY",
            providerCode: "SPY",
            kind: .etf
        )
        let shopNYSE = StockAssetDescriptor(
            key: StockSymbolKey(symbol: "SHOP", exchange: "NYSE", providerAssetId: "eq:nyse:shop"),
            displayName: "Shopify Inc.",
            shortTicker: "SHOP",
            providerCode: "SHOP.N",
            kind: .equity,
            currency: "USD"
        )
        let shopTSX = StockAssetDescriptor(
            key: StockSymbolKey(symbol: "SHOP", exchange: "TSX", providerAssetId: "eq:tsx:shop"),
            displayName: "Shopify Inc.",
            shortTicker: "SHOP",
            providerCode: "SHOP.TO",
            kind: .equity,
            currency: "CAD"
        )
        XCTAssertNotEqual(spIndex.key, spyEtf.key)
        XCTAssertEqual(spIndex.kind, .index)
        XCTAssertEqual(spyEtf.kind, .etf)
        XCTAssertNotEqual(shopNYSE.key, shopTSX.key)
        XCTAssertEqual(Set([shopNYSE.key, shopTSX.key]).count, 2)
    }

    func testChangePercentageIsNilWhenPreviousCloseMissingOrZero() {
        let asset = sampleAssets()[1]
        let now = Date()
        let missingPrev = StockQuote(
            asset: asset, price: 200.0, previousClose: nil, quotedAt: now, fetchedAt: now, sessionState: .open
        )
        let zeroPrev = StockQuote(
            asset: asset, price: 200.0, previousClose: 0.0, quotedAt: now, fetchedAt: now, sessionState: .open
        )
        let missingPrice = StockQuote(
            asset: asset, price: nil, previousClose: 198.0, quotedAt: now, fetchedAt: now, sessionState: .open
        )
        let valid = StockQuote(
            asset: asset, price: 200.0, previousClose: 100.0, quotedAt: now, fetchedAt: now, sessionState: .open
        )
        XCTAssertNil(missingPrev.changePercent)
        XCTAssertNil(missingPrev.formattedChangePercent())
        XCTAssertNil(zeroPrev.changePercent)
        XCTAssertNil(missingPrice.changeAmount)
        XCTAssertEqual(valid.formattedChangePercent(), "+100.00%")
    }

    func testSeparatesSourceDelayFromStaleAndClosedMarket() {
        let asset = sampleAssets()[0]
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let delayed = StockQuote(
            asset: asset, price: 5000, previousClose: 4950,
            quotedAt: t0.addingTimeInterval(-900), fetchedAt: t0,
            sessionState: .open, delayMinutes: 15
        )
        XCTAssertEqual(delayed.effectiveFreshness(at: t0.addingTimeInterval(60)), .delayed(minutes: 15))
        if case .stale = delayed.effectiveFreshness(at: t0.addingTimeInterval(4000)) {
            // expected stale after threshold
        } else {
            XCTFail("Expected .stale")
        }
        XCTAssertEqual(delayed.effectiveFreshness(at: t0.addingTimeInterval(25000)), .expired)
    }

    func testPerRowErrorPreservesOtherWatchlistQuotesAndWatchlistChangeDropsLateFetch() async {
        let now = Date()
        let assets = sampleAssets()
        let provider = ScriptedStocksProvider()
        await provider.configure(
            quotesById: [
                assets[0].id: StockQuote(asset: assets[0], price: 5100, previousClose: 5050, quotedAt: now, fetchedAt: now, sessionState: .closed(lastCloseAt: now), delayMinutes: 15),
                assets[1].id: StockQuote(asset: assets[1], price: 205, previousClose: 200, quotedAt: now, fetchedAt: now, sessionState: .open, delayMinutes: 15),
            ],
            perAssetErrors: [assets[2].id: .rateLimited]
        )

        let coord = StocksCoordinator(provider: provider, watchlistStore: InMemoryStocksWatchlistStore(initial: assets))
        await coord.openPage()

        if case .ready(let rows, _, _, _) = await coord.state {
            XCTAssertNotNil(rows[assets[0].id]?.quote)
            XCTAssertNotNil(rows[assets[1].id]?.quote)
            XCTAssertEqual(rows[assets[2].id]?.error, .rateLimited)
        } else {
            XCTFail("Expected .ready with partial row failure")
        }

        // Now change watchlist while a slow fetch is in flight -> old watchlist result must be ignored.
        await provider.configure(
            quotesById: [assets[0].id: StockQuote(asset: assets[0], price: 5200, previousClose: 5050, quotedAt: now, fetchedAt: now, sessionState: .open)],
            fetchDelay: 0.12
        )
        async let slowFetch: Void = coord.refresh(force: true)
        try? await Task.sleep(for: .milliseconds(25))
        await coord.removeAsset(id: assets[2].id)
        _ = await slowFetch
        let finalWatchlist = await coord.watchlist
        XCTAssertEqual(finalWatchlist.count, 2)
    }

    func testAllStocksL10nKeysExistInStore() throws {
        let store = try L10nFixture.load()
        for kind in StockAssetKind.allCases {
            XCTAssertNotNil(store.entries[kind.badgeKey], "Missing badgeKey \(kind.badgeKey)")
        }
        let errors: [StocksError] = [.networkUnavailable, .rateLimited, .timeout, .symbolNotFound("X"), .unsupportedRange, .invalidData]
        for err in errors {
            let p = StocksErrorPresentation(for: err)
            XCTAssertNotNil(store.entries[p.titleKey], "Missing titleKey \(p.titleKey)")
            if let hint = p.hintKey {
                XCTAssertNotNil(store.entries[hint], "Missing hintKey \(hint)")
            }
        }
    }

    func testInvalidPricesAndNegativePreviousCloseRejectMovementAndComputeDecimalMath() {
        let asset = sampleAssets()[1]
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)

        let zeroPrice = StockQuote(asset: asset, price: 0, previousClose: 200, quotedAt: t0, fetchedAt: t0, sessionState: .open)
        let negativePrice = StockQuote(asset: asset, price: -5, previousClose: 200, quotedAt: t0, fetchedAt: t0, sessionState: .open)
        let negativePrev = StockQuote(asset: asset, price: 200, previousClose: -10, quotedAt: t0, fetchedAt: t0, sessionState: .open)
        let valid = StockQuote(asset: asset, price: 231.40, previousClose: 228.50, quotedAt: t0, fetchedAt: t0, sessionState: .open)

        XCTAssertFalse(zeroPrice.hasValidPrice)
        XCTAssertNil(zeroPrice.changeAmount)
        XCTAssertNil(zeroPrice.changePercent)
        XCTAssertFalse(negativePrice.hasValidPrice)
        XCTAssertNil(negativePrice.changePercent)
        XCTAssertFalse(negativePrev.hasValidPreviousClose)
        XCTAssertNil(negativePrev.changePercent)

        XCTAssertEqual(valid.changeAmountDecimal, Decimal(string: "2.90"))
        XCTAssertEqual(valid.changePercentDecimal, Decimal(string: "1.2691"))
        XCTAssertFalse(StockSymbolKey(symbol: "  ", exchange: "NASDAQ", providerAssetId: "id").isValid)
    }

    @MainActor
    func testStaleBadgesSurfaceOutsideOpenSessionAndClosedTimeUsesClosedAtDSTOffset() throws {
        let asset = sampleAssets()[1]
        // Friday 2026-10-30 16:00 EDT (20:00Z) close, observed after Fall-Back on Sunday 2026-11-01 12:00 EST (17:00Z).
        let fridayClose = try Date("2026-10-30T20:00:00Z", strategy: .iso8601)
        let sundaySync = try Date("2026-11-01T17:00:00Z", strategy: .iso8601)
        let closedQuote = StockQuote(
            asset: asset,
            price: 230.0,
            previousClose: 228.0,
            quotedAt: sundaySync,
            fetchedAt: sundaySync,
            sessionState: .closed(lastCloseAt: fridayClose),
            delayMinutes: 15
        )
        let closeTime = closedQuote.formattedQuoteTime(locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertTrue(["16:00 EDT", "16:00 GMT-4"].contains(closeTime), closeTime)
        XCTAssertTrue(closedQuote.isSourceDelayed)
        XCTAssertFalse(closedQuote.isCacheStale(at: sundaySync.addingTimeInterval(60)))
        XCTAssertTrue(closedQuote.isCacheStale(at: sundaySync.addingTimeInterval(4000)))
        XCTAssertTrue(closedQuote.isCacheStale(at: sundaySync.addingTimeInterval(-120)), "Future-skewed fetchedAt must be stale")

        let provider = ScriptedStocksProvider()
        let staleClock = sundaySync.addingTimeInterval(4000)
        let vm = StocksViewModel(
            coordinator: StocksCoordinator(provider: provider, watchlistStore: InMemoryStocksWatchlistStore(initial: [asset])),
            clock: { staleClock }
        )
        XCTAssertEqual(vm.sessionBadgeText(for: closedQuote), L10n.t("Dữ liệu cũ"))

        let expiredVM = StocksViewModel(
            coordinator: StocksCoordinator(provider: provider, watchlistStore: InMemoryStocksWatchlistStore(initial: [asset])),
            clock: { sundaySync.addingTimeInterval(25_000) }
        )
        XCTAssertEqual(expiredVM.sessionBadgeText(for: closedQuote), L10n.t("Hết hạn cache"))
    }

    func testMissingQuoteInBatchSurfacesErrorWhilePreservingCachedQuote() async {
        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        let assets = Array(sampleAssets().prefix(2))
        let provider = ScriptedStocksProvider()
        let q0 = StockQuote(asset: assets[0], price: 5100, previousClose: 5050, quotedAt: t0, fetchedAt: t0, sessionState: .open)
        let q1 = StockQuote(asset: assets[1], price: 205, previousClose: 200, quotedAt: t0, fetchedAt: t0, sessionState: .open)
        await provider.configure(quotesById: [assets[0].id: q0, assets[1].id: q1])

        let coord = StocksCoordinator(provider: provider, watchlistStore: InMemoryStocksWatchlistStore(initial: assets), clock: { t0 })
        await coord.openPage()

        // Next batch omits assets[1] completely without explicit perAssetErrors entry.
        await provider.configure(quotesById: [assets[0].id: q0])
        await coord.refresh(force: true)

        if case .ready(let rows, _, _, _) = await coord.state {
            XCTAssertNil(rows[assets[0].id]?.error)
            XCTAssertEqual(rows[assets[1].id]?.error, .invalidData, "Omitted quote must report an error")
            XCTAssertEqual(rows[assets[1].id]?.quote, q1, "Prior cached quote must remain available alongside error")
        } else {
            XCTFail("Expected .ready state")
        }
    }

    func testDefaultSeedMigrationAndDeliberatelyEmptyWatchlistPersistence() {
        let suiteName = "com.xfinder.tests.stocks.watchlist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. Fresh unconfigured store seeds exactly S&P 500 index, AAPL, NVDA, CROX, and spot BTC/USD.
        let store = UserDefaultsStocksWatchlistStore(defaults: defaults, key: "wl.test")
        XCTAssertFalse(store.hasSavedConfiguration)
        let seeded = store.loadWatchlist()
        XCTAssertEqual(seeded.map(\.shortTicker), ["SPX", "AAPL", "NVDA", "CROX", "BTC/USD"])
        XCTAssertEqual(seeded[0].kind, .index)
        XCTAssertEqual(seeded[4].kind, .crypto)
        XCTAssertEqual(seeded[4].timeZoneIdentifier, "UTC")

        // 2. Existing custom saved list (migration case) is preserved verbatim without injecting CROX/BTC.
        store.saveWatchlist([StocksWatchlistCatalog.apple])
        XCTAssertTrue(store.hasSavedConfiguration)
        XCTAssertEqual(store.loadWatchlist().map(\.shortTicker), ["AAPL"])

        // 3. Deliberately emptying the list persists `[]` and NEVER re-seeds defaults on reload.
        store.saveWatchlist([])
        XCTAssertTrue(store.hasSavedConfiguration)
        XCTAssertEqual(store.loadWatchlist(), [])

        // 4. Explicit reset restores the 5 defaults.
        store.resetToDefaults()
        XCTAssertEqual(store.loadWatchlist().map(\.shortTicker), ["SPX", "AAPL", "NVDA", "CROX", "BTC/USD"])
    }

    @MainActor
    func testWeekend24x7BitcoinSessionIndependentFromClosedUSEquitiesAndStaleSelectionCleared() async {
        let suiteName = "com.xfinder.tests.stocks.weekend.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsStocksWatchlistStore(defaults: defaults, key: "wl.weekend")
        let sixAssets = StocksWatchlistCatalog.defaultWatchlist + [StocksWatchlistCatalog.longNameInstrument]
        store.saveWatchlist(sixAssets)

        let weekendBatch = StocksOfflineFixtures.weekendBatch(
            for: sixAssets,
            missingAssetIds: [StocksWatchlistCatalog.crocs.id]
        )
        let provider = ScriptedStocksProvider()
        await provider.configure(quotesById: weekendBatch.quotes, perAssetErrors: weekendBatch.errorsByAssetId)

        let coord = StocksCoordinator(
            provider: provider,
            watchlistStore: store,
            isConfigured: true,
            clock: { StocksOfflineFixtures.weekendObservation }
        )
        let vm = StocksViewModel(coordinator: coord, clock: { StocksOfflineFixtures.weekendObservation })
        await coord.openPage()
        await vm.syncState()

        XCTAssertEqual(vm.watchlist.count, 6)
        let aaplQuote = vm.rowState(for: StocksWatchlistCatalog.apple.id)?.quote
        let btcQuote = vm.rowState(for: StocksWatchlistCatalog.bitcoinSpot.id)?.quote
        let croxRow = vm.rowState(for: StocksWatchlistCatalog.crocs.id)

        XCTAssertNotNil(aaplQuote)
        XCTAssertNotNil(btcQuote)
        XCTAssertEqual(croxRow?.error, .invalidData, "Missing CROX quote isolated without breaking other 5 rows")
        XCTAssertEqual(aaplQuote?.changeBasis, .previousClose)
        XCTAssertEqual(btcQuote?.sessionState, .continuous24x7)
        XCTAssertEqual(btcQuote?.changeBasis, .rolling24Hours)
        XCTAssertEqual(vm.sourceDisplayName(for: btcQuote!), "Crypto Spot 24/7 (QA)")
        XCTAssertTrue(vm.sessionBadgeText(for: btcQuote!).hasPrefix("24/7 · "))
        XCTAssertTrue(vm.sessionBadgeText(for: aaplQuote!).hasPrefix(L10n.t("Đóng cửa")))

        // Stale cache still overrides 24/7 crypto badge.
        let staleVM = StocksViewModel(
            coordinator: coord,
            clock: { StocksOfflineFixtures.weekendObservation.addingTimeInterval(4_000) }
        )
        XCTAssertEqual(staleVM.sessionBadgeText(for: btcQuote!), L10n.t("Dữ liệu cũ"))

        // Removing the selected asset in Settings (via shared store) clears stale selection on Island reload.
        vm.selectedAssetId = StocksWatchlistCatalog.bitcoinSpot.id
        store.saveWatchlist([])
        await coord.reloadWatchlistFromStore()
        await vm.syncState()
        XCTAssertEqual(vm.watchlist, [])
        XCTAssertNil(vm.selectedAssetId, "Emptying watchlist must clear stale selection")
        XCTAssertEqual(vm.state, .empty)
    }

    func testAllQuoteChangeBasisAndCryptoKindL10nKeysExistInStore() throws {
        let store = try L10nFixture.load()
        for basis in QuoteChangeBasis.allCases {
            XCTAssertNotNil(store.entries[basis.labelKey], "Missing changeBasis labelKey \(basis.labelKey)")
        }
        XCTAssertNotNil(store.entries[StockAssetKind.crypto.badgeKey])
    }
}

final class TwelveDataStocksProviderTests: XCTestCase {
    func testDemoShowsActualResponseSeriesAndLeavesUnsupportedSymbolsIndependent() async throws {
        let apple = StocksWatchlistCatalog.apple
        let nvidia = StocksWatchlistCatalog.nvidia
        let now = try Date("2026-11-27T18:00:00Z", strategy: .iso8601)
        let provider = TwelveDataStocksProvider(apiKey: "demo", now: { now }) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "apikey demo")
            XCTAssertEqual(request.url?.host, "api.twelvedata.com")
            XCTAssertEqual(request.url?.path, "/time_series")
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            XCTAssertEqual(query?.first { $0.name == "symbol" }?.value, "AAPL")
            XCTAssertNil(query?.first { $0.name == "apikey" })
            return (Data("""
                {"meta":{"symbol":"AAPL","currency":"USD","type":"Common Stock"},"values":[
                    {"datetime":"2026-11-27","close":"200"},
                    {"datetime":"2026-11-25","close":"150"},
                    {"datetime":"2026-11-24","close":"125"},
                    {"datetime":"2026-11-23","close":null},
                    {"datetime":"2026-11-18","close":"100"}
                ]}
                """.utf8), 200)
        }
        let batch = try await provider.fetchQuotes(for: [apple, nvidia])
        let quote = try XCTUnwrap(batch.quotes[apple.id])
        XCTAssertEqual(quote.price, 150)
        XCTAssertEqual(quote.changePercent, 20)
        XCTAssertEqual(quote.series(for: .oneWeek).map(\.price), [125, 150])
        XCTAssertEqual(quote.series(for: .oneMonth).map(\.price), [100, 125, 150])
        XCTAssertEqual(batch.errorsByAssetId[nvidia.id], .accessRequired)
    }

    func testIndexRejectsAnUnrelatedInstrumentWithTheSameSymbol() async throws {
        let index = StocksWatchlistCatalog.sp500Index
        let provider = TwelveDataStocksProvider(apiKey: "test-key") { request in
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            XCTAssertEqual(query?.first { $0.name == "type" }?.value, "Index")
            return (Data("""
                {"meta":{"symbol":"SPX","currency":"USD","type":"ETF"},"values":[
                    {"datetime":"2025-10-16","close":"170"}
                ]}
                """.utf8), 200)
        }
        let batch = try await provider.fetchQuotes(for: [index])
        XCTAssertTrue(batch.quotes.isEmpty)
        XCTAssertEqual(batch.errorsByAssetId[index.id], .invalidData)
    }
}

final class MassiveStocksProviderTests: XCTestCase {
    func testPublicQuoteLinksUseEachMarketSymbol() {
        XCTAssertEqual(StocksWatchlistCatalog.nvidia.publicQuoteURL?.absoluteString, "https://finance.yahoo.com/quote/NVDA/")
        XCTAssertEqual(StocksWatchlistCatalog.crocs.publicQuoteURL?.absoluteString, "https://finance.yahoo.com/quote/CROX/")
        XCTAssertEqual(StocksWatchlistCatalog.shopifyNYSE.publicQuoteURL?.absoluteString, "https://finance.yahoo.com/quote/SHOP/")
    }

    func testUsesIndexTickerAndCompletedDailyBarsAndIsolatesAccessErrors() async throws {
        let now = try Date("2026-11-27T18:00:00Z", strategy: .iso8601)
        let earlier = try Date("2026-11-24T05:00:00Z", strategy: .iso8601)
        let later = try Date("2026-11-25T05:00:00Z", strategy: .iso8601)
        let provider = MassiveStocksProvider(apiKey: "test-key", now: { now }) { request in
            XCTAssertEqual(request.url?.host, "api.massive.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            XCTAssertFalse(request.url?.absoluteString.contains("test-key") ?? true)
            if request.url?.path.contains("/I:SPX/") == true {
                XCTAssertTrue(request.url?.path.hasSuffix("/2026-11-26") == true)
                return (Data("""
                    {"ticker":"I:SPX","results":[
                      {"t":\(later.timeIntervalSince1970 * 1000),"c":6250},
                      {"t":\(earlier.timeIntervalSince1970 * 1000),"c":6200},
                      {"t":\(now.timeIntervalSince1970 * 1000),"c":9900}
                    ]}
                    """.utf8), 200)
            }
            XCTAssertTrue(request.url?.path.contains("/CROX/") == true)
            return (Data(), 403)
        }
        let index = StocksWatchlistCatalog.sp500Index
        let crocs = StocksWatchlistCatalog.crocs
        let batch = try await provider.fetchQuotes(for: [index, crocs])
        let quote = try XCTUnwrap(batch.quotes[index.id])
        XCTAssertEqual(quote.price, 6250)
        XCTAssertEqual(quote.series(for: .oneWeek).map(\.price), [6200, 6250])
        XCTAssertEqual(batch.errorsByAssetId[crocs.id], .accessRequired)
    }

    func testDemoAccessPresentationDistinguishesDemoFromAccountAccessError() {
        let demoProvider = TwelveDataStocksProvider(apiKey: "demo")
        let keyProvider = TwelveDataStocksProvider(apiKey: "personal-key")
        let massiveProvider = MassiveStocksProvider(apiKey: "personal-key")
        XCTAssertTrue(demoProvider.isDemoAccess)
        XCTAssertFalse(keyProvider.isDemoAccess)
        XCTAssertFalse(massiveProvider.isDemoAccess)

        let demoPres = StocksErrorPresentation(for: .accessRequired, context: .quote, isDemoAccess: true)
        XCTAssertEqual(demoPres.titleKey, "Cần khóa API (chế độ demo)")
        XCTAssertEqual(demoPres.hintKey, "Chế độ demo chỉ hỗ trợ AAPL & BTC/USD — thêm khóa API miễn phí trong Cài đặt.")

        let accountPres = StocksErrorPresentation(for: .accessRequired, context: .quote, isDemoAccess: false)
        XCTAssertEqual(accountPres.titleKey, "Cần quyền truy cập nguồn giá")
        XCTAssertEqual(accountPres.hintKey, "Kiểm tra khóa API hoặc gói tài khoản trong Cài đặt nguồn giá.")
    }
}
