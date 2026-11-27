import Foundation

/// Pure Weather Provider interface and error definitions.
/// Allows swapping providers (Open-Meteo, Apple WeatherKit, MockProvider) without altering UI or state rules.

public enum WeatherError: Error, Equatable, Sendable {
    case networkUnavailable
    case rateLimited               // HTTP 429
    case timeout
    case invalidData
    case locationDenied
    case locationUnavailable
    case serverError(statusCode: Int)
    case cancelled
    case unknown(String)

    public var isRetryable: Bool {
        switch self {
        case .networkUnavailable, .rateLimited, .timeout, .serverError:
            return true
        case .invalidData, .locationDenied, .locationUnavailable, .cancelled, .unknown:
            return false
        }
    }
}

/// What the Weather page shows when a fetch fails.
///
/// `WeatherError` is a transport value: it carries no user text, and `localizedDescription` is the
/// runtime's own sentence — "The operation couldn’t be completed. (XFinder.WeatherError error 2.)" —
/// which names the module, prints an error number and tells the person nothing they can act on. So the
/// page never prints it. This type is the single place an error becomes words, grouped the way a person
/// thinks about the failure (network, timeout, quota, data, permission). The `.unknown(String)` payload and
/// `.serverError(statusCode:)` number are deliberately dropped: a URL, an HTTP status or a provider name
/// is backend detail the page cannot act on, and `unknown` may carry exactly that text.
public struct WeatherErrorPresentation: Equatable, Sendable {
    /// Where the failure is shown. The grouping is the same everywhere; only the next step differs,
    /// because "try the Refresh button" is useless advice under a search field.
    public enum Context: Sendable {
        /// The forecast body of the page.
        case forecast
        /// The city search field and its results.
        case search
    }

    /// L10n key for the headline (a Vietnamese source literal, the store's key form).
    public let titleKey: String
    /// L10n key for the one-line next step, or `nil` when the headline says everything.
    public let hintKey: String?
    /// SF Symbol drawn beside the headline.
    public let symbol: String
    /// Whether repeating the same request can plausibly help. Mirrors `WeatherError.isRetryable`.
    public let canRetry: Bool

    public init(for error: WeatherError, context: Context = .forecast) {
        let titleKey: String
        let hintKey: String?
        let symbol: String
        switch error {
        case .networkUnavailable:
            titleKey = "Mất kết nối mạng"
            hintKey = "Kiểm tra Wi-Fi hoặc mạng rồi thử lại."
            symbol = "wifi.slash"
        case .timeout:
            titleKey = "Hết thời gian chờ"
            hintKey = "Kết nối quá lâu nên đã dừng."
            symbol = "clock.badge.exclamationmark"
        case .rateLimited:
            titleKey = "Tạm hết lượt tải thời tiết"
            hintKey = "Thử lại sau ít phút."
            symbol = "hourglass"
        case .serverError:
            // The status code stays in `WeatherError`: it helps a log, not the person reading the panel.
            titleKey = "Dịch vụ thời tiết đang lỗi"
            hintKey = "Thử lại sau ít phút."
            symbol = "antenna.radiowaves.left.and.right.slash"
        case .invalidData:
            titleKey = "Dữ liệu thời tiết không đọc được"
            hintKey = "Thử lại bằng nút Làm mới."
            symbol = "exclamationmark.triangle.fill"
        case .locationDenied, .locationUnavailable:
            titleKey = "Định vị bị từ chối hoặc không khả dụng"
            hintKey = "Chọn thành phố để xem thời tiết."
            symbol = "location.slash.fill"
        case .cancelled:
            titleKey = "Đã dừng tải thời tiết"
            hintKey = nil
            symbol = "xmark.circle.fill"
        case .unknown(_):
            // Any payload here is a transport sentence (often a URL or an OS error), never shown.
            titleKey = "Không tải được thời tiết"
            hintKey = "Thử lại bằng nút Làm mới."
            symbol = "exclamationmark.triangle.fill"
        }

        self.titleKey = titleKey
        // Two hints name a control that only exists in the forecast body ("the Refresh button"), and one
        // ("choose a city") answers a permission failure that cannot occur under a search field. In the
        // search context they would send the person looking for something that is not on screen, so the
        // headline stands alone there instead.
        switch context {
        case .forecast:
            self.hintKey = hintKey
        case .search:
            switch error {
            case .invalidData, .unknown, .locationDenied, .locationUnavailable:
                self.hintKey = nil
            default:
                self.hintKey = hintKey
            }
        }
        self.symbol = symbol
        canRetry = error.isRetryable
    }
}

public protocol WeatherProvider: Sendable {
    var id: String { get }
    var attribution: WeatherAttribution { get }
    func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot
    func searchLocations(query: String) async throws -> [WeatherLocation]
}

/// In-memory mock provider for testing pure behavior without network requests.
public actor MockWeatherProvider: WeatherProvider {
    public let id: String
    public let attribution: WeatherAttribution

    private var stubbedSnapshots: [String: WeatherSnapshot] = [:]
    private var stubbedLocations: [WeatherLocation] = []
    private var errorToThrow: WeatherError?
    private var delaySeconds: TimeInterval = 0
    private var fetchCounts: [String: Int] = [:]
    private var searchQueries: [String] = []

    public init(
        id: String = "mock-provider",
        attribution: WeatherAttribution = WeatherAttribution(
            providerId: "mock-provider",
            serviceName: "Mock Weather",
            legalURL: URL(string: "https://example.com/legal"),
            markSymbol: "cloud.sun.fill"
        ),
        stubbedSnapshots: [String: WeatherSnapshot] = [:],
        stubbedLocations: [WeatherLocation] = [],
        errorToThrow: WeatherError? = nil,
        delaySeconds: TimeInterval = 0
    ) {
        self.id = id
        self.attribution = attribution
        self.stubbedSnapshots = stubbedSnapshots
        self.stubbedLocations = stubbedLocations
        self.errorToThrow = errorToThrow
        self.delaySeconds = delaySeconds
    }

    public func setSnapshot(_ snapshot: WeatherSnapshot, for locationId: String) {
        stubbedSnapshots[locationId] = snapshot
    }

    public func setLocations(_ locations: [WeatherLocation]) {
        stubbedLocations = locations
    }

    public func setError(_ error: WeatherError?) {
        errorToThrow = error
    }

    public func setDelay(_ delay: TimeInterval) {
        delaySeconds = delay
    }

    public func fetchCount(for locationId: String) -> Int {
        fetchCounts[locationId] ?? 0
    }

    public var totalFetchCount: Int {
        fetchCounts.values.reduce(0, +)
    }

    public var recordedSearches: [String] {
        searchQueries
    }

    public func fetchForecast(for location: WeatherLocation) async throws -> WeatherSnapshot {
        fetchCounts[location.id, default: 0] += 1
        let delay = delaySeconds
        let err = errorToThrow
        let snapshot = stubbedSnapshots[location.id]

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if Task.isCancelled {
            throw WeatherError.cancelled
        }

        if let err = err {
            throw err
        }

        guard let snapshot = snapshot else {
            throw WeatherError.invalidData
        }

        return snapshot
    }

    public func searchLocations(query: String) async throws -> [WeatherLocation] {
        searchQueries.append(query)
        let delay = delaySeconds
        let err = errorToThrow
        let results = stubbedLocations.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.region.localizedCaseInsensitiveContains(query) ||
            $0.country.localizedCaseInsensitiveContains(query)
        }

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if Task.isCancelled {
            throw WeatherError.cancelled
        }

        if let err = err {
            throw err
        }

        return results
    }
}
