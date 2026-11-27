import Foundation

/// Canonical Stocks & 24/7 Spot Crypto catalog, default seed watchlist, and offline QA fixtures.
///
/// Rules (docs/specs/XF-ISLAND-STOCKS-REVENUE-plan.md):
/// - `defaultWatchlist` seeds S&P 500 index, AAPL, NVDA, CROX, and spot BTC/USD ONLY when no saved
///   watchlist configuration exists yet.
/// - Existing user watchlists — including a deliberately emptied `[]` list — are never overwritten.
/// - Contains no live prices; `StocksOfflineFixtures` is strictly for offline QA and unit tests.
public enum StocksWatchlistCatalog {
    public static let sp500Index = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "S&P 500", exchange: "US Index", providerAssetId: "idx:sp500"),
        displayName: "S&P 500",
        shortTicker: "SPX",
        providerCode: "^GSPC",
        kind: .index,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let apple = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "AAPL", exchange: "NASDAQ", providerAssetId: "eq:nasdaq:aapl"),
        displayName: "Apple Inc.",
        shortTicker: "AAPL",
        providerCode: "AAPL",
        kind: .equity,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let nvidia = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "NVDA", exchange: "NASDAQ", providerAssetId: "eq:nasdaq:nvda"),
        displayName: "NVIDIA Corp.",
        shortTicker: "NVDA",
        providerCode: "NVDA",
        kind: .equity,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let crocs = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "CROX", exchange: "NASDAQ", providerAssetId: "eq:nasdaq:crox"),
        displayName: "Crocs, Inc.",
        shortTicker: "CROX",
        providerCode: "CROX",
        kind: .equity,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let bitcoinSpot = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "BTC/USD", exchange: "Spot 24/7", providerAssetId: "crypto:spot:btcusd"),
        displayName: "Bitcoin",
        shortTicker: "BTC/USD",
        providerCode: "BTC-USD",
        kind: .crypto,
        currency: "USD",
        timeZoneIdentifier: "UTC"
    )

    public static let spyETF = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "SPY", exchange: "NYSE Arca", providerAssetId: "etf:nyse:spy"),
        displayName: "SPDR S&P 500 ETF Trust",
        shortTicker: "SPY",
        providerCode: "SPY",
        kind: .etf,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let microsoft = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "MSFT", exchange: "NASDAQ", providerAssetId: "eq:nasdaq:msft"),
        displayName: "Microsoft Corporation",
        shortTicker: "MSFT",
        providerCode: "MSFT",
        kind: .equity,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let shopifyNYSE = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "SHOP", exchange: "NYSE", providerAssetId: "eq:nyse:shop"),
        displayName: "Shopify Inc.",
        shortTicker: "SHOP",
        providerCode: "SHOP.N",
        kind: .equity,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    public static let shopifyTSX = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "SHOP", exchange: "TSX", providerAssetId: "eq:tsx:shop"),
        displayName: "Shopify Inc.",
        shortTicker: "SHOP",
        providerCode: "SHOP.TO",
        kind: .equity,
        currency: "CAD",
        timeZoneIdentifier: "America/Toronto"
    )

    public static let longNameInstrument = StockAssetDescriptor(
        key: StockSymbolKey(symbol: "BRK.B", exchange: "NYSE", providerAssetId: "eq:nyse:brkb"),
        displayName: "Berkshire Hathaway Inc. Class B Common Stock",
        shortTicker: "BRK.B",
        providerCode: "BRK-B",
        kind: .equity,
        currency: "USD",
        timeZoneIdentifier: "America/New_York"
    )

    /// Seeded ONLY for brand-new configurations with no stored watchlist key.
    public static let defaultWatchlist: [StockAssetDescriptor] = [
        sp500Index,
        apple,
        nvidia,
        crocs,
        bitcoinSpot,
    ]

    /// Offline searchable catalog available in Settings even when no quote provider is configured.
    public static let searchableCatalog: [StockAssetDescriptor] = [
        sp500Index,
        apple,
        nvidia,
        crocs,
        bitcoinSpot,
        spyETF,
        microsoft,
        shopifyNYSE,
        shopifyTSX,
        longNameInstrument,
    ]

    public static func search(_ query: String) -> [StockAssetDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return searchableCatalog }
        return searchableCatalog.filter { asset in
            asset.displayName.lowercased().contains(trimmed)
                || asset.shortTicker.lowercased().contains(trimmed)
                || asset.key.symbol.lowercased().contains(trimmed)
                || asset.key.exchange.lowercased().contains(trimmed)
                || asset.providerCode.lowercased().contains(trimmed)
                || asset.kind.rawValue.lowercased().contains(trimmed)
        }
    }
}

/// Deterministic offline QA fixtures (never used as live production prices).
public enum StocksOfflineFixtures {
    /// Saturday 2026-10-17 15:00:00 UTC (11:00 EDT): US equities closed since Friday 16:00 EDT,
    /// while spot BTC/USD trades continuously on a 24/7 session with a rolling 24h change basis.
    public static let weekendObservation = Date(timeIntervalSince1970: 1_792_249_200)
    public static let fridayUSClose = Date(timeIntervalSince1970: 1_792_177_200)

    public static func weekendBatch(
        for assets: [StockAssetDescriptor],
        missingAssetIds: Set<String> = []
    ) -> StocksBatchResult {
        var quotes: [String: StockQuote] = [:]
        var errors: [String: StocksError] = [:]

        for asset in assets {
            if missingAssetIds.contains(asset.id) {
                errors[asset.id] = .invalidData
                continue
            }
            if asset.kind == .crypto {
                quotes[asset.id] = StockQuote(
                    asset: asset,
                    price: 89_420.50,
                    previousClose: 87_900.00,
                    quotedAt: weekendObservation,
                    fetchedAt: weekendObservation,
                    sessionState: .continuous24x7,
                    delayMinutes: 0,
                    changeBasis: .rolling24Hours,
                    sourceName: "Crypto Spot 24/7 (QA)"
                )
            } else {
                let pair = fixturePricePair(for: asset.id)
                quotes[asset.id] = StockQuote(
                    asset: asset,
                    price: pair.price,
                    previousClose: pair.previousClose,
                    quotedAt: fridayUSClose,
                    fetchedAt: weekendObservation,
                    sessionState: .closed(lastCloseAt: fridayUSClose),
                    delayMinutes: 15,
                    changeBasis: .previousClose,
                    sourceName: "US Market Feed (QA)"
                )
            }
        }
        return StocksBatchResult(quotes: quotes, errorsByAssetId: errors)
    }

    private static func fixturePricePair(for assetId: String) -> (price: Double, previousClose: Double) {
        switch assetId {
        case StocksWatchlistCatalog.sp500Index.id: return (5_842.75, 5_810.25)
        case StocksWatchlistCatalog.apple.id: return (231.40, 228.50)
        case StocksWatchlistCatalog.nvidia.id: return (134.80, 138.00)
        case StocksWatchlistCatalog.crocs.id: return (112.60, 110.20)
        case StocksWatchlistCatalog.spyETF.id: return (583.10, 579.80)
        case StocksWatchlistCatalog.microsoft.id: return (426.15, 422.00)
        case StocksWatchlistCatalog.longNameInstrument.id: return (461.20, 459.00)
        default: return (100.00, 99.00)
        }
    }
}
