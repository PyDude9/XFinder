import Foundation

// MARK: - Provider & Range

public enum WebsiteAnalyticsProviderKind: String, CaseIterable, Hashable, Codable, Identifiable, Sendable {
    case dataFast = "datafast"
    case googleAnalytics4 = "ga4"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dataFast: return "DataFast"
        case .googleAnalytics4: return "Google Analytics"
        }
    }

    public var shortName: String {
        switch self {
        case .dataFast: return "DataFast"
        case .googleAnalytics4: return "GA4"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .dataFast: return "bolt.horizontal.circle.fill"
        case .googleAnalytics4: return "chart.bar.xaxis"
        }
    }
}

public enum WebsiteAnalyticsRange: String, CaseIterable, Hashable, Codable, Identifiable, Sendable {
    case sevenDays = "7d"
    case thirtyDays = "30d"

    public var id: String { rawValue }

    public var dayCount: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        }
    }

    public var shortLabel: String { rawValue }

    public var titleKey: String {
        switch self {
        case .sevenDays: return "7 ngày"
        case .thirtyDays: return "30 ngày"
        }
    }
}

// MARK: - Configuration (Non-secret metadata only)

public struct DataFastSiteConfig: Equatable, Hashable, Codable, Sendable {
    public let siteId: String
    public let siteLabel: String
    public let timeZoneIdentifier: String

    public init(
        siteId: String = "default",
        siteLabel: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        let trimmedId = siteId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.siteId = trimmedId.isEmpty ? "default" : trimmedId
        self.siteLabel = siteLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeZoneIdentifier = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .current
    }
}

public struct GA4PropertyConfig: Equatable, Hashable, Codable, Sendable {
    public let propertyId: String
    public let propertyLabel: String
    public let oauthClientId: String
    public let redirectURI: String?
    public let timeZoneIdentifier: String

    public init(
        propertyId: String,
        propertyLabel: String,
        oauthClientId: String = "",
        redirectURI: String? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.propertyId = Self.normalizePropertyId(propertyId)
        self.propertyLabel = propertyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.oauthClientId = oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirect = redirectURI?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.redirectURI = (trimmedRedirect?.isEmpty == false) ? trimmedRedirect : nil
        self.timeZoneIdentifier = timeZoneIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizePropertyId(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("properties/") {
            trimmed = String(trimmed.dropFirst("properties/".count))
        }
        return trimmed
    }

    public var isPropertyIdValid: Bool {
        !propertyId.isEmpty && propertyId.count <= 20 && propertyId.allSatisfy(\.isNumber)
    }

    public var hasOAuthClientConfig: Bool {
        !oauthClientId.isEmpty
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .current
    }
}

// MARK: - Metrics & Report

public struct WebsiteAnalyticsKPIs: Equatable, Hashable, Codable, Sendable {
    public let visitors: Int?
    public let pageviews: Int?
    /// Percentage in 0...100 range, or nil if unavailable from the provider.
    public let bounceRatePercent: Double?
    /// Average session duration in seconds (>= 0), or nil if unavailable.
    public let averageSessionDurationSeconds: Double?

    public init(
        visitors: Int?,
        pageviews: Int?,
        bounceRatePercent: Double?,
        averageSessionDurationSeconds: Double?
    ) {
        self.visitors = visitors
        self.pageviews = pageviews
        self.bounceRatePercent = bounceRatePercent
        self.averageSessionDurationSeconds = averageSessionDurationSeconds
    }

    public var hasAnyValue: Bool {
        visitors != nil || pageviews != nil || bounceRatePercent != nil || averageSessionDurationSeconds != nil
    }
}

public struct WebsiteAnalyticsRealtime: Equatable, Hashable, Codable, Sendable {
    public let activeVisitors: Int?
    public let isSupported: Bool
    public let windowMinutes: Int?

    public init(activeVisitors: Int?, isSupported: Bool, windowMinutes: Int? = nil) {
        self.activeVisitors = activeVisitors
        self.isSupported = isSupported
        self.windowMinutes = windowMinutes
    }

    public static let unsupported = WebsiteAnalyticsRealtime(activeVisitors: nil, isSupported: false, windowMinutes: nil)
}

public struct WebsiteAnalyticsSeriesPoint: Equatable, Hashable, Identifiable, Codable, Sendable {
    public var id: String { dateKey }
    /// Canonical calendar day in the provider's reporting timezone (`yyyy-MM-dd`).
    public let dateKey: String
    public let label: String
    public let visitors: Int?
    public let pageviews: Int?

    public init(dateKey: String, label: String, visitors: Int?, pageviews: Int?) {
        self.dateKey = dateKey
        self.label = label
        self.visitors = visitors
        self.pageviews = pageviews
    }

    public var primaryValue: Int {
        visitors ?? pageviews ?? 0
    }
}

public struct WebsiteAnalyticsBreakdownItem: Equatable, Hashable, Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let visitors: Int?
    public let pageviews: Int?

    public init(id: String? = nil, name: String, visitors: Int?, pageviews: Int?) {
        self.id = id ?? name
        self.name = name
        self.visitors = visitors
        self.pageviews = pageviews
    }
}

public struct WebsiteAnalyticsReport: Equatable, Sendable {
    public let provider: WebsiteAnalyticsProviderKind
    public let siteLabel: String
    public let range: WebsiteAnalyticsRange
    public let windowStartDateKey: String
    public let windowEndDateKey: String
    public let timeZoneIdentifier: String
    public let kpis: WebsiteAnalyticsKPIs
    public let realtime: WebsiteAnalyticsRealtime
    public let timeseries: [WebsiteAnalyticsSeriesPoint]
    public let topPages: [WebsiteAnalyticsBreakdownItem]
    public let topReferrers: [WebsiteAnalyticsBreakdownItem]
    public let fetchedAt: Date

    public init(
        provider: WebsiteAnalyticsProviderKind,
        siteLabel: String,
        range: WebsiteAnalyticsRange,
        windowStartDateKey: String,
        windowEndDateKey: String,
        timeZoneIdentifier: String,
        kpis: WebsiteAnalyticsKPIs,
        realtime: WebsiteAnalyticsRealtime,
        timeseries: [WebsiteAnalyticsSeriesPoint],
        topPages: [WebsiteAnalyticsBreakdownItem],
        topReferrers: [WebsiteAnalyticsBreakdownItem],
        fetchedAt: Date
    ) {
        self.provider = provider
        self.siteLabel = siteLabel
        self.range = range
        self.windowStartDateKey = windowStartDateKey
        self.windowEndDateKey = windowEndDateKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.kpis = kpis
        self.realtime = realtime
        self.timeseries = timeseries
        self.topPages = topPages
        self.topReferrers = topReferrers
        self.fetchedAt = fetchedAt
    }

    /// True when the provider returned an empty report with no traffic metrics or rows.
    public var isEffectivelyEmpty: Bool {
        if !kpis.hasAnyValue && timeseries.isEmpty && topPages.isEmpty && topReferrers.isEmpty {
            return true
        }
        let zeroVisitors = (kpis.visitors ?? 0) == 0
        let zeroPageviews = (kpis.pageviews ?? 0) == 0
        let allSeriesZero = timeseries.allSatisfy { ($0.visitors ?? 0) == 0 && ($0.pageviews ?? 0) == 0 }
        return zeroVisitors && zeroPageviews && allSeriesZero && topPages.isEmpty && topReferrers.isEmpty
    }
}

// MARK: - State & Errors

public enum WebsiteAnalyticsUnconfiguredReason: Equatable, Hashable, Sendable {
    case missingCredentials
    case missingProperty
    case oauthNotConfigured
}

public enum WebsiteAnalyticsError: Error, Equatable, Hashable, Sendable {
    case unconfigured(WebsiteAnalyticsUnconfiguredReason)
    case oauthCancelled
    case unauthorized
    case revokedOrForbidden
    case rateLimited(retryAfterSeconds: Int?)
    case serverUnavailable(statusCode: Int)
    case offline
    case timeout
    case cancelled
    case malformedResponse(String)
    case oversizedPayload(byteCount: Int, limit: Int)
    case invalidConfiguration(String)

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverUnavailable, .offline, .timeout:
            return true
        case .unconfigured, .oauthCancelled, .unauthorized, .revokedOrForbidden,
             .cancelled, .malformedResponse, .oversizedPayload, .invalidConfiguration:
            return false
        }
    }

    public var requiresReconnect: Bool {
        switch self {
        case .unauthorized, .revokedOrForbidden, .unconfigured:
            return true
        default:
            return false
        }
    }
}

public struct WebsiteAnalyticsErrorPresentation: Equatable, Sendable {
    public let titleKey: String
    public let hintKey: String
    public let symbolName: String
    public let canRetry: Bool
    public let requiresReconnect: Bool

    public init(for error: WebsiteAnalyticsError) {
        self.canRetry = error.isRetryable
        self.requiresReconnect = error.requiresReconnect
        switch error {
        case .unconfigured(let reason):
            switch reason {
            case .missingCredentials:
                self.titleKey = "Chưa nhập khóa API hoặc xác thực"
                self.hintKey = "Nhập thông tin chỉ đọc để xem thống kê trang web."
                self.symbolName = "key.fill"
            case .missingProperty:
                self.titleKey = "Chưa nhập mã thuộc tính GA4"
                self.hintKey = "Nhập Property ID số để tải báo cáo Google Analytics."
                self.symbolName = "slider.horizontal.3"
            case .oauthNotConfigured:
                self.titleKey = "Chưa cấu hình OAuth cho Google Analytics"
                self.hintKey = "Cần OAuth Client ID và redirect URI đã đăng ký để đăng nhập GA4."
                self.symbolName = "person.crop.circle.badge.exclamationmark"
            }
        case .oauthCancelled:
            self.titleKey = "Đã hủy đăng nhập Google Analytics"
            self.hintKey = "Trạng thái vẫn ngắt kết nối. Thử lại khi sẵn sàng."
            self.symbolName = "xmark.circle"
        case .unauthorized:
            self.titleKey = "Khóa truy cập không hợp lệ hoặc đã hết hạn"
            self.hintKey = "Kết nối lại nguồn dữ liệu để tiếp tục cập nhật."
            self.symbolName = "key.slash.fill"
        case .revokedOrForbidden:
            self.titleKey = "Quyền truy cập đã bị thu hồi hoặc bị từ chối"
            self.hintKey = "Kiểm tra quyền chỉ đọc và kết nối lại tài khoản."
            self.symbolName = "lock.slash.fill"
        case .rateLimited:
            self.titleKey = "Đã chạm giới hạn lượt gọi API"
            self.hintKey = "Dữ liệu gần nhất được giữ nguyên. Thử lại sau ít phút."
            self.symbolName = "hourglass"
        case .serverUnavailable:
            self.titleKey = "Máy chủ phân tích tạm thời không khả dụng"
            self.hintKey = "Dữ liệu cũ được giữ nguyên. Thử làm mới lại sau."
            self.symbolName = "server.rack"
        case .offline:
            self.titleKey = "Không có kết nối mạng"
            self.hintKey = "Đang giữ dữ liệu đã tải gần nhất nếu có."
            self.symbolName = "wifi.slash"
        case .timeout:
            self.titleKey = "Hết thời gian chờ phản hồi"
            self.hintKey = "Thử lại bằng nút Làm mới."
            self.symbolName = "clock.badge.exclamationmark"
        case .cancelled:
            self.titleKey = "Đã hủy yêu cầu cập nhật"
            self.hintKey = "Chọn Làm mới để tải lại dữ liệu."
            self.symbolName = "stop.circle"
        case .malformedResponse:
            self.titleKey = "Phản hồi dữ liệu không đúng định dạng"
            self.hintKey = "Đã từ chối bản ghi lỗi và giữ dữ liệu hợp lệ gần nhất."
            self.symbolName = "exclamationmark.triangle.fill"
        case .oversizedPayload:
            self.titleKey = "Phản hồi vượt quá giới hạn an toàn"
            self.hintKey = "Đã chặn dữ liệu quá lớn để bảo vệ ứng dụng."
            self.symbolName = "shield.lefthalf.filled"
        case .invalidConfiguration:
            self.titleKey = "Cấu hình nguồn phân tích không hợp lệ"
            self.hintKey = "Kiểm tra khóa df_ hoặc mã thuộc tính GA4."
            self.symbolName = "exclamationmark.shield.fill"
        }
    }
}

public enum WebsiteAnalyticsProviderState: Equatable, Sendable {
    case unconfigured(reason: WebsiteAnalyticsUnconfiguredReason)
    case loadingInitial
    case loaded(WebsiteAnalyticsReport, refreshing: Bool)
    case empty(WebsiteAnalyticsReport, refreshing: Bool)
    case failedWithCache(WebsiteAnalyticsReport, error: WebsiteAnalyticsError)
    case failedNoCache(error: WebsiteAnalyticsError)

    public var report: WebsiteAnalyticsReport? {
        switch self {
        case .loaded(let report, _), .empty(let report, _), .failedWithCache(let report, _):
            return report
        case .unconfigured, .loadingInitial, .failedNoCache:
            return nil
        }
    }

    public var isRefreshing: Bool {
        switch self {
        case .loadingInitial:
            return true
        case .loaded(_, let refreshing), .empty(_, let refreshing):
            return refreshing
        case .unconfigured, .failedWithCache, .failedNoCache:
            return false
        }
    }

    public var error: WebsiteAnalyticsError? {
        switch self {
        case .failedWithCache(_, let err), .failedNoCache(let err):
            return err
        default:
            return nil
        }
    }

    public var isStale: Bool {
        if case .failedWithCache = self { return true }
        return false
    }
}

// MARK: - Date Window & Formatting Rules (Pure)

public struct WebsiteAnalyticsDateWindow: Equatable, Hashable, Sendable {
    public let startDateKey: String
    public let endDateKey: String
    public let timeZoneIdentifier: String
    public let dayCount: Int

    public init(startDateKey: String, endDateKey: String, timeZoneIdentifier: String, dayCount: Int) {
        self.startDateKey = startDateKey
        self.endDateKey = endDateKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.dayCount = dayCount
    }
}

public enum WebsiteAnalyticsDateRules {
    /// Computes an inclusive `[startDateKey, endDateKey]` window in the provider's configured timezone.
    /// For 7d ending on `2026-11-27`, returns `2026-11-21` ... `2026-11-27` (7 calendar days inclusive).
    public static func dateWindow(
        for range: WebsiteAnalyticsRange,
        now: Date,
        timeZone: TimeZone
    ) -> WebsiteAnalyticsDateWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let endDayStart = calendar.startOfDay(for: now)
        let offsetDays = -(range.dayCount - 1)
        let startDayStart = calendar.date(byAdding: .day, value: offsetDays, to: endDayStart) ?? endDayStart
        let startKey = formatISODate(startDayStart, timeZone: timeZone)
        let endKey = formatISODate(endDayStart, timeZone: timeZone)
        return WebsiteAnalyticsDateWindow(
            startDateKey: startKey,
            endDateKey: endKey,
            timeZoneIdentifier: timeZone.identifier,
            dayCount: range.dayCount
        )
    }

    public static func formatISODate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Normalizes `YYYYMMDD` (GA4) or `YYYY-MM-DD` / ISO-8601 prefix (DataFast) into `YYYY-MM-DD`.
    public static func normalizeDateKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 8, trimmed.allSatisfy(\.isNumber) {
            let y = trimmed.prefix(4)
            let mStart = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let dStart = trimmed.index(trimmed.startIndex, offsetBy: 6)
            let m = trimmed[mStart..<dStart]
            let d = trimmed[dStart...]
            guard isValidMonthDay(month: Int(m), day: Int(d)) else { return nil }
            return "\(y)-\(m)-\(d)"
        }
        if trimmed.count >= 10 {
            let prefix = String(trimmed.prefix(10))
            let parts = prefix.split(separator: "-")
            if parts.count == 3,
               parts[0].count == 4, parts[0].allSatisfy(\.isNumber),
               parts[1].count == 2, parts[1].allSatisfy(\.isNumber),
               parts[2].count == 2, parts[2].allSatisfy(\.isNumber),
               isValidMonthDay(month: Int(parts[1]), day: Int(parts[2])) {
                return prefix
            }
        }
        return nil
    }

    public static func shortDayLabel(from dateKey: String) -> String {
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3 else { return dateKey }
        return "\(parts[2])/\(parts[1])"
    }

    private static func isValidMonthDay(month: Int?, day: Int?) -> Bool {
        guard let month, let day else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }
}

public enum WebsiteAnalyticsFormatting {
    public static let unavailablePlaceholder = "—"

    public static func formatCount(_ value: Int?) -> String {
        guard let value, value >= 0 else { return unavailablePlaceholder }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 10_000 {
            return String(format: "%.1fK", Double(value) / 1_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.2fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    public static func formatBounceRate(_ percent: Double?) -> String {
        guard let percent, percent.isFinite, percent >= 0, percent <= 100 else {
            return unavailablePlaceholder
        }
        return String(format: "%.1f%%", percent)
    }

    public static func formatDuration(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else {
            return unavailablePlaceholder
        }
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        if mins == 0 {
            return "\(secs)s"
        }
        return String(format: "%dm %02ds", mins, secs)
    }
}
