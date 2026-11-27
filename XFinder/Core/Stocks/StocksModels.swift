import Foundation

/// Distinguishes market indices (e.g. S&P 500 index), index-tracking ETFs, equities, and 24/7 spot crypto
/// so index feeds, ETFs, and 24/7 crypto markets are never conflated inside search or watchlist rows.
public enum StockAssetKind: String, Equatable, Hashable, Codable, CaseIterable, Sendable {
    case index
    case equity
    case etf
    case crypto

    public var badgeKey: String {
        switch self {
        case .index: return "Chỉ số"
        case .equity: return "Cổ phiếu"
        case .etf: return "Quỹ ETF"
        case .crypto: return "Tiền số 24/7"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .index: return "chart.xyaxis.line"
        case .equity: return "building.2.fill"
        case .etf: return "square.stack.3d.up.fill"
        case .crypto: return "bitcoinsign.circle.fill"
        }
    }
}

/// Canonical asset key partitioned by symbol, exchange, and provider-specific identifier
/// so duplicate tickers listed on different exchanges remain distinct rows.
public struct StockSymbolKey: Equatable, Hashable, Codable, Sendable {
    public let symbol: String
    public let exchange: String
    public let providerAssetId: String

    public init(symbol: String, exchange: String, providerAssetId: String) {
        self.symbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        self.exchange = exchange.trimmingCharacters(in: .whitespacesAndNewlines)
        self.providerAssetId = providerAssetId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !symbol.isEmpty && !exchange.isEmpty && !providerAssetId.isEmpty
    }

    public var canonicalId: String {
        "\(exchange.uppercased()):\(symbol.uppercased())#\(providerAssetId)"
    }
}

public struct StockAssetDescriptor: Equatable, Hashable, Codable, Identifiable, Sendable {
    public var id: String { key.providerAssetId }
    public var exchange: String { key.exchange }
    public let key: StockSymbolKey
    public let displayName: String
    public let shortTicker: String
    public let providerCode: String
    public let kind: StockAssetKind
    public let currency: String
    public let timeZoneIdentifier: String

    public init(
        key: StockSymbolKey,
        displayName: String,
        shortTicker: String,
        providerCode: String,
        kind: StockAssetKind,
        currency: String = "USD",
        timeZoneIdentifier: String = "America/New_York"
    ) {
        self.key = key
        self.displayName = displayName
        self.shortTicker = shortTicker
        self.providerCode = providerCode
        self.kind = kind
        self.currency = currency
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(identifier: "America/New_York") ?? .current
    }

    var publicQuoteURL: URL? {
        let ticker = id == StocksWatchlistCatalog.shopifyNYSE.id ? "SHOP" : providerCode
        guard !ticker.isEmpty, ticker.utf8.count <= 32,
              ticker.utf8.allSatisfy({ byte in
                  (65...90).contains(byte) || (48...57).contains(byte) || [45, 46, 94].contains(byte)
              }) else { return nil }
        var url = URLComponents()
        url.scheme = "https"
        url.host = "finance.yahoo.com"
        url.path = "/quote/\(ticker)/"
        return url.url
    }
}

public enum MarketSessionState: Equatable, Hashable, Codable, Sendable {
    case open
    case closed(lastCloseAt: Date)
    case preMarket
    case afterHours
    case continuous24x7
    case unknown
}

/// Identifies the reference price baseline used to compute `changeAmount` / `changePercent`.
public enum QuoteChangeBasis: String, Equatable, Hashable, Codable, CaseIterable, Sendable {
    case previousClose
    case rolling24Hours
    case utcMidnight
    case unknown

    public var labelKey: String {
        switch self {
        case .previousClose: return "So với đóng phiên trước"
        case .rolling24Hours: return "So với 24 giờ trước"
        case .utcMidnight: return "So với 00:00 UTC"
        case .unknown: return "Chưa rõ mốc so sánh"
        }
    }
}

public enum QuoteFreshness: Equatable, Hashable, Sendable {
    case live
    case delayed(minutes: Int)
    case stale(age: TimeInterval)
    case expired

    public var isUsable: Bool {
        switch self {
        case .live, .delayed, .stale: return true
        case .expired: return false
        }
    }
}

public enum StockChartRange: String, Equatable, Hashable, Codable, CaseIterable, Identifiable, Sendable {
    case oneDay = "1D"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case threeMonths = "3M"

    public var id: String { rawValue }
}

public struct StockPricePoint: Equatable, Hashable, Codable, Sendable {
    public let timestamp: Date
    public let price: Double

    public init(timestamp: Date, price: Double) {
        self.timestamp = timestamp
        self.price = price
    }
}

public struct StockQuote: Equatable, Codable, Sendable {
    public let asset: StockAssetDescriptor
    public let price: Double?
    public let previousClose: Double?
    public let quotedAt: Date
    public let fetchedAt: Date
    public let sessionState: MarketSessionState
    public let delayMinutes: Int?
    public let changeBasis: QuoteChangeBasis
    public let sourceName: String?
    public let supportedRanges: [StockChartRange]
    public let seriesByRange: [StockChartRange: [StockPricePoint]]

    public init(
        asset: StockAssetDescriptor,
        price: Double?,
        previousClose: Double?,
        quotedAt: Date,
        fetchedAt: Date,
        sessionState: MarketSessionState,
        delayMinutes: Int? = nil,
        changeBasis: QuoteChangeBasis? = nil,
        sourceName: String? = nil,
        supportedRanges: [StockChartRange] = [.oneDay, .oneWeek],
        seriesByRange: [StockChartRange: [StockPricePoint]] = [:]
    ) {
        self.asset = asset
        self.price = price
        self.previousClose = previousClose
        self.quotedAt = quotedAt
        self.fetchedAt = fetchedAt
        self.sessionState = sessionState
        self.delayMinutes = delayMinutes
        self.changeBasis = changeBasis ?? (asset.kind == .crypto ? .rolling24Hours : .previousClose)
        self.sourceName = sourceName
        self.supportedRanges = supportedRanges
        self.seriesByRange = seriesByRange
    }

    public var isSourceDelayed: Bool {
        (delayMinutes ?? 0) > 0
    }

    public var hasValidPrice: Bool {
        guard let price else { return false }
        return price.isFinite && price > 0
    }

    public var hasValidPreviousClose: Bool {
        guard let previousClose else { return false }
        return previousClose.isFinite && previousClose > 0
    }

    public var priceDecimal: Decimal? {
        guard let price, price.isFinite, price > 0 else { return nil }
        return Decimal(string: String(price), locale: Locale(identifier: "en_US_POSIX"))
    }

    public var previousCloseDecimal: Decimal? {
        guard let previousClose, previousClose.isFinite, previousClose > 0 else { return nil }
        return Decimal(string: String(previousClose), locale: Locale(identifier: "en_US_POSIX"))
    }

    public var changeAmountDecimal: Decimal? {
        guard let priceDec = priceDecimal, let prevDec = previousCloseDecimal else {
            return nil
        }
        return priceDec - prevDec
    }

    /// Computes percentage change in base-10 `Decimal` strictly when both price and reference close are valid (`> 0`).
    public var changePercentDecimal: Decimal? {
        guard let delta = changeAmountDecimal, let prev = previousCloseDecimal, prev > 0 else {
            return nil
        }
        var raw = (delta / prev) * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 4, .bankers)
        return rounded
    }

    public var changeAmount: Double? {
        guard let delta = changeAmountDecimal else { return nil }
        return NSDecimalNumber(decimal: delta).doubleValue
    }

    /// Computes percentage change strictly when both price and reference price are valid (`> 0`).
    public var changePercent: Double? {
        guard let pct = changePercentDecimal else { return nil }
        return NSDecimalNumber(decimal: pct).doubleValue
    }

    public func isCacheStale(at now: Date, staleThreshold: TimeInterval = 3600) -> Bool {
        let rawAge = now.timeIntervalSince(fetchedAt)
        if rawAge < -60 { return true }
        return max(0, rawAge) >= staleThreshold
    }

    public func effectiveFreshness(
        at now: Date,
        staleThreshold: TimeInterval = 3600,
        expiredThreshold: TimeInterval = 21600
    ) -> QuoteFreshness {
        let rawAge = now.timeIntervalSince(fetchedAt)
        if rawAge < -60 {
            return .stale(age: 0)
        }
        let age = max(0, rawAge)
        if age >= expiredThreshold {
            return .expired
        }
        if age >= staleThreshold {
            return .stale(age: age)
        }
        if let delayMinutes, delayMinutes > 0 {
            return .delayed(minutes: delayMinutes)
        }
        return .live
    }

    public func series(for range: StockChartRange) -> [StockPricePoint] {
        guard supportedRanges.contains(range) else { return [] }
        return seriesByRange[range] ?? []
    }

    public func formattedPrice() -> String {
        guard let price, price.isFinite, price > 0 else {
            return L10n.t("Thiếu giá")
        }
        let formatted = Self.numberString(price, decimals: 2)
        if asset.kind == .index {
            return formatted
        }
        return asset.currency == "USD" ? "$\(formatted)" : "\(formatted) \(asset.currency)"
    }

    public func formattedChangePercent() -> String? {
        guard let pct = changePercent, pct.isFinite else { return nil }
        let sign = pct >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", pct))%"
    }

    public func formattedChangeAmount() -> String? {
        guard let delta = changeAmount, delta.isFinite else { return nil }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Self.numberString(delta, decimals: 2))"
    }

    public func formattedQuoteTime(locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = asset.timeZone
        formatter.dateFormat = "HH:mm"
        let displayDate: Date
        switch sessionState {
        case .closed(let closedAt):
            displayDate = closedAt
        default:
            displayDate = quotedAt
        }
        let tzAbbr = asset.timeZone.abbreviation(for: displayDate) ?? asset.timeZone.identifier
        return "\(formatter.string(from: displayDate)) \(tzAbbr)"
    }

    private static func numberString(_ value: Double, decimals: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }
}

public struct StocksProviderAttribution: Equatable, Codable, Sendable {
    public let providerId: String
    public let serviceName: String
    public let noticeKey: String

    public init(providerId: String, serviceName: String, noticeKey: String = "Dữ liệu mẫu QA — không phải giá thật") {
        self.providerId = providerId
        self.serviceName = serviceName
        self.noticeKey = noticeKey
    }
}

public enum StocksRowState: Equatable, Sendable {
    case loading
    case loaded(StockQuote)
    case failed(error: StocksError, cached: StockQuote?)

    public var quote: StockQuote? {
        switch self {
        case .loading: return nil
        case .loaded(let q): return q
        case .failed(_, let cached): return cached
        }
    }

    public var error: StocksError? {
        switch self {
        case .loading, .loaded: return nil
        case .failed(let err, _): return err
        }
    }
}

public enum StocksUIState: Equatable, Sendable {
    case unconfigured
    case empty
    case loadingInitial(watchlist: [StockAssetDescriptor])
    case ready(rows: [String: StocksRowState], refreshing: Bool, bannerError: StocksError?, lastUpdatedAt: Date?)
    case offlineNoData(error: StocksError)
    case failedNoData(error: StocksError)
}
