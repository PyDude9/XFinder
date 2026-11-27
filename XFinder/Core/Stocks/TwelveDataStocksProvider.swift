import Foundation
import Security

/// Daily bars use the provider's exchange-local date. The UI labels these as closing prices.
struct TwelveDataStocksProvider: StocksProvider {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)
    let apiKey: String
    let isDemo: Bool
    var isDemoAccess: Bool { isDemo }
    let supportedRanges: [StockChartRange] = [.oneWeek, .oneMonth]
    let id = "twelve-data-daily"
    var attribution: StocksProviderAttribution {
        .init(providerId: id, serviceName: "Twelve Data",
              noticeKey: isDemo ? "Giá đóng cửa · Quyền truy cập demo" : "Giá đóng cửa theo ngày")
    }

    private let fetch: Fetch
    private let now: @Sendable () -> Date

    init(apiKey: String, now: @escaping @Sendable () -> Date = { Date() },
         fetch: @escaping Fetch = { request in
             let (data, response) = try await URLSession.shared.data(for: request)
             return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
         }) {
        self.apiKey = apiKey
        self.isDemo = apiKey == "demo"
        self.now = now
        self.fetch = fetch
    }

    func searchSymbols(query: String) async throws -> [StockAssetDescriptor] {
        StocksWatchlistCatalog.search(query)
    }

    func fetchQuotes(for assets: [StockAssetDescriptor]) async throws -> StocksBatchResult {
        var quotes: [String: StockQuote] = [:]
        var errors: [String: StocksError] = [:]
        for asset in assets {
            try Task.checkCancellation()
            if isDemo && asset.id != StocksWatchlistCatalog.apple.id && asset.id != StocksWatchlistCatalog.bitcoinSpot.id {
                errors[asset.id] = .accessRequired
                continue
            }
            do {
                quotes[asset.id] = try await dailyQuote(for: asset)
            } catch let error as StocksError {
                errors[asset.id] = error
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                errors[asset.id] = error.code == .timedOut ? .timeout : .networkUnavailable
            }
        }
        return StocksBatchResult(quotes: quotes, errorsByAssetId: errors)
    }

    private func dailyQuote(for asset: StockAssetDescriptor) async throws -> StockQuote {
        var endpoint = URLComponents()
        endpoint.scheme = "https"
        endpoint.host = "api.twelvedata.com"
        endpoint.path = "/time_series"
        endpoint.queryItems = [
            .init(name: "symbol", value: asset.shortTicker),
            .init(name: "interval", value: "1day"),
            .init(name: "outputsize", value: "33")
        ]
        switch asset.kind {
        case .equity, .etf: endpoint.queryItems?.append(.init(name: "exchange", value: asset.exchange))
        case .index: endpoint.queryItems?.append(.init(name: "type", value: "Index"))
        case .crypto: break
        }
        guard let url = endpoint.url else { throw StocksError.invalidData }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("apikey \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, status) = try await fetch(request)
        if !(200..<300).contains(status) { throw Self.apiError(status, asset: asset) }
        let response = try? JSONDecoder().decode(Response.self, from: data)
        if let code = response?.code, code >= 400 { throw Self.apiError(code, asset: asset) }
        guard let meta = response?.meta, let values = response?.values,
              meta.symbol.caseInsensitiveCompare(asset.shortTicker) == .orderedSame,
              asset.kind != .index || meta.type?.caseInsensitiveCompare("Index") == .orderedSame,
              asset.kind == .crypto || meta.currency == asset.currency else {
            throw StocksError.invalidData
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = asset.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = asset.timeZone
        let observed = now()
        // Use completed local dates. Current-day candles can still be partial.
        let today = calendar.startOfDay(for: observed)
        var pricesByDate: [Date: Double] = [:]
        for bar in values.prefix(33) {
            guard let date = formatter.date(from: bar.datetime), date < today,
                  let price = Double(bar.close ?? ""), price.isFinite, price > 0 else { continue }
            pricesByDate[date] = price
        }
        let points = pricesByDate.map { StockPricePoint(timestamp: $0.key, price: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = points.last else { throw StocksError.invalidData }
        let oneWeekStart = calendar.date(byAdding: .day, value: -6, to: last.timestamp) ?? last.timestamp
        let oneMonthStart = calendar.date(byAdding: .day, value: -29, to: last.timestamp) ?? last.timestamp
        return StockQuote(
            asset: asset, price: last.price, previousClose: points.dropLast().last?.price,
            quotedAt: last.timestamp, fetchedAt: observed,
            sessionState: asset.kind == .crypto ? .continuous24x7 : .unknown,
            changeBasis: asset.kind == .crypto ? .utcMidnight : .previousClose,
            sourceName: attribution.serviceName, supportedRanges: supportedRanges,
            seriesByRange: [.oneWeek: points.filter { $0.timestamp >= oneWeekStart },
                            .oneMonth: points.filter { $0.timestamp >= oneMonthStart }]
        )
    }

    private static func apiError(_ code: Int, asset: StockAssetDescriptor) -> StocksError {
        switch code {
        case 401, 403: .accessRequired
        case 404: .symbolNotFound(asset.shortTicker)
        case 429: .rateLimited
        case 500...599: .networkUnavailable
        default: .invalidData
        }
    }

    private struct Response: Decodable {
        let code: Int?
        let meta: Metadata?
        let values: [Bar]?
    }

    private struct Metadata: Decodable {
        let symbol: String
        let currency: String?
        let type: String?
    }

    private struct Bar: Decodable {
        let datetime: String
        let close: String?
    }
}

enum StocksAPIKey {
    enum Source: String, CaseIterable, Identifiable {
        case twelveData = "twelve-data"
        case massive

        static let preferenceKey = "xfinder.stocks.source"
        var id: String { rawValue }
        var name: String { self == .twelveData ? "Twelve Data" : "Massive" }
    }

    private static func query(for source: Source) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.xfinder.app.stocks",
         kSecAttrAccount as String: source.rawValue]
    }

    static func read(for source: Source = .twelveData) -> String? {
        var item: CFTypeRef?
        var request = query(for: source)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for source: Source = .twelveData) -> Bool {
        let query = query(for: source)
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        guard key.count <= 256, key.utf8.allSatisfy({ (33...126).contains($0) }) else { return false }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
}
