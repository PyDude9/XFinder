import Foundation

/// Massive's personal Basic plans expose historical daily bars for eligible tickers.
struct MassiveStocksProvider: StocksProvider {
    let id = "massive-daily"
    let supportedRanges: [StockChartRange] = [.oneWeek, .oneMonth]
    var attribution: StocksProviderAttribution {
        .init(providerId: id, serviceName: "Massive", noticeKey: "Giá đóng cửa theo ngày")
    }

    private let apiKey: String
    private let now: @Sendable () -> Date
    private let fetch: TwelveDataStocksProvider.Fetch

    init(apiKey: String, now: @escaping @Sendable () -> Date = { Date() },
         fetch: @escaping TwelveDataStocksProvider.Fetch = { request in
             let (data, response) = try await URLSession.shared.data(for: request)
             return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
         }) {
        self.apiKey = apiKey
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
            do {
                quotes[asset.id] = try await quote(for: asset)
            } catch let error as StocksError {
                errors[asset.id] = error
            } catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                errors[asset.id] = error.code == .timedOut ? .timeout : .networkUnavailable
            }
        }
        return StocksBatchResult(quotes: quotes, errorsByAssetId: errors)
    }

    private func quote(for asset: StockAssetDescriptor) async throws -> StockQuote {
        let ticker: String
        switch asset.kind {
        case .index:
            guard asset.id == StocksWatchlistCatalog.sp500Index.id else { throw StocksError.symbolNotFound(asset.shortTicker) }
            ticker = "I:SPX"
        case .crypto:
            guard asset.id == StocksWatchlistCatalog.bitcoinSpot.id else { throw StocksError.symbolNotFound(asset.shortTicker) }
            ticker = "X:BTCUSD"
        case .equity, .etf:
            guard asset.currency == "USD", asset.timeZoneIdentifier == "America/New_York" else {
                throw StocksError.symbolNotFound(asset.shortTicker)
            }
            ticker = asset.shortTicker
        }
        guard !ticker.isEmpty, ticker.utf8.count <= 32,
              ticker.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) || $0 == 46 || $0 == 58 || $0 == 45 }) else {
            throw StocksError.symbolNotFound(asset.shortTicker)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = asset.timeZone
        let fetchedAt = now()
        let today = calendar.startOfDay(for: fetchedAt)
        guard let from = calendar.date(byAdding: .day, value: -45, to: today),
              let to = calendar.date(byAdding: .day, value: -1, to: today) else { throw StocksError.invalidData }
        let dateFormat = DateFormatter()
        dateFormat.locale = Locale(identifier: "en_US_POSIX")
        dateFormat.timeZone = calendar.timeZone
        dateFormat.dateFormat = "yyyy-MM-dd"

        var endpoint = URLComponents()
        endpoint.scheme = "https"
        endpoint.host = "api.massive.com"
        endpoint.path = "/v2/aggs/ticker/\(ticker)/range/1/day/\(dateFormat.string(from: from))/\(dateFormat.string(from: to))"
        endpoint.queryItems = [.init(name: "sort", value: "asc")]
        guard let url = endpoint.url else { throw StocksError.invalidData }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, status) = try await fetch(request)
        switch status {
        case 200..<300: break
        case 401, 403: throw StocksError.accessRequired
        case 404: throw StocksError.symbolNotFound(asset.shortTicker)
        case 429: throw StocksError.rateLimited
        case 500...599: throw StocksError.networkUnavailable
        default: throw StocksError.invalidData
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.ticker == ticker, let results = response.results else { throw StocksError.invalidData }
        var daily: [Date: Double] = [:]
        for entry in results.prefix(50) where entry.c.isFinite && entry.c > 0 {
            let date = Date(timeIntervalSince1970: entry.t / 1000)
            if date >= from && date < today { daily[date] = entry.c }
        }
        let points = daily.map { StockPricePoint(timestamp: $0.key, price: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let last = points.last else { throw StocksError.invalidData }
        let week = calendar.date(byAdding: .day, value: -6, to: last.timestamp) ?? last.timestamp
        let month = calendar.date(byAdding: .day, value: -29, to: last.timestamp) ?? last.timestamp
        return StockQuote(asset: asset, price: last.price, previousClose: points.dropLast().last?.price,
                          quotedAt: last.timestamp, fetchedAt: fetchedAt,
                          sessionState: asset.kind == .crypto ? .continuous24x7 : .unknown,
                          changeBasis: asset.kind == .crypto ? .utcMidnight : .previousClose,
                          sourceName: attribution.serviceName, supportedRanges: supportedRanges,
                          seriesByRange: [.oneWeek: points.filter { $0.timestamp >= week },
                                          .oneMonth: points.filter { $0.timestamp >= month }])
    }

    private struct Response: Decodable {
        let ticker: String?
        let results: [Bar]?
    }

    private struct Bar: Decodable {
        let c: Double
        let t: Double
    }
}
