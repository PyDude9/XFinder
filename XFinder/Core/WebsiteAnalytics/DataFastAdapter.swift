import Foundation

/// Read-only adapter contract implemented independently by DataFast and GA4.
public protocol WebsiteAnalyticsSourceAdapter: Sendable {
    var provider: WebsiteAnalyticsProviderKind { get }
    func fetchReport(range: WebsiteAnalyticsRange, now: Date) async throws -> WebsiteAnalyticsReport
}

/// Read-only DataFast Website API v1 adapter (`https://datafa.st/api/v1/`).
/// Uses a website API key (`df_...`) stored in Keychain; explicitly rejects `dft_` account tokens.
public final class DataFastAdapter: WebsiteAnalyticsSourceAdapter, Sendable {
    public let provider: WebsiteAnalyticsProviderKind = .dataFast

    private let transport: WebsiteAnalyticsHTTPTransport
    private let credentialStore: WebsiteAnalyticsCredentialStore
    private let configStore: WebsiteAnalyticsConfigStore
    private let maxResponseBytes: Int

    public init(
        transport: WebsiteAnalyticsHTTPTransport = URLSessionWebsiteAnalyticsTransport(),
        credentialStore: WebsiteAnalyticsCredentialStore = WebsiteAnalyticsKeychainStore.shared,
        configStore: WebsiteAnalyticsConfigStore = UserDefaultsWebsiteAnalyticsConfigStore(),
        maxResponseBytes: Int = WebsiteAnalyticsLimits.maxResponseBytes
    ) {
        self.transport = transport
        self.credentialStore = credentialStore
        self.configStore = configStore
        self.maxResponseBytes = max(1024, maxResponseBytes)
    }

    public func fetchReport(range: WebsiteAnalyticsRange, now: Date) async throws -> WebsiteAnalyticsReport {
        try Task.checkCancellation()

        guard let config = configStore.loadDataFastConfig() else {
            throw WebsiteAnalyticsError.unconfigured(.missingCredentials)
        }
        guard let rawKey = credentialStore.secret(for: .dataFastAPIKey, accountKey: config.siteId),
              !rawKey.isEmpty else {
            throw WebsiteAnalyticsError.unconfigured(.missingCredentials)
        }
        let apiKey: String
        switch WebsiteAnalyticsHostPolicy.validateDataFastAPIKey(rawKey) {
        case .success(let validated):
            apiKey = validated
        case .failure(let err):
            throw err
        }

        let window = WebsiteAnalyticsDateRules.dateWindow(for: range, now: now, timeZone: config.timeZone)
        let baseQuery = [
            URLQueryItem(name: "startAt", value: window.startDateKey),
            URLQueryItem(name: "endAt", value: window.endDateKey),
            URLQueryItem(name: "timezone", value: window.timeZoneIdentifier),
        ]

        // 1. Overview
        let overviewData = try await get(
            path: "/api/v1/analytics/overview",
            queryItems: baseQuery,
            apiKey: apiKey
        )
        let kpis = try Self.decodeOverview(overviewData)

        try Task.checkCancellation()

        // 2. Timeseries
        var timeseriesQuery = baseQuery
        timeseriesQuery.append(URLQueryItem(name: "fields", value: "visitors,pageviews"))
        timeseriesQuery.append(URLQueryItem(name: "interval", value: "day"))
        timeseriesQuery.append(URLQueryItem(name: "limit", value: String(WebsiteAnalyticsLimits.maxSeriesPoints)))
        let timeseriesData = try await get(
            path: "/api/v1/analytics/timeseries",
            queryItems: timeseriesQuery,
            apiKey: apiKey
        )
        let timeseries = try Self.decodeTimeseries(timeseriesData)

        try Task.checkCancellation()

        // 3. Realtime (optional: 404/501 marks unsupported without fabricating numbers)
        let realtime = try await fetchRealtime(apiKey: apiKey)

        try Task.checkCancellation()

        // 4. Top Pages
        var breakdownQuery = baseQuery
        breakdownQuery.append(URLQueryItem(name: "limit", value: String(WebsiteAnalyticsLimits.maxBreakdownRows)))
        let pagesData = try await get(
            path: "/api/v1/analytics/pages",
            queryItems: breakdownQuery,
            apiKey: apiKey
        )
        let topPages = try Self.decodeBreakdown(pagesData, kind: "pages")

        try Task.checkCancellation()

        // 5. Top Referrers
        let referrersData = try await get(
            path: "/api/v1/analytics/referrers",
            queryItems: breakdownQuery,
            apiKey: apiKey
        )
        let topReferrers = try Self.decodeBreakdown(referrersData, kind: "referrers")

        let siteLabel = config.siteLabel.isEmpty ? "DataFast" : config.siteLabel
        return WebsiteAnalyticsReport(
            provider: .dataFast,
            siteLabel: siteLabel,
            range: range,
            windowStartDateKey: window.startDateKey,
            windowEndDateKey: window.endDateKey,
            timeZoneIdentifier: window.timeZoneIdentifier,
            kpis: kpis,
            realtime: realtime,
            timeseries: timeseries,
            topPages: topPages,
            topReferrers: topReferrers,
            fetchedAt: now
        )
    }

    private func fetchRealtime(apiKey: String) async throws -> WebsiteAnalyticsRealtime {
        guard let url = WebsiteAnalyticsHostPolicy.validatedDataFastURL(path: "/api/v1/analytics/realtime"),
              WebsiteAnalyticsHostPolicy.validateDataFastOutboundURL(url) else {
            throw WebsiteAnalyticsError.invalidConfiguration("invalid_datafast_url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request, maxBytes: maxResponseBytes)
        if response.statusCode == 404 || response.statusCode == 501 {
            return .unsupported
        }
        if let httpError = WebsiteAnalyticsHostPolicy.mapHTTPStatus(
            response.statusCode,
            retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw httpError
        }
        return try Self.decodeRealtime(data)
    }

    private func get(path: String, queryItems: [URLQueryItem], apiKey: String) async throws -> Data {
        try Task.checkCancellation()
        guard let url = WebsiteAnalyticsHostPolicy.validatedDataFastURL(path: path, queryItems: queryItems),
              WebsiteAnalyticsHostPolicy.validateDataFastOutboundURL(url) else {
            throw WebsiteAnalyticsError.invalidConfiguration("invalid_datafast_url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await transport.send(request, maxBytes: maxResponseBytes)
        if data.count > maxResponseBytes {
            throw WebsiteAnalyticsError.oversizedPayload(byteCount: data.count, limit: maxResponseBytes)
        }
        if let httpError = WebsiteAnalyticsHostPolicy.mapHTTPStatus(
            response.statusCode,
            retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After")
        ) {
            throw httpError
        }
        return data
    }

    // MARK: - Pure Decoders

    public static func decodeOverview(_ data: Data) throws -> WebsiteAnalyticsKPIs {
        let root = try parseJSONObject(data)
        try validateEnvelopeStatus(root)

        guard let payload = root["data"] as? [String: Any] else {
            throw WebsiteAnalyticsError.malformedResponse("datafast_overview_missing_data")
        }

        let visitors = try optionalNonNegativeInt(payload, keys: ["visitors", "unique_visitors"])
        let pageviews = try optionalNonNegativeInt(payload, keys: ["pageviews", "page_views", "views"])
        let bounce = try optionalFiniteDouble(payload, keys: ["bounce_rate", "bounceRate"], min: 0, max: 100)
        let duration = try optionalFiniteDouble(
            payload,
            keys: ["avg_session_duration", "average_session_duration", "session_duration"],
            min: 0,
            max: 86_400 * 7
        )

        return WebsiteAnalyticsKPIs(
            visitors: visitors,
            pageviews: pageviews,
            bounceRatePercent: bounce,
            averageSessionDurationSeconds: duration
        )
    }

    public static func decodeTimeseries(_ data: Data) throws -> [WebsiteAnalyticsSeriesPoint] {
        let root = try parseJSONObject(data)
        try validateEnvelopeStatus(root)

        guard let rows = root["data"] as? [[String: Any]] else {
            throw WebsiteAnalyticsError.malformedResponse("datafast_timeseries_missing_array")
        }
        if rows.count > WebsiteAnalyticsLimits.maxSeriesPoints {
            throw WebsiteAnalyticsError.oversizedPayload(byteCount: rows.count, limit: WebsiteAnalyticsLimits.maxSeriesPoints)
        }

        var points: [WebsiteAnalyticsSeriesPoint] = []
        points.reserveCapacity(rows.count)
        for row in rows {
            guard let rawDate = (row["date"] as? String) ?? (row["timestamp"] as? String),
                  let dateKey = WebsiteAnalyticsDateRules.normalizeDateKey(rawDate) else {
                throw WebsiteAnalyticsError.malformedResponse("datafast_timeseries_invalid_date")
            }
            let visitors = try optionalNonNegativeInt(row, keys: ["visitors", "unique_visitors"])
            let pageviews = try optionalNonNegativeInt(row, keys: ["pageviews", "page_views", "views"])
            if visitors == nil && pageviews == nil {
                throw WebsiteAnalyticsError.malformedResponse("datafast_timeseries_missing_metrics")
            }
            points.append(
                WebsiteAnalyticsSeriesPoint(
                    dateKey: dateKey,
                    label: WebsiteAnalyticsDateRules.shortDayLabel(from: dateKey),
                    visitors: visitors,
                    pageviews: pageviews
                )
            )
        }
        return points.sorted { $0.dateKey < $1.dateKey }
    }

    public static func decodeRealtime(_ data: Data) throws -> WebsiteAnalyticsRealtime {
        let root = try parseJSONObject(data)
        try validateEnvelopeStatus(root)

        guard let payload = root["data"] as? [String: Any] else {
            throw WebsiteAnalyticsError.malformedResponse("datafast_realtime_missing_data")
        }
        if let count = try optionalNonNegativeInt(payload, keys: ["count", "active_visitors", "activeVisitors", "visitors_count"]) {
            return WebsiteAnalyticsRealtime(activeVisitors: count, isSupported: true, windowMinutes: 5)
        }
        if let visitorsArray = payload["visitors"] as? [Any] {
            return WebsiteAnalyticsRealtime(activeVisitors: visitorsArray.count, isSupported: true, windowMinutes: 5)
        }
        throw WebsiteAnalyticsError.malformedResponse("datafast_realtime_missing_count")
    }

    public static func decodeBreakdown(_ data: Data, kind: String) throws -> [WebsiteAnalyticsBreakdownItem] {
        let root = try parseJSONObject(data)
        try validateEnvelopeStatus(root)

        guard let rows = root["data"] as? [[String: Any]] else {
            throw WebsiteAnalyticsError.malformedResponse("datafast_\(kind)_missing_array")
        }
        let cappedRows = rows.prefix(WebsiteAnalyticsLimits.maxBreakdownRows)
        var items: [WebsiteAnalyticsBreakdownItem] = []
        items.reserveCapacity(cappedRows.count)

        for (index, row) in cappedRows.enumerated() {
            let rawName = (row["name"] as? String)
                ?? (row["path"] as? String)
                ?? (row["page"] as? String)
                ?? (row["referrer"] as? String)
                ?? (row["source"] as? String)
            guard let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                throw WebsiteAnalyticsError.malformedResponse("datafast_\(kind)_missing_name")
            }
            let visitors = try optionalNonNegativeInt(row, keys: ["visitors", "unique_visitors"])
            let pageviews = try optionalNonNegativeInt(row, keys: ["pageviews", "page_views", "views"])
            if visitors == nil && pageviews == nil {
                throw WebsiteAnalyticsError.malformedResponse("datafast_\(kind)_missing_metrics")
            }
            items.append(
                WebsiteAnalyticsBreakdownItem(
                    id: "\(kind):\(index):\(name)",
                    name: name,
                    visitors: visitors,
                    pageviews: pageviews
                )
            )
        }
        return items
    }

    // MARK: - Strict JSON Value Helpers

    private static func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else {
            throw WebsiteAnalyticsError.malformedResponse("empty_body")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw WebsiteAnalyticsError.malformedResponse("invalid_json")
        }
        guard let dict = object as? [String: Any] else {
            throw WebsiteAnalyticsError.malformedResponse("expected_json_object")
        }
        return dict
    }

    private static func validateEnvelopeStatus(_ root: [String: Any]) throws {
        if let status = root["status"] as? String, status.lowercased() != "success" {
            throw WebsiteAnalyticsError.malformedResponse("datafast_status_\(status)")
        }
    }

    private static func optionalNonNegativeInt(_ dict: [String: Any], keys: [String]) throws -> Int? {
        for key in keys {
            guard let raw = dict[key], !(raw is NSNull) else { continue }
            if let num = raw as? NSNumber {
                // Reject booleans masquerading as NSNumber.
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    throw WebsiteAnalyticsError.malformedResponse("unexpected_bool_\(key)")
                }
                let dbl = num.doubleValue
                guard dbl.isFinite, dbl >= 0, dbl <= Double(Int.max), floor(dbl) == dbl else {
                    throw WebsiteAnalyticsError.malformedResponse("invalid_int_\(key)")
                }
                return Int(dbl)
            }
            if let str = raw as? String {
                guard let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)),
                      parsed.isFinite, parsed >= 0, parsed <= Double(Int.max), floor(parsed) == parsed else {
                    throw WebsiteAnalyticsError.malformedResponse("invalid_int_string_\(key)")
                }
                return Int(parsed)
            }
            throw WebsiteAnalyticsError.malformedResponse("unexpected_type_\(key)")
        }
        return nil
    }

    private static func optionalFiniteDouble(
        _ dict: [String: Any],
        keys: [String],
        min: Double,
        max: Double
    ) throws -> Double? {
        for key in keys {
            guard let raw = dict[key], !(raw is NSNull) else { continue }
            if let num = raw as? NSNumber {
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    throw WebsiteAnalyticsError.malformedResponse("unexpected_bool_\(key)")
                }
                let dbl = num.doubleValue
                guard dbl.isFinite, dbl >= min, dbl <= max else {
                    throw WebsiteAnalyticsError.malformedResponse("invalid_double_\(key)")
                }
                return dbl
            }
            if let str = raw as? String {
                guard let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)),
                      parsed.isFinite, parsed >= min, parsed <= max else {
                    throw WebsiteAnalyticsError.malformedResponse("invalid_double_string_\(key)")
                }
                return parsed
            }
            throw WebsiteAnalyticsError.malformedResponse("unexpected_type_\(key)")
        }
        return nil
    }
}
